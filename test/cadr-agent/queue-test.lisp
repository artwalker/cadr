(in-package #:cadr-agent/tests)
(in-suite cadr-agent-suite)

(defun user-text (message)
  (let ((content (cadr-ai:user-message-content message)))
    (if (stringp content)
        content
        (cadr-ai:text-content-text (first content)))))

(test steering-queues-drain-fifo-at-turn-boundaries
  (dolist (mode '(:one-at-a-time :all))
    (let ((*responses*
            (if (eq mode :all)
                (list
                 (assistant (list (make-text-content :text "first")))
                 (assistant (list (make-text-content :text "batched"))))
                (list
                 (assistant (list (make-text-content :text "first")))
                 (assistant (list (make-text-content :text "second")))
                 (assistant (list (make-text-content :text "third"))))))
          (*contexts* nil)
          (queue-lengths nil)
          (queued-p nil)
          (agent nil))
      (declare (special *responses* *contexts*))
      (setf
       agent
       (make-agent
        :provider :mock
        :model (mock-model)
        :stream-function
        (faux-stream '*responses* '*contexts*)
        :on-event
        (lambda (event)
          (when
              (eq :queue-update
                  (agent-event-type event))
            (push
             (length
              (cadr-agent::agent-event-steering event))
             queue-lengths))
          (when
              (and
               (eq :message-start
                   (agent-event-type event))
               (typep
                (agent-event-message event)
                'cadr-ai:assistant-message)
               (not queued-p))
            (setf queued-p t)
            (cadr-agent::agent-steer agent "one")
            (cadr-agent::agent-steer agent "two")))))
      (setf
       (cadr-agent::agent-steering-mode agent)
       mode)
      (agent-prompt agent "start")
      (is
       (equal
        '("start" "one" "two")
        (loop for message in (agent-messages agent)
              when (typep message 'cadr-ai:user-message)
                collect (user-text message))))
      (is
       (equal
        (if (eq mode :all)
            '(1 2 0)
            '(1 2 1 0))
        (nreverse queue-lengths)))
      (is (null *responses*)))))

(test follow-up-queues-drain-only-when-the-agent-would-stop
  (let ((*responses*
          (list
           (assistant (list (make-text-content :text "first")))
           (assistant (list (make-text-content :text "second")))
           (assistant (list (make-text-content :text "third")))))
        (*contexts* nil)
        (queue-lengths nil)
        (queued-p nil)
        (agent nil))
    (declare (special *responses* *contexts*))
    (setf
     agent
     (make-agent
      :provider :mock
      :model (mock-model)
      :stream-function
      (faux-stream '*responses* '*contexts*)
      :on-event
      (lambda (event)
        (when
            (eq :queue-update
                (agent-event-type event))
          (push
           (length
            (cadr-agent::agent-event-follow-up event))
           queue-lengths))
        (when
            (and
             (eq :message-start
                 (agent-event-type event))
             (typep
              (agent-event-message event)
              'cadr-ai:assistant-message)
             (not queued-p))
          (setf queued-p t)
          (cadr-agent::agent-follow-up agent "one")
          (cadr-agent::agent-follow-up agent "two")))))
    (agent-prompt agent "start")
    (is
     (equal
      '("start" "one" "two")
      (loop for message in (agent-messages agent)
            when (typep message 'cadr-ai:user-message)
              collect (user-text message))))
    (is (equal '(1 2 1 0)
               (nreverse queue-lengths)))
    (is (null *responses*))))

(test abort-clears-live-queues-preserves-next-turn-and-wait-settles
  (let* ((started
           (sb-thread:make-semaphore :count 0))
         (release
           (sb-thread:make-semaphore :count 0))
         (contexts nil)
         (calls 0)
         (agent nil)
         (thread nil))
    (labels
        ((stream
             (provider model context on-event
              &key max-tokens temperature abort-p)
           (declare
            (ignore
             provider model max-tokens temperature))
           (push context contexts)
           (incf calls)
           (when (= calls 1)
             (sb-thread:signal-semaphore started)
             (sb-thread:wait-on-semaphore release))
           (let ((message
                   (assistant
                    (list
                     (make-text-content
                      :text
                      (if
                          (and abort-p
                               (funcall abort-p))
                          "aborted"
                          "done")))
                    (if
                        (and abort-p
                             (funcall abort-p))
                        :aborted
                        :stop))))
             (funcall
              on-event
              (make-stream-event
               :type :start
               :message message))
             message)))
      (setf
       agent
       (make-agent
        :provider :mock
        :model (mock-model)
        :stream-function #'stream)
       thread
       (sb-thread:make-thread
        (lambda ()
          (agent-prompt agent "first"))
        :name "cadr-queue-abort-test"))
      (sb-thread:wait-on-semaphore started)
      (cadr-agent::agent-steer agent "discard-steer")
      (cadr-agent::agent-follow-up agent "discard-follow-up")
      (cadr-agent::agent-next-turn agent "keep-next")
      (multiple-value-bind
            (steering follow-up)
          (cadr-agent::agent-abort agent)
        (is (= 1 (length steering)))
        (is (= 1 (length follow-up))))
      (sb-thread:signal-semaphore release)
      (cadr-agent::agent-wait-for-idle agent)
      (sb-thread:join-thread thread)
      (agent-prompt agent "second")
      (is
       (equal
        '("first" "keep-next" "second")
        (loop for message in (agent-messages agent)
              when (typep message 'cadr-ai:user-message)
                collect (user-text message))))
      (is (= 2 calls)))))

(test continue-validates-state-and-drains-queued-work
  (let ((*responses*
          (list
           (assistant (list (make-text-content :text "first")))
           (assistant (list (make-text-content :text "continued")))))
        (*contexts* nil))
    (declare (special *responses* *contexts*))
    (let ((agent
            (make-agent
             :provider :mock
             :model (mock-model)
             :stream-function
             (faux-stream '*responses* '*contexts*))))
      (signals error
        (cadr-agent::agent-continue agent))
      (agent-prompt agent "start")
      (signals error
        (cadr-agent::agent-continue agent))
      (cadr-agent::agent-steer agent "queued")
      (cadr-agent::agent-continue agent)
      (is
       (equal
        '("start" "queued")
        (loop for message in (agent-messages agent)
              when (typep message 'cadr-ai:user-message)
                collect (user-text message))))
      (is (null *responses*)))))

(test agent-queue-messages-owns-three-ecases
  (is (fboundp 'cadr-agent::agent-queue-messages))
  (is (fboundp 'cadr-agent::set-agent-queue-messages)))
