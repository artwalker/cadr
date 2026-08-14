(load (merge-pathnames "support.lisp" *load-truename*))

(defclass example-custom-footer (cadr-tui:component)
  ((tui
    :initarg :tui
    :reader example-custom-footer-tui)
   (theme
    :initarg :theme
    :reader example-custom-footer-theme)
   (footer-data
    :initarg :footer-data
    :reader example-custom-footer-data)
   (session
    :initarg :session
    :reader example-custom-footer-session)
   (model-id
    :initarg :model-id
    :reader example-custom-footer-model-id)
   (unsubscribe
    :initform nil
    :accessor example-custom-footer-unsubscribe)))

(defun example-footer-token-count (count)
  (if (< count 1000)
      (format nil "~D" count)
      (format nil "~,1Fk" (/ count 1000d0))))

(defun example-footer-usage-from-session (session)
  (let ((input 0)
        (output 0)
        (cost 0d0))
    (when session
      (dolist (entry (cadr-agent::session-path-entries session))
        (let ((message (ignore-errors (cadr-agent:session-entry-message entry))))
          (when (typep message 'cadr-ai:assistant-message)
            (let ((usage (cadr-ai:assistant-message-usage message)))
              (incf input (cadr-ai:usage-input usage))
              (incf output (cadr-ai:usage-output usage))
              (incf cost (cadr-ai:cost-total (cadr-ai:usage-cost usage))))))))
    (values input output cost)))

(defmethod initialize-instance :after
    ((component example-custom-footer) &key)
  (let ((footer-data (example-custom-footer-data component))
        (tui (example-custom-footer-tui component)))
    (when (and footer-data tui)
      (setf (example-custom-footer-unsubscribe component)
            (cadr-cli:footer-data-provider-on-branch-change
             footer-data
             (lambda ()
               (cadr-tui:tui-request-render tui)))))))

(defmethod cadr-tui:component-render
    ((component example-custom-footer) width &key focused-p)
  (declare (ignore focused-p))
  (multiple-value-bind (input output cost)
      (example-footer-usage-from-session
       (example-custom-footer-session component))
    (let* ((theme (example-custom-footer-theme component))
           (branch
             (let ((provider (example-custom-footer-data component)))
               (and provider
                    (cadr-cli:footer-data-provider-git-branch provider))))
           (left
             (example-theme-fg
              theme :dim
              (format nil "↑~A ↓~A $~,3F"
                      (example-footer-token-count input)
                      (example-footer-token-count output)
                      cost)))
           (right
             (example-theme-fg
              theme :dim
              (format nil "~A~@[ (~A)~]"
                      (example-custom-footer-model-id component)
                      branch)))
           (pad
             (make-string
              (max 1
                   (- width
                      (cadr-tui:visible-width left)
                      (cadr-tui:visible-width right)))
              :initial-element #\Space)))
      (list
       (cadr-tui:truncate-to-width
        (concatenate 'string left pad right) width)))))

(defmethod cadr-tui:component-dispose
    ((component example-custom-footer))
  (let ((unsubscribe (example-custom-footer-unsubscribe component)))
    (when unsubscribe
      (funcall unsubscribe)
      (setf (example-custom-footer-unsubscribe component) nil)))
  component)

(cadr-agent:define-command
 "footer"
 :description "Toggle custom footer"
 :handler
 (let ((enabled-p nil))
   (lambda (arguments context)
     (declare (ignore arguments))
     (setf enabled-p (not enabled-p))
     (if enabled-p
         (let ((session (cadr-agent:extension-context-session context))
               (model
                 (ignore-errors
                   (cadr-agent:extension-context-model context))))
           (cadr-agent:extension-context-set-footer
            context
            (lambda (tui theme footer-data)
              (make-instance
               'example-custom-footer
               :tui tui :theme theme
               :footer-data footer-data
               :session session
               :model-id
               (if (typep model 'cadr-ai:model)
                   (cadr-ai:model-id model)
                   "no-model"))))
           (cadr-agent:extension-context-notify
            context "Custom footer enabled"))
         (progn
           (cadr-agent:extension-context-set-footer context nil)
           (cadr-agent:extension-context-notify
            context "Default footer restored"))))))
