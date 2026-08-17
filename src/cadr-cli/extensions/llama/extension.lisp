(in-package #:cadr-cli)

(defun llama-gated-approval-text (gated)
  ;; huggingface.lisp stores :manual/:auto. Comparing the wire
  ;; string "manual" here is always NIL (pi index.ts:143).
  (if (eq gated :manual)
      "Manual approval is required"
      "Accept the access terms"))

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

(defun llama-loaded-model-p (model)
  (member (llama-model-info-status model) '(:loaded :sleeping)))

(defun llama-view-catalog-or-retry (context view client)
  "Baseline readCatalog: retry connection errors through the view until
the user closes."
  (loop
    (handler-case
        (let ((catalog (llama-client-list client)))
          (refresh-llama-registry)
          (return catalog))
      (error (cause)
        (when
            (eq
             (llama-view-connection-error
              view
              (llama-client-server-url client)
              (princ-to-string cause))
             :close)
          (return nil))))))

(defun llama-view-unload-model (context view client model)
  "Baseline unloadModel: confirm, unload, refresh, notify."
  (when
      (llama-view-confirm
       view "Unload model?" (llama-model-info-id model))
    (llama-client-unload client (llama-model-info-id model))
    (refresh-llama-registry)
    (cadr-agent:extension-context-notify
     context
     (format nil "Unloaded ~A" (llama-model-info-id model)))))

(defun llama-view-load-model (context view client catalog model)
  "Baseline loadModel: the replace-loaded choice, the cancellable
progress load, and the restore-on-cancel path."
  (let ((loaded
         (remove-if-not
          #'llama-loaded-model-p
          (remove model catalog :test #'eq))))
    (let ((replace-p nil))
      (when loaded
        (let ((choice
               (llama-view-select
                view
                (format
                 nil "~D model~:P ~[are~;is~:;are~] loaded"
                 (length loaded)
                 (if (= 1 (length loaded)) 1 0))
                '("Unload all and load"
                  "Keep loaded and load"
                  "Cancel"))))
          (when (or (null choice) (string= choice "Cancel"))
            (return-from llama-view-load-model nil))
          (setf replace-p (string= choice "Unload all and load"))))
      (flet ((restore-loaded ()
               (cadr-agent:extension-context-notify
                context "Restoring previously loaded models")
               (dolist (previous loaded)
                 (llama-client-load-and-wait
                  client (llama-model-info-id previous) nil))
               (refresh-llama-registry)))
        (when replace-p
          (dolist (previous loaded)
            (llama-client-unload
             client (llama-model-info-id previous))))
        (handler-case
            (multiple-value-bind (entry cancelled-p)
                (run-llama-with-progress
                 view
                 :title "Loading model"
                 :model (llama-model-info-id model)
                 :initial-message "Starting…"
                 :cancel-title "Stop loading?"
                 :cancel-message (llama-model-info-id model)
                 :run (lambda (update)
                        (llama-client-load-and-wait
                         client
                         (llama-model-info-id model)
                         (lambda (progress)
                           (funcall
                            update
                            :message (getf progress :message)
                            :ratio (getf progress :ratio)
                            :detail (getf progress :detail)))))
                 :cancel
                 (lambda ()
                   (llama-client-unload
                    client (llama-model-info-id model))))
              (when cancelled-p
                (when replace-p (restore-loaded))
                (return-from llama-view-load-model nil))
              (refresh-llama-registry)
              (cadr-agent:extension-context-notify
               context
               (if (eq :loaded (llama-model-info-status entry))
                   (format nil "Loaded ~A" (llama-model-info-id model))
                   (format
                    nil
                    "Load started for ~A"
                    (llama-model-info-id model)))))
          (error (cause)
            (when replace-p
              (ignore-errors (restore-loaded)))
            (error cause)))))))

(defun llama-quantization-option-label (entry)
  "Baseline downloadModel option text: name, plus size, plus the
Q4_K_M recommended marker, joined with \' · \'."
  (let ((details
         (append
          (and (getf entry :size)
               (list (format-llama-bytes (getf entry :size))))
          (and
           (string= (getf entry :name) "Q4_K_M")
           (list "recommended")))))
    (if details
        (format nil "~A · ~{~A~^ · ~}" (getf entry :name) details)
        (getf entry :name))))

(defun llama-view-download-model (context view client)
  "Baseline downloadModel: live Hugging Face search, gated-access
notice, quantization select with sizes, cancellable download."
  (let* ((hf
          (make-hugging-face-client :token (find-hugging-face-token)))
         (selected
          (llama-view-search-models
           view
           (lambda (query)
             (mapcar
              (lambda (result)
                (list
                 :id (first result)
                 :downloads (second result)))
              (hugging-face-search hf query))))))
    (unless selected
      (return-from llama-view-download-model nil))
    (multiple-value-bind (repository quantization)
        (parse-llama-hugging-face-model selected)
      (llama-view-show-status view "Loading model details" repository)
      (let ((details (hugging-face-details hf repository)))
        (when (getf details :gated)
          (let* ((approval
                  (llama-gated-approval-text
                   (getf details :gated)))
                 (choice
                  (llama-view-select
                   view
                   (format
                     nil
                     "Hugging Face access required~%~A~2%~A at:~%https://huggingface.co/~A~2%The llama.cpp server needs HF_TOKEN with access."
                     (getf details :id)
                     approval
                     (getf details :id))
                   '("Continue" "Back"))))
            (unless (string= choice "Continue")
              (return-from llama-view-download-model nil))))
        (when (and (not quantization) (getf details :quantizations))
          (let* ((quantizations (getf details :quantizations))
                 (options
                  (mapcar
                   #'llama-quantization-option-label
                   quantizations))
                 (choice
                  (and options
                       (llama-view-select
                        view
                        (format
                         nil "Select quantization~%~A"
                         (getf details :id))
                        options))))
            (if (null choice)
                (return-from llama-view-download-model nil)
                (setf
                 quantization
                 (getf
                  (nth (position choice options :test #'string=)
                       quantizations)
                  :name)))
            (unless quantization
              (return-from llama-view-download-model nil))))
        (let ((model
               (if quantization
                   (format nil "~A:~A" (getf details :id) quantization)
                   (getf details :id))))
          (multiple-value-bind (catalog cancelled-p)
              (run-llama-with-progress
               view
               :title "Downloading model"
               :model model
               :initial-message "Starting…"
               :cancel-title "Stop download?"
               :cancel-message model
               :run (lambda (update)
                      (llama-client-download-and-wait
                       client model
                       (lambda (progress)
                         (funcall
                          update
                          :message (getf progress :message)
                          :ratio (getf progress :ratio)
                          :detail (getf progress :detail)))))
               :cancel
               (lambda () (llama-client-unload client model)))
            (unless cancelled-p
              (refresh-llama-registry)
              (cadr-agent:extension-context-notify
               context (format nil "Downloaded ~A" model))
              catalog)))))))

(defun llama-interactive-action
    (context client initial-catalog)
  "Baseline showLlamaUi session (extensions/llama/index.ts): one
persistent framed view; showModels loop until close."
  (show-llama-ui
   context
   (lambda (view)
    (block llama-session
     (let ((catalog
            (or initial-catalog
                (llama-view-catalog-or-retry context view client))))
       (unless catalog
         (return-from llama-session nil))
       (loop
         (let ((action
                (llama-view-show-models
                 view (llama-client-server-url client) catalog)))
           (let ((action-error nil))
             (cond
               ((null action)
                (return))
               ((eq action :download)
                (handler-case
                    (llama-view-download-model context view client)
                  (error (cause) (setf action-error cause))))
               ((llama-loaded-model-p action)
                (handler-case
                    (llama-view-unload-model context view client action)
                  (error (cause) (setf action-error cause))))
               ((eq :unloaded (llama-model-info-status action))
                (handler-case
                    (llama-view-load-model
                     context view client catalog action)
                  (error (cause) (setf action-error cause))))
               (t
                (cadr-agent:extension-context-notify
                 context
                 (format
                  nil "~A is ~(~A~)"
                  (llama-model-info-id action)
                  (llama-model-info-status action))
                 :level :warning)))
             (let ((refreshed
                    (llama-view-catalog-or-retry context view client)))
               (unless refreshed (return))
               (setf catalog refreshed))
             (when action-error
              (cadr-agent:extension-context-notify
               context
               (princ-to-string action-error)
               :level :error))))))))))

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
