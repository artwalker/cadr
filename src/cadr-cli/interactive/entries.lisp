(in-package #:cadr-cli)

(defun set-tui-keyed-lines
    (entries key lines)
  (if lines
      (acons
       key (copy-list lines)
       (remove key entries
               :key #'car
               :test #'string=))
      (remove key entries
              :key #'car
              :test #'string=)))

(defun set-tui-widget
    (state key lines placement)
  (ecase placement
    (:above-editor
     (setf
      (tui-state-widgets-above state)
      (set-tui-keyed-lines
       (tui-state-widgets-above state)
       key lines)))
    (:below-editor
     (setf
      (tui-state-widgets-below state)
      (set-tui-keyed-lines
       (tui-state-widgets-below state)
       key lines))))
  state)

(defun render-tui-widgets
    (entries width &key spacer-when-empty-p leading-spacer-p)
  (if
      (null entries)
      (and spacer-when-empty-p (list ""))
      (nconc
       (and leading-spacer-p (list ""))
       (loop for entry in
             (sort (copy-list entries)
                   #'string< :key #'car)
             append
             (loop for line in (cdr entry)
                   append
                   (cadr-tui:wrap-text line width))))))

(defun replace-tui-entries (state entries)
  (dolist (entry (tui-state-entries state))
    (when (tui-entry-custom-component entry)
      (ignore-errors
        (cadr-tui:component-dispose
         (tui-entry-custom-component entry)))))
  (let ((tail (last entries)))
    (setf
     (tui-state-entries state) entries
     (tui-state-entries-tail state) tail
     (tui-state-entries-tail-head state) entries))
  state)

(defun append-tui-entry (state entry)
  (let* ((entries (tui-state-entries state))
         (tail (tui-state-entries-tail state))
         (cell (list entry)))
    (cond
      ((null entries)
       (setf
        (tui-state-entries state) cell
        (tui-state-entries-tail state) cell
        (tui-state-entries-tail-head state) cell))
      ((and tail
            (eq entries
                (tui-state-entries-tail-head state))
            (null (cdr tail)))
       (setf
        (cdr tail) cell
        (tui-state-entries-tail state) cell))
      (t
       ;; Internal fixtures historically SETF ENTRIES directly. Repair that
       ;; boundary once; production replacements use REPLACE-TUI-ENTRIES.
       (let ((recovered-tail (last entries)))
         (setf
          (cdr recovered-tail) cell
          (tui-state-entries-tail state) cell
          (tui-state-entries-tail-head state)
          entries)))))
  entry)

(defun invalidate-tui-entry-render-cache (entry)
  (setf
   (tui-entry-render-cache-valid-p entry) nil
   (tui-entry-render-cache-width entry) nil
   (tui-entry-render-cache-theme entry) nil
   (tui-entry-render-cache-extension-snapshot entry)
   nil
   (tui-entry-render-cache-mermaid-mode entry) nil
   (tui-entry-render-cache-code-block-indent entry) nil
   (tui-entry-render-cache-lines entry) nil)
  entry)

(defun add-tui-message-entry (state type text)
  (let ((trimmed
          (string-trim
           '(#\Space #\Tab #\Newline #\Return)
           (or text ""))))
    (when (plusp (length trimmed))
      (append-tui-entry
       state
       (make-tui-entry
        :type type
        :text trimmed))))
  state)

(defun add-tui-status (state text)
  (let ((trimmed
          (string-trim
           '(#\Space #\Tab #\Newline #\Return)
           (or text ""))))
    (when (plusp (length trimmed))
      (let ((last-entry
              (and (tui-state-entries state)
                   (car (tui-state-entries-tail state)))))
        (if (and last-entry
                 (eq (tui-entry-type last-entry) :status))
            (progn
              (setf (tui-entry-text last-entry) trimmed)
              (invalidate-tui-entry-render-cache last-entry))
            (append-tui-entry
             state
             (make-tui-entry
              :type :status
              :text trimmed))))))
  state)

(defun add-tui-notice (state text)
  ;; NOTICE carries arbitrary frontend output.  It uses the same visual shape
  ;; as baseline status text, but must not coalesce adjacent lines.
  (add-tui-message-entry state :notice text))

(defun add-cache-miss-notice (state miss)
  "Pi addCacheMissNotice: warning-styled transcript notice (not persisted)."
  (when (and miss (cache-miss-notice-significant-p miss))
    (add-tui-notice
     state
     (cadr-tui:theme-foreground
      :warning
      (format-cache-miss-notice-text miss)
      :enabled-p t)))
  state)

(defun maybe-show-cache-miss-notice
    (state message
     &key show-p session-entries model-price-function)
  "Pi maybeShowCacheMissNotice on assistant message-end."
  (when
      (and
       show-p
       (typep message 'cadr-ai:assistant-message)
       (not
        (member
         (cadr-ai:assistant-message-stop-reason message)
         '(:aborted :error))))
    (add-cache-miss-notice
     state
     (detect-cache-miss-from-entries
      (or session-entries '())
      message
      :model-price-function model-price-function)))
  state)

(defstruct (compaction-cost-notice
            (:constructor make-compaction-cost-notice))
  "Pi RenderSessionItem compaction_cost: derived billing notice, not persisted."
  (kind :compaction)
  usage)

(defun compaction-cost-notice-token-count (usage)
  (+ (cadr-ai:usage-input usage)
     (cadr-ai:usage-output usage)
     (cadr-ai:usage-cache-read usage)
     (cadr-ai:usage-cache-write usage)))

(defun format-compaction-cost-notice-text (kind usage)
  "Pi addCompactionCostNotice label + formatTokens + optional ~~$ cost."
  (let* ((tokens (compaction-cost-notice-token-count usage))
         (total
           (cadr-ai:cost-total
            (cadr-ai:usage-cost usage)))
         (cost-suffix
           (if (>= total 0.01d0)
               (format nil " (~~$~,2F)" total)
               ""))
         (label
           (if (eq kind :branch-summary)
               "Branch summary"
               "Compaction")))
    (format
     nil
     "~A: ~A tokens billed~A"
     label
     (cadr-tui::format-footer-tokens tokens)
     cost-suffix)))

(defun add-compaction-cost-notice
    (state kind usage &key show-p)
  "Pi addCompactionCostNotice: warning notice when showCacheMissNotices is on."
  (when (and show-p usage)
    (add-tui-notice
     state
     (cadr-tui:theme-foreground
      :warning
      (format-compaction-cost-notice-text kind usage)
      :enabled-p t)))
  state)

(defun add-tui-error (state text)
  (add-tui-message-entry state :error text))

(defun add-tui-warning (state text)
  (add-tui-message-entry state :warning text))
(defun add-tui-project-trust-warning (state text)
  (add-tui-message-entry state :project-trust-warning text))

(defun add-tui-success (state text)
  (add-tui-message-entry state :success text))

(defun add-tui-debug-written (state path)
  ;; Baseline /debug confirmation: accent check line + muted path block.
  (append-tui-entry
   state
   (make-tui-entry
    :type :debug-written
    :text path))
  state)

(defun add-tui-rich-command (state title markdown)
  (append-tui-entry
   state
   (make-tui-entry
    :type :command-markdown
    :label title
    :text markdown))
  state)

(defun add-tui-version-update-notification
    (state version &optional note)
  (append-tui-entry
   state
   (make-tui-entry
    :type :version-update
    :text version
    :label
    (let ((trimmed
            (string-trim
             '(#\Space #\Tab #\Newline #\Return)
             (or note ""))))
      (and (plusp (length trimmed)) trimmed))))
  state)

(defun add-tui-package-update-notification
    (state packages)
  (append-tui-entry
   state
   (make-tui-entry
    :type :package-update
    :custom-options
    (list :packages (copy-list packages))))
  state)

(defun terminal-hyperlink (url label)
  (format nil "~C]8;;~A~C~A~C]8;;~C"
          #\Escape url (code-char 7) label
          #\Escape (code-char 7)))

(defun render-auth-url-lines (url width)
  (let* ((linked
           (cadr-tui:theme-foreground
            :accent
            (terminal-hyperlink url url)
            :enabled-p t))
         (hint
           (cadr-tui:theme-foreground
            :dim
            (terminal-hyperlink
             url "Ctrl+click to open")
            :enabled-p t)))
    (append
     (cadr-tui:wrap-text linked width)
     (list hint))))

(defun add-tui-auth-url (state url)
  (append-tui-entry
   state
   (make-tui-entry
    :type :auth-url
    :text url))
  state)

(defun startup-resource-names (resources accessor)
  (mapcar accessor resources))

(defun startup-extension-entries (extension-manager)
  "Loaded, non-hidden extension bundles as startup display items
(:path/:scope), mirroring the baseline's getExtensions() filter."
  (when extension-manager
    (let ((snapshot
           (cadr-agent::extension-host-current-snapshot
            (cli-extension-manager-host extension-manager))))
      (loop for bundle
            in (and
                snapshot
                (cadr-agent::extension-snapshot-bundles snapshot))
            unless (cadr-agent::extension-bundle-hidden-p bundle)
            collect
            (list
             :path (cadr-agent::extension-bundle-path bundle)
             :scope (cadr-agent::extension-bundle-scope bundle))))))

(defun startup-locale< (a b)
  "Approximate the baseline's JS localeCompare for ASCII labels: letters
order case-insensitively and exact-fold ties put the lowercase form
first (\"a\".localeCompare(\"A\") < 0)."
  (let ((folded-a (string-downcase a))
        (folded-b (string-downcase b)))
    (cond
      ((string< folded-a folded-b) t)
      ((string> folded-a folded-b) nil)
      (t (string> a b)))))

(defun startup-home-abbreviated (path)
  "Baseline formatDisplayPath: replace the $HOME prefix with ~."
  (let ((home (or (uiop:getenv "HOME") (uiop:getenv "USERPROFILE"))))
    (if (and
         home
         (plusp (length home))
         (uiop:string-prefix-p home path))
        (concatenate 'string "~" (subseq path (length home)))
        path)))

(defun startup-cwd-relative (path cwd)
  "Baseline formatContextPath: cwd-relative when the path is inside the
cwd, otherwise the home-abbreviated absolute path."
  (let* ((directory
          (namestring
           (uiop:ensure-directory-pathname (or cwd ""))))
         (relative
          (and
          (plusp (length directory))
          (uiop:string-prefix-p directory path)
          (subseq path (length directory)))))
    (if (and relative (plusp (length relative)))
        relative
        (startup-home-abbreviated path))))

(defun startup-path-scope (path agent-directory cwd)
  "Baseline scope groups: agent-directory resources are user scope,
cwd resources are project scope, everything else is path scope."
  (let ((agent
         (and
          agent-directory
          (namestring
           (uiop:ensure-directory-pathname agent-directory))))
        (project
         (and
          cwd
          (namestring (uiop:ensure-directory-pathname cwd)))))
    (cond
      ((and agent (uiop:string-prefix-p agent path)) "user")
      ((and project (uiop:string-prefix-p project path)) "project")
      (t "path"))))

(defun startup-scope-grouped-lines (items line-function)
  "Render baseline formatScopeGroups: project, user, then path groups,
each introduced by an accent scope label, with items sorted by path."
  (let ((lines nil))
    (dolist (scope '("project" "user" "path"))
      (let ((group
             (remove-if-not
              (lambda (item)
                (string= (getf item :scope) scope))
              items)))
        (when group
          (push
           (cadr-tui:theme-foreground
            :accent (format nil "  ~A" scope) :enabled-p t)
           lines)
          (dolist (item
                   (sort
                    (copy-list group)
                    #'startup-locale<
                    :key (lambda (item) (getf item :path))))
            (push (funcall line-function item) lines)))))
    (nreverse lines)))

(defun startup-compact-section (title labels)
  "One baseline addLoadedSection collapsed body: mdHeading header plus a
dim two-space comma list; the caller sorts or preserves insertion order
per the baseline rule for that section."
  (list
   (cadr-tui:theme-foreground
    :md-heading (format nil "[~A]" title) :enabled-p t)
   (cadr-tui:theme-foreground
    :dim (format nil "  ~{~A~^, ~}" labels) :enabled-p t)))

(defun startup-format-path-with-source (path agent-directory cwd)
  "Baseline formatPathWithSource for local sources: a muted scope label
followed by the home-abbreviated path."
  (format
   nil "~A ~A"
   (startup-path-scope path agent-directory cwd)
   (startup-home-abbreviated path)))

(defun startup-conflict-lines
    (title collisions diagnostics agent-directory cwd)
  "Baseline [Skill conflicts]/[Prompt conflicts] block: warning header,
then collision groups (success check winner, warning cross skipped
loser), then the remaining diagnostics colored by severity."
  (when (or collisions diagnostics)
    (let ((lines
           (list
            (cadr-tui:theme-foreground
             :warning (format nil "[~A]" title) :enabled-p t))))
      (dolist (collision collisions)
        (push
         (cadr-tui:theme-foreground
          :warning
          (format nil "  \"~A\" collision:" (getf collision :name))
          :enabled-p t)
         lines)
        (push
         (cadr-tui:theme-foreground
          :dim
          (format
           nil "    ~A ~A"
           (cadr-tui:theme-foreground :success "✓" :enabled-p t)
           (startup-format-path-with-source
            (getf collision :winner-path) agent-directory cwd))
          :enabled-p t)
         lines)
        (push
         (cadr-tui:theme-foreground
          :dim
          (format
           nil "    ~A ~A (skipped)"
           (cadr-tui:theme-foreground :warning "✗" :enabled-p t)
           (startup-format-path-with-source
            (getf collision :loser-path) agent-directory cwd))
          :enabled-p t)
         lines))
      (dolist (diagnostic diagnostics)
        (let ((color
               (if (eq (cadr-agent::resource-diagnostic-type diagnostic)
                       :error)
                   :error
                   :warning)))
          ;; Load warnings carry no sourceInfo in the baseline, so they
          ;; render as the plain home-abbreviated path with no scope
          ;; label (formatPathWithSource falls back to
          ;; formatDisplayPath); only collision winner/loser lines get
          ;; the scope label.
          (push
           (cadr-tui:theme-foreground
            color
            (format
             nil "  ~A"
             (startup-home-abbreviated
              (cadr-agent::resource-diagnostic-path diagnostic)))
            :enabled-p t)
           lines)
          (push
           (cadr-tui:theme-foreground
            color
            (format
             nil "    ~A"
             (cadr-agent::resource-diagnostic-message diagnostic))
            :enabled-p t)
           lines)))
      (nreverse lines))))

(defun startup-extension-display-path (path)
  "Baseline formatExtensionDisplayPath: home-abbreviated, with the entry
file suffix stripped (/extension.lisp is cadr's index.ts analogue)."
  (let ((displayed (startup-home-abbreviated path)))
    (if (uiop:string-suffix-p displayed "/extension.lisp")
        (subseq
         displayed
         0
         (- (length displayed) (length "/extension.lisp")))
        displayed)))

(defun startup-extension-compact-labels (paths)
  "Baseline getCompactExtensionLabels for local extensions: the minimal
unique path-suffix per entry, with the entry filename dropped for
directory-style extensions."
  (let* ((segmented
          (mapcar
           (lambda (path)
             (let ((segments
                    (remove
                     "~"
                     (remove
                      ""
                      (uiop:split-string
                       (startup-home-abbreviated path)
                       :separator "/")
                      :test #'string=)
                     :test #'string=)))
               (when (and
                      (> (length segments) 1)
                      (string= (car (last segments)) "extension.lisp"))
                 (setf segments (butlast segments)))
               segments))
           paths)))
    (loop for segments in segmented
          for index from 0
          collect
          (or
           (loop for count from 1 to (length segments)
                 for candidate =
                 (format
                  nil "~{~A~^/~}"
                  (last segments count))
                 when (loop for other in segmented
                            for other-index from 0
                            always
                            (or
                             (= other-index index)
                             (string/=
                              candidate
                              (format
                               nil "~{~A~^/~}"
                               (last other count)))))
                 return candidate)
           (format nil "~{~A~^/~}" segments)))))

(defparameter +startup-expanded-help+
  '(("escape to interrupt" "escape" "to interrupt")
    ("ctrl+c to clear" "ctrl+c" "to clear")
    ("ctrl+c twice to exit" "ctrl+c twice" "to exit")
    ("ctrl+d to exit (empty)" "ctrl+d" "to exit (empty)")
    ("ctrl+z to suspend" "ctrl+z" "to suspend")
    ("ctrl+k to delete to end" "ctrl+k" "to delete to end")
    (:cycle-models)
    ("ctrl+o to expand tools" "ctrl+o" "to expand tools")
    ("/ for commands" "/" "for commands")
    ("! to run bash" "!" "to run bash")))

(defun startup-expanded-help-lines (cycle-help-line)
  (loop for row in +startup-expanded-help+
        for text = (if (eq (first row) :cycle-models)
                       cycle-help-line
                       (first row))
        when text collect text))

(defun make-tui-startup-lines
    (resources
     &key
       (version (cadr-ai::cadr-version))
       extensions
       extension-issues)
  (labels
      ((namestring-of (path)
         (if (pathnamep path) (namestring path) path))
       (section-lines (title body-lines &key leading-blank-p)
         (append
          (and leading-blank-p (list ""))
          (list
           (cadr-tui:theme-foreground
            :md-heading (format nil "[~A]" title) :enabled-p t))
          body-lines
          (list "")))
       (compact-body (labels)
         (list
          (cadr-tui:theme-foreground
           :dim (format nil "  ~{~A~^, ~}" labels) :enabled-p t)))
       (sections (expanded-p)
         (let ((agent-directory
                (resource-snapshot-agent-directory resources))
               (cwd
                (and
                 (resource-snapshot-cwd resources)
                 (namestring-of (resource-snapshot-cwd resources)))))
           (labels
               ((scope-of (path)
                  (startup-path-scope path agent-directory cwd))
                (group-items (paths)
                  (mapcar
                   (lambda (path)
                     (list :path path :scope (scope-of path)))
                   paths)))
             (let*
                 ((context-files
                   (append
                    (and
                     (resource-snapshot-system-prompt-path resources)
                     (list
                      (namestring-of
                       (resource-snapshot-system-prompt-path resources))))
                    (and
                     (resource-snapshot-append-system-prompt-path resources)
                     (list
                      (namestring-of
                       (resource-snapshot-append-system-prompt-path
                        resources))))
                    (mapcar
                     #'namestring-of
                     (resource-snapshot-context-files resources))))
                  (skills (resource-snapshot-skills resources))
                  (prompts (resource-snapshot-prompts resources))
                  (themes (resource-snapshot-themes resources))
                  (extension-items
                   (mapcar
                    (lambda (extension)
                      (let ((path (getf extension :path)))
                        (list
                         :path path
                         :scope
                         (case (getf extension :scope)
                           (:global "user")
                           (:project "project")
                           (otherwise "path")))))
                    extensions))
                  (blocks nil))
               (flet
                   ((emit (lines)
                      (setf blocks (nconc blocks lines))))
                 (when context-files
                   (emit
                    (section-lines
                     "Context"
                     (if expanded-p
                         (mapcar
                          (lambda (path)
                            (cadr-tui:theme-foreground
                             :dim
                             (format
                              nil "  ~A"
                              (startup-home-abbreviated path))
                             :enabled-p t))
                          context-files)
                         (compact-body
                          (mapcar
                           (lambda (path)
                             (startup-cwd-relative path cwd))
                           context-files)))
                     :leading-blank-p t)))
                 (when skills
                   (emit
                    (section-lines
                     "Skills"
                     (if expanded-p
                         (startup-scope-grouped-lines
                          (group-items
                           (mapcar
                            #'cadr-agent:skill-file-path
                            skills))
                          (lambda (item)
                            (cadr-tui:theme-foreground
                             :dim
                             (format
                              nil "    ~A"
                              (startup-home-abbreviated
                               (getf item :path)))
                             :enabled-p t)))
                         (compact-body
                          (sort
                           (mapcar
                            #'cadr-agent:skill-name
                            skills)
                           #'startup-locale<))))))
                 (when prompts
                   (emit
                    (section-lines
                     "Prompts"
                     (if expanded-p
                         (startup-scope-grouped-lines
                          (mapcar
                           (lambda (prompt)
                             (list
                              :path
                              (cadr-agent:prompt-template-file-path
                               prompt)
                              :scope
                              (scope-of
                               (cadr-agent:prompt-template-file-path
                                prompt))
                              :name
                              (cadr-agent:prompt-template-name prompt)))
                           prompts)
                          (lambda (item)
                            (cadr-tui:theme-foreground
                             :dim
                             (format nil "    /~A" (getf item :name))
                             :enabled-p t)))
                         (compact-body
                          (sort
                           (mapcar
                            (lambda (prompt)
                              (format
                               nil "/~A"
                               (cadr-agent:prompt-template-name
                                prompt)))
                            prompts)
                           #'startup-locale<))))))
                 (when extension-items
                   (emit
                    (section-lines
                     "Extensions"
                     (if expanded-p
                         (startup-scope-grouped-lines
                          extension-items
                          (lambda (item)
                            (cadr-tui:theme-foreground
                             :dim
                             (format
                              nil "    ~A"
                              (startup-extension-display-path
                               (getf item :path)))
                             :enabled-p t)))
                         (compact-body
                          (sort
                           (startup-extension-compact-labels
                            (mapcar
                             (lambda (item) (getf item :path))
                             extension-items))
                           #'startup-locale<))))))
                 (when themes
                   (emit
                    (section-lines
                     "Themes"
                     (if expanded-p
                         (startup-scope-grouped-lines
                          (group-items
                           (mapcar
                            (lambda (theme)
                              (namestring-of (getf theme :path)))
                            themes))
                          (lambda (item)
                            (cadr-tui:theme-foreground
                             :dim
                             (format
                              nil "    ~A"
                              (startup-home-abbreviated
                               (getf item :path)))
                             :enabled-p t)))
                         (compact-body
                          (sort
                           (mapcar
                            (lambda (theme)
                              (or (getf theme :name) "unnamed"))
                            themes)
                           #'startup-locale<))))))
                 (let ((skill-conflicts
                        (startup-conflict-lines
                         "Skill conflicts"
                         (resource-snapshot-skill-collisions resources)
                         (resource-snapshot-skill-diagnostics resources)
                         agent-directory
                         cwd))
                       (prompt-conflicts
                        (startup-conflict-lines
                         "Prompt conflicts"
                         (resource-snapshot-prompt-collisions resources)
                         (resource-snapshot-prompt-diagnostics
                          resources)
                         agent-directory
                         cwd)))
                   (when skill-conflicts
                     (emit (append skill-conflicts (list ""))))
                   (when prompt-conflicts
                     (emit (append prompt-conflicts (list ""))))
                   (when extension-issues
                     (emit
                      (append
                       (list
                        (cadr-tui:theme-foreground
                         :warning "[Extension issues]" :enabled-p t))
                       (loop
                        for issue in extension-issues
                        for color =
                        (if (eq (getf issue :type) :error)
                            :error
                            :warning)
                        append
                        (if (getf issue :path)
                            (list
                             (cadr-tui:theme-foreground
                              color
                              (format
                               nil "  ~A"
                               (startup-home-abbreviated
                                (getf issue :path)))
                              :enabled-p t)
                             (cadr-tui:theme-foreground
                              color
                              (format
                               nil "    ~A" (getf issue :message))
                              :enabled-p t))
                            (list
                             (cadr-tui:theme-foreground
                              color
                              (format
                               nil "  ~A" (getf issue :message))
                              :enabled-p t))))
                       (list "")))))
                 ;; The baseline puts a Spacer(1) after every block; the
                 ;; last block's spacer coincides with the shared trailing
                 ;; blank the frame adds after the startup lines, so drop
                 ;; it here to keep the total row count identical.
                 (and blocks (butlast blocks))))))))
    (let* ((logo (format nil "cadr v~A" version))
           (cycle-keys
             (cadr-tui:keybinding-keys
              (cadr-tui:get-keybindings)
              "app.model.cycleForward"))
           (backward-cycle-keys
             (cadr-tui:keybinding-keys
              (cadr-tui:get-keybindings)
              "app.model.cycleBackward"))
           (cycle-help-line
             (and (or cycle-keys backward-cycle-keys)
                  (format
                   nil "~{~A~^/~} to cycle models"
                   (append cycle-keys backward-cycle-keys))))
           (compact
             (list
              logo
              "escape interrupt · ctrl+c/ctrl+d clear/exit · / commands · ! bash · ctrl+o more"
              "Press ctrl+o to show full startup help and loaded resources."
              ""
              "Cadr can explain its own features and look up its docs. Ask it how to use or extend Cadr."))
           (expanded
             (append
              (remove
               nil
               (append
                (list logo)
                (startup-expanded-help-lines cycle-help-line)
                (list
                 ""
                 "Cadr can explain its own features and look up its docs. Ask it how to use or extend Cadr.")))
              (let ((blocks (sections t)))
                (when blocks
                  (append (list "") blocks))))))
      (values
       (append
        compact
        (let ((blocks (sections nil)))
          (when blocks
            (append (list "") blocks))))
       expanded))))

(defun render-tui-startup-lines (lines width)
  (labels
      ((key-hint (key description)
         (concatenate
          'string
          (cadr-tui:theme-foreground
           :dim key :enabled-p t)
          (cadr-tui:theme-foreground
           :muted
           (format nil " ~A" description)
           :enabled-p t)))
       (compact-help ()
         (format
          nil "~{~A~^~A~}"
          (list
           (key-hint "escape" "interrupt")
           (cadr-tui:theme-foreground
            :muted " · " :enabled-p t)
           (key-hint "ctrl+c/ctrl+d" "clear/exit")
           (cadr-tui:theme-foreground
            :muted " · " :enabled-p t)
           (key-hint "/" "commands")
           (cadr-tui:theme-foreground
            :muted " · " :enabled-p t)
           (key-hint "!" "bash")
           (cadr-tui:theme-foreground
            :muted " · " :enabled-p t)
           (key-hint "ctrl+o" "more"))))
       (expanded-help (line)
         (let ((parts
                 (assoc
                  line +startup-expanded-help+
                  :test #'string=)))
           (cond
             (parts
              (key-hint (second parts) (third parts)))
             ((and
               (plusp (length line))
               (uiop:string-suffix-p line " to cycle models"))
              (key-hint
               (subseq line 0
                       (- (length line)
                          (length " to cycle models")))
               "to cycle models")))))
       (style-line (line index)
         (cond
           ((find #\Esc line)
            ;; Section/conflict lines arrive pre-themed by
            ;; make-tui-startup-lines; pass them through untouched.
            line)
           ((zerop index)
            (let ((split (position #\Space line)))
              (if split
                  (concatenate
                   'string
                   (cadr-tui:theme-bold
                    (cadr-tui:theme-foreground
                     :accent (subseq line 0 split)
                     :enabled-p t))
                   (cadr-tui:theme-foreground
                    :dim (subseq line split)
                    :enabled-p t))
                  (cadr-tui:theme-bold
                   (cadr-tui:theme-foreground
                    :accent line :enabled-p t)))))
           ((string=
             line
             "escape interrupt · ctrl+c/ctrl+d clear/exit · / commands · ! bash · ctrl+o more")
            (compact-help))
           ((expanded-help line))
           ((and
             (plusp (length line))
             (char= (char line 0) #\[))
            (cadr-tui:theme-foreground
             :md-heading line :enabled-p t))
           (t
            (cadr-tui:theme-foreground
             :dim line :enabled-p t)))))
    (when lines
      ;; The baseline renders the banner (paddingX 1) and the loaded
      ;; resource sections (paddingX 0, in a separate container) as
      ;; distinct components.  Sections arrive pre-themed from
      ;; make-tui-startup-lines, so split at the run of blank lines that
      ;; precedes the first pre-themed line; both halves go through the
      ;; text component so content lines pad to the full width like the
      ;; baseline — padding-x 1 for the banner, 0 for the sections.
      (let* ((first-styled
              (position-if (lambda (line) (find #\Esc line)) lines))
             (split
              (if (null first-styled)
                  (length lines)
                  (let ((index first-styled))
                    (loop while (and
                                 (> index 0)
                                 (string= (nth (1- index) lines) ""))
                          do (decf index))
                    index)))
             (banner (subseq lines 0 split))
             (sections (subseq lines split)))
        (append
         (and
          banner
          (cadr-tui:component-render
           (cadr-tui:make-text-component
            (format
             nil "~{~A~^~%~}"
             (loop for line in banner
                   for index from 0
                   collect (style-line line index)))
            :padding-x 1 :padding-y 0)
           width))
         ;; Render each section block through the component (content
         ;; lines pad to full width like the baseline Text) but keep the
         ;; separator blanks truly empty like the baseline Spacer.
         (loop with block = nil
               with rendered = nil
               for line in sections
               if (string= line "")
                 do (when block
                      (setf
                       rendered
                       (nconc
                        rendered
                        (cadr-tui:component-render
                         (cadr-tui:make-text-component
                          (format nil "~{~A~^~%~}" (nreverse block))
                          :padding-x 0 :padding-y 0)
                         width)))
                      (setf block nil))
                    (setf rendered (nconc rendered (list "")))
               else do (push line block)
               finally
               (when block
                 (setf
                  rendered
                  (nconc
                   rendered
                   (cadr-tui:component-render
                    (cadr-tui:make-text-component
                     (format nil "~{~A~^~%~}" (nreverse block))
                     :padding-x 0 :padding-y 0)
                    width))))
               (return rendered)))))))
