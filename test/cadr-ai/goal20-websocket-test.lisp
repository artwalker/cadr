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

(defun goal20-unmasked-frame-bytes (payload)
  (let ((output
          (flexi-streams:make-in-memory-output-stream
           :element-type '(unsigned-byte 8))))
    (cadr-ai::write-websocket-frame
     output 1 payload :mask-p nil :fin-p t)
    (flexi-streams:get-output-stream-sequence output)))

(defun goal20-extended-length-bytes (length marker)
  (let ((output
          (flexi-streams:make-in-memory-output-stream
           :element-type '(unsigned-byte 8))))
    (cadr-ai::write-websocket-length output length marker)
    (flexi-streams:get-output-stream-sequence output)))

(test goal20-websocket-frame-uses-the-length-helper
  ;; sb-cover A-class: write-websocket-length had no call site.
  ;; The helper is not a drop-in for the first length byte: that byte
  ;; carries the mask bit, and (= marker 126) would then pick 8 bytes
  ;; for a masked 16-bit frame.
  (let ((source
          (uiop:read-file-string
           (merge-pathnames
            "src/cadr-ai/websocket.lisp"
            (asdf:system-source-directory "cadr-ai")))))
    (is
     (search
      "(write-websocket-length stream length 126)"
      source))
    (is
     (search
      "(write-websocket-length stream length 127)"
      source)))
  (is (not (= (logior 126 #x80) 126)))
  (is
   (equalp
    #(0 126)
    (goal20-extended-length-bytes 126 126)))
  (is
   (equalp
    #(0 0 0 0 0 1 0 0)
    (goal20-extended-length-bytes 65536 127))))

(test goal20-websocket-unmasked-length-prefix-matches-rfc6455
  (let ((short
          (goal20-unmasked-frame-bytes
           (make-array 125 :element-type '(unsigned-byte 8)
                       :initial-element 1)))
        (mid
          (goal20-unmasked-frame-bytes
           (make-array 126 :element-type '(unsigned-byte 8)
                       :initial-element 1)))
        (u16
          (goal20-unmasked-frame-bytes
           (make-array 65535 :element-type '(unsigned-byte 8)
                       :initial-element 1)))
        (u64
          (goal20-unmasked-frame-bytes
           (make-array 65536 :element-type '(unsigned-byte 8)
                       :initial-element 1))))
    (is (= 125 (aref short 1)))
    (is (= 126 (aref mid 1)))
    (is (equalp #(0 126) (subseq mid 2 4)))
    (is (= 126 (aref u16 1)))
    (is (equalp #(255 255) (subseq u16 2 4)))
    (is (= 127 (aref u64 1)))
    (is (equalp #(0 0 0 0 0 1 0 0) (subseq u64 2 10)))))

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
