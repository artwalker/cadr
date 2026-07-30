(in-package #:pi-agent)

(define-condition schema-validation-error (pi-ai:pi-error)
  ((tool
    :initarg :tool
    :reader schema-validation-error-tool)
   (json-pointer
    :initarg :json-pointer
    :initform ""
    :reader schema-validation-error-json-pointer)
   (reason
    :initarg :reason
    :reader schema-validation-error-reason)))

(define-condition tool-execution-error (pi-ai:pi-error)
  ((tool
    :initarg :tool
    :reader tool-execution-error-tool)
   (tool-call-id
    :initarg :tool-call-id
    :reader tool-execution-error-tool-call-id)))

(define-condition agent-busy-error (pi-ai:pi-error) ())
(define-condition agent-turn-limit-error (pi-ai:pi-error) ())

(define-condition extension-registration-error
    (pi-ai:configuration-error) ())

(define-condition extension-execution-error
    (pi-ai:pi-error) ())

(define-condition stale-extension-context
    (pi-ai:pi-error) ())

(define-condition session-error (pi-ai:pi-error)
  ((path
    :initarg :path
    :reader session-error-path)
   (line
    :initarg :line
    :initform nil
    :reader session-error-line)))
