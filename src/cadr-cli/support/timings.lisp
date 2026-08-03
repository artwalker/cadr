(in-package #:cadr-cli)

(defparameter *timing-enabled-p*
  (string= (or (uiop:getenv "PI_TIMING") "") "1"))
(defparameter *timing-namespaces* (make-hash-table :test #'eq))
(defparameter *timing-clock*
  (lambda ()
    (round (* 1000 (/ (get-internal-real-time)
                      internal-time-units-per-second)))))

(defun reset-timings (&optional (namespace :main))
  (when *timing-enabled-p*
    (setf (gethash namespace *timing-namespaces*)
          (list :timings nil :last-time (funcall *timing-clock*))))
  nil)

(defun record-timing (label &optional (namespace :main))
  (when *timing-enabled-p*
    (unless (gethash namespace *timing-namespaces*)
      (reset-timings namespace))
    (let* ((state (gethash namespace *timing-namespaces*))
           (now (funcall *timing-clock*)))
      (setf (getf state :timings)
            (append (getf state :timings)
                    (list (cons label (- now (getf state :last-time)))))
            (getf state :last-time) now
            (gethash namespace *timing-namespaces*) state)))
  nil)

(defun print-timings (&optional (output *error-output*))
  (when *timing-enabled-p*
    (maphash
     (lambda (namespace state)
       (let ((timings (remove-if (lambda (entry) (minusp (cdr entry)))
                                 (getf state :timings))))
         (when timings
           (let ((title (format nil "Startup Timings: ~(~A~)" namespace)))
             (format output "~%--- ~A ---~%" title)
             (dolist (entry timings)
               (format output "  ~A: ~Dms~%" (car entry) (cdr entry)))
             (format output "  TOTAL: ~Dms~%~A~%~%"
                     (reduce #'+ timings :key #'cdr :initial-value 0)
                     (make-string (+ (length title) 8)
                                  :initial-element #\-))))))
     *timing-namespaces*))
  nil)
