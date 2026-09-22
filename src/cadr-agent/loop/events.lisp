(in-package #:cadr-agent)

(defvar *agent-run-system-prompt* :use-agent-system-prompt)

(defvar *agent-run-new-messages* nil)

(defparameter +non-retryable-assistant-error-pattern+
  (cl-ppcre:create-scanner
   "(GoUsageLimitError|FreeUsageLimitError|Monthly usage limit reached|available balance|insufficient_quota|out of budget|quota exceeded|billing)"
   :case-insensitive-mode t))

(defparameter +retryable-assistant-error-pattern+
  (cl-ppcre:create-scanner
   "(overloaded|rate.?limit|too many requests|429|500|502|503|504|524|service.?unavailable|server.?error|internal.?error|provider.?returned.?error|network.?error|connection.?error|connection.?refused|connection.?lost|other side closed|fetch failed|getaddrinfo|ENOTFOUND|EAI_AGAIN|upstream.?connect|reset before headers|socket hang up|socket connection was closed|timed? out|timeout|terminated|websocket.?closed|websocket.?error|ended without|stream ended before message_stop|stream ended before a terminal response event|http2 request did not get a response|retry delay|you can retry your request|try your request again|please retry your request|ResourceExhausted)"
   :case-insensitive-mode t))

(defun retryable-assistant-error-p (message)
  (when
      (and
       (typep message 'cadr-ai:assistant-message)
       (eq :error
           (cadr-ai:assistant-message-stop-reason
            message))
       (cadr-ai:assistant-message-error-message
        message)
       (not (context-overflow-message-p message)))
    (let ((text
            (cadr-ai:assistant-message-error-message
             message)))
      (and
       (not
        (cl-ppcre:scan
         +non-retryable-assistant-error-pattern+
         text))
       (not
        (null
         (cl-ppcre:scan
          +retryable-assistant-error-pattern+
          text)))))))

(defun agent-will-retry-p (agent message)
  (and
   (agent-auto-retry-p agent)
   (< (agent-retry-attempt agent)
      (agent-auto-retry-max-attempts agent))
   (retryable-assistant-error-p message)))

(defun last-agent-assistant-message (agent)
  (find-if
   (lambda (message)
     (typep message 'cadr-ai:assistant-message))
   (agent-messages agent)
   :from-end t))

(defun run-agent-lifecycle (agent event &optional payload)
  (let ((host (agent-extension-host agent)))
    (and
     host
     (run-extension-lifecycle-hooks
      host event :payload payload))))

(defun ensure-agent-session-started (agent)
  (let ((host (agent-extension-host agent)))
    (when
        (and host
             (not
              (extension-host-session-started-p host)))
      (setf
       (extension-host-session-started-p host)
       t)
      (run-extension-lifecycle-hooks
       host :session-start
       :payload '(:reason :startup)))))

(defun current-agent-system-prompt (agent)
  (if (eq *agent-run-system-prompt*
          :use-agent-system-prompt)
      (agent-system-prompt agent)
      *agent-run-system-prompt*))

(defun lifecycle-message-end (agent message)
  (let ((result
          (run-agent-lifecycle
           agent :message-end
           (list :message message))))
    (or (getf result :message) message)))

(defun emit-message-start (agent message)
  (run-agent-lifecycle
   agent :message-start
   (list :message message))
  (emit-agent-event
   agent :message-start :message message))

(defun emit-message-update
    (agent message stream-event)
  (run-agent-lifecycle
   agent :message-update
   (list
    :message message
    :assistant-message-event stream-event))
  (emit-agent-event
   agent :message-update
   :message message
   :stream-event stream-event))

(defun emit-message-end (agent message)
  (let ((final
          (lifecycle-message-end agent message)))
    (emit-agent-event
     agent :message-end :message final)
    (when *agent-run-new-messages*
      (vector-push-extend final *agent-run-new-messages*))
    (when
        (and
         (typep final 'cadr-ai:assistant-message)
         (not
          (eq :error
              (cadr-ai:assistant-message-stop-reason
               final)))
         (plusp (agent-retry-attempt agent)))
      (let ((attempt
              (agent-retry-attempt agent)))
        (setf (agent-retry-attempt agent) 0)
        (emit-agent-event
         agent :auto-retry-end
         :success t
         :attempt attempt)))
    final))

(defun ensure-agent-messages-tail (agent)
  (let ((messages (agent-messages agent)))
    (cond
      ((null messages)
       (setf
        (agent-messages-tail agent) nil
        (agent-messages-tail-head agent) nil))
      ((or
        (not
         (eq messages
             (agent-messages-tail-head agent)))
        (null (agent-messages-tail agent))
        (not
         (null
          (cdr (agent-messages-tail agent)))))
       (setf
        (agent-messages-tail agent) (last messages)
        (agent-messages-tail-head agent) messages))))
  (agent-messages-tail agent))

(defun append-agent-message (agent message &key id)
  (when (agent-session agent)
    (session-append-message
     (agent-session agent) message :id id))
  (let ((cell (list message)))
    (if (agent-messages agent)
        (setf
         (cdr (ensure-agent-messages-tail agent)) cell
         (agent-messages-tail agent) cell)
        (setf
         (agent-messages agent) cell
         (agent-messages-tail agent) cell
         (agent-messages-tail-head agent) cell)))
  message)

(defun assistant-tool-calls (message)
  (remove-if-not
   (lambda (block) (typep block 'cadr-ai:tool-call))
   (cadr-ai:assistant-message-content message)))
