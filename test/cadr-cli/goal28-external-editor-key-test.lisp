(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defclass goal28-external-editor-key-terminal
    (cadr-tui::virtual-terminal)
  ((inputs
    :initarg :inputs
    :accessor goal28-external-editor-key-terminal-inputs)))

(defmethod cadr-tui:terminal-read-input
    ((terminal goal28-external-editor-key-terminal))
  (loop
    for next = (first
                (goal28-external-editor-key-terminal-inputs
                 terminal))
    while (functionp next)
    do (if (funcall next terminal)
           (pop
            (goal28-external-editor-key-terminal-inputs
             terminal))
           (return-from cadr-tui:terminal-read-input "")))
  (or
   (pop
    (goal28-external-editor-key-terminal-inputs
     terminal))
   ""))

(defun goal28-external-editor-key-screen (terminal)
  (format
   nil
   "~{~A~^~%~}"
   (mapcar
    #'cadr-tui:strip-terminal-sequences
    (cadr-tui:virtual-terminal-snapshot terminal))))

(test goal28-external-editor-key-reaches-existing-editor
  (let ((previous (cadr-tui:get-keybindings)))
    (unwind-protect
         (progn
           (cadr-tui:set-keybindings
            (cadr-tui:make-keybindings-manager))
           (is
            (eq
             :external-editor
             (cdr
              (assoc
               "app.editor.external"
               cadr-tui::+logical-key-events+
               :test #'string=))))
           (let ((decoder (cadr-tui:make-input-decoder)))
             (is
              (eq
               :external-editor
               (cadr-tui:input-event-kind
                (first
                 (cadr-tui:feed-input
                  decoder
                  (format nil "~C[103;5u" #\Escape)))))))
           (let* ((command-calls 0)
                  (captured nil)
                  (terminal nil))
             (setf
              terminal
              (make-instance
               'goal28-external-editor-key-terminal
               :columns 80
               :rows 16
               :inputs
               (list
                "draft"
                (format nil "~C[103;5u" #\Escape)
                (let ((attempts 0))
                  (lambda (term)
                    (let ((screen
                            (goal28-external-editor-key-screen
                             term)))
                      (cond
                        ((search "from-external" screen)
                         (setf captured screen)
                         t)
                        ((> (incf attempts) 200)
                         (setf captured screen)
                         t)
                        (t nil)))))
                (string (code-char 3))
                (string (code-char 3)))))
             (cadr-cli::run-tui
              (lambda (line)
                (error "Unexpected submission: ~A" line))
              :model "faux"
              :terminal terminal
              :external-editor-command-function
              (lambda ()
                (incf command-calls)
                "nano")
              :external-editor-runner-function
              (lambda (path)
                (write-text path "from-external")
                0))
             (is (= 1 command-calls))
             (is (search "from-external" captured))))
      (cadr-tui:set-keybindings previous))))
