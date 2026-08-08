(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defun goal17-login-dialog-lines (state &optional (width 80))
  (mapcar
   (lambda (line)
     (string-trim
      '(#\Space #\Tab #\Newline #\Return)
      (cadr-tui::strip-ansi line)))
   (multiple-value-bind (lines row column)
       (cadr-cli::render-login-dialog-state state width)
     (declare (ignore row column))
     lines)))

(test goal17-login-dialog-device-code-matches-baseline-copy
  ;; Baseline login-dialog.ts: showDeviceCode + showWaiting("Waiting for
  ;; authentication...") inside the bordered "Login to <provider>" frame.
  (let ((state (cadr-cli::make-login-dialog-state "xAI")))
    (cadr-cli::login-dialog-show-device-code
     state "https://auth.invalid/device" "RENDER-42")
    (cadr-cli::login-dialog-show-waiting
     state "Waiting for authentication...")
    (let ((text
            (format nil "~{~A~^~%~}"
                    (goal17-login-dialog-lines state))))
      (is (search "Login to xAI" text))
      (is (search "https://auth.invalid/device" text))
      (is (search "Ctrl+click to open" text))
      (is (search "Enter code: RENDER-42" text))
      (is (search "Waiting for authentication..." text))
      (is (search "to cancel" text))
      (is (not (search "Device code:" text))
          "device code copy must not use the retired status-line phrasing"))))

(test goal17-login-dialog-auth-url-and-manual-input-preserve-content-order
  ;; Baseline: showAuth keeps the URL block; showManualInput appends the
  ;; prompt, input, and cancel hint without clearing.
  (let ((state (cadr-cli::make-login-dialog-state "Render Auth")))
    (cadr-cli::login-dialog-show-auth
     state "https://auth.invalid/authorize?state=render-fixed"
     "A browser window should open. Complete login to finish.")
    (cadr-cli::login-dialog-show-manual-input
     state "Paste the authorization code" (constantly nil))
    (let* ((lines (goal17-login-dialog-lines state))
           (text (format nil "~{~A~^~%~}" lines)))
      (is (search "Login to Render Auth" text))
      (is (search "https://auth.invalid/authorize?state=render-fixed" text))
      (is (search "A browser window should open. Complete login to finish." text))
      (is (search "Paste the authorization code" text))
      (is (search "to cancel" text))
      (let ((url-position
              (position "https://auth.invalid/authorize?state=render-fixed"
                        lines :test #'search))
            (prompt-position
              (position "Paste the authorization code"
                        lines :test #'search)))
        (is (and url-position prompt-position
                 (< url-position prompt-position))
            "manual input appends below the URL block")))))

(test goal17-login-dialog-submit-replaces-input-and-keeps-dialog-open
  (let* ((state (cadr-cli::make-login-dialog-state "Render Auth"))
         (input (cadr-tui:make-single-line-input :prompt "> ")))
    (cadr-cli::login-dialog-show-device-code
     state "https://auth.invalid/device" "RENDER-42")
    (cadr-cli::login-dialog-show-manual-input
     state "Paste the authorization code" (constantly nil))
    (setf (cadr-cli::login-dialog-state-input state) input)
    (dolist (event
              (cadr-tui:feed-input
               (cadr-tui:make-input-decoder) "code-123"))
      (multiple-value-bind (action value)
          (cadr-cli::login-dialog-state-handle-event state event)
        (declare (ignore action value))))
    (multiple-value-bind (action value)
        (cadr-cli::login-dialog-state-handle-event
         state (cadr-tui:make-input-event :kind :enter))
      (is (eq :select action))
      (is (string= "code-123" value))
      (cadr-cli::login-dialog-complete-input state value))
    (let ((text
            (format nil "~{~A~^~%~}"
                    (goal17-login-dialog-lines state))))
      (is (search "> code-123" text))
      (is (search "Enter code: RENDER-42" text)))))

(test goal17-login-dialog-cancel-invokes-cancel-function-in-every-state
  (let ((cancelled 0))
    (let ((state (cadr-cli::make-login-dialog-state "xAI")))
      (cadr-cli::login-dialog-show-device-code
       state "https://auth.invalid/device" "RENDER-42")
      (setf (cadr-cli::login-dialog-state-cancel-function state)
            (lambda () (incf cancelled)))
      (multiple-value-bind (action value)
          (cadr-cli::login-dialog-state-handle-event
           state (cadr-tui:make-input-event :kind :escape))
        (is (eq :cancel action))
        (is (null value))))
    (is (= 1 cancelled)
        "escape during the device-code wait cancels the flow")))
