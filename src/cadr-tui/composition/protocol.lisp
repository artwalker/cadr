(in-package #:cadr-tui)

(defparameter +cursor-marker+
  (format nil "~C_pi:c~C" #\Escape (code-char 7)))

(defclass component () ())

(defclass focusable-component (component)
  ((focused-p
    :initarg :focused-p
    :initform nil
    :accessor component-focused-p)))

(defgeneric component-render
    (component width &key focused-p))

(defgeneric component-handle-event (component event))
(defgeneric component-invalidate (component))
(defgeneric component-dispose (component))
(defgeneric component-wants-key-release-p (component))
(defgeneric component-focusable-p (component))

(defmethod component-render
    ((component component) width &key focused-p)
  (declare (ignore component width focused-p))
  nil)

(defmethod component-handle-event
    ((component component) event)
  (declare (ignore component event))
  (values nil nil))

(defmethod component-invalidate ((component component))
  component)

(defmethod component-dispose ((component component))
  component)

(defmethod component-wants-key-release-p
    ((component component))
  (declare (ignore component))
  nil)

(defmethod component-focusable-p ((component component))
  (typep component 'focusable-component))

(defmethod component-focused-p ((component component))
  (declare (ignore component))
  nil)

(defmethod (setf component-focused-p)
    (value (component component))
  (declare (ignore component))
  (not (null value)))

(defclass component-container (component)
  ((children
    :initarg :children
    :initform nil
    :accessor component-children)))

(defgeneric component-add-child (container child))
(defgeneric component-remove-child (container child))
(defgeneric component-clear (container))

(defun make-component-container (&rest children)
  (make-instance
   'component-container :children (copy-list children)))

(defmethod component-add-child
    ((container component-container) child)
  (setf
   (component-children container)
   (nconc (component-children container)
          (list child)))
  container)

(defmethod component-remove-child
    ((container component-container) child)
  (setf
   (component-children container)
   (remove child (component-children container)
           :test #'eq :count 1))
  container)

(defmethod component-clear
    ((container component-container))
  (setf (component-children container) nil)
  container)

(defmethod component-render
    ((container component-container) width &key focused-p)
  (declare (ignore focused-p))
  (loop for child in (component-children container)
        nconc
        (component-render
         child width
         :focused-p (component-focused-p child))))

(defmethod component-invalidate
    ((container component-container))
  (dolist (child (component-children container))
    (component-invalidate child))
  container)

(defmethod component-dispose
    ((container component-container))
  (dolist (child (component-children container))
    (component-dispose child))
  container)

(defun pad-component-line (line width)
  (multiple-value-bind (clipped used)
      (slice-to-width line width)
    (concatenate
     'string clipped
     (make-string
      (max 0 (- width used))
      :initial-element #\Space))))

(defun apply-component-background
    (line width background-function)
  (let ((padded (pad-component-line line width)))
    (if background-function
        (apply-restoring-style
         padded background-function)
        padded)))
