(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defun goal28-markdown-indent-live-plain-lines (lines)
  (mapcar
   (lambda (line)
     (string-right-trim
      " "
      (cadr-tui:strip-terminal-sequences line)))
   lines))

(test goal28-markdown-indent-live-reaches-transcript
  (with-test-directory (root)
    (let* ((global (merge-pathnames "settings.json" root))
           (_
             (write-text
              global
              "{\"markdown\":{\"codeBlockIndent\":\">>>>\"}}"))
           (manager
             (cadr-cli::make-settings-manager
              :global-path global))
           (present-indent
             (cadr-cli::settings-markdown-code-block-indent
              manager))
           (source (format nil "```ts~%const x = 1;~%```"))
           (assistant
             (cadr-cli::make-tui-entry
              :type :assistant
              :text source
              :content-blocks
              (list (cons :assistant source))))
           (user
             (cadr-cli::make-tui-entry
              :type :user
              :text source))
           (assistant-lines
             (goal28-markdown-indent-live-plain-lines
              (cadr-cli::render-tui-entry
               assistant 80
               :code-block-indent present-indent)))
           (user-lines
             (goal28-markdown-indent-live-plain-lines
              (cadr-cli::render-tui-entry
               user 80
               :code-block-indent present-indent)))
           (absent-lines
             (goal28-markdown-indent-live-plain-lines
              (cadr-cli::render-tui-entry
               (cadr-cli::make-tui-entry
                :type :assistant
                :text source
                :content-blocks
                (list (cons :assistant source)))
               80))))
      (declare (ignore _))
      (is (string= ">>>>" present-indent))
      (is (equal " >>>>const x = 1;"
                 (find " >>>>const x = 1;" assistant-lines
                       :test #'string=)))
      (is (equal " >>>>const x = 1;"
                 (find " >>>>const x = 1;" user-lines
                       :test #'string=)))
      (is (equal "   const x = 1;"
                 (find "   const x = 1;" absent-lines
                       :test #'string=))))))
