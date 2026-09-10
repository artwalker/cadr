(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defparameter +goal28-extension-remaining-callables+
  '(("ExtensionActions.refreshTools" . cadr-agent::refresh-agent-extension-tools)
    ("ExtensionCommandContextActions.newSession"
     . cadr-agent:extension-command-context-new-session)
    ("ExtensionCommandContextActions.reload" . cadr-agent:extension-context-reload)
    ("ExtensionCommandContextActions.waitForIdle"
     . cadr-agent:extension-command-context-wait-for-idle)
    ("ExtensionCommandContextActions.navigateTree" . cadr-agent:agent-navigate-tree)
    ("ExtensionCommandContextActions.fork" . cadr-agent:session-repository-fork)
    ("ExtensionCommandContextActions.switchSession"
     . cadr-cli:agent-session-runtime-switch-session)
    ("ExtensionContextActions.getSystemPromptOptions"
     . cadr-agent:extension-command-context-system-prompt-options)
    ("ExtensionContextActions.isProjectTrusted"
     . cadr-cli::settings-manager-project-trusted-p)
    ("ExtensionContext.modelRegistry"
     . cadr-agent:extension-context-model-registry-find)
    ("ExtensionContext.sessionManager" . cadr-agent:extension-context-session)
    ("ExtensionContext.ui" . cadr-agent:extension-context-has-ui-p)
    ("ExtensionRuntimeState.assertActive"
     . cadr-agent::assert-active-extension-context)
    ("ExtensionRuntimeState.flagValues" . cadr-agent::extension-host-flag-values)
    ("ExtensionRuntimeState.invalidate"
     . cadr-agent::invalidate-extension-host-generation)
    ("ExtensionRuntimeState.registerProvider"
     . cadr-agent:extension-context-register-provider)
    ("ExtensionRuntimeState.registerNativeProvider"
     . cadr-agent:define-native-provider)
    ("ExtensionRuntimeState.trackEventBusSubscription"
     . cadr-agent::extension-host-event-listeners)
    ("ExtensionUIDialogOptions.signal"
     . cadr-agent::validate-extension-ui-signal)
    ("ExtensionUIDialogOptions.timeout"
     . cadr-agent::validate-extension-timeout)
    ("ExtensionWidgetOptions.placement"
     . cadr-agent:extension-context-set-widget)))

(test goal28-extension-bundle-fields-reach-existing-struct
  (let ((bundle
          (cadr-agent::make-extension-bundle
           :id "goal28"
           :path "/tmp/goal28"
           :commands '(1)
           :tools '(2)
           :flags '(3)
           :shortcuts '(4)
           :hooks '(5)
           :message-renderers '(6)
           :entry-renderers '(7)
           :markdown-transformer 'transformer
           :hidden-p t)))
    (is (string= "goal28" (cadr-agent::extension-bundle-id bundle)))
    (is (string= "/tmp/goal28" (cadr-agent::extension-bundle-path bundle)))
    (is (equal '(1) (cadr-agent::extension-bundle-commands bundle)))
    (is (equal '(2) (cadr-agent::extension-bundle-tools bundle)))
    (is (equal '(3) (cadr-agent::extension-bundle-flags bundle)))
    (is (equal '(4) (cadr-agent::extension-bundle-shortcuts bundle)))
    (is (equal '(5) (cadr-agent::extension-bundle-hooks bundle)))
    (is (equal '(6) (cadr-agent::extension-bundle-message-renderers bundle)))
    (is (equal '(7) (cadr-agent::extension-bundle-entry-renderers bundle)))
    (is (eq 'transformer
            (cadr-agent::extension-bundle-markdown-transformer bundle)))
    (is (cadr-agent::extension-bundle-hidden-p bundle)))
  (let ((flag
          (cadr-agent::make-extension-flag-definition
           :name "flag"
           :description "d"
           :type :boolean
           :default t
           :bundle (cadr-agent::make-extension-bundle :path "/ext")))
        (shortcut
          (cadr-agent::make-extension-shortcut-definition
           :key "ctrl+x"
           :description "s"
           :handler #'identity
           :bundle (cadr-agent::make-extension-bundle :path "/ext")))
        (command
          (cadr-agent::make-extension-command-definition
           :name "cmd"
           :description "c"
           :argument-hint "hint"
           :handler #'identity
           :bundle (cadr-agent::make-extension-bundle :path "/ext"))))
    (is (string= "flag" (cadr-agent::extension-flag-definition-name flag)))
    (is (string= "d" (cadr-agent::extension-flag-definition-description flag)))
    (is (eq :boolean (cadr-agent::extension-flag-definition-type flag)))
    (is (eq t (cadr-agent::extension-flag-definition-default flag)))
    (is (string=
         "/ext"
         (cadr-agent::extension-bundle-path
          (cadr-agent::extension-flag-definition-bundle flag))))
    (is (string= "ctrl+x" (cadr-agent::extension-shortcut-definition-key shortcut)))
    (is (string= "s" (cadr-agent::extension-shortcut-definition-description shortcut)))
    (is (functionp (cadr-agent::extension-shortcut-definition-handler shortcut)))
    (is (string=
         "/ext"
         (cadr-agent::extension-bundle-path
          (cadr-agent::extension-shortcut-definition-bundle shortcut))))
    (is (string= "cmd" (cadr-agent::extension-command-definition-name command)))
    (is (string= "c" (cadr-agent::extension-command-definition-description command)))
    (is (string= "hint" (cadr-agent::extension-command-definition-argument-hint command)))
    (is (functionp (cadr-agent::extension-command-definition-handler command)))
    (is (string=
         "/ext"
         (cadr-agent::extension-bundle-path
          (cadr-agent::extension-command-definition-bundle command)))))
  (is (fboundp 'cadr-agent:extension-context-model-registry-find))
  (is (fboundp 'cadr-agent:extension-context-reload))
  (is (fboundp 'cadr-agent:extension-context-set-session-name))
  (is (find-class 'cadr-agent:extension-registration-error nil))
  (is (find-class 'cadr-agent:extension-execution-error nil))
  (dolist (entry +goal28-extension-remaining-callables+)
    (is (or (fboundp (cdr entry)) (boundp (cdr entry)) (macro-function (cdr entry)))))
  (is (fboundp 'cadr-agent::extension-host-flag-values))
  (let ((host (cadr-agent::%make-extension-host)))
    (is (hash-table-p (cadr-agent::extension-host-flag-values host)))
    (is (hash-table-p (cadr-agent::extension-host-event-listeners host)))
    (is (listp (cadr-agent::extension-host-pending-custom-messages host)))))
