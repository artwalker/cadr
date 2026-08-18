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
  ;; stream_roundtrip this host: 5.400 ms / 3.75 MB.  SSE-only is
  ;; 2.33 MB of that.  FILE-STREAM binary bodies use READ-SEQUENCE
  ;; into a specialized octet chunk (not a runtime-typed array —
  ;; that draft was 15 ms).  Socket / gray bodies stay on
  ;; READ-BYTE: SBCL READ-SEQUENCE waits for the whole chunk, which
  ;; deadlocks incremental SSE (NATIVE-HTTP waits to emit event 2
  ;; until event 1 is consumed).  Character streams keep the unit
  ;; loop for FiveAM.
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
             (process-line ()
               (let ((line (decode-sse-line buffer binary-p)))
                 (clear-buffer)
                 (when (and (plusp (length line))
                            (char= #\Return (char line (1- (length line)))))
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
