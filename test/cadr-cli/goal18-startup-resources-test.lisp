(in-package #:cadr-cli/tests)

(in-suite cadr-cli-suite)

;;; Goal 18 Part H: the startup loaded-resource blocks follow the baseline
;;; (interactive-mode.ts:1537-1613): section order
;;; Context -> Skills -> Prompts -> Extensions -> Themes, the [Skill
;;; conflicts] / [Prompt conflicts] warning blocks, and the baseline
;;; compact/expanded bodies.  The render-diff startup-resources scenario
;;; pins the dual captures; these tests pin the block semantics that
;;; fixtures cannot byte-match (prompt conflicts are
;;; implementation-specific text on the baseline side).

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
    (declare (ignore expanded))
    (let* ((texts (mapcar #'goal18-strip-ansi compact))
           (titles
            (remove-if-not
             (lambda (line)
               (and (plusp (length line)) (char= (char line 0) #\[)))
             texts)))
      (is (equal
           '("[Context]" "[Skills]" "[Prompts]" "[Extensions]" "[Themes]")
           titles))
      (is (not (member "Prompt Templates" titles :test #'string=)))
      ;; Baseline compact lists sort by name; Context keeps insertion order.
      (is (find "  alpha-skill, zeta-skill" texts :test #'string=))
      (is (find "  /review" texts :test #'string=))
      (is (find "  demo" texts :test #'string=))
      (is (find "  acme" texts :test #'string=))
      (is (find "  AGENTS.md" texts :test #'string=)))))

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
               "[Themes]" "[Extension issues]")
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
