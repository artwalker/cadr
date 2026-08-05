(in-package #:cadr-agent/tests)
(in-suite cadr-agent-suite)

(test goal11-agent-message-append-maintains-o1-tail-invariant
  (let* ((initial
           (list
            (cadr-ai:make-user-message :content "first")))
         (agent
           (make-agent
            :provider :mock
            :model (mock-model)
            :messages initial))
         (first-tail
           (cadr-agent::agent-messages-tail agent)))
    (is (eq (agent-messages agent)
            (cadr-agent::agent-messages-tail-head agent)))
    (is (eq first-tail (last (agent-messages agent))))
    (cadr-agent::agent-append-message
     agent
     (cadr-ai:make-user-message :content "second"))
    (is (eq (cdr first-tail)
            (cadr-agent::agent-messages-tail agent)))
    (is (null
         (cdr (cadr-agent::agent-messages-tail agent))))
    (is (equal '("first" "second")
               (mapcar
                #'cadr-ai:user-message-content
                (agent-messages agent))))
    ;; Public accessors allow callers to replace the list. The next append
    ;; repairs the private tail once and then resumes constant-time appends.
    (let ((replacement
            (list
             (cadr-ai:make-user-message :content "replacement"))))
      (setf (agent-messages agent) replacement)
      (cadr-agent::agent-append-message
       agent
       (cadr-ai:make-user-message :content "after-replacement"))
      (is (eq replacement
              (cadr-agent::agent-messages-tail-head agent)))
      (is (equal '("replacement" "after-replacement")
                 (mapcar
                  #'cadr-ai:user-message-content
                  (agent-messages agent)))))))

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

(test goal17-agent-end-messages-exclude-preexisting-context
  (let* ((old-user
           (cadr-ai:make-user-message :content "old request"))
         (old-assistant
           (assistant
            (list (make-text-content :text "old answer"))))
         (*responses*
           (list
            (assistant
             (list (make-text-content :text "new answer")))))
         (*contexts* nil)
         (events nil))
    (declare (special *responses* *contexts*))
    (let ((agent
            (make-agent
             :provider :mock
             :model (mock-model)
             :messages (list old-user old-assistant)
             :stream-function
             (faux-stream '*responses* '*contexts*)
             :on-event (lambda (event) (push event events)))))
      (agent-prompt agent "new request")
      (let* ((event
               (find :agent-end events
                     :key #'agent-event-type))
             (messages
               (cadr-agent:agent-event-messages event)))
        (is (= 2 (length messages)))
        (is
         (string=
          "new request"
          (cadr-ai:user-message-content (first messages))))
        (is
         (string=
          "new answer"
          (cadr-ai:text-content-text
           (first
            (cadr-ai:assistant-message-content
             (second messages))))))
        (is-false (member old-user messages :test #'eq))
        (is-false (member old-assistant messages :test #'eq))))))

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
