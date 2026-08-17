(in-package #:cadr-cli)

;;; Baseline: packages/coding-agent/src/cli/auth-command.ts,
;;; cli/auth-check.ts, cli/credential-print.ts (v0.84.1).  The auth
;;; command surface covers print-api-key, print-bearer-token, and the
;;; auth check subcommand; upstream renamed CredentialPrintError to
;;; AuthCommandError.

(define-condition auth-command-error (error)
  ((message :initarg :message
            :reader auth-command-error-message))
  (:report
   (lambda (condition stream)
     (write-string
      (auth-command-error-message condition)
      stream))))

(defun parse-duration-milliseconds (value)
  (multiple-value-bind (match groups)
      (cl-ppcre:scan-to-strings
       "^([0-9]+)(ms|s|m|h)?$" value)
    (unless match
      (error 'auth-command-error
             :message
             "--min-expiry must use a duration such as 30m or 1h"))
    (* (parse-integer (aref groups 0))
       (cond
         ((string= (aref groups 1) "h") 3600000)
         ((string= (aref groups 1) "m") 60000)
         ((string= (aref groups 1) "s") 1000)
         (t 1)))))

(defun auth-command-name (kind)
  ;; Baseline getAuthCommandName.
  (ecase kind
    (:check "auth check")
    (:api-key "auth print-api-key")
    (:bearer-token "auth print-bearer-token")))

(defun auth-command-usage (kind)
  ;; Baseline AUTH_COMMAND_USAGE with the cadr product name.
  (ecase kind
    (:check
     "cadr auth check --provider <provider> [--json] [--credentials] [--no-refresh]")
    (:api-key
     "cadr auth print-api-key --provider <provider> [--model <model>]")
    (:bearer-token
     "cadr auth print-bearer-token --provider <provider> [--model <model>] [--min-expiry <duration>]")))

(defun auth-command-help-request-p (arguments)
  ;; Baseline isAuthCommandHelp: bare "auth", "auth help", or a help
  ;; flag anywhere in the auth arguments.
  (and arguments
       (string= (first arguments) "auth")
       (or (null (rest arguments))
           (string= (second arguments) "help")
           (member "--help" (rest arguments) :test #'string=)
           (member "-h" (rest arguments) :test #'string=))))

(defun print-auth-command-help
    (&optional (stream *standard-output*))
  ;; Baseline printAuthCommandHelp with the cadr product name.
  (format
   stream
   "Usage:~%  cadr auth print-api-key [--provider <provider>] [--model <model>]~%  cadr auth print-bearer-token [--provider <provider>] [--model <model>] [--min-expiry <duration>]~%  cadr auth check [--provider <provider>] [--model <model>] [--json] [--credentials] [--no-refresh]~%~%Auth commands require at least one of --provider or --model. Checks refresh expired OAuth credentials by default; --no-refresh prevents this. --credentials emits the credential, or includes it in JSON output.~%")
  (finish-output stream))

(defun parse-auth-command (arguments)
  ;; Baseline parseAuthCommand.  Returns NIL when ARGUMENTS is not an
  ;; auth command, (:help-p t) for a help request, else a plist with
  ;; :kind/:arguments and the check/print flags.
  (unless (and arguments
               (string= (first arguments) "auth"))
    (return-from parse-auth-command nil))
  (when (auth-command-help-request-p arguments)
    (return-from parse-auth-command (list :help-p t)))
  (let ((command (second arguments))
        (kind nil))
    (cond
      ((string= command "check") (setf kind :check))
      ((string= command "print-api-key") (setf kind :api-key))
      ((string= command "print-bearer-token")
       (setf kind :bearer-token))
      (t
       (error 'auth-command-error
              :message
              (format nil
                      "Unknown auth command \"~A\". Use \"cadr auth print-api-key\", \"cadr auth print-bearer-token\", or \"cadr auth check\"."
                      command))))
    (let ((rest (cddr arguments))
          (forwarded nil)
          (json-p nil)
          (credentials-p nil)
          (no-refresh-p nil)
          (minimum-expiry nil))
      (loop while rest
            for argument = (pop rest)
            do
            (cond
              ((string= argument "--min-expiry")
               (unless (eq kind :bearer-token)
                 (error 'auth-command-error
                        :message
                        "--min-expiry is only supported by print-bearer-token"))
               (unless rest
                 (error 'auth-command-error
                        :message
                        "--min-expiry must use a duration such as 30m or 1h"))
               (setf minimum-expiry
                     (parse-duration-milliseconds (pop rest))))
              ((member argument
                       '("--json" "--credentials" "--no-refresh")
                       :test #'string=)
               (unless (eq kind :check)
                 (error 'auth-command-error
                        :message
                        (format nil
                                "~A is only supported by auth check"
                                argument)))
               (cond
                 ((string= argument "--json") (setf json-p t))
                 ((string= argument "--credentials")
                  (setf credentials-p t))
                 (t (setf no-refresh-p t))))
              (t
               (push argument forwarded))))
      (list :kind kind
            :arguments (nreverse forwarded)
            :json-p json-p
            :credentials-p credentials-p
            :no-refresh-p no-refresh-p
            :minimum-expiry-ms minimum-expiry))))

(defun validate-auth-command-args (cli kind)
  ;; Baseline validateAuthCommandArgs.  Returns
  ;; (values provider model); signals AUTH-COMMAND-ERROR on misuse.
  (let ((provider
          (let ((value (cli-arguments-provider cli)))
            (and value
                 (plusp (length (string-trim " " value)))
                 (string-trim " " value))))
        (model
          (let ((value (cli-arguments-model cli)))
            (and value
                 (plusp (length (string-trim " " value)))
                 (string-trim " " value)))))
    (when (or (cli-arguments-api-key cli)
              (cli-arguments-messages cli)
              (cli-arguments-file-arguments cli))
      (error 'auth-command-error
             :message
             "Auth commands only accept --provider and --model"))
    (if (eq kind :check)
        (unless (or provider model)
          (error 'auth-command-error
                 :message
                 "Auth checks require --provider <provider> or --model <model>"))
        (unless (or provider model)
          (error 'auth-command-error
                 :message
                 "Credential printing requires --provider <provider> or --model <model>")))
    (values provider model)))

(defun auth-command-oauth-refresh-function (provider)
  ;; The OAuth refresh flow for PROVIDER when one is wired for the
  ;; one-shot CLI context; NIL otherwise.  The :kimi and :radius
  ;; strategies need the runtime environment/gateway, which this
  ;; context does not have.
  (let ((definition
          (cadr-ai:find-provider-definition provider)))
    (when definition
      (case (cadr-ai::provider-definition-oauth-refresh-strategy
             definition)
        (:anthropic #'cadr-ai:refresh-anthropic-oauth-credential)
        (:github-copilot
         #'cadr-ai::refresh-github-copilot-oauth-credential)
        (:openai-device #'cadr-ai:refresh-openai-oauth-credential)
        (:openrouter #'cadr-ai::refresh-openrouter-oauth-credential)
        (:xai #'cadr-ai::refresh-xai-oauth-credential)
        (otherwise nil)))))

(defun credential-for-print
    (storage provider kind
     &key refresh-function
       (minimum-expiry-ms 300000))
  (let ((credential
          (auth-storage-read storage provider)))
    (unless credential
      (error 'auth-command-error
             :message
             (if (eq kind :api-key)
                 "No usable API key is configured"
                 "No usable OAuth bearer token is configured")))
    (ecase kind
      (:api-key
       (unless
           (typep credential
                  'cadr-ai:api-key-credential)
         (error 'auth-command-error
                :message
                (format nil
                        "Provider \"~A\" is configured with OAuth, not an API key"
                        provider)))
       (cadr-ai:api-key-credential-key
        credential))
      (:bearer-token
       (unless
           (typep credential
                  'cadr-ai:oauth-credential)
         (error 'auth-command-error
                :message
                (format nil
                        "Provider \"~A\" is not configured with an OAuth bearer token"
                        provider)))
       (when
           (<=
            (cadr-ai:oauth-credential-expires
             credential)
            (+ (cadr-ai::unix-milliseconds)
               minimum-expiry-ms))
         (unless refresh-function
           (error 'auth-command-error
                  :message
                  "No usable OAuth bearer token is configured"))
         (setf credential
               (auth-storage-modify
                storage provider
                (lambda (current)
                  (funcall refresh-function
                           current)))))
       (cadr-ai:oauth-credential-access
        credential)))))

(defun auth-command-candidate-credential
    (storage provider-id kind minimum-expiry-ms)
  ;; The getAuth leg of resolveCredentialForPrint: the credential value
  ;; for one candidate provider, or NIL when the stored credential does
  ;; not serve KIND.
  (let ((credential
          (ignore-errors (auth-storage-read storage provider-id))))
    (when credential
      (if (eq kind :api-key)
          (and (typep credential 'cadr-ai:api-key-credential)
               (cadr-ai:api-key-credential-key credential))
          (and (typep credential 'cadr-ai:oauth-credential)
               (ignore-errors
                (credential-for-print
                 storage provider-id :bearer-token
                 :refresh-function
                 (auth-command-oauth-refresh-function
                  (provider-symbol-from-key provider-id))
                 :minimum-expiry-ms minimum-expiry-ms)))))))

(defun auth-command-model-match-p (available provider model-id)
  (find-if
   (lambda (candidate)
     (and
      (string=
       (cadr-ai:model-id candidate)
       model-id)
      (string-equal
       (provider-key
        (cadr-ai:model-provider candidate))
       provider)))
   available))

(defun resolve-credential-for-print
    (cli registry storage kind minimum-expiry-ms)
  ;; Baseline resolveCredentialForPrint (credential-print.ts).
  (multiple-value-bind (cli-provider cli-model)
      (validate-auth-command-args cli kind)
    (let* ((available (model-registry-all registry))
           (stored
             (mapcar #'car (auth-storage-list storage)))
           (candidates nil))
      (when (null available)
        (error 'auth-command-error
               :message
               "No models available. Check your installation or add models to models.json."))
      (cond
        (cli-provider
         (unless
             (find
              cli-provider available
              :key
              (lambda (candidate)
                (provider-key
                 (cadr-ai:model-provider candidate)))
              :test #'string-equal)
           (error 'auth-command-error
                  :message
                  (format nil
                          "Unknown provider \"~A\". Use --list-models to see available providers."
                          cli-provider)))
         (when cli-model
           (let ((model-spec
                   (parse-model-spec cli-model cli-provider)))
             (unless
                 (auth-command-model-match-p
                  available cli-provider
                  (getf model-spec :model))
               (error 'auth-command-error
                      :message
                      (format nil
                              "Model \"~A\" not found. Use --list-models to see available models."
                              cli-model)))))
         (setf candidates (list cli-provider)))
        (t
         (let ((model-spec (parse-model-spec cli-model nil)))
           (dolist (provider stored)
             (when
                 (auth-command-model-match-p
                  available provider
                  (getf model-spec :model))
               (push provider candidates)))
           (setf candidates (nreverse candidates))
           (unless candidates
             (error 'auth-command-error
                    :message
                    (format nil
                            "Model \"~A\" not found. Use --list-models to see available models."
                            cli-model))))))
      (let ((resolved nil))
        (dolist (provider candidates)
          (let ((value
                  (auth-command-candidate-credential
                   storage provider kind
                   (or minimum-expiry-ms 300000))))
            (when value
              (push (cons provider value) resolved))))
        (setf resolved (nreverse resolved))
        (cond
          ((null resolved)
           (let* ((provider-id (first candidates))
                  (stored-credential
                    (and provider-id
                         (ignore-errors
                          (auth-storage-read storage provider-id))))
                  (oauth-p
                    (typep stored-credential
                           'cadr-ai:oauth-credential)))
             (cond
               ((and cli-provider (eq kind :api-key) oauth-p)
                (error 'auth-command-error
                       :message
                       (format nil
                               "Provider \"~A\" is configured with OAuth, not an API key"
                               provider-id)))
               ((and cli-provider
                     (eq kind :bearer-token)
                     (not oauth-p))
                (error 'auth-command-error
                       :message
                       (format nil
                               "Provider \"~A\" is not configured with an OAuth bearer token"
                               provider-id)))
               (t
                (error 'auth-command-error
                       :message
                       (if (eq kind :api-key)
                           "No usable API key is configured"
                           "No usable OAuth bearer token is configured"))))))
          ((null (rest resolved))
           (cdr (first resolved)))
          (t
           (error 'auth-command-error
                  :message
                  (format nil
                          "Multiple configured providers matched (~{~A~^, ~}). Specify --provider."
                          (mapcar #'car resolved)))))))))

(defun check-provider-auth (cli registry storage refresh-p)
  ;; Baseline checkProviderAuth (auth-check.ts).  Returns
  ;; (values status provider reason auth-type); STATUS is one of
  ;; :ready, :not-ready, :invalid.
  (multiple-value-bind (cli-provider cli-model)
      (validate-auth-command-args cli :check)
    (let ((provider cli-provider)
          (available (model-registry-all registry)))
      (when cli-model
        (let ((model-spec
                (parse-model-spec cli-model cli-provider)))
          (unless
              (auth-command-model-match-p
               available
               (or (getf model-spec :provider) cli-provider)
               (getf model-spec :model))
            (error 'auth-command-error
                   :message
                   (format nil
                           "Unable to resolve model \"~A\""
                           cli-model)))
          (setf provider
                (or (getf model-spec :provider) cli-provider))))
      (unless provider
        (error 'auth-command-error
               :message "Unable to resolve an auth provider"))
      (cond
        ((model-registry-error registry)
         (values :invalid provider "invalid_state" nil))
        ((not
          (find
           provider available
           :key
           (lambda (candidate)
             (provider-key
              (cadr-ai:model-provider candidate)))
           :test #'string-equal))
         (values :not-ready provider "provider_not_found" nil))
        (t
         (handler-case
             (let ((credential
                     (auth-storage-read storage provider)))
               (cond
                 ((null credential)
                  (values :not-ready provider
                          "credentials_not_configured" nil))
                 ((and refresh-p
                       (typep credential 'cadr-ai:oauth-credential)
                       (null
                        (ignore-errors
                         (credential-for-print
                          storage provider :bearer-token
                          :refresh-function
                          (auth-command-oauth-refresh-function
                           (provider-symbol-from-key provider))
                          :minimum-expiry-ms 300000))))
                  (values :not-ready provider
                          "credentials_not_configured" nil))
                 (t
                  (values :ready provider nil
                          (credential-kind-name credential)))))
           (condition ()
             (values :invalid provider "invalid_state" nil))))))))

(defun auth-command-status-text (status)
  (string-downcase
   (substitute #\_ #\- (symbol-name status))))

(defun auth-check-json-output
    (status provider reason auth-type credential)
  ;; Baseline JSON.stringify({ ...result, ...(credential ? { credentials } : {}) });
  ;; key order is status, provider, reason|authType, credentials.
  (with-output-to-string (stream)
    (write-char #\{ stream)
    (write-string "\"status\":" stream)
    (cadr-ai::write-json-string
     (auth-command-status-text status) stream)
    (write-string ",\"provider\":" stream)
    (cadr-ai::write-json-string provider stream)
    (when reason
      (write-string ",\"reason\":" stream)
      (cadr-ai::write-json-string reason stream))
    (when auth-type
      (write-string ",\"authType\":" stream)
      (cadr-ai::write-json-string auth-type stream))
    (when credential
      (write-string ",\"credentials\":" stream)
      (cadr-ai::write-json-string credential stream))
    (write-char #\} stream)))

(defun run-auth-command
    (arguments
     &key
       (auth-path (default-auth-path))
       (output *standard-output*))
  ;; Baseline main.ts handleAuthCommand.  Parse failures exit 1;
  ;; post-parse auth errors exit 1 for print and 2 for check; check
  ;; results exit 0 (ready), 1 (not_ready), or 2 (invalid).
  (unless (and arguments
               (string= (first arguments) "auth"))
    (return-from run-auth-command (values nil nil)))
  (when (auth-command-help-request-p arguments)
    (print-auth-command-help output)
    (return-from run-auth-command (values t 0)))
  (let ((parsed nil))
    (handler-case
        (setf parsed (parse-auth-command arguments))
      (auth-command-error (condition)
        (format
         *error-output*
         "~A~%"
         (cli-error-text
          *error-output*
          (format
           nil
           "Error: ~A"
           (auth-command-error-message condition))))
        (finish-output *error-output*)
        (return-from run-auth-command (values t 1))))
    (handler-case
        (run-auth-command-1 parsed auth-path output)
      (auth-command-error (condition)
        (format
         *error-output*
         "~A~%"
         (cli-error-text
          *error-output*
          (format
           nil
           "Error: ~A"
           (auth-command-error-message condition))))
        (finish-output *error-output*)
        (values
         t
         (if (eq (getf parsed :kind) :check) 2 1))))))

(defun run-auth-command-1 (parsed auth-path output)
  (let* ((kind (getf parsed :kind))
         (cli
           (parse-cli-arguments
            (getf parsed :arguments)))
         (unknown
           (cli-arguments-unknown-flags cli)))
    (when (plusp (hash-table-count unknown))
      (let ((option
              (first
               (sort
                (loop for key being the hash-keys of unknown
                      collect key)
                #'string<))))
        ;; Baseline prints the red unknown-option line plus the dim
        ;; usage hint and exits 1.
        (format
         *error-output*
         "~A~%~A~%"
         (cli-error-text
          *error-output*
          (format nil
                  "Unknown option --~A for \"~A\"."
                  option (auth-command-name kind)))
         (cli-dim-text
          *error-output*
          (format nil
                  "Use \"cadr --help\" or \"~A\"."
                  (auth-command-usage kind))))
        (finish-output *error-output*)
        (return-from run-auth-command-1 (values t 1))))
    (let ((diagnostics
            (remove-if-not
             (lambda (diagnostic)
               (eq (getf diagnostic :type) :error))
             (cli-arguments-diagnostics cli))))
      (when diagnostics
        (error 'auth-command-error
               :message
               (format nil "~{~A~^~%~}"
                       (mapcar
                        (lambda (diagnostic)
                          (getf diagnostic :message))
                        diagnostics)))))
    (let ((registry
            (make-model-registry
             :path
             (merge-pathnames
              "models.json"
              (default-agent-directory))
             :credentials
             (make-file-auth-storage auth-path)))
          (storage (make-file-auth-storage auth-path)))
      (if (eq kind :check)
          (run-auth-check parsed cli registry storage output)
          (progn
           (format
            output "~A~%"
            (resolve-credential-for-print
             cli registry storage kind
             (getf parsed :minimum-expiry-ms)))
           (finish-output output)
           (values t 0))))))

(defun run-auth-check (parsed cli registry storage output)
  (let ((refresh-p (not (getf parsed :no-refresh-p)))
        (requested
          (or (cli-arguments-provider cli)
              (cli-arguments-model cli))))
    ;; Baseline validateAuthCommandArgs runs before the silent catch.
    (validate-auth-command-args cli :check)
    (multiple-value-bind (status provider reason auth-type)
        ;; Baseline wraps the whole check in a catch that collapses
        ;; every failure to invalid/invalid_state.
        (handler-case
            (check-provider-auth cli registry storage refresh-p)
          (condition ()
            (values :invalid requested "invalid_state" nil)))
      (let ((credential nil)
            (final-status status)
            (final-reason reason)
            (final-auth-type auth-type))
        (when (and (getf parsed :credentials-p)
                   (eq status :ready))
          (setf credential
                (let ((stored
                        (ignore-errors
                         (auth-storage-read storage provider))))
                  (cond
                    ((typep stored 'cadr-ai:api-key-credential)
                     (cadr-ai:api-key-credential-key stored))
                    ((typep stored 'cadr-ai:oauth-credential)
                     (if refresh-p
                         (auth-command-candidate-credential
                          storage provider :bearer-token 300000)
                         (cadr-ai:oauth-credential-access stored)))
                    (t nil))))
          (unless credential
            (setf final-status :not-ready
                  final-reason "credential_not_available"
                  final-auth-type nil)))
        (format
         output "~A~%"
         (if (getf parsed :json-p)
             (auth-check-json-output
              final-status provider final-reason
              final-auth-type credential)
             (or credential
                 (auth-command-status-text final-status))))
        (finish-output output)
        (values
         t
         (case final-status
           (:ready 0)
           (:not-ready 1)
           (t 2)))))))
