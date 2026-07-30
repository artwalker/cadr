(in-package #:pi-ai)

(define-condition pi-error (error)
  ((message
    :initarg :message
    :reader pi-error-message)
   (cause
    :initarg :cause
    :initform nil
    :reader pi-error-cause)
   (retryable-p
    :initarg :retryable-p
    :initform nil
    :reader pi-error-retryable-p))
  (:report (lambda (condition stream)
             (write-string (pi-error-message condition) stream))))

(define-condition configuration-error (pi-error) ())
(define-condition unsupported-content-error (pi-error) ())
(define-condition authentication-error (pi-error) ())

(define-condition transport-error (pi-error) ())
(define-condition network-error (transport-error) ())
(define-condition timeout-error (transport-error) ())
(define-condition request-aborted (transport-error) ())
(define-condition sse-protocol-error (transport-error) ())

(define-condition api-error (pi-error)
  ((provider
    :initarg :provider
    :reader api-error-provider)
   (status
    :initarg :status
    :reader api-error-status)
   (code
    :initarg :code
    :initform nil
    :reader api-error-code)
   (retry-after
    :initarg :retry-after
    :initform nil
    :reader api-error-retry-after)))
