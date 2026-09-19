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

(test overlay-input-press-moves-the-cursor
  (let ((state (cadr-cli::make-login-dialog-state "xAI")))
    (cadr-cli::login-dialog-show-prompt state "Paste the code" nil nil)
    (let ((input (cadr-cli::login-dialog-state-input state)))
      (setf (cadr-tui::single-line-input-value input) "hello"
            (cadr-tui::single-line-input-cursor input) 5)
      (cadr-cli::render-login-dialog-state state 40)
      (let ((origin (cadr-cli::login-dialog-state-input-origin state)))
        (is (integerp origin))
        (is (null
             (cadr-cli::login-dialog-handle-mouse
              state (list :type :press :button :left :x 4) 0)))
        (is (cadr-cli::login-dialog-handle-mouse
             state (list :type :press :button :left :x 4) origin))
        (is (= 2 (cadr-tui::single-line-input-cursor input)))
        (cadr-cli::login-dialog-state-handle-event
         state (cadr-tui:make-input-event :kind :text :text "X"))
        (is (string= "heXllo"
                     (cadr-tui:single-line-input-value input))))))
  (let* ((state
           (cadr-cli::make-api-key-input-state
            (cadr-cli::make-oauth-selector-option
             :id :anthropic :name "Anthropic" :auth-type :api-key)))
         (input (cadr-cli::api-key-input-state-input state)))
    (setf (cadr-tui::single-line-input-value input) "hello"
          (cadr-tui::single-line-input-cursor input) 5)
    (cadr-cli::render-api-key-input-state state 40)
    (let ((origin (cadr-cli::api-key-input-state-input-origin state)))
      (is (integerp origin))
      (is (cadr-cli::api-key-input-handle-mouse
           state (list :type :press :button :left :x 4) origin))
      (is (= 2 (cadr-tui::single-line-input-cursor input)))
      (cadr-cli::api-key-input-state-handle-event
       state (cadr-tui:make-input-event :kind :text :text "X"))
      (is (string= "heXllo"
                   (cadr-tui:single-line-input-value input)))))
  (let* ((dialog (cadr-cli::make-extension-input-dialog "Name"))
         (input (cadr-cli::extension-input-dialog-input dialog)))
    (setf (cadr-tui::single-line-input-value input) "hello"
          (cadr-tui::single-line-input-cursor input) 5)
    (cadr-tui:component-render dialog 40)
    (let ((origin (cadr-cli::extension-input-dialog-input-origin dialog)))
      (is (integerp origin))
      (is (cadr-cli::extension-input-dialog-handle-mouse
           dialog (list :type :press :button :left :x 4) origin))
      (is (= 2 (cadr-tui::single-line-input-cursor input)))
      (cadr-tui:component-handle-event
       dialog (cadr-tui:make-input-event :kind :text :text "X"))
      (is (string= "heXllo"
                   (cadr-tui:single-line-input-value input)))))
  (let* ((state
           (cadr-cli::make-runtime-auth-input-state
            (list :type :secret :message "Enter the key")))
         (input (cadr-cli::runtime-auth-input-state-input state)))
    (setf (cadr-tui::single-line-input-value input) "hello"
          (cadr-tui::single-line-input-cursor input) 5)
    (cadr-cli::render-runtime-auth-input-state state 40)
    (let ((origin (cadr-cli::runtime-auth-input-state-input-origin state)))
      (is (integerp origin))
      (is (cadr-cli::runtime-auth-input-handle-mouse
           state (list :type :press :button :left :x 4) origin))
      (is (= 2 (cadr-tui::single-line-input-cursor input)))
      (cadr-cli::runtime-auth-input-state-handle-event
       state (cadr-tui:make-input-event :kind :text :text "X"))
      (is (string= "heXllo"
                   (cadr-tui:single-line-input-value input))))))
