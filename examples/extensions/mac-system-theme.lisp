(load (merge-pathnames "support.lisp" *load-truename*))

(defvar *mac-system-theme-thread* nil)
(defvar *mac-system-theme-running-p* nil)

(defun mac-system-dark-mode-p ()
  (let ((result
          (example-exec
           "osascript"
           '("-e"
             "tell application \"System Events\" to tell appearance preferences to return dark mode"))))
    (and (zerop (example-exec-code result))
         (string= "true"
                  (string-downcase
                   (example-trim (example-exec-output result)))))))

(defun stop-mac-system-theme-watcher ()
  (setf *mac-system-theme-running-p* nil)
  (when (and *mac-system-theme-thread*
             (sb-thread:thread-alive-p *mac-system-theme-thread*)
             (not (eq *mac-system-theme-thread* sb-thread:*current-thread*)))
    (sb-thread:join-thread *mac-system-theme-thread*))
  (setf *mac-system-theme-thread* nil))

(defun start-mac-system-theme-watcher (context)
  (stop-mac-system-theme-watcher)
  (let ((current-theme (if (mac-system-dark-mode-p) "dark" "light")))
    (cadr-agent:extension-context-set-theme context current-theme)
    (setf *mac-system-theme-running-p* t
          *mac-system-theme-thread*
          (sb-thread:make-thread
           (lambda ()
             (loop while *mac-system-theme-running-p*
                   do
                   (sleep 2)
                   (when *mac-system-theme-running-p*
                     (handler-case
                         (let ((new-theme
                                 (if (mac-system-dark-mode-p)
                                     "dark"
                                     "light")))
                           (unless (string= new-theme current-theme)
                             (setf current-theme new-theme)
                             (cadr-agent:extension-context-set-theme
                              context current-theme)))
                       (condition ()
                         (setf *mac-system-theme-running-p* nil))))))
           :name "cadr-example-mac-system-theme"))))

(cadr-agent:define-event-hook
 :session-start
 :handler
 (lambda (event context)
   (declare (ignore event))
   (start-mac-system-theme-watcher context)))

(cadr-agent:define-event-hook
 :session-shutdown
 :handler
 (lambda (event context)
   (declare (ignore event context))
   (stop-mac-system-theme-watcher)))
