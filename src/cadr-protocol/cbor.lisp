(in-package #:cadr-protocol)

(defconstant +maximum-safe-integer+ 9007199254740991)
(defconstant +maximum-uint32+ #xffffffff)
(defconstant +default-max-cbor-byte-length+ (* 16 1024 1024))
(defconstant +default-max-cbor-container-length+ 1000000)
(defconstant +default-max-cbor-depth+ 64)
(defconstant +maximum-configured-cbor-depth+ 512)

(define-condition cbor-error (error)
  ((message :initarg :message :reader cbor-error-message))
  (:report
   (lambda (condition stream)
     (write-string (cbor-error-message condition) stream))))

(defstruct (byte-string
            (:constructor %make-byte-string (octets)))
  (octets #() :type (vector (unsigned-byte 8))))

(defun make-byte-string (octets)
  (unless (typep octets '(vector (unsigned-byte 8)))
    (error 'type-error
           :datum octets
           :expected-type '(vector (unsigned-byte 8))))
  (%make-byte-string (copy-seq octets)))

(defun cbor-fail (control &rest arguments)
  (error 'cbor-error
         :message (apply #'format nil control arguments)))

(defun resolve-cbor-limit (name value maximum)
  (unless (and (integerp value)
               (<= 0 value maximum))
    (error 'range-error
           :datum value
           :expected-type `(integer 0 ,maximum)
           :format-control "~A must be an integer between 0 and ~D"
           :format-arguments (list name maximum)))
  value)

(defun resolved-cbor-limits
    (max-byte-length max-container-length max-depth)
  (values
   (resolve-cbor-limit
    "max-byte-length"
    (or max-byte-length +default-max-cbor-byte-length+)
    +maximum-uint32+)
   (resolve-cbor-limit
    "max-container-length"
    (or max-container-length
        +default-max-cbor-container-length+)
    +maximum-uint32+)
   (resolve-cbor-limit
    "max-depth"
    (or max-depth +default-max-cbor-depth+)
    +maximum-configured-cbor-depth+)))

(defun make-octet-writer ()
  (make-array 256
              :element-type '(unsigned-byte 8)
              :adjustable t
              :fill-pointer 0))

(defun writer-ensure (writer count limit)
  (when (> (+ (fill-pointer writer) count) limit)
    (cbor-fail
     "CBOR byte length exceeds configured limit of ~D"
     limit)))

(defun writer-byte (writer value limit)
  (writer-ensure writer 1 limit)
  (vector-push-extend (logand value #xff) writer))

(defun writer-bytes (writer bytes limit)
  (writer-ensure writer (length bytes) limit)
  (loop for byte across bytes
        do (vector-push-extend byte writer)))

(defun writer-uint (writer value width limit)
  (loop for shift downfrom (* 8 (1- width)) to 0 by 8
        do (writer-byte
            writer
            (ldb (byte 8 shift) value)
            limit)))

(defun cbor-write-argument
    (writer major-type value max-byte-length)
  (let ((prefix (ash major-type 5)))
    (cond
      ((< value 24)
       (writer-byte writer
                    (logior prefix value)
                    max-byte-length))
      ((<= value #xff)
       (writer-byte writer
                    (logior prefix 24)
                    max-byte-length)
       (writer-byte writer value max-byte-length))
      ((<= value #xffff)
       (writer-byte writer
                    (logior prefix 25)
                    max-byte-length)
       (writer-uint writer value 2 max-byte-length))
      ((<= value +maximum-uint32+)
       (writer-byte writer
                    (logior prefix 26)
                    max-byte-length)
       (writer-uint writer value 4 max-byte-length))
      (t
       (writer-byte writer
                    (logior prefix 27)
                    max-byte-length)
       (writer-uint writer value 8 max-byte-length)))))

(defun valid-unicode-scalar-string-p (text)
  (loop for character across text
        for code = (char-code character)
        always (and (<= code #x10ffff)
                    (not (<= #xd800 code #xdfff)))))

(defun string-octets-strict (text)
  (unless (valid-unicode-scalar-string-p text)
    (cbor-fail
     "CBOR text strings must contain valid Unicode scalar values"))
  (handler-case
      (sb-ext:string-to-octets
       text :external-format :utf-8)
    (error ()
      (cbor-fail
       "CBOR text strings must contain valid Unicode scalar values"))))

(defun cbor-write-text
    (writer text max-byte-length)
  (let ((bytes (string-octets-strict text)))
    (when (> (length bytes) max-byte-length)
      (cbor-fail
       "CBOR text string length exceeds configured limit of ~D"
       max-byte-length))
    (cbor-write-argument
     writer 3 (length bytes) max-byte-length)
    (writer-bytes writer bytes max-byte-length)))

(defun finite-real-p (value)
  (and (realp value)
       (or (not (floatp value))
           (and (not (sb-ext:float-nan-p value))
                (not (sb-ext:float-infinity-p value))))))

(defun negative-zero-p (value)
  (and (floatp value)
       (zerop value)
       (minusp (float-sign value))))

(defun cbor-map-p (value)
  (hash-table-p value))

(defun cbor-sequence-p (value)
  (and (vectorp value)
       (not (typep value
                   '(vector (unsigned-byte 8))))))

(defun encode-cbor-value
    (writer value max-byte-length max-container-length max-depth
     depth ancestors)
  (when (> depth max-depth)
    (cbor-fail
     "CBOR nesting depth exceeds configured limit of ~D"
     max-depth))
  (cond
    ((eq value 'null)
     (writer-byte writer #xf6 max-byte-length))
    ((null value)
     (writer-byte writer #xf4 max-byte-length))
    ((eq value t)
     (writer-byte writer #xf5 max-byte-length))
    ((integerp value)
     (unless (<= (- +maximum-safe-integer+)
                 value
                 +maximum-safe-integer+)
       (cbor-fail
        "CBOR integers must be safe JavaScript integers"))
     (if (minusp value)
         (cbor-write-argument
          writer 1 (- -1 value) max-byte-length)
         (cbor-write-argument
          writer 0 value max-byte-length)))
    ((realp value)
     (unless (finite-real-p value)
       (cbor-fail "CBOR numbers must be finite"))
     (let* ((double (coerce value 'double-float))
            (bits (logand
                   (sb-kernel:double-float-bits double)
                   #xffffffffffffffff)))
       (writer-byte writer #xfb max-byte-length)
       (writer-uint writer bits 8 max-byte-length)))
    ((stringp value)
     (cbor-write-text writer value max-byte-length))
    ((byte-string-p value)
     (let ((bytes (byte-string-octets value)))
       (when (> (length bytes) max-byte-length)
         (cbor-fail
          "CBOR byte string length exceeds configured limit of ~D"
          max-byte-length))
       (cbor-write-argument
        writer 2 (length bytes) max-byte-length)
       (writer-bytes writer bytes max-byte-length)))
    ((cbor-sequence-p value)
     (when (gethash value ancestors)
       (cbor-fail "CBOR values must not contain cycles"))
     (when (> (length value) max-container-length)
       (cbor-fail
        "CBOR array length exceeds configured limit of ~D"
        max-container-length))
     (setf (gethash value ancestors) t)
     (unwind-protect
          (progn
            (cbor-write-argument
             writer 4 (length value) max-byte-length)
            (loop for item across value
                  do (encode-cbor-value
                      writer item
                      max-byte-length
                      max-container-length
                      max-depth
                      (1+ depth)
                      ancestors)))
       (remhash value ancestors)))
    ((cbor-map-p value)
     (when (gethash value ancestors)
       (cbor-fail "CBOR values must not contain cycles"))
     (when (> (hash-table-count value)
              max-container-length)
       (cbor-fail
        "CBOR map length exceeds configured limit of ~D"
        max-container-length))
     (setf (gethash value ancestors) t)
     (unwind-protect
          (progn
            (cbor-write-argument
             writer 5 (hash-table-count value)
             max-byte-length)
            (maphash
             (lambda (key item)
               (unless (stringp key)
                 (cbor-fail
                  "CBOR map keys must be strings"))
               (cbor-write-text
                writer key max-byte-length)
               (encode-cbor-value
                writer item
                max-byte-length
                max-container-length
                max-depth
                (1+ depth)
                ancestors))
             value))
       (remhash value ancestors)))
    (t
     (cbor-fail
      "Unsupported CBOR value type: ~S"
      (type-of value)))))

(defun encode-cbor
    (value &key max-byte-length max-container-length max-depth)
  (multiple-value-bind
      (resolved-byte-length
       resolved-container-length
       resolved-depth)
      (resolved-cbor-limits
       max-byte-length max-container-length max-depth)
    (let ((writer (make-octet-writer)))
      (encode-cbor-value
       writer value
       resolved-byte-length
       resolved-container-length
       resolved-depth
       0
       (make-hash-table :test #'eq))
      (copy-seq writer))))

(defstruct (cbor-reader
            (:constructor %make-cbor-reader
                (bytes max-byte-length
                       max-container-length max-depth)))
  (bytes #() :type (vector (unsigned-byte 8)))
  (offset 0 :type integer)
  (max-byte-length 0 :type integer)
  (max-container-length 0 :type integer)
  (max-depth 0 :type integer))

(defun reader-byte (reader)
  (when (>= (cbor-reader-offset reader)
            (length (cbor-reader-bytes reader)))
    (cbor-fail "Truncated CBOR payload"))
  (prog1
      (aref (cbor-reader-bytes reader)
            (cbor-reader-offset reader))
    (incf (cbor-reader-offset reader))))

(defun reader-bytes (reader length)
  (let ((end (+ (cbor-reader-offset reader)
                length)))
    (when (> end (length (cbor-reader-bytes reader)))
      (cbor-fail "Truncated CBOR payload"))
    (prog1
        (subseq (cbor-reader-bytes reader)
                (cbor-reader-offset reader)
                end)
      (setf (cbor-reader-offset reader) end))))

(defun reader-unsigned (reader width)
  (loop with value = 0
        repeat width
        do (setf value
                 (+ (ash value 8)
                    (reader-byte reader)))
        finally (return value)))

(defun reader-argument (reader additional-information)
  (cond
    ((< additional-information 24)
     additional-information)
    ((= additional-information 24)
     (reader-byte reader))
    ((= additional-information 25)
     (reader-unsigned reader 2))
    ((= additional-information 26)
     (reader-unsigned reader 4))
    ((= additional-information 27)
     (let ((value (reader-unsigned reader 8)))
       (when (> value +maximum-safe-integer+)
         (cbor-fail
          "Decoded CBOR integer or length is outside the safe range"))
       value))
    ((= additional-information 31)
     (cbor-fail
      "Indefinite-length CBOR items are not supported"))
    (t
     (cbor-fail
      "Malformed CBOR additional information"))))

(defun reader-length
    (reader additional-information kind limit)
  (when (= additional-information 31)
    (cbor-fail
     "Indefinite-length CBOR ~As are not supported"
     kind))
  (let ((length
          (reader-argument
           reader additional-information)))
    (when (> length limit)
      (cbor-fail
       "CBOR ~A length exceeds configured limit of ~D"
       kind limit))
    length))

(defun decode-float64 (reader)
  (let* ((bits (reader-unsigned reader 8))
         (high (ldb (byte 32 32) bits))
         (low (ldb (byte 32 0) bits))
         (value
           (sb-kernel:make-double-float
            (if (logbitp 31 high)
                (- high #x100000000)
                high)
            low)))
    (unless (finite-real-p value)
      (cbor-fail
       "Decoded CBOR number must be finite"))
    (when (and (integerp (rational value))
               (not (negative-zero-p value))
               (> (abs value) +maximum-safe-integer+))
      (cbor-fail
       "Decoded CBOR integer is outside the safe range"))
    value))

(defun decode-text (bytes)
  (handler-case
      (let ((text
              (sb-ext:octets-to-string
               bytes :external-format :utf-8)))
        (unless (valid-unicode-scalar-string-p text)
          (cbor-fail
           "CBOR text string contains invalid UTF-8"))
        text)
    (cbor-error (condition)
      (error condition))
    (error ()
      (cbor-fail
       "CBOR text string contains invalid UTF-8"))))

(defun decode-cbor-item (reader depth)
  (when (> depth (cbor-reader-max-depth reader))
    (cbor-fail
     "CBOR nesting depth exceeds configured limit of ~D"
     (cbor-reader-max-depth reader)))
  (let* ((initial (reader-byte reader))
         (major-type (ash initial -5))
         (additional-information
           (logand initial #x1f)))
    (case major-type
      (0
       (reader-argument
        reader additional-information))
      (1
       (let ((value
               (- -1
                  (reader-argument
                   reader additional-information))))
         (when (< value (- +maximum-safe-integer+))
           (cbor-fail
            "Decoded CBOR integer is outside the safe range"))
         value))
      (2
       (make-byte-string
        (reader-bytes
         reader
         (reader-length
          reader additional-information
          "byte string"
          (cbor-reader-max-byte-length reader)))))
      (3
       (decode-text
        (reader-bytes
         reader
         (reader-length
          reader additional-information
          "text string"
          (cbor-reader-max-byte-length reader)))))
      (4
       (let* ((length
                (reader-length
                 reader additional-information
                 "array"
                 (cbor-reader-max-container-length reader)))
              (result (make-array length)))
         (loop for index below length
               do (setf
                   (aref result index)
                   (decode-cbor-item reader (1+ depth))))
         result))
      (5
       (let* ((length
                (reader-length
                 reader additional-information
                 "map"
                 (cbor-reader-max-container-length reader)))
              (result
                (make-hash-table :test #'equal)))
         (loop repeat length
               for key =
               (decode-cbor-item reader (1+ depth))
               do
                  (unless (stringp key)
                    (cbor-fail
                     "CBOR map keys must be strings"))
                  (when (nth-value
                         1 (gethash key result))
                    (cbor-fail
                     "CBOR map contains a duplicate key"))
                  (setf
                   (gethash key result)
                   (decode-cbor-item
                    reader (1+ depth))))
         result))
      (6
       (cbor-fail "CBOR tags are not supported"))
      (7
       (case additional-information
         (20 nil)
         (21 t)
         (22 'null)
         (27 (decode-float64 reader))
         (31
          (cbor-fail
           "CBOR break marker is not supported"))
         (otherwise
          (cbor-fail
           "Unsupported CBOR simple value or floating-point width")))))))

(defun decode-cbor
    (bytes &key max-byte-length max-container-length max-depth)
  (unless (typep bytes '(vector (unsigned-byte 8)))
    (error 'type-error
           :datum bytes
           :expected-type '(vector (unsigned-byte 8))))
  (multiple-value-bind
      (resolved-byte-length
       resolved-container-length
       resolved-depth)
      (resolved-cbor-limits
       max-byte-length max-container-length max-depth)
    (when (> (length bytes) resolved-byte-length)
      (cbor-fail
       "CBOR byte length exceeds configured limit of ~D"
       resolved-byte-length))
    (let ((reader
            (%make-cbor-reader
             bytes
             resolved-byte-length
             resolved-container-length
             resolved-depth)))
      (let ((value (decode-cbor-item reader 0)))
        (unless (= (cbor-reader-offset reader)
                   (length bytes))
          (cbor-fail
           "CBOR payload contains trailing data"))
        value))))
