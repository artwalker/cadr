(in-package #:cadr-cli)

(defun model-registry-login-options
    (registry status-function)
  (let* ((built-in
           (login-provider-options
            (cadr-ai:list-provider-definitions)
            :status-function status-function))
         (native-records
           (model-registry-native-login-records registry)))
    (if (null native-records)
        built-in
        (stable-sort
         (append
          built-in
          (loop for record in native-records
                for id = (getf record :id)
                for name = (getf record :name)
                unless
                  (find id built-in
                        :key #'oauth-selector-option-id
                        :test #'eq)
                  append
                  (loop for auth-type in
                        (getf record :auth-types)
                        collect
                        (let ((metadata
                                (and
                                 (eq auth-type :oauth)
                                 (getf record :oauth-metadata))))
                          (make-oauth-selector-option
                           :id id
                           :name name
                           :auth-type auth-type
                           :method-name
                           (if metadata
                               (cadr-ai:oauth-provider-metadata-method-name
                                metadata)
                               (format nil "~A ~A" name
                                       (if (eq auth-type :oauth)
                                           "account"
                                           "API key")))
                           :login-label
                           (and metadata
                                (cadr-ai:oauth-provider-metadata-login-label
                                 metadata))
                           :status
                           (and status-function
                                (funcall status-function id)))))))
         #'string-lessp
         :key #'oauth-selector-option-name))))

(defun handle-native-auth-command
    (registry line interaction
     &key (output *standard-output*) on-change)
  (let* ((parts (split-command-line line))
         (command (first parts))
         (provider
           (and (second parts)
                (or
                 (ignore-errors
                   (parse-auth-provider (second parts)))
                 (provider-symbol-from-key (second parts)))))
         (runtime
           (and registry
                (model-registry-native-runtime registry)))
         (definition
           (and runtime provider
                (cadr-ai:models-runtime-provider
                 runtime provider)))
         (built-in-definition
          (and provider
                (ignore-errors
                  (cadr-ai:find-provider-definition provider)))))
    (labels
        ((auth-file-path ()
           (if (typep
                (model-registry-credentials registry)
                'file-auth-storage)
               (file-auth-storage-path
                (model-registry-credentials registry))
               (default-auth-path)))
         (provider-display-name ()
           (or
            (and definition
                 (cadr-ai::non-empty-string-p
                  (cadr-ai:runtime-provider-name definition))
                 (cadr-ai:runtime-provider-name definition))
            (and built-in-definition
                 (cadr-ai:provider-definition-name built-in-definition))
            (string-downcase (symbol-name provider))))
         (report-login (action-label)
           ;; Baseline completeProviderAuthentication: the status line
           ;; carries the selection outcome; a provider without a
           ;; default model adds the caveat as an error.
           (let ((selection
                   (and on-change
                        (funcall on-change provider :login))))
             ;; pi@4e58f324f interactive-mode.ts:5548,5662 — when the
             ;; credential saved but the local model/auth snapshot could
             ;; not be synchronized, the synchronization error replaces
             ;; the success status.
             (let ((sync-error
                     (model-registry-error registry)))
               (if sync-error
                   (format output "~A ~A, but local model state could not be synchronized: ~A~%"
                           action-label
                           (provider-display-name)
                           sync-error)
                   (progn
                     (format output "~A.~@[ Selected ~A.~] Credentials saved to ~A~%"
                             (format nil "~A ~A" action-label
                                     (provider-display-name))
                             (and (stringp selection) selection)
                             (namestring (auth-file-path)))
                     (when (consp selection)
                       (error
                        'cadr-ai:configuration-error
                        :message
                        (post-login-selection-error
                         action-label
                         (provider-display-name)
                         provider
                         (first selection)
                         (second selection))))
                     (when (eq selection :no-default-model)
                       (error
                        'cadr-ai:configuration-error
                        :message
                        (post-login-selection-error
                         action-label
                         (provider-display-name)
                         provider
                         :no-default-model
                         nil)))))
             (finish-output output)
             t))))
      (cond
        ((and definition
              (string= command "/login")
              (cadr-ai:runtime-provider-oauth-login-function
               definition))
         (model-registry-login-native-provider
          registry provider interaction :auth-type :oauth)
         (report-login "Logged in to"))
        ((and built-in-definition
              (string= command "/login")
              (member :oauth
                      (cadr-ai:provider-definition-auth-types
                       built-in-definition)))
         (model-registry-login-built-in-provider
          registry provider interaction)
         (report-login "Logged in to"))
        ((and definition
              (string= command "/login")
              (cadr-ai:runtime-provider-api-key-login-function
               definition))
         ;; Structured API key flows (Bedrock, Vertex) run through the
         ;; auth interaction like the baseline ApiKeyAuth.login.
         (model-registry-login-native-provider
          registry provider interaction :auth-type :api-key)
         (report-login "Saved API key for"))
      ((and definition
            (string= command "/logout"))
       (auth-storage-delete
        (model-registry-credentials registry) provider)
       (format output "~(~A~) logged out~%" provider)
       (when on-change
         (funcall on-change provider :logout))
       (finish-output output)
       t)
       (t nil)))))
