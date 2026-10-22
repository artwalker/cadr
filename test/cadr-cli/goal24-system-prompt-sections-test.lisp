(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

;;; Locks packages/coding-agent/test/system-prompt-updates.test.ts
;;; "diffs sections into a patch" and
;;; "keeps the preamble untagged and replaces it like any section"
;;; against baseline v0.86.0 system-prompt.ts.

(defun section-text (sections name)
  (cdr (assoc name sections :test #'string=)))

(test diffs-sections-into-a-patch
  (let ((previous
          (cadr-cli:build-system-prompt-sections
           :cwd "/tmp"
           :sections '(("plan_mode" . "Plan only."))))
        (current
          (cadr-cli:build-system-prompt-sections
           :cwd "/tmp"
           :sections
           '(("plan_mode" . "Implementation allowed.")))))
    (is (equal
         '(("plan_mode"
            . "<plan_mode>
Implementation allowed.
</plan_mode>"))
         (cadr-cli:diff-system-prompt-sections
          previous current)))
    (is (null
         (cadr-cli:diff-system-prompt-sections
          previous previous)))
    (is (equal
         '(("plan_mode" . nil))
         (cadr-cli:diff-system-prompt-sections
          previous
          (cadr-cli:build-system-prompt-sections
           :cwd "/tmp"))))))

(test keeps-the-preamble-untagged-and-replaces-it-like-any-section
  (let ((previous
          (cadr-cli:build-system-prompt-sections
           :custom-prompt "You are A."
           :cwd "/tmp"))
        (current
          (cadr-cli:build-system-prompt-sections
           :custom-prompt "You are B."
           :cwd "/tmp")))
    (is (string= "You are A."
                 (section-text previous "preamble")))
    (is (equal
         '(("preamble" . "You are B."))
         (cadr-cli:diff-system-prompt-sections
          previous current)))
    (is (equal
         '(:content "Exact prompt.")
         (cadr-cli:build-system-prompt-state
          :force-system-prompt "Exact prompt."
          :cwd "/tmp")))
    (let ((state
            (cadr-cli:build-system-prompt-state
             :cwd "/tmp")))
      (is (string= "" (getf state :content)))
      (is (equal
           (cadr-cli:build-system-prompt-sections
            :cwd "/tmp")
           (getf state :sections))))
    (signals error
      (cadr-cli:build-system-prompt-sections
       :cwd "/tmp"
       :sections '(("preamble" . "x"))))))

(test hidden-tools-leave-the-prompt-list-rules-and-reader-name
  ;; pi@4a080252f #10343. Declared tools are the selected tools minus
  ;; hidden ones. Skills stay when the reader is only hidden, and the
  ;; hint names no tool. A hidden name is not put back on the registry.
  (let* ((skill
           (cadr-agent::make-skill
            :name "review"
            :description "Review a change"
            :content "steps"
            :file-path "/skills/review/SKILL.md"))
         (snippets
           '(("read" . "Read files")
             ("bash" . "Run commands")
             ("run" . "Run a task")))
         (guidelines
           '(("read" "Use read for files.")
             ("run" "Prefer run.")))
         (both
           (cadr-cli:build-system-prompt-sections
            :cwd "/tmp"
            :selected-tools '("read" "bash" "run")
            :hidden-tools '("read" "bash")
            :tool-snippets snippets
            :tool-guidelines guidelines
            :skills (list skill)))
         (bash-only
           (cadr-cli:build-system-prompt-sections
            :cwd "/tmp"
            :selected-tools '("read" "bash" "run")
            :hidden-tools '("read")
            :tool-snippets snippets
            :tool-guidelines guidelines
            :skills (list skill)))
         (none
           (cadr-cli:build-system-prompt-sections
            :cwd "/tmp"
            :selected-tools '("read" "bash" "run")
            :tool-snippets snippets
            :tool-guidelines guidelines
            :skills (list skill)))
         (tools (section-text both "tools"))
         (rules (section-text both "rules"))
         (skills (section-text both "skills")))
    (is (search "- run: Run a task" tools))
    (is (not (search "- read: " tools)))
    (is (not (search "- bash: " tools)))
    (is (not (search "Use read for files." rules)))
    (is (not (search "Use bash for file operations" rules)))
    (is (search "- Prefer run." rules))
    (is (search "Load a skill's file when the task matches its description."
                skills))
    (is (search "<available_skills>" skills))
    (is (search "Use bash to load a skill's file"
                (section-text bash-only "skills")))
    (is (search "Use the read tool to load a skill's file"
                (section-text none "skills"))))
  (let* ((read-tool
           (cadr-ai:make-tool
            :name "read" :description "read"
            :parameters (cadr-ai::json-object)
            :executor (lambda (&rest args) (declare (ignore args)) nil)))
         (run-tool
           (cadr-ai:make-tool
            :name "run" :description "run"
            :parameters (cadr-ai::json-object)
            :executor (lambda (&rest args) (declare (ignore args)) nil)))
         (lookup
           (let ((by-name (make-hash-table :test #'equal)))
             (setf (gethash "read" by-name) read-tool
                   (gethash "run" by-name) run-tool)
             (lambda (name) (gethash name by-name)))))
    (multiple-value-bind (update selected)
        (cadr-cli:prepare-prompt-and-tool-loadout
         (list :cwd "/tmp"
               :selected-tools '("read" "run")
               :hidden-tools '("read"))
         nil lookup)
      (declare (ignore update))
      (is (equal '("run")
                 (mapcar #'cadr-ai:tool-name selected))))))
