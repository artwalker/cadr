(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(test goal28-packages-settings-reach-configured-records
  (with-test-directory (root)
    (let* ((agent (merge-pathnames "agent/" root))
           (project (merge-pathnames "project/" root))
           (global (merge-pathnames "settings.json" agent))
           (package
             (merge-pathnames "local-pkg/" root))
           (_
             (progn
               (ensure-directories-exist agent)
               (ensure-directories-exist project)
               (ensure-directories-exist package)
               (write-text
                (merge-pathnames "extension.lisp" package)
                "(define-command \"pkg\" :handler (lambda (a c) (declare (ignore a c))))")
               (write-text
                global
                (format
                 nil
                 "{\"packages\":[~S]}"
                 (namestring package)))))
           (manager
             (cadr-cli::make-settings-manager
              :global-path global
              :project-path
              (merge-pathnames "settings.json"
                               (merge-pathnames ".cadr/" project))
              :project-trusted-p t)))
      (declare (ignore _))
      (is (equal
           (list (namestring package))
           (mapcar
            #'cadr-cli::package-entry-source
            (cadr-cli::settings-package-entries
             manager :global))))
      (let ((records
              (cadr-cli::configured-package-records
               manager
               :global-base agent
               :project-base
               (merge-pathnames ".cadr/" project))))
        (is (= 1 (length records)))
        (is (eq :user (getf (first records) :scope)))
        (is (string=
             (namestring package)
             (getf (first records) :source)))))))
