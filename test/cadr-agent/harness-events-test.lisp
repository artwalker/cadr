(in-package #:cadr-agent/tests)

(in-suite cadr-agent-suite)

;;; Mirrors packages/agent/test/harness/events.test.ts (v0.84.2).

(test harness-event-bus-delivers-to-direct-listeners-and-watchers
  (let ((bus (cadr-agent:make-harness-event-bus))
        (direct nil)
        (watched nil))
    (let ((off
            (cadr-agent:harness-event-bus-on
             bus :run-start (lambda (event) (push event direct)))))
      (multiple-value-bind (snapshot start unsubscribe)
          (cadr-agent:harness-event-bus-watch bus (lambda () nil))
        (declare (ignore snapshot))
        (funcall start (lambda (event) (push event watched)))
        (let ((run-start
                (cadr-agent:make-run-start-event "main" "run-1"))
              (run-end
                (cadr-agent:make-run-end-event
                 "main" "run-1" :completed "entry-1")))
          (cadr-agent:harness-event-bus-emit bus run-start)
          (cadr-agent:harness-event-bus-emit bus run-end)
          (funcall off)
          (cadr-agent:harness-event-bus-emit bus run-start)
          (is (equal (list run-start) direct))
          (is (equal (list run-start run-end run-start)
                     (reverse watched)))
          (funcall unsubscribe))))))

(test harness-event-bus-watch-snapshot-flush-and-unsubscribe
  (let ((bus (cadr-agent:make-harness-event-bus))
        (received nil))
    (let ((run-start (cadr-agent:make-run-start-event "main" "run-1"))
          (run-end
            (cadr-agent:make-run-end-event
             "main" "run-1" :completed "entry-1"))
          (expected-snapshot (list :leaf-id nil)))
      (multiple-value-bind (snapshot start unsubscribe)
          (cadr-agent:harness-event-bus-watch
           bus
           (lambda ()
             ;; An emission during snapshot capture is buffered, not lost.
             (cadr-agent:harness-event-bus-emit bus run-start)
             expected-snapshot))
        (is (eq expected-snapshot snapshot))
        (is (null received))
        (funcall start (lambda (event) (push event received)))
        (is (equal (list run-start) (reverse received)))
        (cadr-agent:harness-event-bus-emit bus run-end)
        (is (equal (list run-start run-end) (reverse received)))
        (funcall unsubscribe)
        (cadr-agent:harness-event-bus-emit bus run-start)
        (is (equal (list run-start run-end) (reverse received)))))))
