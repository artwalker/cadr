(in-package #:cadr-cli/tests)

(in-suite cadr-cli-suite)

;; v1.4.0 packages/coding-agent/schemas/{keybindings,settings,theme}.schema.json
;; Digests are the git blobs at 4a080252. Editor strings are
;; config-schemas.test.ts. models.schema.json stays out.

(defparameter +goal27-config-schema-digests+
  '(("keybindings"
     "46d494b2493cd9fcf957d352aac653fe6f04121254f34033a5664e7c8f9928aa"
     "https://pi.dev/schemas/keybindings.schema.json")
    ("settings"
     "d4b19b0e492cb887a23c50034f00213c476048956fa92c5cce2f1536ef50b9b0"
     "https://pi.dev/schemas/settings.schema.json")
    ("theme"
     "f526a690b63c6303296f683c9df6077ddc290ee9acb1bc27eedef169c0caad59"
     "https://pi.dev/schemas/theme.schema.json")))

(defun goal27-config-schema-path (name)
  (merge-pathnames
   (format nil "schemas/~A.schema.json" name)
   (asdf:system-source-directory "cadr-cli")))

(defun goal27-config-schema (name)
  (cadr-ai::parse-json
   (uiop:read-file-string
    (goal27-config-schema-path name)
    :external-format :utf-8)))

(defun goal27-config-schema-sha256 (path)
  (subseq
   (string-trim
    '(#\Newline #\Space)
    (uiop:run-program
     (list "sha256sum" (namestring path))
     :output :string))
   0 64))

(defun goal27-schema-text (condition)
  (princ-to-string condition))

(defun goal27-theme-other-errors (label &rest lines)
  ;; theme-schema.ts writes the title, then "\n\nOther errors:\n".
  (format nil
          "Invalid theme \"~A\":~%~%~%Other errors:~%~{~A~^~%~}"
          label
          lines))

(defun goal27-copy-theme (mutate)
  (let ((object
          (cadr-ai::copy-json-value
           (cadr-ai::parse-json
            (uiop:read-file-string
             (merge-pathnames
              "test/fixtures/v140-theme/dark.json"
              (asdf:system-source-directory "cadr-cli"))
             :external-format :utf-8)))))
    (funcall mutate object)
    object))

(test goal27-config-schemas-match-v140-blobs
  (dolist (entry +goal27-config-schema-digests+)
    (let* ((name (first entry))
           (schema (goal27-config-schema name)))
      (is (string=
           (second entry)
           (goal27-config-schema-sha256
            (goal27-config-schema-path name)))
          name)
      (is (string= (third entry) (gethash "$id" schema)) name)
      (is (string=
           "https://json-schema.org/draft/2020-12/schema"
           (gethash "$schema" schema))
          name))))

(test goal27-config-schemas-keep-editor-guidance
  (let* ((theme (goal27-config-schema "theme"))
         (colors (gethash "colors" (gethash "properties" theme)))
         (accent (gethash "accent" (gethash "properties" colors)))
         (color-value (gethash "ColorValue" (gethash "$defs" theme)))
         (settings (goal27-config-schema "settings"))
         (settings-properties (gethash "properties" settings)))
    (is (string= "Pi Coding Agent Theme" (gethash "title" theme)))
    (is (string= "Theme schema for Pi coding agent"
                 (gethash "description" theme)))
    (is (search "use compatible fallbacks"
                (gethash "description" colors)))
    (is (search "falls back to muted"
                (gethash
                 "description"
                 (gethash "scrollbarTrack"
                          (gethash "properties" colors)))))
    (is (string=
         "Primary accent color (logo, selected items, cursor)"
         (gethash "description" accent)))
    (is (search
         "Hex color"
         (gethash
          "description"
          (aref (gethash "anyOf" color-value) 0))))
    (is (search
         "defaults derived from userMessageBg"
         (gethash
          "description"
          (gethash "export" (gethash "properties" theme)))))
    (is (search
         "hide all startup output"
         (gethash
          "description"
          (gethash "quietStartup" settings-properties))))
    (is (search
         "+name and -name"
         (gethash
          "description"
          (gethash "defaultTools" settings-properties))))
    (is (search
         "1 to 100"
         (gethash
          "description"
          (gethash "fullscreenWheelScrollLines"
                   settings-properties))))
    (is (string=
         "Legacy setting migrated to steeringMode."
         (gethash
          "description"
          (gethash "queueMode" settings-properties))))
    (is (search
         "provider.maxRetryDelayMs"
         (gethash
          "description"
          (gethash
           "maxDelayMs"
           (gethash
            "properties"
            (gethash "retry" settings-properties))))))))

(test goal27-keybinding-schema-accepts-the-v140-chord-list
  (let* ((schema (goal27-config-schema "keybindings"))
         (pattern
           (gethash
            "pattern"
            (aref
             (gethash
              "anyOf"
              (gethash
               "KeybindingValue"
               (gethash "$defs" schema)))
             0)))
         (scanner (cl-ppcre:create-scanner pattern)))
    (dolist (binding
             '("a" "9" "pageUp" "+" "ctrl+shift+x"
               "alt+ctrl+?" "ctrl+shift+alt+super+f12"))
      (is (cl-ppcre:scan scanner binding) binding))
    (dolist (binding
             '("" "Ctrl+x" "control+x" "ctrl+not-a-key"
               "ctrl+ctrl+x" "ctrl+shift+alt+super+ctrl+x"))
      (is (null (cl-ppcre:scan scanner binding)) binding))))

(test goal27-keybindings-file-skips-schema-and-invalid-chords
  (with-test-directory (root)
    (let ((agent (merge-pathnames "agent/" root)))
      (ensure-directories-exist agent)
      (write-text
       (merge-pathnames "keybindings.json" agent)
       "{\"$schema\":\"https://pi.dev/schemas/keybindings.schema.json\",\"app.session.new\":\"ctrl+n\",\"extension.action\":[\"alt+x\"],\"extension.invalid\":\"ctrl+not-a-key\"}")
      (let ((bindings
              (cadr-cli::keybindings-file-bindings agent)))
        (is (null (assoc "$schema" bindings :test #'string=)))
        (is (null
             (assoc "extension.invalid" bindings :test #'string=)))
        (is (equal
             '("ctrl+n")
             (cdr
              (assoc "app.session.new" bindings :test #'string=))))
        (is (equal
             '("alt+x")
             (cdr
              (assoc "extension.action" bindings :test #'string=)))))
      (write-text
       (merge-pathnames "keybindings.json" agent)
       "{\"app.session.new\":42}")
      (is (null
           (assoc
            "app.session.new"
            (cadr-cli::keybindings-file-bindings agent)
            :test #'string=))))))

(test goal27-settings-file-keeps-schema-and-unknown-keys
  (with-test-directory (root)
    (write-text
     (merge-pathnames "settings.json" root)
     "{\"$schema\":\"https://pi.dev/schemas/settings.schema.json\",\"theme\":\"light\",\"extensionSetting\":{\"enabled\":true}}")
    (let* ((manager
             (cadr-cli::make-settings-manager
              :global-path
              (merge-pathnames "settings.json" root)
              :project-path
              (merge-pathnames
               "missing/settings.json" root)))
           (global
             (cadr-cli::settings-manager-global manager))
           (extension (gethash "extensionSetting" global)))
      (is (string= "light"
                   (cadr-cli::settings-value manager "theme")))
      (is (string=
           "https://pi.dev/schemas/settings.schema.json"
           (gethash "$schema" global)))
      (is (eq t (gethash "enabled" extension))))))

(test goal27-theme-schema-accepts-schema-and-rejects-malformed
  (let* ((valid
           (goal27-copy-theme
            (lambda (object)
              (setf (gethash "name" object) "custom"
                    (gethash "$schema" object)
                    "https://pi.dev/schemas/theme.schema.json"))))
         (overrides
           (cadr-cli::theme-object-overrides valid)))
    (is (stringp (cdr (assoc :accent overrides)))))
  (let ((condition
          (nth-value
           1
           (ignore-errors
            (cadr-cli::theme-object-overrides
             (goal27-copy-theme
              (lambda (object)
                (setf (gethash "name" object) "invalid/name"))))))))
    (is (search
         "theme names cannot contain"
         (goal27-schema-text condition)))
    (is (null
         (search
          "Invalid theme \""
          (goal27-schema-text condition)))))
  (let* ((without-track
           (goal27-copy-theme
            (lambda (object)
              (remhash "scrollbarTrack"
                       (gethash "colors" object)))))
         (overrides
           (cadr-cli::theme-object-overrides
            without-track)))
    (is (string=
         (cdr (assoc :muted overrides))
         (cdr (assoc :scrollbar-track overrides)))))
  ;; scrollbar-theme.test.ts: omitted scrollbarThumb matches text.
  ;; dark.json text is okhsl(234 3% 89%) -> #dee0e1 (222 224 225).
  ;; selectedBg is okhsl(233 41% 24%) -> #213b49 (33 59 73).
  (let* ((without-thumb
           (goal27-copy-theme
            (lambda (object)
              (remhash "scrollbarThumb"
                       (gethash "colors" object)))))
         (overrides
           (cadr-cli::theme-object-overrides
            without-thumb)))
    (is (string= "#dee0e1"
                 (cdr (assoc :text overrides))))
    (is (string= "#dee0e1"
                 (cdr (assoc :scrollbar-thumb overrides))))
    (is (string= "#213b49"
                 (cdr (assoc :selected-bg overrides)))))
  (let ((overrides
          (cadr-cli::theme-object-overrides
           (goal27-copy-theme
            (lambda (object)
              (setf (gethash "scrollbarThumb"
                             (gethash "colors" object))
                    "#123456"))))))
    (is (string= "#123456"
                 (cdr (assoc :scrollbar-thumb overrides)))))
  (let ((condition
          (nth-value
           1
           (ignore-errors
            (cadr-cli::theme-object-overrides
             (goal27-copy-theme
              (lambda (object)
                (setf (gethash "colors" object)
                      (cadr-ai::json-object)))))))))
    (is (search
         "Invalid theme \"dark\":"
         (goal27-schema-text condition)))
    (is (search
         "Missing required color tokens"
         (goal27-schema-text condition)))
    (is (search "  - accent" (goal27-schema-text condition)))
    (dolist (token
             '("scrollbarTrack" "scrollbarThumb"
               "searchMatchBg" "searchMatchText"
               "thinkingMax"))
      (is (null
           (search
            (format nil "  - ~A" token)
            (goal27-schema-text condition)))
          token)))
  (dolist (case
           (list
            (list
             (lambda (object)
               (setf (gethash "unexpected" object) t))
             (goal27-theme-other-errors
              "dark"
              "  - /unexpected: schema is false"
              "  - /: must not have additional properties"))
            (list
             (lambda (object)
               (setf (gethash
                      "scrollbarThmb"
                      (gethash "colors" object))
                     ""))
             (goal27-theme-other-errors
              "dark"
              "  - /colors/scrollbarThmb: schema is false"
              "  - /colors: must not have additional properties"))
            (list
             (lambda (object)
               (setf (gethash "export" object)
                     (cadr-ai::json-object "unexpected" "")))
             (goal27-theme-other-errors
              "dark"
              "  - /export/unexpected: schema is false"
              "  - /export: must not have additional properties"))))
    (let* ((mutate (first case))
           (expected (second case))
           (condition
             (nth-value
              1
              (ignore-errors
               (cadr-cli::theme-object-overrides
                (goal27-copy-theme mutate))))))
      (is (string= expected (goal27-schema-text condition))))))

(test goal27-theme-load-drops-invalid-documents
  ;; v1.4.0 resource-loader-theme.test.ts: additional properties stay
  ;; out of the theme list. The warning is validateThemeJson's text,
  ;; and the label is the file path.
  (with-test-directory (root)
    (let* ((path (merge-pathnames "bad-theme.json" root))
           (object
             (goal27-copy-theme
              (lambda (theme)
                (setf (gethash "name" theme) "bad-theme"
                      (gethash "unsupported" theme) t)))))
      (write-json path object)
      (let ((label (namestring (truename path))))
        (multiple-value-bind (themes diagnostics)
            (cadr-cli::load-themes-at-paths (list path))
          (is (null themes))
          (is (= 1 (length diagnostics)))
          (is (eq :warning
                  (cadr-agent::resource-diagnostic-type
                   (first diagnostics))))
          (is (string=
               label
               (cadr-agent::resource-diagnostic-path
                (first diagnostics))))
          (let ((message
                  (cadr-agent::resource-diagnostic-message
                   (first diagnostics))))
            (is (string=
                 (goal27-theme-other-errors
                  label
                  "  - /unsupported: schema is false"
                  "  - /: must not have additional properties")
                 message)))))
      (remhash "unsupported" object)
      (write-json path object)
      (multiple-value-bind (themes diagnostics)
          (cadr-cli::load-themes-at-paths (list path))
        (is (null diagnostics))
        (is (string=
             "bad-theme"
             (getf (first themes) :name))))
      (setf (gethash "unsupported" object) t)
      (write-json path object)
      (multiple-value-bind (themes diagnostics)
          (cadr-cli::load-themes-at-paths (list path))
        (is (null themes))
        (is (= 1 (length diagnostics))))
      (setf (gethash "colors" object) (cadr-ai::json-object))
      (remhash "unsupported" object)
      (write-json path object)
      (multiple-value-bind (themes diagnostics)
          (cadr-cli::load-themes-at-paths (list path))
        (is (null themes))
        (let ((message
                (cadr-agent::resource-diagnostic-message
                 (first diagnostics))))
          (is (search "Missing required color tokens" message))
          (dolist (token
                   '("scrollbarTrack" "scrollbarThumb"
                     "searchMatchBg" "searchMatchText"
                     "thinkingMax"))
            (is (null
                 (search
                  (format nil "  - ~A" token)
                  message))
                token)))))
    (let* ((path (merge-pathnames "applied.json" root))
           (previous (cadr-tui:current-theme))
           (object
             (goal27-copy-theme
              (lambda (theme)
                (setf (gethash "name" theme) "bad-theme"
                      (gethash "unsupported" theme) t))))
           (summary
             (list :name "bad-theme" :path path :object object))
           (label (namestring path)))
      (unwind-protect
           (progn
             (is (null
                  (cadr-cli::apply-tui-theme-summary
                   summary
                   :keep-current-on-error-p t
                   :capabilities
                   (cadr-tui:make-terminal-capabilities))))
             (let ((condition
                     (nth-value
                      1
                      (ignore-errors
                       (cadr-cli::apply-tui-theme-summary
                        summary
                        :capabilities
                        (cadr-tui:make-terminal-capabilities))))))
               (is (string=
                    (goal27-theme-other-errors
                     label
                     "  - /unsupported: schema is false"
                     "  - /: must not have additional properties")
                    (goal27-schema-text condition)))))
        (cadr-tui:set-current-theme previous)))))
