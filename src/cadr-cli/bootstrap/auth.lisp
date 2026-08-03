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
                        (make-oauth-selector-option
                         :id id
                         :name name
                         :auth-type auth-type
                         :method-name
                         (let ((metadata
                                 (and
                                  (eq auth-type :oauth)
                                  (getf record :oauth-metadata))))
                           (if metadata
                               (cadr-ai:oauth-provider-metadata-method-name
                                metadata)
                               (format nil "~A ~A" name
                                       (if (eq auth-type :oauth)
                                           "account"
                                           "API key"))))
                         :login-label
                         (let ((metadata
                                 (and
                                  (eq auth-type :oauth)
                                  (getf record :oauth-metadata))))
                           (and metadata
                                (cadr-ai:oauth-provider-metadata-login-label
                                 metadata)))
                         :status
                         (and status-function
                              (funcall status-function id))))))
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
    (cond
      ((and definition
            (string= command "/login")
            (cadr-ai:runtime-provider-oauth-login-function
             definition))
       (model-registry-login-native-provider
        registry provider interaction :auth-type :oauth)
       (format output "~(~A~) login stored in ~A~%"
               provider
               (namestring
                (if
                    (typep
                     (model-registry-credentials registry)
                     'file-auth-storage)
                    (file-auth-storage-path
                     (model-registry-credentials registry))
                    (default-auth-path))))
       (when on-change
         (funcall on-change provider :login))
       (finish-output output)
       t)
      ((and built-in-definition
            (string= command "/login")
            (member :oauth
                    (cadr-ai:provider-definition-auth-types
                     built-in-definition)))
       (model-registry-login-built-in-provider
        registry provider interaction)
       (format output "~(~A~) login stored in ~A~%"
               provider
               (namestring
                (if
                    (typep
                     (model-registry-credentials registry)
                     'file-auth-storage)
                    (file-auth-storage-path
                     (model-registry-credentials registry))
                    (default-auth-path))))
       (when on-change
         (funcall on-change provider :login))
       (finish-output output)
       t)
      ((and definition
            (string= command "/logout"))
       (auth-storage-delete
        (model-registry-credentials registry) provider)
       (format output "~(~A~) logged out~%" provider)
       (when on-change
         (funcall on-change provider :logout))
       (finish-output output)
       t)
      (t nil))))
