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

(test sse-file-stream-matches-character-stream
  ;; File-stream READ-SEQUENCE scans newlines in the 8192 chunk.
  ;; Character and in-memory binary paths must keep the same events.
  (let* ((text
           (concatenate
            'string
            "data: {\"n\":1}" (string #\Newline)
            (string #\Newline)
            "data: {\"n\":2}" (string #\Return) (string #\Newline)
            (string #\Return) (string #\Newline)
            ": comment" (string #\Newline)
            "event: ping" (string #\Newline)
            "data: tail" (string #\Newline)
            (string #\Newline)))
         (octets (babel:string-to-octets text :encoding :utf-8))
         (from-chars nil)
         (from-file nil))
    (with-input-from-string (stream text)
      (read-sse-stream
       stream
       (lambda (event) (push event from-chars))))
    (uiop:with-temporary-file (:pathname path)
      (with-open-file (out path
                           :direction :output
                           :if-exists :supersede
                           :element-type '(unsigned-byte 8))
        (write-sequence octets out))
      (with-open-file (stream path
                              :direction :input
                              :element-type '(unsigned-byte 8))
        (read-sse-stream
         stream
         (lambda (event) (push event from-file)))))
    (setf from-chars (nreverse from-chars)
          from-file (nreverse from-file))
    (is (= (length from-chars) (length from-file)))
    (mapc
     (lambda (left right)
       (is (equal (sse-event-event left) (sse-event-event right)))
       (is (string= (sse-event-data left) (sse-event-data right)))
       (is (equal (sse-event-id left) (sse-event-id right))))
     from-chars from-file)))

(test pairing-mistral-recorded-sse-utf8-payload-stays-put
  ;; scripts/goal20-paired-paths.lisp provider_mistral.stream_roundtrip.
  ;; Drives shipped read-sse-stream on the recorded fixture. Binary
  ;; data lines go through utf8-string (ASCII run), not a
  ;; reimplementation.
  (let ((events nil))
    (with-open-file
        (stream
         (fixture-path
          "test/fixtures/goal20-paired-paths/mistral-conversations.sse")
         :direction :input
         :element-type '(unsigned-byte 8))
      (read-sse-stream
       stream
       (lambda (event) (push event events))))
    (setf events (nreverse events))
    (is (> (length events) 10))
    (is (string= "[DONE]" (sse-event-data (car (last events)))))
    (let ((object (parse-json (sse-event-data (first events)))))
      (is (string= "chatcmpl-mistral-goal20"
                   (cadr-ai::json-get object "id")))
      (is (vectorp (cadr-ai::json-get object "choices"))))))
