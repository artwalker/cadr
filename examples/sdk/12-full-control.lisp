(defpackage #:cadr-example-sdk-12
  (:use #:cl)
  (:export #:run))

(in-package #:cadr-example-sdk-12)

(defun run (&key model stream-function
              (cwd (uiop:getcwd)) agent-directory api-key)
  "Construct an explicit no-discovery, in-memory SDK session."
  (let* ((agent-dir
           (or agent-directory
               (merge-pathnames "cadr-sdk/" (uiop:temporary-directory))))
         (runtime
           (cadr-cli:make-sdk-model-runtime
            :auth-path (merge-pathnames "auth.json" agent-dir)
            :models-path (merge-pathnames "models.json" agent-dir)))
         (settings
           (cadr-cli:make-memory-sdk-settings-manager))
         (resources
           (cadr-cli:make-sdk-resource-loader
            :cwd cwd :agent-directory agent-dir
            :no-extensions-p t :no-skills-p t :no-prompts-p t
            :no-themes-p t :no-context-files-p t
            :system-prompt
            "You are a minimal assistant. Available: read, bash. Be concise."
            :append-system-prompt nil)))
    (when api-key
      (cadr-cli:sdk-model-runtime-set-api-key
       runtime (cadr-ai:model-provider model) api-key))
    (cadr-cli:sdk-resource-loader-reload resources)
    (multiple-value-bind (session)
        (cadr-cli:create-agent-session
         :cwd cwd :agent-directory agent-dir
         :model model :thinking-level :off
         :model-runtime runtime
         :resource-loader resources
         :tools '("read" "bash")
         :session-manager (cadr-cli:session-manager-in-memory cwd)
         :settings-manager settings
         :stream-function stream-function)
      session)))
