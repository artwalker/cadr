(in-package #:cadr-ai)

(defun login-anthropic-runtime-oauth (interaction)
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
