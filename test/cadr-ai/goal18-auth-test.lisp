(in-package #:cadr-ai/tests)
(in-suite cadr-ai-suite)

;;; Goal 18 Part A: every device-code login flow must observe cancellation
;;; through the shared poll-device-authorization cancelled-p mechanism.
;;; These tests were red before the fix: the poll loop ran to the marker
;;; error without ever raising authentication-cancelled.

(defun goal18-device-authorization-object (base-url)
  (cadr-ai::json-object
   "device_code" "device" "user_code" "ABCD"
   "verification_uri" base-url
   "verification_uri_complete"
   (format nil "~A?code=ABCD" base-url)
   "interval" 5 "expires_in" 900))

(defmacro goal18-with-device-cancel-harness
    ((aborted sleeps) &body body)
  ;; The stubbed device endpoint answers once, the token endpoint pends
  ;; forever, and the sleep stub flips the abort flag exactly like an ESC
  ;; landing mid-poll.  If the loop never observes it, the marker error
  ;; proves the broken link deterministically instead of hanging.
  `(let ((,aborted nil)
         (,sleeps 0))
     (let ((cadr-ai::*oauth-flow-request-function*
             (lambda (url &rest options)
               (declare (ignore options))
               (if (search "device" url)
                   (values
                    (goal18-device-authorization-object
                     "https://auth.invalid/activate")
                    200)
                   (values
                    (cadr-ai::json-object
                     "error" "authorization_pending")
                    400))))
           (cadr-ai::*oauth-flow-sleep-function*
             (lambda (seconds)
               (declare (ignore seconds))
               (setf ,aborted t)
               (incf ,sleeps)
               (when (> ,sleeps 10)
                 (error
                  "device login poll never observed the cancellation")))))
       ,@body)))

(defmacro goal18-assert-device-login-cancels (login-form)
  `(signals cadr-ai:authentication-cancelled
     ,login-form))

(test goal18-xai-device-login-cancel-terminates-poll
  (goal18-with-device-cancel-harness (aborted sleeps)
    (let ((interaction
            (cadr-ai:make-runtime-auth-interaction
             :abort-p (lambda () aborted))))
      (goal18-assert-device-login-cancels
       (cadr-ai::login-xai-oauth interaction)))))

(test goal18-kimi-device-login-cancel-terminates-poll
  (goal18-with-device-cancel-harness (aborted sleeps)
    (let ((interaction
            (cadr-ai:make-runtime-auth-interaction
             :abort-p (lambda () aborted))))
      (goal18-assert-device-login-cancels
       (cadr-ai::login-kimi-oauth interaction)))))

(test goal18-github-copilot-device-login-cancel-terminates-poll
  (goal18-with-device-cancel-harness (aborted sleeps)
    (let ((interaction
            (cadr-ai:make-runtime-auth-interaction
             :prompt-function
             (lambda (prompt)
               (declare (ignore prompt))
               "")
             :abort-p (lambda () aborted))))
      (goal18-assert-device-login-cancels
       (cadr-ai::login-github-copilot-oauth interaction)))))

(test goal18-radius-device-login-cancel-terminates-poll
  (goal18-with-device-cancel-harness (aborted sleeps)
    (let ((interaction
            (cadr-ai:make-runtime-auth-interaction
             :abort-p (lambda () aborted))))
      (goal18-assert-device-login-cancels
       (cadr-ai::login-radius-device-oauth
        "https://radius.invalid" interaction)))))

(test goal18-radius-browser-login-cancel-terminates-callback-wait
  ;; The loopback wait must observe the interaction abort and raise
  ;; authentication-cancelled instead of blocking on accept forever.
  (let ((cadr-ai::*oauth-flow-request-function*
          (lambda (url &rest options)
            (declare (ignore url options))
            (values
             (cadr-ai::json-object
              "authorizationEndpoint" "https://radius.invalid/authorize")
             200))))
    (signals cadr-ai:authentication-cancelled
      (cadr-ai::login-radius-browser-oauth
       "https://radius.invalid"
       (cadr-ai:make-runtime-auth-interaction
        :abort-p (constantly t))))))

;;; Goal 18 A5: the structured Bedrock/Vertex API key login flows mirror
;;; the baseline ApiKeyAuth.login contracts (method select, per-method
;;; prompts, info notice with its link, shaped credential).

(defun goal18-scripted-interaction (answers notify-box)
  "An interaction answering prompts from ANSWERS in order and recording
notifies into NOTIFY-BOX, a one-element list whose car holds the events."
  (cadr-ai:make-runtime-auth-interaction
   :prompt-function
   (lambda (prompt)
     (unless answers
       (error "unexpected prompt: ~A" (getf prompt :message)))
     (let ((answer (pop answers)))
       (if (eq :cancel answer)
           (error 'cadr-ai:authentication-cancelled
                  :message "Login cancelled")
           answer)))
   :notify-function
   (lambda (event) (push (copy-list event) (car notify-box)))
   :abort-p (constantly nil)))

(test goal18-bedrock-login-bearer-token-path
  (let ((notifies (list nil)))
    (let ((credential
            (cadr-ai::login-bedrock-api-key
             (goal18-scripted-interaction
              (list "bearer-token" "secret-token") notifies))))
      (is (typep credential 'cadr-ai:api-key-credential))
      (is (string= "secret-token"
                   (cadr-ai:api-key-credential-key credential)))
      (is (null (cadr-ai:api-key-credential-environment credential)))
      (is (null (first notifies))
          "the bearer-token path sends no info notice"))))

(test goal18-bedrock-login-aws-profile-path-notifies-with-link
  (let ((notifies (list nil)))
    (let ((credential
            (cadr-ai::login-bedrock-api-key
             (goal18-scripted-interaction
              (list "aws-profile" "prod-admin") notifies))))
      (is (equal '(("AWS_PROFILE" . "prod-admin"))
                 (cadr-ai:api-key-credential-environment credential)))
      (is (= 1 (length (first notifies))))
      (let ((event (first (first notifies))))
        (is (eq :info (getf event :type)))
        (is (string=
             "Amazon Bedrock supports AWS profiles, IAM credentials, and role-based credentials."
             (getf event :message)))
        (is (equal
             '((:label "AWS credential provider chain"
                :url "https://docs.aws.amazon.com/sdkref/latest/guide/standardized-credentials.html"))
             (getf event :links)))))))

(test goal18-bedrock-login-credential-chain-path
  (let ((notifies (list nil)))
    (let ((credential
            (cadr-ai::login-bedrock-api-key
             (goal18-scripted-interaction
              (list "credential-chain" "") notifies))))
      (is (typep credential 'cadr-ai:api-key-credential))
      (is (string= "" (cadr-ai:api-key-credential-key credential)))
      (is (= 1 (length (first notifies)))))))

(test goal18-bedrock-login-cancel-is-typed
  (signals cadr-ai:authentication-cancelled
    (cadr-ai::login-bedrock-api-key
     (goal18-scripted-interaction (list :cancel) nil))))

(test goal18-vertex-login-api-key-path
  (let ((credential
          (cadr-ai::login-vertex-api-key
           (goal18-scripted-interaction
            (list "api-key" "gcp-key") nil))))
    (is (string= "gcp-key"
                 (cadr-ai:api-key-credential-key credential)))))

(test goal18-vertex-login-adc-path-collects-project-and-location
  (let ((notifies (list nil)))
    (let ((credential
            (cadr-ai::login-vertex-api-key
             (goal18-scripted-interaction
              (list "adc" "my-project" "us-central1") notifies))))
      (is (equal '(("GOOGLE_CLOUD_PROJECT" . "my-project")
                   ("GOOGLE_CLOUD_LOCATION" . "us-central1"))
                 (cadr-ai:api-key-credential-environment credential)))
      (let ((event (first (first notifies))))
        (is (search "gcloud auth application-default login"
                    (getf event :message)))
        (is (equal
             '((:label "Application Default Credentials"
                :url "https://cloud.google.com/docs/authentication/provide-credentials-adc"))
             (getf event :links)))))))

(test goal18-vertex-login-service-account-path-includes-credentials-file
  (let ((credential
          (cadr-ai::login-vertex-api-key
           (goal18-scripted-interaction
            (list "service-account" "proj" "eu" "/keys/sa.json")
            (list nil)))))
    (is (equal '(("GOOGLE_CLOUD_PROJECT" . "proj")
                 ("GOOGLE_CLOUD_LOCATION" . "eu")
                 ("GOOGLE_APPLICATION_CREDENTIALS" . "/keys/sa.json"))
               (cadr-ai:api-key-credential-environment credential)))))

(test goal18-only-structured-providers-expose-api-key-login-functions
  (dolist (spec '((:amazon-bedrock t) (:google-vertex t)
                  (:deepseek nil) (:openrouter nil) (:xai nil)))
    (destructuring-bind (provider-id expected-p) spec
      (let* ((definition
               (cadr-ai:find-provider-definition provider-id))
             (runtime-provider
               (cadr-ai::make-built-in-runtime-provider definition)))
        (is (eq expected-p
                (not
                 (null
                  (cadr-ai:runtime-provider-api-key-login-function
                   runtime-provider))))
            "~A structured login exposure drifted" provider-id)
        (is (eq expected-p
                (cadr-ai:provider-definition-structured-api-key-login-p
                 definition))
            "~A structured-login predicate drifted" provider-id)))))
