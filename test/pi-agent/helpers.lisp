(in-package #:pi-agent/tests)

(defun mock-model ()
  (make-model :id "mock"
              :provider :openai
              :api :openai-responses
              :base-url "https://example.invalid"
              :max-tokens 2048))

(defun assistant (content &optional (stop-reason :stop))
  (make-assistant-message
   :content content
   :api :openai-responses
   :provider :openai
   :model "mock"
   :stop-reason stop-reason))

(defun faux-stream (responses captured-contexts)
  (lambda (provider model context on-event
           &key max-tokens temperature abort-p)
    (declare (ignore provider model max-tokens temperature))
    (push context (symbol-value captured-contexts))
    (let ((message
            (if (and abort-p (funcall abort-p))
                (assistant nil :aborted)
                (pop (symbol-value responses)))))
      (funcall on-event
               (make-stream-event :type :start :message message))
      (dolist (block (assistant-message-content message))
        (when (typep block 'pi-ai:text-content)
          (funcall
           on-event
           (make-stream-event
            :type :text-delta
            :delta (text-content-text block)
            :message message))))
      (funcall
       on-event
       (make-stream-event
        :type (if (member (assistant-message-stop-reason message)
                          '(:error :aborted))
                  :error
                  :done)
        :message message
        :reason (assistant-message-stop-reason message)))
      message)))

(defun event-types (events)
  (mapcar #'agent-event-type events))

(defun text-result (message)
  (text-content-text
   (first (tool-result-message-content message))))

(defun object-schema (&rest required)
  (if (null required)
      (pi-ai::json-object "type" "object")
      (let ((properties (pi-ai::json-object)))
        (dolist (name required)
          (pi-ai::json-put properties name
                           (pi-ai::json-object "type" "string")))
        (pi-ai::json-object
         "type" "object"
         "properties" properties
         "required" (coerce required 'vector)
         "additionalProperties" nil))))
