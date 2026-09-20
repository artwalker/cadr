(in-package #:cadr-cli)

(defparameter +system-prompt-section-name+
  (cl-ppcre:create-scanner "^[a-z][a-z0-9_-]*$"))

(defparameter +default-system-prompt-preamble+
  "You are an expert coding assistant operating inside cadr, a coding agent harness. You help users by reading files, executing commands, editing code, and writing new files.")

(defun copy-alist-string-lists (alist)
  (mapcar
   (lambda (pair)
     (cons (car pair) (copy-list (cdr pair))))
   alist))

(defun normalize-build-system-prompt-options
    (&key
       custom-prompt
       (force-system-prompt nil force-system-prompt-p)
       (selected-tools nil selected-tools-p)
       tool-snippets
       tool-guidelines
       prompt-guidelines
       append-system-prompt
       sections
       cwd
       context-files
       skills
       (readme-path nil readme-path-p)
       (docs-directory nil docs-directory-p)
       (examples-directory nil examples-directory-p))
  (list*
   :custom-prompt custom-prompt
   :selected-tools
   (copy-list
    (if selected-tools-p
        selected-tools
        '("read" "bash" "edit" "write")))
   :tool-snippets (copy-alist tool-snippets)
   :tool-guidelines (copy-alist-string-lists tool-guidelines)
   :prompt-guidelines (copy-list prompt-guidelines)
   :append-system-prompt (or append-system-prompt "")
   :sections (copy-alist sections)
   :cwd cwd
   :context-files
   (mapcar
    (lambda (file)
      (if (and (listp file) (keywordp (first file)))
          (copy-list file)
          file))
    (or context-files '()))
   :skills (copy-list skills)
   (append
    (when force-system-prompt-p
      (list :force-system-prompt force-system-prompt))
    (when readme-path-p
      (list :readme-path readme-path))
    (when docs-directory-p
      (list :docs-directory docs-directory))
    (when examples-directory-p
      (list :examples-directory examples-directory)))))

(defun system-prompt-rule-lines
    (selected-tools &key tool-guidelines prompt-guidelines)
  (let ((rules nil)
        (seen (make-hash-table :test #'equal)))
    (flet ((add-rule (rule)
             (let ((normalized
                     (string-trim
                      '(#\Space #\Tab #\Newline #\Return)
                      rule)))
               (when (and
                      (plusp (length normalized))
                      (not (gethash normalized seen)))
                 (setf (gethash normalized seen) t)
                 (push normalized rules)))))
      (let ((has-bash
              (member "bash" selected-tools :test #'string=))
            (has-powershell
              (member "powershell" selected-tools
                      :test #'string=))
            (has-file-ops
              (intersection
               '("grep" "find" "ls")
               selected-tools
               :test #'string=)))
        (when (and (or has-bash has-powershell)
                   (not has-file-ops))
          (cond
            ((and has-bash has-powershell)
             (add-rule
              "Use bash or PowerShell for file operations like listing, searching, and finding files"))
            (has-powershell
             (add-rule
              "Use PowerShell for file operations like listing, searching, and finding files"))
            (t
             (add-rule
              "Use bash for file operations like ls, rg, find")))))
      (dolist (name selected-tools)
        (dolist (rule
                 (cdr (assoc name tool-guidelines
                             :test #'string=)))
          (add-rule rule)))
      (dolist (rule prompt-guidelines)
        (add-rule rule))
      (add-rule "Be concise in your responses")
      (add-rule "Show file paths clearly when working with files"))
    (nreverse rules)))

(defun system-prompt-tools-listing (selected-tools tool-snippets)
  (let ((described
          (remove-if-not
           (lambda (name)
             (assoc name tool-snippets :test #'string=))
           selected-tools)))
    (if described
        (format
         nil "~{~A~^~%~}"
         (mapcar
          (lambda (name)
            (format
             nil "- ~A: ~A"
             name
             (cdr (assoc name tool-snippets
                         :test #'string=))))
          described))
        "(none)")))

(defun system-prompt-tools-section-body
    (selected-tools tool-snippets)
  (format
   nil
   "~A~%~%In addition to the tools above, you may have access to other custom tools depending on the project."
   (system-prompt-tools-listing selected-tools tool-snippets)))

(defun system-prompt-docs-section-body
    (readme-path docs-directory examples-directory)
  (format
   nil
   "Cadr documentation (read only when the user asks about cadr itself, its SDK, extensions, themes, skills, or TUI):
- Main documentation: ~A
- Additional docs: ~A
- Examples: ~A (extensions, custom tools, SDK)
- When reading cadr docs or examples, resolve docs/... under Additional docs and examples/... under Examples, not the current working directory
- When asked about: extensions (docs/extensions.md, examples/extensions/), themes (docs/themes.md), skills (docs/skills.md), prompt templates (docs/prompt-templates.md), TUI components (docs/tui.md), keybindings (docs/keybindings.md), SDK integrations (docs/sdk.md), custom providers (docs/custom-provider.md), adding models (docs/models.md), cadr packages (docs/packages.md), environment variables (docs/environment-variables.md)
- When working on cadr topics, read the docs and examples, and follow .md cross-references before implementing
- Always read cadr .md files completely and follow links to related docs (e.g., tui.md for TUI API details)"
   readme-path docs-directory examples-directory))

(defun system-prompt-context-file-path (context)
  (if (and (listp context) (keywordp (first context)))
      (getf context :path)
      context))

(defun system-prompt-context-file-content (context)
  (if (and (listp context) (keywordp (first context)))
      (getf context :content)
      (uiop:read-file-string context :external-format :utf-8)))

(defun system-prompt-project-context-body (context-files)
  (format
   nil
   "Project-specific instructions and guidelines:~%~%~{~A~^~%~%~}"
   (mapcar
    (lambda (context)
      (format
       nil
       "<project_instructions path=\"~A\">~%~A~%</project_instructions>"
       (system-prompt-context-file-path context)
       (system-prompt-context-file-content context)))
    context-files)))

(defun system-prompt-normalize-cwd (cwd)
  (substitute #\/ #\\ (or cwd ".")))

(defun valid-system-prompt-section-name-p (name)
  (and (stringp name)
       (not (string= name "preamble"))
       (cl-ppcre:scan +system-prompt-section-name+ name)))

(defun wrap-system-prompt-section (name text)
  (if (string= name "preamble")
      text
      (format nil "<~A>~%~A~%</~A>" name text name)))

(defun build-system-prompt-sections
    (&key
       custom-prompt
       (selected-tools nil selected-tools-p)
       tool-snippets
       tool-guidelines
       prompt-guidelines
       append-system-prompt
       sections
       cwd
       context-files
       skills
       (readme-path nil readme-path-p)
       (docs-directory nil docs-directory-p)
       (examples-directory nil examples-directory-p)
       &allow-other-keys)
  (let* ((selected
           (copy-list
            (if selected-tools-p
                selected-tools
                '("read" "bash" "edit" "write"))))
         (snippets (copy-alist tool-snippets))
         (guidelines-by-tool
           (copy-alist-string-lists tool-guidelines))
         (prompt-rules (copy-list prompt-guidelines))
         (addendum (or append-system-prompt ""))
         (custom-sections (copy-alist sections))
         (files
           (mapcar
            (lambda (file)
              (if (and (listp file) (keywordp (first file)))
                  (copy-list file)
                  file))
            (or context-files '())))
         (skill-list (copy-list skills))
         (cli-root (cadr-ai::cadr-cli-source-directory))
         (readme
           (if readme-path-p
               readme-path
               (merge-pathnames "README.md" cli-root)))
         (docs
           (if docs-directory-p
               docs-directory
               (cadr-ai::cadr-docs-directory)))
         (examples
           (if examples-directory-p
               examples-directory
               (merge-pathnames "examples/" cli-root)))
         (raw nil))
    (dolist (pair custom-sections)
      (let ((name (car pair)))
        (unless (valid-system-prompt-section-name-p name)
          (error "Invalid system prompt section name: ~A"
                 name))))
    (flet ((push-section (name text)
             (push (cons name text) raw)))
      (if custom-prompt
          (push-section "preamble" custom-prompt)
          (progn
            (push-section "preamble" +default-system-prompt-preamble+)
            (push-section
             "tools"
             (system-prompt-tools-section-body selected snippets))
            (push-section
             "rules"
             (format
              nil "~{- ~A~^~%~}"
              (system-prompt-rule-lines
               selected
               :tool-guidelines guidelines-by-tool
               :prompt-guidelines prompt-rules)))
            (push-section
             "docs"
             (system-prompt-docs-section-body
              readme docs examples))))
      (when (plusp (length addendum))
        (push-section "addendum" addendum))
      (when files
        (push-section
         "project_context"
         (system-prompt-project-context-body files)))
      (let ((skill-file-read-tool
              (cond
                ((member "read" selected :test #'string=) :read)
                ((member "bash" selected :test #'string=) :bash)
                (t nil))))
        (when (and skill-file-read-tool skill-list)
          (let ((skills-prompt
                  (string-trim
                   '(#\Space #\Tab #\Newline #\Return)
                   (cadr-agent:format-skills-for-system-prompt
                    skill-list skill-file-read-tool))))
            (when (plusp (length skills-prompt))
              (push-section "skills" skills-prompt)))))
      (push-section "cwd" (system-prompt-normalize-cwd cwd))
      (dolist (pair custom-sections)
        (let ((name (car pair))
              (content (cdr pair)))
          (when (and content (plusp (length content)))
            (push-section name content)))))
    (mapcar
     (lambda (pair)
       (cons (car pair)
             (wrap-system-prompt-section
              (car pair) (cdr pair))))
     (nreverse raw))))

(defun build-system-prompt-state
    (&rest args
     &key (force-system-prompt nil force-system-prompt-p)
     &allow-other-keys)
  (if force-system-prompt-p
      (list :content force-system-prompt)
      (list :content ""
            :sections
            (apply #'build-system-prompt-sections args))))

(defun diff-system-prompt-sections (previous current)
  (let ((patch nil)
        (seen (make-hash-table :test #'equal)))
    (dolist (pair current)
      (let* ((name (car pair))
             (text (cdr pair))
             (prior (assoc name previous :test #'string=)))
        (setf (gethash name seen) t)
        (unless (and prior (equal (cdr prior) text))
          (push (cons name text) patch))))
    (dolist (pair previous)
      (let ((name (car pair)))
        (unless (gethash name seen)
          (push (cons name nil) patch))))
    (when patch
      (nreverse patch))))

(defun prepare-prompt-and-tool-loadout
    (options messages tool-lookup)
  (let* ((selected-names
           (remove-duplicates
            (remove-if-not
             (lambda (name)
               (and (stringp name)
                    (funcall tool-lookup name)))
             (copy-list
              (getf options :selected-tools)))
            :test #'string=))
         (selected-tools
           (mapcar
            (lambda (name) (funcall tool-lookup name))
            selected-names))
         (previous
           (let ((message
                   (cadr-ai:get-current-system-message
                    messages)))
             (if message
                 (cadr-ai:system-message-sections message)
                 nil)))
         (current
           (apply #'build-system-prompt-sections options))
         (patch
           (diff-system-prompt-sections previous current)))
    (values
     (when patch
       (cadr-ai:make-system-message
        :content ""
        :sections patch
        :timestamp (cadr-ai::unix-milliseconds)))
     selected-tools)))

(defun apply-prepare-prompt-and-tool-loadout
    (agent options messages)
  (let ((by-name (make-hash-table :test #'equal)))
    (dolist
        (tool
         (cadr-agent::merged-agent-tools agent))
      (setf
       (gethash (cadr-ai:tool-name tool) by-name)
       tool))
    (multiple-value-bind (update selected)
        (prepare-prompt-and-tool-loadout
         options
         messages
         (lambda (name) (gethash name by-name)))
      (setf
       (cadr-agent::agent-tool-registry agent)
       (cadr-agent:make-tool-registry selected))
      update)))

(defun build-system-prompt
    (&key
       (selected-tools nil selected-tools-p)
       tool-snippets
       tool-guidelines
       prompt-guidelines context-files
       skills cwd custom-prompt
       append-system-prompt
       (readme-path nil readme-path-p)
       (docs-directory nil docs-directory-p)
       (examples-directory nil examples-directory-p))
  (let ((selected
          (if selected-tools-p
              selected-tools
              '("read" "bash" "edit" "write"))))
    (with-output-to-string (output)
      (if custom-prompt
          (write-string custom-prompt output)
          (let* ((cli-root (cadr-ai::cadr-cli-source-directory))
                 (readme-path
                   (if readme-path-p
                       readme-path
                       (merge-pathnames "README.md" cli-root)))
                 (docs-directory
                   (if docs-directory-p
                       docs-directory
                       (cadr-ai::cadr-docs-directory)))
                 (examples-directory
                   (if examples-directory-p
                       examples-directory
                       (merge-pathnames "examples/" cli-root)))
                 (guidelines
                   (system-prompt-rule-lines
                    selected
                    :tool-guidelines tool-guidelines
                    :prompt-guidelines prompt-guidelines)))
            (write-string +default-system-prompt-preamble+ output)
            (terpri output)
            (terpri output)
            (format output "Available tools:~%")
            (let ((listing
                    (system-prompt-tools-listing
                     selected tool-snippets)))
              (if (string= listing "(none)")
                  (format output "(none)~%")
                  (format output "~A~%" listing)))
            (format
             output
             "~%In addition to the tools above, you may have access to other custom tools depending on the project.~%~%Guidelines:~%")
            (dolist (guideline guidelines)
              (format output "- ~A~%" guideline))
            (format
             output "~%~A"
             (system-prompt-docs-section-body
              readme-path docs-directory
              examples-directory))))
      (when append-system-prompt
        (format output "~%~%~A"
                append-system-prompt))
      (when context-files
        (format
         output
         "~%~%<project_context>~%~%~A~%"
         (system-prompt-project-context-body context-files))
        (format output "</project_context>~%"))
      (let ((skill-file-read-tool
              (cond
                ((member "read" selected :test #'string=) :read)
                ((member "bash" selected :test #'string=) :bash)
                (t nil))))
        (when (and skill-file-read-tool skills)
          (write-string
           (cadr-agent:format-skills-for-system-prompt
            skills skill-file-read-tool)
           output)))
      (format output
              ;; Baseline v0.84.2 system-prompt.ts: the custom-prompt
              ;; branch (:69) ends the cwd line with a trailing newline;
              ;; the default branch (:159) does not.
              (if custom-prompt
                  "~%Current working directory: ~A~%"
                  "~%Current working directory: ~A")
              (or cwd ".")))))

(defun provider-header-table (headers)
  (let ((table
          (make-hash-table :test #'equalp)))
    (dolist (header headers table)
      (setf
       (gethash (car header) table)
       (cdr header)))))

(defun provider-header-alist (table)
  (let ((headers nil))
    (maphash
     (lambda (name value)
       (when value
         (push (cons name value)
               headers)))
     table)
    (nreverse headers)))

(defun make-extension-aware-stream-function
    (extension-host
     &key
       (stream-function #'cadr-ai:stream-chat)
       session-id
       (telemetry-p t))
  (lambda
      (provider model context on-event
       &rest options)
    (let ((request-options (copy-list options))
          (callbacks
            (list
             :on-payload
             (lambda (payload callback-model)
               (declare (ignore callback-model))
               (values
                (if extension-host
                    (cadr-agent::run-extension-lifecycle-hooks
                     extension-host
                     :before-provider-request
                     :payload
                     (list :payload payload))
                    payload)
                t))
             :transform-headers
             (lambda (request-headers)
               (let* ((merged
                        (provider-attribution-headers
                         :provider
                         (cadr-ai:model-provider model)
                         :base-url
                         (cadr-ai:model-base-url model)
                         :telemetry-p telemetry-p
                         :session-id session-id
                         :request-headers
                         request-headers))
                      (table
                        (provider-header-table
                         merged)))
                 (when extension-host
                   (cadr-agent::run-extension-lifecycle-hooks
                    extension-host
                    :before-provider-headers
                    :payload
                    (list :headers table)))
                 (provider-header-alist table)))
             :on-response
             (lambda (response callback-model)
               (declare (ignore callback-model))
               (when extension-host
                 (cadr-agent::run-extension-lifecycle-hooks
                  extension-host
                  :after-provider-response
                  :payload response))))))
      (when (and session-id
                 (null (getf request-options :session-id)))
        (setf (getf request-options :session-id)
              session-id))
      (apply
       stream-function
       provider model context on-event
       (append request-options callbacks)))))

;;; In-process SDK service facades.  These objects deliberately wrap the same
;;; settings, resource, auth, and model services used by the CLI; they do not
;;; invoke the command-line entry point or start a child cadr process.
