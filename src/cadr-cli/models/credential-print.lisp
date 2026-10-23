(in-package #:cadr-cli)

;;; Baseline: packages/coding-agent/src/cli/auth-command.ts,
;;; cli/auth-check.ts, cli/credential-print.ts (v0.84.1).  The auth
;;; command surface covers print-api-key, print-bearer-token, and the
;;; auth check subcommand; upstream renamed CredentialPrintError to
;;; AuthCommandError.
;;;
;;; packages/ai/src/cli.ts (v1.4.0) is the separate library CLI:
;;; help, list, and login for providers that have OAuth, writing
;;; ./auth.json.  cadr exposes that as `cadr ai`.

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
  ;; Same CLI refresh table as resolve-stored-credential.  Kimi/Radius
  ;; use the wrappers that default host/gateway when env is absent.
  (cdr
   (assoc
    (provider-symbol-from-key provider)
    +oauth-login-providers+)))

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

(define-condition ai-cli-error (error)
  ((message :initarg :message :reader ai-cli-error-message))
  (:report (lambda (condition stream)
             (write-string (ai-cli-error-message condition) stream))))

(defparameter +ai-cli-reserved-credential-keys+
  '("type" "access" "refresh" "expires" "accountId"))

(defun ai-cli-condition-message (condition)
  (cond
    ((typep condition 'ai-cli-error)
     (ai-cli-error-message condition))
    ((typep condition 'cadr-ai:cadr-error)
     (cadr-ai:cadr-error-message condition))
    (t (princ-to-string condition))))

(defun ai-cli-oauth-providers ()
  ;; v1.4.0 packages/ai/src/providers/all.ts builtinProviders(),
  ;; filtered to auth.oauth.  Row order is that construction order.
  ;; openai-codex's provider name at that tag is the legacy label.
  (loop for row in cadr-ai::*built-in-provider-definition-rows*
        for id = (getf row :id)
        when (getf row :oauth-login-strategy)
          collect (cons (string-downcase (symbol-name id))
                        (if (eq id :openai-codex)
                            "OpenAI Codex (legacy)"
                            (getf row :name)))))

(defun ai-cli-provider-lines (&optional (prefix ""))
  ;; v1.4.0 cli.ts help is `  ${id.padEnd(20)} ${name}`; list omits
  ;; those two spaces.
  (loop for (id . name) in (ai-cli-oauth-providers)
        collect (format nil "~A~A ~A"
                        prefix (cli-pad-right id 20) name)))

(defun ai-cli-usage-text ()
  (with-output-to-string (stream)
    (write-string "Usage: cadr ai <command> [provider]" stream)
    (terpri stream)
    (terpri stream)
    (write-string "Commands:" stream)
    (terpri stream)
    (write-string
     "  login [provider]  Login to an OAuth provider" stream)
    (terpri stream)
    (write-string
     "  list              List available providers" stream)
    (terpri stream)
    (terpri stream)
    (write-string "Providers:" stream)
    (dolist (line (ai-cli-provider-lines "  "))
      (terpri stream)
      (write-string line stream))))

(defun ai-cli-parse-int (text)
  ;; Number.parseInt(text, 10): leading whitespace, optional sign,
  ;; then digits.  Junk after the digits is ignored.  No digit is NIL.
  (let ((index 0)
        (length (length text))
        (sign 1)
        (digits nil))
    (loop while (and (< index length)
                     (member (char text index)
                             '(#\Space #\Tab #\Newline #\Return
                               #\Page #\Vt)))
          do (incf index))
    (when (< index length)
      (case (char text index)
        (#\+ (incf index))
        (#\- (setf sign -1) (incf index))))
    (loop while (and (< index length)
                     (digit-char-p (char text index)))
          do (push (digit-char-p (char text index)) digits)
             (incf index))
    (when digits
      (* sign
         (reduce (lambda (accumulator digit)
                   (+ (* accumulator 10) digit))
                 (nreverse digits))))))

(defun ai-cli-read-answer (input output question)
  (write-string question output)
  (finish-output output)
  (or (read-line input nil nil) ""))

(defun ai-cli-answer-prompt (input output prompt)
  (if (eq (getf prompt :type) :select)
      (let* ((options (getf prompt :options))
             (count (length options)))
        (format output "~%~A~%" (getf prompt :message))
        (loop for option in options
              for index from 1
              do (format output "  ~D. ~A~%"
                         index (getf option :label)))
        (let ((choice
                (ai-cli-parse-int
                 (ai-cli-read-answer
                  input output
                  (format nil "Enter number (1-~D): " count)))))
          (unless (and choice (<= 1 choice count))
            (error 'ai-cli-error :message "Invalid selection"))
          (getf (nth (1- choice) options) :id)))
      (let ((placeholder (getf prompt :placeholder)))
        (ai-cli-read-answer
         input output
         (format nil "~A~A: "
                 (getf prompt :message)
                 (if (and (stringp placeholder)
                          (plusp (length placeholder)))
                     (format nil " (~A)" placeholder)
                     ""))))))

(defun ai-cli-notify (output event)
  (case (getf event :type)
    (:auth-url
     (format output "~%Open this URL in your browser:~%~A~%"
             (getf event :url))
     (let ((instructions (getf event :instructions)))
       (when (and (stringp instructions)
                  (plusp (length instructions)))
         (format output "~A~%" instructions))))
    (:device-code
     (format output "~%Open this URL in your browser:~%~A~%"
             (getf event :verification-uri))
     (format output "Enter code: ~A~%" (getf event :user-code)))
    ((:info :progress)
     (format output "~A~%" (getf event :message))))
  (finish-output output))

(defun ai-cli-random-uuid ()
  ;; crypto.randomUUID: version 4, variant 8/9/a/b, lowercase.
  (let ((bytes (cadr-ai::default-random-octets 16)))
    (setf (aref bytes 6)
          (logior #x40 (logand (aref bytes 6) #x0f))
          (aref bytes 8)
          (logior #x80 (logand (aref bytes 8) #x3f)))
    (let ((hex (cadr-ai::octets-hex bytes)))
      (format nil "~A-~A-~A-~A-~A"
              (subseq hex 0 8)
              (subseq hex 8 12)
              (subseq hex 12 16)
              (subseq hex 16 20)
              (subseq hex 20 32)))))

(defun ai-cli-json-from-lisp (value)
  (cond
    ((stringp value) value)
    ((integerp value) value)
    ((eq value t) :true)
    ((eq value nil) :false)
    ((eq value 'null) :null)
    ((and (consp value) (eq (car value) :object)) value)
    ((vectorp value)
     (map 'vector #'ai-cli-json-from-lisp value))
    ((consp value)
     (if (and (consp (car value)) (stringp (caar value)))
         (cons :object
               (loop for pair in value
                     collect (cons (car pair)
                                   (ai-cli-json-from-lisp (cdr pair)))))
         (map 'vector #'ai-cli-json-from-lisp value)))
    ((floatp value) value)
    (t (error 'ai-cli-error
              :message "Login returned an invalid credential"))))

(defun ai-cli-credential-object (credential)
  (unless (typep credential 'cadr-ai:oauth-credential)
    (error 'ai-cli-error
           :message "Login returned an invalid credential"))
  (cons :object
        (append
         (list (cons "type" "oauth")
               (cons "access"
                     (cadr-ai:oauth-credential-access credential))
               (cons "refresh"
                     (cadr-ai:oauth-credential-refresh credential))
               (cons "expires"
                     (cadr-ai:oauth-credential-expires credential)))
         (when (cadr-ai:oauth-credential-account-id credential)
           (list (cons "accountId"
                       (cadr-ai:oauth-credential-account-id
                        credential))))
         (loop for entry in (cadr-ai:oauth-credential-metadata
                             credential)
               for key = (car entry)
               unless (member key +ai-cli-reserved-credential-keys+
                              :test #'string=)
                 collect (cons key
                               (ai-cli-json-from-lisp (cdr entry)))))))

(defun ai-cli-write-json (value stream level)
  (cond
    ((and (consp value) (eq (car value) :object))
     (let ((pairs (cdr value)))
       (if (null pairs)
           (write-string "{}" stream)
           (let ((pad (make-string (* 2 (1+ level))
                                   :initial-element #\Space))
                 (end (make-string (* 2 level)
                                   :initial-element #\Space)))
             (write-char #\{ stream)
             (loop for pair in pairs
                   for first-p = t then nil
                   do (unless first-p
                        (write-char #\, stream))
                      (terpri stream)
                      (write-string pad stream)
                      (cadr-ai::write-json-string (car pair) stream)
                      (write-string ": " stream)
                      (ai-cli-write-json (cdr pair) stream (1+ level)))
             (terpri stream)
             (write-string end stream)
             (write-char #\} stream)))))
    ((stringp value)
     (cadr-ai::write-json-string value stream))
    ((vectorp value)
     (if (zerop (length value))
         (write-string "[]" stream)
         (let ((pad (make-string (* 2 (1+ level))
                                 :initial-element #\Space))
               (end (make-string (* 2 level)
                                 :initial-element #\Space)))
           (write-char #\[ stream)
           (loop for item across value
                 for first-p = t then nil
                 do (unless first-p
                      (write-char #\, stream))
                    (terpri stream)
                    (write-string pad stream)
                    (ai-cli-write-json item stream (1+ level)))
           (terpri stream)
           (write-string end stream)
           (write-char #\] stream))))
    ((integerp value) (princ value stream))
    ((eq value :true) (write-string "true" stream))
    ((eq value :false) (write-string "false" stream))
    ((eq value :null) (write-string "null" stream))
    ((floatp value) (cadr-ai::write-json-value value stream))
    (t (error 'ai-cli-error
              :message "Login returned an invalid credential"))))

(defun ai-cli-stringify-json (value)
  (with-output-to-string (stream)
    (ai-cli-write-json value stream 0)))

(defun ai-cli-parse-json (text)
  (let ((index 0)
        (length (length text)))
    (labels
        ((peek ()
           (and (< index length) (char text index)))
         (take ()
           (prog1 (char text index) (incf index)))
         (skip ()
           (loop while (member (peek)
                               '(#\Space #\Tab #\Newline #\Return
                                 #\Page #\Vt))
                 do (incf index)))
         (fail ()
           (error 'ai-cli-error :message "Invalid auth.json"))
         (parse-string ()
           (unless (eql (take) #\")
             (fail))
           (with-output-to-string (out)
             (loop
               (when (>= index length) (fail))
               (let ((character (take)))
                 (cond
                   ((char= character #\") (return))
                   ((char= character #\\)
                    (when (>= index length) (fail))
                    (let ((escaped (take)))
                      (case escaped
                        (#\" (write-char #\" out))
                        (#\\ (write-char #\\ out))
                        (#\/ (write-char #\/ out))
                        (#\b (write-char #\Backspace out))
                        (#\f (write-char #\Page out))
                        (#\n (write-char #\Newline out))
                        (#\r (write-char #\Return out))
                        (#\t (write-char #\Tab out))
                        (#\u
                         (when (> (+ index 4) length) (fail))
                         (let ((code 0))
                           (dotimes (offset 4)
                             (let ((digit
                                     (digit-char-p
                                      (char text (+ index offset))
                                      16)))
                               (unless digit (fail))
                               (setf code (+ (* code 16) digit))))
                           (incf index 4)
                           (write-char (code-char code) out)))
                        (t (fail)))))
                   (t (write-char character out)))))))
         (parse-number ()
           (let ((start index))
             (when (eql (peek) #\-) (incf index))
             (unless (digit-char-p (or (peek) #\a)) (fail))
             (if (eql (peek) #\0)
                 (incf index)
                 (loop while (digit-char-p (or (peek) #\a))
                       do (incf index)))
             (when (eql (peek) #\.)
               (incf index)
               (unless (digit-char-p (or (peek) #\a)) (fail))
               (loop while (digit-char-p (or (peek) #\a))
                     do (incf index)))
             (when (member (peek) '(#\e #\E))
               (incf index)
               (when (member (peek) '(#\+ #\-)) (incf index))
               (unless (digit-char-p (or (peek) #\a)) (fail))
               (loop while (digit-char-p (or (peek) #\a))
                     do (incf index)))
             (let ((token (subseq text start index)))
               (if (find-if (lambda (character)
                              (member character '(#\. #\e #\E)))
                            token)
                   (cadr-ai::parse-json token)
                   (parse-integer token)))))
         (parse-literal (literal value)
           (let ((end (+ index (length literal))))
             (unless (and (<= end length)
                          (string= text literal
                                   :start1 index :end1 end))
               (fail))
             (setf index end)
             value))
         (parse-value ()
           (skip)
           (case (peek)
             (#\{ (parse-object))
             (#\[ (parse-array))
             (#\" (parse-string))
             (#\t (parse-literal "true" :true))
             (#\f (parse-literal "false" :false))
             (#\n (parse-literal "null" :null))
             ((#\- #\0 #\1 #\2 #\3 #\4 #\5 #\6 #\7 #\8 #\9)
              (parse-number))
             (t (fail))))
         (parse-object ()
           (take)
           (skip)
           (when (eql (peek) #\})
             (take)
             (return-from parse-object (list :object)))
           (let ((pairs nil))
             (loop
               (skip)
               (unless (eql (peek) #\") (fail))
               (let ((key (parse-string)))
                 (skip)
                 (unless (eql (take) #\:) (fail))
                 (push (cons key (parse-value)) pairs))
               (skip)
               (case (peek)
                 (#\, (take))
                 (#\} (take) (return))
                 (t (fail))))
             (cons :object (nreverse pairs))))
         (parse-array ()
           (take)
           (skip)
           (when (eql (peek) #\])
             (take)
             (return-from parse-array #()))
           (let ((items nil))
             (loop
               (push (parse-value) items)
               (skip)
               (case (peek)
                 (#\, (take))
                 (#\] (take) (return))
                 (t (fail))))
             (coerce (nreverse items) 'vector))))
      (let ((value (parse-value)))
        (skip)
        (when (< index length) (fail))
        value))))

(defun ai-cli-load-auth (path)
  ;; v1.4.0 loadAuth returns JSON.parse as-is.  A missing file or a
  ;; parse error is {}.  null, numbers, booleans, strings, and arrays
  ;; stay what they parsed as.
  (if (not (probe-file path))
      (list :object)
      (handler-case
          (ai-cli-parse-json
           (uiop:read-file-string path :external-format :utf-8))
        (error ()
          (list :object)))))

(defun ai-cli-js-number-text (value)
  (if (integerp value)
      (princ-to-string value)
      (cadr-ai::terminating-rational-json-text value)))

(defun ai-cli-assign-message (key value)
  ;; Node strict mode, the same sentences cli.ts prints via error.message.
  (cond
    ((eq value :null)
     (format nil "Cannot set properties of null (setting '~A')" key))
    ((eq value :true)
     (format nil "Cannot create property '~A' on boolean 'true'" key))
    ((eq value :false)
     (format nil "Cannot create property '~A' on boolean 'false'" key))
    ((stringp value)
     (format nil "Cannot create property '~A' on string '~A'" key value))
    ((numberp value)
     (format nil "Cannot create property '~A' on number '~A'"
             key (ai-cli-js-number-text value)))
    (t
     (format nil "Cannot create property '~A'" key))))

(defun ai-cli-object-put (object key value)
  (cond
    ((and (vectorp object) (not (stringp object)))
     ;; JSON.stringify keeps index properties only, so a provider id
     ;; never lands in the rewritten array.  A string is a vector in
     ;; Lisp and a primitive in JavaScript, so it must not take this path.
     object)
    ((not (and (consp object) (eq (car object) :object)))
     (error 'ai-cli-error
            :message (ai-cli-assign-message key object)))
    (t
     (let* ((found nil)
            (pairs
              (loop for pair in (cdr object)
                    collect (if (string= (car pair) key)
                                (progn (setf found t) (cons key value))
                                pair))))
       (unless found
         (setf pairs (append pairs (list (cons key value)))))
       (cons :object pairs)))))

(defun ai-cli-auth-path (directory)
  (merge-pathnames
   "auth.json"
   (uiop:ensure-directory-pathname directory)))

(defun ai-cli-save-auth (path object)
  (cadr-core:atomic-write-string
   path (ai-cli-stringify-json object) :mode #o600)
  path)

(defun ai-cli-provider-login (provider-id)
  (cadr-ai::built-in-oauth-login-function
   (cadr-ai:find-provider-definition
    (intern (string-upcase provider-id) :keyword))
   (cadr-ai::ambient-provider-environment)
   cadr-ai::+default-radius-gateway+))

(defun ai-cli-login (provider-id input output login-function)
  (let ((entry (find provider-id (ai-cli-oauth-providers)
                     :key #'car :test #'string=)))
    (unless entry
      (error 'ai-cli-error
             :message (format nil "Unknown provider: ~A" provider-id)))
    (let* ((interaction
             (cadr-ai:make-runtime-auth-interaction
              :prompt-function
              (lambda (prompt)
                (ai-cli-answer-prompt input output prompt))
              :notify-function
              (lambda (event) (ai-cli-notify output event))
              :abort-p (constantly nil)))
           (login (or login-function
                      (ai-cli-provider-login provider-id)))
           (credential
             (let ((cadr-ai::*oauth-login-device-id*
                     (ai-cli-random-uuid))
                   (cadr-ai::*oauth-login-agent-name* nil))
               (funcall login interaction))))
      (ai-cli-credential-object credential))))

(defun ai-cli-select-provider (input output)
  (let* ((providers (ai-cli-oauth-providers))
         (count (length providers)))
    (loop for (id . name) in providers
          for index from 1
          do (format output "  ~D. ~A~%" index name))
    (let ((choice
            (ai-cli-parse-int
             (ai-cli-read-answer
              input output
              (format nil "Enter number (1-~D): " count)))))
      (when (and choice (<= 1 choice count))
        (car (nth (1- choice) providers))))))

(defun ai-cli-main (arguments &key input output directory login-function)
  (let ((command (first arguments)))
    (cond
      ((or (null command)
           (string= command "help")
           (string= command "--help")
           (string= command "-h"))
       (write-line (ai-cli-usage-text) output)
       (finish-output output)
       0)
      ((string= command "list")
       (dolist (line (ai-cli-provider-lines))
         (write-line line output))
       (finish-output output)
       0)
      ((string= command "login")
       (let ((provider-id (second arguments)))
         (when (or (null provider-id) (string= provider-id ""))
           (setf provider-id
                 (ai-cli-select-provider input output)))
         (unless (find provider-id (ai-cli-oauth-providers)
                       :key #'car :test #'string=)
           (error 'ai-cli-error
                  :message
                  (format nil "Unknown provider: ~A"
                          (or provider-id ""))))
         (let* ((path (ai-cli-auth-path directory))
                (credential
                  (ai-cli-login
                   provider-id input output login-function))
                (auth (ai-cli-load-auth path)))
           (ai-cli-save-auth
            path (ai-cli-object-put auth provider-id credential))
           (format output "~%Credentials saved to auth.json~%")
           (finish-output output)
           0)))
      (t
       (error 'ai-cli-error
              :message
              (format nil "Unknown command: ~A" command))))))

(defun run-ai-cli
    (arguments
     &key
       (input *standard-input*)
       (output *standard-output*)
       (error *error-output*)
       (directory (uiop:getcwd))
       login-function)
  (handler-case
      (ai-cli-main arguments
                   :input input
                   :output output
                   :directory directory
                   :login-function login-function)
    (error (condition)
      (format error "Error: ~A~%"
              (ai-cli-condition-message condition))
      (finish-output error)
      1)))

(defun ai-cli-binary-p ()
  (let* ((argv (ignore-errors (first sb-ext:*posix-argv*)))
         (name (and (stringp argv) (file-namestring argv))))
    (and name
         (or (string= name "cadr-ai")
             (string-equal name "cadr-ai.exe")))))

(defun maybe-run-ai-command
    (arguments
     &key
       (directory (uiop:getcwd))
       (input *standard-input*)
       (output *standard-output*)
       (error *error-output*)
       login-function)
  (cond
    ((ai-cli-binary-p)
     (values t
             (run-ai-cli arguments
                         :input input
                         :output output
                         :error error
                         :directory directory
                         :login-function login-function)))
    ((and arguments (string= (first arguments) "ai"))
     (values t
             (run-ai-cli (rest arguments)
                         :input input
                         :output output
                         :error error
                         :directory directory
                         :login-function login-function)))
    (t (values nil nil))))
