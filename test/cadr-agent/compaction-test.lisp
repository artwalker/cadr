(in-package #:cadr-agent/tests)
(in-suite cadr-agent-suite)

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
        (list :length "length-limited")
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
                     &key max-tokens abort-p)
              (declare
               (ignore provider model on-event
                       max-tokens abort-p))
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
        (list "provider failed"
              "Summarization failed: provider failed")
        (list nil
              "Summarization failed: Unknown error")))
    (destructuring-bind (provider-error expected) case
      (let* ((*responses*
               (list
                (compaction-test-response
                 nil :error provider-error)))
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
             (_old-user
               (cadr-agent:session-append-message
                session
                (cadr-ai:make-user-message
                 :content
                 (format nil "old context ~120@{x~}"))))
             (_old-assistant
               (cadr-agent:session-append-message
                session
                (compaction-test-response
                 (format nil "old answer ~120@{y~}")
                 :stop)))
             (*responses*
               (list
                (compaction-test-response summary :stop)
                (compaction-test-response "continued" :stop)))
             (*contexts* nil)
             (agent
               (cadr-agent:make-agent
                :provider :mock
                :model (compaction-test-model)
                :session session
                :compaction-reserve-tokens 20
                :compaction-keep-recent-tokens 4
                :stream-function
                (faux-stream '*responses* '*contexts*))))
        (declare
         (ignore _old-user _old-assistant)
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
                 &key max-tokens abort-p)
          (declare
           (ignore provider model context on-event
                   max-tokens abort-p))
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
          "Summarization failed: summary provider failed"
          (cadr-agent:agent-event-error-message
           (find
            :compaction-error events
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
               (format nil "old-secret-user ~120@{x~}"))))
           (old-assistant-id
             (cadr-agent:session-append-message
              session
              (cadr-ai:make-assistant-message
               :content
               (list
                (cadr-ai:make-text-content
                 :text
                 (format nil "old-secret-assistant ~120@{y~}")))
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
              :compaction-reserve-tokens 20
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
          (is (member old-assistant-id
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
