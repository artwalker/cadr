(in-package #:cadr-wasm)

(defun bit-flag (value) (if value 1 0))

(defun i32-lt-s (a b) (bit-flag (< (i32-signed a) (i32-signed b))))
(defun i32-lt-u (a b) (bit-flag (< (i32 a) (i32 b))))
(defun i32-gt-s (a b) (bit-flag (> (i32-signed a) (i32-signed b))))
(defun i32-gt-u (a b) (bit-flag (> (i32 a) (i32 b))))
(defun i32-le-s (a b) (bit-flag (<= (i32-signed a) (i32-signed b))))
(defun i32-le-u (a b) (bit-flag (<= (i32 a) (i32 b))))
(defun i32-ge-s (a b) (bit-flag (>= (i32-signed a) (i32-signed b))))
(defun i32-ge-u (a b) (bit-flag (>= (i32 a) (i32 b))))
(defun i64-lt-s (a b) (bit-flag (< (i64-signed a) (i64-signed b))))
(defun i64-lt-u (a b) (bit-flag (< (i64 a) (i64 b))))
(defun i64-gt-s (a b) (bit-flag (> (i64-signed a) (i64-signed b))))
(defun i64-gt-u (a b) (bit-flag (> (i64 a) (i64 b))))
(defun i64-le-s (a b) (bit-flag (<= (i64-signed a) (i64-signed b))))
(defun i64-le-u (a b) (bit-flag (<= (i64 a) (i64 b))))
(defun i64-ge-s (a b) (bit-flag (>= (i64-signed a) (i64-signed b))))
(defun i64-ge-u (a b) (bit-flag (>= (i64 a) (i64 b))))
(defun f32-eq (a b) (with-wasm-floats (bit-flag (= (bits-to-f32 a) (bits-to-f32 b)))))
(defun f32-ne (a b) (with-wasm-floats (bit-flag (/= (bits-to-f32 a) (bits-to-f32 b)))))
(defun f32-lt (a b) (with-wasm-floats (bit-flag (< (bits-to-f32 a) (bits-to-f32 b)))))
(defun f32-gt (a b) (with-wasm-floats (bit-flag (> (bits-to-f32 a) (bits-to-f32 b)))))
(defun f32-le (a b) (with-wasm-floats (bit-flag (<= (bits-to-f32 a) (bits-to-f32 b)))))
(defun f32-ge (a b) (with-wasm-floats (bit-flag (>= (bits-to-f32 a) (bits-to-f32 b)))))
(defun f64-eq (a b) (with-wasm-floats (bit-flag (= (bits-to-f64 a) (bits-to-f64 b)))))
(defun f64-ne (a b) (with-wasm-floats (bit-flag (/= (bits-to-f64 a) (bits-to-f64 b)))))
(defun f64-lt (a b) (with-wasm-floats (bit-flag (< (bits-to-f64 a) (bits-to-f64 b)))))
(defun f64-gt (a b) (with-wasm-floats (bit-flag (> (bits-to-f64 a) (bits-to-f64 b)))))
(defun f64-le (a b) (with-wasm-floats (bit-flag (<= (bits-to-f64 a) (bits-to-f64 b)))))
(defun f64-ge (a b) (with-wasm-floats (bit-flag (>= (bits-to-f64 a) (bits-to-f64 b)))))
(defun i32-add (a b) (i32 (+ a b)))
(defun i32-sub (a b) (i32 (- a b)))
(defun i32-mul (a b) (i32 (* a b)))
(defun i32-and (a b) (i32 (logand a b)))
(defun i32-or (a b) (i32 (logior a b)))
(defun i32-xor (a b) (i32 (logxor a b)))
(defun i64-add (a b) (i64 (+ a b)))
(defun i64-sub (a b) (i64 (- a b)))
(defun i64-mul (a b) (i64 (* a b)))
(defun i64-and (a b) (i64 (logand a b)))
(defun i64-or (a b) (i64 (logior a b)))
(defun i64-xor (a b) (i64 (logxor a b)))
(defun i32-eqz (a) (if (zerop (i32 a)) 1 0))
(defun i64-eqz (a) (if (zerop (i64 a)) 1 0))
(defun i32-eq (a b) (if (= (i32 a) (i32 b)) 1 0))
(defun i32-ne (a b) (if (/= (i32 a) (i32 b)) 1 0))
(defun i64-eq (a b) (if (= (i64 a) (i64 b)) 1 0))
(defun i64-ne (a b) (if (/= (i64 a) (i64 b)) 1 0))
(defun i64-extend-i32-s (a) (i64 (i32-signed a)))
(defun i64-extend-i32-u (a) (i64 a))
(defun i32-wrap-i64 (a) (i32 a))

(defstruct cframe
  kind base nparams nresults
  br-label br-arity end-label else-label
  entry-reachable param-temps saw-else
  param-types result-types)

(defun block-parts (module bt)
  (cond ((eq bt :empty) (cons #() #()))
        ((and (consp bt) (eq (car bt) :val)) (cons #() (vector (cdr bt))))
        (t (type-at module (cdr bt)))))

(defun ref-type-p (type)
  (member type '(:funcref :externref)))

(defun numeric-function-p (module sig locals body)
  "True when the operand stack and locals hold only integer bit patterns.
quickjs-wasi 3.6.2 is in this set: its call_indirect tables stay off the
operand stack. Spec functions that push a funcref or externref are not."
  (and (notany #'ref-type-p (coerce (sig-params sig) 'list))
       (notany #'ref-type-p (coerce (sig-results sig) 'list))
       (notany #'ref-type-p locals)
       (not (find-if (lambda (item)
                       (member (instr-op item)
                               '(:ref.null :ref.func :ref.is-null
                                 :table.get :table.set :table.grow
                                 :table.fill :table.copy :table.init)))
                     body))
       (not (find-if (lambda (item)
                       (and (member (instr-op item) '(:global.get :global.set))
                            (ref-type-p (car (global-type-at
                                              module (instr-a item))))))
                     body))
       (let ((sigs (collect-sigs module)))
         (not (find-if (lambda (item)
                         (and (eq (instr-op item) :call)
                              (let ((target (aref sigs (instr-a item))))
                                (or (some #'ref-type-p (sig-params target))
                                    (some #'ref-type-p (sig-results target))))))
                       body)))))

(defun bit-binop (width function left right)
  (let ((mask (if (= width 32) '(byte 32 0) '(byte 64 0))))
    (case function
      ((i32-add i64-add) `(ldb ,mask (+ (the (unsigned-byte 64) ,left)
                                        (the (unsigned-byte 64) ,right))))
      ((i32-sub i64-sub) `(ldb ,mask (- (the (unsigned-byte 64) ,left)
                                        (the (unsigned-byte 64) ,right))))
      ((i32-mul i64-mul) `(ldb ,mask (* (the (unsigned-byte 64) ,left)
                                        (the (unsigned-byte 64) ,right))))
      ((i32-and i64-and) `(logand (the (unsigned-byte 64) ,left)
                                  (the (unsigned-byte 64) ,right)
                                  ,(if (= width 32) '#xffffffff '#xffffffffffffffff)))
      ((i32-or i64-or) `(ldb ,mask (logior (the (unsigned-byte 64) ,left)
                                           (the (unsigned-byte 64) ,right))))
      ((i32-xor i64-xor) `(ldb ,mask (logxor (the (unsigned-byte 64) ,left)
                                             (the (unsigned-byte 64) ,right))))
      ((i32-eq i64-eq) `(if (= (the (unsigned-byte 64) ,left)
                               (the (unsigned-byte 64) ,right))
                            1 0))
      ((i32-ne i64-ne) `(if (= (the (unsigned-byte 64) ,left)
                               (the (unsigned-byte 64) ,right))
                            0 1))
      ((i32-lt-u i64-lt-u) `(if (< (the (unsigned-byte 64) ,left)
                                   (the (unsigned-byte 64) ,right))
                                1 0))
      ((i32-gt-u i64-gt-u) `(if (> (the (unsigned-byte 64) ,left)
                                   (the (unsigned-byte 64) ,right))
                                1 0))
      ((i32-le-u i64-le-u) `(if (<= (the (unsigned-byte 64) ,left)
                                    (the (unsigned-byte 64) ,right))
                                1 0))
      ((i32-ge-u i64-ge-u) `(if (>= (the (unsigned-byte 64) ,left)
                                    (the (unsigned-byte 64) ,right))
                                1 0))
      (t nil))))

(defun fast-unop-form (function arg)
  (case function
    (i32-eqz `(if (zerop (ldb (byte 32 0) (the (unsigned-byte 64) ,arg))) 1 0))
    (i64-eqz `(if (zerop (the (unsigned-byte 64) ,arg)) 1 0))
    (i32-wrap-i64 `(ldb (byte 32 0) (the (unsigned-byte 64) ,arg)))
    (i64-extend-i32-u `(ldb (byte 32 0) (the (unsigned-byte 64) ,arg)))
    (i64-extend-i32-s `(let ((low (ldb (byte 32 0) (the (unsigned-byte 64) ,arg))))
                         (if (logbitp 31 low) (logior low #xffffffff00000000) low)))
    (t nil)))

(defun fast-binop-form (function left right)
  (or (bit-binop (if (member function '(i32-add i32-sub i32-mul i32-and i32-or i32-xor
                                        i32-eq i32-ne i32-lt-u i32-gt-u i32-le-u i32-ge-u))
                     32 64)
                 function left right)
      (case function
        (i32-lt-s `(if (< (logxor (ldb (byte 32 0) (the (unsigned-byte 64) ,left)) #x80000000)
                          (logxor (ldb (byte 32 0) (the (unsigned-byte 64) ,right)) #x80000000))
                       1 0))
        (i32-gt-s `(if (> (logxor (ldb (byte 32 0) (the (unsigned-byte 64) ,left)) #x80000000)
                          (logxor (ldb (byte 32 0) (the (unsigned-byte 64) ,right)) #x80000000))
                       1 0))
        (i32-le-s `(if (<= (logxor (ldb (byte 32 0) (the (unsigned-byte 64) ,left)) #x80000000)
                           (logxor (ldb (byte 32 0) (the (unsigned-byte 64) ,right)) #x80000000))
                       1 0))
        (i32-ge-s `(if (>= (logxor (ldb (byte 32 0) (the (unsigned-byte 64) ,left)) #x80000000)
                           (logxor (ldb (byte 32 0) (the (unsigned-byte 64) ,right)) #x80000000))
                       1 0))
        (i64-lt-s `(if (< (logxor (the (unsigned-byte 64) ,left) #x8000000000000000)
                          (logxor (the (unsigned-byte 64) ,right) #x8000000000000000))
                       1 0))
        (i64-gt-s `(if (> (logxor (the (unsigned-byte 64) ,left) #x8000000000000000)
                          (logxor (the (unsigned-byte 64) ,right) #x8000000000000000))
                       1 0))
        (i64-le-s `(if (<= (logxor (the (unsigned-byte 64) ,left) #x8000000000000000)
                           (logxor (the (unsigned-byte 64) ,right) #x8000000000000000))
                       1 0))
        (i64-ge-s `(if (>= (logxor (the (unsigned-byte 64) ,left) #x8000000000000000)
                           (logxor (the (unsigned-byte 64) ,right) #x8000000000000000))
                       1 0))
        (i32-shl `(ldb (byte 32 0)
                       (ash (ldb (byte 32 0) (the (unsigned-byte 64) ,left))
                            (logand (the (unsigned-byte 64) ,right) 31))))
        (i32-shr-u `(ash (ldb (byte 32 0) (the (unsigned-byte 64) ,left))
                         (- (logand (the (unsigned-byte 64) ,right) 31))))
        (i64-shl `(ldb (byte 64 0)
                       (ash (the (unsigned-byte 64) ,left)
                            (logand (the (unsigned-byte 64) ,right) 63))))
        (i64-shr-u `(ash (the (unsigned-byte 64) ,left)
                         (- (logand (the (unsigned-byte 64) ,right) 63))))
        (t nil))))

(defmacro with-mem-bytes ((bytes ea address offset size) &body body)
  "bytes is the function-entry memory vector. A 32-bit sum that overflows traps."
  (let ((sum (gensym "SUM")) (len (gensym "LEN")))
    `(let* ((,sum (+ (ldb (byte 32 0) (the (unsigned-byte 64) ,address))
                     (ldb (byte 32 0) (the (unsigned-byte 64) ,offset))))
            (,len (length (the (simple-array (unsigned-byte 8) (*)) ,bytes))))
       (declare (type (unsigned-byte 33) ,sum))
       (unless (and (< ,sum #x100000000) (<= ,size (- ,len ,sum)))
         (wasm-trap "out of bounds memory access"))
       (let ((,ea ,sum))
         (declare (type (unsigned-byte 32) ,ea)
                  (type (simple-array (unsigned-byte 8) (*)) ,bytes))
         ,@body))))

(defun repr-lisp-type (type)
  (case type
    (:f32 'single-float)
    (:f64 'double-float)
    (t '(unsigned-byte 64))))

(defun repr-default (type)
  (case type
    (:f32 '0f0)
    (:f64 '0d0)
    (t 0)))

(defun f64-from-bits-form (form)
  (let ((bits (gensym "B")) (hi (gensym "H")) (lo (gensym "L")))
    `(let* ((,bits (the (unsigned-byte 64) ,form))
            (,lo (ldb (byte 32 0) ,bits))
            (,hi (ldb (byte 32 32) ,bits)))
       (declare (type (unsigned-byte 32) ,lo ,hi))
       (sb-kernel:make-double-float
        (if (logbitp 31 ,hi) (- ,hi #x100000000) ,hi)
        ,lo))))

(defun f32-from-bits-form (form)
  (let ((bits (gensym "B")))
    `(let ((,bits (ldb (byte 32 0) (the (unsigned-byte 64) ,form))))
       (declare (type (unsigned-byte 32) ,bits))
       (sb-kernel:make-single-float
        (if (logbitp 31 ,bits) (- ,bits #x100000000) ,bits)))))

(defun f64-to-bits-form (form)
  (let ((value (gensym "F")))
    `(let ((,value (the double-float ,form)))
       (logior (ash (ldb (byte 32 0) (sb-kernel:double-float-high-bits ,value)) 32)
               (ldb (byte 32 0) (sb-kernel:double-float-low-bits ,value))))))

(defun f32-to-bits-form (form)
  (let ((value (gensym "F")))
    `(let ((,value (the single-float ,form)))
       (ldb (byte 32 0) (sb-kernel:single-float-bits ,value)))))

(defun to-bits-form (form type)
  (case type
    (:f64 (f64-to-bits-form form))
    (:f32 (f32-to-bits-form form))
    (:i32 `(ldb (byte 32 0) (the (unsigned-byte 64) ,form)))
    (t `(the (unsigned-byte 64) ,form))))

(defun from-bits-form (form type)
  (case type
    (:f64 (f64-from-bits-form form))
    (:f32 (f32-from-bits-form form))
    (:i32 `(ldb (byte 32 0) (the (unsigned-byte 64) ,form)))
    (t `(the (unsigned-byte 64) ,form))))

(defun float-arith-form (lisp-type canon left right op)
  (let ((result (gensym "R")))
    `(let ((,result (,op (the ,lisp-type ,left) (the ,lisp-type ,right))))
       (declare (type ,lisp-type ,result))
       (if (/= ,result ,result) ,canon ,result))))

(defun float-cmp-form (op lisp-type left right)
  `(if (,op (the ,lisp-type ,left) (the ,lisp-type ,right)) 1 0))

(defun fast-float-binop-form (function left right)
  (case function
    (f64-add (float-arith-form 'double-float '(sb-kernel:make-double-float #x7ff80000 0) left right '+))
    (f64-sub (float-arith-form 'double-float '(sb-kernel:make-double-float #x7ff80000 0) left right '-))
    (f64-mul (float-arith-form 'double-float '(sb-kernel:make-double-float #x7ff80000 0) left right '*))
    (f64-div (float-arith-form 'double-float '(sb-kernel:make-double-float #x7ff80000 0) left right '/))
    (f32-add (float-arith-form 'single-float '(sb-kernel:make-single-float #x7fc00000) left right '+))
    (f32-sub (float-arith-form 'single-float '(sb-kernel:make-single-float #x7fc00000) left right '-))
    (f32-mul (float-arith-form 'single-float '(sb-kernel:make-single-float #x7fc00000) left right '*))
    (f32-div (float-arith-form 'single-float '(sb-kernel:make-single-float #x7fc00000) left right '/))
    (f64-eq (float-cmp-form '= 'double-float left right))
    (f64-ne (float-cmp-form '/= 'double-float left right))
    (f64-lt (float-cmp-form '< 'double-float left right))
    (f64-gt (float-cmp-form '> 'double-float left right))
    (f64-le (float-cmp-form '<= 'double-float left right))
    (f64-ge (float-cmp-form '>= 'double-float left right))
    (f32-eq (float-cmp-form '= 'single-float left right))
    (f32-ne (float-cmp-form '/= 'single-float left right))
    (f32-lt (float-cmp-form '< 'single-float left right))
    (f32-gt (float-cmp-form '> 'single-float left right))
    (f32-le (float-cmp-form '<= 'single-float left right))
    (f32-ge (float-cmp-form '>= 'single-float left right))
    (t nil)))

(defun fast-float-unop-form (function arg)
  (case function
    (f64-neg `(- (the double-float ,arg)))
    (f64-abs `(abs (the double-float ,arg)))
    (f32-neg `(- (the single-float ,arg)))
    (f32-abs `(abs (the single-float ,arg)))
    (f64-convert-i32-s
     (let ((n (gensym "N")))
       `(float (let ((,n (ldb (byte 32 0) (the (unsigned-byte 64) ,arg))))
                 (declare (type (unsigned-byte 32) ,n))
                 (if (logbitp 31 ,n) (- ,n #x100000000) ,n))
               1d0)))
    (f64-convert-i32-u
     `(float (ldb (byte 32 0) (the (unsigned-byte 64) ,arg)) 1d0))
    (f32-convert-i32-s
     (let ((n (gensym "N")))
       `(float (let ((,n (ldb (byte 32 0) (the (unsigned-byte 64) ,arg))))
                 (declare (type (unsigned-byte 32) ,n))
                 (if (logbitp 31 ,n) (- ,n #x100000000) ,n))
               1f0)))
    (f32-convert-i32-u
     `(float (ldb (byte 32 0) (the (unsigned-byte 64) ,arg)) 1f0))
    (f64-promote-f32
     `(let ((r (float (the single-float ,arg) 1d0)))
        (declare (type double-float r))
        (if (/= r r) (sb-kernel:make-double-float #x7ff80000 0) r)))
    (f32-demote-f64
     `(let ((r (float (the double-float ,arg) 1f0)))
        (declare (type single-float r))
        (if (/= r r) (sb-kernel:make-single-float #x7fc00000) r)))
    (t nil)))

(defvar *wasm-call-names* nil)

(defun module-has-memory-p (module)
  (or (plusp (length (wasm-module-memories module)))
      (find :memory (wasm-module-imports module) :key #'wasm-import-kind)))

(defun direct-call-form (index args)
  (let ((name (and *wasm-call-names*
                   (< index (length *wasm-call-names*))
                   (aref *wasm-call-names* index))))
    (if name
        `(,name ,@args)
        `(funcall (the function
                       (svref (the simple-vector (wasm-instance-funcs *wasm-instance*))
                              ,index))
                  ,@args))))

(defun refresh-mem-form (mem-var)
  `(setq ,mem-var
         (the (simple-array (unsigned-byte 8) (*))
              (wasm-memory-bytes
               (aref (the simple-vector (wasm-instance-memories *wasm-instance*)) 0)))))

(defun global-read-form (cell type)
  (case type
    (:f64 `(wasm-gcell-f64 ,cell))
    (:f32 `(wasm-gcell-f32 ,cell))
    (t `(wasm-gcell-bits ,cell))))

(defun global-write-form (cell type value-form)
  (case type
    (:f64 (let ((f (gensym "F")) (bits (gensym "B")))
            `(let* ((,f (the double-float ,value-form))
                    (,bits ,(f64-to-bits-form f)))
               (declare (type double-float ,f)
                        (type (unsigned-byte 64) ,bits))
               (setf (wasm-gcell-f64 ,cell) ,f
                     (wasm-gcell-bits ,cell) ,bits
                     (wasm-gcell-value ,cell) ,bits))))
    (:f32 (let ((f (gensym "F")) (bits (gensym "B")))
            `(let* ((,f (the single-float ,value-form))
                    (,bits ,(f32-to-bits-form f)))
               (declare (type single-float ,f)
                        (type (unsigned-byte 32) ,bits))
               (setf (wasm-gcell-f32 ,cell) ,f
                     (wasm-gcell-bits ,cell) ,bits
                     (wasm-gcell-value ,cell) ,bits))))
    (t (let ((n (gensym "N")))
         `(let ((,n (the (unsigned-byte 64) ,value-form)))
            (setf (wasm-gcell-bits ,cell) ,n
                  (wasm-gcell-value ,cell) ,n))))))

(defun fast-load-form (op bytes address offset)
  (let ((width (case op
                 ((:i32.load8-s :i32.load8-u :i64.load8-s :i64.load8-u) 1)
                 ((:i32.load16-s :i32.load16-u :i64.load16-s :i64.load16-u) 2)
                 ((:i32.load :f32.load :i64.load32-s :i64.load32-u) 4)
                 ((:i64.load :f64.load) 8))))
    (when width
      `(with-mem-bytes (,bytes ea ,address ,offset ,width)
         ,(subst bytes 'bytes (case op
            ((:i32.load :i32.load8-u :i64.load8-u)
             (if (= width 1)
                 '(aref bytes ea)
                 '(logior (aref bytes ea)
                          (ash (aref bytes (+ ea 1)) 8)
                          (ash (aref bytes (+ ea 2)) 16)
                          (ash (aref bytes (+ ea 3)) 24))))
            ((:i32.load16-u :i64.load16-u)
             '(logior (aref bytes ea) (ash (aref bytes (+ ea 1)) 8)))
            (:i32.load8-s
             '(let ((byte (aref bytes ea)))
                (if (logbitp 7 byte) (logior byte #xffffff00) byte)))
            (:i64.load8-s
             '(let ((byte (aref bytes ea)))
                (if (logbitp 7 byte) (logior byte #xffffffffffffff00) byte)))
            ((:i32.load16-s)
             '(let ((value (logior (aref bytes ea) (ash (aref bytes (+ ea 1)) 8))))
                (if (logbitp 15 value) (logior value #xffff0000) value)))
            (:i64.load16-s
             '(let ((value (logior (aref bytes ea) (ash (aref bytes (+ ea 1)) 8))))
                (if (logbitp 15 value) (logior value #xffffffffffff0000) value)))
            (:i64.load32-u
             '(logior (aref bytes ea)
                      (ash (aref bytes (+ ea 1)) 8)
                      (ash (aref bytes (+ ea 2)) 16)
                      (ash (aref bytes (+ ea 3)) 24)))
            (:i64.load32-s
             '(let ((value (logior (aref bytes ea)
                                   (ash (aref bytes (+ ea 1)) 8)
                                   (ash (aref bytes (+ ea 2)) 16)
                                   (ash (aref bytes (+ ea 3)) 24))))
                (if (logbitp 31 value) (logior value #xffffffff00000000) value)))
            (:f32.load
             '(let ((word (logior (aref bytes ea)
                                  (ash (aref bytes (+ ea 1)) 8)
                                  (ash (aref bytes (+ ea 2)) 16)
                                  (ash (aref bytes (+ ea 3)) 24))))
                (declare (type (unsigned-byte 32) word))
                (sb-kernel:make-single-float
                 (if (logbitp 31 word) (- word #x100000000) word))))
            (:i64.load
             '(logior (aref bytes ea)
                      (ash (aref bytes (+ ea 1)) 8)
                      (ash (aref bytes (+ ea 2)) 16)
                      (ash (aref bytes (+ ea 3)) 24)
                      (ash (aref bytes (+ ea 4)) 32)
                      (ash (aref bytes (+ ea 5)) 40)
                      (ash (aref bytes (+ ea 6)) 48)
                      (ash (aref bytes (+ ea 7)) 56)))
            (:f64.load
             '(let ((lo (logior (aref bytes ea)
                                (ash (aref bytes (+ ea 1)) 8)
                                (ash (aref bytes (+ ea 2)) 16)
                                (ash (aref bytes (+ ea 3)) 24)))
                    (hi (logior (aref bytes (+ ea 4))
                                (ash (aref bytes (+ ea 5)) 8)
                                (ash (aref bytes (+ ea 6)) 16)
                                (ash (aref bytes (+ ea 7)) 24))))
                (declare (type (unsigned-byte 32) lo hi))
                (sb-kernel:make-double-float
                 (if (logbitp 31 hi) (- hi #x100000000) hi)
                 lo)))))))))

(defun fast-store-form (op bytes address offset value vtype)
  (let ((width (case op
                 ((:i32.store8 :i64.store8) 1)
                 ((:i32.store16 :i64.store16) 2)
                 ((:i32.store :f32.store :i64.store32) 4)
                 ((:i64.store :f64.store) 8))))
    (when width
      (cond ((eq vtype :f64)
             `(with-mem-bytes (,bytes ea ,address ,offset ,width)
                (let* ((f (the double-float ,value))
                       (lo (ldb (byte 32 0) (sb-kernel:double-float-low-bits f)))
                       (hi (ldb (byte 32 0) (sb-kernel:double-float-high-bits f))))
                  (declare (type double-float f)
                           (type (unsigned-byte 32) lo hi))
                  ,@(loop for index from 0 below 4
                          collect `(setf (aref ,bytes (+ ea ,index))
                                         (ldb (byte 8 ,(* 8 index)) lo)))
                  ,@(loop for index from 0 below 4
                          collect `(setf (aref ,bytes (+ ea ,(+ 4 index)))
                                         (ldb (byte 8 ,(* 8 index)) hi))))))
            ((eq vtype :f32)
             `(with-mem-bytes (,bytes ea ,address ,offset ,width)
                (let ((word (ldb (byte 32 0)
                                 (sb-kernel:single-float-bits (the single-float ,value)))))
                  (declare (type (unsigned-byte 32) word))
                  ,@(loop for index from 0 below width
                          collect `(setf (aref ,bytes (+ ea ,index))
                                         (ldb (byte 8 ,(* 8 index)) word))))))
            (t
             `(with-mem-bytes (,bytes ea ,address ,offset ,width)
                (let ((word (the (unsigned-byte 64) ,value)))
                  ,@(loop for index from 0 below width
                          collect `(setf (aref ,bytes (+ ea ,index))
                                         (ldb (byte 8 ,(* 8 index)) word))))))))))

(defun large-function-interpreter (module sig locals body)
  "Compile a long cold function as a tiny loop over its opcodes.
Unrolling thousands of loads makes SBCL fill the default heap."
  (let* ((param-vars (loop for type across (sig-params sig) collect (gensym "P")))
         (local-count (+ (length param-vars) (length locals)))
         (sigs (collect-sigs module))
         (results (length (sig-results sig))))
    `(lambda ,param-vars
       (declare (optimize (speed 1) (safety 1) (debug 0) (compilation-speed 3))
                (ignorable ,@param-vars))
       (let ((*wasm-depth* (1+ *wasm-depth*))
             (stack (make-array 64 :initial-element 0))
             (locs (make-array ,local-count :initial-element 0))
             (sp 0))
         ,@(loop for var in param-vars
                 for index from 0
                 collect `(setf (aref locs ,index) ,var))
         (when (> *wasm-depth* *wasm-call-limit*)
           (error 'wasm-exhaustion :message "call stack exhausted"))
         (loop for instr across ,body
               do (case (instr-op instr)
                    (:end)
                    (:i32.const
                     (setf (aref stack sp) (i32 (instr-a instr)))
                     (incf sp))
                    (:i64.const
                     (setf (aref stack sp) (i64 (instr-a instr)))
                     (incf sp))
                    (:local.get
                     (setf (aref stack sp) (aref locs (instr-a instr)))
                     (incf sp))
                    (:local.set
                     (decf sp)
                     (setf (aref locs (instr-a instr)) (aref stack sp)))
                    (:local.tee
                     (setf (aref locs (instr-a instr)) (aref stack (1- sp))))
                    (:i32.load
                     (decf sp)
                     (setf (aref stack sp)
                           (load-i32 (aref (wasm-instance-memories *wasm-instance*) 0)
                                     (aref stack sp) (instr-b instr)))
                     (incf sp))
                    (:i64.load
                     (decf sp)
                     (setf (aref stack sp)
                           (load-i64 (aref (wasm-instance-memories *wasm-instance*) 0)
                                     (aref stack sp) (instr-b instr)))
                     (incf sp))
                    (:i32.store
                     (let ((value (aref stack (1- sp)))
                           (addr (aref stack (- sp 2))))
                       (store-i32 (aref (wasm-instance-memories *wasm-instance*) 0)
                                  addr (instr-b instr) value)
                       (decf sp 2)))
                    (:i64.store
                     (let ((value (aref stack (1- sp)))
                           (addr (aref stack (- sp 2))))
                       (store-i64 (aref (wasm-instance-memories *wasm-instance*) 0)
                                  addr (instr-b instr) value)
                       (decf sp 2)))
                    (:call
                     (let* ((target (aref ,sigs (instr-a instr)))
                            (nparams (length (sig-params target)))
                            (nresults (length (sig-results target))))
                       (decf sp nparams)
                       (let ((results
                               (multiple-value-list
                                (apply (svref (wasm-instance-funcs *wasm-instance*)
                                              (instr-a instr))
                                       (loop for index from sp below (+ sp nparams)
                                             collect (aref stack index))))))
                         (loop for value in results
                               for index from 0 below nresults
                               do (setf (aref stack (+ sp index)) value))
                         (incf sp nresults))))
                    (t (error "unsupported opcode ~A" (instr-op instr)))))
         (values ,@(loop for index from 0 below results
                         collect `(aref stack ,index)))))))

(defun translate-function (module sig locals body)
  (let* ((code nil)
        (frames nil)
        (hoisted nil)
        (ht 0)
        (max-ht 1)
        (reachable t)
        ;; A few hundred typed locals make SBCL's control stack overflow
        ;; while it compiles the function (skip-stack-guard-page). quickjs
        ;; wasm stays under 64 locals, so it keeps the typed path.
        (fast (and (<= (+ (length (sig-params sig)) (length locals)) 64)
                   (numeric-function-p module sig locals body)))
        (param-vars (loop for type across (sig-params sig) collect (gensym "P")))
        (param-count (length param-vars))
        (local-count (+ param-count (length locals)))
        (all-types (append (coerce (sig-params sig) 'list) locals))
        (local-names (when fast
                       (coerce (loop repeat local-count collect (gensym "L")) 'vector)))
        (stypes (make-array 8192 :initial-element :i32))
        (needs-f32 (member :f32 all-types))
        (needs-f64 (member :f64 all-types))
        (needs-mem (module-has-memory-p module))
        (mem-var (gensym "MEM"))
        (gcells (make-hash-table))
        (sigs (collect-sigs module)))
    (labels ((tag () (gensym "LBL"))
             (temp (type)
               (let ((symbol (gensym "T")))
                 (push (cons symbol type) hoisted)
                 symbol))
             (scratch () (gensym "S"))
             (emit (form) (push form code))
             (note (index type)
               (when fast
                 (setf (aref stypes index) type)
                 (case type
                   (:f32 (setf needs-f32 t))
                   (:f64 (setf needs-f64 t)))))
             (dest-slot (type index)
               (if fast
                   (ecase type
                     ((:i32 :i64) `(aref istack ,index))
                     (:f32 `(aref f32stack ,index))
                     (:f64 `(aref f64stack ,index)))
                   `(aref stack ,index)))
             (slot (index)
               (if fast (dest-slot (aref stypes index) index) `(aref stack ,index)))
             (local-form (index)
               (if fast (aref local-names index) `(aref locs ,index)))
             (gcell (index)
               (or (gethash index gcells)
                   (setf (gethash index gcells) (gensym "GC"))))
             (bump (n)
               (incf ht n)
               (setf max-ht (max max-ht ht)))
             (push-form (form &optional (type :i32))
               (when reachable
                 (note ht type)
                 (emit `(setf ,(slot ht) ,form))
                 (bump 1)))
             (unop (function op)
               (when reachable
                 (let* ((spec (unary-type op))
                        (arg (slot (1- ht)))
                        (fast-form (and fast (or (fast-unop-form function arg)
                                                (fast-float-unop-form function arg))))
                        (res (cdr spec))
                        (form (or fast-form
                                  (if fast
                                      (from-bits-form
                                       `(,function ,(to-bits-form arg (car spec)))
                                       res)
                                      `(,function ,arg)))))
                   (note (1- ht) res)
                   (emit `(setf ,(slot (1- ht)) ,form)))))
             (binop (function op)
               (when reachable
                 (let* ((spec (binary-type op))
                        (left (- ht 2))
                        (lhs (slot left))
                        (rhs (slot (1+ left)))
                        (fast-form (and fast (or (fast-binop-form function lhs rhs)
                                                (fast-float-binop-form function lhs rhs))))
                        (res (third spec))
                        (form (or fast-form
                                  (if fast
                                      (from-bits-form
                                       `(,function ,(to-bits-form lhs (first spec))
                                                   ,(to-bits-form rhs (second spec)))
                                       res)
                                      `(,function ,lhs ,rhs)))))
                   (decf ht)
                   (note left res)
                   (emit `(setf ,(slot left) ,form)))))
             (copy-form (base arity)
               (let* ((types (loop for index from (- ht arity) below ht
                                   collect (if fast (aref stypes index) :i64)))
                      (temps (loop for type in types collect (scratch)))
                      (sources (loop for index from (- ht arity) below ht collect index))
                      (dests (loop for index from base below (+ base arity) collect index)))
                 `(let ,(mapcar (lambda (temp source) `(,temp ,(slot source))) temps sources)
                    ,@(when (and fast temps)
                        `((declare ,@(loop for temp in temps
                                           for type in types
                                           collect `(type ,(repr-lisp-type type) ,temp)))))
                    ,@(mapcar (lambda (temp dest type)
                                `(setf ,(dest-slot type dest) ,temp))
                              temps dests types))))
             (branch-to (target)
               (when reachable
                 (emit `(progn ,(copy-form (cframe-base target) (cframe-br-arity target))
                               (go ,(cframe-br-label target)))))
               (setf reachable nil))
             (memory ()
               (if fast
                   `(aref (the simple-vector (wasm-instance-memories *wasm-instance*)) 0)
                   `(aref (wasm-instance-memories *wasm-instance*) 0)))
             (table (index)
               (if fast
                   `(aref (the simple-vector (wasm-instance-tables *wasm-instance*)) ,index)
                   `(aref (wasm-instance-tables *wasm-instance*) ,index)))
             (global (index)
               (if fast
                   `(aref (the simple-vector (wasm-instance-globals *wasm-instance*)) ,index)
                   `(aref (wasm-instance-globals *wasm-instance*) ,index)))
             (restore-params (current)
               (loop for temp in (cframe-param-temps current)
                     for type in (cframe-param-types current)
                     for index from (cframe-base current)
                     do (note index type)
                        (emit `(setf ,(slot index) ,temp))))
             (finish (current)
               (when (and (eq (cframe-kind current) :if)
                          (not (cframe-saw-else current))
                          (cframe-entry-reachable current))
                 (when reachable (emit `(go ,(cframe-end-label current))))
                 (emit (cframe-else-label current))
                 (restore-params current))
               (when (cframe-entry-reachable current)
                 (emit (cframe-end-label current))
                 (setf reachable t
                       ht (+ (cframe-base current) (cframe-nresults current)))
                 (loop for type in (cframe-result-types current)
                       for index from (cframe-base current)
                       do (note index type)))))
      (when (and (not fast) (> (length body) 400))
        (return-from translate-function
          (large-function-interpreter module sig locals body)))
      (let ((end (tag)))
        (push (make-cframe :kind :func :base 0 :nparams 0
                           :nresults (length (sig-results sig))
                           :br-label end :br-arity (length (sig-results sig))
                           :end-label end :entry-reachable t
                           :param-types nil
                           :result-types (coerce (sig-results sig) 'list))
              frames))
      (loop for item across body do
        (let ((op (instr-op item)))
          (case op
            (:unreachable
             (when reachable (emit `(wasm-trap "unreachable")))
             (setf reachable nil))
            (:nop)
            (:drop (when reachable (decf ht)))
            (:select
             (when reachable
               (let ((cond (- ht 1)) (second (- ht 2)) (first (- ht 3)))
                 (emit `(setf ,(slot first)
                              (if (zerop ,(slot cond)) ,(slot second) ,(slot first))))
                 (decf ht 2))))
            (:select-t
             (when reachable
               (let ((cond (- ht 1)) (second (- ht 2)) (first (- ht 3)))
                 (emit `(setf ,(slot first)
                              (if (zerop ,(slot cond)) ,(slot second) ,(slot first))))
                 (decf ht 2))))
            ((:block :loop :if)
             (let* ((parts (block-parts module (instr-a item)))
                    (param-types (coerce (sig-params parts) 'list))
                    (result-types (coerce (sig-results parts) 'list))
                    (nparams (length param-types))
                    (nresults (length result-types))
                    (end (tag))
                    (else (when (eq op :if) (tag)))
                    (start (when (eq op :loop) (tag))))
               (when (and (eq op :if) reachable) (decf ht))
               (let ((base (if reachable (- ht nparams) 0))
                     (temps (when (eq op :if)
                              (loop for type in param-types collect (temp type)))))
                 (when (and (eq op :if) reachable)
                   (loop for temp in temps for index from base do
                     (emit `(setf ,temp ,(slot index))))
                   (emit `(when (zerop ,(slot (+ base nparams))) (go ,else))))
                 (when (and (eq op :loop) reachable) (emit start))
                 (push (make-cframe :kind op :base base :nparams nparams
                                    :nresults nresults
                                    :br-label (if (eq op :loop) start end)
                                    :br-arity (if (eq op :loop) nparams nresults)
                                    :end-label end :else-label else
                                    :entry-reachable reachable
                                    :param-temps temps
                                    :param-types param-types
                                    :result-types result-types)
                       frames))))
            (:else
             (let ((current (car frames)))
               (when (cframe-entry-reachable current)
                 (when reachable (emit `(go ,(cframe-end-label current))))
                 (emit (cframe-else-label current))
                 (setf reachable t
                       ht (+ (cframe-base current) (cframe-nparams current)))
                 (restore-params current))
               (setf (cframe-saw-else current) t)))
            (:end
             (finish (pop frames)))
            (:br (branch-to (nth (instr-a item) frames)))
            (:br-if
             (when reachable
               (let ((target (nth (instr-a item) frames))
                     (cond (1- ht)))
                 (decf ht)
                 (emit `(when (not (zerop ,(slot cond)))
                          ,(copy-form (cframe-base target) (cframe-br-arity target))
                          (go ,(cframe-br-label target)))))))
            (:br-table
             (when reachable
               (let* ((cond (1- ht))
                      (default (nth (instr-b item) frames))
                      (labels (loop for index across (instr-a item)
                                    collect (nth index frames))))
                 (decf ht)
                 (let ((seen (make-hash-table :test #'eq))
                       (arms nil)
                       (next 0))
                   (flet ((arm (frame)
                            (or (gethash frame seen)
                                (let ((id next))
                                  (incf next)
                                  (setf (gethash frame seen) id)
                                  (push `(,id (progn
                                                ,(copy-form (cframe-base frame)
                                                            (cframe-br-arity frame))
                                                (go ,(cframe-br-label frame))))
                                        arms)
                                  id))))
                     (let ((vector (coerce (mapcar #'arm labels) 'vector)))
                       (if (zerop (length vector))
                           (emit `(progn ,(copy-form (cframe-base default)
                                                     (cframe-br-arity default))
                                         (go ,(cframe-br-label default))))
                           (emit `(let ((idx ,(slot cond)))
                                    (declare (ignorable idx))
                                    (case (if (< idx ,(length vector))
                                              (svref ,vector idx)
                                              ,(arm default))
                                      ,@(nreverse arms))))))))))
             (setf reachable nil))
            (:return (branch-to (car (last frames))))
            (:call
             (when reachable
               (let* ((sig (aref sigs (instr-a item)))
                      (param-types (coerce (sig-params sig) 'list))
                      (result-types (coerce (sig-results sig) 'list))
                      (nparams (length param-types))
                      (nresults (length result-types))
                      (args (loop for type in param-types
                                  for index from (- ht nparams)
                                  collect (if fast
                                              (to-bits-form (slot index) type)
                                              (slot index))))
                      (dest (- ht nparams))
                      (temps (loop repeat nresults collect (scratch)))
                      (call (direct-call-form (instr-a item) args)))
                 (if (zerop nresults)
                     (emit call)
                     (emit `(multiple-value-bind ,temps
                                ,call
                              ,@(loop for temp in temps
                                      for type in result-types
                                      for index from dest
                                      do (note index type)
                                      collect `(setf ,(slot index)
                                                     ,(if fast
                                                          (from-bits-form temp type)
                                                          temp))))))
                 (setf ht (+ dest nresults))
                 (setf max-ht (max max-ht ht))
                 (when (and fast needs-mem)
                   (emit (refresh-mem-form mem-var))))))
            (:call-indirect
             (let* ((sig (type-at module (instr-a item)))
                    (param-types (coerce (sig-params sig) 'list))
                    (result-types (coerce (sig-results sig) 'list))
                    (nparams (length param-types))
                    (nresults (length result-types)))
               (when reachable
                 (let ((index-form (slot (1- ht)))
                       (args (loop for type in param-types
                                   for slot-index from (- ht 1 nparams) below (1- ht)
                                   collect (if fast
                                               (to-bits-form (slot slot-index) type)
                                               (slot slot-index))))
                       (dest (- ht 1 nparams))
                       (temps (loop repeat nresults collect (scratch)))
                       (fn (gensym "FN"))
                       (owner (gensym "OWN")))
                   (decf ht)
                   (emit `(multiple-value-bind (,fn ,owner)
                              (indirect-callee *wasm-instance*
                                               ,(instr-b item)
                                               ,(instr-a item)
                                               ,index-form)
                            (let ((*wasm-instance* ,owner))
                              ,(if (zerop nresults)
                                   `(funcall (the function ,fn) ,@args)
                                   `(multiple-value-bind ,temps
                                        (funcall (the function ,fn) ,@args)
                                      ,@(loop for temp in temps
                                              for type in result-types
                                              for index from dest
                                              do (note index type)
                                              collect `(setf ,(slot index)
                                                             ,(if fast
                                                                  (from-bits-form temp type)
                                                                  temp))))))))
                   (setf ht (+ dest nresults))
                   (setf max-ht (max max-ht ht))
                   (when (and fast needs-mem)
                     (emit (refresh-mem-form mem-var)))))))
            (:local.get (push-form (local-form (instr-a item))
                                   (if fast (nth (instr-a item) all-types) :i32)))
            (:local.set
             (when reachable
               (emit `(setf ,(local-form (instr-a item)) ,(slot (1- ht))))
               (decf ht)))
            (:local.tee
             (when reachable
               (emit `(setf ,(local-form (instr-a item)) ,(slot (1- ht))))))
            (:global.get
             (let ((type (car (global-type-at module (instr-a item)))))
               (if fast
                   (push-form (global-read-form (gcell (instr-a item)) type) type)
                   (push-form `(wasm-gcell-value ,(global (instr-a item)))))))
            (:global.set
             (when reachable
               (let ((type (car (global-type-at module (instr-a item)))))
                 (if fast
                     (emit (global-write-form (gcell (instr-a item)) type (slot (1- ht))))
                     (emit `(gcell-store ,(global (instr-a item)) ',type ,(slot (1- ht))))))
               (decf ht)))
            (:table.get
             (when reachable
               (emit `(setf ,(slot (1- ht))
                            (table-get ,(table (instr-a item)) ,(slot (1- ht)))))))
            (:table.set
             (when reachable
               (emit `(table-set ,(table (instr-a item)) ,(slot (- ht 2)) ,(slot (1- ht))))
               (decf ht 2)))
            (:table.size (push-form `(table-size ,(table (instr-a item)))))
            (:table.grow
             (when reachable
               (emit `(setf ,(slot (- ht 2))
                            (table-grow ,(table (instr-a item))
                                        ,(slot (- ht 2)) ,(slot (1- ht)))))
               (decf ht)))
            (:table.fill
             (when reachable
               (emit `(table-fill ,(table (instr-a item)) ,(slot (- ht 3))
                                  ,(slot (- ht 2)) ,(slot (1- ht))))
               (decf ht 3)))
            (:table.copy
             (when reachable
               (emit `(table-copy ,(table (instr-a item)) ,(table (instr-b item))
                                  ,(slot (- ht 3)) ,(slot (- ht 2)) ,(slot (1- ht))))
               (decf ht 3)))
            (:table.init
             (when reachable
               (emit `(table-init ,(table (instr-a item))
                                  (wasm-seg-items (aref (wasm-instance-elems *wasm-instance*)
                                                        ,(instr-b item)))
                                  ,(slot (- ht 3)) ,(slot (- ht 2)) ,(slot (1- ht))))
               (decf ht 3)))
            (:elem.drop
             (when reachable
               (emit `(drop-seg (aref (wasm-instance-elems *wasm-instance*) ,(instr-a item))))))
            (:memory.size (push-form `(memory-size ,(memory))))
            (:memory.grow
             (when reachable
               (emit `(setf ,(slot (1- ht)) (memory-grow ,(memory) ,(slot (1- ht)))))
               (when (and fast needs-mem) (emit (refresh-mem-form mem-var)))))
            ((:memory.fill :memory.copy)
             (when reachable
               (emit `(,(if (eq op :memory.fill) 'memory-fill 'memory-copy)
                       ,(memory) ,(slot (- ht 3)) ,(slot (- ht 2)) ,(slot (1- ht))))
               (decf ht 3)))
            (:memory.init
             (when reachable
               (emit `(memory-init ,(memory)
                                   (wasm-seg-items (aref (wasm-instance-datas *wasm-instance*)
                                                         ,(instr-a item)))
                                   ,(slot (- ht 3)) ,(slot (- ht 2)) ,(slot (1- ht))))
               (decf ht 3)))
            (:data.drop
             (when reachable
               (emit `(drop-seg (aref (wasm-instance-datas *wasm-instance*) ,(instr-a item))))))
            (:i32.const (push-form (i32 (instr-a item)) :i32))
            (:i64.const (push-form (i64 (instr-a item)) :i64))
            (:f32.const (if fast
                            (push-form (f32-from-bits-form (instr-a item)) :f32)
                            (push-form (instr-a item))))
            (:f64.const (if fast
                            (push-form (f64-from-bits-form (instr-a item)) :f64)
                            (push-form (instr-a item))))
            (:ref.null (push-form (if (eq (instr-a item) :funcref) '+null-funcref+ '+null-externref+)))
            (:ref.is-null
             (when reachable
               (emit `(setf ,(slot (1- ht)) (ref-is-null ,(slot (1- ht)))))))
            (:ref.func (push-form `(make-wasm-funcref :instance *wasm-instance*
                                                       :index ,(instr-a item))))
            ((:i32.load :i64.load :f32.load :f64.load :i32.load8-s :i32.load8-u
              :i32.load16-s :i32.load16-u :i64.load8-s :i64.load8-u :i64.load16-s
              :i64.load16-u :i64.load32-s :i64.load32-u)
             (when reachable
               (let* ((addr (slot (1- ht)))
                      (rtype (load-result op))
                      (fast-form (and fast (fast-load-form op mem-var addr (instr-b item)))))
                 (note (1- ht) (or rtype :i32))
                 (emit `(setf ,(slot (1- ht))
                              ,(or fast-form
                                   `(,(load-name op) ,(memory) ,addr ,(instr-b item))))))))
            ((:i32.store :i64.store :f32.store :f64.store :i32.store8 :i32.store16
              :i64.store8 :i64.store16 :i64.store32)
             (when reachable
               (let* ((addr (slot (- ht 2)))
                      (vtype (if fast (aref stypes (1- ht)) :i64))
                      (value (slot (1- ht)))
                      (fast-form (and fast
                                      (fast-store-form op mem-var addr (instr-b item)
                                                       value vtype))))
                 (emit (or fast-form
                           `(,(store-name op) ,(memory) ,addr ,(instr-b item)
                              ,(if (and fast (member vtype '(:f32 :f64)))
                                   (to-bits-form value vtype)
                                   value))))
               (decf ht 2))))
            (t (let ((function (or (simple-function op)
                                   (error "unsupported opcode ~A" op))))
                 (if (unary-function-p op)
                     (unop function op)
                     (binop function op)))))))
      (emit `(return-from wasm-fn
               (values ,@(loop for type in (coerce (sig-results sig) 'list)
                               for index from 0
                               collect (if fast
                                           (to-bits-form (slot index) type)
                                           (slot index))))))
      (let* ((param-inits (unless fast
                              (loop for var in param-vars
                                    for index from 0
                                    collect `(setf (aref locs ,index) ,var))))
             (local-inits (unless fast
                            (loop for type in locals
                                  for index from param-count
                                  for default = (default-for type)
                                  unless (eql default 0)
                                    collect `(setf (aref locs ,index) ,default))))
             (gcell-pairs (loop for index being the hash-key of gcells
                                  using (hash-value var)
                                collect (cons index var)))
             (local-bindings
               (when fast
                 (loop for index from 0 below local-count
                       for type = (nth index all-types)
                       collect `(,(aref local-names index)
                                 ,(if (< index param-count)
                                      (from-bits-form (nth index param-vars) type)
                                      (repr-default type))))))
             (hoist-bindings
               (loop for (var . type) in hoisted
                     collect `(,var ,(if fast (repr-default type) 0))))
             (form (if fast
                       `(lambda ,param-vars
                          (declare (optimize (speed 3) (safety 0) (debug 0))
                                   (type wasm-instance *wasm-instance*)
                                   ,@(when param-vars
                                       `((type (unsigned-byte 64) ,@param-vars)))
                                   (ignorable ,@param-vars *wasm-instance*))
                          (let ((*wasm-depth* (1+ *wasm-depth*))
                                (istack (make-array ,max-ht
                                                    :element-type '(unsigned-byte 64)
                                                    :initial-element 0))
                                ,@(when needs-f32
                                    `((f32stack (make-array ,max-ht
                                                            :element-type 'single-float
                                                            :initial-element 0f0))))
                                ,@(when needs-f64
                                    `((f64stack (make-array ,max-ht
                                                            :element-type 'double-float
                                                            :initial-element 0d0))))
                                ,@(when needs-mem
                                    `((,mem-var
                                       (the (simple-array (unsigned-byte 8) (*))
                                            (wasm-memory-bytes
                                             (aref (the simple-vector
                                                        (wasm-instance-memories
                                                         *wasm-instance*))
                                                   0))))))
                                ,@(loop for (index . var) in gcell-pairs
                                        collect `(,var (aref (the simple-vector
                                                                   (wasm-instance-globals
                                                                    *wasm-instance*))
                                                             ,index)))
                                ,@local-bindings
                                ,@hoist-bindings)
                            (declare (type (simple-array (unsigned-byte 64) (*)) istack)
                                     ,@(when needs-f32
                                         '((type (simple-array single-float (*)) f32stack)))
                                     ,@(when needs-f64
                                         '((type (simple-array double-float (*)) f64stack)))
                                     ,@(when needs-mem
                                         `((type (simple-array (unsigned-byte 8) (*)) ,mem-var)))
                                     ,@(loop for index from 0 below local-count
                                             collect `(type ,(repr-lisp-type (nth index all-types))
                                                            ,(aref local-names index)))
                                     ,@(loop for (var . type) in hoisted
                                             collect `(type ,(repr-lisp-type type) ,var))
                                     ,@(loop for (index . var) in gcell-pairs
                                             collect `(type wasm-gcell ,var))
                                     (ignorable istack
                                                ,@(when needs-f32 '(f32stack))
                                                ,@(when needs-f64 '(f64stack))
                                                ,@(when needs-mem (list mem-var))
                                                ,@(when local-names
                                                    (coerce local-names 'list))
                                                ,@(mapcar #'car hoisted)
                                                ,@(mapcar #'cdr gcell-pairs)))
                            (when (> *wasm-depth* *wasm-call-limit*)
                              (error 'wasm-exhaustion :message "call stack exhausted"))
                            (block wasm-fn
                              (tagbody ,@(nreverse code)))))
                       `(lambda ,param-vars
                          (declare (optimize (speed 1) (safety 1)
                                             (debug 0) (compilation-speed 3))
                                   (notinline aref svref load-i64 store-i64
                                              load-i32 store-i32 load-f32 store-f32
                                              load-f64 store-f64
                                              wasm-instance-memories wasm-instance-funcs)
                                   (ignorable ,@param-vars))
                          (let ((*wasm-depth* (1+ *wasm-depth*))
                                (stack (make-array ,max-ht :initial-element 0))
                                (locs (make-array ,local-count :initial-element 0))
                                ,@hoist-bindings)
                            (declare (ignorable ,@(mapcar #'car hoisted) stack locs))
                            ,@param-inits
                            ,@local-inits
                            (when (> *wasm-depth* *wasm-call-limit*)
                              (error 'wasm-exhaustion :message "call stack exhausted"))
                            (block wasm-fn
                              (tagbody ,@(nreverse code))))))))
        form))))

(defun compile-function (module sig locals body)
  (let ((form (translate-function module sig locals body)))
    ;; A large spec function's copy propagation fills the default 1GB heap
    ;; if earlier modules are still tenured. Callers that must stay inside
    ;; that heap compile one module per process. Warnings are noise there.
    (handler-bind ((warning #'muffle-warning)
                   (sb-ext:compiler-note #'muffle-warning))
      (compile nil form))))

(defun load-name (op)
  (case op
    (:i32.load 'load-i32) (:i64.load 'load-i64) (:f32.load 'load-f32) (:f64.load 'load-f64)
    (:i32.load8-s 'load-i32-8-s) (:i32.load8-u 'load-i32-8-u)
    (:i32.load16-s 'load-i32-16-s) (:i32.load16-u 'load-i32-16-u)
    (:i64.load8-s 'load-i64-8-s) (:i64.load8-u 'load-i64-8-u)
    (:i64.load16-s 'load-i64-16-s) (:i64.load16-u 'load-i64-16-u)
    (:i64.load32-s 'load-i64-32-s) (:i64.load32-u 'load-i64-32-u)))

(defun store-name (op)
  (case op
    (:i32.store 'store-i32) (:i64.store 'store-i64)
    (:f32.store 'store-f32) (:f64.store 'store-f64)
    (:i32.store8 'store-i32-8) (:i32.store16 'store-i32-16)
    (:i64.store8 'store-i64-8) (:i64.store16 'store-i64-16)
    (:i64.store32 'store-i64-32)))

(defun simple-function (op)
  (case op
    (:i32.eqz 'i32-eqz) (:i64.eqz 'i64-eqz)
    (:i32.eq 'i32-eq) (:i32.ne 'i32-ne) (:i64.eq 'i64-eq) (:i64.ne 'i64-ne)
    (:i32.lt-s 'i32-lt-s) (:i32.lt-u 'i32-lt-u) (:i32.gt-s 'i32-gt-s) (:i32.gt-u 'i32-gt-u)
    (:i32.le-s 'i32-le-s) (:i32.le-u 'i32-le-u) (:i32.ge-s 'i32-ge-s) (:i32.ge-u 'i32-ge-u)
    (:i64.lt-s 'i64-lt-s) (:i64.lt-u 'i64-lt-u) (:i64.gt-s 'i64-gt-s) (:i64.gt-u 'i64-gt-u)
    (:i64.le-s 'i64-le-s) (:i64.le-u 'i64-le-u) (:i64.ge-s 'i64-ge-s) (:i64.ge-u 'i64-ge-u)
    (:f32.eq 'f32-eq) (:f32.ne 'f32-ne) (:f32.lt 'f32-lt) (:f32.gt 'f32-gt)
    (:f32.le 'f32-le) (:f32.ge 'f32-ge)
    (:f64.eq 'f64-eq) (:f64.ne 'f64-ne) (:f64.lt 'f64-lt) (:f64.gt 'f64-gt)
    (:f64.le 'f64-le) (:f64.ge 'f64-ge)
    (:i32.clz 'i32-clz) (:i32.ctz 'i32-ctz) (:i32.popcnt 'logcount)
    (:i64.clz 'i64-clz) (:i64.ctz 'i64-ctz) (:i64.popcnt 'logcount)
    (:i32.add 'i32-add) (:i32.sub 'i32-sub) (:i32.mul 'i32-mul)
    (:i32.div-s 'i32-div-s) (:i32.div-u 'i32-div-u) (:i32.rem-s 'i32-rem-s) (:i32.rem-u 'i32-rem-u)
    (:i32.and 'i32-and) (:i32.or 'i32-or) (:i32.xor 'i32-xor)
    (:i32.shl 'i32-shl) (:i32.shr-s 'i32-shr-s) (:i32.shr-u 'i32-shr-u)
    (:i32.rotl 'i32-rotl) (:i32.rotr 'i32-rotr)
    (:i64.add 'i64-add) (:i64.sub 'i64-sub) (:i64.mul 'i64-mul)
    (:i64.div-s 'i64-div-s) (:i64.div-u 'i64-div-u) (:i64.rem-s 'i64-rem-s) (:i64.rem-u 'i64-rem-u)
    (:i64.and 'i64-and) (:i64.or 'i64-or) (:i64.xor 'i64-xor)
    (:i64.shl 'i64-shl) (:i64.shr-s 'i64-shr-s) (:i64.shr-u 'i64-shr-u)
    (:i64.rotl 'i64-rotl) (:i64.rotr 'i64-rotr)
    (:f32.abs 'f32-abs) (:f32.neg 'f32-neg) (:f32.sqrt 'f32-sqrt)
    (:f32.add 'f32-add) (:f32.sub 'f32-sub) (:f32.mul 'f32-mul) (:f32.div 'f32-div)
    (:f32.min 'f32-min) (:f32.max 'f32-max) (:f32.copysign 'f32-copysign)
    (:f64.abs 'f64-abs) (:f64.neg 'f64-neg) (:f64.sqrt 'f64-sqrt)
    (:f64.add 'f64-add) (:f64.sub 'f64-sub) (:f64.mul 'f64-mul) (:f64.div 'f64-div)
    (:f64.min 'f64-min) (:f64.max 'f64-max) (:f64.copysign 'f64-copysign)
    (:f32.ceil 'f32-ceil) (:f32.floor 'f32-floor) (:f32.trunc 'f32-trunc) (:f32.nearest 'f32-nearest)
    (:f64.ceil 'f64-ceil) (:f64.floor 'f64-floor) (:f64.trunc 'f64-trunc) (:f64.nearest 'f64-nearest)
    (:i32.wrap-i64 'i32-wrap-i64)
    (:i32.trunc-f32-s 'i32-trunc-f32-s) (:i32.trunc-f32-u 'i32-trunc-f32-u)
    (:i32.trunc-f64-s 'i32-trunc-f64-s) (:i32.trunc-f64-u 'i32-trunc-f64-u)
    (:i32.trunc-sat-f32-s 'i32-trunc-sat-f32-s) (:i32.trunc-sat-f32-u 'i32-trunc-sat-f32-u)
    (:i32.trunc-sat-f64-s 'i32-trunc-sat-f64-s) (:i32.trunc-sat-f64-u 'i32-trunc-sat-f64-u)
    (:i64.extend-i32-s 'i64-extend-i32-s) (:i64.extend-i32-u 'i64-extend-i32-u)
    (:i64.trunc-f32-s 'i64-trunc-f32-s) (:i64.trunc-f32-u 'i64-trunc-f32-u)
    (:i64.trunc-f64-s 'i64-trunc-f64-s) (:i64.trunc-f64-u 'i64-trunc-f64-u)
    (:i64.trunc-sat-f32-s 'i64-trunc-sat-f32-s) (:i64.trunc-sat-f32-u 'i64-trunc-sat-f32-u)
    (:i64.trunc-sat-f64-s 'i64-trunc-sat-f64-s) (:i64.trunc-sat-f64-u 'i64-trunc-sat-f64-u)
    (:f32.convert-i32-s 'f32-convert-i32-s) (:f32.convert-i32-u 'f32-convert-i32-u)
    (:f32.convert-i64-s 'f32-convert-i64-s) (:f32.convert-i64-u 'f32-convert-i64-u)
    (:f32.demote-f64 'f32-demote-f64)
    (:f64.convert-i32-s 'f64-convert-i32-s) (:f64.convert-i32-u 'f64-convert-i32-u)
    (:f64.convert-i64-s 'f64-convert-i64-s) (:f64.convert-i64-u 'f64-convert-i64-u)
    (:f64.promote-f32 'f64-promote-f32)
    (:i32.reinterpret-f32 'identity) (:f32.reinterpret-i32 'identity)
    (:i64.reinterpret-f64 'identity) (:f64.reinterpret-i64 'identity)
    (:i32.extend8-s 'i32-extend8-s) (:i32.extend16-s 'i32-extend16-s)
    (:i64.extend8-s 'i64-extend8-s) (:i64.extend16-s 'i64-extend16-s)
    (:i64.extend32-s 'i64-extend32-s)))

(defun unary-function-p (op)
  (member op '(:i32.eqz :i64.eqz :i32.clz :i32.ctz :i32.popcnt :i64.clz :i64.ctz :i64.popcnt
               :f32.abs :f32.neg :f32.ceil :f32.floor :f32.trunc :f32.nearest :f32.sqrt
               :f64.abs :f64.neg :f64.ceil :f64.floor :f64.trunc :f64.nearest :f64.sqrt
               :i32.wrap-i64 :i32.trunc-f32-s :i32.trunc-f32-u :i32.trunc-f64-s :i32.trunc-f64-u
               :i32.trunc-sat-f32-s :i32.trunc-sat-f32-u :i32.trunc-sat-f64-s :i32.trunc-sat-f64-u
               :i64.extend-i32-s :i64.extend-i32-u
               :i64.trunc-f32-s :i64.trunc-f32-u :i64.trunc-f64-s :i64.trunc-f64-u
               :i64.trunc-sat-f32-s :i64.trunc-sat-f32-u :i64.trunc-sat-f64-s :i64.trunc-sat-f64-u
               :f32.convert-i32-s :f32.convert-i32-u :f32.convert-i64-s :f32.convert-i64-u
               :f32.demote-f64
               :f64.convert-i32-s :f64.convert-i32-u :f64.convert-i64-s :f64.convert-i64-u
               :f64.promote-f32
               :i32.reinterpret-f32 :i64.reinterpret-f64 :f32.reinterpret-i32 :f64.reinterpret-i64
               :i32.extend8-s :i32.extend16-s :i64.extend8-s :i64.extend16-s :i64.extend32-s)))

(defun f32-ceil (bits) (if (f32-nan-p bits) +f32-canon+ (f32-unop bits #'fceiling)))
(defun f32-floor (bits) (if (f32-nan-p bits) +f32-canon+ (f32-unop bits #'ffloor)))
(defun f32-trunc (bits) (if (f32-nan-p bits) +f32-canon+ (f32-unop bits #'ftruncate)))
(defun f64-ceil (bits) (if (f64-nan-p bits) +f64-canon+ (f64-unop bits #'fceiling)))
(defun f64-floor (bits) (if (f64-nan-p bits) +f64-canon+ (f64-unop bits #'ffloor)))
(defun f64-trunc (bits) (if (f64-nan-p bits) +f64-canon+ (f64-unop bits #'ftruncate)))
(defun f32-add (a b) (f32-binop a b #'+))
(defun f32-sub (a b) (f32-binop a b #'-))
(defun f32-mul (a b) (f32-binop a b #'*))
(defun f32-div (a b) (f32-binop a b #'/))
(defun f64-add (a b) (f64-binop a b #'+))
(defun f64-sub (a b) (f64-binop a b #'-))
(defun f64-mul (a b) (f64-binop a b #'*))
(defun f64-div (a b) (f64-binop a b #'/))
