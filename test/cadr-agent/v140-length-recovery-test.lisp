(in-package #:cadr-agent/tests)
(in-suite cadr-agent-suite)

(defun v140-length-recovery-model ()
  (make-model
   :id "faux-1"
   :provider :openai
   :api :openai-responses
   :base-url "https://example.invalid"
   :max-tokens 1000
   :context-window 100000))

(defun v140-request-after-resumed-length-stop
    (sessions cwd
     &key (output 16) (assistant-model "faux-1")
          (auto-compact-p t) session-id)
  ;; pi@4a080252f 11227-recovery-omits-tool-results.test.ts
  (let* ((model (v140-length-recovery-model))
         (arguments (make-hash-table :test #'equal))
         (session
           (cadr-agent:create-session
            :directory sessions
            :cwd cwd
            :id session-id))
         (*responses*
           (list
            (assistant
             (list (make-text-content :text "done")))))
         (*contexts* nil)
         (agent
           (cadr-agent:make-agent
            :provider :mock
            :model model
            :session session
            :auto-compact-p auto-compact-p
            :stream-function
            (faux-stream '*responses* '*contexts*))))
    (declare (special *responses* *contexts*))
    (setf (gethash "command" arguments) "echo")
    (cadr-agent:session-append-message
     session
     (cadr-ai:make-user-message :content "check status"))
    (cadr-agent:session-append-message
     session
     (make-assistant-message
      :content
      (list
       (make-tool-call
        :id "call_truncated"
        :name "bash"
        :arguments arguments))
      :api (cadr-ai:model-api model)
      :provider (cadr-ai:model-provider model)
      :model assistant-model
      :usage (cadr-ai:make-usage
              :input 100
              :output output
              :cache-read 0
              :cache-write 0
              :total 116)
      :stop-reason :length))
    (cadr-agent:session-append-message
     session
     (cadr-ai:make-tool-result-message
      :tool-call-id "call_truncated"
      :tool-name "bash"
      :is-error t
      :content
      (list
       (make-text-content
        :text "Not executed: output token limit reached."))))
    (setf (cadr-agent:agent-messages agent)
          (cadr-agent:session-messages session))
    (cadr-agent:agent-prompt agent "continue")
    (values
     (cadr-ai:context-messages
      (car (last *contexts*)))
     session)))

(defun v140-tool-result-p (message)
  (typep message 'cadr-ai:tool-result-message))

(defun v140-length-assistant-p (message)
  (and (typep message 'cadr-ai:assistant-message)
       (eq :length
           (cadr-ai:assistant-message-stop-reason message))))

(test v140-pre-prompt-recovery-omits-truncated-call-and-result
  ;; packages/coding-agent/test/suite/regressions/11227-recovery-omits-tool-results.test.ts
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (multiple-value-bind (request session)
        (v140-request-after-resumed-length-stop
         sessions cwd :session-id "v140-11227")
      (is (not (find-if #'v140-tool-result-p request)))
      (is (not (find-if #'v140-length-assistant-p request)))
      (is (not
           (find-if
            #'v140-tool-result-p
            (cadr-agent:session-messages session))))
      (is (not
           (find-if
            #'v140-length-assistant-p
            (cadr-agent:session-messages session)))))))

(test v140-length-stop-at-output-limit-keeps-its-tool-result
  ;; pi@4a080252f overflow.ts isRecoverableLength: output must be
  ;; strictly below the model's max output.
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (multiple-value-bind (request session)
        (v140-request-after-resumed-length-stop
         sessions cwd
         :output 1000
         :session-id "v140-11227-at-limit")
      (is (find-if #'v140-tool-result-p request))
      (is (find-if #'v140-length-assistant-p request))
      (is (find-if
           #'v140-tool-result-p
           (cadr-agent:session-messages session))))))

(test v140-length-stop-from-another-model-keeps-its-tool-result
  ;; pi@4a080252f agent-session.ts _modelForMessage: a different model
  ;; does not recover.
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (multiple-value-bind (request session)
        (v140-request-after-resumed-length-stop
         sessions cwd
         :assistant-model "other"
         :session-id "v140-11227-other-model")
      (is (find-if #'v140-tool-result-p request))
      (is (find-if #'v140-length-assistant-p request))
      (is (find-if
           #'v140-tool-result-p
           (cadr-agent:session-messages session))))))

(test v140-disabled-compaction-keeps-truncated-tool-result
  ;; pi@4a080252f _checkCompaction returns before omission when
  ;; compaction is disabled.
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (multiple-value-bind (request session)
        (v140-request-after-resumed-length-stop
         sessions cwd
         :auto-compact-p nil
         :session-id "v140-11227-disabled")
      (is (find-if #'v140-tool-result-p request))
      (is (find-if #'v140-length-assistant-p request))
      (is (find-if
           #'v140-tool-result-p
           (cadr-agent:session-messages session))))))
