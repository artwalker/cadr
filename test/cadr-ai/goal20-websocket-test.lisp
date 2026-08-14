(in-package #:cadr-ai/tests)

(in-suite cadr-ai-suite)

(defun goal20-websocket-roundtrip (payload &key (opcode 1) (fin-p t))
  (let ((output
          (flexi-streams:make-in-memory-output-stream
           :element-type '(unsigned-byte 8))))
    (cadr-ai::write-websocket-frame
     output opcode payload :mask-p nil :fin-p fin-p)
    (multiple-value-bind (read-opcode read-payload)
        (cadr-ai::read-websocket-frame
         (flexi-streams:make-in-memory-input-stream
          (flexi-streams:get-output-stream-sequence output)))
      (unless (= read-opcode opcode)
        (error "opcode ~D, expected ~D" read-opcode opcode))
      read-payload)))

(test goal20-websocket-64-bit-length-roundtrips-65536-bytes
  ;; 12A-1: marker=127 used to skip the first of eight length bytes
  ;; (`for value = 0 then read-byte`), so payloads >= 65536 desynced
  ;; the stream. This roundtrip is red on that loop.
  (let* ((payload
           (make-array 65536
                       :element-type '(unsigned-byte 8)
                       :initial-element 7))
         (read (goal20-websocket-roundtrip payload)))
    (is (equalp payload read))))

(test goal20-websocket-assembles-fragmented-text-frames
  ;; 12A-2: FIN was never read, so a FIN=0 frame was treated as a
  ;; complete message. write two frames; one read must concatenate.
  (let ((output
          (flexi-streams:make-in-memory-output-stream
           :element-type '(unsigned-byte 8))))
    (cadr-ai::write-websocket-frame
     output #x1 (babel:string-to-octets "hel" :encoding :utf-8)
     :mask-p nil :fin-p nil)
    (cadr-ai::write-websocket-frame
     output #x0 (babel:string-to-octets "lo" :encoding :utf-8)
     :mask-p nil :fin-p t)
    (multiple-value-bind (opcode payload)
        (cadr-ai::read-websocket-frame
         (flexi-streams:make-in-memory-input-stream
          (flexi-streams:get-output-stream-sequence output)))
      (is (= 1 opcode))
      (is (string= "hello"
                   (babel:octets-to-string payload :encoding :utf-8))))))

(test goal20-websocket-url-handshake-converts-ws-schemes
  ;; 12A-4: the old https/http branches were identity. wss/ws are the
  ;; schemes that need rewriting for the HTTP upgrade.
  (is (string= "https://example/v1"
               (cadr-ai::websocket-url-as-http-url "wss://example/v1")))
  (is (string= "http://example/v1"
               (cadr-ai::websocket-url-as-http-url "ws://example/v1")))
  (is (string= "https://example/v1"
               (cadr-ai::websocket-url-as-http-url "https://example/v1"))))
