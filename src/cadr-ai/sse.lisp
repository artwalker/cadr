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
             (utf8-payload (vector start end)
               ;; ASCII-run utf8-string, same decoder as tool_read /
               ;; session JSONL. Whole-line octets-to-string was
               ;; UTF8->STRING-AREF 25.6% of mistral stream_roundtrip
               ;; at 3374ac197. Not intern. Not FFI.
               (handler-case
                   (utf8-string vector start end)
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
             (process-binary-octets (vector start end)
               (declare (type (array (unsigned-byte 8) (*)) vector)
                        (type fixnum start end))
               (when (and (> end start)
                          (= (aref vector (1- end)) 13))
                 (decf end))
               (let ((len (- end start)))
                 (declare (type fixnum len))
                 (cond
                   ((zerop len)
                    (flush-event))
                   ((= (aref vector start) 58)
                    nil)
                   ((and (>= len 5)
                         (= (aref vector start) 100)
                         (= (aref vector (+ start 1)) 97)
                         (= (aref vector (+ start 2)) 116)
                         (= (aref vector (+ start 3)) 97)
                         (= (aref vector (+ start 4)) 58))
                    (let ((payload (+ start 5)))
                      (declare (type fixnum payload))
                      (when (and (< payload end)
                                 (= (aref vector payload) 32))
                        (incf payload))
                      (push (utf8-payload vector payload end)
                            data-lines)
                      (setf saw-field-p t)))
                   ((and (>= len 6)
                         (= (aref vector start) 101)
                         (= (aref vector (+ start 1)) 118)
                         (= (aref vector (+ start 2)) 101)
                         (= (aref vector (+ start 3)) 110)
                         (= (aref vector (+ start 4)) 116)
                         (= (aref vector (+ start 5)) 58))
                    (let ((payload (+ start 6)))
                      (declare (type fixnum payload))
                      (when (and (< payload end)
                                 (= (aref vector payload) 32))
                        (incf payload))
                      (setf event-name (utf8-payload vector payload end)
                            saw-field-p t)))
                   ((and (>= len 3)
                         (= (aref vector start) 105)
                         (= (aref vector (+ start 1)) 100)
                         (= (aref vector (+ start 2)) 58))
                    (let ((payload (+ start 3)))
                      (declare (type fixnum payload))
                      (when (and (< payload end)
                                 (= (aref vector payload) 32))
                        (incf payload))
                      (setf event-id (utf8-payload vector payload end)
                            saw-field-p t)))
                   (t
                    (let ((line (utf8-payload vector start end)))
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
             (process-binary-line ()
               (process-binary-octets buffer 0 (fill-pointer buffer))
               (clear-buffer))
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
               (let ((start 0))
                 (declare (type fixnum start))
                 (loop for index of-type fixnum from 0 below count
                       do (when (= (aref chunk index) 10)
                            (if (zerop (fill-pointer buffer))
                                (process-binary-octets chunk start index)
                                (progn
                                  (loop for copy of-type fixnum
                                        from start below index
                                        do (vector-push-extend
                                            (aref chunk copy) buffer))
                                  (process-binary-line)))
                            (setf start (1+ index))))
                 (loop for copy of-type fixnum from start below count
                       do (vector-push-extend
                           (aref chunk copy) buffer)))))))
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
