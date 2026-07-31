(in-package #:cadr-agent/tests)
(in-suite cadr-agent-suite)

(defmacro with-shutdown-test-session ((session) &body body)
  `(uiop:with-temporary-file
       (:pathname marker :keep t)
     (delete-file marker)
     (let* ((directory
              (uiop:ensure-directory-pathname
               (format nil "~A-session/"
                       (namestring marker))))
            (,session
              (cadr-agent::create-session
               :directory directory
               :cwd (uiop:getcwd))))
       (unwind-protect
            (progn ,@body)
         (when (probe-file directory)
           (uiop:delete-directory-tree
            directory
            :validate t
            :if-does-not-exist :ignore))))))

(test shutdown-is-permanent-idempotent-and-awaits-active-prompt
  (let* ((entered
           (sb-thread:make-semaphore :count 0))
         (release
           (sb-thread:make-semaphore :count 0))
         (shutdown-finished
           (sb-thread:make-semaphore :count 0))
         (agent nil)
         (provider-calls 0)
         (prompt-thread nil)
         (shutdown-thread nil))
    (labels
        ((stream
             (provider model context on-event
              &key max-tokens temperature abort-p)
           (declare
            (ignore provider model context max-tokens temperature))
           (incf provider-calls)
           (sb-thread:signal-semaphore entered)
           (sb-thread:wait-on-semaphore release)
           (let ((message
                   (assistant
                    (list
                     (make-text-content :text "finished"))
                    (if (and abort-p (funcall abort-p))
                        :aborted
                        :stop))))
             (funcall
              on-event
              (make-stream-event
               :type :start :message message))
             message)))
      (setf
       agent
       (make-agent
        :provider :mock
        :model (mock-model)
        :stream-function #'stream)
       prompt-thread
       (sb-thread:make-thread
        (lambda ()
          (agent-prompt agent "hello"))))
      (sb-thread:wait-on-semaphore entered)
      (cadr-agent:agent-steer agent "queued steer")
      (cadr-agent:agent-follow-up agent "queued follow-up")
      (cadr-agent:agent-next-turn agent "queued next")
      (setf
       shutdown-thread
       (sb-thread:make-thread
        (lambda ()
          (cadr-agent:agent-shutdown agent)
          (cadr-agent:agent-shutdown agent)
          (sb-thread:signal-semaphore shutdown-finished))))
      (is
       (not
        (sb-thread:wait-on-semaphore
         shutdown-finished :timeout 0.05)))
      (sb-thread:signal-semaphore release)
      (sb-thread:join-thread prompt-thread)
      (sb-thread:join-thread shutdown-thread)
      (is (= 1 provider-calls))
      (is (cadr-agent:agent-shutdown-p agent))
      (multiple-value-bind
            (steering follow-up next-turn)
          (cadr-agent::agent-queue-snapshot agent)
        (is (null steering))
        (is (null follow-up))
        (is (null next-turn)))
      (signals cadr-agent:agent-shutdown-error
        (cadr-agent:agent-prompt agent "again"))
      (signals cadr-agent:agent-shutdown-error
        (cadr-agent:agent-next-turn agent "again")))))

(test shutdown-during-preflight-prevents-provider-start
  (let* ((entered
           (sb-thread:make-semaphore :count 0))
         (release
           (sb-thread:make-semaphore :count 0))
         (provider-calls 0)
         (agent
           (make-agent
            :provider :mock
            :model (mock-model)
            :stream-function
            (lambda (&rest arguments)
              (declare (ignore arguments))
              (incf provider-calls)
              (assistant nil))))
         (prompt-error nil)
         (prompt-thread
           (sb-thread:make-thread
            (lambda ()
              (handler-case
                  (agent-prompt
                   agent "hello"
                   :preflight-function
                   (lambda ()
                     (sb-thread:signal-semaphore entered)
                     (sb-thread:wait-on-semaphore release)))
                (error (condition)
                  (setf prompt-error condition)))))))
    (sb-thread:wait-on-semaphore entered)
    (let ((shutdown-thread
            (sb-thread:make-thread
             (lambda ()
               (cadr-agent:agent-shutdown agent)))))
      (sb-thread:signal-semaphore release)
      (sb-thread:join-thread prompt-thread)
      (sb-thread:join-thread shutdown-thread))
    (is (typep prompt-error
               'cadr-agent:agent-shutdown-error))
    (is (zerop provider-calls))))

(test wait-for-idle-ignores-mutations-but-shutdown-awaits-them
  (let* ((agent
           (make-agent
            :provider :mock
            :model (mock-model)))
         (entered
           (sb-thread:make-semaphore :count 0))
         (release
           (sb-thread:make-semaphore :count 0))
         (mutation-thread
           (sb-thread:make-thread
            (lambda ()
              (cadr-agent::call-with-agent-mutation
               agent
               (lambda ()
                 (sb-thread:signal-semaphore entered)
                 (sb-thread:wait-on-semaphore release))))))
         (shutdown-finished
           (sb-thread:make-semaphore :count 0)))
    (sb-thread:wait-on-semaphore entered)
    (cadr-agent:agent-wait-for-idle agent)
    (let ((shutdown-thread
            (sb-thread:make-thread
             (lambda ()
               (cadr-agent:agent-shutdown agent)
               (sb-thread:signal-semaphore
                shutdown-finished)))))
      (is
       (not
        (sb-thread:wait-on-semaphore
         shutdown-finished :timeout 0.05)))
      (sb-thread:signal-semaphore release)
      (sb-thread:join-thread mutation-thread)
      (sb-thread:join-thread shutdown-thread)
      (is
       (sb-thread:wait-on-semaphore
        shutdown-finished :timeout 0.05)))))

(test shutdown-prevents-compaction-result-and-tree-move
  (with-shutdown-test-session (session)
    (let ((first
            (cadr-agent::session-append-message
             session
             (cadr-ai:make-user-message
              :content (make-string 80
                                    :initial-element #\a))))
          (entered
            (sb-thread:make-semaphore :count 0))
          (release
            (sb-thread:make-semaphore :count 0)))
      (cadr-agent::session-append-message
       session
       (assistant
        (list
         (make-text-content
          :text (make-string 80
                             :initial-element #\b)))))
      (cadr-agent::session-append-message
       session
       (cadr-ai:make-user-message
        :content
        (make-string 80 :initial-element #\c)))
      (let* ((original-leaf
               (cadr-agent::session-leaf-id session))
             (agent
               (make-agent
                :provider :mock
                :model
                (make-model
                 :id "mock"
                 :provider :openai
                 :api :openai-responses
                 :base-url "https://example.invalid"
                 :max-tokens 128
                 :context-window 128)
                :session session
                :stream-function
                (lambda
                    (provider model context on-event
                     &key max-tokens temperature abort-p)
                  (declare
                   (ignore provider model context on-event
                           max-tokens temperature abort-p))
                  (sb-thread:signal-semaphore entered)
                  (sb-thread:wait-on-semaphore release)
                  (assistant
                   (list
                    (make-text-content
                     :text "summary"))))))
             (compaction-thread
               (sb-thread:make-thread
                (lambda ()
                  (cadr-agent:compact-agent
                   agent :force-p t)))))
        (sb-thread:wait-on-semaphore entered)
        (let ((shutdown-thread
                (sb-thread:make-thread
                 (lambda ()
                   (cadr-agent:agent-shutdown agent)))))
          (sb-thread:signal-semaphore release)
          (sb-thread:join-thread compaction-thread)
          (sb-thread:join-thread shutdown-thread))
        (is
         (null
          (find :compaction
                (cadr-agent::session-entries session)
                :key #'cadr-agent::session-entry-type)))
        (is (string= original-leaf
                     (cadr-agent::session-leaf-id session)))
        (signals cadr-agent:agent-shutdown-error
          (cadr-agent:agent-navigate-tree
           agent first))))))

(test shutdown-awaits-active-tree-navigation-and-preserves-leaf
  (with-shutdown-test-session (session)
    (let* ((target
             (cadr-agent::session-append-message
              session
              (cadr-ai:make-user-message
               :content "target")))
           (_reply
             (cadr-agent::session-append-message
              session
              (assistant
               (list
                (make-text-content :text "reply")))))
           (original-leaf
             (cadr-agent::session-append-message
              session
              (cadr-ai:make-user-message
               :content "current")))
           (entered
             (sb-thread:make-semaphore :count 0))
           (release
             (sb-thread:make-semaphore :count 0))
           (bundle
             (make-test-extension-bundle
              "blocking-tree"
              (lambda ()
                (cadr-agent:define-event-hook
                 :session-before-tree
                 :handler
                 (lambda (event context)
                   (declare (ignore event context))
                   (sb-thread:signal-semaphore entered)
                   (sb-thread:wait-on-semaphore release)
                   nil)))))
           (agent
             (make-agent
              :provider :mock
              :model (mock-model)
              :session session
              :extension-host
              (make-test-extension-host
               (list bundle))))
           (navigation-error nil)
           (navigation-thread
             (sb-thread:make-thread
              (lambda ()
                (handler-case
                    (cadr-agent:agent-navigate-tree
                     agent target)
                  (error (condition)
                    (setf navigation-error condition)))))))
      (declare (ignore _reply))
      (sb-thread:wait-on-semaphore entered)
      (let* ((shutdown-finished
              (sb-thread:make-semaphore :count 0))
            (shutdown-thread
              (sb-thread:make-thread
               (lambda ()
                 (cadr-agent:agent-shutdown agent)
                 (sb-thread:signal-semaphore
                  shutdown-finished)))))
        (is
         (not
          (sb-thread:wait-on-semaphore
           shutdown-finished :timeout 0.05)))
        (sb-thread:signal-semaphore release)
        (sb-thread:join-thread navigation-thread)
        (sb-thread:join-thread shutdown-thread)
        (is
         (typep navigation-error
                'cadr-agent:agent-shutdown-error))
        (is
         (string= original-leaf
                  (cadr-agent::session-leaf-id
                   session)))))))
