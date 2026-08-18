(in-package #:cadr-ai)

(defstruct sse-event
  (event nil :type (or null string))
  (data "" :type string)
  (id nil :type (or null string)))

(defun binary-stream-p (stream)
  (multiple-value-bind (yes certain-p)
      (subtypep (stream-element-type stream) '(unsigned-byte 8))
    (and certain-p yes)))

(defun decode-sse-line (buffer binary-p)
  (handler-case
      (if binary-p
          (utf8-string
           (coerce buffer
                   '(simple-array
                     (unsigned-byte 8) (*))))
          (coerce (copy-seq buffer) 'string))
    (error (cause)
      (error 'sse-protocol-error
             :message (format nil "Invalid UTF-8 in SSE stream: ~A" cause)
             :cause cause))))

(defun sse-field-value (line start)
  (let ((len (length line)))
    (cond
      ((>= start len) "")
      ((char= #\Space (char line start))
       (if (>= (1+ start) len)
           ""
           (subseq line (1+ start))))
      (t (subseq line start)))))

(defun split-sse-field (line)
  ;; Common "data: …" / "event:" / "id:" paths keep the field name
  ;; literal and take one payload SUBSEQ.  Unknown fields keep the
  ;; WHATWG first-colon split.
  (let ((len (length line)))
    (cond
      ((and (>= len 5)
            (char= #\d (char line 0))
            (char= #\a (char line 1))
            (char= #\t (char line 2))
            (char= #\a (char line 3))
            (char= #\: (char line 4)))
       (values "data" (sse-field-value line 5)))
      ((and (>= len 6)
            (char= #\e (char line 0))
            (char= #\v (char line 1))
            (char= #\e (char line 2))
            (char= #\n (char line 3))
            (char= #\t (char line 4))
            (char= #\: (char line 5)))
       (values "event" (sse-field-value line 6)))
      ((and (>= len 3)
            (char= #\i (char line 0))
            (char= #\d (char line 1))
            (char= #\: (char line 2)))
       (values "id" (sse-field-value line 3)))
      (t
       (let ((colon (position #\: line)))
         (if colon
             (values (subseq line 0 colon)
                     (sse-field-value line (1+ colon)))
             (values line "")))))))

(defun join-sse-data-lines (lines)
  ;; Fixture events are one data line (394/394).  FORMAT always copied
  ;; that string; the single-line path returns it.  Multi-line stays
  ;; newline-joined (WHATWG / sse-framing-handles-comments-crlf-*).
  (cond
    ((null lines) "")
    ((null (rest lines)) (first lines))
    (t
     (with-output-to-string (out)
       (loop for (line . more) on (nreverse lines)
             do (write-string line out)
                (when more (write-char #\Newline out)))))))

(defun read-sse-stream (stream consumer)
  ;; Binary data/event/id lines decode only the payload octets.
  ;; Whole-line COERCE + UTF8 + SUBSEQ was the leftover after
  ;; f7d1d3dc7 (1.66 MB SSE-only).  octets-to-string on the
  ;; adjustable line buffer without a specialized copy was the
  ;; slower 6.2–7.2 ms draft — not repeated.  File-stream
  ;; READ-SEQUENCE and socket READ-BYTE stay as in c183539e7.
  (let* ((binary-p (binary-stream-p stream))
         (buffer (make-array 128
                             :element-type (if binary-p
                                               '(unsigned-byte 8)
                                               'character)
                             :adjustable t
                             :fill-pointer 0))
         (decode-scratch
           (and binary-p
                (make-array 256 :element-type '(unsigned-byte 8))))
         (event-name nil)
         (data-lines nil)
         (event-id nil)
         (saw-field-p nil))
    (labels ((clear-buffer ()
               (setf (fill-pointer buffer) 0))
             (flush-event ()
               (when (or saw-field-p event-name data-lines event-id)
                 (funcall consumer
                          (make-sse-event
                           :event event-name
                           :data (join-sse-data-lines data-lines)
                           :id event-id)))
               (setf event-name nil
                     data-lines nil
                     event-id nil
                     saw-field-p nil))
             (utf8-payload (start end)
               (handler-case
                   (let ((count (- end start)))
                     (declare (type fixnum start end count))
                     (cond
                       ((zerop count) "")
                       (t
                        (when (> count (length decode-scratch))
                          (setf decode-scratch
                                (make-array count
                                            :element-type
                                            '(unsigned-byte 8))))
                        (replace decode-scratch buffer
                                 :start2 start :end2 end)
                        (sb-ext:octets-to-string
                         decode-scratch
                         :external-format :utf-8
                         :start 0
                         :end count))))
                 (error (cause)
                   (error 'sse-protocol-error
                          :message
                          (format nil
                                  "Invalid UTF-8 in SSE stream: ~A"
                                  cause)
                          :cause cause))))
             (process-character-line ()
               (let ((line (decode-sse-line buffer nil)))
                 (clear-buffer)
                 (when (and (plusp (length line))
                            (char= #\Return
                                   (char line (1- (length line)))))
                   (setf line (subseq line 0 (1- (length line)))))
                 (cond
                   ((zerop (length line))
                    (flush-event))
                   ((char= #\: (char line 0))
                    nil)
                   (t
                    (multiple-value-bind (field value)
                        (split-sse-field line)
                      (cond
                        ((string= field "event")
                         (setf event-name value
                               saw-field-p t))
                        ((string= field "data")
                         (push value data-lines)
                         (setf saw-field-p t))
                        ((string= field "id")
                         (setf event-id value
                               saw-field-p t))))))))
             (process-binary-line ()
               (let ((end (fill-pointer buffer)))
                 (declare (type fixnum end)
                          (type (vector (unsigned-byte 8)) buffer))
                 (when (and (plusp end)
                            (= (aref buffer (1- end)) 13))
                   (decf end))
                 (cond
                   ((zerop end)
                    (clear-buffer)
                    (flush-event))
                   ((= (aref buffer 0) 58)
                    (clear-buffer))
                   ((and (>= end 5)
                         (= (aref buffer 0) 100)
                         (= (aref buffer 1) 97)
                         (= (aref buffer 2) 116)
                         (= (aref buffer 3) 97)
                         (= (aref buffer 4) 58))
                    (let ((start 5))
                      (declare (type fixnum start))
                      (when (and (< start end)
                                 (= (aref buffer start) 32))
                        (incf start))
                      (push (utf8-payload start end) data-lines)
                      (setf saw-field-p t)
                      (clear-buffer)))
                   ((and (>= end 6)
                         (= (aref buffer 0) 101)
                         (= (aref buffer 1) 118)
                         (= (aref buffer 2) 101)
                         (= (aref buffer 3) 110)
                         (= (aref buffer 4) 116)
                         (= (aref buffer 5) 58))
                    (let ((start 6))
                      (declare (type fixnum start))
                      (when (and (< start end)
                                 (= (aref buffer start) 32))
                        (incf start))
                      (setf event-name (utf8-payload start end)
                            saw-field-p t)
                      (clear-buffer)))
                   ((and (>= end 3)
                         (= (aref buffer 0) 105)
                         (= (aref buffer 1) 100)
                         (= (aref buffer 2) 58))
                    (let ((start 3))
                      (declare (type fixnum start))
                      (when (and (< start end)
                                 (= (aref buffer start) 32))
                        (incf start))
                      (setf event-id (utf8-payload start end)
                            saw-field-p t)
                      (clear-buffer)))
                   (t
                    (setf (fill-pointer buffer) end)
                    (let ((line (decode-sse-line buffer t)))
                      (clear-buffer)
                      (multiple-value-bind (field value)
                          (split-sse-field line)
                        (cond
                          ((string= field "event")
                           (setf event-name value
                                 saw-field-p t))
                          ((string= field "data")
                           (push value data-lines)
                           (setf saw-field-p t))
                          ((string= field "id")
                           (setf event-id value
                                 saw-field-p t)))))))))
             (process-line ()
               (if binary-p
                   (process-binary-line)
                   (process-character-line)))
             (consume-binary-unit (unit)
               (if (= unit 10)
                   (process-line)
                   (vector-push-extend unit buffer))))
      (cond
        ((and binary-p (typep stream 'file-stream))
         (let ((chunk (make-array 8192 :element-type '(unsigned-byte 8))))
           (declare (type (simple-array (unsigned-byte 8) (*)) chunk))
           (loop
             (let ((count (read-sequence chunk stream)))
               (declare (type fixnum count))
               (when (zerop count)
                 (return))
               (loop for index of-type fixnum from 0 below count
                     do (consume-binary-unit
                         (aref chunk index)))))))
        (binary-p
         (loop for unit = (read-byte stream nil :eof)
               until (eq unit :eof)
               do (consume-binary-unit unit)))
        (t
         (loop for unit = (read-char stream nil :eof)
               until (eq unit :eof)
               do (if (char= unit #\Newline)
                      (process-line)
                      (vector-push-extend unit buffer)))))
      (when (plusp (length buffer))
        (process-line))
      (flush-event)))
  nil)
