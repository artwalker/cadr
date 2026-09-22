(in-package #:cadr-agent/tests)
(in-suite cadr-agent-suite)

(test goal18-nil-model-prompt-fails-with-baseline-guidance
  ;; Baseline agent-session.ts:1181-1192 — with the unknown sentinel
  ;; model the auth check fails before any append, throwing
  ;; formatNoApiKeyFoundMessage("unknown").
  (let ((agent
          (make-agent
           :provider :mock
           :model nil)))
    (handler-case
        (progn
          (cadr-agent:agent-prompt agent "hello")
          (is nil "nil-model prompt did not signal"))
      (cadr-ai:configuration-error (condition)
        (is (string=
             (cadr-ai::no-api-key-found-message "unknown")
             (cadr-ai:cadr-error-message condition)))
        (is (search
             "No API key found for the selected model."
             (cadr-ai:cadr-error-message condition)))))
    (is (null (agent-messages agent))
        "nil-model prompt must not append the user message")))

(test goal11-agent-message-append-maintains-o1-tail-invariant
  (let* ((initial
           (list
            (cadr-ai:make-user-message :content "first")))
         (agent
           (make-agent
            :provider :mock
            :model (mock-model)
            :messages initial))
         (first-tail
           (cadr-agent::agent-messages-tail agent)))
    (is (eq (agent-messages agent)
            (cadr-agent::agent-messages-tail-head agent)))
    (is (eq first-tail (last (agent-messages agent))))
    (cadr-agent::agent-append-message
     agent
     (cadr-ai:make-user-message :content "second"))
    (is (eq (cdr first-tail)
            (cadr-agent::agent-messages-tail agent)))
    (is (null
         (cdr (cadr-agent::agent-messages-tail agent))))
    (is (equal '("first" "second")
               (mapcar
                #'cadr-ai:user-message-content
                (agent-messages agent))))
    ;; Public accessors allow callers to replace the list. The next append
    ;; repairs the private tail once and then resumes constant-time appends.
    (let ((replacement
            (list
             (cadr-ai:make-user-message :content "replacement"))))
      (setf (agent-messages agent) replacement)
      (cadr-agent::agent-append-message
       agent
       (cadr-ai:make-user-message :content "after-replacement"))
      (is (eq replacement
              (cadr-agent::agent-messages-tail-head agent)))
      (is (equal '("replacement" "after-replacement")
                 (mapcar
                  #'cadr-ai:user-message-content
                  (agent-messages agent)))))))

(test simple-turn-emits-reference-lifecycle-order
  (let ((*responses*
          (list
           (assistant
            (list (make-text-content :text "Hello")))))
        (*contexts* nil)
        (events nil))
    (declare (special *responses* *contexts*))
    (let ((agent
            (make-agent
             :provider :mock
             :model (mock-model)
             :stream-function
             (faux-stream '*responses* '*contexts*)
             :on-event (lambda (event) (push event events)))))
      (agent-prompt agent "Hi")
      (setf events (nreverse events))
      (is (equal
           '(:agent-start :turn-start
             :message-start :message-end
             :message-start :message-update :message-end
             :turn-end :agent-end :agent-settled)
           (event-types events)))
      (is (= 2 (length (agent-messages agent))))
      (is (string= "Hello"
                   (text-content-text
                    (first
                     (assistant-message-content
                      (second (agent-messages agent))))))))))

(test finish-turn-end-stops-the-run
  (let ((*responses*
          (list
           (assistant (list (make-text-content :text "one")))
           (assistant (list (make-text-content :text "two")))))
        (*contexts* nil))
    (declare (special *responses* *contexts*))
    (let ((agent
            (make-agent
             :provider :mock
             :model (mock-model)
             :stream-function
             (faux-stream '*responses* '*contexts*)
             :finish-turn-function
             (lambda (agent message results)
               (declare (ignore agent message results))
               :end))))
      (agent-prompt agent "Hi")
      (is (= 1 (length *responses*)))
      (is (= 2 (length (agent-messages agent)))))))

(test finish-turn-continue-requests-another-provider-turn
  (let ((*responses*
          (list
           (assistant (list (make-text-content :text "one")))
           (assistant (list (make-text-content :text "two")))))
        (*contexts* nil)
        (calls 0))
    (declare (special *responses* *contexts*))
    (let ((agent
            (make-agent
             :provider :mock
             :model (mock-model)
             :stream-function
             (faux-stream '*responses* '*contexts*)
             :finish-turn-function
             (lambda (agent message results)
               (declare (ignore agent message results))
               (incf calls)
               (when (= calls 1) :continue)))))
      (agent-prompt agent "Hi")
      (is (null *responses*))
      (is (= 3 (length (agent-messages agent))))
      (is (= 2 calls)))))

(test goal17-agent-end-messages-exclude-preexisting-context
  (let* ((old-user
           (cadr-ai:make-user-message :content "old request"))
         (old-assistant
           (assistant
            (list (make-text-content :text "old answer"))))
         (*responses*
           (list
            (assistant
             (list (make-text-content :text "new answer")))))
         (*contexts* nil)
         (events nil))
    (declare (special *responses* *contexts*))
    (let ((agent
            (make-agent
             :provider :mock
             :model (mock-model)
             :messages (list old-user old-assistant)
             :stream-function
             (faux-stream '*responses* '*contexts*)
             :on-event (lambda (event) (push event events)))))
      (agent-prompt agent "new request")
      (let* ((event
               (find :agent-end events
                     :key #'agent-event-type))
             (messages
               (cadr-agent:agent-event-messages event)))
        (is (= 2 (length messages)))
        (is
         (string=
          "new request"
          (cadr-ai:user-message-content (first messages))))
        (is
         (string=
          "new answer"
          (cadr-ai:text-content-text
           (first
            (cadr-ai:assistant-message-content
             (second messages))))))
        (is-false (member old-user messages :test #'eq))
        (is-false (member old-assistant messages :test #'eq))))))

(test error-and-abort-stop-the-run-cleanly
  (dolist (reason '(:error :aborted))
    (let ((*responses* (list (assistant nil reason)))
          (*contexts* nil)
          (events nil))
      (declare (special *responses* *contexts*))
      (let ((agent
              (make-agent
               :provider :mock
               :model (mock-model)
               :stream-function
               (faux-stream '*responses* '*contexts*)
               :on-event (lambda (event) (push event events)))))
        (agent-prompt agent "Hi")
        (is (= 2 (length (agent-messages agent))))
        (is (= 1 (count :turn-end (event-types events))))
        (is (= 1 (count :agent-end (event-types events))))))))

(test goal17-terminal-abort-preserves-last-partial-content-and-usage
  ;; Fixed pi@16787ad5b faux.ts:288-297,313-344 turns the last partial into
  ;; the aborted terminal message.  Providers may return a sparse terminal
  ;; object, so the agent must preserve content and usage already observed.
  (let* ((partial
           (make-assistant-message
            :api :mock :provider :openai :model "mock"
            :content
            (list (make-text-content :text "partial response"))
            :usage
            (cadr-ai:make-usage
             :input 1300 :output 14 :cache-write 1300)
            :stop-reason :pending))
         (terminal
           (make-assistant-message
            :api :mock :provider :openai :model "mock"
            :stop-reason :aborted
            :error-message "Request was aborted"))
         (agent
           (make-agent
            :provider :mock
            :model (mock-model)
            :stream-function
            (lambda (provider model context on-event &rest options)
              (declare
               (ignore provider model context options))
              (funcall
               on-event
               (make-stream-event
                :type :start :message partial))
              (funcall
               on-event
               (make-stream-event
                :type :text-delta
                :delta "partial response"
                :message partial))
              terminal))))
    (agent-prompt agent "stop this stream")
    (let ((committed (car (last (agent-messages agent)))))
      (is (eq :aborted
              (assistant-message-stop-reason committed)))
      (is (string= "Request was aborted"
                   (cadr-ai:assistant-message-error-message
                    committed)))
      (is (string= "partial response"
                   (text-content-text
                    (first
                     (assistant-message-content committed)))))
      (is (= 1300
             (cadr-ai:usage-input
              (cadr-ai:assistant-message-usage committed))))
      (is (= 14
             (cadr-ai:usage-output
              (cadr-ai:assistant-message-usage committed))))
      (is (= 1300
             (cadr-ai:usage-cache-write
              (cadr-ai:assistant-message-usage committed)))))))

(test goal17-provider-error-terminal-payload-remains-authoritative
  (let* ((partial
           (make-assistant-message
            :api :mock :provider :openai :model "mock"
            :content
            (list (make-text-content :text "partial response"))
            :usage (cadr-ai:make-usage :input 1300)
            :stop-reason :pending))
         (terminal
           (make-assistant-message
            :api :mock :provider :openai :model "mock"
            :content
            (list (make-text-content :text "provider final"))
            :usage (cadr-ai:make-usage :input 17 :output 3)
            :stop-reason :error
            :error-message "render transport failed"))
         (agent
           (make-agent
            :provider :mock
            :model (mock-model)
            :stream-function
            (lambda (provider model context on-event &rest options)
              (declare
               (ignore provider model context options))
              (funcall
               on-event
               (make-stream-event
                :type :start :message partial))
              terminal))))
    (agent-prompt agent "trigger provider error")
    (let ((committed (car (last (agent-messages agent)))))
      (is (eq :error
              (assistant-message-stop-reason committed)))
      (is (string= "render transport failed"
                   (cadr-ai:assistant-message-error-message
                    committed)))
      (is (string= "provider final"
                   (text-content-text
                    (first
                     (assistant-message-content committed)))))
      (is (= 17
             (cadr-ai:usage-input
              (cadr-ai:assistant-message-usage committed))))
      (is (= 3
             (cadr-ai:usage-output
              (cadr-ai:assistant-message-usage committed)))))))

(test agent-message-to-llm-owns-type-dispatch
  (is (fboundp 'cadr-agent::agent-message-to-llm))
  (let ((user (cadr-ai:make-user-message :content "hi")))
    (is (eq user (cadr-agent::agent-message-to-llm user)))
    (is (cadr-agent::llm-passthrough-message-p user))))

(defun call-with-boundary-session (function)
  (let* ((root
           (uiop:ensure-directory-pathname
            (format nil "/tmp/cadr-boundary-~A/"
                    (cadr-ai:uuid-v7))))
         (sessions (merge-pathnames "sessions/" root))
         (cwd (merge-pathnames "project/" root)))
    (ensure-directories-exist
     (merge-pathnames "anchor" sessions))
    (ensure-directories-exist
     (merge-pathnames "anchor" cwd))
    (unwind-protect
         (funcall
          function
          (cadr-agent:create-session
           :directory sessions
           :cwd cwd
           :timestamp 1))
      (uiop:delete-directory-tree
       root :validate t :if-does-not-exist :ignore))))

(test turn-end-boundary-entries-request-another-provider-turn
  (call-with-boundary-session
   (lambda (session)
     (let* ((turn-ends 0)
            (provider-calls 0)
            (bundle
              (make-test-extension-bundle
               "turn-boundary"
               (lambda ()
                 (cadr-agent:define-event-hook
                  :turn-end
                  :handler
                  (lambda (event context)
                    (declare (ignore context))
                    (incf turn-ends)
                    (let ((payload
                            (cadr-agent:extension-event-payload
                             event)))
                      (is (stringp
                           (getf payload :message-entry-id)))
                      (when (= turn-ends 1)
                        (cadr-agent:make-extension-hook-result
                         :entries
                         '((:type :custom-message
                            :custom-type "note"
                            :content "please continue"))
                         :continue t))))))))
            (host (make-test-extension-host (list bundle)))
            (*responses*
              (list
               (assistant
                (list (make-text-content :text "one")))
               (assistant
                (list (make-text-content :text "two")))))
            (*contexts* nil)
            (stream (faux-stream '*responses* '*contexts*))
            (agent
              (make-agent
               :provider :mock
               :model (mock-model)
               :session session
               :extension-host host
               :stream-function
               (lambda (&rest arguments)
                 (incf provider-calls)
                 (apply stream arguments)))))
       (declare (special *responses* *contexts*))
       (agent-prompt agent "Hi")
       (is (= 2 provider-calls))
       (is (find "please continue"
                 (agent-messages agent)
                 :key (lambda (message)
                        (and (typep message 'cadr-ai:user-message)
                             (cadr-ai:user-message-content message)))
                 :test #'equal))))))

(test turn-end-continue-without-context-does-not-start-another-turn
  (call-with-boundary-session
   (lambda (session)
     (let* ((*notifications* nil)
            (provider-calls 0)
            (bundle
              (make-test-extension-bundle
               "turn-boundary-invalid"
               (lambda ()
                 (cadr-agent:define-event-hook
                  :turn-end
                  :handler
                  (lambda (event context)
                    (declare (ignore event context))
                    (cadr-agent:make-extension-hook-result
                     :continue t))))))
            (host
              (make-test-extension-host
               (list bundle)
               :notifications '*notifications*))
            (*responses*
              (list
               (assistant
                (list (make-text-content :text "one")))
               (assistant
                (list (make-text-content :text "two")))))
            (*contexts* nil)
            (stream (faux-stream '*responses* '*contexts*))
            (agent
              (make-agent
               :provider :mock
               :model (mock-model)
               :session session
               :extension-host host
               :stream-function
               (lambda (&rest arguments)
                 (incf provider-calls)
                 (apply stream arguments)))))
       (declare (special *responses* *contexts* *notifications*))
       (agent-prompt agent "Hi")
       (is (= 1 provider-calls))
       (is (search
            "turn_end requested continuation without runnable model context"
            (second (first *notifications*))))))))

(test agent-before-settle-entries-request-another-provider-turn
  (call-with-boundary-session
   (lambda (session)
     (let* ((settles 0)
            (provider-calls 0)
            (bundle
              (make-test-extension-bundle
               "settle-boundary"
               (lambda ()
                 (cadr-agent:define-event-hook
                  :agent-before-settle
                  :handler
                  (lambda (event context)
                    (declare (ignore event context))
                    (incf settles)
                    (when (= settles 1)
                      '(:entries
                        ((:type :custom-message
                          :custom-type "note"
                          :content "settle continue"))
                        :continue t)))))))
            (host (make-test-extension-host (list bundle)))
            (*responses*
              (list
               (assistant
                (list (make-text-content :text "one")))
               (assistant
                (list (make-text-content :text "two")))))
            (*contexts* nil)
            (stream (faux-stream '*responses* '*contexts*))
            (agent
              (make-agent
               :provider :mock
               :model (mock-model)
               :session session
               :extension-host host
               :stream-function
               (lambda (&rest arguments)
                 (incf provider-calls)
                 (apply stream arguments)))))
       (declare (special *responses* *contexts*))
       (agent-prompt agent "Hi")
       (is (= 2 provider-calls))
       (is (find "settle continue"
                 (agent-messages agent)
                 :key (lambda (message)
                        (and (typep message 'cadr-ai:user-message)
                             (cadr-ai:user-message-content message)))
                 :test #'equal))))))

(defun prompt-context (agent)
  (agent-prompt agent "Hi")
  (first *contexts*))

(test context-handler-omits-system-messages-and-restores-the-request
  (let* ((declared
           (make-tool :name "declared" :description "from the transcript"))
         (registry-tool
           (make-tool :name "registry" :description "executable"))
         (system
           (cadr-agent:make-agent-system-message
            :content "transcript prompt"
            :tools-added (list declared)))
         (seen nil)
         (bundle
           (make-test-extension-bundle
            "context-restore"
            (lambda ()
              (cadr-agent:define-event-hook
               :context
               :handler
               (lambda (event context)
                 (declare (ignore context))
                 (setf seen
                       (getf
                        (cadr-agent:extension-event-payload event)
                        :messages))
                 (list :messages (last seen)))))))
         (host (make-test-extension-host (list bundle)))
         (*responses*
           (list
            (assistant
             (list (make-text-content :text "ok")))))
         (*contexts* nil)
         (agent
           (make-agent
            :provider :mock
            :model (mock-model)
            :system-prompt "agent prompt"
            :tools (list registry-tool)
            :messages (list system)
            :extension-host host
            :stream-function
            (faux-stream '*responses* '*contexts*))))
    (declare (special *responses* *contexts*))
    (let ((context (prompt-context agent)))
    (is (every
         (lambda (message)
           (not (cadr-agent:agent-system-message-p message)))
         seen))
    (is (string=
         "transcript prompt"
         (cadr-ai:context-system-prompt context)))
    (is (equal
         '("declared")
         (mapcar #'cadr-ai:tool-name
                 (cadr-ai:context-tools context)))))))

(test context-with-system-replaces-the-request-prompt
  (let* ((system
           (cadr-agent:make-agent-system-message
            :content "original prompt"))
         (bundle
           (make-test-extension-bundle
            "context-with-system"
            (lambda ()
              (cadr-agent:define-event-hook
               :context-with-system
               :handler
               (lambda (event context)
                 (declare (ignore context))
                 (let ((messages
                         (getf
                          (cadr-agent:extension-event-payload
                           event)
                          :messages)))
                   (is (cadr-agent:agent-system-message-p (first messages)))
                   (list
                    :messages
                    (cons
                     (cadr-agent:make-agent-system-message
                      :content "replaced prompt")
                     (rest messages)))))))))
         (host (make-test-extension-host (list bundle)))
         (*responses*
           (list
            (assistant
             (list (make-text-content :text "ok")))))
         (*contexts* nil)
         (agent
           (make-agent
            :provider :mock
            :model (mock-model)
            :system-prompt "agent prompt"
            :messages (list system)
            :extension-host host
            :stream-function
            (faux-stream '*responses* '*contexts*))))
    (declare (special *responses* *contexts*))
    (is (string=
         "replaced prompt"
         (cadr-ai:context-system-prompt (prompt-context agent))))))

(test context-with-system-drop-reports-a-missing-prompt
  (let* ((*notifications* nil)
         (system
           (cadr-agent:make-agent-system-message
            :content "original prompt"))
         (bundle
           (make-test-extension-bundle
            "context-drop-system"
            (lambda ()
              (cadr-agent:define-event-hook
               :context-with-system
               :handler
               (lambda (event context)
                 (declare (ignore context))
                 (list
                  :messages
                  (cadr-agent::conversation-messages
                   (getf
                    (cadr-agent:extension-event-payload event)
                    :messages))))))))
         (host
           (make-test-extension-host
            (list bundle)
            :notifications '*notifications*))
         (*responses*
           (list
            (assistant
             (list (make-text-content :text "ok")))))
         (*contexts* nil)
         (agent
           (make-agent
            :provider :mock
            :model (mock-model)
            :system-prompt "agent prompt"
            :messages (list system)
            :extension-host host
            :stream-function
            (faux-stream '*responses* '*contexts*))))
    (declare (special *notifications* *responses* *contexts*))
    (let ((context (prompt-context agent)))
    (is (null (cadr-ai:context-system-prompt context)))
    (is (null (cadr-ai:context-tools context)))
    (is (search
         "leading system message"
         (second (first *notifications*)))))))
