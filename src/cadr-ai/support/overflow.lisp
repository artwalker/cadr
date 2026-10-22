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
    "prompt too long"
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

(defun request-size-overflow-text-p (text)
  ;; pi@4a080252f overflow.ts: HTTP 413 is request-size overflow for every
  ;; provider. Match formatProviderError's "<name> API error (413):" prefix
  ;; and a raw "413" status. A 413 later in the body, or status 4130, does not.
  (labels ((provider-name-char-p (char)
             (let ((code (char-code char)))
               (or (<= 48 code 57)
                   (<= 65 code 90)
                   (<= 97 code 122)
                   (char= char #\_)
                   (char= char #\Space)
                   (char= char #\-))))
           (status-break-p (char)
             (or (char= char #\:)
                 (char= char #\Space)
                 (char= char #\Tab)
                 (char= char #\Newline)
                 (char= char #\Return)
                 (char= char #\Page)
                 (= (char-code char) 11))))
    (and
     (stringp text)
     (or
      (let ((position
              (search " API error (413):" text :test #'char-equal)))
        (and position
             (plusp position)
             (loop for index below position
                   always (provider-name-char-p (char text index)))))
      (and (>= (length text) 3)
           (string= "413" text :end2 3)
           (or (= (length text) 3)
               (status-break-p (char text 3))))))))

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
     (request-size-overflow-text-p
      (assistant-message-error-message message))
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
