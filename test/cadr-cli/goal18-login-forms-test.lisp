(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

;;; Goal 18 A5 TUI wiring: while a login dialog is active, auth selects
;;; borrow the screen and restore the dialog, text prompts render through
;;; the dialog's showPrompt form, and info events render message + link —
;;; never as transcript status lines.

(defun goal18-screen-text (terminal)
  (format nil "~{~A~^~%~}"
          (mapcar #'cadr-tui:strip-terminal-sequences
                  (cadr-tui:virtual-terminal-snapshot terminal))))

(defun goal18-screen-has-p (terminal needle)
  (not (null (search needle (goal18-screen-text terminal)))))

(test goal18-auth-select-restores-the-login-dialog-for-later-events
  (let* ((prompt-bridge nil)
        (event-bridge nil)
        (select-visible nil)
        (answered nil)
        (choice nil)
        (dialog-screen nil)
        (work-done nil)
        (terminal
          (make-instance
           'goal17-scripted-terminal
           :columns 80 :rows 16
           :inputs
           (list
            (format nil "/login xai~C~C" #\Return #\Return)
            (lambda ()
              (and select-visible
                       (not answered)
                       (prog1 (format nil "~C" #\Return)
                         (setf answered t))))
            (lambda ()
              (and work-done (format nil "/quit~C" #\Return)))))))
    (cadr-cli::run-tui
     (lambda (line) (declare (ignore line)))
     :command-function
     (lambda (line)
       (if (string-equal
            (string-trim '(#\Space #\Tab #\Newline #\Return) line)
            "/login xai")
           (progn
             (setf choice
                   (funcall
                    prompt-bridge
                    '(:type :select :message "Pick a method:"
                      :options
                      ((:id "browser" :label "Browser")
                       (:id "device" :label "Device")))))
             ;; After the select, an auth-url event belongs in the
             ;; restored dialog.  The worker records; the main thread
             ;; asserts (fiveam checks cannot run in the worker).
             (funcall
              event-bridge
              '(:type :auth-url
                :url "https://auth.invalid/activate"
                :instructions "Continue in your browser."))
             (sleep 0.2)
             (setf dialog-screen (goal18-screen-text terminal)
                   work-done t)
             (values t nil))
           (values nil nil)))
     :login-options-function
     (lambda ()
       (list
        (cadr-cli::make-oauth-selector-option
         :id :xai :name "xAI" :auth-type :oauth)))
     :set-auth-prompt-consumer
     (lambda (f) (setf prompt-bridge f))
     :set-auth-event-consumer
     (lambda (f) (setf event-bridge f))
     :extension-overlay-opened-function
     (lambda () (setf select-visible t))
     :model "faux"
     :terminal terminal)
    (is-true answered "the scripted select was never answered")
    (is (string= "browser" choice)
        "the select must resolve to the chosen id")
    (is (not (null dialog-screen)))
    (is (search "Login to xAI" dialog-screen)
        "the login dialog must be restored after the select")
    (is (search "auth.invalid/activate" dialog-screen)
        "the auth URL must render inside the dialog")))

(test goal18-auth-text-prompt-renders-through-the-dialog
  (let* ((prompt-bridge nil)
         (dialog-visible nil)
         (answered nil)
         (prompt-screen nil)
         (answer nil)
         (work-done nil)
         (terminal-cell (list nil))
        (terminal
          (make-instance
           'goal17-scripted-terminal
           :columns 80 :rows 16
           :inputs
           (list
            (format nil "/login github-copilot~C~C" #\Return #\Return)
            (lambda ()
              (and dialog-visible
                       (not answered)
                       ;; Answer only once the rendered dialog actually
                       ;; shows the prompt; capture it for the assertions.
                       (goal18-screen-has-p
                        (first terminal-cell) "e.g., company.ghe.com")
                       (prog1
                           (format nil "corp.ghe.example~C" #\Return)
                         (setf prompt-screen
                               (goal18-screen-text (first terminal-cell))
                               answered t))))
            (lambda ()
              (and work-done (format nil "/quit~C" #\Return)))))))
    (setf (first terminal-cell) terminal)
    (cadr-cli::run-tui
     (lambda (line) (declare (ignore line)))
     :command-function
     (lambda (line)
       (if (string-equal
            (string-trim '(#\Space #\Tab #\Newline #\Return) line)
            "/login github-copilot")
           (progn
             (setf answer
                   (funcall
                    prompt-bridge
                    '(:type :text
                      :message "GitHub Enterprise URL/domain (blank for github.com)"
                      :placeholder "company.ghe.com"))
                   work-done t)
             (values t nil))
            (values nil nil)))
     :login-options-function
     (lambda ()
       (list
        (cadr-cli::make-oauth-selector-option
         :id :github-copilot :name "GitHub Copilot" :auth-type :oauth)))
     :set-auth-prompt-consumer
     (lambda (f)
       (setf prompt-bridge
             (lambda (prompt)
               (setf dialog-visible t)
               (funcall f prompt))))
    :model "faux"
     :terminal terminal)
    (is-true answered "the scripted prompt was never answered")
    (is (string= "corp.ghe.example" answer)
        "the dialog input must return the entered text")
    (is (not (null prompt-screen)))
    (is (search "e.g., company.ghe.com" prompt-screen)
        "the dialog must show the baseline e.g. placeholder line")
    (is (search "GitHub Enterprise URL/domain" prompt-screen)
        "the dialog must show the prompt message")))

(test goal18-auth-info-event-renders-message-and-accent-link
  (let* ((event-bridge nil)
        (ready nil)
        (info-screen nil)
        (terminal
          (make-instance
           'goal17-scripted-terminal
           :columns 80 :rows 16
           :inputs
           (list
            (format nil "/login xai~C~C" #\Return #\Return)
            (lambda ()
              (and ready (format nil "/quit~C" #\Return)))))))
    (cadr-cli::run-tui
     (lambda (line) (declare (ignore line)))
     :command-function
     (lambda (line)
       (if (string-equal
            (string-trim '(#\Space #\Tab #\Newline #\Return) line)
            "/login xai")
           (progn
             (funcall
              event-bridge
              '(:type :info
                :message "Credential chain is supported."
                :links
                ((:label "AWS credential provider chain"
                  :url "https://docs.aws.amazon.com/sdkref/latest/guide/standardized-credentials.html"))))
             (sleep 0.2)
             (setf info-screen (goal18-screen-text terminal))
             (setf ready t)
             (values t nil))
           (values nil nil)))
     :login-options-function
     (lambda ()
       (list
        (cadr-cli::make-oauth-selector-option
         :id :xai :name "xAI" :auth-type :oauth)))
     :set-auth-event-consumer
     (lambda (f) (setf event-bridge f))
     :model "faux"
     :terminal terminal)
    (is-true ready "the info event was never exercised")
    (is (not (null info-screen)))
    (is (search "Credential chain is supported." info-screen)
        "the info message must render in the dialog")
    ;; The dialog wraps the long link line; assert the rendered pieces.
    (is (search "AWS credential provider chain:" info-screen)
        "the info link must render its label")
    (is (search "https://docs.aws.amazon.com/sdkref" info-screen)
        "the info link must render its URL")))
