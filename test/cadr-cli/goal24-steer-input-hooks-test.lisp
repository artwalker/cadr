(in-package #:cadr-cli/tests)

(in-suite cadr-cli-suite)

(defun goal24-steer-input-hooks-model ()
  (cadr-ai:make-model
   :id "sdk-steer-hooks"
   :name "SDK Steer Hooks"
   :provider :faux
   :api :openai-responses
   :base-url "https://example.invalid"
   :max-tokens 1024
   :context-window 8192
   :supports-tools-p t))

(defun goal24-steer-input-hooks-stream
    (provider model context on-event &rest options)
  (declare (ignore provider model context options))
  (let ((message
          (cadr-ai:make-assistant-message
           :content
           (list
            (cadr-ai:make-text-content
             :text "unused"))
           :api :openai-responses
           :provider :faux
           :model "sdk-steer-hooks"
           :stop-reason :stop)))
    (funcall on-event
             (cadr-ai:make-stream-event
              :type :done :message message
              :reason :stop))
    message))

(defun goal24-queue-texts (messages)
  (mapcar
   (lambda (message)
     (cadr-ai::content-text
      (cadr-ai:user-message-content message)))
   messages))

(test goal24-sdk-steer-and-follow-up-run-input-hooks
  ;; Mirror pi agent-session-queue #8718: transform/handle via
  ;; agent-session-prompt :steer / :follow-up.
  (with-test-directory (temporary)
    (let* ((events nil)
           (bundle
             (let ((bundle
                     (cadr-agent::make-extension-bundle
                      :id "goal24-steer-input-hooks"
                      :path
                      "/tmp/goal24-steer-input-hooks.lisp")))
               (cadr-agent::call-with-extension-registration
                bundle
                (lambda ()
                  (cadr-agent:define-event-hook
                   :input
                   :handler
                   (lambda (event context)
                     (declare (ignore context))
                     (let* ((payload
                              (cadr-agent:extension-event-payload
                               event))
                            (text (getf payload :text)))
                       (push
                        (list
                         :text text
                         :source (getf payload :source)
                         :streaming-behavior
                         (getf payload :streaming-behavior))
                        events)
                       (if (and (stringp text)
                                (uiop:string-prefix-p
                                 "handle" text))
                           '(:action :handled)
                           (list
                            :action :transform
                            :text
                            (format nil "transformed: ~A"
                                    text))))))))
               bundle))
           (host (cadr-agent::make-extension-host))
           (session
             (cadr-cli::create-agent-session
              :cwd temporary
              :agent-directory
              (merge-pathnames "agent/" temporary)
              :model (goal24-steer-input-hooks-model)
              :provider :faux
              :thinking-level :off
              :stream-function
              #'goal24-steer-input-hooks-stream
              :session-manager
              (cadr-cli::session-manager-in-memory
               temporary)
              :no-tools :all))
           (agent (cadr-cli::agent-session-agent session)))
      (cadr-agent::replace-extension-bundles
       host (list bundle))
      (cadr-agent::attach-extension-host host agent)
      (cadr-cli::agent-session-prompt
       session "steer me"
       :streaming-behavior :steer
       :source :rpc)
      (cadr-cli::agent-session-prompt
       session "handle steer"
       :streaming-behavior :steer
       :source :rpc)
      (cadr-cli::agent-session-prompt
       session "follow me"
       :streaming-behavior :follow-up
       :source :rpc)
      (cadr-cli::agent-session-prompt
       session "handle follow"
       :streaming-behavior :follow-up
       :source :rpc)
      (is
       (equal
        '((:text "steer me"
           :source :rpc
           :streaming-behavior :steer)
          (:text "handle steer"
           :source :rpc
           :streaming-behavior :steer)
          (:text "follow me"
           :source :rpc
           :streaming-behavior :follow-up)
          (:text "handle follow"
           :source :rpc
           :streaming-behavior :follow-up))
        (nreverse events)))
      (is
       (equal
        '("transformed: steer me")
        (goal24-queue-texts
         (cadr-agent::agent-steering-queue agent))))
      (is
       (equal
        '("transformed: follow me")
        (goal24-queue-texts
         (cadr-agent::agent-follow-up-queue agent))))
      (cadr-cli::agent-session-dispose session))))
