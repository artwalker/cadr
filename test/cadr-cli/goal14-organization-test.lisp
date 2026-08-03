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
           (or
            (goal14-b1-source
             root "src/cadr-cli/interactive-services.lisp")
            (format
             nil "~{~A~^~%~}"
             (loop
               for family in
               '("sessions" "tree" "settings" "auth"
                 "models" "trust" "fork")
               collect
               (goal14-b1-source
                root
                (format
                 nil
                 "src/cadr-cli/interactive/selectors/~A.lisp"
                 family)))))))
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
             "(:module \"selectors\""
             "(:file \"common\")"
             "(:file \"sessions\")"
             "(:file \"tree\")"
             "(:file \"settings\")"
             "(:file \"auth\")"
             "(:file \"models\")"
             "(:file \"trust\")"
             "(:file \"fork\")"
             "(:file \"truncation\")"))
         (positions
           (let ((cursor 0))
             (loop for marker in ordered
                   for position = (search marker source :start2 cursor)
                   collect position
                   when position do (setf cursor (1+ position))))))
    (is (every #'identity positions)
        "cadr-cli.asd omits a B1 load boundary: ~S"
        (loop for marker in ordered
              for position in positions
              unless position collect marker))
    (when (every #'identity positions)
      (is (every #'< positions (rest positions))
          "B1 owner load order is not dependency-safe: ~S" positions))))

(test goal14-b2-selector-frame-owns-shared-selector-decisions
  (let* ((root (asdf:system-source-directory "cadr-cli"))
         (common
           (goal14-b1-source
            root "src/cadr-cli/interactive/selectors/common.lisp"))
         (families
           '("sessions" "tree" "settings" "auth"
             "models" "trust" "fork")))
    (is (not (null common)) "missing B2 selector-frame owner")
    (when common
      (dolist (marker
               '("(defstruct (selector-frame"
                 "(defun render-selector-frame"
                 "(defun selector-frame-visible-slice"
                 "(defun selector-frame-move-index"))
        (is (search marker common)
            "selector-frame owner omits ~A" marker)))
    (dolist (family families)
      (let* ((relative
               (format nil
                       "src/cadr-cli/interactive/selectors/~A.lisp"
                       family))
             (source (goal14-b1-source root relative)))
        (is (not (null source)) "missing B2 selector family ~A" relative)
        (when source
          (is (search "render-selector-frame" source)
              "~A bypasses selector-frame rendering" relative)
          (is (search "selector-frame-move-index" source)
              "~A retains local wrap-navigation policy" relative))))))

(test goal14-b2-selector-frame-wraps-and-centers-independently
  (let ((move (find-symbol "SELECTOR-FRAME-MOVE-INDEX" :cadr-cli))
        (slice (find-symbol "SELECTOR-FRAME-VISIBLE-SLICE" :cadr-cli)))
    (is (and move (fboundp move))
        "selector-frame wrap primitive is unavailable")
    (is (and slice (fboundp slice))
        "selector-frame viewport primitive is unavailable")
    (when (and move (fboundp move))
      (is (= 2 (funcall move 0 3 -1)))
      (is (= 0 (funcall move 2 3 1)))
      (is (= 0 (funcall move 0 0 -1))))
    (when (and slice (fboundp slice))
      (multiple-value-bind (visible start end total)
          (funcall slice '(a b c d e) 3 3)
        (is (equal '(c d e) visible))
        (is (= 2 start))
        (is (= 5 end))
        (is (= 5 total))))))
