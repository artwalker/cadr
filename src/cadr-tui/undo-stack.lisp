(in-package #:cadr-tui)

(defstruct (undo-stack
            (:constructor make-undo-stack ()))
  (entries nil :type list))

(defun undo-stack-push (stack state)
  (push (copy-tree state)
        (undo-stack-entries stack))
  stack)

(defun undo-stack-pop (stack)
  (pop (undo-stack-entries stack)))

(defun undo-stack-clear (stack)
  (setf (undo-stack-entries stack) nil)
  stack)

(defun undo-stack-length (stack)
  (length (undo-stack-entries stack)))
