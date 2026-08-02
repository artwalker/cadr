(load (merge-pathnames "support.lisp" *load-truename*))

(defparameter +file-trigger-path+ #p"/tmp/agent-trigger.txt")
(defvar *file-trigger-thread* nil)
(defvar *file-trigger-stop-p* nil)

(defun file-trigger-consume ()
  (when (probe-file +file-trigger-path+)
    (cadr-agent:with-file-mutation-queue
     +file-trigger-path+
     (lambda ()
       (let ((content
               (example-trim
                (uiop:read-file-string
                 +file-trigger-path+ :external-format :utf-8))))
         (when (plusp (length content))
           (with-open-file
               (stream +file-trigger-path+
                       :direction :output :if-exists :supersede
                       :external-format :utf-8)
             (declare (ignore stream)))
           content))))))

(defun file-trigger-poll ()
  (loop until *file-trigger-stop-p*
        do
        (handler-case
            (let ((content (file-trigger-consume)))
              (when content
                (cadr-agent:extension-api-send-message
                 *example-api*
                 (list :custom-type "file-trigger"
                       :content (format nil "External trigger: ~A" content)
                       :display-p t)
                 :trigger-turn-p t)))
          (cadr-agent:stale-extension-context ()
            (return))
          (condition () nil))
        (sleep 0.1)))

(defun file-trigger-stop ()
  (setf *file-trigger-stop-p* t)
  (let ((thread *file-trigger-thread*))
    (when (and thread
               (sb-thread:thread-alive-p thread)
               (not (eq thread sb-thread:*current-thread*)))
      (sb-thread:join-thread thread)))
  (setf *file-trigger-thread* nil)
  nil)

(defun file-trigger-start ()
  (file-trigger-stop)
  (setf *file-trigger-stop-p* nil
        *file-trigger-thread*
        (sb-thread:make-thread
         #'file-trigger-poll :name "cadr file-trigger example"))
  nil)

(cadr-agent:define-event-hook
 :session-start
 :handler
 (lambda (event context)
   (declare (ignore event))
   (file-trigger-start)
   (when (cadr-agent:extension-context-has-ui-p context)
     (cadr-agent:extension-context-notify
      context (format nil "Watching ~A" (namestring +file-trigger-path+))))))

(cadr-agent:define-event-hook
 :session-shutdown
 :handler
 (lambda (event context)
   (declare (ignore event context))
   (file-trigger-stop)))
