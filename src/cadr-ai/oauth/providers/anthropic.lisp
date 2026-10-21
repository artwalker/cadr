(in-package #:cadr-ai)

(defun login-anthropic-copy-code-oauth (interaction)
  ;; pi@71023aec1 anthropic.ts #10194. The copy-code page shows the
  ;; authorization code, so a browser on another machine can finish
  ;; login without the localhost callback.
  (multiple-value-bind (verifier challenge)
      (generate-pkce)
    (let ((url
            (anthropic-authorization-url
             challenge verifier
             +anthropic-copy-code-redirect-uri+)))
      (runtime-auth-interaction-notify
       interaction
       (list :type :auth-url
             :url url
             :instructions
             "Complete login in your browser, then copy the code Anthropic shows and paste it here."))
      (multiple-value-bind (code state)
          (parse-oauth-authorization-input
           (runtime-auth-interaction-prompt
            interaction
            '(:type :manual-code
              :message
              "Paste the code Anthropic shows after you sign in:"
              :placeholder "code#state")))
        (when (and (non-empty-string-p state)
                   (not (string= state verifier)))
          (error 'authentication-error
                 :message "OAuth state mismatch"))
        (unless (non-empty-string-p code)
          (error 'authentication-error
                 :message "Missing authorization code"))
        (runtime-auth-interaction-notify
         interaction
         '(:type :progress
           :message
           "Exchanging authorization code for tokens..."))
        (exchange-anthropic-authorization-code
         code
         (if (non-empty-string-p state) state verifier)
         verifier
         +anthropic-copy-code-redirect-uri+)))))

(defun login-anthropic-runtime-oauth (interaction)
  (let ((method
          (runtime-auth-interaction-prompt
           interaction
           '(:type :select
             :message "Select Anthropic login method:"
             :options
             ((:id "browser" :label "Browser login (default)")
              (:id "copy_code"
               :label "Copy code login (headless)"))))))
    (cond
      ((string= method "copy_code")
       (login-anthropic-copy-code-oauth interaction))
      ((string= method "browser")
       (login-anthropic-oauth
        nil
        :auth-url-function
        (lambda (url)
          (runtime-auth-interaction-notify
           interaction
           (list :type :auth-url :url url
                 :instructions
                 (oauth-provider-metadata-auth-url-instructions
                  +anthropic-oauth-metadata+))))
        :auth-prompt-function
        (lambda (prompt)
          (runtime-auth-interaction-prompt interaction prompt))))
      (t
       (error 'authentication-error
              :message
              (format nil
                      "Unknown Anthropic login method: ~A"
                      method))))))
