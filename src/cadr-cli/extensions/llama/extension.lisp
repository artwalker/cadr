(in-package #:cadr-cli)

(defun llama-runtime-for-command ()
  (and
   *active-native-model-registry*
   (model-registry-native-runtime
    *active-native-model-registry*)))

(defun llama-command-interaction (context)
  (cadr-ai:make-runtime-auth-interaction
   :prompt-function
   (lambda (prompt)
     (or
      (cadr-agent:extension-context-input
       context
       (getf prompt :message)
       :placeholder
       (getf prompt :placeholder))
      (error
       'cadr-agent:extension-execution-error
       :message
       "llama.cpp login was cancelled")))
   :notify-function
   (lambda (event)
     (cadr-agent:extension-context-notify
      context
      (getf event :message)
      :level
      (if (eq :error (getf event :type))
          :error
          :info)))
   :abort-p (constantly nil)))

(defun ensure-llama-auth (context force-login-p)
  (let ((runtime (llama-runtime-for-command)))
    (unless runtime
      (error
       'cadr-agent:extension-execution-error
       :message
       "Native model registry is unavailable"))
    (when
        (or
         force-login-p
         (null
          (cadr-ai:models-runtime-check-auth
           runtime +llama-provider-id+)))
      (model-registry-login-native-provider
       *active-native-model-registry*
       +llama-provider-id+
       (llama-command-interaction context)))
    (or
     (cadr-ai:models-runtime-auth
      runtime +llama-provider-id+)
     (error
      'cadr-agent:extension-execution-error
      :message
      "Configure llama.cpp with /llama login"))))

(defun llama-command-client (context force-login-p)
  (let* ((auth
           (ensure-llama-auth
            context force-login-p))
         (base-url
           (or
            (cadr-ai:runtime-auth-result-base-url
             auth)
            (cdr
             (assoc
              "LLAMA_BASE_URL"
              (cadr-ai:runtime-auth-result-environment
               auth)
              :test #'string-equal)))))
    (make-llama-client
     :server-url
     (normalize-llama-server-url base-url)
     :api-key
     (let ((key
             (cadr-ai:runtime-auth-result-api-key
              auth)))
       (and
        key
        (not (string= key "local"))
        key)))))

(defun notify-llama-catalog (context catalog)
  (if catalog
      (dolist (model catalog)
        (cadr-agent:extension-context-notify
         context
         (format nil
                 "~(~A~)  ~A"
                 (llama-model-info-status model)
                 (llama-model-info-id model))))
      (cadr-agent:extension-context-notify
       context "No llama.cpp models found"))
  catalog)

(defun llama-progress-notifier (context)
  (lambda (progress)
    (cadr-agent:extension-context-notify
     context
     (format nil
             "~A~@[ (~,0F%%)~]~@[ — ~A~]"
             (getf progress :message)
             (and
              (getf progress :ratio)
              (* 100
                 (getf progress :ratio)))
             (getf progress :detail)))))

(defun refresh-llama-registry ()
  (when *active-native-model-registry*
    (sync-model-registry-native-providers
     *active-native-model-registry*
     :allow-network t
     :force t)))

(defun split-llama-command-arguments (arguments)
  (let* ((trimmed
           (string-trim
            '(#\Space #\Tab #\Newline
              #\Return)
            arguments))
         (separator
           (position-if
            (lambda (character)
              (member character
                      '(#\Space #\Tab)))
            trimmed)))
    (values
     (string-downcase
      (if separator
          (subseq trimmed 0 separator)
          trimmed))
     (if separator
         (string-left-trim
          '(#\Space #\Tab)
          (subseq trimmed separator))
         ""))))

(defun llama-interactive-action
    (context client catalog)
  (let* ((model-options
           (mapcar
            (lambda (model)
              (format nil
                      "~(~A~)  ~A"
                      (llama-model-info-status model)
                      (llama-model-info-id model)))
            catalog))
         (download "Download from Hugging Face")
         (choice
           (cadr-agent:extension-context-select
            context
            (format nil "llama.cpp — ~A"
                    (llama-client-server-url client))
            (append model-options
                    (list download "Close")))))
    (cond
      ((or (null choice)
           (string= choice "Close"))
       nil)
      ((string= choice download)
       (let ((query
               (cadr-agent:extension-context-input
                context
                "Hugging Face model search")))
         (when query
           (let* ((hf
                    (make-hugging-face-client
                     :token
                     (find-hugging-face-token)))
                  (results
                    (hugging-face-search hf query))
                  (ids (mapcar #'first results))
                  (selected
                    (and
                     ids
                     (cadr-agent:extension-context-select
                      context
                      "Select GGUF repository"
                      ids))))
             (when selected
               (let* ((details
                        (hugging-face-details
                         hf selected))
                      (quantizations
                        (getf details
                              :quantizations))
                      (quantization
                        (and
                         quantizations
                         (cadr-agent:extension-context-select
                          context
                          "Select quantization"
                          (mapcar #'first
                                  quantizations))))
                      (model
                        (if quantization
                            (format nil "~A:~A"
                                    selected
                                    quantization)
                            selected)))
                 (when (getf details :gated)
                   (cadr-agent:extension-context-notify
                    context
                    (format nil
                            "Hugging Face access is ~A for ~A"
                            (getf details :gated)
                            selected)
                    :level :warning))
                 (llama-client-download-and-wait
                  client model
                  (llama-progress-notifier
                   context))
                 (refresh-llama-registry)
                 (cadr-agent:extension-context-notify
                 context
                  (format nil "Downloaded ~A"
                          model))))))))
      (t
       (let* ((index
                (position choice model-options
                          :test #'string=))
              (model
                (and index
                     (nth index catalog))))
         (when model
           (case (llama-model-info-status model)
             ((:loaded :sleeping)
              (when
                  (cadr-agent:extension-context-confirm
                   context
                   "Unload model?"
                   (llama-model-info-id model))
                (llama-client-unload
                 client
                 (llama-model-info-id model))
                (refresh-llama-registry)))
             (:unloaded
              (llama-client-load-and-wait
               client
               (llama-model-info-id model)
               (llama-progress-notifier context))
              (refresh-llama-registry))
             (otherwise
              (cadr-agent:extension-context-notify
               context
               (format nil
                       "~A is ~(~A~)"
                       (llama-model-info-id model)
                       (llama-model-info-status model))
               :level :warning)))))))))

(defun handle-llama-command (arguments context)
  (multiple-value-bind (action target)
      (split-llama-command-arguments arguments)
    (let ((client
            (llama-command-client
             context
             (string= action "login"))))
      (cond
        ((or
          (zerop (length action))
          (string= action "list")
          (string= action "login"))
         (let ((catalog
                 (llama-client-list client)))
           (if
               (and
                (zerop (length action))
                (eq
                 :tui
                 (cadr-agent:extension-context-mode
                  context)))
               (llama-interactive-action
                context client catalog)
               (notify-llama-catalog
                context catalog))))
        ((and (string= action "load")
              (plusp (length target)))
         (llama-client-load-and-wait
          client target
          (llama-progress-notifier context))
         (refresh-llama-registry))
        ((and (string= action "unload")
              (plusp (length target)))
         (llama-client-unload client target)
         (refresh-llama-registry))
        ((and (string= action "download")
              (plusp (length target)))
         (llama-client-download-and-wait
          client target
          (llama-progress-notifier context))
         (refresh-llama-registry))
        (t
         (error
          'cadr-agent:extension-execution-error
          :message
          "Usage: /llama [login|list|load <model>|unload <model>|download <repo[:quant]>]")))))
  nil)

(defun llama-extension-factory (api)
  (declare (ignore api))
  (let ((controller
          (make-llama-provider-controller)))
    (cadr-agent:define-native-provider
     (llama-provider-controller-provider
      controller))
    (cadr-agent:define-command
     "llama"
     :description
     "Manage llama.cpp router models"
     :argument-hint
     "[login|list|load|unload|download]"
     :handler #'handle-llama-command)))
