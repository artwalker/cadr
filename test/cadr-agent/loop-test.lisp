(in-package #:cadr-agent/tests)
(in-suite cadr-agent-suite)

(test simple-turn-emits-reference-lifecycle-order
  (let ((*responses*
          (list
           (assistant
            (list (make-text-content :text "Hello")))))
        (*contexts* nil)
        (events nil))
    (declare (special *responses* *contexts*))
    (let ((agent
            (make-agent
             :provider :mock
             :model (mock-model)
             :stream-function
             (faux-stream '*responses* '*contexts*)
             :on-event (lambda (event) (push event events)))))
      (agent-prompt agent "Hi")
      (setf events (nreverse events))
      (is (equal
           '(:agent-start :turn-start
             :message-start :message-end
             :message-start :message-update :message-end
             :turn-end :agent-end :agent-settled)
           (event-types events)))
      (is (= 2 (length (agent-messages agent))))
      (is (string= "Hello"
                   (text-content-text
                    (first
                     (assistant-message-content
                      (second (agent-messages agent))))))))))

(test error-and-abort-stop-the-run-cleanly
  (dolist (reason '(:error :aborted))
    (let ((*responses* (list (assistant nil reason)))
          (*contexts* nil)
          (events nil))
      (declare (special *responses* *contexts*))
      (let ((agent
              (make-agent
               :provider :mock
               :model (mock-model)
               :stream-function
               (faux-stream '*responses* '*contexts*)
               :on-event (lambda (event) (push event events)))))
        (agent-prompt agent "Hi")
        (is (= 2 (length (agent-messages agent))))
        (is (= 1 (count :turn-end (event-types events))))
        (is (= 1 (count :agent-end (event-types events))))))))
