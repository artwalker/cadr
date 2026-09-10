(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(test goal28-cli-settings-readers-match-pin-defaults
  (let ((manager (cadr-cli::make-memory-settings-manager)))
    (is (eq t (cadr-cli::settings-show-terminal-images-p manager)))
    (is (= 60 (cadr-cli::settings-terminal-image-width-cells manager)))
    (is (eq :regular (cadr-cli::settings-tui-mode manager)))
    (is (null (cadr-cli::settings-default-tools manager)))
    (is (string= "auto" (cadr-cli::settings-fullscreen-scrollbar manager)))
    (is (eq :transcript (cadr-cli::settings-fullscreen-exit-output manager)))
    (is (eq t (cadr-cli::settings-fullscreen-copy-on-select-p manager)))
    (is (= 1 (cadr-cli::settings-output-padding manager)))
    (is (eq :all (cadr-cli::settings-enabled-models manager)))
    (is (null (cadr-cli::settings-default-provider manager)))
    (is (null (cadr-cli::settings-default-model manager)))
    (is (null (cadr-cli::settings-default-thinking-level manager)))
    (is (eq :detect-once (cadr-cli::settings-terminal-theme-mode manager)))
    (is (= 5
           (cadr-cli::settings-choice-value
            manager "autocompleteMaxVisible"
            '(3 5 7 10 15 20) 5)))
    (is (not (cadr-cli::settings-boolean-value manager "quietStartup" nil)))
    (is (not (cadr-cli::settings-boolean-value manager "hideThinkingBlock" nil)))
    (is (not (cadr-cli::settings-boolean-value manager "showCacheMissNotices" nil)))
    (is (not (cadr-cli::settings-boolean-value manager "collapseChangelog" nil)))
    (is (not (cadr-cli::settings-boolean-value manager "showHardwareCursor" nil)))
    (is (eq t (cadr-cli::settings-boolean-value manager "enableSkillCommands" t)))
    (is (eq t (cadr-cli::settings-boolean-value manager "enableInstallTelemetry" t)))
    (is (not (cadr-cli::settings-analytics-enabled-p manager)))
    (is (null (cadr-cli::settings-tracking-id manager)))
    (is (string= "ask"
                 (cadr-cli::settings-choice-value
                  manager "defaultProjectTrust"
                  '("ask" "always" "never") "ask")))
    (is (string= "tree"
                 (cadr-cli::settings-choice-value
                  manager "doubleEscapeAction"
                  '("tree" "fork" "none") "tree")))
    (is (string= "default"
                 (cadr-cli::settings-choice-value
                  manager "treeFilterMode"
                  '("default" "no-tools" "user-only" "labeled-only" "all")
                  "default")))
    (is (string= "auto"
                 (cadr-cli::settings-choice-value
                  manager "transport"
                  '("sse" "websocket" "websocket-cached" "auto")
                  "auto")))
    (is (= 0
           (cadr-cli::settings-choice-value
            manager "editorPaddingX" '(0 1 2 3) 0)))
    (is (string= "one-at-a-time"
                 (cadr-cli::settings-choice-value
                  manager "steeringMode"
                  '("one-at-a-time" "all")
                  "one-at-a-time")))
    (is (string= "one-at-a-time"
                 (cadr-cli::settings-choice-value
                  manager "followUpMode"
                  '("one-at-a-time" "all")
                  "one-at-a-time")))
    (is (null
         (cadr-cli::settings-model-thinking-level
          manager :openai "gpt-test"))))
  (let ((manager
          (cadr-cli::make-memory-settings-manager
           (args "terminal"
                 (args "showImages" nil "imageWidthCells" 80)
                 "tuiMode" "fullscreen"
                 "defaultTools" (vector "read" "bash")
                 "fullscreenScrollbar" "hidden"
                 "fullscreenExitOutput" "resume-hint"
                 "fullscreenCopyOnSelect" nil
                 "outputPad" 0
                 "enabledModels" (vector "openai/gpt-test")
                 "defaultProvider" "openai"
                 "defaultModel" "gpt-test"
                 "defaultThinkingLevel" "high"
                 "theme" "dark"
                 "autocompleteMaxVisible" 10
                 "quietStartup" t
                 "hideThinkingBlock" t
                 "showCacheMissNotices" t
                 "collapseChangelog" t
                 "showHardwareCursor" t
                 "enableSkillCommands" nil
                 "enableInstallTelemetry" nil
                 "enableAnalytics" t
                 "trackingId" "track-1"
                 "defaultProjectTrust" "never"
                 "doubleEscapeAction" "none"
                 "treeFilterMode" "user-only"
                 "transport" "sse"
                 "editorPaddingX" 2
                 "steeringMode" "all"
                 "followUpMode" "all"
                 "modelThinkingLevels"
                 (args "openai/gpt-test" "low")))))
    (is (not (cadr-cli::settings-show-terminal-images-p manager)))
    (is (= 80 (cadr-cli::settings-terminal-image-width-cells manager)))
    (is (eq :fullscreen (cadr-cli::settings-tui-mode manager)))
    (is (equal '("read" "bash") (cadr-cli::settings-default-tools manager)))
    (is (string= "hidden" (cadr-cli::settings-fullscreen-scrollbar manager)))
    (is (eq :resume-hint (cadr-cli::settings-fullscreen-exit-output manager)))
    (is (not (cadr-cli::settings-fullscreen-copy-on-select-p manager)))
    (is (= 0 (cadr-cli::settings-output-padding manager)))
    (is (equal '("openai/gpt-test") (cadr-cli::settings-enabled-models manager)))
    (is (string= "openai" (cadr-cli::settings-default-provider manager)))
    (is (string= "gpt-test" (cadr-cli::settings-default-model manager)))
    (is (eq :high (cadr-cli::settings-default-thinking-level manager)))
    (is (eq :fixed (cadr-cli::settings-terminal-theme-mode manager)))
    (is (= 10
           (cadr-cli::settings-choice-value
            manager "autocompleteMaxVisible"
            '(3 5 7 10 15 20) 5)))
    (is (eq t (cadr-cli::settings-boolean-value manager "quietStartup" nil)))
    (is (eq t (cadr-cli::settings-boolean-value manager "hideThinkingBlock" nil)))
    (is (eq t (cadr-cli::settings-boolean-value manager "showCacheMissNotices" nil)))
    (is (eq t (cadr-cli::settings-boolean-value manager "collapseChangelog" nil)))
    (is (eq t (cadr-cli::settings-boolean-value manager "showHardwareCursor" nil)))
    (is (not (cadr-cli::settings-boolean-value manager "enableSkillCommands" t)))
    (is (not (cadr-cli::settings-boolean-value manager "enableInstallTelemetry" t)))
    (is (eq t (cadr-cli::settings-analytics-enabled-p manager)))
    (is (string= "track-1" (cadr-cli::settings-tracking-id manager)))
    (is (string= "never"
                 (cadr-cli::settings-choice-value
                  manager "defaultProjectTrust"
                  '("ask" "always" "never") "ask")))
    (is (string= "none"
                 (cadr-cli::settings-choice-value
                  manager "doubleEscapeAction"
                  '("tree" "fork" "none") "tree")))
    (is (string= "user-only"
                 (cadr-cli::settings-choice-value
                  manager "treeFilterMode"
                  '("default" "no-tools" "user-only" "labeled-only" "all")
                  "default")))
    (is (string= "sse"
                 (cadr-cli::settings-choice-value
                  manager "transport"
                  '("sse" "websocket" "websocket-cached" "auto")
                  "auto")))
    (is (= 2
           (cadr-cli::settings-choice-value
            manager "editorPaddingX" '(0 1 2 3) 0)))
    (is (string= "all"
                 (cadr-cli::settings-choice-value
                  manager "steeringMode"
                  '("one-at-a-time" "all")
                  "one-at-a-time")))
    (is (string= "all"
                 (cadr-cli::settings-choice-value
                  manager "followUpMode"
                  '("one-at-a-time" "all")
                  "one-at-a-time")))
    (is (eq :low
            (cadr-cli::settings-model-thinking-level
             manager :openai "gpt-test"))))
  (let ((manager
          (cadr-cli::make-memory-settings-manager
           (args "terminal" (args "imageWidthCells" 40)
                 "autocompleteMaxVisible" 4
                 "tuiMode" "nope"
                 "outputPad" 9))))
    (is (= 60 (cadr-cli::settings-terminal-image-width-cells manager)))
    (is (= 5
           (cadr-cli::settings-choice-value
            manager "autocompleteMaxVisible"
            '(3 5 7 10 15 20) 5)))
    (is (eq :regular (cadr-cli::settings-tui-mode manager)))
    (is (= 1 (cadr-cli::settings-output-padding manager)))))
