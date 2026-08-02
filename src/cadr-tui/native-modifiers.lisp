(in-package #:cadr-tui)

(defconstant +native-modifier-shift-mask+ #x00020000)
(defconstant +native-modifier-control-mask+ #x00040000)
(defconstant +native-modifier-option-mask+ #x00080000)
(defconstant +native-modifier-command-mask+ #x00100000)

(defun native-modifier-mask (key)
  (flet ((named-p (name)
           (or (eq key name)
               (and (stringp key)
                    (string-equal key
                                  (symbol-name name))))))
    (cond
      ((named-p :shift) +native-modifier-shift-mask+)
      ((named-p :control) +native-modifier-control-mask+)
      ((named-p :option) +native-modifier-option-mask+)
      ((named-p :command) +native-modifier-command-mask+))))

(defun supported-darwin-modifier-architecture-p (machine)
  (not
   (null
    (member (string-downcase machine)
            '("arm64" "aarch64" "x86-64" "x86_64" "amd64")
            :test #'string=))))

#+(and sbcl darwin)
(defvar *core-graphics-load-state* :unloaded)

#+(and sbcl darwin)
(sb-alien:define-alien-routine
    ("CGEventSourceFlagsState"
     %cg-event-source-flags-state)
    sb-alien:unsigned-long-long
  (state sb-alien:int))

#+(and sbcl darwin)
(defun ensure-core-graphics-loaded-p ()
  (case *core-graphics-load-state*
    (:loaded t)
    (:unavailable nil)
    (otherwise
     (setf *core-graphics-load-state*
           (handler-case
               (progn
                 (sb-alien:load-shared-object
                  "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics")
                 :loaded)
             (condition () :unavailable)))
     (eq :loaded *core-graphics-load-state*))))

(defun darwin-native-modifier-flags ()
  #+(and sbcl darwin)
  (when (ensure-core-graphics-loaded-p)
    (handler-case
        (%cg-event-source-flags-state 0)
      (condition () nil)))
  #-(and sbcl darwin)
  nil)

(defun native-modifier-pressed-p
    (key macos-p machine flags-function)
  (let ((mask (native-modifier-mask key)))
    (and mask
         macos-p
         (supported-darwin-modifier-architecture-p machine)
         (handler-case
             (let ((flags (funcall flags-function)))
               (and (integerp flags)
                    (logtest mask flags)))
           (condition () nil)))))

(defun is-native-modifier-pressed (key)
  (native-modifier-pressed-p
   key
   (uiop:os-macosx-p)
   (machine-type)
   #'darwin-native-modifier-flags))
