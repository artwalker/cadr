(in-package #:cadr-wasm)

(define-condition wasm-error (error)
  ((message :initarg :message :reader wasm-message))
  (:report (lambda (condition stream)
             (write-string (wasm-message condition) stream))))

(define-condition wasm-malformed (wasm-error) ())
(define-condition wasm-invalid (wasm-error) ())
(define-condition wasm-unlinkable (wasm-error) ())
(define-condition wasm-trap (wasm-error) ())
(define-condition wasm-exhaustion (wasm-trap) ())

(defun wasm-fail (type message)
  (error type :message message))

(defun wasm-trap (message)
  (wasm-fail 'wasm-trap message))

(defstruct (wasm-null (:constructor wasm-null (kind))) kind)

(defparameter +null-funcref+ (wasm-null :funcref))
(defparameter +null-externref+ (wasm-null :externref))

(defstruct (instr (:constructor instr (op &optional a b c)))
  op a b c)

(defstruct wasm-import module name kind type)

(defstruct wasm-export name kind index)

(defstruct wasm-global-def type mutable init)

(defstruct wasm-table-type element min max)
(defstruct wasm-memory-type min max)

(defstruct wasm-elem type mode table offset inits)
(defstruct wasm-data mode memory offset bytes)

(defstruct wasm-code locals body)

(defstruct wasm-module
  types
  imports
  func-types
  tables
  memories
  globals
  exports
  start
  elems
  data-count
  codes
  datas)

(defstruct wasm-memory
  (bytes (make-array 0 :element-type '(unsigned-byte 8))
         :type (simple-array (unsigned-byte 8) (*)))
  min
  max)
(defstruct wasm-table
  (elements #() :type simple-vector)
  type min max)
(defstruct wasm-gcell
  (value 0)
  (bits 0 :type (unsigned-byte 64))
  ;; i64 and the raw bits of f32/f64 live in two fixnum halves. A single
  ;; (unsigned-byte 64) with bit 62 or 63 set is a bignum.
  (lo 0 :type (unsigned-byte 32))
  (hi 0 :type (unsigned-byte 32))
  (f64 0d0 :type double-float)
  (f32 0f0 :type single-float))

(defstruct wasm-instance
  module
  (funcs #() :type simple-vector)
  func-types
  (memories #() :type simple-vector)
  (tables #() :type simple-vector)
  (globals #() :type simple-vector)
  elems
  datas)

(defvar *wasm-instance* nil)
(defvar *wasm-depth* 0)
(defparameter *wasm-call-limit* 4096)

(defstruct compiled-module
  module
  funcs
  max-stacks)

(defstruct wasm-seg items)

(defstruct wasm-extern kind value type instance)
(defstruct wasm-funcref instance index)

(defun drop-seg (seg)
  (setf (wasm-seg-items seg)
        (make-array 0 :element-type (array-element-type (wasm-seg-items seg)))))
