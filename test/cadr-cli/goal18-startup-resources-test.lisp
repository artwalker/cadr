(in-package #:cadr-cli/tests)

(in-suite cadr-cli-suite)

;;; Goal 18 Part H, locked to v1.4.0 showLoadedResources: section order
;;; Context -> Skills -> Prompts -> Extensions. Themes are not a startup
;;; section. The [Skill conflicts] / [Prompt conflicts] warning blocks
;;; and the compact/expanded bodies follow the same function.

(defun goal18-startup-section-titles (lines)
  (loop for line in lines
        when (and (plusp (length line)) (char= (char line 0) #\Esc))
        collect line))

(defun goal18-strip-ansi (text)
  (cl-ppcre:regex-replace-all "\\e\\[[0-9;]*m" text ""))

(defun goal18-resource-snapshot ()
  (cadr-cli::make-resource-snapshot
   :skills (list (cadr-agent:make-skill
                  :name "zeta-skill"
                  :description "z"
                  :file-path "/home/u/.cadr/agent/skills/zeta-skill/SKILL.md")
                 (cadr-agent:make-skill
                  :name "alpha-skill"
                  :description "a"
                  :file-path "/home/u/.cadr/agent/skills/alpha-skill/SKILL.md"))
   :prompts (list (cadr-agent:make-prompt-template
                   :name "review"
                   :file-path "/home/u/.cadr/agent/prompts/review.md"))
   :themes (list (list :name "acme" :path "/home/u/.cadr/agent/themes/acme.json"))
   :context-files (list #P"/home/u/project/AGENTS.md")
   :cwd "/home/u/project/"
   :agent-directory "/home/u/.cadr/agent/"))

(test goal18-startup-sections-follow-the-baseline-order-and-labels
  (multiple-value-bind (compact expanded)
      (cadr-cli::make-tui-startup-lines
       (goal18-resource-snapshot)
       :extensions
       (list
        (list
         :path "/home/u/.cadr/agent/extensions/demo/extension.lisp"
         :scope :global)))
    (let* ((texts (mapcar #'goal18-strip-ansi compact))
           (user-header
            (find "user" expanded :test #'search))
           (titles
            (remove-if-not
             (lambda (line)
               (and (plusp (length line)) (char= (char line 0) #\[)))
             texts)))
      (is (equal
           '("[Context]" "[Skills]" "[Prompts]" "[Extensions]")
           titles))
      (is (not (member "Prompt Templates" titles :test #'string=)))
      (is (not (member "[Themes]" titles :test #'string=)))
      ;; Baseline compact lists sort by name; Context keeps insertion order.
      (is (find "  alpha-skill, zeta-skill" texts :test #'string=))
      (is (find "  /review" texts :test #'string=))
      (is (find "  demo" texts :test #'string=))
      (is (not (find "  acme" texts :test #'string=)))
      (is (find "  AGENTS.md" texts :test #'string=))
      ;; v1.4.0 formatScopeGroups: the two spaces sit outside the accent color.
      (is (and user-header
               (>= (length user-header) 2)
               (string= "  " (subseq user-header 0 2)))))))

(test startup-single-file-extension-keeps-its-filename
  ;; v1.4.0 getCompactExtensionLabels keeps hello.ts. Directory entries
  ;; named extension.lisp still collapse to the directory.
  (multiple-value-bind (compact expanded)
      (cadr-cli::make-tui-startup-lines
       (cadr-cli::make-resource-snapshot
        :cwd "/home/u/project/"
        :agent-directory "/home/u/.cadr/agent/")
       :extensions
       (list
        (list :path "/home/u/.cadr/agent/extensions/hello.ts"
              :scope :global)))
    (declare (ignore expanded))
    (let ((texts (mapcar #'goal18-strip-ansi compact)))
      (is (find "  hello.ts" texts :test #'string=))
      (is (not (find "  hello.lisp" texts :test #'string=))))))

(test goal18-context-files-follow-baseline-ancestor-order
  (with-test-directory (root)
    (let* ((outer (merge-pathnames "outer/" root))
           (project (merge-pathnames "outer/project/" root)))
      (ensure-directories-exist project)
      (write-text (merge-pathnames "AGENTS.md" outer) "outer")
      (write-text (merge-pathnames "AGENTS.md" project) "project")
      (let* ((expected
              (list (namestring (merge-pathnames "AGENTS.md" outer))
                    (namestring (merge-pathnames "AGENTS.md" project))))
             (actual
              (mapcar #'namestring
                      (cadr-cli::load-project-context-files
                       :cwd project))))
        ;; Baseline order is rootward-first; ancestors above the temp tree
        ;; (for example /tmp/AGENTS.md) may also be present.
        (is (equal expected (subseq actual (- (length actual) 2))))))))

(test goal18-startup-skill-conflicts-block-matches-the-baseline-shape
  (let* ((snapshot (goal18-resource-snapshot))
         (diagnostic
          (cadr-agent::make-resource-diagnostic
           :type :warning
           :code :invalid-metadata
           :message "description is required"
           :path "/home/u/.cadr/agent/skills/broken-skill/SKILL.md")))
    (setf
     (cadr-cli::resource-snapshot-skill-diagnostics snapshot)
     (list diagnostic))
    (multiple-value-bind (compact expanded)
        (cadr-cli::make-tui-startup-lines snapshot)
      (declare (ignore expanded))
      (let ((texts (mapcar #'goal18-strip-ansi compact)))
        (is (find "[Skill conflicts]" texts :test #'string=))
        ;; Load warnings carry no sourceInfo in the baseline, so the path
        ;; line has no scope label (formatPathWithSource falls back to
        ;; formatDisplayPath).
        (is (find
             "  /home/u/.cadr/agent/skills/broken-skill/SKILL.md"
             texts
             :test #'string=))
        (is (find "    description is required" texts :test #'string=))))))

(test goal18-startup-prompt-conflicts-block-renders
  (let* ((snapshot (goal18-resource-snapshot))
         (diagnostic
          (cadr-agent::make-resource-diagnostic
           :type :warning
           :code :parse-failed
           :message "unterminated frontmatter"
           :path "/home/u/.cadr/agent/prompts/bad.md")))
    (setf
     (cadr-cli::resource-snapshot-prompt-diagnostics snapshot)
     (list diagnostic))
    (multiple-value-bind (compact expanded)
        (cadr-cli::make-tui-startup-lines snapshot)
      (declare (ignore expanded))
      (let ((texts (mapcar #'goal18-strip-ansi compact)))
        (is (find "[Prompt conflicts]" texts :test #'string=))
        (is (find "  /home/u/.cadr/agent/prompts/bad.md" texts :test #'string=))
        (is (find "    unterminated frontmatter" texts :test #'string=))))))

(test goal18-startup-collision-group-matches-the-baseline-shape
  (let ((snapshot (goal18-resource-snapshot)))
    (setf
     (cadr-cli::resource-snapshot-skill-collisions snapshot)
     (list
      (list
       :name "shared"
       :winner-path "/home/u/project/.cadr/skills/shared/SKILL.md"
       :loser-path "/home/u/.cadr/agent/skills/shared/SKILL.md")))
    (multiple-value-bind (compact expanded)
        (cadr-cli::make-tui-startup-lines snapshot)
      (declare (ignore expanded))
      (let ((texts (mapcar #'goal18-strip-ansi compact)))
        (is (find "[Skill conflicts]" texts :test #'string=))
        (is (find "  \"shared\" collision:" texts :test #'string=))
        ;; Collision paths carry the baseline scope label.
        (is (find
             "    ✓ project /home/u/project/.cadr/skills/shared/SKILL.md"
             texts
             :test #'string=))
        (is (find
             "    ✗ user /home/u/.cadr/agent/skills/shared/SKILL.md (skipped)"
             texts
             :test #'string=))))))

(test goal18-startup-extension-issues-block-renders
  ;; Baseline interactive-mode.ts:1627-1645 aggregates extension load
  ;; errors and command/shortcut diagnostics into a warning [Extension
  ;; issues] block after [Prompt conflicts]; real load-error text is
  ;; implementation-specific on both sides, so the block shape is pinned
  ;; here rather than in the dual capture.
  (multiple-value-bind (compact expanded)
      (cadr-cli::make-tui-startup-lines
       (goal18-resource-snapshot)
       :extensions
       (list
        (list
         :path "/home/u/.cadr/agent/extensions/demo/extension.lisp"
         :scope :global))
       :extension-issues
       (list
        (list
         :type :error
         :path "/home/u/.cadr/agent/extensions/broken/extension.lisp"
         :message "failed to load extension")
        (list
         :type :warning
         :message "command /demo conflicts with a built-in command")))
    (declare (ignore expanded))
    (let ((texts (mapcar #'goal18-strip-ansi compact)))
      (is (find "[Extension issues]" texts :test #'string=))
      (is (find
           "  /home/u/.cadr/agent/extensions/broken/extension.lisp"
           texts
           :test #'string=))
      (is (find "    failed to load extension" texts :test #'string=))
      (is (find
           "  command /demo conflicts with a built-in command"
           texts
           :test #'string=))
      ;; The block sorts after [Prompt conflicts]/[Skill conflicts].
      (let ((titles
             (remove-if-not
              (lambda (line)
                (and (plusp (length line)) (char= (char line 0) #\[)))
              texts)))
        (is (equal
             '("[Context]" "[Skills]" "[Prompts]" "[Extensions]"
               "[Extension issues]")
             titles))))))

(test goal18-startup-collision-winner-is-the-project-resource
  ;; Baseline grounding: package-manager resolve() adds project resources
  ;; before user resources and the first occurrence wins the dedupe, so the
  ;; project skill wins a same-name collision.
  (with-test-directory (root)
    (let ((agent-dir (merge-pathnames "agent/" root))
          (cwd (merge-pathnames "project/" root)))
      (write-text
       (merge-pathnames "skills/shared/SKILL.md" agent-dir)
       (format nil "---~%name: shared~%description: user~%---~%user body"))
      (write-text
       (merge-pathnames ".cadr/skills/shared/SKILL.md" cwd)
       (format nil "---~%name: shared~%description: project~%---~%project body"))
      (let* ((loader
              (cadr-cli::make-default-resource-loader
               :cwd cwd :agent-directory agent-dir :project-trusted-p t))
             (snapshot (cadr-cli::reload-resources loader)))
        (is (= 1 (length (cadr-cli::resource-snapshot-skills snapshot))))
        (is (search
             "project body"
             (cadr-agent:skill-content
              (first (cadr-cli::resource-snapshot-skills snapshot)))))
        (is (= 1 (length (cadr-cli::resource-snapshot-skill-collisions snapshot))))
        (let ((collision
               (first (cadr-cli::resource-snapshot-skill-collisions snapshot))))
          (is (search "project" (getf collision :winner-path)))
          (is (search "agent" (getf collision :loser-path))))))))

(defun goal18-link-worktree (main worktree name)
  (let ((git-dir
          (merge-pathnames
           (format nil ".git/worktrees/~A/" name)
           main)))
    (ensure-directories-exist git-dir)
    (write-text (merge-pathnames ".git/HEAD" main)
                (format nil "ref: refs/heads/main~%"))
    (write-text (merge-pathnames "HEAD" git-dir)
                (format nil "ref: refs/heads/feat~%"))
    (write-text (merge-pathnames "commondir" git-dir) "../..")
    (write-text (merge-pathnames ".git" worktree)
                (format nil "gitdir: ~A~%" (namestring git-dir)))))

(defun goal18-symlink (target link)
  (uiop:run-program
   (list "ln" "-s" (namestring target) (namestring link))))

(defun goal18-context-under (root cwd)
  (let ((prefix
          (namestring
           (uiop:ensure-directory-pathname root))))
    (remove-if-not
     (lambda (path)
       (uiop:string-prefix-p prefix (namestring path)))
     (cadr-cli::load-project-context-files :cwd cwd))))

(test nested-worktree-keeps-its-own-agents-file
  (with-test-directory (root)
    (let* ((main (merge-pathnames "outer/main/" root))
           (worktree (merge-pathnames "worktrees/feat/" main))
           (src (merge-pathnames "src/" worktree)))
      (ensure-directories-exist src)
      (goal18-link-worktree main worktree "feat")
      (write-text (merge-pathnames "AGENTS.md" main)
                  "main repo instructions")
      (write-text (merge-pathnames "AGENTS.md" worktree)
                  "worktree instructions")
      (is (equal '("worktree instructions")
                 (mapcar (lambda (path)
                           (uiop:read-file-string
                            path :external-format :utf-8))
                         (goal18-context-under root src)))))))

(test nested-worktree-symlink-loads-the-worktree-path-once
  (with-test-directory (root)
    (let* ((main (merge-pathnames "outer/main/" root))
           (worktree (merge-pathnames "worktrees/feat/" main))
           (src (merge-pathnames "src/" worktree))
           (link (merge-pathnames "AGENTS.md" worktree)))
      (ensure-directories-exist src)
      (goal18-link-worktree main worktree "feat")
      (write-text (merge-pathnames "AGENTS.md" main)
                  "main repo instructions")
      (goal18-symlink (merge-pathnames "AGENTS.md" main) link)
      (is (equal (list (namestring link))
                 (mapcar #'namestring
                         (goal18-context-under root src)))))))

(test nested-worktree-shared-symlink-keeps-the-worktree-path
  (with-test-directory (root)
    (let* ((outer (merge-pathnames "outer/" root))
           (main (merge-pathnames "main/" outer))
           (worktree (merge-pathnames "worktrees/feat/" main))
           (src (merge-pathnames "src/" worktree))
           (shared (merge-pathnames "shared-agents.md" outer))
           (link (merge-pathnames "AGENTS.md" worktree)))
      (ensure-directories-exist src)
      (goal18-link-worktree main worktree "feat")
      (write-text shared "shared instructions")
      (goal18-symlink shared (merge-pathnames "AGENTS.md" main))
      (goal18-symlink shared link)
      (is (equal (list (namestring link))
                 (mapcar #'namestring
                         (goal18-context-under root src)))))))

(test nested-worktree-without-its-own-file-inherits-the-main-repo
  (with-test-directory (root)
    (let* ((main (merge-pathnames "outer/main/" root))
           (worktree (merge-pathnames "worktrees/feat/" main))
           (src (merge-pathnames "src/" worktree)))
      (ensure-directories-exist src)
      (goal18-link-worktree main worktree "feat")
      (write-text (merge-pathnames "AGENTS.md" main)
                  "main repo instructions")
      (is (equal '("main repo instructions")
                 (mapcar (lambda (path)
                           (uiop:read-file-string
                            path :external-format :utf-8))
                         (goal18-context-under root src)))))))

(test nested-worktree-keeps-a-differently-named-main-context-file
  (with-test-directory (root)
    (let* ((main (merge-pathnames "outer/main/" root))
           (worktree (merge-pathnames "worktrees/feat/" main))
           (src (merge-pathnames "src/" worktree)))
      (ensure-directories-exist src)
      (goal18-link-worktree main worktree "feat")
      (write-text (merge-pathnames "CLAUDE.md" main)
                  "main repo instructions")
      (write-text (merge-pathnames "AGENTS.md" worktree)
                  "worktree instructions")
      (is (equal '("main repo instructions" "worktree instructions")
                 (mapcar (lambda (path)
                           (uiop:read-file-string
                            path :external-format :utf-8))
                         (goal18-context-under root src)))))))

(test bare-worktree-layout-keeps-the-container-context
  (with-test-directory (root)
    (let* ((proj (merge-pathnames "proj/" root))
           (bare (merge-pathnames ".bare/" proj))
           (worktree (merge-pathnames "main/" proj))
           (git-dir (merge-pathnames "worktrees/main/" bare)))
      (ensure-directories-exist git-dir)
      (ensure-directories-exist worktree)
      (write-text (merge-pathnames "HEAD" bare)
                  (format nil "ref: refs/heads/main~%"))
      (write-text (merge-pathnames "HEAD" git-dir)
                  (format nil "ref: refs/heads/main~%"))
      (write-text (merge-pathnames "commondir" git-dir) "../..")
      (write-text (merge-pathnames ".git" worktree)
                  (format nil "gitdir: ~A~%" (namestring git-dir)))
      (write-text (merge-pathnames "AGENTS.md" proj)
                  "container instructions")
      (write-text (merge-pathnames "AGENTS.md" worktree)
                  "worktree instructions")
      (is (equal '("container instructions" "worktree instructions")
                 (mapcar (lambda (path)
                           (uiop:read-file-string
                            path :external-format :utf-8))
                         (goal18-context-under root worktree)))))))

(test nested-worktree-keeps-context-above-the-main-repo
  (with-test-directory (root)
    (let* ((outer (merge-pathnames "outer/" root))
           (main (merge-pathnames "main/" outer))
           (worktree (merge-pathnames "worktrees/feat/" main))
           (src (merge-pathnames "src/" worktree)))
      (ensure-directories-exist src)
      (goal18-link-worktree main worktree "feat")
      (write-text (merge-pathnames "AGENTS.md" outer) "outer instructions")
      (write-text (merge-pathnames "AGENTS.md" main) "main repo instructions")
      (write-text (merge-pathnames "AGENTS.md" worktree)
                  "worktree instructions")
      (is (equal '("outer instructions" "worktree instructions")
                 (mapcar (lambda (path)
                           (uiop:read-file-string
                            path :external-format :utf-8))
                         (goal18-context-under root src)))))))

(test sibling-worktree-keeps-the-outer-context
  (with-test-directory (root)
    (let* ((outer (merge-pathnames "outer/" root))
           (main (merge-pathnames "main/" outer))
           (sib (merge-pathnames "sib-feat/" outer))
           (src (merge-pathnames "src/" sib)))
      (ensure-directories-exist src)
      (ensure-directories-exist main)
      (goal18-link-worktree main sib "sib")
      (write-text (merge-pathnames "AGENTS.md" outer) "outer instructions")
      (write-text (merge-pathnames "AGENTS.md" sib)
                  "sibling worktree instructions")
      (is (equal '("outer instructions" "sibling worktree instructions")
                 (mapcar (lambda (path)
                           (uiop:read-file-string
                            path :external-format :utf-8))
                         (goal18-context-under root src)))))))

(test submodule-keeps-the-superproject-context
  (with-test-directory (root)
    (let* ((sup (merge-pathnames "super/" root))
           (sub (merge-pathnames "vendor/lib/" sup))
           (src (merge-pathnames "src/" sub))
           (git-dir (merge-pathnames ".git/modules/vendor/lib/" sup)))
      (ensure-directories-exist src)
      (ensure-directories-exist git-dir)
      (write-text (merge-pathnames "AGENTS.md" sup)
                  "superproject instructions")
      (write-text (merge-pathnames "AGENTS.md" sub)
                  "submodule instructions")
      (write-text (merge-pathnames "HEAD" git-dir)
                  (format nil "ref: refs/heads/main~%"))
      (write-text (merge-pathnames ".git" sub)
                  (format nil "gitdir: ~A~%" (namestring git-dir)))
      (is (equal '("superproject instructions" "submodule instructions")
                 (mapcar (lambda (path)
                           (uiop:read-file-string
                            path :external-format :utf-8))
                         (goal18-context-under root src)))))))

(test header-only-quiet-startup-keeps-the-banner-and-drops-resources
  (let* ((manager (cadr-cli::make-memory-settings-manager))
         (model
           (cadr-ai:make-model
            :id "faux-1" :name "Faux" :provider :faux :api :faux))
         (agent (cadr-agent:make-agent :provider nil :model model))
         (state
           (cadr-cli::make-cli-settings-selector-state
            manager agent (cadr-cli::make-resource-snapshot)
            :supports-images-p nil))
         (snapshot (goal18-resource-snapshot))
         (scope
           (list (list :model model :thinking nil)))
         (keys (cadr-tui:make-keybindings-manager)))
    (is (null (cadr-cli::settings-quiet-startup manager)))
    (cadr-cli::settings-selector-notify-change
     state "quiet-startup" "header")
    (is (eq :header (cadr-cli::settings-quiet-startup manager)))
    (cadr-cli::settings-selector-notify-change
     state "quiet-startup" "true")
    (is (eq t (cadr-cli::settings-quiet-startup manager)))
    (cadr-cli::settings-selector-notify-change
     state "quiet-startup" "false")
    (is (null (cadr-cli::settings-quiet-startup manager)))
    (cadr-cli::settings-set
     manager "quietStartup" "nope" :scope :global)
    (is (null (cadr-cli::settings-quiet-startup manager)))
    (is (null
         (cadr-cli::model-scope-startup-line
          scope keys :verbose-p nil :quiet-startup-p :header)))
    (is (stringp
         (cadr-cli::model-scope-startup-line
          scope keys :verbose-p t :quiet-startup-p :header)))
    (multiple-value-bind (compact expanded)
        (cadr-cli::make-tui-startup-lines
         snapshot :include-resources-p nil)
      (let ((compact-text (mapcar #'goal18-strip-ansi compact))
            (expanded-text (mapcar #'goal18-strip-ansi expanded)))
        (is (find-if
             (lambda (line) (uiop:string-prefix-p "cadr v" line))
             compact-text))
        (is (find "Press ctrl+o to show full startup help."
                  compact-text :test #'string=))
        (is (not (find "loaded resources" compact-text :test #'search)))
        (is (not (find "[Skills]" compact-text :test #'string=)))
        (is (not (find "alpha-skill" compact-text :test #'search)))
        (is (not (find "[Skills]" expanded-text :test #'string=)))
        (is (not (find "alpha-skill" expanded-text :test #'search)))))
    (let ((texts
            (mapcar
             #'goal18-strip-ansi
             (cadr-cli::make-tui-startup-lines snapshot))))
      (is (find
           "Press ctrl+o to show full startup help and loaded resources."
           texts :test #'string=))
      (is (find "[Skills]" texts :test #'string=))
      (is (find "  alpha-skill, zeta-skill" texts :test #'string=)))))
