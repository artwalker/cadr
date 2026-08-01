(in-package #:cadr-cli)

(defvar *active-agent* nil)

(defvar *active-agent-lock*
  (sb-thread:make-mutex
   :name "cadr active agent"))

(defun active-agent ()
  (sb-thread:with-mutex (*active-agent-lock*)
    *active-agent*))

(defun install-active-agent (agent)
  (sb-thread:with-mutex (*active-agent-lock*)
    (when *active-agent*
      (error
       'cadr-ai:configuration-error
       :message "A cadr agent is already exposed through Slynk"))
    (setf *active-agent* agent)))

(defun clear-active-agent (agent)
  (sb-thread:with-mutex (*active-agent-lock*)
    (when (eq *active-agent* agent)
      (setf *active-agent* nil))))

(defun ensure-slynk-runtime ()
  (unless (find-package :slynk)
    (let ((*debug-io* (make-broadcast-stream)))
      (asdf:load-system "slynk/mrepl")))
  (unless (find-package :slynk)
    (error
     'cadr-ai:configuration-error
     :message "Slynk failed to load")))

(defun start-remote-repl (port)
  (handler-case
      (progn
        (ensure-slynk-runtime)
        (uiop:symbol-call
         :slynk :create-server
         :port port
         :interface "127.0.0.1"
         :style :spawn
         :dont-close t))
    (error (condition)
      (error
       'cadr-ai:configuration-error
       :message
       (format nil
               "Unable to start Slynk on 127.0.0.1:~D: ~A"
               port condition)))))

(defun call-with-remote-repl (agent port function)
  (if (null port)
      (funcall function)
      (let ((started-port nil))
        (install-active-agent agent)
        (unwind-protect
             (progn
               (setf started-port
                     (start-remote-repl port))
               (funcall function))
          (when started-port
            (ignore-errors
              (uiop:symbol-call
               :slynk :stop-server started-port)))
          (clear-active-agent agent)))))
