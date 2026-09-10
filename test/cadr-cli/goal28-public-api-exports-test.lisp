(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defparameter +goal28-public-api-lisp-symbols+
  '(
    "+default-max-bytes+"
    "+default-max-lines+"
    "+project-config-directory-name+"
    "agent-session"
    "agent-session-runtime"
    "cadr-version"
    "coding-agent-directory"
    "collect-entries-for-branch-summary"
    "compact-agent"
    "copy-to-clipboard"
    "create-agent-session"
    "create-agent-session-from-services"
    "create-agent-session-runtime"
    "create-agent-session-services"
    "credential-synchronization-error"
    "default-resource-loader"
    "define-tool"
    "format-size"
    "format-skills-for-system-prompt"
    "generate-branch-summary"
    "get-powershell-config"
    "get-shell-config"
    "harness-session-build-context"
    "harness-session-build-context-entries"
    "key-hint"
    "key-text"
    "load-project-context-files"
    "load-skills"
    "load-skills-directory"
    "main"
    "make-bash-tool"
    "make-coding-tools"
    "make-edit-tool"
    "make-event-bus"
    "make-find-tool"
    "make-grep-tool"
    "make-ls-tool"
    "make-model-registry"
    "make-powershell-tool"
    "make-read-tool"
    "make-settings-manager"
    "make-write-tool"
    "parse-cli-arguments"
    "prepare-branch-entries"
    "raw-key-hint"
    "resize-image-rgba-to-limits"
    "resolve-model"
    "run-print-mode"
    "run-rpc-mode"
    "serialize-conversation"
    "session-manager"
    "truncate-head"
    "truncate-line"
    "truncate-tail"
    "with-file-mutation-queue"
    ))

(defun goal28-public-api-symbol-reachable-p (name)
  (loop for pkg-name in '("CADR-CLI" "CADR-AGENT" "CADR-CORE" "CADR-AI" "CADR-TUI"
                          "CADR-SERVER" "CADR-STORAGE")
        for pkg = (find-package pkg-name)
        for sym = (and pkg (find-symbol (string-upcase name) pkg))
        thereis (and sym
                     (or (fboundp sym)
                         (boundp sym)
                         (find-class sym nil)
                         (macro-function sym)))))

(test goal28-public-api-exports-reach-existing-lisp
  (dolist (name +goal28-public-api-lisp-symbols+)
    (is (goal28-public-api-symbol-reachable-p name)
        (format nil "missing Lisp symbol ~A" name))))
