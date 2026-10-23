(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(test goal28-thinking-budgets-settings-reach-lookup
  (let ((manager (cadr-cli::make-memory-settings-manager)))
    (is (null (cadr-cli::settings-thinking-budgets manager)))
    (is (= 1024 (cadr-ai:thinking-budget-for-level
                 :minimal
                 (cadr-cli::settings-thinking-budgets manager))))
    (is (= 2048 (cadr-ai:thinking-budget-for-level
                 :low
                 (cadr-cli::settings-thinking-budgets manager))))
    (is (= 8192 (cadr-ai:thinking-budget-for-level
                 :medium
                 (cadr-cli::settings-thinking-budgets manager))))
    (is (= 16384 (cadr-ai:thinking-budget-for-level
                  :high
                  (cadr-cli::settings-thinking-budgets manager))))
    (is (null (cadr-cli::settings-http-proxy manager)))
    (is (null
         (cadr-cli::settings-websocket-connect-timeout-ms
          manager)))
    (is (null (cadr-cli::settings-session-dir manager)))
    (is (null (cadr-cli::settings-shell-path manager)))
    (is (eq t (cadr-cli::settings-boolean-value
               manager "compaction" t "enabled")))
    (is (= 16384
           (cadr-cli::settings-branch-summary-reserve-tokens
            manager))))
  (with-test-directory (root)
    (let* ((global (merge-pathnames "settings.json" root))
           (_
             (write-text
              global
              "{\"thinkingBudgets\":{\"medium\":4096}}"))
           (manager
             (cadr-cli::make-settings-manager
              :global-path global))
           (budgets
             (cadr-cli::settings-thinking-budgets manager)))
      (declare (ignore _))
      (is (= 4096
             (cadr-ai:thinking-budget-for-level :medium budgets)))
      (is (= 1024
             (cadr-ai:thinking-budget-for-level :minimal budgets)))
      (is (= 2048
             (cadr-ai:thinking-budget-for-level :low budgets)))
      (is (= 16384
             (cadr-ai:thinking-budget-for-level :high budgets)))
      (is (null (cadr-cli::settings-http-proxy manager)))
      (is (null (cadr-cli::settings-session-dir manager)))))
  (let ((settings
          (cadr-cli::make-memory-sdk-settings-manager)))
    (is (null (cadr-cli:sdk-settings-thinking-budgets settings)))
    (is (= 8192
           (cadr-ai:thinking-budget-for-level
            :medium
            (cadr-cli:sdk-settings-thinking-budgets settings))))
    (is (null (cadr-cli:sdk-settings-http-proxy settings)))
    (is (null (cadr-cli:sdk-settings-session-dir settings)))
    (is (null (cadr-cli:sdk-settings-shell-path settings)))
    (is (null
         (cadr-cli:sdk-settings-websocket-connect-timeout-ms
          settings)))
    (is (eq t
            (cadr-cli:sdk-settings-compaction-enabled-p
             settings)))
    (is (= 16384
           (cadr-cli:sdk-settings-branch-summary-reserve-tokens
            settings))))
  (let* ((seen nil)
         (manager
           (cadr-cli::make-memory-sdk-settings-manager
            (cadr-ai::json-object
             "thinkingBudgets"
             (cadr-ai::json-object "medium" 4096))))
         (stream
           (cadr-cli::stream-function-with-thinking-budgets
            (lambda (provider model context on-event &rest options)
              (declare (ignore provider model context on-event))
              (setf seen (getf options :thinking-budgets)))
            (lambda ()
              (cadr-cli:sdk-settings-thinking-budgets manager)))))
    (funcall stream nil nil nil nil)
    (is (= 4096
           (cadr-ai:thinking-budget-for-level :medium seen)))
    (is (= 1024
           (cadr-ai:thinking-budget-for-level :minimal seen)))
    (is (= 2048
           (cadr-ai:thinking-budget-for-level :low seen)))
    (is (= 16384
           (cadr-ai:thinking-budget-for-level :high seen)))))

(defun goal49-budget-completions-payload (budgets)
  (cadr-ai:request-spec-payload
   (cadr-ai:build-request
    (cadr-ai:make-openai-completions-provider :api-key "test")
    (cadr-ai:make-model
     :id "zai-org/glm-5.2"
     :provider :local-vllm
     :api :openai-completions
     :base-url "http://127.0.0.1:9/v1"
     :max-tokens 16384
     :reasoning-p t
     :compat '(:supports-thinking-token-budget t
               :thinking-format :zai))
    (cadr-ai:make-context
     :messages (list (cadr-ai:make-user-message :content "Hi")))
    :stream-p t
    :reasoning :high
    :thinking-budgets budgets)))

(test goal49-zero-thinking-budget-from-settings-omits-the-field
  ;; pi@4a080252f settings-schema.ts Type.Number() and
  ;; resolveClampedThinkingBudget: a budget that is not greater than
  ;; 0 is kept and the request field is omitted. Missing keys still
  ;; use 1024 / 2048 / 8192 / 16384.
  (with-test-directory (root)
    (let* ((global (merge-pathnames "settings.json" root))
           (_
             (write-text
              global
              "{\"thinkingBudgets\":{\"high\":0,\"medium\":-1}}"))
           (manager
             (cadr-cli::make-settings-manager :global-path global))
           (budgets
             (cadr-cli::settings-thinking-budgets manager))
           (seen nil))
      (declare (ignore _))
      (is (= 0 (cadr-ai:thinking-budget-for-level :high budgets)))
      (is (= -1 (cadr-ai:thinking-budget-for-level :medium budgets)))
      (is (= 1024 (cadr-ai:thinking-budget-for-level :minimal budgets)))
      (is (= 2048 (cadr-ai:thinking-budget-for-level :low budgets)))
      (funcall
       (cadr-cli::stream-function-with-thinking-budgets
        (lambda (provider model context on-event &rest options)
          (declare (ignore provider model context on-event))
          (setf seen (getf options :thinking-budgets)))
        (lambda ()
          (cadr-cli::settings-thinking-budgets manager)))
       nil nil nil nil)
      (is (= 0 (cadr-ai:thinking-budget-for-level :high seen)))
      (is (not (cadr-ai::json-present-p
                (goal49-budget-completions-payload seen)
                "thinking_token_budget")))))
  (let* ((manager
           (cadr-cli::make-memory-sdk-settings-manager
            (cadr-ai::json-object
             "thinkingBudgets"
             (cadr-ai::json-object "high" 0))))
         (budgets
           (cadr-cli:sdk-settings-thinking-budgets manager))
         (seen nil))
    (is (= 0 (cadr-ai:thinking-budget-for-level :high budgets)))
    (funcall
     (cadr-cli::stream-function-with-thinking-budgets
      (lambda (provider model context on-event &rest options)
        (declare (ignore provider model context on-event))
        (setf seen (getf options :thinking-budgets)))
      (lambda ()
        (cadr-cli:sdk-settings-thinking-budgets manager)))
     nil nil nil nil)
    (is (= 0 (getf seen :high)))
    (is (not (cadr-ai::json-present-p
              (goal49-budget-completions-payload seen)
              "thinking_token_budget")))))
