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
