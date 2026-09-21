(in-package #:cadr-cli/tests)

(in-suite cadr-cli-suite)

;;; pi #8919 / f53ac1135: custom footer with zero rendered rows must not
;;; reserve a blank frame row. cadr has no flex minSize; render-tui-state
;;; appends whatever component-render returns for footer-component.

(defclass goal24-footer-component (cadr-tui:component)
  ((rows
    :initarg :rows
    :initform nil
    :reader goal24-footer-component-rows)))

(defmethod cadr-tui:component-render
    ((component goal24-footer-component) width &key focused-p)
  (declare (ignore width focused-p))
  (goal24-footer-component-rows component))

(test goal24-empty-custom-footer-does-not-inflate-frame
  (let* ((width 60)
         (height 16)
         (editor (cadr-tui:make-multiline-editor))
         (state-a
           (cadr-cli::make-tui-state :model "mock"))
         (state-b
           (cadr-cli::make-tui-state :model "mock"))
         (empty-footer
           (make-instance 'goal24-footer-component :rows nil))
         (one-line-footer
           (make-instance 'goal24-footer-component
                          :rows '("custom-footer-row"))))
    (setf (cadr-cli::tui-state-footer-component state-a) empty-footer
          (cadr-cli::tui-state-footer-component state-b) one-line-footer)
    (multiple-value-bind (lines-a row-a column-a)
        (cadr-cli::render-tui-state state-a editor width height)
      (declare (ignore row-a column-a))
      (multiple-value-bind (lines-b row-b column-b)
          (cadr-cli::render-tui-state state-b editor width height)
        (declare (ignore row-b column-b))
        (let ((plain-a
                (mapcar #'cadr-tui:strip-terminal-sequences lines-a))
              (plain-b
                (mapcar #'cadr-tui:strip-terminal-sequences lines-b)))
          (is (= (length plain-a) (1- (length plain-b))))
          ;; Structure match: A is B without the footer line (no blank
          ;; row reserved solely for an empty custom footer).
          (is (equal plain-a (butlast plain-b)))
          (is (string= "custom-footer-row" (car (last plain-b)))))))))