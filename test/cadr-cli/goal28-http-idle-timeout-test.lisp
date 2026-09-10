(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(test goal28-http-idle-timeout-reaches-existing-request
  (let ((manager (cadr-cli::make-memory-settings-manager)))
    (is (= 300000
           (cadr-cli::settings-http-idle-timeout-ms manager))))
  (let ((settings (cadr-cli::make-memory-sdk-settings-manager)))
    (is (= 300000
           (cadr-cli:sdk-settings-http-idle-timeout-ms settings))))
  (let* ((seen nil)
         (manager
           (cadr-cli::make-memory-sdk-settings-manager
            (args "httpIdleTimeoutMs" 5000)))
         (stream
           (cadr-cli::stream-function-with-http-idle-timeout
            (lambda (provider model context on-event &rest options)
              (declare (ignore provider model context on-event))
              (setf seen (getf options :read-timeout)))
            (lambda ()
              (cadr-cli:sdk-settings-http-idle-timeout-ms
               manager)))))
    (is (= 5000
           (cadr-cli:sdk-settings-http-idle-timeout-ms manager)))
    (funcall stream nil nil nil nil)
    (is (= 5 seen)))
  (let ((captured nil)
        (provider
          (cadr-ai:make-openai-provider :api-key "idle-test"))
        (model
          (cadr-ai:make-model
           :id "gpt-test"
           :provider :openai
           :api :openai-responses
           :base-url "https://api.openai.com"
           :max-tokens 4096))
        (context
          (cadr-ai:make-context
           :messages
           (list
            (cadr-ai:make-user-message
             :content "hi"
             :timestamp 1))))
        (manager
          (cadr-cli::make-memory-sdk-settings-manager
           (args "httpIdleTimeoutMs" 5000))))
    (let ((cadr-ai:*http-request-function*
            (lambda (url &rest arguments)
              (declare (ignore url))
              (setf captured arguments)
              (values "{}" 200 nil))))
      (funcall
       (cadr-cli::stream-function-with-http-idle-timeout
        (lambda (provider model context on-event &rest options)
          (declare (ignore on-event))
          (apply #'cadr-ai:complete-chat
                 provider model context options))
        (lambda ()
          (cadr-cli:sdk-settings-http-idle-timeout-ms manager)))
       provider model context nil))
    (is (= 5 (getf captured :read-timeout)))))
