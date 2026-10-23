(in-package #:cadr-cli/tests)

(in-suite cadr-cli-suite)

(defun goal27-automatic-theme-state ()
  (cadr-cli::make-settings-selector-state
   :theme-names '("system" "dark" "light")
   :current-theme "dark"
   :options
   (list
    (cadr-cli::make-settings-option
     :id "theme" :label "Theme"
     :description "Color theme for the interface"
     :value "dark"
     :values '("system" "dark" "light")
     :submenu :theme))))

(defun goal27-automatic-theme-plain (state width)
  (mapcar #'cadr-tui:strip-terminal-sequences
          (cadr-cli::render-settings-selector state width)))

(test goal27-single-theme-list-orders-system-then-automatic
  ;; v1.4.0 settings-selector.ts singleModeThemeItems: system, then
  ;; "  automatic", then the remaining themes. themeItems marks the
  ;; current name with "✓ " and gives system its terminal-color description.
  (let ((state (goal27-automatic-theme-state)))
    (cadr-cli::settings-selector-handle-event
     state (cadr-tui:make-input-event :kind :enter))
    (is (eq :theme-single
            (cadr-cli::settings-selector-state-mode state)))
    (is (equal '("system" "/" "dark" "light")
               (mapcar #'cadr-cli::settings-option-value
                       (cadr-cli::settings-selector-submenu-options
                        state))))
    (is (equal '("  system" "  automatic" "✓ dark" "  light")
               (mapcar #'cadr-cli::settings-option-label
                       (cadr-cli::settings-selector-submenu-options
                        state))))
    (is (string=
         "Theme created from your terminal's colors"
         (cadr-cli::settings-option-description
          (first
           (cadr-cli::settings-selector-submenu-options state)))))
    (is (= 2
           (cadr-cli::settings-selector-state-submenu-selected state)))
    (let ((plain (goal27-automatic-theme-plain state 100)))
      (is (find "Select a theme, or choose automatic to follow terminal appearance."
                plain :test #'search))
      (is (find "    system     Theme created from your terminal's colors"
                plain :test #'search))
      (is (find "    automatic  Use separate themes for light and dark terminal appearance"
                plain :test #'search))
      (is (find "→ ✓ dark" plain :test #'search))
      (is (find "    light" plain :test #'search)))))

(test goal27-up-from-the-current-theme-stops-on-automatic-theme
  ;; overlays-secondary sends up, then enter, and waits for "Automatic Theme".
  ;; The next enter waits for "Light Theme". Escape returns to the light row;
  ;; down, then enter, waits for "Dark Theme".
  (let ((state (goal27-automatic-theme-state)))
    (cadr-cli::settings-selector-handle-event
     state (cadr-tui:make-input-event :kind :enter))
    (cadr-cli::settings-selector-handle-event
     state (cadr-tui:make-input-event :kind :up))
    (cadr-cli::settings-selector-handle-event
     state (cadr-tui:make-input-event :kind :enter))
    (is (eq :theme-automatic
            (cadr-cli::settings-selector-state-mode state)))
    (is (find "Automatic Theme"
              (goal27-automatic-theme-plain state 100)
              :test #'search))
    (is (string= "light-theme"
                 (cadr-cli::settings-option-id
                  (nth
                   (cadr-cli::settings-selector-state-submenu-selected
                    state)
                   (cadr-cli::settings-selector-submenu-options state)))))
    (cadr-cli::settings-selector-handle-event
     state (cadr-tui:make-input-event :kind :enter))
    (is (eq :theme-light
            (cadr-cli::settings-selector-state-mode state)))
    (is (find "Light Theme"
              (goal27-automatic-theme-plain state 48)
              :test #'search))
    (is (find "✓ dark"
              (mapcar #'cadr-cli::settings-option-label
                      (cadr-cli::settings-selector-submenu-options state))
              :test #'string=))
    (cadr-cli::settings-selector-handle-event
     state (cadr-tui:make-input-event :kind :escape))
    (is (eq :theme-automatic
            (cadr-cli::settings-selector-state-mode state)))
    (is (zerop
         (cadr-cli::settings-selector-state-submenu-selected state)))
    (cadr-cli::settings-selector-handle-event
     state (cadr-tui:make-input-event :kind :down))
    (cadr-cli::settings-selector-handle-event
     state (cadr-tui:make-input-event :kind :enter))
    (is (eq :theme-dark
            (cadr-cli::settings-selector-state-mode state)))
    (is (find "Dark Theme"
              (goal27-automatic-theme-plain state 100)
              :test #'search))
    (is (not (eq :main
                 (cadr-cli::settings-selector-state-mode state))))))

(test goal27-tall-theme-page-keeps-its-top-border-on-a-short-terminal
  ;; v1.4.0 chat-viewport.ts + v-stack.ts: one transcript row stays,
  ;; the dock shrinks, and the editor child is sliced from the top.
  ;; A 20-row terminal therefore drops the selector's bottom border
  ;; and keeps the footer.
  (let* ((editor (loop for index from 1 to 18
                       collect (format nil "E~D" index)))
         (footer '("cwd" "status"))
         (fitted
           (cadr-tui::fit-chat-dock-to-rows
            (list (list nil 0)
                  (list nil 0)
                  (list nil 0)
                  (list editor 3)
                  (list nil 0)
                  (list footer 0))
            20))
         (untouched
           (cadr-tui::fit-chat-dock-to-rows
            (list (list nil 0)
                  (list nil 0)
                  (list nil 0)
                  (list editor 3)
                  (list nil 0)
                  (list footer 0))
            32)))
    (is (equal (subseq editor 0 17) (fourth fitted)))
    (is (equal footer (sixth fitted)))
    (is (equal editor (fourth untouched)))
    (is (equal footer (sixth untouched)))))
