(in-package #:cadr-cli)

(defparameter +credential-environment-names+
  '("ANTHROPIC_AUTH_TOKEN"
    "ANTHROPIC_OAUTH_TOKEN"
    "AWS_ACCESS_KEY_ID"
    "AWS_BEARER_TOKEN_BEDROCK"
    "AWS_SECRET_ACCESS_KEY"
    "AWS_SESSION_TOKEN"
    "GOOGLE_CLOUD_API_KEY"))

(defun crash-known-secrets
    (&optional (arguments (uiop:command-line-arguments)))
  (remove-duplicates
   (remove-if-not
    #'cadr-ai::non-empty-string-p
    (append
     (cadr-ai::command-line-api-key-secrets arguments)
     (stored-auth-secrets)
     (loop for definition in (cadr-ai:list-provider-definitions)
           for name =
             (cadr-ai:provider-definition-key-environment definition)
           when name collect (uiop:getenv name))
     (loop for name in +credential-environment-names+
           collect (uiop:getenv name))))
   :test #'string=))

(defun redact-crash-diagnostic (text secrets)
  (let ((redacted (cadr-ai:redact-secrets text secrets)))
    (dolist
        (rule
         '(("(?i)authorization[[:space:]]*[:=][^\r\n]*"
            . "Authorization: [REDACTED]")
           ("(?i)(bearer|basic)[[:space:]]+[A-Za-z0-9._~+/=-]+"
            . "Authorization [REDACTED]")
           ("(?i)[\"']?(access|refresh|api[-_]?key|token|client[-_]?secret)[\"']?[[:space:]]*[:=][[:space:]]*[\"']?[^\"'[:space:](),]+"
            . "[REDACTED-CREDENTIAL]")))
      (setf redacted
            (cl-ppcre:regex-replace-all
             (car rule) redacted (cdr rule))))
    redacted))

(defun call-with-fatal-condition-boundary
    (function &key
                (program-name "cadr")
                (crash-directory
                  (cadr-ai::default-crash-directory))
                secrets
                (exit-function #'uiop:quit))
  (let ((cadr-ai::*fatal-condition-side-effect*
          (lambda (report)
            (record-crash
             :kind "fatal_error"
             :message
             (cadr-ai::fatal-condition-report-user-message
              report)
             :cwd (uiop:getcwd)))))
    (cadr-ai::call-with-fatal-condition-boundary
     function
     :program-name program-name
     :crash-directory crash-directory
     :secrets
     (remove-duplicates
      (append secrets (crash-known-secrets))
      :test #'string=)
     :redactor #'redact-crash-diagnostic
     :exit-function exit-function)))
