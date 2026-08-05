(in-package #:cadr-ai)

(defparameter +cadr-version+
  (asdf:component-version
   (asdf:find-system "cadr-ai")))

(defparameter +cadr-product-slug+ "cadr")
(defparameter +cadr-product-display-name+ "Cadr")
(defparameter +cadr-canonical-repository-url+
  "https://github.com/artwalker/cadr")
(defparameter +cadr-default-share-viewer-url+
  "https://cadr.dev/session/")

(defun cadr-product-slug ()
  +cadr-product-slug+)

(defun cadr-product-display-name ()
  +cadr-product-display-name+)

(defun cadr-canonical-repository-url ()
  +cadr-canonical-repository-url+)

(defun cadr-default-share-viewer-url ()
  +cadr-default-share-viewer-url+)

(defun cadr-changelog-url ()
  (format nil "~A/blob/main/CHANGELOG.md"
          (cadr-canonical-repository-url)))

(defun cadr-version ()
  +cadr-version+)

(defparameter +cadr-aligned-pi-release+ "v0.83.0")
(defparameter +cadr-aligned-pi-distance+ 38)
(defparameter +cadr-aligned-pi-commit+ "74caa2649")

(defun cadr-release-identity ()
  (format
   nil
   "~A ~A · aligned with pi ~A (+~D, ~A)"
   (cadr-product-slug)
   (cadr-version)
   +cadr-aligned-pi-release+
   +cadr-aligned-pi-distance+
   +cadr-aligned-pi-commit+))
