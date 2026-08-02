(load (merge-pathnames "support.lisp" *load-truename*))

(defparameter *read-access-log*
  (merge-pathnames ".cadr-read-access.log" (uiop:getcwd)))

(defun example-blocked-read-path-p (path)
  (or (search "/.env" path :from-end t)
      (search "/.ssh/" path :from-end t)
      (search "/.cadr/auth.json" path :from-end t)))

(defun example-log-read-access (path allowed-p)
  (cadr-agent:with-file-mutation-queue
   *read-access-log*
   (lambda ()
     (with-open-file (output *read-access-log*
                             :direction :output :if-exists :append
                             :if-does-not-exist :create)
       (format output "~A ~A~%" (if allowed-p "ALLOW" "BLOCK") path)))))

(let ((read-tool (cadr-cli:make-read-tool (uiop:getcwd))))
  (cadr-agent:define-rich-tool
   "read"
   :label "Read (audited)"
   :description (cadr-ai:tool-description read-tool)
   :parameters (cadr-ai:tool-parameters read-tool)
   :handler
   (lambda (call-id arguments signal on-update context)
     (declare (ignore signal on-update))
     (let* ((raw (example-argument arguments "path" ""))
            (path (namestring
                   (uiop:ensure-absolute-pathname
                    raw (cadr-agent:extension-context-cwd context))))
            (allowed-p (not (example-blocked-read-path-p path))))
       (example-log-read-access path allowed-p)
       (if allowed-p
           (example-execute-tool read-tool call-id arguments)
           (values "Read blocked by protected-path policy" nil nil))))))

(cadr-agent:define-command
 "read-log"
 :description "Show recent audited read decisions"
 :handler
 (lambda (arguments context)
   (declare (ignore arguments))
   (cadr-agent:extension-context-notify
    context
    (if (probe-file *read-access-log*)
        (uiop:read-file-string *read-access-log*)
        "No access log found"))))
