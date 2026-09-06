(in-package #:cadr-cli)

(defun dedupe-prompt-guidelines (guidelines)
  (let ((seen (make-hash-table :test #'equal))
        (result nil))
    (dolist (guideline guidelines)
      (let ((trimmed
              (string-trim
               '(#\Space #\Tab #\Newline #\Return)
               guideline)))
        (when (and
               (plusp (length trimmed))
               (not (gethash trimmed seen)))
          (setf (gethash trimmed seen) t)
          (push trimmed result))))
    (nreverse result)))

(defun build-system-prompt
    (&key
       (selected-tools nil selected-tools-p)
       tool-snippets
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
                 (described
                   (remove-if-not
                    (lambda (name)
                      (assoc name tool-snippets
                             :test #'string=))
                    selected))
                 (guidelines
                   (dedupe-prompt-guidelines
                    (append
                     (when
                         (and
                          (member "bash" selected
                                  :test #'string=)
                          (not
                           (intersection
                            '("grep" "find" "ls")
                            selected
                            :test #'string=)))
                       (list
                        "Use bash for file operations like ls, rg, find"))
                     prompt-guidelines
                     (list
                      "Be concise in your responses"
                      "Show file paths clearly when working with files")))))
            (write-string
             "You are an expert coding assistant operating inside cadr, a coding agent harness. You help users by reading files, executing commands, editing code, and writing new files."
             output)
            (terpri output)
            (terpri output)
            (format output "Available tools:~%")
            (if described
                (dolist (name described)
                  (format
                   output "- ~A: ~A~%"
                   name
                   (cdr
                    (assoc name tool-snippets
                           :test #'string=))))
                (format output "(none)~%"))
            (format
             output
             "~%In addition to the tools above, you may have access to other custom tools depending on the project.~%~%Guidelines:~%")
            (dolist (guideline guidelines)
              (format output "- ~A~%" guideline))
            (format
             output
             "~%Cadr documentation (read only when the user asks about cadr itself, its SDK, extensions, themes, skills, or TUI):~%- Main documentation: ~A~%- Additional docs: ~A~%- Examples: ~A (extensions, custom tools, SDK)~%"
             readme-path docs-directory
             examples-directory)
            (format
             output
             "- When reading cadr docs or examples, resolve docs/... under Additional docs and examples/... under Examples, not the current working directory~%- When asked about: extensions (docs/extensions.md, examples/extensions/), themes (docs/themes.md), skills (docs/skills.md), prompt templates (docs/prompt-templates.md), TUI components (docs/tui.md), keybindings (docs/keybindings.md), SDK integrations (docs/sdk.md), custom providers (docs/custom-provider.md), adding models (docs/models.md), cadr packages (docs/packages.md), environment variables (docs/environment-variables.md)~%- When working on cadr topics, read the docs and examples, and follow .md cross-references before implementing~%- Always read cadr .md files completely and follow links to related docs (e.g., tui.md for TUI API details)")))
      (when append-system-prompt
        (format output "~%~%~A"
                append-system-prompt))
      (when context-files
        (format
         output
         "~%~%<project_context>~%~%Project-specific instructions and guidelines:~%~%")
        (dolist (context context-files)
          (let* ((path
                   (if (listp context)
                       (getf context :path)
                       context))
                 (content
                   (if (listp context)
                       (getf context :content)
                       (uiop:read-file-string
                        path :external-format :utf-8))))
            (format
             output
             "<project_instructions path=\"~A\">~%~A~%</project_instructions>~%~%"
             path content)))
        (format output "</project_context>~%"))
      (when
          (and
           (member "read" selected
                   :test #'string=)
           skills)
        (write-string
         (cadr-agent:format-skills-for-system-prompt
          skills)
         output))
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
