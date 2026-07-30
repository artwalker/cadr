(in-package #:cadr-ai/tests)
(in-suite cadr-ai-suite)

(test sse-framing-handles-comments-crlf-multiline-and-eof
  (let ((events nil)
        (source (concatenate
                 'string
                 ": heartbeat" (string #\Return) (string #\Newline)
                 "event: delta" (string #\Return) (string #\Newline)
                 "id: 7" (string #\Return) (string #\Newline)
                 "data: first" (string #\Return) (string #\Newline)
                 "data: second" (string #\Return) (string #\Newline)
                 (string #\Return) (string #\Newline)
                 "data: tail")))
    (with-input-from-string (stream source)
      (read-sse-stream stream (lambda (event) (push event events))))
    (setf events (nreverse events))
    (is (= 2 (length events)))
    (is (string= "delta" (sse-event-event (first events))))
    (is (string= "7" (sse-event-id (first events))))
    (is (string= (format nil "first~%second")
                 (sse-event-data (first events))))
    (is (string= "tail" (sse-event-data (second events))))))

(test sse-framing-preserves-utf8-split-across-source-reads
  (let* ((source (babel:string-to-octets
                  (format nil "data: {\"text\":\"你好\"}~%~%")
                  :encoding :utf-8))
         (events nil))
    (with-open-stream
        (stream (flexi-streams:make-in-memory-input-stream source))
      (read-sse-stream stream (lambda (event) (push event events))))
    (is (= 1 (length events)))
    (is (string= "{\"text\":\"你好\"}"
                 (sse-event-data (first events))))))

(test sse-framing-rejects-invalid-utf8
  (let ((source (make-array 9
                            :element-type '(unsigned-byte 8)
                            :initial-contents '(100 97 116 97 58 32 195 10 10))))
    (with-open-stream
        (stream (flexi-streams:make-in-memory-input-stream source))
      (signals cadr-ai:sse-protocol-error
        (read-sse-stream stream (lambda (event) (declare (ignore event))))))))
