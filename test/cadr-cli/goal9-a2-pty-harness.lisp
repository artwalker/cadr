(defpackage #:cadr-goal9-a2-pty-harness
  (:use #:cl)
  (:export #:main))

(in-package #:cadr-goal9-a2-pty-harness)

(defun input-has-code-p (input code)
  (loop for character across input
        thereis (= code (char-code character))))

(defun write-marker (terminal marker)
  (cadr-tui:terminal-write
   terminal
   (format nil "~A~%" marker)))

(defun run-lifecycle-harness ()
  (unless
      (and
       (cadr-tui:terminal-stream-p *standard-input* :input)
       (cadr-tui:terminal-stream-p *standard-output* :output))
    (error "Goal 9 A2 PTY harness requires terminal stdin and stdout"))
  (let ((terminal (cadr-tui:make-process-terminal))
        (done-p nil)
        (exit-reason :unknown)
        (suspended-p nil))
    (labels
        ((start-terminal ()
           (cadr-tui:terminal-start terminal))
         (stop-terminal ()
           (cadr-tui:terminal-stop terminal))
         (render-resumed ()
           (write-marker terminal "GOAL9_A2_RESUMED")))
      (unwind-protect
           (progn
             (start-terminal)
             (write-marker terminal "GOAL9_A2_READY")
             (loop until done-p
                   for input = (cadr-tui:terminal-read-input terminal)
                   do
                   (cond
                     ((input-has-code-p input 3)
                      (setf done-p t
                            exit-reason :ctrl-c))
                     ((input-has-code-p input 26)
                      (setf suspended-p t)
                      (cadr-cli::suspend-tui
                       :linux
                       #'stop-terminal
                       #'start-terminal
                       #'render-resumed
                       #'cadr-cli::suspend-current-process
                       #'cadr-cli::call-with-sigcont-handler))
                     ((find #\q input :test #'char-equal)
                      (setf done-p t
                            exit-reason
                            (if suspended-p
                                :suspend-resume
                                :normal)))))
             (stop-terminal)
             (format t "GOAL9_A2_EXIT:~A~%"
                     (string-upcase
                      (symbol-name exit-reason)))
             (finish-output))
        (stop-terminal)))))

(defun main ()
  (run-lifecycle-harness))

(main)
