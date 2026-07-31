(in-package #:cadr-agent)

(define-condition schema-validation-error (cadr-ai:cadr-error)
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

(define-condition tool-execution-error (cadr-ai:cadr-error)
  ((tool
    :initarg :tool
    :reader tool-execution-error-tool)
   (tool-call-id
    :initarg :tool-call-id
    :reader tool-execution-error-tool-call-id)))

(define-condition agent-busy-error (cadr-ai:cadr-error) ())
(define-condition agent-shutdown-error (cadr-ai:cadr-error) ())
(define-condition agent-turn-limit-error (cadr-ai:cadr-error) ())

(define-condition extension-registration-error
    (cadr-ai:configuration-error) ())

(define-condition extension-execution-error
    (cadr-ai:cadr-error) ())

(define-condition stale-extension-context
    (cadr-ai:cadr-error) ())

(define-condition session-error (cadr-ai:cadr-error)
  ((path
    :initarg :path
    :reader session-error-path)
   (line
    :initarg :line
    :initform nil
    :reader session-error-line)))
