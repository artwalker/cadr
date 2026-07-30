(in-package #:pi-tui/tests)
(in-suite pi-tui-suite)

(defclass lifecycle-terminal (pi-tui:terminal)
  ((starts :initform 0 :accessor lifecycle-starts)
   (stops :initform 0 :accessor lifecycle-stops)))

(defmethod pi-tui:terminal-start ((terminal lifecycle-terminal))
  (incf (lifecycle-starts terminal)))

(defmethod pi-tui:terminal-stop ((terminal lifecycle-terminal))
  (incf (lifecycle-stops terminal)))

(test terminal-lifecycle-restores-after-condition
  (let ((terminal (make-instance 'lifecycle-terminal)))
    (signals simple-error
      (pi-tui:call-with-terminal
       terminal
       (lambda ()
         (error "boom"))))
    (is (= 1 (lifecycle-starts terminal)))
    (is (= 1 (lifecycle-stops terminal)))))

(defclass failing-start-terminal (lifecycle-terminal) ())

(defmethod pi-tui:terminal-start ((terminal failing-start-terminal))
  (incf (lifecycle-starts terminal))
  (error "start failed after partial setup"))

(test terminal-lifecycle-cleans-up-partial-start
  (let ((terminal (make-instance 'failing-start-terminal)))
    (signals simple-error
      (pi-tui:call-with-terminal
       terminal
       (lambda () nil)))
    (is (= 1 (lifecycle-starts terminal)))
    (is (= 1 (lifecycle-stops terminal)))))
