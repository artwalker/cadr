(in-package #:pi-cli/tests)
(in-suite pi-cli-suite)

(test native-image-options-omit-unsupported-compression-keyword
  (let ((without
          (pi-cli::native-image-save-arguments
           '(:sbcl :linux)))
        (with
          (pi-cli::native-image-save-arguments
           '(:sbcl :linux :sb-core-compression))))
    (is (eq #'pi-cli:executable-main
            (getf without :toplevel)))
    (is (eq t (getf without :executable)))
    (is (eq t (getf without :save-runtime-options)))
    (is (not (member :compression without)))
    (is (eq t (getf with :compression)))))
