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
