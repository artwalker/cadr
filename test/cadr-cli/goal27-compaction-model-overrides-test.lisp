(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defun goal22-model (id &optional (provider :provider))
  (cadr-ai:make-model
   :id id
   :provider provider
   :api :openai-responses
   :base-url "https://example.invalid"
   :max-tokens 16
   :context-window 1000))

(defun goal22-memory (json)
  (cadr-cli::make-memory-settings-manager
   (cadr-ai::parse-json json)))

(defun goal22-triple (manager &optional model)
  (list
   (cadr-cli::settings-boolean-value
    manager "compaction" t "enabled")
   (cadr-cli::settings-compaction-reserve-tokens
    manager model)
   (cadr-cli::settings-compaction-keep-recent-tokens
    manager model)))

(defun goal22-error-text (thunk)
  (handler-case
      (progn (funcall thunk) nil)
    (error (condition)
      (princ-to-string condition))))

(defparameter +goal22-model-key+ "provider/family/model")

(defun goal22-nan ()
  (sb-int:with-float-traps-masked (:invalid)
    (/ 0.0d0 0.0d0)))

(test goal22-compaction-defaults-and-independent-fields
  (let ((manager (cadr-cli::make-memory-settings-manager))
        (model (goal22-model "family/model")))
    (is (equal '(t 16384 20000) (goal22-triple manager)))
    (is (equal '(t 16384 20000) (goal22-triple manager model))))
  (let* ((model (goal22-model "family/model"))
         (manager
           (goal22-memory
            (format
             nil
             "{\"compaction\":{\"reserveTokens\":8192,\"keepRecentTokens\":10000,\"modelOverrides\":{\"~A\":{\"reserveTokens\":400000}}}}"
             +goal22-model-key+))))
    (is (equal '(t 400000 10000) (goal22-triple manager model)))
    (is (= 400000
           (cadr-cli::settings-compaction-reserve-tokens
            manager model)))
    (is (= 10000
           (cadr-cli::settings-compaction-keep-recent-tokens
            manager model)))
    (is (equal '(t 8192 10000) (goal22-triple manager)))
    (cadr-cli::settings-override-runtime-value
     manager "compaction"
     (cadr-ai::parse-json
      (format
       nil
       "{\"modelOverrides\":{\"~A\":{\"keepRecentTokens\":30000}}}"
       +goal22-model-key+)))
    (is (= 30000
           (cadr-cli::settings-compaction-keep-recent-tokens
            manager model)))
    (is (= 400000
           (cadr-cli::settings-compaction-reserve-tokens
            manager model))))
  (let ((manager
          (goal22-memory
           (format
            nil
            "{\"compaction\":{\"modelOverrides\":{\"~A\":{\"keepRecentTokens\":1024}}}}"
            +goal22-model-key+)))
        (model (goal22-model "family/model")))
    (is (equal '(t 16384 1024) (goal22-triple manager model)))))

(test goal22-compaction-override-keys-are-exact
  (let* ((model (goal22-model "family/model"))
         (manager
           (goal22-memory
            (format
             nil
             "{\"compaction\":{\"modelOverrides\":{\"~A\":{\"reserveTokens\":400000},\"provider/*\":{\"reserveTokens\":1},\"family/model\":{\"reserveTokens\":2}}}}"
             +goal22-model-key+))))
    (is (= 400000
           (cadr-cli::settings-compaction-reserve-tokens
            manager model)))
    (dolist (other
             (list
              (goal22-model "family/model" :other)
              (goal22-model "other")
              (goal22-model "family/Model")))
      (is (equal '(t 16384 20000) (goal22-triple manager other))))))

(test goal22-compaction-project-overrides-merge-per-field
  (with-test-directory (root)
    (let ((global (merge-pathnames "settings.json" root))
          (project (merge-pathnames "project.json" root)))
      (write-text
       global
       (format
        nil
        "{\"compaction\":{\"reserveTokens\":8192,\"modelOverrides\":{\"~A\":{\"reserveTokens\":400000,\"keepRecentTokens\":30000},\"provider/other\":{\"keepRecentTokens\":4096}}}}"
        +goal22-model-key+))
      (write-text
       project
       (format
        nil
        "{\"compaction\":{\"reserveTokens\":1024,\"modelOverrides\":{\"~A\":{\"keepRecentTokens\":2000}}}}"
        +goal22-model-key+))
      (let ((manager
              (cadr-cli::make-settings-manager
               :global-path global
               :project-path project))
            (model (goal22-model "family/model"))
            (other (goal22-model "other")))
        (is (equal '(t 400000 2000) (goal22-triple manager model)))
        (is (equal '(t 1024 4096) (goal22-triple manager other)))
        (cadr-cli::settings-reload manager)
        (is (= 2000
               (cadr-cli::settings-compaction-keep-recent-tokens
                manager model)))
        (setf (cadr-cli::settings-manager-project-trusted-p manager)
              nil)
        (cadr-cli::settings-reload manager)
        (is (= 30000
               (cadr-cli::settings-compaction-keep-recent-tokens
                manager model)))))))

(test goal22-compaction-enabled-stays-global-and-toggle-keeps-overrides
  (with-test-directory (root)
    (let ((global (merge-pathnames "settings.json" root)))
      (write-text
       global
       (format
        nil
        "{\"compaction\":{\"modelOverrides\":{\"~A\":{\"enabled\":false,\"reserveTokens\":400000}}}}"
        +goal22-model-key+))
      (let ((manager
              (cadr-cli::make-settings-manager
               :global-path global))
            (model (goal22-model "family/model")))
        (is (eq t (first (goal22-triple manager model))))
        (cadr-cli::settings-set-nested
         manager "compaction" "enabled" nil :scope :global)
        (cadr-cli::settings-reload manager)
        (is (equal '(nil 400000 20000)
                   (goal22-triple manager model)))))))

(test goal22-compaction-rejects-invalid-override-tokens
  (let ((model (goal22-model "family/model"))
        (other (goal22-model "family/model" :other)))
    (dolist (field '("reserveTokens" "keepRecentTokens"))
      (dolist (pair
               '(("null" "null")
                 ("-1" "-1")
                 ("1.5" "1.5")
                 ("\"400000\"" "400000")
                 ("true" "true")
                 ("{}" "[object Object]")
                 ("[]" "")
                 ("9007199254740992" "9007199254740992")))
        (destructuring-bind (json text) pair
          (let* ((manager
                   (goal22-memory
                    (format
                     nil
                     "{\"compaction\":{\"modelOverrides\":{\"~A\":{\"~A\":~A}}}}"
                     +goal22-model-key+ field json)))
                 (message
                   (format
                    nil
                    "Invalid compaction.modelOverrides[\"~A\"].~A setting: ~A. Expected a non-negative safe integer."
                    +goal22-model-key+ field text)))
            (is (string=
                 message
                 (goal22-error-text
                  (lambda ()
                    (goal22-triple manager model)))))
            (is (equal '(t 16384 20000) (goal22-triple manager)))
            (is (equal '(t 16384 20000)
                       (goal22-triple manager other))))))
      (dolist (pair
               (list
                (list (goal22-nan) "NaN")
                (list sb-ext:double-float-positive-infinity
                      "Infinity")
                (list (- sb-ext:double-float-positive-infinity)
                      "-Infinity")))
        (destructuring-bind (value text) pair
          (let ((manager
                  (cadr-cli::make-memory-settings-manager)))
            (cadr-cli::settings-override-runtime-value
             manager "compaction"
             (cadr-ai::json-object
              "modelOverrides"
              (cadr-ai::json-object
               +goal22-model-key+
               (cadr-ai::json-object field value))))
            (is (search
                 (format
                  nil
                  "Invalid compaction.modelOverrides[\"~A\"].~A setting: ~A"
                  +goal22-model-key+ field text)
                 (goal22-error-text
                  (lambda ()
                    (goal22-triple manager model)))))))))))

(test goal22-compaction-rejects-invalid-ordinary-tokens
  (let ((model (goal22-model "family/model")))
    (dolist (field '("reserveTokens" "keepRecentTokens"))
      (dolist (pair
               '(("null" "null")
                 ("-1" "-1")
                 ("1.5" "1.5")
                 ("\"400000\"" "400000")
                 ("true" "true")
                 ("{}" "[object Object]")
                 ("[]" "")
                 ("9007199254740992" "9007199254740992")))
        (destructuring-bind (json text) pair
          (let* ((manager
                   (goal22-memory
                    (format
                     nil
                     "{\"compaction\":{\"~A\":~A,\"modelOverrides\":{\"~A\":{\"~A\":4096}}}}"
                     field json +goal22-model-key+ field)))
                 (message
                   (format
                    nil
                    "Invalid compaction.~A setting: ~A. Expected a non-negative safe integer."
                    field text)))
            (is (string=
                 message
                 (goal22-error-text
                  (lambda () (goal22-triple manager)))))
            (is (string=
                 message
                 (goal22-error-text
                  (lambda ()
                    (goal22-triple manager model))))))))
      (dolist (pair
               (list
                (list (goal22-nan) "NaN")
                (list sb-ext:double-float-positive-infinity
                      "Infinity")
                (list (- sb-ext:double-float-positive-infinity)
                      "-Infinity")))
        (destructuring-bind (value text) pair
          (let ((manager
                  (cadr-cli::make-memory-settings-manager)))
            (cadr-cli::settings-override-runtime-value
             manager "compaction"
             (cadr-ai::json-object field value))
            (is (search
                 (format
                  nil
                  "Invalid compaction.~A setting: ~A"
                  field text)
                 (goal22-error-text
                  (lambda () (goal22-triple manager)))))))))))

(test goal22-compaction-rejects-malformed-override-entries
  (let ((model (goal22-model "family/model")))
    (dolist (pair
             '(("null" "null")
               ("false" "false")
               ("42" "42")
               ("\"invalid\"" "invalid")
               ("[]" "")))
      (destructuring-bind (json text) pair
        (let ((manager
                (goal22-memory
                 (format
                  nil
                  "{\"compaction\":{\"modelOverrides\":{\"~A\":~A}}}"
                  +goal22-model-key+ json))))
          (is (string=
               (format
                nil
                "Invalid compaction.modelOverrides[\"~A\"] setting: ~A. Expected an object."
                +goal22-model-key+ text)
               (goal22-error-text
                (lambda ()
                  (goal22-triple manager model))))))))))

(test goal22-compaction-accepts-zero
  (let ((model (goal22-model "family/model"))
        (manager
          (goal22-memory
           "{\"compaction\":{\"reserveTokens\":0,\"keepRecentTokens\":0}}")))
    (is (equal '(t 0 0) (goal22-triple manager model)))
    (cadr-cli::settings-override-runtime-value
     manager "compaction"
     (cadr-ai::parse-json
      (format
       nil
       "{\"reserveTokens\":1000,\"keepRecentTokens\":1000,\"modelOverrides\":{\"~A\":{\"reserveTokens\":0,\"keepRecentTokens\":0}}}"
       +goal22-model-key+)))
    (is (equal '(t 0 0) (goal22-triple manager model)))))

(test goal22-compaction-sync-uses-the-active-model
  (let* ((model (goal22-model "family/model"))
         (manager
           (goal22-memory
            (format
             nil
             "{\"compaction\":{\"reserveTokens\":8192,\"keepRecentTokens\":10000,\"modelOverrides\":{\"~A\":{\"reserveTokens\":400000}}}}"
             +goal22-model-key+)))
         (agent (cadr-agent:make-agent :model model)))
    (cadr-cli::sync-agent-settings-from-manager agent manager)
    (is (= 8192
           (cadr-agent::agent-compaction-reserve-tokens agent)))
    (is (= 10000
           (cadr-agent::agent-compaction-keep-recent-tokens agent)))
    (multiple-value-bind (reserve keep enabled)
        (funcall
         (cadr-agent::agent-compaction-settings-function agent)
         model)
      (is (= 400000 reserve))
      (is (= 10000 keep))
      (is (eq t enabled)))
    (multiple-value-bind (reserve keep enabled)
        (funcall
         (cadr-agent::agent-compaction-settings-function agent)
         (goal22-model "other"))
      (is (= 8192 reserve))
      (is (= 10000 keep))
      (is (eq t enabled)))))

(test goal22-sdk-compaction-override-matches-the-settings-reader
  (let* ((model (goal22-model "family/model"))
         (settings
           (cadr-cli::make-memory-sdk-settings-manager
            (cadr-ai::parse-json
             (format
              nil
              "{\"compaction\":{\"reserveTokens\":8192,\"modelOverrides\":{\"~A\":{\"reserveTokens\":400000,\"keepRecentTokens\":1024}}}}"
              +goal22-model-key+))))
         (agent (cadr-agent:make-agent :model model)))
    (is (= 400000
           (cadr-cli:sdk-settings-compaction-reserve-tokens
            settings model)))
    (is (= 1024
           (cadr-cli:sdk-settings-compaction-keep-recent-tokens
            settings model)))
    (is (= 8192
           (cadr-cli:sdk-settings-compaction-reserve-tokens
            settings)))
    (cadr-cli::sdk-apply-agent-settings agent settings)
    (multiple-value-bind (reserve keep enabled)
        (funcall
         (cadr-agent::agent-compaction-settings-function agent)
         model)
      (is (= 400000 reserve))
      (is (= 1024 keep))
      (is (eq t enabled)))))
