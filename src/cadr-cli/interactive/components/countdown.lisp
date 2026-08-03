(in-package #:cadr-cli)

(defclass countdown-timer (cadr-tui:component)
  ((remaining-seconds
    :initarg :remaining-seconds
    :accessor countdown-timer-remaining-seconds)
   (ui
    :initarg :ui
    :reader countdown-timer-ui)
   (on-tick
    :initarg :on-tick
    :reader countdown-timer-on-tick)
   (on-expire
    :initarg :on-expire
    :reader countdown-timer-on-expire)
   (thread
    :initform nil
    :accessor countdown-timer-thread)
   (stop-p
    :initform nil
    :accessor countdown-timer-stop-p)
   (expired-p
    :initform nil
    :accessor countdown-timer-expired-p)))

(defun countdown-request-render (timer)
  (let ((ui (countdown-timer-ui timer)))
    (cond
      ((typep ui 'cadr-tui:tui-root)
       (cadr-tui:tui-request-render ui))
      ((functionp ui)
       (funcall ui)))))

(defun countdown-timer-tick (timer)
  (unless (or (countdown-timer-stop-p timer)
              (countdown-timer-expired-p timer))
    (decf (countdown-timer-remaining-seconds timer))
    (funcall
     (countdown-timer-on-tick timer)
     (countdown-timer-remaining-seconds timer))
    (countdown-request-render timer)
    (when (<= (countdown-timer-remaining-seconds timer) 0)
      (setf
       (countdown-timer-expired-p timer) t
       (countdown-timer-stop-p timer) t)
      (funcall (countdown-timer-on-expire timer))))
  timer)

(defun countdown-timer-run (timer)
  (loop
    (sleep 1)
    (when (countdown-timer-stop-p timer)
      (return))
    (countdown-timer-tick timer)))

(defun countdown-timer-start (timer)
  (setf (countdown-timer-stop-p timer) nil)
  (unless (countdown-timer-thread timer)
    (setf
     (countdown-timer-thread timer)
     (sb-thread:make-thread
      (lambda () (countdown-timer-run timer))
      :name "cadr countdown timer")))
  timer)

(defun make-countdown-timer
    (timeout-milliseconds ui on-tick on-expire
     &key (start-p t))
  (let* ((seconds
           (ceiling (max 0 timeout-milliseconds) 1000))
         (timer
           (make-instance
            'countdown-timer
            :remaining-seconds seconds
            :ui ui :on-tick on-tick
            :on-expire on-expire)))
    (funcall on-tick seconds)
    (when start-p (countdown-timer-start timer))
    timer))

(defmethod cadr-tui:component-dispose
    ((timer countdown-timer))
  (setf (countdown-timer-stop-p timer) t)
  (let ((thread (countdown-timer-thread timer)))
    (when (and thread
               (not (eq thread sb-thread:*current-thread*))
               (sb-thread:thread-alive-p thread))
      (stop-thread-for-cleanup thread))
    (setf (countdown-timer-thread timer) nil))
  timer)
