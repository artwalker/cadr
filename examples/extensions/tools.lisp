(load (merge-pathnames "support.lisp" *load-truename*))

(defvar *tools-example-enabled* nil)

(defun tools-example-persist ()
  (cadr-agent:extension-api-append-entry
   *example-api* "tools-config"
   (list :enabled-tools (copy-list *tools-example-enabled*))))

(defun tools-example-restore (context)
  (let ((saved nil))
    (dolist (entry (example-session-branch context))
      (when (and (eq (cadr-agent:session-entry-type entry) :custom)
                 (string= (or (cadr-agent:session-entry-custom-type entry) "")
                          "tools-config"))
        (setf saved (getf (cadr-agent:session-entry-data entry)
                          :enabled-tools))))
    (let ((available
            (mapcar (lambda (tool) (getf tool :name))
                    (cadr-agent:extension-api-get-all-tools *example-api*))))
      (setf *tools-example-enabled*
            (if saved
                (remove-if-not
                 (lambda (name) (member name available :test #'string=))
                 saved)
                (cadr-agent:extension-api-get-active-tools *example-api*)))
      (when saved
        (cadr-agent:extension-api-set-active-tools
         *example-api* *tools-example-enabled*)))))

(cadr-agent:define-command
 "tools"
 :description "Enable or disable active tools"
 :handler
 (lambda (arguments context)
   (declare (ignore arguments))
   (if (not (cadr-agent:extension-context-has-ui-p context))
       (cadr-agent:extension-context-notify context "/tools requires TUI mode" :level :error)
       (let ((all (cadr-agent:extension-api-get-all-tools *example-api*)))
         (loop
           for selected =
             (cadr-agent:extension-context-select
              context "Tool Configuration"
              (mapcar
               (lambda (tool)
                 (let ((name (getf tool :name)))
                   (format nil "~:[disabled~;enabled~] · ~A"
                           (member name *tools-example-enabled* :test #'string=)
                           name)))
               all))
           while selected
           for separator = (search " · " selected)
           for name = (and separator (subseq selected (+ separator 3)))
           when name
             do
             (if (member name *tools-example-enabled* :test #'string=)
                 (setf *tools-example-enabled*
                       (remove name *tools-example-enabled* :test #'string=))
                 (setf *tools-example-enabled*
                       (append *tools-example-enabled* (list name))))
             (cadr-agent:extension-api-set-active-tools
              *example-api* *tools-example-enabled*)
             (tools-example-persist))))))

(cadr-agent:define-event-hook
 :session-start
 :handler
 (lambda (event context)
   (declare (ignore event))
   (tools-example-restore context)
   nil))

(cadr-agent:define-event-hook
 :session-tree
 :handler
 (lambda (event context)
   (declare (ignore event))
   (tools-example-restore context)
   nil))
