(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

;;; Locked to pi@ecac0a9c4 packages/coding-agent/test/settings-manager-compaction.test.ts

(defparameter +goal24-compaction-model+
  '(:provider "provider" :id "family/model"))

(defparameter +goal24-compaction-model-key+
  "provider/family/model")

(defparameter +goal24-compaction-defaults+
  '(:enabled-p t :reserve-tokens 16384 :keep-recent-tokens 20000))

(defun goal24-compaction-settings-plist (manager &optional model)
  (cadr-cli::settings-compaction-settings manager model))

(defun goal24-assert-compaction-defaults (manager &optional model)
  (is (equal +goal24-compaction-defaults+
             (goal24-compaction-settings-plist manager model))))

(test goal24-compaction-defaults-without-settings
  (let ((manager (cadr-cli::make-memory-settings-manager)))
    (goal24-assert-compaction-defaults manager)
    (goal24-assert-compaction-defaults
     manager +goal24-compaction-model+)))

(test goal24-compaction-resolves-fields-independently
  (let* ((manager
           (cadr-cli::make-memory-settings-manager
            (args
             "compaction"
             (args
              "reserveTokens" 8192
              "keepRecentTokens" 10000
              "modelOverrides"
              (args
               +goal24-compaction-model-key+
               (args "reserveTokens" 400000))))))
         (with-model
           (goal24-compaction-settings-plist
            manager +goal24-compaction-model+)))
    (is (equal
         '(:enabled-p t :reserve-tokens 400000
           :keep-recent-tokens 10000)
         with-model))
    (is (= 400000
           (cadr-cli::settings-compaction-reserve-tokens
            manager +goal24-compaction-model+)))
    (is (= 10000
           (cadr-cli::settings-compaction-keep-recent-tokens
            manager +goal24-compaction-model+)))
    (is (equal
         '(:enabled-p t :reserve-tokens 8192
           :keep-recent-tokens 10000)
         (goal24-compaction-settings-plist manager)))
    (cadr-cli::settings-override-runtime-value
     manager "compaction"
     (args
      "modelOverrides"
      (args
       +goal24-compaction-model-key+
       (args "keepRecentTokens" 30000))))
    (is (= 30000
           (cadr-cli::settings-compaction-keep-recent-tokens
            manager +goal24-compaction-model+)))
    (is (= 400000
           (cadr-cli::settings-compaction-reserve-tokens
            manager +goal24-compaction-model+)))))

(test goal24-compaction-falls-back-for-missing-fields
  (let ((manager
          (cadr-cli::make-memory-settings-manager
           (args
            "compaction"
            (args
             "modelOverrides"
             (args
              +goal24-compaction-model-key+
              (args "keepRecentTokens" 1024)))))))
    (is (equal
         '(:enabled-p t :reserve-tokens 16384
           :keep-recent-tokens 1024)
         (goal24-compaction-settings-plist
          manager +goal24-compaction-model+)))))

(test goal24-compaction-exact-provider-model-keys
  (let ((manager
          (cadr-cli::make-memory-settings-manager
           (args
            "compaction"
            (args
             "modelOverrides"
             (args
              +goal24-compaction-model-key+
              (args "reserveTokens" 400000)
              "provider/*"
              (args "reserveTokens" 1)
              "family/model"
              (args "reserveTokens" 2)))))))
    (is (= 400000
           (cadr-cli::settings-compaction-reserve-tokens
            manager +goal24-compaction-model+)))
    (dolist
        (other
         '((:provider "other" :id "family/model")
           (:provider "provider" :id "other")
           (:provider "provider" :id "family/Model")))
      (goal24-assert-compaction-defaults manager other))))

(test goal24-compaction-merges-project-overrides-per-field
  (with-test-directory (root)
    (let* ((global
             (merge-pathnames "settings.json" root))
           (project
             (merge-pathnames
              "project/settings.json" root))
           (_
             (progn
               (write-text
                global
                (cadr-ai::stringify-json
                 (args
                  "compaction"
                  (args
                   "reserveTokens" 8192
                   "modelOverrides"
                   (args
                    +goal24-compaction-model-key+
                    (args
                     "reserveTokens" 400000
                     "keepRecentTokens" 30000)
                    "provider/other"
                    (args "keepRecentTokens" 4096))))))
               (ensure-directories-exist project)
               (write-text
                project
                (cadr-ai::stringify-json
                 (args
                  "compaction"
                  (args
                   "reserveTokens" 1024
                   "modelOverrides"
                   (args
                    +goal24-compaction-model-key+
                    (args "keepRecentTokens" 2000))))))))
           (manager
             (cadr-cli::make-settings-manager
              :global-path global
              :project-path project
              :project-trusted-p t)))
      (declare (ignore _))
      (is (equal
           '(:enabled-p t :reserve-tokens 400000
             :keep-recent-tokens 2000)
           (goal24-compaction-settings-plist
            manager +goal24-compaction-model+)))
      (is (equal
           '(:enabled-p t :reserve-tokens 1024
             :keep-recent-tokens 4096)
           (goal24-compaction-settings-plist
            manager
            '(:provider "provider" :id "other"))))
      (cadr-cli::settings-reload manager)
      (is (= 2000
             (cadr-cli::settings-compaction-keep-recent-tokens
              manager +goal24-compaction-model+)))
      (setf
       (cadr-cli::settings-manager-project-trusted-p
        manager)
       nil)
      (is (= 30000
             (cadr-cli::settings-compaction-keep-recent-tokens
              manager +goal24-compaction-model+))))))

(test goal24-compaction-enabled-stays-global
  (with-test-directory (root)
    (let* ((global
             (merge-pathnames "settings.json" root))
           (_
             (write-text
              global
              (cadr-ai::stringify-json
               (args
                "compaction"
                (args
                 "modelOverrides"
                 (args
                  +goal24-compaction-model-key+
                  (args
                   "enabled" nil
                   "reserveTokens" 400000)))))))
           (manager
             (cadr-cli::make-settings-manager
              :global-path global)))
      (declare (ignore _))
      ;; Override enabled is ignored; top-level enabled stays true.
      (is (eq t
              (getf
               (goal24-compaction-settings-plist
                manager +goal24-compaction-model+)
               :enabled-p)))
      (cadr-cli::settings-set-nested
       manager "compaction" "enabled" nil
       :scope :global)
      (cadr-cli::settings-reload manager)
      (is (equal
           '(:enabled-p nil :reserve-tokens 400000
             :keep-recent-tokens 20000)
           (goal24-compaction-settings-plist
            manager +goal24-compaction-model+))))))

(defun goal24-invalid-token-values ()
  (list
   'null
   -1
   1.5
   "400000"
   t
   (args)
   (vector)
   (1+ cadr-cli::+js-max-safe-integer+)))

(defun goal24-nonfinite-token-values ()
  ;; Avoid constant-folding (/ 0d0 0d0) at compile time.
  (let* ((zero 0d0)
         (nan (handler-bind
                  ((floating-point-invalid-operation
                    #'continue))
                (/ zero zero))))
    (list
     nan
     sb-ext:double-float-positive-infinity
     (- sb-ext:double-float-positive-infinity))))

(defun goal24-expect-error-message (thunk expected &key (prefix-p nil))
  (handler-case
      (progn
        (funcall thunk)
        (fail "expected error"))
    (error (condition)
      (let ((text (princ-to-string condition)))
        (if prefix-p
            (is (search expected text))
            (is (string= expected text)))))))

(test goal24-compaction-model-override-invalid-tokens
  (dolist (field '("reserveTokens" "keepRecentTokens"))
    (dolist (value (goal24-invalid-token-values))
      (let* ((manager
               (cadr-cli::make-memory-settings-manager
                (args
                 "compaction"
                 (args
                  "modelOverrides"
                  (args
                   +goal24-compaction-model-key+
                   (args field value))))))
             (message
               (format
                nil
                "Invalid compaction.modelOverrides[~S].~A setting: ~A. Expected a non-negative safe integer."
                +goal24-compaction-model-key+
                field
                (cadr-cli::settings-js-display-string
                 value))))
        (goal24-expect-error-message
         (lambda ()
           (goal24-compaction-settings-plist
            manager +goal24-compaction-model+))
         message)
        (goal24-assert-compaction-defaults manager)
        (goal24-assert-compaction-defaults
         manager
         (list :provider "other"
               :id (getf +goal24-compaction-model+
                         :id)))))
    ;; Non-finite floats cannot round-trip through cadr's JSON
    ;; settings writer. Probe the resolver on a raw hash table.
    (dolist (value (goal24-nonfinite-token-values))
      (let* ((compaction
               (args
                "modelOverrides"
                (args
                 +goal24-compaction-model-key+
                 (let ((entry (make-hash-table :test #'equal)))
                   (setf (gethash field entry) value)
                   entry))))
             (prefix
               (format
                nil
                "Invalid compaction.modelOverrides[~S].~A setting: ~A"
                +goal24-compaction-model-key+
                field
                (cadr-cli::settings-js-display-string
                 value))))
        (goal24-expect-error-message
         (lambda ()
           (cadr-cli::settings-compaction-token-from-object
            compaction field +goal24-compaction-model+))
         prefix
         :prefix-p t)))))
(test goal24-compaction-ordinary-invalid-tokens
  (dolist (field '("reserveTokens" "keepRecentTokens"))
    (dolist (value (goal24-invalid-token-values))
      (let* ((manager
               (cadr-cli::make-memory-settings-manager
                (args
                 "compaction"
                 (args
                  field value
                  "modelOverrides"
                  (args
                   +goal24-compaction-model-key+
                   (args field 4096))))))
             (message
               (format
                nil
                "Invalid compaction.~A setting: ~A. Expected a non-negative safe integer."
                field
                (cadr-cli::settings-js-display-string
                 value))))
        (dolist (model
                 (list nil +goal24-compaction-model+))
          (goal24-expect-error-message
           (lambda ()
             (goal24-compaction-settings-plist
              manager model))
           message))))
    (dolist (value (goal24-nonfinite-token-values))
      (let* ((compaction
               (let ((table (make-hash-table :test #'equal)))
                 (setf (gethash field table) value)
                 table))
             (prefix
               (format
                nil
                "Invalid compaction.~A setting: ~A"
                field
                (cadr-cli::settings-js-display-string
                 value))))
        (goal24-expect-error-message
         (lambda ()
           (cadr-cli::settings-compaction-token-from-object
            compaction field))
         prefix
         :prefix-p t)))))

(test goal24-compaction-malformed-model-entries
  (dolist (entry (list 'null nil 42 "invalid" (vector)))
    (let* ((manager
             (cadr-cli::make-memory-settings-manager
              (args
               "compaction"
               (args
                "modelOverrides"
                (args
                 +goal24-compaction-model-key+
                 entry)))))
           (message
             (format
              nil
              "Invalid compaction.modelOverrides[~S] setting: ~A. Expected an object."
              +goal24-compaction-model-key+
              (cadr-cli::settings-js-display-string
               entry))))
      (goal24-expect-error-message
       (lambda ()
         (goal24-compaction-settings-plist
          manager +goal24-compaction-model+))
       message))))

(test goal24-compaction-accepts-zero
  (let ((manager
          (cadr-cli::make-memory-settings-manager
           (args
            "compaction"
            (args "reserveTokens" 0 "keepRecentTokens" 0)))))
    (is (equal
         '(:enabled-p t :reserve-tokens 0
           :keep-recent-tokens 0)
         (goal24-compaction-settings-plist
          manager +goal24-compaction-model+)))
    (cadr-cli::settings-override-runtime-value
     manager "compaction"
     (args
      "reserveTokens" 1000
      "keepRecentTokens" 1000
      "modelOverrides"
      (args
       +goal24-compaction-model-key+
       (args "reserveTokens" 0 "keepRecentTokens" 0))))
    (is (equal
         '(:enabled-p t :reserve-tokens 0
           :keep-recent-tokens 0)
         (goal24-compaction-settings-plist
          manager +goal24-compaction-model+)))))

(test goal24-compaction-sync-passes-agent-model
  (let* ((manager
           (cadr-cli::make-memory-settings-manager
            (args
             "compaction"
             (args
              "reserveTokens" 10
              "keepRecentTokens" 20
              "modelOverrides"
              (args
               "faux/faux-1"
               (args
                "reserveTokens" 2000
                "keepRecentTokens" 150))))))
         (agent
           (cadr-agent:make-agent
            :provider :faux
            :model
            (cadr-ai:make-model
             :id "faux-1"
             :provider :faux
             :name "faux-1"))))
    (cadr-cli::sync-agent-settings-from-manager
     agent manager)
    (is (= 2000
           (cadr-agent::agent-compaction-reserve-tokens
            agent)))
    (is (= 150
           (cadr-agent::agent-compaction-keep-recent-tokens
            agent)))
    (setf
     (cadr-agent:agent-model agent)
     (cadr-ai:make-model
      :id "other"
      :provider :faux
      :name "other"))
    (cadr-cli::sync-agent-compaction-tokens
     agent manager)
    (is (= 10
           (cadr-agent::agent-compaction-reserve-tokens
            agent)))
    (is (= 20
           (cadr-agent::agent-compaction-keep-recent-tokens
            agent)))))
