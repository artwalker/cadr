(in-package #:cadr-agent/tests)

(in-suite cadr-agent-suite)

(defun custom-trigger-host (handler)
  (let ((bundle
          (cadr-agent::make-extension-bundle
           :id "custom-trigger"
           :path "/tmp/custom-trigger.lisp"
           :scope :project
           :rank 1
           :order 0)))
    (cadr-agent::call-with-extension-registration
     bundle
     (lambda ()
       (cadr-agent:define-event-hook
        :before-agent-start
        :handler handler)))
    (let ((host
            (cadr-agent::make-extension-host
             :cwd #P"/tmp/"
             :mode :repl)))
      (cadr-agent::replace-extension-bundles host (list bundle))
      host)))

(defun custom-trigger-agent (host responses contexts)
  (let ((agent
          (cadr-agent:make-agent
           :provider :mock
           :model (mock-model)
           :system-prompt "base"
           :auto-compact-p nil
           :stream-function (faux-stream responses contexts))))
    (cadr-agent::attach-extension-host host agent)
    agent))

(test custom-trigger-turn-keeps-the-custom-message
  ;; pi@71023aec1 #10739. Idle triggerTurn reports the custom message
  ;; and does not also send that text as a user prompt.
  (let ((seen nil)
        (busy-during-hook nil)
        (*custom-trigger-responses*
          (list
           (assistant
            (list (make-text-content :text "done")))))
        (*custom-trigger-contexts* nil))
    (declare
     (special *custom-trigger-responses*
              *custom-trigger-contexts*))
    (let* ((host
             (custom-trigger-host
              (lambda (event context)
                (let ((payload
                        (cadr-agent:extension-event-payload event)))
                  (setf seen payload
                        busy-during-hook
                        (cadr-agent:agent-busy-p
                         (cadr-agent:extension-context-agent
                          context))))
                (list
                 :message
                 (cadr-ai:make-user-message
                  :content "from the hook")
                 :system-prompt "forced section"))))
           (agent
             (custom-trigger-agent
              host
              '*custom-trigger-responses*
              '*custom-trigger-contexts*)))
      (cadr-agent:agent-next-turn agent "queued next")
      (cadr-agent::extension-host-send-message
       host
       (list :custom-type "board"
             :content "Player moved"
             :display-p t)
       :trigger-turn-p t)
      (is (eq t busy-during-hook))
      (is (eq :custom (getf seen :message-type)))
      (is (string= "board"
                   (getf (getf seen :message) :custom-type)))
      (is (string= "Player moved"
                   (getf (getf seen :message) :content)))
      (is (not (find :prompt seen)))
      (let ((messages (cadr-agent:agent-messages agent)))
        (is (= 1
               (count-if
                #'cadr-agent::custom-agent-message-p
                messages)))
        (is (string= "Player moved"
                     (cadr-agent::custom-agent-message-content
                      (find-if
                       #'cadr-agent::custom-agent-message-p
                       messages))))
        (is (zerop
             (count-if
              (lambda (message)
                (and (typep message 'cadr-ai:user-message)
                     (string= "Player moved"
                              (cadr-ai:user-message-content
                               message))))
              messages))))
      (let* ((context (first *custom-trigger-contexts*))
             (request (cadr-ai:context-messages context))
             (texts
               (loop for message in request
                     when (typep message 'cadr-ai:user-message)
                       collect
                       (cadr-ai:user-message-content message))))
        (is (string= "forced section"
                     (cadr-ai:context-system-prompt context)))
        (is (equal
             '("Player moved" "queued next" "from the hook")
             texts))))))
