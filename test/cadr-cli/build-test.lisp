(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(test native-image-options-omit-unsupported-compression-keyword
  (let ((without
          (cadr-cli::native-image-save-arguments
           '(:sbcl :linux)))
        (with
          (cadr-cli::native-image-save-arguments
           '(:sbcl :linux :sb-core-compression))))
    (is (eq #'cadr-cli:executable-main
            (getf without :toplevel)))
    (is (eq t (getf without :executable)))
    (is (eq t (getf without :save-runtime-options)))
    (is (not (member :compression without)))
    (is (eq t (getf with :compression)))))
