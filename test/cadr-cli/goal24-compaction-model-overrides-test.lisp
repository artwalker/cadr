(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defun goal24-compaction-test-model ()
  ;; pi@ecac0a9c4 settings-manager-compaction.test.ts model key
  ;; "provider/family/model" (id may contain slashes).
  (cadr-ai:make-model
   :id "family/model"
   :name "Family Model"
   :provider :provider
   :api :openai-responses
   :base-url "https://example.invalid"
   :max-tokens 1024))

(defun goal24-compaction-settings-json ()
  (cadr-ai::parse-json
   "{\"compaction\":{\"reserveTokens\":8192,\"keepRecentTokens\":10000,\"modelOverrides\":{\"provider/family/model\":{\"reserveTokens\":400000},\"provider/*\":{\"reserveTokens\":1},\"family/model\":{\"reserveTokens\":2}}}}"))

(test goal24-compaction-model-overrides-resolve-per-field
  ;; pi@ecac0a9c4 getCompactionTokenSetting: override wins per field;
  ;; exact provider/id match; no model keeps ordinary settings.
  (let* ((manager
           (cadr-cli::make-memory-settings-manager
            (goal24-compaction-settings-json)))
         (model (goal24-compaction-test-model))
         (other
           (cadr-ai:make-model
            :id "other"
            :name "Other"
            :provider :provider
            :api :openai-responses
            :base-url "https://example.invalid"
            :max-tokens 1024)))
    (is (= 400000
           (cadr-cli::settings-compaction-reserve-tokens
            manager model)))
    (is (= 10000
           (cadr-cli::settings-compaction-keep-recent-tokens
            manager model)))
    (is (= 8192
           (cadr-cli::settings-compaction-reserve-tokens
            manager)))
    (is (= 10000
           (cadr-cli::settings-compaction-keep-recent-tokens
            manager)))
    (is (= 8192
           (cadr-cli::settings-compaction-reserve-tokens
            manager other)))
    (let ((agent
            (cadr-agent:make-agent
             :provider :provider
             :model model)))
      (cadr-cli::sync-agent-settings-from-manager
       agent manager)
      (is (= 400000
             (cadr-agent::agent-compaction-reserve-tokens
              agent)))
      (is (= 10000
             (cadr-agent::agent-compaction-keep-recent-tokens
              agent))))
    (let ((sdk
            (cadr-cli::make-memory-sdk-settings-manager
             (goal24-compaction-settings-json))))
      (is (= 400000
             (cadr-cli:sdk-settings-compaction-reserve-tokens
              sdk model)))
      (is (= 10000
             (cadr-cli:sdk-settings-compaction-keep-recent-tokens
              sdk model))))))

(test goal24-compaction-model-override-keep-recent-only
  (let* ((manager
           (cadr-cli::make-memory-settings-manager
            (cadr-ai::parse-json
             "{\"compaction\":{\"modelOverrides\":{\"provider/family/model\":{\"keepRecentTokens\":1024}}}}")))
         (model (goal24-compaction-test-model)))
    (is (= 16384
           (cadr-cli::settings-compaction-reserve-tokens
            manager model)))
    (is (= 1024
           (cadr-cli::settings-compaction-keep-recent-tokens
            manager model)))))
