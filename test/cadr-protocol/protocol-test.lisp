(in-package #:cadr-protocol/tests)
(in-suite cadr-protocol-suite)

(defun octets (&rest values)
  (make-array (length values)
              :element-type '(unsigned-byte 8)
              :initial-contents values))

(defun bytes= (left right)
  (equalp left right))

(defun protocol-object (&rest entries)
  (let ((object (make-hash-table :test #'equal)))
    (loop for (key value) on entries by #'cddr
          do (setf (gethash key object) value))
    object))

(defun object-get (object key)
  (gethash key object))

(test cbor-rfc8949-strict-subset
  (dolist (fixture
           (list
            (list 'null (octets #xf6))
            (list nil (octets #xf4))
            (list t (octets #xf5))
            (list 0 (octets #x00))
            (list 24 (octets #x18 #x18))
            (list 1000 (octets #x19 #x03 #xe8))
            (list 1000000000000
                  (octets #x1b #x00 #x00 #x00 #xe8
                          #xd4 #xa5 #x10 #x00))
            (list -1000 (octets #x39 #x03 #xe7))
            (list -0.0d0
                  (octets #xfb #x80 #x00 #x00 #x00
                          #x00 #x00 #x00 #x00))
            (list "水" (octets #x63 #xe6 #xb0 #xb4))
            (list #(1 2 3) (octets #x83 #x01 #x02 #x03))))
    (destructuring-bind (value wire) fixture
      (is (bytes= wire (cadr-protocol:encode-cbor value)))
      (let ((decoded (cadr-protocol:decode-cbor wire)))
        (if (and (floatp value) (zerop value))
            (is (minusp (float-sign decoded)))
            (is (equalp value decoded)))))))

(test cbor-byte-string-map-and-limits
  (let* ((bytes (octets 1 2 3 4))
         (object (protocol-object
                  "bytes" (cadr-protocol:make-byte-string bytes)
                  "zero" 0
                  "empty" ""
                  "false" nil
                  "null" 'null))
         (decoded
           (cadr-protocol:decode-cbor
            (cadr-protocol:encode-cbor object))))
    (is (bytes=
         bytes
         (cadr-protocol:byte-string-octets
          (object-get decoded "bytes"))))
    (is (= 0 (object-get decoded "zero")))
    (is (string= "" (object-get decoded "empty")))
    (is (null (object-get decoded "false")))
    (is (eq 'null (object-get decoded "null"))))
  (signals cadr-protocol:cbor-error
    (cadr-protocol:encode-cbor
     (make-array 3 :initial-contents '(1 2 3))
     :max-container-length 2))
  (signals cadr-protocol:cbor-error
    (cadr-protocol:decode-cbor
     (octets #x83 #x01 #x02 #x03)
     :max-container-length 2))
  (signals cadr-protocol:cbor-error
    (cadr-protocol:encode-cbor "ab" :max-byte-length 2))
  (signals cadr-protocol:cbor-error
    (cadr-protocol:decode-cbor
     (octets #x62 #x61 #x62)
     :max-byte-length 2)))

(test cbor-rejects-invalid-values-and-wire
  (dolist (value (list most-positive-fixnum
                       most-negative-fixnum
                       #C(1 2)
                       #'identity))
    (when (or (not (integerp value))
              (> (abs value) cadr-protocol:+maximum-safe-integer+))
      (signals cadr-protocol:cbor-error
        (cadr-protocol:encode-cbor value))))
  (let ((cyclic (make-array 1)))
    (setf (aref cyclic 0) cyclic)
    (signals cadr-protocol:cbor-error
      (cadr-protocol:encode-cbor cyclic)))
  (dolist (wire
           (list
            (octets)
            (octets #x18)
            (octets #x5f)
            (octets #x7f)
            (octets #x9f)
            (octets #xbf)
            (octets #xc0 #x00)
            (octets #xf7)
            (octets #xf9 #x3c #x00)
            (octets #xfa #x3f #x80 #x00 #x00)
            (octets #xff)
            (octets #x00 #x00)
            (octets #xa1 #x01 #x02)
            (octets #xa2 #x61 #x61 #x01 #x61 #x61 #x02)
            (octets #x61 #xff)
            (octets #x1b #x00 #x20 #x00 #x00 #x00 #x00 #x00 #x00)))
    (signals cadr-protocol:cbor-error
      (cadr-protocol:decode-cbor wire))))

(test frame-codec-fragmentation-and-state
  (let* ((a (cadr-protocol:encode-frame (octets 1 2 3)))
         (b (cadr-protocol:encode-frame (octets)))
         (wire (concatenate '(vector (unsigned-byte 8)) a b))
         (decoder (cadr-protocol:make-frame-decoder))
         (frames nil))
    (loop for byte across wire
          do (setf frames
                   (nconc frames
                          (cadr-protocol:frame-decoder-push
                           decoder (octets byte)))))
    (cadr-protocol:frame-decoder-end decoder)
    (is (= 2 (length frames)))
    (is (bytes= (octets 1 2 3) (first frames)))
    (is (bytes= (octets) (second frames)))
    (signals cadr-protocol:frame-error
      (cadr-protocol:frame-decoder-push decoder (octets))))
  (let ((decoder (cadr-protocol:make-frame-decoder)))
    (cadr-protocol:frame-decoder-push
     decoder (octets 0 0 0 2 1))
    (signals cadr-protocol:frame-error
      (cadr-protocol:frame-decoder-end decoder)))
  (let ((decoder
          (cadr-protocol:make-frame-decoder
           :max-frame-length 3)))
    (signals cadr-protocol:frame-error
      (cadr-protocol:frame-decoder-push
       decoder (octets 0 0 0 4)))
    (signals cadr-protocol:frame-error
      (cadr-protocol:frame-decoder-push decoder (octets 1)))))

(test protocol-v2-strict-validation-and-framed-roundtrip
  (is (= 2 cadr-protocol:+protocol-version+))
  (is (cadr-protocol:supported-protocol-version-p 2))
  (is (not (cadr-protocol:supported-protocol-version-p 1)))
  (let* ((hello
           (protocol-object
            "type" "hello"
            "version" 2
            "token" "secret"))
         (wire (cadr-protocol:encode-client-message hello))
         (messages nil))
    (loop for split from 0 to (length wire)
          do (let ((candidate
                     (cadr-protocol:make-client-message-decoder)))
               (setf messages
                     (append
                      (cadr-protocol:message-decoder-push
                       candidate (subseq wire 0 split))
                      (cadr-protocol:message-decoder-push
                       candidate (subseq wire split))))
               (cadr-protocol:message-decoder-end candidate)
               (is (= 1 (length messages)))
               (is (string=
                    "secret"
                    (object-get (first messages) "token"))))))
  (dolist (invalid
           (list
            (protocol-object
             "type" "hello" "version" "2" "token" "secret")
            (protocol-object
             "type" "hello" "version" 2.5d0 "token" "secret")
            (protocol-object
             "type" "hello" "version" 2 "token" "")
            (protocol-object
             "type" "hello" "version" 2 "token" "secret"
             "extra" t)))
    (signals cadr-protocol:protocol-validation-error
      (cadr-protocol:parse-client-message invalid))))

(test protocol-v2-command-and-server-schema
  (let ((request
          (protocol-object
           "type" "request"
           "id" "request-1"
           "request"
           (protocol-object "command" "create"
                            "cwd" "/tmp/work"
                            "name" "demo"))))
    (is (eq request
            (cadr-protocol:parse-client-message request))))
  (let* ((snapshot
           (protocol-object
            "serverId" "server-1"
            "protocolVersion" 2
            "revision" 0
            "sessions" #()
            "models" #()))
         (hello
           (protocol-object
            "type" "hello"
            "version" 2
            "connectionId" "connection-1"
            "snapshot" snapshot))
         (decoded
           (cadr-protocol:make-server-message-decoder)))
    (is (eq hello (cadr-protocol:parse-server-message hello)))
    (is (= 1
           (length
            (cadr-protocol:message-decoder-push
             decoded
             (cadr-protocol:encode-server-message hello)))))
    (cadr-protocol:message-decoder-end decoded))
  (signals cadr-protocol:protocol-validation-error
    (cadr-protocol:parse-server-message
     (protocol-object
      "type" "hello_error"
      "error"
      (protocol-object "code" "bogus" "message" "bad")))))
