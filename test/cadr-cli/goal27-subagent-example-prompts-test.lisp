(in-package #:cadr-cli/tests)

(in-suite cadr-cli-suite)

;; v1.4.0 packages/coding-agent/examples/extensions/subagent/
;; File digests are the git blobs. Body digests are parseFrontmatter's
;; trimmed body (frontmatter.ts extractFrontmatter).

(defparameter +goal27-subagent-sample-files+
  '(("agents/planner.md"
     "452f21f65957753cec3b0772004209c108071be168e627fffd7191234c0ce64e"
     "d90239701e63b00eaa4b3a23dce17346373720ca67caeac15ff4a9e201c9e70f")
    ("agents/reviewer.md"
     "b5c3f13b67207e8e32de631f8cd52a373d9b956028e2f8c1fd8b737b5f239265"
     "88a453e530152024e2b3b9d886b5d14646bc8cee7b06711ac39740582e79ce07")
    ("agents/scout.md"
     "3b84e8e01c6e05c8dfbff1c845c0c6371f4f16350735d4d1dbd02bfa98b1d4e6"
     "295bd1bd97a4314b838aabea1db9a2599f3bb37c430582392bfa4234aca914a5")
    ("agents/worker.md"
     "ca2b2298fcbd8bfafcfe61977dc8075001a64b9c4d8c289c3b5eaa896efe6238"
     "167e04449b49cf5f2efa29a873a018c71685acf10ed68d540b20541738efcab4")
    ("prompts/implement.md"
     "65462de33c97ac1372cfed270dad9af164605b05028c069dd4c013ff9792675b"
     "bd5a312a13815476336d5700b9d0ad652156d528254fdc445adc6a009a3e0e4c")
    ("prompts/implement-and-review.md"
     "019ba4bf42d596ea03fc4564be5b2cc55a06227c95db19a4d5a5bb96697a75f9"
     "c46594919c8953684780307903e9720bbae67f95ab000bcec33acf782a1e45a3")
    ("prompts/scout-and-plan.md"
     "9506399391e0d2c71826c45f26cc332175dd964465f99a8bb880e109f8ed89f4"
     "83d3d19ba95465ef414dfe26dab1ebc7dc7247ddba6d1a834de25d454d0234c3")))

(defparameter +goal27-subagent-sample-agents+
  '(("planner"
     "Creates implementation plans from context and requirements"
     ("read" "grep" "find" "ls")
     "claude-sonnet-4-5"
     "You are a planning specialist."
     "Keep the plan concrete. The worker agent will execute it verbatim.")
    ("reviewer"
     "Code review specialist for quality and security analysis"
     ("read" "grep" "find" "ls" "bash")
     "claude-sonnet-4-5"
     "You are a senior code reviewer."
     "Be specific with file paths and line numbers.")
    ("scout"
     "Fast codebase recon that returns compressed context for handoff to other agents"
     ("read" "grep" "find" "ls" "bash")
     "claude-haiku-4-5"
     "You are a scout."
     "Which file to look at first and why.")
    ("worker"
     "General-purpose subagent with full capabilities, isolated context"
     nil
     "claude-sonnet-4-5"
     "You are a worker agent with full capabilities."
     "Key functions/types touched (short list)")))

(defun goal27-subagent-sample-root ()
  (merge-pathnames
   "examples/extensions/subagent/"
   (asdf:system-source-directory "cadr-cli")))

(defun goal27-sha256-file (path)
  (subseq
   (string-trim
    '(#\Newline #\Space)
    (uiop:run-program
     (list "sha256sum" (namestring path))
     :output :string))
   0 64))

(defun goal27-sha256-text (text)
  (uiop:with-temporary-file (:pathname path)
    (with-open-file (stream path
                            :direction :output
                            :if-exists :supersede
                            :external-format :utf-8)
      (write-string text stream))
    (goal27-sha256-file path)))

(defun goal27-sample-entry (relative)
  (find relative +goal27-subagent-sample-files+
        :key #'first :test #'string=))

(test goal27-subagent-example-files-match-v140-blobs
  (let ((root (goal27-subagent-sample-root)))
    (dolist (relative (mapcar #'first +goal27-subagent-sample-files+))
      (let* ((path (merge-pathnames relative root))
             (entry (goal27-sample-entry relative)))
        (is (probe-file path))
        (is (string= (second entry) (goal27-sha256-file path)) relative)))))

(test goal27-subagent-example-agents-discover-from-project-directory
  ;; v1.4.0 agents.ts loadAgentsFromDir. Project agents live under
  ;; .cadr/agents/ (CONFIG_DIR_NAME agents, product name cadr).
  (let ((root (goal27-subagent-sample-root)))
    (let ((*package* (find-package '#:cadr-cli/tests)))
      (load (merge-pathnames
             "examples/extensions/subagent/agents.lisp"
             (asdf:system-source-directory "cadr-cli"))))
    (with-test-directory (directory)
      (let ((agents-directory (merge-pathnames ".cadr/agents/" directory))
            (nested (merge-pathnames "src/deep/" directory)))
        (ensure-directories-exist (merge-pathnames "anchor" nested))
        (dolist (name '("planner" "reviewer" "scout" "worker"))
          (let ((destination
                  (merge-pathnames
                   (format nil "~A.md" name) agents-directory)))
            (ensure-directories-exist destination)
            (uiop:copy-file
             (merge-pathnames (format nil "agents/~A.md" name) root)
             destination)))
        (let* ((result
                 (funcall (symbol-function 'discover-subagents)
                          nested :project))
               (agents (getf result :agents)))
          (is (= 4 (length agents)))
          (is (search ".cadr/agents/"
                      (getf result :project-agents-directory)))
          (dolist (expected +goal27-subagent-sample-agents+)
            (let* ((name (first expected))
                   (agent (find name agents
                                :key (lambda (item) (getf item :name))
                                :test #'string=))
                   (prompt (getf agent :system-prompt))
                   (trimmed
                     (string-trim
                      '(#\Space #\Tab #\Newline #\Return)
                      prompt))
                   (entry
                     (goal27-sample-entry
                      (format nil "agents/~A.md" name))))
              (is (string= (second expected) (getf agent :description))
                  name)
              (is (equal (third expected) (getf agent :tools)) name)
              (is (string= (fourth expected) (getf agent :model)) name)
              (is (eq :project (getf agent :source)) name)
              (is (search (fifth expected) trimmed) name)
              (is (search (sixth expected) trimmed) name)
              (is (string= (third entry) (goal27-sha256-text trimmed))
                  name))))))))

(test goal27-subagent-example-chain-prompts-expand-arguments
  ;; v1.4.0 prompt-templates.ts substituteArgs. $@ is the joined
  ;; arguments. {previous} is text for the model, not a template slot.
  (let* ((root (goal27-subagent-sample-root))
         (query "refactor auth to support OAuth"))
    (multiple-value-bind (templates diagnostics)
        (cadr-agent:load-prompt-templates
         (merge-pathnames "prompts/" root))
      (is (null diagnostics))
      (is (= 3 (length templates)))
      (dolist (spec
               '(("implement"
                  "Full implementation workflow - scout gathers context, planner creates plan, worker implements"
                  "find all code relevant to: refactor auth to support OAuth"
                  "implementation plan for \"refactor auth to support OAuth\""
                  "use the \"worker\" agent to implement the plan"
                  nil)
                 ("implement-and-review"
                  "Worker implements, reviewer reviews, worker applies feedback"
                  "use the \"worker\" agent to implement: refactor auth to support OAuth"
                  "use the \"reviewer\" agent to review the implementation"
                  "use the \"worker\" agent to apply the feedback"
                  nil)
                 ("scout-and-plan"
                  "Scout gathers context, planner creates implementation plan (no implementation)"
                  "find all code relevant to: refactor auth to support OAuth"
                  "implementation plan for \"refactor auth to support OAuth\""
                  "Do NOT implement - just return the plan."
                  t)))
        (let* ((name (first spec))
               (template
                 (find name templates
                       :key #'cadr-agent:prompt-template-name
                       :test #'string=))
               (content (cadr-agent:prompt-template-content template))
               (expanded
                 (cadr-agent::substitute-prompt-arguments
                  content (list query)))
               (entry
                 (goal27-sample-entry
                  (format nil "prompts/~A.md" name))))
          (is (string= (second spec)
                       (cadr-agent:prompt-template-description template))
              name)
          (is (search "$@" content) name)
          (is (search "{previous}" content) name)
          (is (string= (third entry) (goal27-sha256-text content)) name)
          (is (not (search "$@" expanded)) name)
          (is (search "{previous}" expanded) name)
          (is (search (third spec) expanded) name)
          (is (search (fourth spec) expanded) name)
          (is (search (fifth spec) expanded) name)
          (let ((scout (search "\"scout\"" expanded))
                (planner (search "\"planner\"" expanded))
                (reviewer (search "\"reviewer\"" expanded))
                (implement (search "to implement:" expanded))
                (apply (search "to apply the feedback" expanded)))
            (cond
              ((string= name "implement")
               (is (and scout planner (< scout planner)))
               (is (search "\"worker\"" expanded :start2 planner)))
              ((string= name "implement-and-review")
               (is (and implement reviewer apply
                        (< implement reviewer apply))))
              ((string= name "scout-and-plan")
               (is (and scout planner (< scout planner)))
               (is (not (search "\"worker\"" expanded)))))))))))
