(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(test goal28-terminal-warning-settings-reach-existing-readers
  (let ((manager (cadr-cli::make-memory-settings-manager)))
    (is (eq t
            (cadr-cli::settings-boolean-value
             manager "compaction" t "enabled")))
    (is (string=
         "streaming"
         (cadr-cli::settings-mermaid-rendering-mode manager)))
    (is (eq (string=
             (or (uiop:getenv "CADR_CLEAR_ON_SHRINK") "")
             "1")
            (cadr-cli::settings-clear-on-shrink-p manager)))
    (is (not (cadr-cli::settings-show-terminal-progress-p manager)))
    (is (null (cadr-cli::settings-terminal-capability-overrides manager)))
    (is (eq t
            (cadr-cli::settings-boolean-value
             manager "warnings" t "anthropicExtraUsage"))))
  (let* ((manager
           (cadr-cli::make-memory-settings-manager
            (args "compaction" (args "enabled" nil)
                  "markdown" (args "mermaid" "off")
                  "terminal"
                  (args "clearOnShrink" t
                        "showTerminalProgress" t
                        "hyperlinks" nil
                        "trueColor" t
                        "images" "kitty")
                  "warnings"
                  (args "anthropicExtraUsage" nil))))
         (overrides
           (cadr-cli::settings-terminal-capability-overrides
            manager)))
    (is (not
         (cadr-cli::settings-boolean-value
          manager "compaction" t "enabled")))
    (is (string=
         "off"
         (cadr-cli::settings-mermaid-rendering-mode manager)))
    (is (eq t (cadr-cli::settings-clear-on-shrink-p manager)))
    (is (eq t
            (cadr-cli::settings-show-terminal-progress-p manager)))
    (is (eq nil (getf overrides :hyperlinks-p)))
    (is (eq t (getf overrides :true-color-p)))
    (is (eq :kitty (getf overrides :images)))
    (is (not
         (cadr-cli::settings-boolean-value
          manager "warnings" t "anthropicExtraUsage"))))
  (let ((manager
          (cadr-cli::make-memory-settings-manager
           (args "markdown" (args "mermaid" "nope")
                 "terminal" (args "images" "none")))))
    (is (string=
         "streaming"
         (cadr-cli::settings-mermaid-rendering-mode manager)))
    (is (null
         (getf
          (cadr-cli::settings-terminal-capability-overrides
           manager)
          :images)))))
