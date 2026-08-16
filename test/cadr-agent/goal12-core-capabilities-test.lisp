(in-package #:cadr-agent/tests)
(in-suite cadr-agent-suite)

(test goal12-agent-message-projection-and-file-operation-copy-match-baseline
  (let* ((arguments (cadr-ai::json-object "path" "src/a.lisp" "n" 1))
         (assistant
           (cadr-ai:make-assistant-message
            :content
            (list
             (cadr-ai:make-thinking-content :thinking "plan")
             (cadr-ai:make-text-content :text "done")
             (cadr-ai:make-tool-call
              :id "call" :name "read" :arguments arguments))
            :api :openai-responses :provider :openai :model "mock"
            :stop-reason :stop))
         (operations (cadr-agent:make-file-operations)))
    (cadr-agent:extract-file-operations-from-message assistant operations)
    (multiple-value-bind (read modified)
        (cadr-agent:compute-file-operation-lists operations)
      (is (equal '("src/a.lisp") read))
      (is (null modified))
      (is (string= (format nil "~%~%<read-files>~%src/a.lisp~%</read-files>")
                   (cadr-agent:format-file-operations read modified))))
    (let ((serialized
            (cadr-agent:serialize-conversation
             (list (cadr-ai:make-user-message :content "request") assistant))))
      (is (search "[User]: request" serialized))
      (is (search "[Assistant thinking]: plan" serialized))
      (is (search "[Assistant]: done" serialized))
      (is (search "[Assistant tool calls]: read(n=1, path=\"src/a.lisp\")"
                  serialized)))
    (is (string=
         (format nil
                 "Ran `false`~%```~%bad~%```~%~%Command exited with code 7~%~%[Output truncated. Full output: /tmp/full]")
         (cadr-agent:bash-execution-to-text
          (cadr-agent:make-bash-execution-message
           :command "false" :output "bad" :exit-code 7
           :truncated-p t :full-output-path "/tmp/full"))))
    (is (null
         (cadr-agent:convert-agent-messages-to-llm
          (list
           (cadr-agent:make-bash-execution-message
            :command "secret" :exclude-from-context-p t)))))))

(test goal12-agent-branch-collection-preparation-and-generation-match-baseline
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let* ((session
             (cadr-agent:create-session
              :directory sessions :cwd cwd :id "goal12-branch"))
           (root
             (cadr-agent:session-append-message
              session (cadr-ai:make-user-message :content "root")))
           (abandoned
             (cadr-agent:session-append-message
              session
              (cadr-ai:make-assistant-message
               :content
               (list
                (cadr-ai:make-tool-call
                 :id "r" :name "write"
                 :arguments (cadr-ai::json-object "path" "src/new.lisp")))
               :api :openai-responses :provider :openai :model "mock"
               :stop-reason :tool-use)))
           (_tail
             (cadr-agent:session-append-message
              session (cadr-ai:make-user-message :content "tail"))))
      (declare (ignore _tail))
      (is (stringp abandoned))
      (multiple-value-bind (entries ancestor)
          (cadr-agent:collect-entries-for-branch-summary
           session (cadr-agent:session-leaf-id session) root)
        (is (= 2 (length entries)))
        (is (string= root ancestor))
        (let ((prepared (cadr-agent:prepare-branch-entries entries)))
          (is (= 2 (length
                    (cadr-agent:branch-summary-preparation-messages prepared))))
          (multiple-value-bind (read modified)
              (cadr-agent:compute-file-operation-lists
               (cadr-agent:branch-summary-preparation-file-operations prepared))
            (is (null read))
            (is (equal '("src/new.lisp") modified)))))
      (let* ((*responses*
               (list
                (cadr-ai:make-assistant-message
                 :content (list (cadr-ai:make-text-content :text "## Goal\nKeep work"))
                 :api :openai-responses :provider :openai :model "mock"
                 :usage (cadr-ai:make-usage :input 10 :output 5 :total 15)
                 :stop-reason :stop)))
             (*contexts* nil)
             (model (cadr-ai:make-model
                     :id "mock" :provider :openai :api :openai-responses
                     :base-url "https://example.invalid"
                     :max-tokens 2048 :context-window 64000))
             (agent (cadr-agent:make-agent
                     :provider :mock :model model :session session
                     :stream-function (faux-stream '*responses* '*contexts*))))
        (declare (special *responses* *contexts*))
        (multiple-value-bind (messages cancelled editor summary-entry)
            (cadr-agent:agent-navigate-tree agent root :summarize-p t)
          (is (not cancelled))
          (is (string= "root" editor))
          (is (listp messages))
          (is (typep summary-entry 'cadr-agent:session-entry))
          (is (eq :branch-summary
                  (cadr-agent:session-entry-type summary-entry)))
          (is (search "The user explored a different conversation branch"
                      (cadr-agent:session-entry-summary summary-entry)))
          (is (search "<modified-files>"
                      (cadr-agent:session-entry-summary summary-entry))))))))

(test goal12-agent-execution-context-and-proxy-stream-reconstruct-content
  (let ((context
          (cadr-agent:make-execution-tool-context
           :env (cadr-agent:make-node-execution-env))))
    (is (typep (cadr-agent:execution-tool-context-env context)
               'cadr-agent:node-execution-env)))
  (let* ((model (cadr-ai:make-model
                 :id "proxy" :provider :openai :api :openai-responses
                 :base-url "https://example.invalid" :max-tokens 100))
         (events nil)
         (response
           (cadr-agent:stream-proxy
            model
            (cadr-ai:make-context
             :system-prompt "system"
             :messages (list (cadr-ai:make-user-message :content "hello")))
            (lambda (event) (push event events))
            :auth-token "secret" :proxy-url "https://proxy.invalid"
            :request-sse-function
            (lambda (request consumer &key abort-p)
              (declare (ignore abort-p))
              (is (string= "Bearer secret"
                           (cdr (assoc "Authorization"
                                       (cadr-ai:request-spec-headers request)
                                       :test #'string=))))
              (dolist (json
                       '("{\"type\":\"start\"}"
                         "{\"type\":\"text_start\",\"contentIndex\":0}"
                         "{\"type\":\"text_delta\",\"contentIndex\":0,\"delta\":\"hello \"}"
                         "{\"type\":\"text_delta\",\"contentIndex\":0,\"delta\":\"7\"}"
                         "{\"type\":\"text_end\",\"contentIndex\":0}"
                         "{\"type\":\"thinking_start\",\"contentIndex\":1}"
                         "{\"type\":\"thinking_delta\",\"contentIndex\":1,\"delta\":\"plan\"}"
                         "{\"type\":\"thinking_end\",\"contentIndex\":1}"
                         "{\"type\":\"toolcall_start\",\"contentIndex\":2,\"id\":\"call\",\"toolName\":\"read\"}"
                         "{\"type\":\"toolcall_delta\",\"contentIndex\":2,\"delta\":\"{\\\"path\\\":\\\"a\\\"}\"}"
                         "{\"type\":\"toolcall_end\",\"contentIndex\":2}"
                         "{\"type\":\"done\",\"reason\":\"toolUse\",\"usage\":{\"input\":1,\"output\":2,\"cacheRead\":0,\"cacheWrite\":0,\"totalTokens\":9,\"cost\":{\"input\":0,\"output\":0,\"cacheRead\":0,\"cacheWrite\":0,\"total\":0}}}"))
                (funcall consumer (cadr-ai::make-sse-event :data json)))))))
    (is (eq :tool-use (cadr-ai:assistant-message-stop-reason response)))
    (is (string= "hello 7"
                 (cadr-ai:text-content-text
                  (first (cadr-ai:assistant-message-content response)))))
    (is (string= "plan"
                 (cadr-ai:thinking-content-thinking
                  (second (cadr-ai:assistant-message-content response)))))
    (is (string= "a"
                 (cadr-ai::json-get
                  (cadr-ai:tool-call-arguments
                   (third (cadr-ai:assistant-message-content response)))
                  "path")))
    (is (= 9 (cadr-ai:usage-total
              (cadr-ai:assistant-message-usage response))))
    (is (equal '(:start :text-start :text-delta :text-delta :text-end
                 :thinking-start :thinking-delta :thinking-end
                 :tool-call-start :tool-call-delta :tool-call-end :done)
               (mapcar #'cadr-ai:stream-event-type (nreverse events))))))

(test proxy-toolcall-end-merges-only-present-keys
  ;; Baseline v0.84.2 proxy.ts toolcall_end: Object.assign(content,
  ;; toolCall) — a final toolCall carrying only some keys must not wipe
  ;; the streamed partial values for the keys it omits.
  (let* ((model (cadr-ai:make-model
                 :id "proxy" :provider :openai :api :openai-responses
                 :base-url "https://example.invalid" :max-tokens 100))
         (response
           (cadr-agent:stream-proxy
            model
            (cadr-ai:make-context
             :system-prompt "system"
             :messages (list (cadr-ai:make-user-message :content "hello")))
            (lambda (event) (declare (ignore event)))
            :auth-token "secret" :proxy-url "https://proxy.invalid"
            :request-sse-function
            (lambda (request consumer &key abort-p)
              (declare (ignore request abort-p))
              (dolist (json
                       '("{\"type\":\"start\"}"
                         "{\"type\":\"toolcall_start\",\"contentIndex\":0,\"id\":\"stream-id\",\"toolName\":\"read\"}"
                         "{\"type\":\"toolcall_delta\",\"contentIndex\":0,\"delta\":\"{\\\"path\\\":\\\"a\\\"}\"}"
                         "{\"type\":\"toolcall_end\",\"contentIndex\":0,\"toolCall\":{\"id\":\"final-id\"}}"
                         "{\"type\":\"done\",\"reason\":\"toolUse\",\"usage\":{\"input\":1,\"output\":1,\"cacheRead\":0,\"cacheWrite\":0,\"totalTokens\":2,\"cost\":{\"input\":0,\"output\":0,\"cacheRead\":0,\"cacheWrite\":0,\"total\":0}}}"))
                (funcall consumer (cadr-ai::make-sse-event :data json))))))
         (call (first (cadr-ai:assistant-message-content response))))
    (is (string= "final-id" (cadr-ai:tool-call-id call)))
    (is (string= "read" (cadr-ai:tool-call-name call)))
    (is (string= "a"
                 (cadr-ai::json-get
                  (cadr-ai:tool-call-arguments call) "path")))))
