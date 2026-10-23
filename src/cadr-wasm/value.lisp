(in-package #:cadr-wasm)

(defconstant +i32-mask+ #xffffffff)
(defconstant +i64-mask+ #xffffffffffffffff)
(defconstant +i32-min+ (- #x80000000))
(defconstant +i64-min+ (- #x8000000000000000))
(defconstant +f32-canon+ #x7fc00000)
(defconstant +f64-canon+ #x7ff8000000000000)
(defconstant +page-size+ 65536)

(defun i32 (n) (logand n +i32-mask+))
(defun i64 (n) (logand n +i64-mask+))

(defun i32-signed (n)
  (let ((n (i32 n)))
    (if (logbitp 31 n) (- n #x100000000) n)))

(defun i64-signed (n)
  (let ((n (i64 n)))
    (if (logbitp 63 n) (- n #x10000000000000000) n)))

(defun sign-extend (n width)
  (let ((n (logand n (1- (ash 1 width)))))
    (if (logbitp (1- width) n)
        (- n (ash 1 width))
        n)))

(defun bits-to-f32 (bits)
  (sb-kernel:make-single-float
   (let ((bits (i32 bits)))
     (if (logbitp 31 bits) (- bits #x100000000) bits))))

(defun f32-to-bits (value)
  (i32 (sb-kernel:single-float-bits value)))

(defun bits-to-f64 (bits)
  (let ((bits (i64 bits)))
    (sb-kernel:make-double-float
     (let ((hi (ldb (byte 32 32) bits)))
       (if (logbitp 31 hi) (- hi #x100000000) hi))
     (ldb (byte 32 0) bits))))

(defun f64-to-bits (value)
  (i64 (logior (ash (i32 (sb-kernel:double-float-high-bits value)) 32)
               (i32 (sb-kernel:double-float-low-bits value)))))

(defun f32-nan-p (bits)
  (let ((bits (i32 bits)))
    (and (= (ldb (byte 8 23) bits) #xff)
         (plusp (ldb (byte 23 0) bits)))))

(defun f64-nan-p (bits)
  (let ((bits (i64 bits)))
    (and (= (ldb (byte 11 52) bits) #x7ff)
         (plusp (ldb (byte 52 0) bits)))))

(defun f32-canon (bits)
  (if (f32-nan-p bits) +f32-canon+ (i32 bits)))

(defun f64-canon (bits)
  (if (f64-nan-p bits) +f64-canon+ (i64 bits)))

(defmacro with-wasm-floats (&body body)
  "invoke and the start function mask traps for the whole call.
A mask on every f64 operation is arch_set_fp_modes in the profile."
  `(progn ,@body))

(defun f32-unop (bits op)
  (with-wasm-floats
    (f32-canon (f32-to-bits (funcall op (bits-to-f32 bits))))))

(defun f64-unop (bits op)
  (with-wasm-floats
    (f64-canon (f64-to-bits (funcall op (bits-to-f64 bits))))))

(defun f32-binop (a b op)
  (with-wasm-floats
    (f32-canon (f32-to-bits (funcall op (bits-to-f32 a) (bits-to-f32 b))))))

(defun f64-binop (a b op)
  (with-wasm-floats
    (f64-canon (f64-to-bits (funcall op (bits-to-f64 a) (bits-to-f64 b))))))

(defun f32-neg (bits) (logxor (i32 bits) #x80000000))
(defun f32-abs (bits) (logand (i32 bits) #x7fffffff))
(defun f32-copysign (mag sign)
  (logior (f32-abs mag) (logand (i32 sign) #x80000000)))

(defun f64-neg (bits) (logxor (i64 bits) #x8000000000000000))
(defun f64-abs (bits) (logand (i64 bits) #x7fffffffffffffff))
(defun f64-copysign (mag sign)
  (logior (f64-abs mag) (logand (i64 sign) #x8000000000000000)))

(defun f32-sign-bit-p (bits) (logbitp 31 (i32 bits)))
(defun f64-sign-bit-p (bits) (logbitp 63 (i64 bits)))

(defun f32-min (a b)
  (cond ((or (f32-nan-p a) (f32-nan-p b)) +f32-canon+)
        ((and (zerop (bits-to-f32 a)) (zerop (bits-to-f32 b)))
         (if (or (f32-sign-bit-p a) (f32-sign-bit-p b)) #x80000000 0))
        (t (f32-binop a b #'min))))

(defun f32-max (a b)
  (cond ((or (f32-nan-p a) (f32-nan-p b)) +f32-canon+)
        ((and (zerop (bits-to-f32 a)) (zerop (bits-to-f32 b)))
         (if (and (f32-sign-bit-p a) (f32-sign-bit-p b)) #x80000000 0))
        (t (f32-binop a b #'max))))

(defun f64-min (a b)
  (cond ((or (f64-nan-p a) (f64-nan-p b)) +f64-canon+)
        ((and (zerop (bits-to-f64 a)) (zerop (bits-to-f64 b)))
         (if (or (f64-sign-bit-p a) (f64-sign-bit-p b)) #x8000000000000000 0))
        (t (f64-binop a b #'min))))

(defun f64-max (a b)
  (cond ((or (f64-nan-p a) (f64-nan-p b)) +f64-canon+)
        ((and (zerop (bits-to-f64 a)) (zerop (bits-to-f64 b)))
         (if (and (f64-sign-bit-p a) (f64-sign-bit-p b)) #x8000000000000000 0))
        (t (f64-binop a b #'max))))

(defun f32-sqrt (bits)
  (cond ((f32-nan-p bits) +f32-canon+)
        ((and (f32-sign-bit-p bits) (not (zerop (logand bits #x7fffffff))))
         +f32-canon+)
        (t (f32-unop bits #'sqrt))))

(defun f64-sqrt (bits)
  (cond ((f64-nan-p bits) +f64-canon+)
        ((and (f64-sign-bit-p bits) (not (zerop (logand bits #x7fffffffffffffff))))
         +f64-canon+)
        (t (f64-unop bits #'sqrt))))

(defun f32-nearest (bits)
  (if (or (f32-nan-p bits) (= (ldb (byte 8 23) (i32 bits)) #xff))
      (f32-canon bits)
      (f32-unop bits #'fround)))

(defun f64-nearest (bits)
  (if (or (f64-nan-p bits) (= (ldb (byte 11 52) (i64 bits)) #x7ff))
      (f64-canon bits)
      (f64-unop bits #'fround)))

(defun i32-clz (n)
  (let ((n (i32 n)))
    (if (zerop n) 32 (- 32 (integer-length n)))))

(defun i64-clz (n)
  (let ((n (i64 n)))
    (if (zerop n) 64 (- 64 (integer-length n)))))

(defun i32-ctz (n)
  (let ((n (i32 n)))
    (if (zerop n) 32 (1- (integer-length (logand n (- n)))))))

(defun i64-ctz (n)
  (let ((n (i64 n)))
    (if (zerop n) 64 (1- (integer-length (logand n (- n)))))))

(defun i32-div-s (a b)
  (let ((a (i32-signed a)) (b (i32-signed b)))
    (when (zerop b) (wasm-trap "integer divide by zero"))
    (when (and (= a +i32-min+) (= b -1)) (wasm-trap "integer overflow"))
    (i32 (truncate a b))))

(defun i64-div-s (a b)
  (let ((a (i64-signed a)) (b (i64-signed b)))
    (when (zerop b) (wasm-trap "integer divide by zero"))
    (when (and (= a +i64-min+) (= b -1)) (wasm-trap "integer overflow"))
    (i64 (truncate a b))))

(defun i32-rem-s (a b)
  (let ((a (i32-signed a)) (b (i32-signed b)))
    (when (zerop b) (wasm-trap "integer divide by zero"))
    (if (and (= a +i32-min+) (= b -1)) 0 (i32 (rem a b)))))

(defun i64-rem-s (a b)
  (let ((a (i64-signed a)) (b (i64-signed b)))
    (when (zerop b) (wasm-trap "integer divide by zero"))
    (if (and (= a +i64-min+) (= b -1)) 0 (i64 (rem a b)))))

(defun i32-div-u (a b)
  (when (zerop (i32 b)) (wasm-trap "integer divide by zero"))
  (floor (i32 a) (i32 b)))

(defun i64-div-u (a b)
  (when (zerop (i64 b)) (wasm-trap "integer divide by zero"))
  (floor (i64 a) (i64 b)))

(defun i32-rem-u (a b)
  (when (zerop (i32 b)) (wasm-trap "integer divide by zero"))
  (mod (i32 a) (i32 b)))

(defun i64-rem-u (a b)
  (when (zerop (i64 b)) (wasm-trap "integer divide by zero"))
  (mod (i64 a) (i64 b)))

(defun i32-shl (a b) (i32 (ash (i32 a) (logand b 31))))
(defun i64-shl (a b) (i64 (ash (i64 a) (logand b 63))))
(defun i32-shr-u (a b) (ash (i32 a) (- (logand b 31))))
(defun i64-shr-u (a b) (ash (i64 a) (- (logand b 63))))
(defun i32-shr-s (a b) (i32 (ash (i32-signed a) (- (logand b 31)))))
(defun i64-shr-s (a b) (i64 (ash (i64-signed a) (- (logand b 63)))))

(defun i32-rotl (a b)
  (let ((n (logand b 31)) (a (i32 a)))
    (i32 (logior (ash a n) (ash a (- n 32))))))

(defun i32-rotr (a b)
  (let ((n (logand b 31)))
    (if (zerop n) (i32 a) (i32-rotl a (- 32 n)))))

(defun i64-rotl (a b)
  (let ((n (logand b 63)) (a (i64 a)))
    (i64 (logior (ash a n) (ash a (- n 64))))))

(defun i64-rotr (a b)
  (let ((n (logand b 63)))
    (if (zerop n) (i64 a) (i64-rotl a (- 64 n)))))

(defun flag (value) (if value 1 0))

(defun i32-extend8-s (n) (i32 (sign-extend n 8)))
(defun i32-extend16-s (n) (i32 (sign-extend n 16)))
(defun i64-extend8-s (n) (i64 (sign-extend n 8)))
(defun i64-extend16-s (n) (i64 (sign-extend n 16)))
(defun i64-extend32-s (n) (i64 (sign-extend n 32)))

(defun non-finite-p (value)
  (or (sb-ext:float-nan-p value) (sb-ext:float-infinity-p value)))

(defun trunc-range (value min max)
  (cond ((sb-ext:float-nan-p value) (wasm-trap "invalid conversion to integer"))
        ((sb-ext:float-infinity-p value) (wasm-trap "integer overflow"))
        (t (let ((n (truncate value)))
             (unless (<= min n max) (wasm-trap "integer overflow"))
             n))))

(defun trunc-i32-s (value) (i32 (trunc-range value +i32-min+ 2147483647)))
(defun trunc-i32-u (value) (i32 (trunc-range value 0 4294967295)))
(defun trunc-i64-s (value) (i64 (trunc-range value +i64-min+ (1- (ash 1 63)))))
(defun trunc-i64-u (value) (i64 (trunc-range value 0 (1- (ash 1 64)))))

(defun i32-trunc-f32-s (bits) (with-wasm-floats (trunc-i32-s (bits-to-f32 bits))))
(defun i32-trunc-f32-u (bits) (with-wasm-floats (trunc-i32-u (bits-to-f32 bits))))
(defun i32-trunc-f64-s (bits) (with-wasm-floats (trunc-i32-s (bits-to-f64 bits))))
(defun i32-trunc-f64-u (bits) (with-wasm-floats (trunc-i32-u (bits-to-f64 bits))))
(defun i64-trunc-f32-s (bits) (with-wasm-floats (trunc-i64-s (bits-to-f32 bits))))
(defun i64-trunc-f32-u (bits) (with-wasm-floats (trunc-i64-u (bits-to-f32 bits))))
(defun i64-trunc-f64-s (bits) (with-wasm-floats (trunc-i64-s (bits-to-f64 bits))))
(defun i64-trunc-f64-u (bits) (with-wasm-floats (trunc-i64-u (bits-to-f64 bits))))

(defun sat-i32-s (value)
  (cond ((sb-ext:float-nan-p value) 0)
        ((sb-ext:float-infinity-p value) (if (minusp value) #x80000000 #x7fffffff))
        (t (let ((n (truncate value)))
             (cond ((< n +i32-min+) #x80000000)
                   ((> n 2147483647) #x7fffffff)
                   (t (i32 n)))))))

(defun sat-i32-u (value)
  (cond ((sb-ext:float-nan-p value) 0)
        ((sb-ext:float-infinity-p value) (if (minusp value) 0 #xffffffff))
        (t (let ((n (truncate value)))
             (cond ((< n 0) 0)
                   ((> n 4294967295) #xffffffff)
                   (t (i32 n)))))))

(defun sat-i64-s (value)
  (cond ((sb-ext:float-nan-p value) 0)
        ((sb-ext:float-infinity-p value)
         (if (minusp value) #x8000000000000000 #x7fffffffffffffff))
        (t (let ((n (truncate value)))
             (cond ((< n +i64-min+) #x8000000000000000)
                   ((> n (1- (ash 1 63))) #x7fffffffffffffff)
                   (t (i64 n)))))))

(defun sat-i64-u (value)
  (cond ((sb-ext:float-nan-p value) 0)
        ((sb-ext:float-infinity-p value) (if (minusp value) 0 #xffffffffffffffff))
        (t (let ((n (truncate value)))
             (cond ((< n 0) 0)
                   ((> n (1- (ash 1 64))) #xffffffffffffffff)
                   (t (i64 n)))))))

(defun i32-trunc-sat-f32-s (bits) (with-wasm-floats (sat-i32-s (bits-to-f32 bits))))
(defun i32-trunc-sat-f32-u (bits) (with-wasm-floats (sat-i32-u (bits-to-f32 bits))))
(defun i32-trunc-sat-f64-s (bits) (with-wasm-floats (sat-i32-s (bits-to-f64 bits))))
(defun i32-trunc-sat-f64-u (bits) (with-wasm-floats (sat-i32-u (bits-to-f64 bits))))
(defun i64-trunc-sat-f32-s (bits) (with-wasm-floats (sat-i64-s (bits-to-f32 bits))))
(defun i64-trunc-sat-f32-u (bits) (with-wasm-floats (sat-i64-u (bits-to-f32 bits))))
(defun i64-trunc-sat-f64-s (bits) (with-wasm-floats (sat-i64-s (bits-to-f64 bits))))
(defun i64-trunc-sat-f64-u (bits) (with-wasm-floats (sat-i64-u (bits-to-f64 bits))))

(defun f32-from-signed (n) (f32-canon (f32-to-bits (float n 1.0))))
(defun f32-from-unsigned (n) (f32-canon (f32-to-bits (float n 1.0))))
(defun f64-from-signed (n) (f64-canon (f64-to-bits (float n 1.0d0))))
(defun f64-from-unsigned (n) (f64-canon (f64-to-bits (float n 1.0d0))))

(defun f32-convert-i32-s (n) (f32-from-signed (i32-signed n)))
(defun f32-convert-i32-u (n) (f32-from-unsigned (i32 n)))
(defun f32-convert-i64-s (n) (f32-from-signed (i64-signed n)))
(defun f32-convert-i64-u (n) (f32-from-unsigned (i64 n)))
(defun f64-convert-i32-s (n) (f64-from-signed (i32-signed n)))
(defun f64-convert-i32-u (n) (f64-from-unsigned (i32 n)))
(defun f64-convert-i64-s (n) (f64-from-signed (i64-signed n)))
(defun f64-convert-i64-u (n) (f64-from-unsigned (i64 n)))

(defun f32-demote-f64 (bits)
  (with-wasm-floats (f32-canon (f32-to-bits (float (bits-to-f64 bits) 1.0)))))

(defun f64-promote-f32 (bits)
  (with-wasm-floats (f64-canon (f64-to-bits (float (bits-to-f32 bits) 1.0d0)))))

(defun mem-range (memory address offset size)
  (let* ((sum (+ (i32 address) (i32 offset)))
         (bytes (wasm-memory-bytes memory))
         (len (length bytes)))
    (declare (type (simple-array (unsigned-byte 8) (*)) bytes))
    (unless (and (< sum #x100000000) (<= size (- len sum)))
      (wasm-trap "out of bounds memory access"))
    (values bytes sum)))

(defun gcell-store (cell type value)
  (setf (wasm-gcell-value cell) value)
  (when (member type '(:i32 :i64 :f32 :f64))
    (let ((bits (i64 value)))
      (setf (wasm-gcell-bits cell) bits
            (wasm-gcell-lo cell) (ldb (byte 32 0) bits)
            (wasm-gcell-hi cell) (ldb (byte 32 32) bits))
      (case type
        (:f32 (setf (wasm-gcell-f32 cell) (bits-to-f32 value)))
        (:f64 (setf (wasm-gcell-f64 cell) (bits-to-f64 value))))))
  value)

(defun load-le (memory address offset size)
  (multiple-value-bind (bytes ea) (mem-range memory address offset size)
    (let ((value 0))
      (dotimes (i size value)
        (setf value (logior value (ash (aref bytes (+ ea i)) (* 8 i))))))))

(defun store-le (memory address offset size value)
  (multiple-value-bind (bytes ea) (mem-range memory address offset size)
    (dotimes (i size)
      (setf (aref bytes (+ ea i)) (ldb (byte 8 (* 8 i)) value)))))

(defun load-i32 (memory address offset) (load-le memory address offset 4))
(defun load-i64 (memory address offset) (load-le memory address offset 8))
(defun load-f32 (memory address offset) (load-le memory address offset 4))
(defun load-f64 (memory address offset) (load-le memory address offset 8))

(defun load-i32-8-s (memory address offset)
  (i32 (sign-extend (load-le memory address offset 1) 8)))
(defun load-i32-8-u (memory address offset) (load-le memory address offset 1))
(defun load-i32-16-s (memory address offset)
  (i32 (sign-extend (load-le memory address offset 2) 16)))
(defun load-i32-16-u (memory address offset) (load-le memory address offset 2))
(defun load-i64-8-s (memory address offset)
  (i64 (sign-extend (load-le memory address offset 1) 8)))
(defun load-i64-8-u (memory address offset) (load-le memory address offset 1))
(defun load-i64-16-s (memory address offset)
  (i64 (sign-extend (load-le memory address offset 2) 16)))
(defun load-i64-16-u (memory address offset) (load-le memory address offset 2))
(defun load-i64-32-s (memory address offset)
  (i64 (sign-extend (load-le memory address offset 4) 32)))
(defun load-i64-32-u (memory address offset) (load-le memory address offset 4))

(defun store-i32 (memory address offset value) (store-le memory address offset 4 value))
(defun store-i64 (memory address offset value) (store-le memory address offset 8 value))
(defun store-f32 (memory address offset value) (store-le memory address offset 4 value))
(defun store-f64 (memory address offset value) (store-le memory address offset 8 value))
(defun store-i32-8 (memory address offset value) (store-le memory address offset 1 value))
(defun store-i32-16 (memory address offset value) (store-le memory address offset 2 value))
(defun store-i64-8 (memory address offset value) (store-le memory address offset 1 value))
(defun store-i64-16 (memory address offset value) (store-le memory address offset 2 value))
(defun store-i64-32 (memory address offset value) (store-le memory address offset 4 value))

(defun memory-size (memory)
  (floor (length (wasm-memory-bytes memory)) +page-size+))

(defun memory-grow (memory delta)
  (let* ((delta (i32 delta))
         (old (memory-size memory))
         (new (+ old delta))
         (limit (or (wasm-memory-max memory) 65536)))
    (if (or (> new 65536) (> new limit))
        #xffffffff
        (let ((grown (make-array (* new +page-size+)
                                 :element-type '(unsigned-byte 8)
                                 :initial-element 0)))
          (replace grown (wasm-memory-bytes memory))
          (setf (wasm-memory-bytes memory) grown)
          old))))

(defun range-ok (length start count)
  (and (<= start length) (<= count (- length start))))

(defun memory-copy (memory destination source count)
  (let* ((destination (i32 destination))
         (source (i32 source))
         (count (i32 count))
         (bytes (wasm-memory-bytes memory))
         (length (length bytes)))
    (unless (and (range-ok length destination count) (range-ok length source count))
      (wasm-trap "out of bounds memory access"))
    (replace bytes (subseq bytes source (+ source count)) :start1 destination)))

(defun memory-fill (memory destination value count)
  (let* ((destination (i32 destination))
         (count (i32 count))
         (byte (logand value #xff))
         (bytes (wasm-memory-bytes memory)))
    (unless (range-ok (length bytes) destination count)
      (wasm-trap "out of bounds memory access"))
    (fill bytes byte :start destination :end (+ destination count))))

(defun memory-init (memory data destination source count)
  (let* ((destination (i32 destination))
         (source (i32 source))
         (count (i32 count))
         (bytes (wasm-memory-bytes memory))
         (init (or data (make-array 0 :element-type '(unsigned-byte 8)))))
    (unless (and (range-ok (length bytes) destination count)
                 (range-ok (length init) source count))
      (wasm-trap "out of bounds memory access"))
    (replace bytes init :start1 destination :end1 (+ destination count)
             :start2 source :end2 (+ source count))))

(defun table-oob (table address count)
  (not (range-ok (length (wasm-table-elements table)) (i32 address) (i32 count))))

(defun table-get (table index)
  (let ((index (i32 index))
        (elements (wasm-table-elements table)))
    (unless (< index (length elements))
      (wasm-trap "out of bounds table access"))
    (aref elements index)))

(defun table-set (table index value)
  (let ((index (i32 index))
        (elements (wasm-table-elements table)))
    (unless (< index (length elements))
      (wasm-trap "out of bounds table access"))
    (setf (aref elements index) value)))

(defun table-size (table) (length (wasm-table-elements table)))

(defun table-grow (table value delta)
  (let* ((delta (i32 delta))
         (old (table-size table))
         (new (+ old delta))
         (limit (or (wasm-table-max table) #xffffffff)))
    (if (or (> new limit) (> new #xffffffff))
        #xffffffff
        (let ((grown (make-array new :initial-element value)))
          (replace grown (wasm-table-elements table))
          (setf (wasm-table-elements table) grown)
          old))))

(defun table-fill (table index value count)
  (let ((index (i32 index)) (count (i32 count)))
    (when (table-oob table index count)
      (wasm-trap "out of bounds table access"))
    (fill (wasm-table-elements table) value :start index :end (+ index count))))

(defun table-copy (destination source dest-index src-index count)
  (let ((dest-index (i32 dest-index))
        (src-index (i32 src-index))
        (count (i32 count)))
    (when (or (table-oob destination dest-index count)
              (table-oob source src-index count))
      (wasm-trap "out of bounds table access"))
    (replace (wasm-table-elements destination)
             (subseq (wasm-table-elements source) src-index (+ src-index count))
             :start1 dest-index)))

(defun table-init (table elements dest-index src-index count)
  (let ((dest-index (i32 dest-index))
        (src-index (i32 src-index))
        (count (i32 count))
        (source (or elements (vector))))
    (when (or (table-oob table dest-index count)
              (not (range-ok (length source) src-index count)))
      (wasm-trap "out of bounds table access"))
    (replace (wasm-table-elements table) source
             :start1 dest-index :end1 (+ dest-index count)
             :start2 src-index :end2 (+ src-index count))))

(defun null-ref-p (value) (wasm-null-p value))

(defun ref-is-null (value) (flag (null-ref-p value)))

(defun default-for (type)
  (case type
    ((:funcref) +null-funcref+)
    ((:externref) +null-externref+)
    ((:f32 :f64 :i32 :i64) 0)
    (t 0)))
