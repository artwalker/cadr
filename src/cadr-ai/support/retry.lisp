(in-package #:cadr-ai)

(defparameter +non-retryable-assistant-error-fragments+
  '("gousagelimiterror"
    "freeusagelimiterror"
    "monthly usage limit reached"
    "available balance"
    "insufficient_quota"
    "out of budget"
    "quota exceeded"
    "billing"
    "subscription_sharing_usage_limit_exceeded"
    ;; ChatGPT Business workspace cap. The personal usage-limit code is
    ;; not a substring of this one, so a 429 that names only this code
    ;; would otherwise match the retryable "429".
    "subscription_sharing_workplace_individual_usage_limit_exceeded"))

(defparameter +retryable-http-status-codes+
  '("429" "500" "502" "503" "504" "520" "524"))

(defparameter +retryable-assistant-error-patterns+
  '("overloaded" "server_busy" "servers are currently busy"
    "currently experiencing high demand" "model is at capacity"
    "rate.?limit" "too many requests"
    ;; Status codes are matched by retryable-http-status-text-p so
    ;; digits inside request ids or byte counts do not count (#11057).
    "service.?unavailable"
    "service is unavailable"
    "service temporarily unavailable"
    "service is temporarily unavailable"
    "server.?error" "internal.?error"
    "provider.?returned.?error"
    "provider returned an error"
    "exceeded request buffer limit while retrying upstream"
    "unable to forward upstream"
    "upstream.?request.?failed"
    "upstream_stream_read_error"
    "stream was interrupted"
    "http/?2 stream failed"
    "network.?error"
    "connection.?error" "connection.?refused"
    "connection.?lost" "other side closed" "fetch failed"
    "getaddrinfo" "ENOTFOUND" "EAI_AGAIN" "upstream.?connect"
    "reset before headers" "socket hang up"
    "socket connection was closed" "timed? out" "timeout"
    "terminated" "websocket.?closed" "websocket.?error"
    "ended without" "stream ended before message_stop"
    "stream ended before a terminal response event"
    "http2 request did not get a response"
    "stream disconnected before completion"
    "retry delay"
    "you can retry your request" "try your request again"
    "please retry your request" "ResourceExhausted"
    "pending stream has been canceled"
    "subscription_sharing_usage_unavailable"
    "subscription_sharing_user_unavailable"))

(defun ascii-alphanumeric-p (character)
  (or (alpha-char-p character)
      (digit-char-p character)))

(defun retryable-http-status-text-p (text)
  ;; Same boundary as pi's (?<![a-z0-9])(?:429|...)(?![a-z0-9]).
  (dolist (code +retryable-http-status-codes+)
    (loop for start = 0 then (1+ position)
          for position = (search code text :start2 start)
          while position
          do (let* ((end (+ position (length code)))
                    (before
                      (when (plusp position)
                        (char text (1- position))))
                    (after
                      (when (< end (length text))
                        (char text end))))
               (when (and (or (null before)
                              (not (ascii-alphanumeric-p before)))
                          (or (null after)
                              (not (ascii-alphanumeric-p after))))
                 (return-from retryable-http-status-text-p t)))))
  nil)

(defun node-fetch-request-failure-text-p (text)
  ;; node-fetch system errors from Google ADC OAuth refresh (#10996):
  ;; "request to <url> failed, reason:" with a non-empty URL.
  (let ((needle "request to ")
        (tail " failed, reason:"))
    (loop for start = 0 then (1+ position)
          for position = (search needle text :start2 start
                                            :test #'char-equal)
          while position
          do (let* ((url-start (+ position (length needle)))
                    (tail-position
                      (search tail text :start2 url-start
                                       :test #'char-equal)))
               (when (and tail-position
                          (< url-start tail-position)
                          (not
                           (find-if
                            (lambda (character)
                              (or (char= character #\Space)
                                  (char= character #\Tab)
                                  (char= character #\Newline)
                                  (char= character #\Return)))
                            text
                            :start url-start
                            :end tail-position)))
                 (return-from node-fetch-request-failure-text-p t)))))
  nil)

(defun text-contains-any-p (text fragments)
  (some
   (lambda (fragment)
     (search fragment text :test #'char-equal))
   fragments))

(defun terminal-quota-error-text-p (text)
  ;; Same set as +non-retryable-assistant-error-fragments+.
  ;; HTTP 429 with this text is a subscription/quota wall, not a
  ;; transient throttle (pi isTerminalRateLimitError).
  (and (stringp text)
       (plusp (length text))
       (text-contains-any-p
        text +non-retryable-assistant-error-fragments+)))

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
         (or (retryable-http-status-text-p text)
             (node-fetch-request-failure-text-p text)
             (text-matches-any-retry-pattern-p
              text +retryable-assistant-error-patterns+)))))

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
