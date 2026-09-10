(in-package #:cadr-ai/tests)
(in-suite cadr-ai-suite)

(test goal28-http-idle-stream-reaches-existing-sse
  (multiple-value-bind (provider model)
      (provider-case :anthropic)
    (flet ((captured-read-timeout (&rest stream-chat-args)
             (let ((captured nil))
               (let ((*http-request-function*
                       (lambda (url &rest arguments)
                         (declare (ignore url))
                         (setf captured (getf arguments :read-timeout))
                         (values
                          (open
                           (fixture-path
                            "test/fixtures/goal20-paired-paths/anthropic-messages.sse")
                           :direction :input
                           :element-type '(unsigned-byte 8))
                          200
                          '(("content-type" . "text/event-stream"))))))
                 (apply #'stream-chat provider model (sample-context)
                        (lambda (event) (declare (ignore event)))
                        stream-chat-args)
                 captured))))
      (is (eql 5 (captured-read-timeout :read-timeout 5)))
      (is (null (captured-read-timeout))))))
