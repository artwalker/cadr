(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(test radius-login-shimmers-the-selected-option
  ;; pi@4a080252f radius-login-selector.ts: elapsed 0 sits on the first
  ;; logo color; one second later the first character has moved 10 cells.
  (let* ((theme (cadr-tui:current-theme))
         (mode (cadr-tui:terminal-theme-color-mode theme)))
    (unwind-protect
         (progn
           (setf (cadr-tui:terminal-theme-color-mode theme) :truecolor)
           (is (uiop:string-prefix-p
                (format nil "~C[38;2;77;154;191mS" #\Escape)
                (cadr-cli::radius-shimmer "Sign in with Radius" 0)))
           (is (uiop:string-prefix-p
                (format nil "~C[38;2;186;197;149mS" #\Escape)
                (cadr-cli::radius-shimmer "Sign in with Radius" 1000))))
      (setf (cadr-tui:terminal-theme-color-mode theme) mode)))
  (let* ((radius
           (first
            (cadr-cli::login-provider-options
             (list (cadr-ai:find-provider-definition :radius))
             :auth-type :oauth)))
         (state
           (nth-value
            1
            (cadr-cli::login-auth-type-route
             nil :generic-p t :radius-option radius)))
         (labels
           (mapcar
            (lambda (item)
              (cadr-tui:strip-terminal-sequences
               (cadr-tui:select-item-label item)))
            (cadr-tui::select-list-items
             (cadr-cli::login-method-selector-state-select-list
              state)))))
    (is (equal
         '("Sign in with an account"
           "Sign in with an API key"
           "Sign in with Radius • not configured")
         labels))
    (setf (cadr-tui::select-list-selected
           (cadr-cli::login-method-selector-state-select-list state))
          2)
    (let ((line
            (find-if
             (lambda (row)
               (search "Sign in with Radius"
                       (cadr-tui:strip-terminal-sequences row)))
             (cadr-cli::render-login-method-selector
              state 80 :elapsed 0))))
      (is (search (format nil "~C[38;2;77;154;191m" #\Escape) line))
      (is (not (cadr-cli::login-method-radius-selected-p
                (cadr-cli::make-login-method-selector-state))))
      (is (cadr-cli::login-method-radius-selected-p state)))))
