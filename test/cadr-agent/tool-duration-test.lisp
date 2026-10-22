(in-package #:cadr-agent/tests)

(in-suite cadr-agent-suite)

(defun duration-tool-call ()
  (cadr-ai:make-tool-call
   :id "call-1"
   :name "bash"
   :arguments (make-hash-table :test #'equal)))

(defun duration-prepared (executor)
  (cadr-agent::make-prepared-tool-call
   :call (duration-tool-call)
   :tool
   (cadr-ai:make-tool
    :name "bash"
    :executor executor)
   :arguments (make-hash-table :test #'equal)))

(test executed-tool-records-duration-ms
  ;; pi@4a080252f agent-loop.ts executePreparedToolCall. The clock
  ;; covers execute only. A thrown execute still carries that time.
  (let* ((outcome
           (cadr-agent::execute-prepared-tool
            (duration-prepared
             (lambda (id arguments)
               (declare (ignore id arguments))
               (values
                (list (cadr-ai:make-text-content :text "ok"))
                nil
                nil)))))
         (result (cadr-agent::tool-outcome-result outcome))
         (duration
           (cadr-ai:tool-result-message-duration-ms result)))
    (is (integerp duration))
    (is (>= duration 0))
    (is (null (cadr-ai:tool-result-message-is-error result))))
  (let ((caught nil))
    (handler-case
        (cadr-agent::execute-prepared-tool
         (duration-prepared
          (lambda (id arguments)
            (declare (ignore id arguments))
            (error "boom"))))
      (cadr-agent:tool-execution-error (condition)
        (setf caught condition)))
    (is (typep caught 'cadr-agent:tool-execution-error))
    (is (integerp
         (cadr-agent::tool-execution-error-duration-ms caught)))
    (is (>=
         (cadr-agent::tool-execution-error-duration-ms caught)
         0)))
  (let* ((message
           (cadr-ai:make-tool-result-message
            :tool-call-id "call-1"
            :tool-name "bash"
            :content
            (list (cadr-ai:make-text-content :text "ok"))
            :duration-ms 1300
            :timestamp 10))
         (restored
           (cadr-agent::message-from-json
            (cadr-agent::message-to-json message))))
    (is (= 1300
           (cadr-ai:tool-result-message-duration-ms restored)))
    (is (null
         (cadr-ai:tool-result-message-duration-ms
          (cadr-agent::message-from-json
           (cadr-agent::message-to-json
            (cadr-ai:make-tool-result-message
             :tool-call-id "call-2"
             :tool-name "read"
             :content nil
             :timestamp 10))))))))
