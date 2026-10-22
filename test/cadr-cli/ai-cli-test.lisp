(in-package #:cadr-cli/tests)

(in-suite cadr-cli-suite)

;;; Locked to v1.4.0 packages/ai/src/cli.ts and the OAuth rows of
;;; packages/ai/src/providers/all.ts.  The command name is cadr's.
;;; openai-codex's provider name at that tag is "OpenAI Codex (legacy)".

(defparameter +ai-cli-help-text+
  "Usage: cadr ai <command> [provider]

Commands:
  login [provider]  Login to an OAuth provider
  list              List available providers

Providers:
anthropic            Anthropic
github-copilot       GitHub Copilot
kimi-coding          Kimi For Coding
meta                 Meta
openai               OpenAI
openai-codex         OpenAI Codex (legacy)
openrouter           OpenRouter
radius               Radius
xai                  xAI")

(defparameter +ai-cli-list-text+
  "anthropic            Anthropic
github-copilot       GitHub Copilot
kimi-coding          Kimi For Coding
meta                 Meta
openai               OpenAI
openai-codex         OpenAI Codex (legacy)
openrouter           OpenRouter
radius               Radius
xai                  xAI")

(defparameter +ai-cli-saved-credential+
  "{
  \"anthropic\": {
    \"type\": \"oauth\",
    \"access\": \"access-token\",
    \"refresh\": \"refresh-token\",
    \"expires\": 1700000000000,
    \"clientId\": \"issued-client\",
    \"scopes\": [
      \"openid\",
      \"profile\"
    ]
  }
}")

(defparameter +ai-cli-merged-credential+
  "{
  \"github-copilot\": {
    \"type\": \"oauth\",
    \"access\": \"old-access\",
    \"refresh\": \"old-refresh\",
    \"expires\": 1
  },
  \"anthropic\": {
    \"type\": \"oauth\",
    \"access\": \"access-token\",
    \"refresh\": \"refresh-token\",
    \"expires\": 1700000000000,
    \"clientId\": \"issued-client\",
    \"scopes\": [
      \"openid\",
      \"profile\"
    ]
  }
}")

(defun ai-cli-temp-dir ()
  (let ((dir (merge-pathnames
              (format nil "cadr-ai-cli-~A-~A/"
                      (get-universal-time)
                      (random 1000000))
              (uiop:temporary-directory))))
    (ensure-directories-exist dir)
    dir))

(defun ai-cli-run (arguments &key input directory login-function)
  (let ((output (make-string-output-stream))
        (error (make-string-output-stream))
        (in (make-string-input-stream (or input ""))))
    (let ((status
            (cadr-cli::run-ai-cli
             arguments
             :input in
             :output output
             :error error
             :directory (or directory (uiop:getcwd))
             :login-function login-function)))
      (values status
              (get-output-stream-string output)
              (get-output-stream-string error)))))

(defun ai-cli-sample-credential ()
  (cadr-ai:make-oauth-credential
   :provider :anthropic
   :access "access-token"
   :refresh "refresh-token"
   :expires 1700000000000
   :metadata '(("clientId" . "issued-client")
               ("scopes" . #("openid" "profile")))))

(defun ai-cli-interactive-login (interaction)
  (cadr-ai:runtime-auth-interaction-notify
   interaction
   '(:type :auth-url
     :url "https://example.test/auth"
     :instructions "Paste it."))
  (cadr-ai:runtime-auth-interaction-notify
   interaction
   '(:type :device-code
     :user-code "ABCD-EFGH"
     :verification-uri "https://example.test/device"))
  (cadr-ai:runtime-auth-interaction-notify
   interaction '(:type :info :message "info line"))
  (cadr-ai:runtime-auth-interaction-notify
   interaction '(:type :progress :message "progress line"))
  (let ((picked
          (cadr-ai:runtime-auth-interaction-prompt
           interaction
           '(:type :select
             :message "Choose a method"
             :options ((:id "browser" :label "Browser login")
                       (:id "device" :label "Device code"))))))
    (is (string= "browser" picked)))
  (let ((pasted
          (cadr-ai:runtime-auth-interaction-prompt
           interaction
           '(:type :text
             :message "Paste the redirect"
             :placeholder "url"))))
    (is (string= "http://127.0.0.1/done" pasted)))
  (cadr-ai:runtime-auth-interaction-prompt
   interaction
   '(:type :secret :message "Extra secret"))
  (ai-cli-sample-credential))

(defun ai-cli-uuid-v4-p (value)
  (and (stringp value)
       (= (length value) 36)
       (char= (char value 14) #\4)
       (member (char value 19) '(#\8 #\9 #\a #\b))
       (loop for index from 0 below 36
             for character = (char value index)
             always (if (member index '(8 13 18 23))
                        (char= character #\-)
                        (digit-char-p character 16)))))

(test ai-cli-help-matches-the-library-cli
  (dolist (arguments '(nil ("help") ("--help") ("-h")))
    (multiple-value-bind (status output error)
        (ai-cli-run arguments)
      (is (= 0 status))
      (is (string= "" error))
      (is (string= (format nil "~A~%" +ai-cli-help-text+) output)))))

(test ai-cli-list-prints-only-oauth-providers
  (multiple-value-bind (status output error)
      (ai-cli-run '("list" "--help"))
    (is (= 0 status))
    (is (string= "" error))
    (is (string= (format nil "~A~%" +ai-cli-list-text+) output))
    (dolist (absent '("deepseek" "typesafe" "huggingface" "Commands:"))
      (is (null (search absent output))))))

(test ai-cli-unknown-command-and-provider-go-to-stderr
  (multiple-value-bind (status output error)
      (ai-cli-run '("frob"))
    (is (= 1 status))
    (is (string= "" output))
    (is (string= (format nil "Error: Unknown command: frob~%") error)))
  (multiple-value-bind (status output error)
      (ai-cli-run '("login" "nope"))
    (is (= 1 status))
    (is (string= "" output))
    (is (string= (format nil "Error: Unknown provider: nope~%") error)))
  (multiple-value-bind (status output error)
      (ai-cli-run '("login" "--help"))
    (is (= 1 status))
    (is (string= "" output))
    (is (string= (format nil "Error: Unknown provider: --help~%") error)))
  (multiple-value-bind (status output error)
      (ai-cli-run '("login" ""))
    (declare (ignore status output))
    (is (string= (format nil "Error: Unknown provider: ~%") error)))
  (multiple-value-bind (status error-text)
      (multiple-value-bind (status output error)
          (ai-cli-run '("login") :input (format nil "0~%"))
        (declare (ignore output))
        (values status error))
    (is (= 1 status))
    (is (string= (format nil "Error: Unknown provider: ~%") error-text)))
  (multiple-value-bind (status error-text)
      (multiple-value-bind (status output error)
          (ai-cli-run '("login") :input (format nil "99~%"))
        (declare (ignore output))
        (values status error))
    (is (= 1 status))
    (is (string= (format nil "Error: Unknown provider: ~%") error-text))))

(test ai-cli-login-prints-prompts-and-writes-auth-json
  (let ((dir (ai-cli-temp-dir)))
    (unwind-protect
         (multiple-value-bind (status output error)
             (ai-cli-run
              '("login" "anthropic")
              :directory dir
              :input (format nil "1~%http://127.0.0.1/done~%secret-value~%")
              :login-function #'ai-cli-interactive-login)
           (is (= 0 status))
           (is (string= "" error))
           (is (search (format nil "~%Open this URL in your browser:~%https://example.test/auth~%Paste it.~%")
                       output))
           (is (search (format nil "~%Open this URL in your browser:~%https://example.test/device~%Enter code: ABCD-EFGH~%")
                       output))
           (is (search (format nil "info line~%progress line~%") output))
           (is (search (format nil "~%Choose a method~%  1. Browser login~%  2. Device code~%Enter number (1-2): ")
                       output))
           (is (search "Paste the redirect (url): " output))
           (is (search "Extra secret: " output))
           (is (search (format nil "~%Credentials saved to auth.json~%") output))
           (is (string= +ai-cli-saved-credential+
                        (uiop:read-file-string
                         (merge-pathnames "auth.json" dir)
                         :external-format :utf-8)))
           (is (= #o600
                  (cadr-ai:auth-file-mode
                   (merge-pathnames "auth.json" dir)))))
      (uiop:delete-directory-tree dir :validate t))))

(test ai-cli-login-keeps-other-providers-and-drops-invalid-json
  (let ((dir (ai-cli-temp-dir))
        (login (lambda (interaction)
                 (declare (ignore interaction))
                 (ai-cli-sample-credential))))
    (unwind-protect
         (progn
           (with-open-file (out (merge-pathnames "auth.json" dir)
                                :direction :output
                                :if-exists :supersede
                                :external-format :utf-8)
             (write-string "{
  \"github-copilot\": {
    \"type\": \"oauth\",
    \"access\": \"old-access\",
    \"refresh\": \"old-refresh\",
    \"expires\": 1
  }
}" out))
           (multiple-value-bind (status output error)
               (ai-cli-run '("login" "anthropic")
                           :directory dir
                           :login-function login)
             (declare (ignore output))
             (is (= 0 status))
             (is (string= "" error))
             (is (string= +ai-cli-merged-credential+
                          (uiop:read-file-string
                           (merge-pathnames "auth.json" dir)
                           :external-format :utf-8))))
           (with-open-file (out (merge-pathnames "auth.json" dir)
                                :direction :output
                                :if-exists :supersede
                                :external-format :utf-8)
             (write-string "not json" out))
           (multiple-value-bind (status output error)
               (ai-cli-run '("login" "anthropic")
                           :directory dir
                           :login-function login)
             (declare (ignore output))
             (is (= 0 status))
             (is (string= "" error))
             (is (string= +ai-cli-saved-credential+
                          (uiop:read-file-string
                           (merge-pathnames "auth.json" dir)
                           :external-format :utf-8)))))
      (uiop:delete-directory-tree dir :validate t))))

(test ai-cli-login-without-a-provider-uses-the-numbered-names
  (let ((dir (ai-cli-temp-dir)))
    (unwind-protect
         (multiple-value-bind (status output error)
             (ai-cli-run
              '("login")
              :directory dir
              :input (format nil "1~%1~%http://127.0.0.1/done~%secret~%")
              :login-function #'ai-cli-interactive-login)
           (is (= 0 status))
           (is (string= "" error))
           (is (search (format nil "  1. Anthropic~%  2. GitHub Copilot~%")
                       output))
           (is (search "Enter number (1-9): " output))
           (is (string= +ai-cli-saved-credential+
                        (uiop:read-file-string
                         (merge-pathnames "auth.json" dir)
                         :external-format :utf-8))))
      (uiop:delete-directory-tree dir :validate t))))

(test ai-cli-login-rejects-an-invalid-selection
  (multiple-value-bind (status output error)
      (ai-cli-run
       '("login" "xai")
       :input (format nil "9~%")
       :login-function #'ai-cli-interactive-login)
    (declare (ignore output))
    (is (= 1 status))
    (is (string= (format nil "Error: Invalid selection~%") error))))

(test ai-cli-login-uses-a-fresh-uuid-and-no-stored-agent-name
  (let ((dir (ai-cli-temp-dir))
        (seen nil))
    (unwind-protect
         (let ((cadr-ai::*oauth-login-agent-name* "leftover")
               (login
                 (lambda (interaction)
                   (declare (ignore interaction))
                   (push cadr-ai::*oauth-login-device-id* seen)
                   (is (null cadr-ai::*oauth-login-agent-name*))
                   (ai-cli-sample-credential))))
           (is (= 0 (ai-cli-run '("login" "meta")
                                :directory dir
                                :login-function login)))
           (is (= 0 (ai-cli-run '("login" "meta")
                                :directory dir
                                :login-function login)))
           (is (= 2 (length seen)))
           (is (ai-cli-uuid-v4-p (first seen)))
           (is (ai-cli-uuid-v4-p (second seen)))
           (is (string/= (first seen) (second seen))))
      (uiop:delete-directory-tree dir :validate t))))

(test ai-cli-main-dispatches-the-ai-command
  (multiple-value-bind (handled status)
      (cadr-cli::maybe-run-ai-command '("list"))
    (is (null handled))
    (is (null status)))
  (let ((output (make-string-output-stream)))
    (multiple-value-bind (handled status)
        (cadr-cli::maybe-run-ai-command
         '("ai" "list") :output output)
      (is (eq handled t))
      (is (= 0 status))
      (is (string= (format nil "~A~%" +ai-cli-list-text+)
                   (get-output-stream-string output))))))
