(in-package #:cadr-ai)

(defparameter +non-retryable-assistant-error-fragments+
  '("gousagelimiterror"
    "freeusagelimiterror"
    "monthly usage limit reached"
    "available balance"
    "insufficient_quota"
    "out of budget"
    "quota exceeded"
    "billing"))

(defparameter +retryable-assistant-error-patterns+
  '("overloaded" "rate.?limit" "too many requests"
    "429" "500" "502" "503" "504" "524"
    "service.?unavailable" "server.?error" "internal.?error"
    "provider.?returned.?error"
    "exceeded request buffer limit while retrying upstream"
    "network.?error"
    "connection.?error" "connection.?refused"
    "connection.?lost" "other side closed" "fetch failed"
    "getaddrinfo" "ENOTFOUND" "EAI_AGAIN" "upstream.?connect"
    "reset before headers" "socket hang up"
    "socket connection was closed" "timed? out" "timeout"
    "terminated" "websocket.?closed" "websocket.?error"
    "ended without" "stream ended before message_stop"
    "stream ended before a terminal response event"
    "http2 request did not get a response" "retry delay"
    "you can retry your request" "try your request again"
    "please retry your request" "ResourceExhausted"))

(defun text-contains-any-p (text fragments)
  (some
   (lambda (fragment)
     (search fragment text :test #'char-equal))
   fragments))

(defun retry-pattern-matches-at-p
    (pattern text pattern-index text-index)
  (cond
    ((= pattern-index (length pattern)) t)
    ((>= text-index (length text))
     (and
      (< (1+ pattern-index) (length pattern))
      (char= #\? (char pattern (1+ pattern-index)))
      (retry-pattern-matches-at-p
       pattern text (+ pattern-index 2) text-index)))
    (t
     (let* ((pattern-character
              (char pattern pattern-index))
            (optional-p
              (and
               (< (1+ pattern-index) (length pattern))
               (char= #\? (char pattern (1+ pattern-index)))))
            (matches-p
              (or
               (char= #\. pattern-character)
               (char-equal
                pattern-character
                (char text text-index)))))
       (if optional-p
           (or
            (retry-pattern-matches-at-p
             pattern text (+ pattern-index 2) text-index)
            (and
             matches-p
             (retry-pattern-matches-at-p
              pattern text (+ pattern-index 2) (1+ text-index))))
           (and
            matches-p
            (retry-pattern-matches-at-p
             pattern text (1+ pattern-index) (1+ text-index))))))))

(defun text-matches-retry-pattern-p (text pattern)
  (loop for index from 0 to (length text)
        thereis
        (retry-pattern-matches-at-p pattern text 0 index)))

(defun text-matches-any-retry-pattern-p (text patterns)
  (some
   (lambda (pattern)
     (text-matches-retry-pattern-p text pattern))
   patterns))

(defun retryable-assistant-error-p (message)
  (let ((text (assistant-message-error-message message)))
    (and (eq :error
             (assistant-message-stop-reason message))
         (non-empty-string-p text)
         (not
          (text-contains-any-p
           text +non-retryable-assistant-error-fragments+))
         (text-matches-any-retry-pattern-p
          text +retryable-assistant-error-patterns+))))

(defstruct retry-policy
  (enabled-p t :type boolean)
  (max-retries 3 :type (integer 0 *))
  (base-delay-milliseconds 1000
                           :type (integer 0 *)))

(defun retry-assistant-call
    (produce policy
     &key abort-p
       on-retry-scheduled
       on-retry-attempt-start
       on-retry-finished
       (sleep-function #'sleep))
  (let ((attempt 0)
        (last-error nil)
        (maximum
          (if (and policy (retry-policy-enabled-p policy))
              (retry-policy-max-retries policy)
              0)))
    (loop
      (let ((message (funcall produce)))
        (cond
          ((eq :aborted
               (assistant-message-stop-reason message))
           (when (and (plusp attempt)
                      on-retry-finished)
             (funcall on-retry-finished nil attempt nil))
           (return message))
          ((not (eq :error
                    (assistant-message-stop-reason message)))
           (when (and (plusp attempt)
                      on-retry-finished)
             (funcall on-retry-finished t attempt nil))
           (return message))
          ((or (>= attempt maximum)
               (not (retryable-assistant-error-p message)))
           (when (and (plusp attempt)
                      on-retry-finished)
             (funcall
              on-retry-finished nil attempt
              (assistant-message-error-message message)))
           (return message))
          (t
           (incf attempt)
           (setf last-error
                 (or (assistant-message-error-message message)
                     "Unknown error"))
           (let ((delay
                   (* (retry-policy-base-delay-milliseconds policy)
                      (expt 2 (1- attempt)))))
             (flet ((aborted-message ()
                      (when on-retry-finished
                        (funcall on-retry-finished
                                 nil attempt last-error))
                      (make-assistant-message
                       :api (assistant-message-api message)
                       :provider (assistant-message-provider message)
                       :model (assistant-message-model message)
                       :content
                       (assistant-message-content message)
                       :usage (assistant-message-usage message)
                       :stop-reason :aborted)))
               (when on-retry-scheduled
                 (funcall on-retry-scheduled
                          attempt maximum delay last-error))
               (when (and abort-p (funcall abort-p))
                 (return (aborted-message)))
               (when (plusp delay)
                 (funcall sleep-function
                          (/ delay 1000d0)))
               (when (and abort-p (funcall abort-p))
                 (return (aborted-message)))
               (when on-retry-attempt-start
                 (funcall on-retry-attempt-start))))))))))
