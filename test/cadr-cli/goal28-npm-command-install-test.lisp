(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(test goal28-npm-command-reaches-package-install-runner
  (with-test-directory (root)
    (let* ((agent (merge-pathnames "agent/" root))
           (cwd (merge-pathnames "cwd/" root))
           (captured nil)
           (npm-root
             (merge-pathnames "npm/" agent))
           (dest
             (merge-pathnames
              "node_modules/@scope/pkg/"
              npm-root))
           (runner
             (lambda (argv)
               (setf captured argv)
               (ensure-directories-exist dest)
               (write-text
                (merge-pathnames "extension.lisp" dest)
                "(define-command \"npm-pkg\" :handler (lambda (a c) (declare (ignore a c))))")
               0))
           (_
             (progn
               (ensure-directories-exist agent)
               (ensure-directories-exist cwd)
               (write-text
                (merge-pathnames "settings.json" agent)
                "{\"npmCommand\":[\"mise\",\"exec\",\"node@20\",\"--\",\"npm\"]}")))
           (out (make-string-output-stream))
           (err (make-string-output-stream)))
      (declare (ignore _))
      (multiple-value-bind (handled exit)
          (cadr-cli::handle-package-command
           '("install" "npm:@scope/pkg")
           :cwd cwd
           :agent-directory agent
           :output out
           :error-output err
           :runner runner)
        (is (eq t handled))
        (is (= 0 exit))
        (is (equal
             (list
              "mise" "exec" "node@20" "--" "npm"
              "install"
              "--prefix"
              (namestring
               (uiop:ensure-directory-pathname
                npm-root))
              "--no-save"
              "--legacy-peer-deps"
              "@scope/pkg")
             captured))
        (is (probe-file
             (merge-pathnames
              "settings.json" agent)))
        (let* ((manager
                 (cadr-cli::make-settings-manager
                  :global-path
                  (merge-pathnames
                   "settings.json" agent)))
               (entries
                 (cadr-cli::settings-package-entries
                  manager :global)))
          (is (equal
               '("npm:@scope/pkg")
               (mapcar
                #'cadr-cli::package-entry-source
                entries))))))))
