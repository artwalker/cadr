(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defun goal15-fixed-text-row (text width)
  (let* ((limited (if (> (length text) width)
                      (subseq text 0 width)
                      text))
         (padding
           (max 0 (- width (cadr-tui:visible-width limited)))))
    (concatenate
     'string limited
     (make-string padding :initial-element #\Space))))

(defun goal15-fixed-input-row (text width)
  ;; pi@53fa77ccd Input always reserves its software-cursor cell.
  (goal15-fixed-text-row
   (concatenate 'string "> " text " ") width))

(defun make-goal15-fake-rg-program (directory)
  (let ((program (merge-pathnames "rg" directory)))
    (with-open-file
        (stream program
                :direction :output
                :if-exists :supersede
                :if-does-not-exist :create)
      (write-line "#!/bin/sh" stream)
      (write-line "for argument do search_path=$argument; done" stream)
      (write-line
       "printf '{\"type\":\"match\",\"data\":{\"path\":{\"text\":\"%s/beta.md\"},\"lines\":{\"text\":\"needle beta\\\\n\"},\"line_number\":1}}\\n' \"$search_path\""
       stream)
      (write-line
       "printf '{\"type\":\"match\",\"data\":{\"path\":{\"text\":\"%s/alpha.txt\"},\"lines\":{\"text\":\"needle alpha\\\\n\"},\"line_number\":1}}\\n' \"$search_path\""
       stream))
    (uiop:run-program (list "chmod" "+x" (namestring program)))
    program))

(test goal15-grep-preserves-fixed-baseline-ripgrep-stream-order
  (with-test-directory (directory)
    (let ((bin (merge-pathnames "bin/" directory))
          (notes (merge-pathnames "notes/" directory)))
      (ensure-directories-exist (merge-pathnames "anchor" bin))
      (write-text (merge-pathnames "alpha.txt" notes)
                  (format nil "needle alpha~%"))
      (write-text (merge-pathnames "beta.md" notes)
                  (format nil "needle beta~%"))
      (make-goal15-fake-rg-program bin)
      (with-test-path-prefix (bin)
        (multiple-value-bind (content details)
            (invoke-tool
             (cadr-cli::make-grep-tool directory)
             (args "pattern" "needle" "path" "notes"))
          (declare (ignore details))
          (is
           (string=
            (format nil
                    "beta.md:1: needle beta~%alpha.txt:1: needle alpha")
            (result-text content))))))))

(test goal15-ls-relative-subdirectory-lists-the-requested-directory
  (with-test-directory (directory)
    (write-text (merge-pathnames "root-decoy.txt" directory) "root")
    (write-text (merge-pathnames "notes/alpha.txt" directory) "alpha")
    (write-text (merge-pathnames "notes/beta.md" directory) "beta")
    (multiple-value-bind (content details)
        (invoke-tool
         (cadr-cli::make-ls-tool directory)
         (args "path" "notes"))
      (declare (ignore details))
      (is
       (string=
        (format nil "alpha.txt~%beta.md")
        (result-text content))))))

(test goal15-read-missing-relative-path-preserves-baseline-enoent-copy
  (with-test-directory (directory)
    (let* ((display-path "notes/missing.txt")
           (absolute-path
             (namestring (merge-pathnames display-path directory)))
           (expected
             (format nil
                     "ENOENT: no such file or directory, access '~A'"
                     absolute-path)))
      (handler-case
          (progn
            (invoke-tool
             (cadr-cli::make-read-tool directory)
             (args "path" display-path))
            (fail "missing read path should fail"))
        (condition (condition)
          (is (string= expected (princ-to-string condition))))))))

(test goal15-directory-tool-pathname-forms-stay-rooted-in-relative-subdirectories
  (with-test-directory (directory)
    (write-text (merge-pathnames "root-decoy.txt" directory) "root")
    (write-text (merge-pathnames "notes/nested/kept.txt" directory) "kept")
    (multiple-value-bind (content details)
        (invoke-tool
         (cadr-cli::make-find-tool directory)
         (args "pattern" "*.txt" "path" "notes"))
      (declare (ignore details))
      (is (search "nested/kept.txt" (result-text content)))
      (is (not (search "root-decoy.txt" (result-text content)))))
    (multiple-value-bind (content details)
        (invoke-tool
         (cadr-cli::make-glob-tool directory)
         (args "pattern" "**/*.txt" "path" "notes"))
      (declare (ignore details))
      (is (search "notes/nested/kept.txt" (result-text content)))
      (is (not (search "root-decoy.txt" (result-text content)))))
    (invoke-tool
     (cadr-cli::make-write-tool directory)
     (args "path" "notes/generated/result.txt" "content" "written"))
    (is
     (string=
      "written"
      (read-text
       (merge-pathnames "notes/generated/result.txt" directory))))))

(test goal15-startup-chrome-matches-fixed-baseline-padding-and-styles
  ;; pi@53fa77ccd interactive-mode.ts:754-812 constructs an ExpandableText
  ;; with one horizontal cell of padding, styles the product and version
  ;; separately, and styles key tokens independently from descriptions.
  (let* ((width 72)
         (lines
           (cadr-cli::render-tui-startup-lines
            '("cadr v0.2.0"
              "escape interrupt · ctrl+c/ctrl+d clear/exit · / commands · ! bash · ctrl+o more"
              "Press ctrl+o to show full startup help and loaded resources.")
            width))
         (logo (first lines))
         (help (second lines)))
    (is (= width (cadr-tui:visible-width logo)))
    (is (= width (cadr-tui:visible-width help)))
    (is
     (uiop:string-prefix-p
      " cadr v0.2.0"
      (cadr-tui:strip-terminal-sequences logo)))
    (is
     (search
      (cadr-tui:theme-bold
       (cadr-tui:theme-foreground
        :accent "cadr" :enabled-p t))
      logo))
    (is
     (search
      (cadr-tui:theme-foreground
       :dim " v0.2.0" :enabled-p t)
      logo))
    (is
     (search
      (cadr-tui:theme-foreground
       :dim "escape" :enabled-p t)
      help))
    (is
     (search
      (cadr-tui:theme-foreground
       :muted " interrupt" :enabled-p t)
      help))))

(test goal15-root-composition-has-no-invented-idle-status-rows
  ;; pi@53fa77ccd interactive-mode.ts:734-746 leaves statusContainer empty
  ;; while idle.  Only widgetContainerAbove contributes its default spacer.
  (labels ((editor-top (status)
             (let ((state
                     (cadr-cli::make-tui-state
                      :model "faux-1"
                      :cwd "/tmp/project"
                      :context-window 128000)))
               (setf (cadr-cli::tui-state-status-message state) status)
               (multiple-value-bind (lines row column)
                   (cadr-cli::render-tui-state
                    state (cadr-tui:make-multiline-editor)
                    60 20 :full-document-p t
                    :spinner-frame "x")
                 (declare (ignore row column))
                 (position-if
                  (lambda (line)
                    (let ((plain
                            (cadr-tui:strip-terminal-sequences line)))
                      (and (plusp (length plain))
                           (every (lambda (character)
                                    (char= character #\─))
                                  plain))))
                  lines)))))
    (is (= 1 (editor-top nil)))
    (is (= 3 (editor-top "Working...")))))

(test goal15-footer-initial-context-and-thinking-follow-model-capability
  ;; footer.ts:116-119 renders an absent initial usage estimate as 0.0%, but
  ;; preserves NIL after compaction as unknown.  Lines 173-178 only append a
  ;; thinking suffix for reasoning-capable models.
  (let ((state
          (cadr-cli::make-tui-state
           :model "faux-1" :cwd "/tmp/project"
           :context-window 128000))
        (plain-model
          (cadr-ai:make-model
           :id "plain" :name "Plain" :provider :faux :api :faux
           :base-url "http://localhost:0" :reasoning-p nil
           :context-window 128000 :max-tokens 4096))
        (reasoning-model
          (cadr-ai:make-model
           :id "reasoning" :name "Reasoning" :provider :faux :api :faux
           :base-url "http://localhost:0" :reasoning-p t
           :context-window 128000 :max-tokens 4096)))
    (is (= 0d0 (cadr-cli::tui-state-context-percent state)))
    (let ((footer
            (mapcar
             #'cadr-tui:strip-terminal-sequences
             (cadr-tui:render-footer
              72 :cwd "/tmp/project" :model "faux-1"
              :context-percent
              (cadr-cli::tui-state-context-percent state)
              :context-window 128000 :auto-compact-p t))))
      (is (search "0.0%/128k (auto)" (second footer))))
    (cadr-cli::apply-tui-footer-state state '(:context-percent nil))
    (is (null (cadr-cli::tui-state-context-percent state)))
    (is (null (cadr-cli::model-footer-thinking-level plain-model :high)))
    (is
     (eq :high
         (cadr-cli::model-footer-thinking-level reasoning-model :high)))))

(test goal15-provider-stream-receives-the-active-session-id
  ;; pi@53fa77ccd agent.ts:430-440 forwards Agent.sessionId into every normal
  ;; provider stream request, enabling provider cache usage and footer totals.
  (let* ((captured nil)
        (stream
          (cadr-cli::make-extension-aware-stream-function
           nil :session-id "session-15"
           :stream-function
           (lambda (provider model context on-event &rest options)
             (declare (ignore provider model context on-event))
             (setf captured options)
             :streamed))))
    (is
     (eq :streamed
         (funcall
          stream nil
          (cadr-ai:make-model :id "faux" :provider :faux :api :faux)
          (cadr-ai:make-context)
          (lambda (event) (declare (ignore event)))
          :session-id nil)))
    (is (string= "session-15" (getf captured :session-id)))))

(test goal15-terminal-title-matches-fixed-baseline-session-grammar
  ;; pi@53fa77ccd interactive-mode.ts:843-854 uses APP_TITLE, optional session
  ;; name, and the cwd basename, then delegates control-byte stripping to the
  ;; terminal title boundary.
  (is
   (string=
    "cadr - project"
    (cadr-cli::tui-terminal-title "/tmp/project/" nil)))
  (is
   (string=
    "cadr - project"
    (cadr-cli::tui-terminal-title #P"/tmp/project/" nil)))
  (is
   (string=
    "cadr - branch work - project"
    (cadr-cli::tui-terminal-title
     "/tmp/project/" "branch work")))
  (is
   (string=
    (format nil "~C]0;cadr - branchwork - project~C"
            #\Escape (code-char 7))
    (cadr-cli::tui-terminal-title-sequence
     "/tmp/project/"
     (format nil "branch~Cwork" #\Escape)))))

(test goal15-selector-overlays-preserve-natural-height-and-input-cursor
  ;; pi@53fa77ccd model-selector.ts:91-129 composes the selector from normal
  ;; components.  The root renderer owns viewport cropping; it does not delete
  ;; spacers or rebuild a compact selector.  Input supplies the real cursor.
  (let* ((models
           (loop for index below 14
                 collect
                 (cadr-ai:make-model
                  :id (format nil "model-~2,'0D" index)
                  :name (format nil "Model ~D" index)
                  :provider :faux :api :faux
                  :base-url "http://localhost:0"
                  :context-window 128000 :max-tokens 4096)))
         (scoped-overlay
           (cadr-cli::make-model-selector-state
            :all-models models
            :scoped-models models
            :current-model (first models)))
         (unscoped-overlay
           (cadr-cli::make-model-selector-state
            :all-models models
            :current-model (first models))))
    (cadr-cli::model-selector-set-query scoped-overlay "model")
    (dolist (width '(72 28))
      (multiple-value-bind (lines row column)
          (cadr-cli::render-tui-overlay-lines
           scoped-overlay width 0d0)
        (is (= 22 (length lines)))
        (is (= 5 row))
        (is (= 7 column))
        (is
         (string=
          (goal15-fixed-text-row
           "tab scope (all/scoped)" width)
          (cadr-tui:strip-terminal-sequences (nth 3 lines))))
        (is
         (string=
          (goal15-fixed-input-row "model" width)
          (cadr-tui:strip-terminal-sequences (nth row lines)))))
      (multiple-value-bind (lines row column)
          (cadr-cli::render-tui-overlay-lines
           unscoped-overlay width 0d0)
        (is (= 21 (length lines)))
        (is (= 4 row))
        (is (= 2 column))
        (is
         (string=
          (goal15-fixed-text-row
           "Only showing models from configured providers. Use /login to add providers."
           width)
          (cadr-tui:strip-terminal-sequences (nth 2 lines))))))))

(test goal15-model-scope-startup-copy-follows-baseline-gate-and-grammar
  ;; pi@53fa77ccd interactive-mode.ts:719-731 emits this only for a nonempty
  ;; scope when verbose startup is enabled or quiet startup is disabled.
  (let* ((manager
           (cadr-tui:make-keybindings-manager
            :definitions
            '(("app.model.cycleForward" . ("ctrl+p")))))
         (disabled-manager
           (cadr-tui:make-keybindings-manager
            :user-bindings
            '(("app.model.cycleForward" . nil))))
         (first
           (cadr-ai:make-model
            :id "faux-1" :provider :faux :api :faux))
         (second
           (cadr-ai:make-model
            :id "other-1" :provider :other :api :faux))
         (scope
           (list (list :model first :thinking nil)
                 (list :model second :thinking :high))))
    (is
     (string=
      "Model scope: faux-1, other-1:high (Ctrl+P to cycle)"
      (cadr-tui:strip-terminal-sequences
       (cadr-cli::model-scope-startup-line
        scope manager :verbose-p nil :quiet-startup-p nil))))
    (is
     (null
      (cadr-cli::model-scope-startup-line
       scope manager :verbose-p nil :quiet-startup-p t)))
    (is
     (stringp
      (cadr-cli::model-scope-startup-line
       scope manager :verbose-p t :quiet-startup-p t)))
    (is
     (null
      (cadr-cli::model-scope-startup-line
       nil manager :verbose-p t :quiet-startup-p nil)))
    (is
     (string=
      "Model scope: faux-1, other-1:high"
      (cadr-tui:strip-terminal-sequences
       (cadr-cli::model-scope-startup-line
        scope disabled-manager
        :verbose-p t :quiet-startup-p nil))))))

(test goal15-model-cycle-target-matches-baseline-wrap-and-missing-current
  ;; agent-session.ts:1601-1665 resolves the current entry, defaults a missing
  ;; current model to index zero, applies the direction, and wraps modulo the
  ;; complete scoped batch.
  (let* ((one
           (cadr-ai:make-model
            :id "one" :provider :faux :api :faux))
         (two
           (cadr-ai:make-model
            :id "two" :provider :faux :api :faux))
         (three
           (cadr-ai:make-model
            :id "three" :provider :faux :api :faux))
         (missing
           (cadr-ai:make-model
            :id "missing" :provider :faux :api :faux))
         (entries
           (list
            (list :model one :thinking nil)
            (list :model two :thinking :high)
            (list :model three :thinking :off))))
    (flet ((target (current direction)
             (getf
              (cadr-cli::model-cycle-target-entry
               entries current direction)
              :model)))
      (is (cadr-ai:models-equal-p two (target one :forward)))
      (is (cadr-ai:models-equal-p three (target one :backward)))
      (is (cadr-ai:models-equal-p one (target three :forward)))
      (is (cadr-ai:models-equal-p two (target missing :forward)))
      (is (cadr-ai:models-equal-p three (target missing :backward))))
    (is
     (null
      (cadr-cli::model-cycle-target-entry
       nil one :forward)))
    (is
     (null
      (cadr-cli::model-cycle-target-entry
       (list (first entries)) one :forward)))))

(test goal15-model-scope-hint-uses-key-and-description-styles
  ;; keybinding-hints.ts:17-31,42-47 styles the key independently from its
  ;; description and model-selector.ts:219-220 keeps the scope suffix muted.
  (let* ((one
           (cadr-ai:make-model
            :id "one" :name "One" :provider :faux :api :faux))
         (two
           (cadr-ai:make-model
            :id "two" :name "Two" :provider :other :api :faux))
         (keybindings
           (cadr-cli::make-models-selector-keybindings
            '(("tui.input.tab" . ("ctrl+t")))))
         (state
           (cadr-cli::make-model-selector-state
            :all-models (list one two)
            :scoped-models (list one two)
            :current-model one
            :keybindings keybindings))
         (line
           (nth 3
                (nth-value
                 0
                 (cadr-cli::render-model-selector state 80)))))
    (is
     (string=
      (goal15-fixed-text-row
       "ctrl+t scope (all/scoped)" 80)
      (cadr-tui:strip-terminal-sequences line)))
    (is
     (search
      (cadr-tui:theme-foreground :dim "ctrl+t") line))
    (is
     (search
      (cadr-tui:theme-foreground :muted " scope") line))
    (is
     (search
      (cadr-tui:theme-foreground :muted " (all/scoped)") line))))

(test goal15-visible-directory-copy-strips-only-non-root-trailing-separators
  ;; pi@53fa77ccd utils/paths.ts:81-85 canonicalizes display paths without a
  ;; trailing separator, while the filesystem trust key remains canonical.
  (is (string= "/" (cadr-cli::display-directory-name "/")))
  (is (string= "/tmp/project"
               (cadr-cli::display-directory-name "/tmp/project/")))
  (is (string= "/tmp/project"
               (cadr-cli::display-directory-name #P"/tmp/project/")))
  (is (string= "C:/"
               (cadr-cli::display-directory-name "C:/")))
  (is (string= (format nil "C:~C" #\\)
               (cadr-cli::display-directory-name
                (format nil "C:~C" #\\))))
  (is (string= "/tmp/project"
               (cadr-cli::format-cwd-for-footer
                "/tmp/project/" "/root")))
  (is (string= "~"
               (cadr-cli::format-cwd-for-footer
                "/root/" "/root"))))

(test goal15-trust-selector-copy-and-paths-match-baseline
  ;; pi@53fa77ccd trust-selector.ts:52-87 renders normalized paths and the
  ;; keybinding-derived cancel alternatives verbatim.
  (let ((lines
          (mapcar
           #'cadr-tui:strip-terminal-sequences
           (cadr-cli::render-trust-selector
            (cadr-cli::make-trust-selector-state
             :cwd "/tmp/project/" :project-trusted-p nil)
            80))))
    (is (find (goal15-fixed-text-row " /tmp/project" 80)
              lines :test #'string=))
    (is (find (goal15-fixed-text-row
               "   Trust parent folder (/tmp)" 80)
              lines :test #'string=))
    (is
     (find
      (goal15-fixed-text-row
       " ↑↓ navigate  enter save  escape/ctrl+c cancel" 80)
      lines :test #'string=)))
  (is
   (string=
    "trusted (/tmp/project)"
    (cadr-cli::trust-decision-description
     (cadr-cli::make-trust-selector-state
      :cwd "/tmp/project/"
      :saved-entry '(:path "/tmp/project/" :decision t)))))
  (is
   (string=
    "trusted (inherited from /tmp)"
    (cadr-cli::trust-decision-description
     (cadr-cli::make-trust-selector-state
      :cwd "/tmp/project/"
      :saved-entry '(:path "/tmp/" :decision t))))))

(test goal17-trust-inherited-description-wraps-as-baseline-text
  ;; pi@53fa77ccd trust-selector.ts renders the saved decision through Text,
  ;; so a narrow inherited path wraps instead of being truncated.
  (let* ((width 48)
         (lines
           (mapcar
            #'cadr-tui:strip-terminal-sequences
            (cadr-cli::render-trust-selector
             (cadr-cli::make-trust-selector-state
              :cwd "/tmp/cadr-render-diff-abcdefgh/cadr/workspace/"
              :saved-entry
              '(:path "/tmp/cadr-render-diff-abcdefgh/cadr/"
                :decision t)
              :project-trusted-p t)
             width)))
         (saved-index
           (position-if
            (lambda (line)
              (search "Saved decision:" line))
            lines))
         (current-index
           (position-if
            (lambda (line)
              (search "Current session:" line))
            lines)))
    (is (integerp saved-index))
    (is (integerp current-index))
    (when (and (integerp saved-index)
               (integerp current-index))
      (is (= (+ saved-index 2) current-index))
      (is
       (string=
        "Saved decision: trusted (inherited from"
        (string-trim '(#\Space)
                     (nth saved-index lines))))
      (is
       (string=
        "/tmp/cadr-render-diff-abcdefgh/cadr)"
        (string-trim '(#\Space)
                     (nth (1+ saved-index) lines))))
      (loop for index from saved-index below current-index
            do (is (= width
                      (cadr-tui:visible-width
                       (nth index lines))))))))

(test goal15-trust-help-styles-keys-and-descriptions-independently
  ;; trust-selector.ts:75-84 composes three key hints rather than dimming the
  ;; complete row as one string.
  (let* ((state
           (cadr-cli::make-trust-selector-state
            :cwd "/tmp/project/" :project-trusted-p nil))
         (lines
           (nth-value
            0 (cadr-cli::render-trust-selector state 80)))
         (line (nth (- (length lines) 3) lines)))
    (dolist (key '("↑↓" "enter" "escape/ctrl+c"))
      (is
       (search
        (cadr-tui:theme-foreground :dim key)
        line)))
    (dolist (description '(" navigate" " save" " cancel"))
      (is
       (search
        (cadr-tui:theme-foreground :muted description)
        line)))))

(test goal15-busy-status-and-queued-messages-use-baseline-text-padding
  ;; pi@53fa77ccd TruncatedText and Loader both inherit Text's paddingX=1.
  ;; The dequeue hint uses keyDisplayText, which capitalizes Alt+Up.
  (let* ((width 40)
         (state
           (cadr-cli::make-tui-state :model "faux")))
    (setf
     (cadr-cli::tui-state-steering-messages state)
     (list (cadr-ai:make-user-message :content "redirect"))
     (cadr-cli::tui-state-follow-up-messages state)
     (list (cadr-ai:make-user-message :content "later")))
    (let ((lines
            (cadr-cli::render-tui-pending-message-lines
             state width)))
      (is (string= "" (first lines)))
      (dolist (line (rest lines))
        (let ((plain
                (cadr-tui:strip-terminal-sequences line)))
          (is (= width (cadr-tui:visible-width plain)))
          (is (char= #\Space (char plain 0)))
          (is (char= #\Space (char plain (1- width))))))
      (is
       (search
        "↳ Alt+Up to edit all queued messages"
        (cadr-tui:strip-terminal-sequences
         (car (last lines))))))
    (let* ((lines
             (cadr-cli::render-tui-status-indicator
              "Working..." width :spinner-frame "x"))
           (plain
             (cadr-tui:strip-terminal-sequences
              (second lines))))
      (is (string= "" (first lines)))
      (is (= width (cadr-tui:visible-width plain)))
      (is (uiop:string-prefix-p " x Working..." plain))
      (is (char= #\Space (char plain (1- width)))))))

(test goal15-export-and-reload-share-baseline-status-replacement-channel
  ;; interactive-mode.ts:3266-3281,5471-5511 sends both commands through
  ;; showStatus, so adjacent statuses replace rather than accumulate.
  (with-test-directory (root)
    (let* ((sessions (merge-pathnames "sessions/" root))
           (cwd (merge-pathnames "project/" root))
           (_
             (ensure-directories-exist
              (merge-pathnames "anchor" cwd)))
           (session
             (cadr-agent:create-session
              :directory sessions :cwd cwd
              :id "goal15-status" :timestamp 0))
           (agent
             (cadr-agent:make-agent
              :provider :mock
              :model (cli-mock-model)
              :session session))
           (state
             (cadr-cli::make-tui-state :model "mock"))
           (output (make-string-output-stream))
           (status-function
             (lambda (text)
               (cadr-cli::add-tui-status state text))))
      (declare (ignore _))
      (is
       (cadr-cli::handle-session-command
        "/export" agent
        :directory sessions :cwd cwd :output output
        :status-function status-function))
      (is (string= "" (get-output-stream-string output)))
      (is (= 1 (length (cadr-cli::tui-state-entries state))))
      (is
       (uiop:string-prefix-p
        "Session exported to: cadr-session-"
        (cadr-cli::tui-entry-text
         (first (cadr-cli::tui-state-entries state)))))
      (funcall
       status-function
       "Reloaded keybindings, extensions, skills, prompts, themes, and context files")
      (is (= 1 (length (cadr-cli::tui-state-entries state))))
      (is
       (string=
        "Reloaded keybindings, extensions, skills, prompts, themes, and context files"
        (cadr-cli::tui-entry-text
         (first (cadr-cli::tui-state-entries state))))))))

(test goal15-project-trust-resource-detection-matches-the-fixed-baseline
  ;; trust-manager.ts:178-204 gates every project .pi resource and ancestor
  ;; .agents/skills, while excluding the user's own ~/.agents/skills.
  (with-test-directory (root)
    (loop
      for resource in
      '("settings.json" "extensions/" "skills/" "prompts/" "themes/"
        "SYSTEM.md" "APPEND_SYSTEM.md")
      for index from 0
      for project =
        (merge-pathnames (format nil "case-~D/project/" index) root)
      for target = (merge-pathnames
                    (concatenate 'string ".cadr/" resource)
                    project)
      do
         (if (char= #\/ (char resource (1- (length resource))))
             (ensure-directories-exist (merge-pathnames "anchor" target))
             (write-text target "fixture"))
         (is
          (cadr-cli::trust-requiring-project-resources-p
           project :home-directory (merge-pathnames "home/" root))))
    (let* ((home (merge-pathnames "home/" root))
           (project (merge-pathnames "workspace/project/child/" root))
           (ancestor-skills
             (merge-pathnames "workspace/.agents/skills/" root)))
      (ensure-directories-exist (merge-pathnames "anchor" project))
      (ensure-directories-exist (merge-pathnames "anchor" ancestor-skills))
      (is
       (cadr-cli::trust-requiring-project-resources-p
        project :home-directory home)))
    (let* ((home (merge-pathnames "user-home/" root))
           (project (merge-pathnames "projects/child/" home)))
      (ensure-directories-exist
       (merge-pathnames ".agents/skills/anchor" home))
      (ensure-directories-exist (merge-pathnames "anchor" project))
      (is
       (null
        (cadr-cli::trust-requiring-project-resources-p
         project :home-directory home))))))

(test goal15-untrusted-project-warning-copy-and-shape-match-the-fixed-baseline
  ;; interactive-mode.ts:3531-3549 renders a bare yellow Text row after the
  ;; transcript; it does not route through showWarning's "Warning:" prefix.
  (with-test-directory (root)
    (write-text (merge-pathnames ".cadr/SYSTEM.md" root) "fixture")
    (let* ((text
             (cadr-cli::project-trust-warning-text
              nil root :home-directory (merge-pathnames "home/" root)))
           (state (cadr-cli::make-tui-state :model "faux")))
      (is
       (string=
        "This project is not trusted. Project .cadr resources and packages are ignored. Use /trust to save a trust decision, then restart cadr."
        text))
      (cadr-cli::add-tui-project-trust-warning state text)
      (let* ((lines
               (cadr-cli::render-tui-entry
                (first (cadr-cli::tui-state-entries state)) 100))
             (plain
               (mapcar #'cadr-tui:strip-terminal-sequences lines)))
        (is (string= "" (first plain)))
        (is (uiop:string-prefix-p " This project is not trusted." (second plain)))
        (is (null (search "Warning:" (format nil "~{~A~^~%~}" plain))))))
    (is
     (null
      (cadr-cli::project-trust-warning-text
       t root :home-directory (merge-pathnames "home/" root))))))

(test goal15-fatal-summary-is-emitted-after-protected-terminal-teardown
  ;; interactive-mode.ts:3671-3692 stops the TUI before writing fatal output.
  (with-test-directory (directory)
    (let* ((visible (make-string-output-stream))
           (status
             (let ((*error-output* visible))
               (cadr-cli::call-with-fatal-condition-boundary
                (lambda ()
                  (unwind-protect
                       (error "goal15 fatal ordering sentinel")
                    (write-line "TERMINAL-RESTORED" visible)))
                :crash-directory directory
                :exit-function #'identity)))
           (output (get-output-stream-string visible))
           (restored (search "TERMINAL-RESTORED" output))
           (fatal (search "cadr exiting due to uncaught SIMPLE-ERROR" output)))
      (is (= 1 status))
      (is (not (null restored)))
      (is (not (null fatal)))
      (when (and restored fatal)
        (is (< restored fatal))))))

(test goal15-fatal-boundary-preserves-normal-multiple-values
  (is
   (equal
    '(alpha beta gamma)
    (multiple-value-list
     (cadr-cli::call-with-fatal-condition-boundary
      (lambda () (values 'alpha 'beta 'gamma))
      :exit-function #'identity)))))
