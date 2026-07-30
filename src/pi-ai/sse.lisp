(in-package #:pi-ai)

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

(defun split-sse-field (line)
  (let ((colon (position #\: line)))
    (if colon
        (values (subseq line 0 colon)
                (let ((value (subseq line (1+ colon))))
                  (if (and (plusp (length value))
                           (char= #\Space (char value 0)))
                      (subseq value 1)
                      value)))
        (values line ""))))

(defun read-sse-stream (stream consumer)
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
                           :data (format nil "~{~A~^~%~}"
                                         (nreverse data-lines))
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
             (read-unit ()
               (if binary-p
                   (read-byte stream nil :eof)
                   (read-char stream nil :eof))))
      (loop for unit = (read-unit)
            until (eq unit :eof)
            do (if (if binary-p
                       (= unit 10)
                       (char= unit #\Newline))
                   (process-line)
                   (vector-push-extend unit buffer)))
      (when (plusp (length buffer))
        (process-line))
      (flush-event)))
  nil)
