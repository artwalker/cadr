(in-package #:cadr-ai)

(defparameter +cadr-version+
  (asdf:component-version
   (asdf:find-system "cadr-ai")))

(defun cadr-version ()
  +cadr-version+)

(defparameter +cadr-aligned-pi-release+ "v0.83.0")
(defparameter +cadr-aligned-pi-distance+ 38)
(defparameter +cadr-aligned-pi-commit+ "74caa2649")

(defun cadr-release-identity ()
  (format
   nil
   "cadr ~A · aligned with pi ~A (+~D, ~A)"
   (cadr-version)
   +cadr-aligned-pi-release+
   +cadr-aligned-pi-distance+
   +cadr-aligned-pi-commit+))
