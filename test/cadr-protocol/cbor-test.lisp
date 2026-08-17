(in-package #:cadr-protocol/tests)
(in-suite cadr-protocol-suite)

(defun from-hex (hex)
  (unless (evenp (length hex))
    (error "Hex fixture must contain whole bytes"))
  (let ((bytes (make-array (/ (length hex) 2)
                           :element-type '(unsigned-byte 8))))
    (loop for index below (length bytes)
          do (setf (aref bytes index)
                   (parse-integer hex
                                  :start (* index 2)
                                  :end (+ (* index 2) 2)
                                  :radix 16)))
    bytes))

(defun to-hex (bytes)
  (string-downcase
   (with-output-to-string (stream)
     (loop for byte across bytes
           do (format stream "~2,'0x" byte)))))

(defun quiet-double-nan ()
  (sb-kernel:make-double-float #x7ff80000 0))

(defun cbor-known-vectors ()
  (list
   (list 'null "f6")
   (list nil "f4")
   (list t "f5")
   (list 0 "00")
   (list 1 "01")
   (list 10 "0a")
   (list 23 "17")
   (list 24 "1818")
   (list 25 "1819")
   (list 100 "1864")
   (list 1000 "1903e8")
   (list 1000000 "1a000f4240")
   (list 1000000000000 "1b000000e8d4a51000")
   (list cadr-protocol:+maximum-safe-integer+
         "1b001fffffffffffff")
   (list -1 "20")
   (list -10 "29")
   (list -24 "37")
   (list -25 "3818")
   (list -100 "3863")
   (list -1000 "3903e7")
   (list -1000000 "3a000f423f")
   (list (- cadr-protocol:+maximum-safe-integer+)
         "3b001ffffffffffffe")
   (list 1.1d0 "fb3ff199999999999a")
   (list -0.0d0 "fb8000000000000000")
   (list (cadr-protocol:make-byte-string (octets 1 2 3 4))
         "4401020304")
   (list "" "60")
   (list "IETF" "6449455446")
   (list "ü" "62c3bc")
   (list "水" "63e6b0b4")
   (list (string (code-char #x10151)) "64f0908591")
   (list #() "80")
   (list #(1 2 3) "83010203")
   (list #(1 #(2 3) #(4 5)) "8301820203820405")
   (list (protocol-object "a" 1 "b" #(2 3))
         "a26161016162820203")))

(test cbor-encodes-and-decodes-rfc8949-vectors
  (dolist (fixture (cbor-known-vectors))
    (destructuring-bind (value wire) fixture
      (is (string= wire
                   (to-hex (cadr-protocol:encode-cbor value))))
      (is (protocol-value=
           value
           (cadr-protocol:decode-cbor (from-hex wire)))))))

(test cbor-map-preserves-falsey-values
  (let* ((value (protocol-object
                 "zero" 0
                 "empty" ""
                 "no" nil
                 "nil" 'null))
         (decoded
           (cadr-protocol:decode-cbor
            (cadr-protocol:encode-cbor value))))
    (is (protocol-value= value decoded))
    (is (= 4 (hash-table-count decoded)))))

(test cbor-preserves-bom-and-proto-data-key
  (is (string= (string (code-char #xfeff))
               (cadr-protocol:decode-cbor
                (from-hex "63efbbbf"))))
  (let* ((value (protocol-object "__proto__" "safe"))
         (decoded
           (cadr-protocol:decode-cbor
            (cadr-protocol:encode-cbor value))))
    (is (string= "safe" (object-get decoded "__proto__")))
    (is (= 1 (hash-table-count decoded)))))

(test cbor-rejects-unsupported-encoder-values
  (dolist (value
           (list (1+ cadr-protocol:+maximum-safe-integer+)
                 (1- (- cadr-protocol:+maximum-safe-integer+))
                 sb-ext:double-float-positive-infinity
                 (- sb-ext:double-float-positive-infinity)
                 (quiet-double-nan)
                 #C(1 2)
                 'unsupported
                 '(1 2)
                 #'identity
                 (make-pathname :name "unsupported")))
    (signals cadr-protocol:cbor-error
      (cadr-protocol:encode-cbor value))))

(test cbor-rejects-non-string-map-keys
  (dolist (key (list :symbol-key 1))
    (signals cadr-protocol:cbor-error
      (cadr-protocol:encode-cbor
       (let ((object (make-hash-table :test #'equal)))
         (setf (gethash key object) t)
         object)))))

(test cbor-rejects-lossy-strings-cycles-and-depth
  (signals-message cadr-protocol:cbor-error "Unicode"
    (cadr-protocol:encode-cbor
     (string (code-char #xd800))))
  (let ((cyclic (make-array 1)))
    (setf (aref cyclic 0) cyclic)
    (signals-message cadr-protocol:cbor-error "cycles"
      (cadr-protocol:encode-cbor cyclic)))
  (let ((too-deep 'null))
    (loop repeat (1+ cadr-protocol:+default-max-cbor-depth+)
          do (setf too-deep (vector too-deep)))
    (signals-message cadr-protocol:cbor-error "depth"
      (cadr-protocol:encode-cbor too-deep))))

(test cbor-rejects-invalid-decoder-input
  (dolist (fixture
           '(;; label, wire
             ("empty input" "")
             ("truncated integer" "18")
             ("reserved additional information" "1c")
             ("indefinite byte string" "5f")
             ("indefinite text string" "7f")
             ("indefinite array" "9f")
             ("indefinite map" "bf")
             ("tag" "c000")
             ("undefined" "f7")
             ("unsupported simple value" "e0")
             ("break outside an indefinite item" "ff")
             ("float16" "f93c00")
             ("float32" "fa3f800000")
             ("positive infinity" "fb7ff0000000000000")
             ("NaN" "fb7ff8000000000000")
             ("truncated float64" "fb3ff00000")
             ("truncated byte string" "44010203")
             ("truncated text string" "636162")
             ("truncated array" "8201")
             ("truncated map" "a16161")
             ("trailing data" "0000")
             ("non-string map key" "a10102")
             ("duplicate map key" "a2616101616102")
             ("invalid UTF-8 byte" "61ff")
             ("overlong UTF-8" "62c080")
             ("UTF-8 surrogate" "63eda080")
             ("unsafe positive integer" "1b0020000000000000")
             ("unsafe negative integer" "3b001fffffffffffff")
             ("unsafe integer encoded as float64"
              "fb4340000000000000")))
    (signals cadr-protocol:cbor-error
      (cadr-protocol:decode-cbor
       (from-hex (second fixture))))))

(defun declared-length-wire (initial length)
  (octets initial
          (ldb (byte 8 24) length)
          (ldb (byte 8 16) length)
          (ldb (byte 8 8) length)
          (ldb (byte 8 0) length)))

(test cbor-enforces-depth-and-declared-length-limits
  (let ((too-deep
          (make-array
           (+ cadr-protocol:+default-max-cbor-depth+ 2)
           :element-type '(unsigned-byte 8)
           :initial-element #x81)))
    (setf (aref too-deep (1- (length too-deep))) #xf6)
    (signals-message cadr-protocol:cbor-error "depth"
      (cadr-protocol:decode-cbor too-deep)))
  (dolist (wire
           (list
            (declared-length-wire
             #x5a
             (1+ cadr-protocol:+default-max-cbor-byte-length+))
            (declared-length-wire
             #x7a
             (1+ cadr-protocol:+default-max-cbor-byte-length+))
            (declared-length-wire
             #x9a
             (1+ cadr-protocol:+default-max-cbor-container-length+))
            (declared-length-wire
             #xba
             (1+ cadr-protocol:+default-max-cbor-container-length+))))
    (signals-message cadr-protocol:cbor-error "limit"
      (cadr-protocol:decode-cbor wire))))

(test cbor-supports-stricter-caller-limits
  (signals-message cadr-protocol:cbor-error "limit"
    (cadr-protocol:decode-cbor
     (from-hex "83010203") :max-container-length 2))
  (signals-message cadr-protocol:cbor-error "limit"
    (cadr-protocol:decode-cbor
     (from-hex "626162") :max-byte-length 2))
  (signals-message cadr-protocol:cbor-error "limit"
    (cadr-protocol:encode-cbor
     #(1 2 3) :max-container-length 2))
  (signals-message cadr-protocol:cbor-error "limit"
    (cadr-protocol:encode-cbor "ab" :max-byte-length 2)))

(test encode-cbor-writer-owns-the-three-limits
  ;; Red on the old positional-limit encode-cbor-value.
  (is (fboundp 'cadr-protocol::cbor-writer-max-byte-length))
  (is (fboundp 'cadr-protocol::cbor-writer-max-container-length))
  (is (fboundp 'cadr-protocol::cbor-writer-max-depth)))
