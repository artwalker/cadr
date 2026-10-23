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

(defstruct wasm-memory bytes min max)
(defstruct wasm-table elements type min max)
(defstruct wasm-gcell value)

(defstruct wasm-instance
  module
  funcs
  func-types
  memories
  tables
  globals
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
