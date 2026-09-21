(in-package #:cadr-ai)

(defparameter +overflow-fragments+
  '("prompt is too long"
    "request_too_large"
    "input is too long for requested model"
    "exceeds the context window"
    "maximum context length"
    "input token count"
    "maximum prompt length is"
    "reduce the length of the messages"
    "maximum allowed input length"
    "is longer than the model's context length"
    "exceeds the limit of"
    "exceeds the available context size"
    "greater than the context length"
    "context window exceeds limit"
    "exceeded model token limit"
    "too large for model with"
    "configured context size"
    "model_context_window_exceeded"
    "prompt too long; exceeded"
    "range of input length should be"
    "context_length_exceeded"
    "context length exceeded"
    "too many tokens"
    "token limit exceeded"))

(defparameter +non-overflow-fragments+
  '("throttling error:"
    "service unavailable:"
    "rate limit"
    "too many requests"))

(defun contains-ci-p (needle haystack)
  (and (search needle haystack :test #'char-equal) t))

(defun bare-overflow-http-status-p (text)
  (let ((trimmed
          (string-left-trim '(#\Space #\Tab #\Newline) text)))
    (and
     (or (uiop:string-prefix-p "400" trimmed)
         (uiop:string-prefix-p "413" trimmed))
     (contains-ci-p "no body" trimmed))))

(defun context-overflow-p (message &optional context-window)
  (or
   (and
    (eq :error (assistant-message-stop-reason message))
    (assistant-message-error-message message)
    (notany
     (lambda (fragment)
       (contains-ci-p
        fragment (assistant-message-error-message message)))
     +non-overflow-fragments+)
    (or
     (some
      (lambda (fragment)
        (contains-ci-p
         fragment (assistant-message-error-message message)))
      +overflow-fragments+)
     (and
      (eq (assistant-message-provider message) :cerebras)
      (bare-overflow-http-status-p
       (assistant-message-error-message message)))))
   (and
    context-window
    (eq :stop (assistant-message-stop-reason message))
    (>
     (+ (usage-input (assistant-message-usage message))
        (usage-cache-read (assistant-message-usage message)))
     context-window))
   (and
    context-window
    (eq :length (assistant-message-stop-reason message))
    (zerop (usage-output (assistant-message-usage message)))
    (>=
     (+ (usage-input (assistant-message-usage message))
        (usage-cache-read (assistant-message-usage message)))
     (* context-window 0.99d0)))))
