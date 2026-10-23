(in-package #:cadr-chord)

(defstruct mem-link
  (inbox nil)
  handler
  close-handlers
  (closed nil)
  reason
  peer)

(defun memory-link-pair ()
  (let ((left (make-mem-link))
        (right (make-mem-link)))
    (setf (mem-link-peer left) right
          (mem-link-peer right) left)
    (values left right)))

(defgeneric link-closed-p (link))
(defgeneric link-receive (link handler))
(defgeneric link-on-close (link handler))
(defgeneric link-send (link frame))
(defgeneric link-close (link &optional reason))

(defmethod link-closed-p ((link mem-link))
  (mem-link-closed link))

(defmethod link-receive ((link mem-link) handler)
  (setf (mem-link-handler link) handler)
  (dolist (frame (nreverse (mem-link-inbox link)))
    (funcall handler frame))
  (setf (mem-link-inbox link) nil)
  handler)

(defmethod link-on-close ((link mem-link) handler)
  (push handler (mem-link-close-handlers link))
  (when (mem-link-closed link)
    (funcall handler (mem-link-reason link)))
  handler)

(defmethod link-send ((link mem-link) frame)
  (unless (mem-link-closed link)
    (let ((peer (mem-link-peer link)))
      (cond
        ((mem-link-handler peer) (funcall (mem-link-handler peer) frame))
        (t (push frame (mem-link-inbox peer))))))
  frame)

(defmethod link-close ((link mem-link) &optional reason)
  (unless (mem-link-closed link)
    (setf (mem-link-closed link) t
          (mem-link-reason link) reason)
    (dolist (handler (mem-link-close-handlers link))
      (funcall handler reason))
    (let ((peer (mem-link-peer link)))
      (when (and peer (not (mem-link-closed peer)))
        (setf (mem-link-closed peer) t
              (mem-link-reason peer) reason)
        (dolist (handler (mem-link-close-handlers peer))
          (funcall handler reason)))))
  reason)

(defun link-frames (link)
  (mem-link-inbox link))

(defstruct pipe-link
  (inbox nil)
  (controls nil)
  handler
  control-listeners
  close-handlers
  (closed nil)
  reason
  process
  input
  output
  (lock (sb-thread:make-mutex :name "chord-pipe"))
  (ready (sb-thread:make-waitqueue :name "chord-pipe")))

(defun pipe-write (link object)
  (let ((stream (pipe-link-input link)))
    (when stream
      (write-line (canonical-json object) stream)
      (finish-output stream))))

(defun pipe-deliver (link object)
  (sb-thread:with-mutex ((pipe-link-lock link))
    (cond
      ((and (hash-table-p object) (json-get object "chord2control"))
       (let ((listeners (pipe-link-control-listeners link)))
         (if listeners
             (dolist (listener listeners)
               (funcall listener (json-get object "chord2control")))
             (push object (pipe-link-controls link)))))
      (t
       (let ((handler (pipe-link-handler link)))
         (if handler
             (funcall handler object)
             (push object (pipe-link-inbox link))))))
    (sb-thread:condition-broadcast (pipe-link-ready link))))

(defun start-pipe-reader (link)
  (sb-thread:make-thread
   (lambda ()
     (handler-case
         (loop for line = (read-line (pipe-link-output link) nil nil)
               while line
               do (unless (zerop (length (string-trim '(#\Space #\Tab) line)))
                    (pipe-deliver link (parse-json line))))
       (end-of-file ())
       (error () nil))
     (sb-thread:with-mutex ((pipe-link-lock link))
       (setf (pipe-link-closed link) t)
       (sb-thread:condition-broadcast (pipe-link-ready link))))
   :name "chord-pipe-reader"))

(defun open-pipe-link (process)
  (let ((link (make-pipe-link :process process
                              :input (uiop:process-info-input process)
                              :output (uiop:process-info-output process))))
    (start-pipe-reader link)
    link))

(defmethod link-closed-p ((link pipe-link))
  (pipe-link-closed link))

(defmethod link-send ((link pipe-link) frame)
  (unless (pipe-link-closed link)
    (pipe-write link frame))
  frame)

(defmethod link-receive ((link pipe-link) handler)
  (sb-thread:with-mutex ((pipe-link-lock link))
    (setf (pipe-link-handler link) handler)
    (dolist (frame (nreverse (pipe-link-inbox link)))
      (funcall handler frame))
    (setf (pipe-link-inbox link) nil))
  handler)

(defun link-on-control (link listener)
  (sb-thread:with-mutex ((pipe-link-lock link))
    (push listener (pipe-link-control-listeners link))
    (dolist (frame (nreverse (pipe-link-controls link)))
      (funcall listener (json-get frame "chord2control")))
    (setf (pipe-link-controls link) nil))
  listener)

(defstruct stdio-link (handler nil) (closed nil))

(defmethod link-closed-p ((link stdio-link))
  (stdio-link-closed link))

(defmethod link-send ((link stdio-link) frame)
  (write-line (canonical-json frame) *standard-output*)
  (finish-output *standard-output*)
  frame)

(defmethod link-receive ((link stdio-link) handler)
  (setf (stdio-link-handler link) handler))

(defmethod link-on-close ((link stdio-link) handler)
  (declare (ignore link handler))
  nil)

(defmethod link-close ((link stdio-link) &optional reason)
  (declare (ignore reason))
  (setf (stdio-link-closed link) t))

(defun stdio-link-dispatch (link frame)
  (let ((handler (stdio-link-handler link)))
    (when handler (funcall handler frame))))

(defmethod link-on-close ((link pipe-link) handler)
  (push handler (pipe-link-close-handlers link))
  handler)

(defmethod link-close ((link pipe-link) &optional reason)
  (setf (pipe-link-closed link) t
        (pipe-link-reason link) reason)
  (dolist (handler (pipe-link-close-handlers link))
    (funcall handler reason))
  reason)
