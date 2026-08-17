(in-package #:cadr-tui)

(defparameter +synchronized-update-begin+
  (format nil "~C[?2026h" #\Escape))
(defparameter +synchronized-update-end+
  (format nil "~C[?2026l" #\Escape))

(defclass terminal ()
  ((columns
    :initarg :columns
    :initform 80
    :accessor terminal-columns)
   (rows
    :initarg :rows
    :initform 24
    :accessor terminal-rows)))

(defgeneric terminal-start (terminal))
(defgeneric terminal-stop (terminal))
(defgeneric terminal-write (terminal text))
(defgeneric terminal-read-input (terminal))
(defgeneric terminal-resized-p (terminal))
(defgeneric terminal-query-background-color
    (terminal &key timeout-seconds))
(defgeneric terminal-query-color-scheme
    (terminal &key timeout-seconds))
(defgeneric terminal-set-color-scheme-notifications
    (terminal enabled))
(defgeneric terminal-color-scheme-change (terminal))
(defgeneric terminal-set-progress (terminal active))
(defgeneric terminal-poll-progress (terminal))

(defmethod terminal-start ((terminal terminal))
  (declare (ignore terminal))
  nil)

(defmethod terminal-stop ((terminal terminal))
  (declare (ignore terminal))
  nil)

(defmethod terminal-write ((terminal terminal) text)
  (declare (ignore terminal text))
  nil)

(defmethod terminal-read-input ((terminal terminal))
  (declare (ignore terminal))
  "")

(defmethod terminal-resized-p ((terminal terminal))
  (declare (ignore terminal))
  nil)

(defmethod terminal-query-background-color
    ((terminal terminal) &key (timeout-seconds 0.1d0))
  (declare (ignore terminal timeout-seconds))
  nil)

(defmethod terminal-query-color-scheme
    ((terminal terminal) &key (timeout-seconds 0.1d0))
  (declare (ignore terminal timeout-seconds))
  nil)

(defmethod terminal-set-color-scheme-notifications
    ((terminal terminal) enabled)
  (declare (ignore terminal))
  (not (null enabled)))

(defmethod terminal-color-scheme-change ((terminal terminal))
  (declare (ignore terminal))
  nil)

(defmethod terminal-set-progress ((terminal terminal) active)
  (declare (ignore terminal))
  (not (null active)))

(defmethod terminal-poll-progress ((terminal terminal))
  (declare (ignore terminal))
  nil)
