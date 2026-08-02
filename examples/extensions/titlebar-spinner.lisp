(load (merge-pathnames "support.lisp" *load-truename*))

(defparameter +titlebar-spinner-frames+
  #("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏"))

(defvar *titlebar-spinner-thread* nil)
(defvar *titlebar-spinner-running-p* nil)

(defun titlebar-spinner-directory-name (directory)
  (princ-to-string
   (car (last (pathname-directory
               (uiop:ensure-directory-pathname directory))))))

(defun titlebar-spinner-base-title (context)
  (let* ((session (cadr-agent:extension-context-session context))
         (name (and session (cadr-agent:session-name session)))
         (cwd (titlebar-spinner-directory-name
               (cadr-agent:extension-context-cwd context))))
    (if name
        (format nil "π - ~A - ~A" name cwd)
        (format nil "π - ~A" cwd))))

(defun stop-titlebar-spinner (&optional context)
  (setf *titlebar-spinner-running-p* nil)
  (when (and *titlebar-spinner-thread*
             (sb-thread:thread-alive-p *titlebar-spinner-thread*)
             (not (eq *titlebar-spinner-thread* sb-thread:*current-thread*)))
    (sb-thread:join-thread *titlebar-spinner-thread*))
  (setf *titlebar-spinner-thread* nil)
  (when context
    (cadr-agent:extension-context-set-title
     context (titlebar-spinner-base-title context))))

(defun start-titlebar-spinner (context)
  (stop-titlebar-spinner context)
  (setf *titlebar-spinner-running-p* t
        *titlebar-spinner-thread*
        (sb-thread:make-thread
         (lambda ()
           (loop for frame-index from 0
                 while *titlebar-spinner-running-p*
                 do
                 (handler-case
                     (cadr-agent:extension-context-set-title
                      context
                      (format nil "~A ~A"
                              (aref +titlebar-spinner-frames+
                                    (mod frame-index
                                         (length +titlebar-spinner-frames+)))
                              (titlebar-spinner-base-title context)))
                   (condition ()
                     (setf *titlebar-spinner-running-p* nil)))
                 (sleep 0.08)))
         :name "cadr-example-titlebar-spinner")))

(cadr-agent:define-event-hook
 :agent-start
 :handler
 (lambda (event context)
   (declare (ignore event))
   (start-titlebar-spinner context)))

(cadr-agent:define-event-hook
 :agent-end
 :handler
 (lambda (event context)
   (declare (ignore event))
   (stop-titlebar-spinner context)))

(cadr-agent:define-event-hook
 :session-shutdown
 :handler
 (lambda (event context)
   (declare (ignore event))
   (stop-titlebar-spinner context)))
