(in-package #:cadr-agent/tests)
(in-suite cadr-agent-suite)

(test goal18-nil-model-manual-compaction-emits-baseline-failure-events
  ;; Baseline agent-session.ts:1790-1800,1905-1916 — manual compact
  ;; with the unknown sentinel model emits compaction_start, then
  ;; compaction_end with "Compaction failed: <NoApiKeyFound text>".
  (let* ((events nil)
         (agent
           (cadr-agent:make-agent
            :provider :mock
            :model nil
            :on-event (lambda (event) (push event events)))))
    (is-false (cadr-agent:compact-agent agent :force-p t))
    (let ((start
           (find :compaction-start events
                 :key #'cadr-agent:agent-event-type))
          (end
           (find :compaction-end events
                 :key #'cadr-agent:agent-event-type)))
      (is (not (null start)))
      (is (not (null end)))
      (is (string=
           (format nil "Compaction failed: ~A"
                   (cadr-ai::no-api-key-found-message "unknown"))
           (cadr-agent:agent-event-error-message end))))))

(defun context-contains-text-p (context needle)
  (let ((messages
          (if (typep context 'cadr-ai:context)
              (cadr-ai:context-messages context)
              context)))
    (some
     (lambda (message)
       (cond
         ((typep message 'cadr-ai:user-message)
          (let ((content (cadr-ai:user-message-content message)))
            (and (stringp content)
                 (search needle content))))
         ((typep message 'cadr-ai:assistant-message)
          (some
           (lambda (block)
             (and (typep block 'cadr-ai:text-content)
                  (search needle
                          (cadr-ai:text-content-text block))))
           (cadr-ai:assistant-message-content message)))
         (t nil)))
     messages)))

(defun compaction-test-response
    (text stop-reason &optional error-message)
  (cadr-ai:make-assistant-message
   :content
   (and text
        (list
         (cadr-ai:make-text-content :text text)))
   :api :openai-responses
   :provider :openai
   :model "tiny"
   :usage
   (cadr-ai:make-usage :input 60 :output 20 :total 80)
   :stop-reason stop-reason
   :error-message error-message))

(defun compaction-test-model ()
  (cadr-ai:make-model
   :id "tiny"
   :provider :openai
   :api :openai-responses
   :base-url "https://example.invalid"
   :max-tokens 32
   :context-window 100))

(test compaction-summary-failure-contract-matches-baseline
  (dolist
      (case
       (list
        (list :stop "complete")
        (list :tool-use "tool-use text")
        (list :aborted "partial before abort")
        (list :stop "")
        (list :stop (format nil " ~C~%" #\Tab))))
    (destructuring-bind (stop-reason expected) case
      (let* ((*responses*
               (list
                (compaction-test-response
                 expected stop-reason)))
             (*contexts* nil)
             (agent
               (cadr-agent:make-agent
                :provider :mock
                :model (compaction-test-model)
                :stream-function
                (faux-stream '*responses* '*contexts*))))
        (declare (special *responses* *contexts*))
        (is
         (string=
          expected
          (cadr-agent::generate-compaction-summary
           agent nil 16)))
        (is (null *responses*)))))
  (let* ((*contexts* nil)
         (agent
           (cadr-agent:make-agent
            :provider :mock
            :model (compaction-test-model)
            :stream-function
            (lambda (provider model context on-event
                     &key max-tokens abort-p cache-retention session-id)
              (declare
               (ignore provider model on-event
                       max-tokens abort-p cache-retention session-id))
              (push context *contexts*)
              nil))))
    (declare (special *contexts*))
    (is
     (string=
      ""
      (cadr-agent::generate-compaction-summary
       agent nil 16))))
  (dolist
      (case
       (list
        (list :error "provider failed" nil
              "Summarization failed: provider failed")
        (list :error nil nil
              "Summarization failed: Unknown error")
        (list :length "partial summary" nil
              "Summarization failed: generation hit the token cap and the summary is incomplete")))
    (destructuring-bind (kind provider-error summary-text expected) case
      (let* ((*responses*
               (list
                (if (eq kind :length)
                    (compaction-test-response summary-text :length)
                    (compaction-test-response nil :error provider-error))))
             (*contexts* nil)
             (agent
               (cadr-agent:make-agent
                :provider :mock
                :model (compaction-test-model)
                :stream-function
                (faux-stream '*responses* '*contexts*))))
        (declare (special *responses* *contexts*))
        (handler-case
            (progn
              (cadr-agent::generate-compaction-summary
               agent nil 16)
              (fail "Expected compaction summary failure"))
          (error (condition)
            (is
             (string=
              expected
              (princ-to-string condition)))))))))

(test empty-and-whitespace-compaction-summaries-persist-and-continue
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (loop
      for summary in (list "" (format nil " ~C~%" #\Tab))
      for index from 1
      do
      (let* ((session
               (cadr-agent:create-session
                :directory sessions :cwd cwd
                :id (format nil "empty-summary-~D" index)))
             (_discarded-user
               (cadr-agent:session-append-message
                session
                (cadr-ai:make-user-message
                 :content
                 (concatenate
                  'string "discarded context "
                  (make-string 40 :initial-element #\d)))))
             (_discarded-assistant
               (cadr-agent:session-append-message
                session
                (compaction-test-response
                 (concatenate
                  'string "discarded answer "
                  (make-string 40 :initial-element #\e))
                 :stop)))
             (_old-user
               (cadr-agent:session-append-message
                session
                (cadr-ai:make-user-message
                 :content
                 (concatenate
                  'string "old context "
                  (make-string 120 :initial-element #\x)))))
             (_old-assistant
               (cadr-agent:session-append-message
                session
                (compaction-test-response
                 (concatenate
                  'string "old answer "
                  (make-string 120 :initial-element #\y))
                 :stop)))
             (*responses*
               (list
                (compaction-test-response summary :stop)
                (cadr-ai:make-assistant-message
                 :content
                 (list
                  (cadr-ai:make-text-content :text "continued"))
                 :api :openai-responses
                 :provider :openai
                 :model "tiny"
                 :usage
                 (cadr-ai:make-usage
                  :input 30 :output 2 :total 32)
                 :stop-reason :stop)))
             (*contexts* nil)
             (agent
               (cadr-agent:make-agent
                :provider :mock
                :model (compaction-test-model)
                :session session
                :compaction-reserve-tokens 21
                :compaction-keep-recent-tokens 40
                :stream-function
                (faux-stream '*responses* '*contexts*))))
        (declare
         (ignore _discarded-user _discarded-assistant
                 _old-user _old-assistant)
         (special *responses* *contexts*))
        (let ((result
                (cadr-agent:agent-prompt
                 agent "current request")))
          (is
           (string=
            "continued"
            (cadr-ai:text-content-text
             (first
              (cadr-ai:assistant-message-content result)))))
          (is-false (cadr-agent:agent-busy-p agent))
          (let ((entry
                  (find
                   :compaction
                   (cadr-agent:session-entries session)
                   :key #'cadr-agent:session-entry-type)))
            (is (not (null entry)))
            (is
             (string=
              summary
              (cadr-agent:session-entry-summary entry))))
          (let* ((loaded
                   (cadr-agent:load-session
                    (cadr-agent:session-path session)))
                 (entry
                   (find
                    :compaction
                    (cadr-agent:session-entries loaded)
                    :key #'cadr-agent:session-entry-type)))
            (is (not (null entry)))
            (is
             (string=
              summary
              (cadr-agent:session-entry-summary entry))))
          (is (null *responses*)))))))

(test extension-compaction-allows-empty-and-whitespace-summaries
  (dolist (summary (list "" (format nil " ~C~%" #\Tab)))
    (is-true
     (cadr-agent::usable-extension-compaction-p
      (list
       :summary summary
       :first-kept-entry-id "entry"
       :tokens-before 0)))))

(test user-abort-after-summary-response-does-not-persist-compaction
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let* ((session
             (cadr-agent:create-session
              :directory sessions :cwd cwd
              :id "aborted-compaction"))
           (_old-user
             (cadr-agent:session-append-message
              session
              (cadr-ai:make-user-message
               :content
               (format nil "old context ~120@{x~}"))))
           (_old-assistant
             (cadr-agent:session-append-message
              session
              (compaction-test-response "old answer" :stop)))
           (agent nil))
      (declare (ignore _old-user _old-assistant))
      (setf
       agent
       (cadr-agent:make-agent
        :provider :mock
        :model (compaction-test-model)
        :session session
        :compaction-keep-recent-tokens 4
        :stream-function
        (lambda (provider model context on-event
                 &key max-tokens abort-p cache-retention session-id)
          (declare
           (ignore provider model context on-event
                   max-tokens abort-p cache-retention session-id))
          (cadr-agent:agent-abort agent)
          (compaction-test-response
           "partial summary" :aborted))))
      (is-false
       (cadr-agent:compact-agent agent :force-p t))
      (is
       (zerop
        (count
         :compaction
         (cadr-agent:session-entries session)
         :key #'cadr-agent:session-entry-type))))))


(test g21-length-limited-compaction-summary-is-not-persisted
  ;; pi#7048 / 97fa14e: length-stopped summaries must fail before appendCompaction.
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let* ((session
             (cadr-agent:create-session
              :directory sessions :cwd cwd
              :id "length-limited-compaction"))
           (_old-user
             (cadr-agent:session-append-message
              session
              (cadr-ai:make-user-message
               :content
               (format nil "old context ~120@{x~}"))))
           (_old-assistant
             (cadr-agent:session-append-message
              session
              (compaction-test-response "old answer" :stop)))
           (agent nil))
      (declare (ignore _old-user _old-assistant))
      (setf
       agent
       (cadr-agent:make-agent
        :provider :mock
        :model (compaction-test-model)
        :session session
        :compaction-keep-recent-tokens 4
        :stream-function
        (lambda (provider model context on-event
                 &key max-tokens abort-p cache-retention session-id)
          (declare
           (ignore provider model context on-event
                   max-tokens abort-p cache-retention session-id))
          (compaction-test-response "partial summar" :length))))
      (is-false
       (cadr-agent:compact-agent agent :force-p t))
      (is
       (zerop
        (count
         :compaction
         (cadr-agent:session-entries session)
         :key #'cadr-agent:session-entry-type))))))

(test g21-session-compact-failed-notifies-extensions-on-auto-compaction-failure
  ;; pi@d981de122 agent-session-compaction.test.ts notifies extensions when
  ;; auto-compaction fails.
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let* ((failed-payload nil)
           (bundle
             (make-test-extension-bundle
              "session-compact-failed"
              (lambda ()
                (cadr-agent:define-event-hook
                 :session-compact-failed
                 :handler
                 (lambda (event context)
                   (declare (ignore context))
                   (setf failed-payload
                         (cadr-agent:extension-event-payload event))
                   nil)))))
           (host (make-test-extension-host (list bundle)))
           (session
             (cadr-agent:create-session
              :directory sessions :cwd cwd
              :id "auto-compaction-failure")))
      (cadr-agent:session-append-message
       session
       (cadr-ai:make-user-message
        :content (make-string 80 :initial-element #\a)))
      (cadr-agent:session-append-message
       session
       (compaction-test-response
        (make-string 80 :initial-element #\b) :stop))
      (cadr-agent:session-append-message
       session
       (cadr-ai:make-user-message :content "keep"))
      (let ((agent
              (cadr-agent:make-agent
               :provider :mock
               :model (compaction-test-model)
               :session session
               :extension-host host
               :compaction-keep-recent-tokens 1
               :stream-function
               (lambda (&rest arguments)
                 (declare (ignore arguments))
                 (error "summary generator blew up")))))
        (is-false
         (cadr-agent:compact-agent
          agent :force-p t :reason :threshold))
        (is (equal :threshold (getf failed-payload :reason)))
        (is-false (getf failed-payload :aborted))
        (is-false (getf failed-payload :will-retry-p))
        (is-false (getf failed-payload :from-extension-p))
        (is
         (string=
          "Auto-compaction failed: summary generator blew up"
          (getf failed-payload :error-message)))))))

(test failed-overflow-compaction-leaves-session-usable
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let* ((session
             (cadr-agent:create-session
              :directory sessions :cwd cwd
              :id "failed-overflow-compaction"))
           (_old-user
             (cadr-agent:session-append-message
              session
              (cadr-ai:make-user-message
               :content
               (format nil "old context ~120@{x~}"))))
           (_old-assistant
             (cadr-agent:session-append-message
              session
              (compaction-test-response "old answer" :stop)))
           (*responses*
             (list
              (compaction-test-response
               nil :error
               "context_length_exceeded: maximum context length")
              (compaction-test-response
               nil :error "summary provider failed")
              (compaction-test-response "later answer" :stop)))
           (*contexts* nil)
           (events nil)
           (agent
             (cadr-agent:make-agent
              :provider :mock
              :model (compaction-test-model)
              :session session
              :auto-compact-p nil
              :compaction-keep-recent-tokens 4
              :stream-function
              (faux-stream '*responses* '*contexts*)
              :on-event (lambda (event) (push event events)))))
      (declare
       (ignore _old-user _old-assistant)
       (special *responses* *contexts*))
      (let ((failed
              (cadr-agent:agent-prompt agent "overflow now")))
        (is
         (eq :error
             (cadr-ai:assistant-message-stop-reason failed)))
        (is-false (cadr-agent:agent-busy-p agent))
        (is
         (string=
          "Context overflow recovery failed: Turn prefix summarization failed: summary provider failed"
          (cadr-agent:agent-event-error-message
           (find
            :compaction-end events
            :key #'cadr-agent:agent-event-type)))))
      (let ((continued
              (cadr-agent:agent-prompt agent "continue anyway")))
        (is
         (string=
          "later answer"
          (cadr-ai:text-content-text
           (first
            (cadr-ai:assistant-message-content continued)))))
        (is-false (cadr-agent:agent-busy-p agent))
        (is (null *responses*))
        (is
         (zerop
          (count
           :compaction
           (cadr-agent:session-entries session)
           :key #'cadr-agent:session-entry-type)))))))

(test branch-summary-uses-baseline-empty-fallback
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let* ((session
             (cadr-agent:create-session
              :directory sessions :cwd cwd
              :id "empty-branch-summary"))
           (_entry
             (cadr-agent:session-append-message
              session
              (cadr-ai:make-user-message :content "branch")))
           (*responses*
             (list
              (compaction-test-response "" :stop)))
           (*contexts* nil)
           (agent
             (cadr-agent:make-agent
              :provider :mock
              :model (compaction-test-model)
              :session session
              :stream-function
              (faux-stream '*responses* '*contexts*))))
      (declare
       (ignore _entry)
       (special *responses* *contexts*))
      (let ((cadr-agent::+branch-summary-preamble+ ""))
        (is
         (string=
          "No summary generated"
          (cadr-agent:branch-summary-result-summary
           (cadr-agent:generate-branch-summary
            agent
            (cadr-agent:session-entries session)))))))))

(test aborted-branch-summary-cancels-without-moving-the-session
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let* ((session
             (cadr-agent:create-session
              :directory sessions :cwd cwd
              :id "aborted-branch-summary"))
           (root
             (cadr-agent:session-append-message
              session
              (cadr-ai:make-user-message :content "root")))
           (_branch
             (cadr-agent:session-append-message
              session
              (compaction-test-response "branch" :stop)))
           (_tail
             (cadr-agent:session-append-message
              session
              (cadr-ai:make-user-message :content "tail")))
           (original-leaf
             (cadr-agent:session-leaf-id session))
           (*responses*
             (list
              (compaction-test-response
               "partial summary" :aborted)))
           (*contexts* nil)
           (agent
             (cadr-agent:make-agent
              :provider :mock
              :model (compaction-test-model)
              :session session
              :stream-function
              (faux-stream '*responses* '*contexts*))))
      (declare
       (ignore _branch _tail)
       (special *responses* *contexts*))
      (multiple-value-bind
            (messages cancelled-p editor-text summary-entry)
          (cadr-agent:agent-navigate-tree
           agent root :summarize-p t)
        (is (null messages))
        (is-true cancelled-p)
        (is (null editor-text))
        (is (null summary-entry))
        (is
         (string=
          original-leaf
          (cadr-agent:session-leaf-id session)))
        (is (null *responses*))))))

(test automatic-compaction-uses-current-model-and-continues-the-prompt
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let* ((session
             (cadr-agent:create-session
              :directory sessions :cwd cwd :id "compact"))
           (old-user-id
             (cadr-agent:session-append-message
              session
              (cadr-ai:make-user-message
               :content
               (concatenate
                'string "old-secret-user "
                (make-string 120 :initial-element #\x)))))
           (old-assistant-id
             (cadr-agent:session-append-message
              session
              (cadr-ai:make-assistant-message
               :content
               (list
                (cadr-ai:make-text-content
                 :text
                 (concatenate
                  'string "old-secret-assistant "
                  (make-string 120 :initial-element #\y))))
               :api :openai-responses
               :provider :openai
               :model "tiny"
               :usage (cadr-ai:make-usage
                       :input 60 :output 20 :total 80)
               :stop-reason :stop)))
           (*responses*
             (list
              (cadr-ai:make-assistant-message
               :content
               (list
                (cadr-ai:make-text-content
                 :text "checkpoint-summary"))
               :api :openai-responses
               :provider :openai
               :model "tiny"
               :usage (cadr-ai:make-usage
                       :input 60 :output 5 :total 65)
               :stop-reason :stop)
              (cadr-ai:make-assistant-message
               :content
               (list
                (cadr-ai:make-text-content :text "continued"))
               :api :openai-responses
               :provider :openai
               :model "tiny"
               :usage (cadr-ai:make-usage
                       :input 30 :output 2 :total 32)
               :stop-reason :stop)))
           (*contexts* nil)
           (before-payload nil)
           (after-payload nil)
           (bundle
             (make-test-extension-bundle
              "threshold-compaction-events"
              (lambda ()
                (cadr-agent:define-event-hook
                 :session-before-compact
                 :handler
                 (lambda (event context)
                   (declare (ignore context))
                   (setf before-payload
                         (cadr-agent:extension-event-payload event))
                   nil))
                (cadr-agent:define-event-hook
                 :session-compact
                 :handler
                 (lambda (event context)
                   (declare (ignore context))
                   (setf after-payload
                         (cadr-agent:extension-event-payload event))
                   nil)))))
           (host (make-test-extension-host (list bundle)))
           (model
             (cadr-ai:make-model
              :id "tiny"
              :provider :openai
              :api :openai-responses
              :base-url "https://example.invalid"
              :max-tokens 32
              :context-window 100))
           (agent
             (cadr-agent:make-agent
              :provider :current-provider
              :model model
              :session session
              :extension-host host
              :compaction-reserve-tokens 21
              :compaction-keep-recent-tokens 4
              :stream-function
              (faux-stream '*responses* '*contexts*))))
      (declare (special *responses* *contexts*))
      (let ((result
              (cadr-agent:agent-prompt
               agent "current request must survive")))
        (is (string=
             "continued"
             (cadr-ai:text-content-text
              (first
               (cadr-ai:assistant-message-content result)))))
        (is (eq :threshold (getf before-payload :reason)))
        (is-false (getf before-payload :will-retry-p))
        (is (eq :threshold (getf after-payload :reason)))
        (is-false (getf after-payload :will-retry-p))
        (is-false (getf after-payload :from-extension-p))
        (is (null *responses*))
        (let* ((contexts (nreverse *contexts*))
               (summary-context (first contexts))
               (request-context (second contexts)))
          (is (= 2 (length contexts)))
          (is (context-contains-text-p
               summary-context "old-secret-user"))
          (is (context-contains-text-p
               request-context "checkpoint-summary"))
          (is (context-contains-text-p
               request-context "current request must survive"))
          (is (not
               (context-contains-text-p
                request-context "old-secret-user"))))
        (let* ((entries (cadr-agent:session-entries session))
               (compaction
                 (find :compaction entries
                       :key #'cadr-agent:session-entry-type)))
          (is (not (null compaction)))
          (is (member old-user-id
                      (cadr-agent:session-entry-source-ids compaction)
                      :test #'string=))
          (is-false
           (member old-assistant-id
                   (cadr-agent:session-entry-source-ids compaction)
                   :test #'string=))
          (is (stringp
               (cadr-agent:session-entry-first-kept-id
                compaction)))
          (let ((file
                  (uiop:read-file-string
                   (cadr-agent:session-path session)
                   :external-format :utf-8)))
            (is (search "old-secret-user" file))
            (is (not (search "\"sourceIds\"" file)))
            (is (search "checkpoint-summary" file))))
        (let ((loaded
                (cadr-agent:load-session
                 (cadr-agent:session-path session))))
          (is (context-contains-text-p
               (cadr-agent:session-messages loaded)
               "checkpoint-summary"))
          (is (not
               (context-contains-text-p
                (cadr-agent:session-messages loaded)
                "old-secret-user"))))))))

(test compaction-does-not-trigger-when-model-has-no-context-window
  (let* ((*responses*
           (list
            (assistant
             (list (make-text-content :text "one response")))))
         (*contexts* nil)
         (agent
           (make-agent
            :provider :mock
            :model (mock-model)
            :messages
            (list
             (cadr-ai:make-user-message
              :content (make-string 10000
                                    :initial-element #\x)))
            :stream-function
            (faux-stream '*responses* '*contexts*))))
    (declare (special *responses* *contexts*))
    (agent-prompt agent "still direct")
    (is (= 1 (length *contexts*)))
    (is (null *responses*))))

(test context-overflow-compacts-once-and-retries-without-the-error-branch
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let* ((session
             (cadr-agent:create-session
              :directory sessions :cwd cwd
              :id "overflow"))
           (_old-user
             (cadr-agent:session-append-message
              session
              (cadr-ai:make-user-message
               :content
               (concatenate
                'string "old overflow context "
                (make-string 100 :initial-element #\x)))))
           (_old-assistant
             (cadr-agent:session-append-message
              session
              (cadr-ai:make-assistant-message
               :content
               (list
                (cadr-ai:make-text-content
                 :text "old response"))
               :api :openai-responses
               :provider :openai
               :model "tiny"
               :stop-reason :stop)))
           (*responses*
             (list
              (cadr-ai:make-assistant-message
               :api :openai-responses
               :provider :openai
               :model "tiny"
               :stop-reason :error
               :error-message
               "context_length_exceeded: maximum context length")
              (cadr-ai:make-assistant-message
               :content
               (list
                (cadr-ai:make-text-content
                 :text "overflow checkpoint"))
               :api :openai-responses
               :provider :openai
               :model "tiny"
               :stop-reason :stop)
              (cadr-ai:make-assistant-message
               :content
               (list
                (cadr-ai:make-text-content
                 :text "recovered"))
               :api :openai-responses
               :provider :openai
               :model "tiny"
               :stop-reason :stop)))
           (*contexts* nil)
           (before-payload nil)
           (after-payload nil)
           (bundle
             (make-test-extension-bundle
              "overflow-compaction-events"
              (lambda ()
                (cadr-agent:define-event-hook
                 :session-before-compact
                 :handler
                 (lambda (event context)
                   (declare (ignore context))
                   (setf before-payload
                         (cadr-agent:extension-event-payload event))
                   nil))
                (cadr-agent:define-event-hook
                 :session-compact
                 :handler
                 (lambda (event context)
                   (declare (ignore context))
                   (setf after-payload
                         (cadr-agent:extension-event-payload event))
                   nil)))))
           (host (make-test-extension-host (list bundle)))
           (model
             (cadr-ai:make-model
              :id "tiny"
              :provider :openai
              :api :openai-responses
              :base-url "https://example.invalid"
              :max-tokens 32
              :context-window 100))
           (agent
             (cadr-agent:make-agent
              :provider :current-provider
              :model model
              :session session
              :extension-host host
              :auto-compact-p nil
              :compaction-keep-recent-tokens 4
              :stream-function
              (faux-stream '*responses* '*contexts*))))
      (declare
       (ignore _old-user _old-assistant)
       (special *responses* *contexts*))
      (let ((result
              (cadr-agent:agent-prompt
               agent "retry this request")))
        (is (string=
             "recovered"
             (cadr-ai:text-content-text
              (first
               (cadr-ai:assistant-message-content result)))))
        (is (eq :overflow (getf before-payload :reason)))
        (is-true (getf before-payload :will-retry-p))
        (is (eq :overflow (getf after-payload :reason)))
        (is-true (getf after-payload :will-retry-p))
        (is-false (getf after-payload :from-extension-p))
        (is (null *responses*))
        (is (= 3 (length *contexts*)))
        (is (not
             (context-contains-text-p
              (third (nreverse *contexts*))
              "context_length_exceeded")))
        (let ((entries
                (cadr-agent:session-entries session)))
          (is (= 1
                 (count :compaction entries
                        :key
                        #'cadr-agent:session-entry-type)))
          (is (= 1
                 (count-if
                  (lambda (entry)
                    (and
                     (eq :message
                         (cadr-agent:session-entry-type entry))
                     (typep
                      (cadr-agent:session-entry-message entry)
                      'cadr-ai:assistant-message)
                     (eq
                      :error
                      (cadr-ai:assistant-message-stop-reason
                       (cadr-agent:session-entry-message
                        entry)))))
                  entries))))))))

(defun goal17-compaction-fixture (id stream-function on-event)
  (let* ((root (uiop:ensure-directory-pathname
                (merge-pathnames
                 (format nil "cadr-goal17-~A/" id)
                 (uiop:temporary-directory))))
         (sessions (merge-pathnames "sessions/" root))
         (cwd (merge-pathnames "cwd/" root)))
    (ensure-directories-exist sessions)
    (ensure-directories-exist cwd)
    (let ((session
            (cadr-agent:create-session
             :directory sessions :cwd cwd :id id)))
      (cadr-agent:session-append-message
       session
       (cadr-ai:make-user-message
        :content (format nil "old context ~120@{x~}")))
      (cadr-agent:session-append-message
       session
       (compaction-test-response "old answer" :stop))
      (cadr-agent:session-append-message
       session
       (cadr-ai:make-user-message
        :content "current context remains after compaction"))
      (let ((agent
              (cadr-agent:make-agent
               :provider :mock
               :model (compaction-test-model)
               :session session
               :compaction-keep-recent-tokens 4
               :stream-function stream-function
               :on-event on-event)))
        (setf (cadr-agent::agent-auto-retry-base-delay agent) 0)
        (values
         agent
         session
         root)))))

(test goal17-compaction-start-carries-manual-threshold-and-overflow-reasons
  (dolist (reason '(:manual :threshold :overflow))
    (let ((events nil))
      (multiple-value-bind (agent session root)
          (goal17-compaction-fixture
           (string-downcase (symbol-name reason))
           (lambda (provider model context on-event
                    &key max-tokens abort-p cache-retention session-id)
             (declare
              (ignore provider model context on-event max-tokens
                      abort-p cache-retention session-id))
             (compaction-test-response "summary" :stop))
           (lambda (event) (push event events)))
        (declare (ignore session))
        (unwind-protect
             (progn
               (is-true
                (cadr-agent:compact-agent
                 agent :force-p t :reason reason))
               (let ((start
                       (find :compaction-start events
                             :key #'cadr-agent:agent-event-type)))
                 (is (not (null start)))
                 (is (eq reason
                         (cadr-agent:agent-event-reason start)))))
          (uiop:delete-directory-tree
           root :validate t :if-does-not-exist :ignore))))))

(test goal17-compaction-ignores-thinking-level-metadata
  (multiple-value-bind (agent session root)
      (goal17-compaction-fixture
       "thinking-level-metadata"
       (lambda (provider model context on-event
                &key max-tokens abort-p cache-retention session-id)
         (declare
          (ignore provider model context on-event max-tokens
                  abort-p cache-retention session-id))
         (compaction-test-response "summary" :stop))
       nil)
    (unwind-protect
         (progn
           (cadr-agent:session-append-thinking-level-change
            session "high")
           (let ((metadata
                   (find :thinking-level-change
                         (cadr-agent:session-entries session)
                         :key #'cadr-agent:session-entry-type)))
             (is
              (zerop
               (cadr-agent::compaction-entry-estimated-tokens
                metadata)))
             (is-false
              (search "high"
                      (cadr-agent::entries-summary-text
                       (list metadata)))))
           (is-true
            (cadr-agent:compact-agent
             agent :force-p t :reason :manual))
           (is
            (find :compaction
                  (cadr-agent:session-entries session)
                  :key #'cadr-agent:session-entry-type)))
      (uiop:delete-directory-tree
       root :validate t :if-does-not-exist :ignore))))

(test goal17-compaction-abort-reaches-summary-request-and-preserves-session
  (let ((events nil)
        (observed-abort-p nil)
        (agent nil))
    (multiple-value-bind (created session root)
        (goal17-compaction-fixture
         "abort-during-summary"
         (lambda (provider model context on-event
                  &key max-tokens abort-p cache-retention session-id)
           (declare
            (ignore provider model context on-event max-tokens
                    cache-retention session-id))
           (is (functionp abort-p))
           (cadr-agent:agent-abort agent)
           (setf observed-abort-p (funcall abort-p))
           (compaction-test-response nil :aborted))
         (lambda (event) (push event events)))
      (setf agent created)
      (unwind-protect
           (progn
             (is-false
              (cadr-agent:compact-agent agent :force-p t))
             (is-true observed-abort-p)
             (is
              (zerop
               (count :compaction
                      (cadr-agent:session-entries session)
                      :key #'cadr-agent:session-entry-type)))
             (is (find :compaction-end events
                       :key #'cadr-agent:agent-event-type))
             (let ((event
                     (find :compaction-end events
                           :key #'cadr-agent:agent-event-type)))
               (is (eq :manual
                       (cadr-agent:agent-event-reason event)))
               (is-true
                (cadr-agent:agent-event-aborted event))
               (is-false
                (cadr-agent:agent-event-result event))
               (is-false
                (cadr-agent:agent-event-error-message event))))
        (uiop:delete-directory-tree
         root :validate t :if-does-not-exist :ignore)))))

(test goal17-summarization-retries-transient-errors-with-isolated-request-options
  (let ((events nil)
        (calls nil)
        (responses
          (list
           (compaction-test-response nil :error "terminated")
           (compaction-test-response "summary" :stop))))
    (multiple-value-bind (agent session root)
        (goal17-compaction-fixture
         "retry-transient"
         (lambda (provider model context on-event
                  &key max-tokens abort-p cache-retention session-id)
           (declare
            (ignore provider model context on-event max-tokens abort-p))
           (push (list cache-retention session-id) calls)
           (pop responses))
         (lambda (event) (push event events)))
      (declare (ignore session))
      (unwind-protect
           (progn
             (is-true
              (cadr-agent:compact-agent agent :force-p t))
             (is (= 2 (length calls)))
             (is (every (lambda (call) (eq :none (first call))) calls))
             (is (every (lambda (call)
                          (and (stringp (second call))
                               (plusp (length (second call)))))
                        calls))
             (is (string= (second (first calls))
                          (second (second calls))))
             (is (equal
                  '(:summarization-retry-scheduled
                    :summarization-retry-attempt-start
                    :summarization-retry-finished)
                  (remove-if-not
                   (lambda (type)
                     (member type
                             '(:summarization-retry-scheduled
                               :summarization-retry-attempt-start
                               :summarization-retry-finished)))
                   (reverse (mapcar #'cadr-agent:agent-event-type events)))))
             (let ((finished
                     (find :summarization-retry-finished events
                           :key #'cadr-agent:agent-event-type)))
               (is-false (cadr-agent:agent-event-success finished))
               (is-false (cadr-agent:agent-event-attempt finished))
               (is-false (cadr-agent:agent-event-final-error finished))
               (is-false (cadr-agent:agent-event-source finished))
               (is-false (cadr-agent:agent-event-reason finished))))
        (uiop:delete-directory-tree
         root :validate t :if-does-not-exist :ignore)))))

(test goal17-summarization-does-not-retry-deterministic-errors-or-aborts
  (let ((calls 0))
    (multiple-value-bind (agent session root)
        (goal17-compaction-fixture
         "no-retry-error"
         (lambda (provider model context on-event
                  &key max-tokens abort-p cache-retention session-id)
           (declare
            (ignore provider model context on-event max-tokens abort-p
                    cache-retention session-id))
           (incf calls)
           (compaction-test-response nil :error "invalid request"))
         nil)
      (declare (ignore session))
      (unwind-protect
           (progn
             (is-false
              (cadr-agent:compact-agent agent :force-p t))
             (is (= 1 calls)))
        (uiop:delete-directory-tree
         root :validate t :if-does-not-exist :ignore))))
  (let ((calls 0)
        (agent nil))
    (multiple-value-bind (created session root)
        (goal17-compaction-fixture
         "no-retry-abort"
         (lambda (provider model context on-event
                  &key max-tokens abort-p cache-retention session-id)
           (declare
            (ignore provider model context on-event max-tokens abort-p
                    cache-retention session-id))
           (incf calls)
           (cadr-agent:agent-abort agent)
           (compaction-test-response nil :aborted))
         nil)
      (declare (ignore session))
      (setf agent created)
      (unwind-protect
           (progn
             (is-false
              (cadr-agent:compact-agent agent :force-p t))
             (is (= 1 calls)))
        (uiop:delete-directory-tree
         root :validate t :if-does-not-exist :ignore)))))

(test goal17-branch-summary-uses-the-shared-retry-and-isolation-path
  (let ((calls nil)
        (responses
          (list
           (compaction-test-response nil :error "terminated")
           (compaction-test-response "branch summary" :stop))))
    (multiple-value-bind (agent session root)
        (goal17-compaction-fixture
         "branch-retry"
         (lambda (provider model context on-event
                  &key max-tokens abort-p cache-retention session-id)
           (declare
            (ignore provider model context on-event max-tokens abort-p))
           (push (list cache-retention session-id) calls)
           (pop responses))
         nil)
      (unwind-protect
           (let ((result
                   (cadr-agent:generate-branch-summary
                    agent (cadr-agent:session-entries session))))
             (is (not (null result)))
             (is (= 2 (length calls)))
             (is (every (lambda (call) (eq :none (first call))) calls))
             (is (string= (second (first calls))
                          (second (second calls)))))
        (uiop:delete-directory-tree
         root :validate t :if-does-not-exist :ignore)))))

(test goal17-summary-tool-result-truncation-marker-matches-baseline-exactly
  (let* ((text (make-string 2001 :initial-element #\x))
         (expected
           (concatenate
            'string
            (make-string 2000 :initial-element #\x)
            (format nil "~%~%[... 1 more characters truncated]"))))
    (is
     (string=
      expected
      (cadr-agent::truncate-summary-tool-result text)))))

(test goal17-summary-tool-result-truncates-by-javascript-utf16-code-units
  ;; pi@d981de122 compaction/utils.ts:88-99 uses String.length and slice,
  ;; whose unit is UTF-16 rather than Unicode scalar values.
  (let* ((emoji (string (code-char #x1f642)))
         (text
           (concatenate
            'string
            (apply #'concatenate 'string
                   (make-list 1000 :initial-element emoji))
            "x"))
         (expected-prefix
           (apply #'concatenate 'string
                  (make-list 1000 :initial-element emoji)))
         (expected
           (format nil "~A~%~%[... 1 more characters truncated]"
                   expected-prefix)))
    (is (= 2001 (cadr-agent::utf16-code-unit-length text)))
    (is
     (string=
      expected
      (cadr-agent::truncate-summary-tool-result text)))))

(test goal17-split-turn-compaction-uses-two-summaries-and-combines-usage
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (flet ((response (text input output)
             (cadr-ai:make-assistant-message
              :content
              (list (cadr-ai:make-text-content :text text))
              :api :openai-responses :provider :openai :model "split"
              :usage
              (cadr-ai:make-usage
               :input input :output output :total (+ input output))
              :stop-reason :stop)))
      (let* ((session
               (cadr-agent:create-session
                :directory sessions :cwd cwd :id "goal17-split-turn"))
             (_history-user
               (cadr-agent:session-append-message
                session
                (cadr-ai:make-user-message :content "history request")))
             (_history-assistant
               (cadr-agent:session-append-message
                session
                (compaction-test-response "history answer" :stop)))
             (_prefix-user
               (cadr-agent:session-append-message
                session
                (cadr-ai:make-user-message :content "large current request")))
             (kept-id
               (cadr-agent:session-append-message
                session
                (compaction-test-response
                 (make-string 80 :initial-element #\k) :stop)))
             (*responses*
               (list
                (response "Summary of earlier context." 217 7)
                (response "Summary of the split turn prefix." 420 9)))
             (*contexts* nil)
             (max-token-values nil)
             (events nil)
             (model
               (cadr-ai:make-model
                :id "split" :provider :openai :api :openai-responses
                :base-url "https://example.invalid"
                :max-tokens 100 :context-window 100))
             (agent
               (cadr-agent:make-agent
                :provider :mock :model model :session session
                :compaction-reserve-tokens 20
                :compaction-keep-recent-tokens 4
                :stream-function
                (lambda (provider request-model context on-event
                         &key max-tokens abort-p cache-retention session-id)
                  (declare
                   (ignore provider request-model on-event abort-p
                           cache-retention session-id))
                  (push context *contexts*)
                  (push max-tokens max-token-values)
                  (pop *responses*))
                :on-event (lambda (event) (push event events)))))
        (declare
         (ignore _history-user _history-assistant _prefix-user)
         (special *responses* *contexts*))
        (let* ((result
                 (cadr-agent:compact-agent
                  agent :force-p t :reason :manual))
               (expected
                 (format
                  nil
                  "Summary of earlier context.~%~%---~%~%**Turn Context (split turn):**~%~%Summary of the split turn prefix."))
               (usage (getf result :usage))
               (event
                 (find :compaction-end events
                       :key #'cadr-agent:agent-event-type)))
          (is (= 2 (length *contexts*)))
          (is (equal '(16 10) (nreverse max-token-values)))
          (is (string= expected (getf result :summary)))
          (is (string= kept-id (getf result :first-kept-entry-id)))
          (is (= 637 (cadr-ai:usage-input usage)))
          (is (= 16 (cadr-ai:usage-output usage)))
          (is (= 653 (cadr-ai:usage-total usage)))
          (is (eq result (cadr-agent:agent-event-result event)))
          (is (string= expected
                       (cadr-agent:session-entry-summary
                        (find :compaction
                              (cadr-agent:session-entries session)
                              :key #'cadr-agent:session-entry-type))))
          (is (null *responses*)))))))

(test goal17-small-windows-use-unmodified-reserve-and-eighty-percent-summary-budget
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let* ((session
             (cadr-agent:create-session
              :directory sessions :cwd cwd
              :id "goal17-small-window"))
           (_old-user
             (cadr-agent:session-append-message
              session
              (cadr-ai:make-user-message
               :content "old context to summarize")))
           (_old-assistant
             (cadr-agent:session-append-message
              session
              (cadr-ai:make-assistant-message
               :content
               (list (cadr-ai:make-text-content :text "old answer"))
               :api :openai-responses :provider :openai :model "small"
               :usage (cadr-ai:make-usage :input 16000 :total 16000)
               :stop-reason :stop)))
           (_tail
             (cadr-agent:session-append-message
              session
              (cadr-ai:make-user-message
               :content (make-string 81000 :initial-element #\x))))
           (observed-max-tokens nil)
           (model
             (cadr-ai:make-model
              :id "small" :provider :openai :api :openai-responses
              :base-url "https://example.invalid"
              :max-tokens 32000 :context-window 32000))
           (agent
             (cadr-agent:make-agent
              :provider :mock :model model :session session
              :stream-function
              (lambda (provider request-model context on-event
                       &key max-tokens abort-p cache-retention session-id)
                (declare
                 (ignore provider request-model context on-event abort-p
                         cache-retention session-id))
                (setf observed-max-tokens max-tokens)
                (compaction-test-response "summary" :stop)))))
      (declare (ignore _old-user _old-assistant _tail))
      (is-true
       (cadr-agent:compact-agent agent :reason :threshold))
      (is (= 13107 observed-max-tokens)))))

(test goal17-threshold-compaction-runs-after-the-completing-agent-run
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let* ((session
             (cadr-agent:create-session
              :directory sessions :cwd cwd
              :id "goal17-post-run-compaction"))
           (_old-user
             (cadr-agent:session-append-message
              session
              (cadr-ai:make-user-message
               :content (make-string 120 :initial-element #\x))))
           (_old-assistant
             (cadr-agent:session-append-message
              session
              (compaction-test-response "old" :stop)))
           (*responses*
             (list
              (cadr-ai:make-assistant-message
               :content (list (cadr-ai:make-text-content :text "answer"))
               :api :openai-responses :provider :openai :model "tiny"
               :usage (cadr-ai:make-usage :input 90 :total 90)
               :stop-reason :stop)
              (compaction-test-response "history summary" :stop)
              (compaction-test-response "turn prefix summary" :stop)))
           (*contexts* nil)
           (agent
             (cadr-agent:make-agent
              :provider :mock :model (compaction-test-model)
              :session session
              :compaction-reserve-tokens 20
              :compaction-keep-recent-tokens 1
              :stream-function
              (faux-stream '*responses* '*contexts*))))
      (declare
       (ignore _old-user _old-assistant)
       (special *responses* *contexts*))
      (let ((result (cadr-agent:agent-prompt agent "current request")))
        (is
         (string=
          "answer"
          (cadr-ai:text-content-text
           (first (cadr-ai:assistant-message-content result)))))
        (is (= 3 (length *contexts*)))
        (is
         (= 1
            (count :compaction
                   (cadr-agent:session-entries session)
                   :key #'cadr-agent:session-entry-type)))
        (is (null *responses*))))))

(test goal17-threshold-compaction-runs-after-a-final-nonretryable-error
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let* ((session
             (cadr-agent:create-session
              :directory sessions :cwd cwd
              :id "goal17-post-error-compaction"))
           (_old-user
             (cadr-agent:session-append-message
              session
              (cadr-ai:make-user-message
               :content (make-string 120 :initial-element #\x))))
           (_old-assistant
             (cadr-agent:session-append-message
              session
              (cadr-ai:make-assistant-message
               :content
               (list (cadr-ai:make-text-content :text "old"))
               :api :openai-responses :provider :openai :model "tiny"
               :usage (cadr-ai:make-usage :input 70 :total 70)
               :stop-reason :stop)))
           (*responses*
             (list
              (cadr-ai:make-assistant-message
               :content
               (list
                (cadr-ai:make-text-content
                 :text (make-string 80 :initial-element #\e)))
               :api :openai-responses :provider :openai :model "tiny"
               :usage (cadr-ai:make-usage)
               :stop-reason :error
               :error-message "invalid request")
              (compaction-test-response "history summary" :stop)
              (compaction-test-response "turn prefix summary" :stop)))
           (*contexts* nil)
           (agent
             (cadr-agent:make-agent
              :provider :mock :model (compaction-test-model)
              :session session
              :compaction-reserve-tokens 20
              :compaction-keep-recent-tokens 4
              :stream-function
              (faux-stream '*responses* '*contexts*))))
      (declare
       (ignore _old-user _old-assistant)
       (special *responses* *contexts*))
      (let ((result (cadr-agent:agent-prompt agent "current request")))
        (is
         (eq :error
             (cadr-ai:assistant-message-stop-reason result)))
        (is (= 3 (length *contexts*)))
        (is
         (= 1
            (count :compaction
                   (cadr-agent:session-entries session)
                   :key #'cadr-agent:session-entry-type)))
        (is (null *responses*))))))

(test goal17-pre-prompt-compaction-precedes-the-new-turn
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let* ((session
             (cadr-agent:create-session
              :directory sessions :cwd cwd
              :id "goal17-pre-prompt-compaction"))
           (_old-user
             (cadr-agent:session-append-message
              session
              (cadr-ai:make-user-message :content "old request")))
           (_old-assistant
             (cadr-agent:session-append-message
              session
              (cadr-ai:make-assistant-message
               :content
               (list
                (cadr-ai:make-text-content
                 :text (make-string 40 :initial-element #\a)))
               :api :openai-responses :provider :openai :model "tiny"
               :usage (cadr-ai:make-usage :input 90 :total 90)
               :stop-reason :stop)))
           (*responses*
             (list
              (compaction-test-response "summary" :stop)
              (compaction-test-response "new answer" :stop)))
           (*contexts* nil)
           (events nil)
           (agent
             (cadr-agent:make-agent
              :provider :mock :model (compaction-test-model)
              :session session
              :compaction-reserve-tokens 20
              :compaction-keep-recent-tokens 4
              :stream-function (faux-stream '*responses* '*contexts*)
              :on-event (lambda (event) (push event events)))))
      (declare
       (ignore _old-user _old-assistant)
       (special *responses* *contexts*))
      (cadr-agent:agent-prompt agent "new request")
      (let* ((types
               (mapcar #'cadr-agent:agent-event-type
                       (nreverse events)))
             (compaction-position
               (position :compaction-start types))
             (turn-position (position :turn-start types)))
        (is (integerp compaction-position))
        (is (integerp turn-position))
        (is (< compaction-position turn-position)))
      (is
       (not
        (context-contains-text-p
         (first (nreverse *contexts*)) "new request"))))))

(test goal17-threshold-failure-and-second-overflow-use-baseline-guidance
  (let ((events nil))
    (multiple-value-bind (agent session root)
        (goal17-compaction-fixture
         "threshold-failure-copy"
         (lambda (provider model context on-event
                  &key max-tokens abort-p cache-retention session-id)
           (declare
            (ignore provider model context on-event max-tokens abort-p
                    cache-retention session-id))
           (compaction-test-response nil :error "invalid request"))
         (lambda (event) (push event events)))
      (declare (ignore session))
      (unwind-protect
           (progn
             (is-false
              (cadr-agent:compact-agent
               agent :force-p t :reason :threshold))
             (is
              (string=
               "Auto-compaction failed: Summarization failed: invalid request"
               (cadr-agent:agent-event-error-message
                (find :compaction-end events
                      :key #'cadr-agent:agent-event-type)))))
        (uiop:delete-directory-tree
         root :validate t :if-does-not-exist :ignore))))
  (let ((events nil)
        (*responses*
          (list
           (compaction-test-response
            nil :error "context_length_exceeded")
           (compaction-test-response "summary" :stop)
           (compaction-test-response
            nil :error "context_length_exceeded")))
        (*contexts* nil))
    (declare (special *responses* *contexts*))
    (multiple-value-bind (agent session root)
        (goal17-compaction-fixture
         "second-overflow-guidance"
         (faux-stream '*responses* '*contexts*)
         (lambda (event) (push event events)))
      (declare (ignore session))
      (setf (cadr-agent::agent-auto-compact-p agent) nil)
      (unwind-protect
           (progn
             (let ((result
                     (cadr-agent:agent-prompt agent "overflow twice")))
               (is
                (eq :error
                    (cadr-ai:assistant-message-stop-reason result))))
             (is
              (string=
               "Context overflow recovery failed after one compact-and-retry attempt. Try reducing context or switching to a larger-context model."
               (cadr-agent:agent-event-error-message
                (find :compaction-end events
                      :key #'cadr-agent:agent-event-type)))))
        (uiop:delete-directory-tree
         root :validate t :if-does-not-exist :ignore)))))

(test compaction-cut-point-keeps-backward-walk-semantics
  ;; goal 20, 12F-3: reverse+forward must equal the old nth-downfrom walk:
  ;; accumulate from the end, overwrite the candidate on every message
  ;; entry, stop once the threshold is reached, never return index 0.
  (flet ((message-entry (characters)
           (cadr-agent::make-session-entry
            :type :message
            :message (cadr-ai:make-user-message
                      :content (make-string characters
                                            :initial-element #\u))))
         (other-entry (characters)
           (cadr-agent::make-session-entry
            :type :compaction
            :summary (make-string characters :initial-element #\s))))
    ;; empty
    (is (null (cadr-agent::compaction-cut-point nil 10)))
    ;; single message at index 0 is not a legal cut
    (is (null
         (cadr-agent::compaction-cut-point
          (list (message-entry 40)) 5)))
    ;; threshold crossed on the last entry: cut at the last message
    (is (= 2
           (cadr-agent::compaction-cut-point
            (list (message-entry 40) (message-entry 40) (message-entry 40))
            5)))
    ;; candidate survives a trailing non-message once the threshold holds
    (is (= 2
           (cadr-agent::compaction-cut-point
            (list (message-entry 40) (other-entry 400) (message-entry 8))
            50)))
    ;; walk reaching index 0: candidate is the deepest message, index 1
    (is (= 1
           (cadr-agent::compaction-cut-point
            (list (other-entry 400) (message-entry 40)) 50)))
    ;; threshold never reached and the only message sits at index 0
    (is (null
         (cadr-agent::compaction-cut-point
          (list (message-entry 4) (other-entry 4)) 1000)))))

(test compaction-field-owns-extension-vs-generated
  (is (string=
       "from-ext"
       (cadr-agent::compaction-field
        t '(:summary "from-ext") :summary "generated")))
  (is (string=
       "generated"
       (cadr-agent::compaction-field
        nil '(:summary "from-ext") :summary "generated"))))

(test pairing-session-compact-observed-stays-put
  ;; scripts/goal20-paired-paths.lisp session_compact.compact.
  ;; Drives shipped compact-agent, not a reimplementation.
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let* ((session
             (cadr-agent:create-session
              :directory sessions :cwd cwd
              :id "pairing-session-compact"))
           (*responses*
             (list (compaction-test-response "SUMMARY" :stop)))
           (*contexts* nil))
      (declare (special *responses* *contexts*))
      (cadr-agent:session-append-message
       session
       (cadr-ai:make-user-message
        :content
        (concatenate 'string "discarded context "
                     (make-string 40 :initial-element #\d))))
      (cadr-agent:session-append-message
       session
       (compaction-test-response
        (concatenate 'string "discarded answer "
                     (make-string 40 :initial-element #\e))
        :stop))
      (cadr-agent:session-append-message
       session
       (cadr-ai:make-user-message
        :content
        (concatenate 'string "old context "
                     (make-string 120 :initial-element #\x))))
      (cadr-agent:session-append-message
       session
       (compaction-test-response
        (concatenate 'string "old answer "
                     (make-string 120 :initial-element #\y))
        :stop))
      (cadr-agent:session-append-message
       session
       (cadr-ai:make-user-message :content "current request"))
      (let* ((agent
               (cadr-agent:make-agent
                :provider :mock
                :model (compaction-test-model)
                :session session
                :compaction-reserve-tokens 21
                :compaction-keep-recent-tokens 40
                :auto-compact-p nil
                :stream-function
                (faux-stream '*responses* '*contexts*)))
             (result (cadr-agent:compact-agent agent :force-p t)))
        (is (not (null result)))
        (is (stringp (getf result :first-kept-entry-id)))
        (is (string= "SUMMARY" (getf result :summary)))
        (is (= 7
               (cadr-agent::utf16-code-unit-length
                (getf result :summary))))))))

(test pairing-session-compact-in-memory-core-stays-put
  ;; scripts/goal20-paired-paths.lisp session_compact.compact after
  ;; copying pi prepareCompaction + compact. Drives shipped
  ;; compact-from-preparation, not a reimplementation. No JSONL.
  (let* ((entries
           (list
            (cadr-agent::make-session-entry
             :type :message :id "e1" :parent-id nil
             :timestamp 1786665600000
             :message
             (cadr-ai:make-user-message
              :content
              (concatenate 'string "discarded context "
                           (make-string 40 :initial-element #\d))))
            (cadr-agent::make-session-entry
             :type :message :id "e2" :parent-id "e1"
             :timestamp 1786665600000
             :message
             (compaction-test-response
              (concatenate 'string "discarded answer "
                           (make-string 40 :initial-element #\e))
              :stop))
            (cadr-agent::make-session-entry
             :type :message :id "e3" :parent-id "e2"
             :timestamp 1786665600000
             :message
             (cadr-ai:make-user-message
              :content
              (concatenate 'string "old context "
                           (make-string 120 :initial-element #\x))))
            (cadr-agent::make-session-entry
             :type :message :id "e4" :parent-id "e3"
             :timestamp 1786665600000
             :message
             (compaction-test-response
              (concatenate 'string "old answer "
                           (make-string 120 :initial-element #\y))
              :stop))
            (cadr-agent::make-session-entry
             :type :message :id "e5" :parent-id "e4"
             :timestamp 1786665600000
             :message
             (cadr-ai:make-user-message :content "current request"))))
         (cut (cadr-agent::compaction-cut-point entries 40))
         (*responses*
           (list (compaction-test-response "SUMMARY" :stop)))
         (*contexts* nil))
    (declare (special *responses* *contexts*))
    (is (integerp cut))
    (let* ((source (subseq entries 0 cut))
           (kept (nth cut entries))
           (messages
             (remove nil
                     (mapcar #'cadr-agent:session-entry-message entries)))
           (preparation
             (cadr-agent::make-compaction-preparation
              source kept
              (cadr-agent::context-estimated-tokens messages)
              40 21))
           (agent
             (cadr-agent:make-agent
              :provider :mock
              :model (compaction-test-model)
              :auto-compact-p nil
              :stream-function
              (faux-stream '*responses* '*contexts*))))
      (multiple-value-bind (summary usage)
          (cadr-agent::compact-from-preparation agent preparation)
        (declare (ignore usage))
        (is (string= "SUMMARY" summary))
        (is (string= "e3" (getf preparation :first-kept-entry-id)))
        (is (= 7 (cadr-agent::utf16-code-unit-length summary)))))))

(test agent-abort-cancels-in-progress-manual-compaction
  ;; Baseline #8920 agent-session-compaction.test.ts: abort wakes the
  ;; in-flight compaction cancellation signal and leaves the session idle.
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let* ((started (sb-thread:make-semaphore :count 0))
           (events nil)
           (bundle
             (make-test-extension-bundle
              "abort-waits-for-compaction"
              (lambda ()
                (cadr-agent:define-event-hook
                 :session-before-compact
                 :handler
                 (lambda (event context)
                   (declare (ignore context))
                   (let* ((signal
                            (getf
                             (cadr-agent:extension-event-payload event)
                             :signal))
                          (state
                            (cadr-agent::%extension-cancellation-signal-state
                             signal)))
                     (sb-thread:signal-semaphore started)
                     (is
                      (eq :aborted
                          (cadr-core:wait-for-cancellation
                           state :timeout 5.0d0)))
                     '(:cancel-p t)))))))
           (host (make-test-extension-host (list bundle)))
           (session
             (cadr-agent:create-session
              :directory sessions :cwd cwd
              :id "abort-during-compact"))
           (agent nil)
           (compact-result :unset))
      (cadr-agent:session-append-message
       session
       (cadr-ai:make-user-message
        :content (make-string 80 :initial-element #\a)))
      (cadr-agent:session-append-message
       session
       (compaction-test-response
        (make-string 80 :initial-element #\b) :stop))
      (cadr-agent:session-append-message
       session (cadr-ai:make-user-message :content "keep"))
      (setf agent
            (cadr-agent:make-agent
             :provider :mock
             :model (compaction-test-model)
             :session session
             :extension-host host
             :compaction-keep-recent-tokens 1
             :on-event (lambda (event) (push event events))
             :stream-function
             (lambda (&rest arguments)
               (declare (ignore arguments))
               (error "aborted compaction must not summarize"))))
      (let ((thread
              (sb-thread:make-thread
               (lambda ()
                 (setf compact-result
                       (cadr-agent:compact-agent
                        agent :force-p t)))
               :name "compact")))
        (sb-thread:wait-on-semaphore started :timeout 5)
        (cadr-agent:agent-abort agent)
        (sb-thread:join-thread thread :timeout 5))
      (is-false compact-result)
      (is
       (zerop
        (count :compaction
               (cadr-agent:session-entries session)
               :key #'cadr-agent:session-entry-type)))
      (let ((end
              (find :compaction-end events
                    :key #'cadr-agent:agent-event-type)))
        (is (not (null end)))
        (is-true (cadr-agent:agent-event-aborted end)))
      (is (zerop (cadr-agent::agent-operation-count agent)))
      (is (null (cadr-agent::agent-compaction-cancellation agent))))))
