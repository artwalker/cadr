(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(test goal28-image-settings-reach-existing-readers
  (let ((manager (cadr-cli::make-memory-settings-manager)))
    (is (eq t (cadr-cli::settings-auto-resize-images-p manager)))
    (is (not (cadr-cli::settings-block-images-p manager))))
  (let ((manager
          (cadr-cli::make-memory-settings-manager
           (args "images"
                 (args "autoResize" nil
                       "blockImages" t)))))
    (is (not (cadr-cli::settings-auto-resize-images-p manager)))
    (is (eq t (cadr-cli::settings-block-images-p manager))))
  (let ((manager
          (cadr-cli::make-memory-settings-manager
           (args "images" nil))))
    (is (eq t (cadr-cli::settings-auto-resize-images-p manager)))
    (is (not (cadr-cli::settings-block-images-p manager)))))
