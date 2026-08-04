(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defun goal14-a0-auth-option
    (&key (id :openai-codex)
          (name "OpenAI Codex")
          (auth-type :oauth)
          status)
  (cadr-cli::make-oauth-selector-option
   :id id :name name :auth-type auth-type :status status))

(test goal14-a0-auth-overlays-own-baseline-title-and-border-semantics
  (let* ((width 48)
         (border
           (cadr-tui:theme-foreground
            :border
            (make-string width :initial-element #\─)
            :enabled-p t))
         (login-title
           (cadr-tui:theme-foreground
            :accent
            (cadr-tui:theme-bold
             "Select authentication method:" :enabled-p t)
            :enabled-p t))
         (provider-title
           (cadr-tui:theme-foreground
            :accent
            (cadr-tui:theme-bold
             "Select provider to configure:" :enabled-p t)
            :enabled-p t))
         (dialog-title
           (cadr-tui:theme-foreground
            :accent
            (cadr-tui:theme-bold
             "Login to Anthropic" :enabled-p t)
            :enabled-p t))
         (login
           (cadr-cli::render-login-method-selector
            (cadr-cli::make-login-method-selector-state)
            width))
         (provider
           (cadr-cli::render-oauth-selector
            (cadr-cli::make-oauth-selector-state
             :options (list (goal14-a0-auth-option)))
            width))
         (dialog
           (cadr-cli::render-api-key-input-state
            (cadr-cli::make-api-key-input-state
             (goal14-a0-auth-option
              :id :anthropic :name "Anthropic"
              :auth-type :api-key))
            width)))
    (dolist (rendered (list login provider dialog))
      (is (string= border (first rendered)))
      (is (string= border (car (last rendered)))))
    (is (search login-title (third login)))
    (is (search provider-title (third provider)))
    (is (search dialog-title (second dialog)))))

(test post-goal15-overlay-title-styles-follow-baseline-component-classes
  (let* ((width 48)
         (ordinary
           (first
            (cadr-cli::render-selector-frame
             (cadr-cli::make-selector-frame
              :sections '((:title "Fork from Message" :plain)))
             width)))
         (settings-submenu
           (first
            (cadr-cli::render-selector-frame
             (cadr-cli::make-selector-frame
              :sections '((:title "Thinking Level")))
             width)))
         (auth
           (first
            (cadr-cli::render-selector-frame
             (cadr-cli::make-selector-frame
              :sections '((:title "Select authentication method:" :overlay)))
             width)))
         (extension-editor
           (third
            (cadr-tui:component-render
             (cadr-cli::make-extension-editor-dialog
              "Extension Editor" "prefill")
             width))))
    (is (search
         (cadr-tui:theme-bold "Fork from Message" :enabled-p t)
         ordinary))
    (is (null
         (search
          (cadr-tui:theme-foreground
           :accent
           (cadr-tui:theme-bold "Fork from Message" :enabled-p t)
           :enabled-p t)
          ordinary)))
    (dolist (case
             `((,settings-submenu "Thinking Level")
               (,auth "Select authentication method:")))
      (destructuring-bind (line title) case
        (is (search
             (cadr-tui:theme-foreground
              :accent
              (cadr-tui:theme-bold title :enabled-p t)
              :enabled-p t)
             line))))
    (is (search
         (cadr-tui:theme-foreground
          :accent "Extension Editor" :enabled-p t)
         extension-editor))
    (is (null
         (search
          (cadr-tui:theme-bold "Extension Editor" :enabled-p t)
          extension-editor)))))

(test goal14-a0-provider-search-and-login-inputs-render-a-visible-cursor
  (let* ((inverse-space
           (format nil "~C[7m ~C[27m" #\Escape #\Escape))
         (provider
           (cadr-cli::render-oauth-selector
            (cadr-cli::make-oauth-selector-state
             :options (list (goal14-a0-auth-option)))
            48))
         (dialog
           (cadr-cli::render-api-key-input-state
            (cadr-cli::make-api-key-input-state
             (goal14-a0-auth-option
              :id :anthropic :name "Anthropic"
              :auth-type :api-key))
            48)))
    (is (search inverse-space (fifth provider)))
    (is (search inverse-space (fifth dialog)))))

(test goal14-a0-provider-status-source-contract-matches-baseline
  (dolist
      (case
       '((nil "✓ configured")
         ("OAuth" "✓ configured")
         ("stored credential" "✓ configured")
         ("stored" "✓ stored")
         ("OPENAI_API_KEY" "✓ env: OPENAI_API_KEY")
         ("OPENAI_API_KEY, FALLBACK_API_KEY"
          "✓ env: OPENAI_API_KEY, FALLBACK_API_KEY")
         ("models_json_key" "✓ models_json_key")
         ("models_json_command" "✓ models_json_command")
         ("runtime" "✓ runtime")))
    (destructuring-bind (source expected) case
      (is
       (string=
        expected
        (cadr-cli::oauth-option-status-label
         (goal14-a0-auth-option
          :status (list :type :oauth :source source)))))))
  (uiop:with-temporary-file
      (:pathname auth-path :keep t)
    (delete-file auth-path)
    (let* ((storage
             (cadr-cli::make-file-auth-storage auth-path))
           (registry
             (cadr-cli::make-model-registry
              :credentials storage)))
      (cadr-cli::auth-storage-modify
       storage :openai-codex
       (lambda (current)
         (declare (ignore current))
         (cadr-ai:make-oauth-credential
          :provider :openai-codex
          :access "secret-access"
          :refresh "secret-refresh"
          :expires most-positive-fixnum)))
      (is
       (equal
        '(:type :oauth :source "stored")
        (cadr-cli::model-registry-authentication-status
         registry :openai-codex))))))
