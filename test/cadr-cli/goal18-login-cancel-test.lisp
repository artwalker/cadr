(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

;;; Goal 18 Part A regression: ESC-cancelling an OAuth login must end the
;;; login work and clear busy-p so the next message dispatches to the agent
;;; instead of queueing forever.  Drives the exact user repro shape through
;;; the real controller: selector option -> login dialog -> hanging device
;;; flow -> ESC -> follow-up message.

(test goal18-esc-cancel-during-device-login-dispatches-next-message
  (let* ((abort-p nil)
         (login-polling (sb-thread:make-semaphore))
         (login-ended nil)
         (prompt-line nil)
         (terminal
           (make-instance
            'goal17-scripted-terminal
            :columns 80 :rows 16
            :inputs
            (list
             ;; The provider-argument autocomplete applies on the first
             ;; Return (baseline editor.ts:697-720 swallows Enter for
             ;; non-"/" prefixes); the second Return submits.
             (format nil "/login xai~C~C" #\Return #\Return)
             ;; ESC lands only after the device flow is actually polling.
             (lambda ()
               (and (sb-thread:try-semaphore login-polling)
                    (format nil "~C" #\Escape)))
             ;; The follow-up message is offered only after the worker
             ;; finished; without the fix it never gets dispatched.
             (lambda ()
               (and login-ended
                    (format nil "hello~C" #\Return)))
             (format nil "/quit~C" #\Return)))))
    (cadr-cli::run-tui
     (lambda (line)
       (setf prompt-line line))
       :command-function
       (lambda (line)
       (if (string-equal
            (string-trim '(#\Space #\Tab #\Newline #\Return) line)
            "/login xai")
           (progn
             (sb-thread:signal-semaphore login-polling)
             (loop until abort-p do (sleep 0.01))
             (setf login-ended t)
             (values t nil))
           (values nil nil)))
     :login-options-function
     (lambda ()
       (list
        (cadr-cli::make-oauth-selector-option
         :id :xai :name "xAI"
         :auth-type :oauth
         :method-name "xAI (Grok/X subscription)")))
     :abort-function (lambda () (setf abort-p t))
     :reset-abort-function (lambda () (setf abort-p nil))
     :model "faux"
     :terminal terminal)
    (is-true login-ended)
    (is (string= "hello" prompt-line)
        "the post-cancel message must reach the agent, not the Steering queue")))

(test goal18-esc-cancel-during-api-key-login-dispatches-next-message
  ;; The API-key flow never starts background work; ESC only closes the
  ;; input overlay.  The follow-up message must still dispatch.
  (let ((prompt-line nil)
        (terminal
          (make-instance
           'goal17-scripted-terminal
           :columns 80 :rows 16
           :inputs
           (list
            (format nil "/login render-key~C~C" #\Return #\Return)
            (format nil "~C" #\Escape)
            ;; One empty read flushes the buffered ESC into a standalone
            ;; :escape event before the next text arrives.
            (lambda () "")
            (format nil "hello~C" #\Return)
            (format nil "/quit~C" #\Return)))))
    (cadr-cli::run-tui
     (lambda (line)
       (setf prompt-line line))
     :command-function (lambda (line) (declare (ignore line)) (values nil nil))
     :login-options-function
     (lambda ()
       (list
        (cadr-cli::make-oauth-selector-option
         :id :render-key :name "Render Key"
         :auth-type :api-key)))
     :model "faux"
     :terminal terminal)
    (is (string= "hello" prompt-line)
        "cancelling the API-key dialog must leave the editor usable")))

(test goal27-second-return-on-two-method-provider-opens-method-selector
  ;; v1.4.0 packages/tui/src/autocomplete.ts returns argumentText as the
  ;; prefix, and editor.ts confirm falls through to submit only when that
  ;; prefix starts with "/". The first Return applies the login argument
  ;; and stays in the editor. The second Return submits. handleLoginCommand
  ;; then opens the provider method selector when that id has both oauth
  ;; and api_key (interactive-mode.ts showLoginAuthTypeSelector).
  (let ((title "Select authentication method for Render Auth:"))
    (cadr-cli::run-tui
     (constantly nil)
     :model "mock"
     :login-options-function
     (lambda ()
       (list
        (cadr-cli::make-oauth-selector-option
         :id :render-auth :name "Render Auth"
         :auth-type :oauth
         :method-name "Render Auth account")
        (cadr-cli::make-oauth-selector-option
         :id :render-auth :name "Render Auth"
         :auth-type :api-key
         :method-name "Render Auth API key")))
     :terminal
     (make-instance
      'footer-sync-test-terminal
      :columns 100 :rows 24
      :inputs
      (append
       (loop for character across "/login render-auth"
             collect (string character))
       (list
        (footer-sync-wait-for-screen-text
         "Render Auth · subscription/API key")
        (string #\Return)
        (let ((attempts 0))
          (lambda (terminal)
            (let ((screen
                    (format
                     nil "~{~A~^~%~}"
                     (mapcar
                      #'cadr-tui:strip-terminal-sequences
                      (cadr-tui:virtual-terminal-snapshot
                       terminal)))))
              (when (search title screen)
                (error
                 "first Return opened the method selector:~%~A"
                 screen))
              (incf attempts)
              (cond
                ((null
                  (search "subscription/API key" screen))
                 t)
                ((> attempts 80)
                 (error
                  "login autocomplete stayed open:~%~A"
                  screen))
                (t nil)))))
        (string #\Return)
        (footer-sync-wait-for-screen-text title)
        (lambda (terminal)
          (let ((screen
                  (format
                   nil "~{~A~^~%~}"
                   (mapcar
                    #'cadr-tui:strip-terminal-sequences
                    (cadr-tui:virtual-terminal-snapshot
                     terminal)))))
            (is (search "Sign in with an account" screen))
            (is (search "Sign in with an API key" screen))
            (is (null
                 (search "Select provider to configure:"
                         screen)))
            t))
        (string #\Escape)
        ""
        (footer-sync-submit-input "/quit")))))))
