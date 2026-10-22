(in-package #:cadr-cli/tests)

;;; Goal 26: settings-schema.ts migrations and deviceId (pi@71023aec).

(defun goal26-settings-table (&rest pairs)
  (let ((table (cadr-cli::empty-json-object)))
    (loop for (key value) on pairs by #'cddr
          do (setf (gethash key table) value))
    table))

(fiveam:test goal26-queue-mode-migrates-to-steering-mode
  (let* ((migrated
           (cadr-cli::migrate-legacy-settings
            (goal26-settings-table
             "queueMode" "all")))
         (manager
           (cadr-cli::make-memory-settings-manager migrated)))
    (fiveam:is
     (string=
      "all"
      (cadr-cli::settings-value manager "steeringMode")))
    (fiveam:is
     (not
      (cadr-ai::json-present-p migrated "queueMode")))))

(fiveam:test goal26-queue-mode-keeps-existing-steering-mode
  (let ((migrated
          (cadr-cli::migrate-legacy-settings
           (goal26-settings-table
            "queueMode" "all"
            "steeringMode" "one-at-a-time"))))
    (fiveam:is
     (string=
      "one-at-a-time"
      (gethash "steeringMode" migrated)))
    (fiveam:is
     (cadr-ai::json-present-p migrated "queueMode"))))

(fiveam:test goal26-websockets-boolean-migrates-to-transport
  (let ((on
          (cadr-cli::migrate-legacy-settings
           (goal26-settings-table "websockets" t)))
        (off
          (cadr-cli::migrate-legacy-settings
           (goal26-settings-table "websockets" nil))))
    (fiveam:is (string= "websocket" (gethash "transport" on)))
    (fiveam:is (not (cadr-ai::json-present-p on "websockets")))
    (fiveam:is (string= "sse" (gethash "transport" off)))))

(fiveam:test goal26-legacy-skills-object-becomes-directories
  (let* ((skills (goal26-settings-table
                  "enableSkillCommands" nil
                  "customDirectories"
                  (vector "/tmp/skills")))
         (migrated
           (cadr-cli::migrate-legacy-settings
            (goal26-settings-table "skills" skills))))
    (fiveam:is
     (equalp (vector "/tmp/skills")
             (gethash "skills" migrated)))
    (fiveam:is
     (null
      (gethash "enableSkillCommands" migrated)))))

(fiveam:test goal26-device-id-is-global-and-stable
  (let* ((dir
           (ensure-directories-exist
            (uiop:ensure-directory-pathname
             (merge-pathnames
              (format nil "cadr-g26-device-~A/"
                      (cadr-ai:uuid-v7))
              (uiop:temporary-directory)))))
         (path (merge-pathnames "settings.json" dir))
         (manager
           (cadr-cli::make-settings-manager
            :global-path path))
         (first (cadr-cli::settings-device-id manager))
         (second (cadr-cli::settings-device-id manager))
         (reloaded
           (cadr-cli::make-settings-manager
            :global-path path)))
    (fiveam:is (stringp first))
    (fiveam:is (= 36 (length first)))
    (fiveam:is (string= first second))
    (fiveam:is
     (string=
      first
      (cadr-cli::settings-device-id reloaded)))
    (uiop:delete-directory-tree
     dir :validate t :if-does-not-exist :ignore)))
