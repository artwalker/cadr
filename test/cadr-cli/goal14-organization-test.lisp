(in-package #:cadr-cli/tests)

(in-suite cadr-cli-suite)

(defun goal14-b1-source (root relative)
  (let ((path (merge-pathnames relative root)))
    (and (probe-file path)
         (uiop:read-file-string path))))

(test goal14-b1-interactive-leaf-services-have-exact-owners
  (let* ((root (asdf:system-source-directory "cadr-cli"))
         (owners
           '(("src/cadr-cli/interactive/transcript.lisp"
              "(defun render-user-message-lines"
              "(defun render-assistant-message-lines")
             ("src/cadr-cli/interactive/status.lisp"
              "(defstruct (status-log"
              "(defun maybe-anthropic-subscription-warning")
             ("src/cadr-cli/interactive/footer.lisp"
              "(defun format-cwd-for-footer"
              "(defun footer-data-provider-dispose")
             ("src/cadr-cli/interactive/theme.lisp"
              "(defstruct theme-detection"
              "(defun load-theme-summaries")
             ("src/cadr-cli/interactive/images.lisp"
              "(defstruct image-process-result"
              "(defun process-image-file")
             ("src/cadr-cli/interactive/clipboard.lisp"
              "(defun clipboard-command-candidates"
              "(defun read-clipboard-image")
             ("src/cadr-cli/interactive/syntax.lisp"
              "(defparameter +syntax-highlight-languages+"
              "(defun simple-syntax-highlight")
             ("src/cadr-cli/interactive/tool-render-session.lisp"
              "(defstruct (tool-render-session"
              "(defun render-tool-session")))
         (legacy
           (uiop:read-file-string
            (merge-pathnames
             "src/cadr-cli/interactive-services.lisp" root))))
    (dolist (owner owners)
      (let ((source (goal14-b1-source root (first owner))))
        (is (not (null source)) "missing B1 owner ~A" (first owner))
        (when source
          (dolist (marker (rest owner))
            (is (search marker source)
                "~A does not own ~A" (first owner) marker)))))
    (dolist (marker
             (mapcan (lambda (owner) (copy-list (rest owner))) owners))
      (is (not (search marker legacy))
          "interactive-services still owns ~A" marker))
    (dolist (selector
             '("(defun render-session-selector"
               "(defun render-tree-selector"
               "(defun render-settings-selector"
               "(defun render-oauth-selector"
               "(defun render-model-selector"))
      (is (search selector legacy)
          "B1 moved selector code before selector-frame convergence: ~A"
          selector))))

(test goal14-b1-asdf-loads-leaf-owners-before-selector-consumers
  (let* ((root (asdf:system-source-directory "cadr-cli"))
         (source
           (uiop:read-file-string
            (merge-pathnames "cadr-cli.asd" root)))
         (ordered
           '("(:file \"media\")"
             "(:module \"interactive\""
             "(:file \"transcript\")"
             "(:file \"status\")"
             "(:file \"footer\")"
             "(:file \"theme\")"
             "(:file \"images\")"
             "(:file \"clipboard\")"
             "(:file \"syntax\")"
             "(:file \"tool-render-session\")"
             "(:file \"interactive-services\")"
             "(:file \"truncation\")"))
         (positions (mapcar (lambda (marker) (search marker source)) ordered)))
    (is (every #'identity positions)
        "cadr-cli.asd omits a B1 load boundary: ~S"
        (loop for marker in ordered
              for position in positions
              unless position collect marker))
    (when (every #'identity positions)
      (is (every #'< positions (rest positions))
          "B1 owner load order is not dependency-safe: ~S" positions))))
