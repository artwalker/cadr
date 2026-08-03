(in-package #:cadr-ai)

(define-condition cadr-error (error)
  ((message
    :initarg :message
    :reader cadr-error-message)
   (cause
    :initarg :cause
    :initform nil
    :reader cadr-error-cause)
   (retryable-p
    :initarg :retryable-p
    :initform nil
    :reader cadr-error-retryable-p))
  (:report (lambda (condition stream)
             (write-string (cadr-error-message condition) stream))))

(define-condition configuration-error (cadr-error) ())
(define-condition unsupported-content-error (cadr-error) ())
(define-condition authentication-error (cadr-error) ())
(define-condition authentication-cancelled (authentication-error) ())

(define-condition transport-error (cadr-error) ())
(define-condition network-error (transport-error) ())
(define-condition timeout-error (transport-error) ())
(define-condition request-aborted (transport-error) ())
(define-condition sse-protocol-error (transport-error) ())
(define-condition bedrock-stream-exception (cadr-error) ())

(define-condition api-error (cadr-error)
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
