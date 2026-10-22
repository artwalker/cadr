(in-package #:cadr-agent/tests)
(in-suite cadr-agent-suite)

(test late-cache-refresh-is-not-sent
  (let ((now 0)
        (calls 0))
    (let ((warmer
            (cadr-agent:make-cache-warmer
             :now-function (lambda () now)
             :warm-function
             (lambda (run)
               (declare (ignore run))
               (incf calls)))))
      (cadr-agent:cache-warmer-start warmer :ttl-ms 300000)
      (setf now 285001)
      (cadr-agent:refresh-cache-warmer
       warmer (cadr-agent::cache-warmer-run warmer))
      (is (zerop calls))
      (is (equal '(:state :inactive
                   :reason "cache refresh deadline missed")
                 (cadr-agent:cache-warmer-status warmer))))))

(test late-cache-refresh-is-rechecked-after-the-extension-decision
  (let ((now 0)
        (calls 0))
    (let ((warmer
            (cadr-agent:make-cache-warmer
             :now-function (lambda () now)
             :warm-function
             (lambda (run)
               (declare (ignore run))
               (incf calls))
             :decide-function
             (lambda ()
               (setf now 285001)
               :warm))))
      (cadr-agent:cache-warmer-start warmer :ttl-ms 300000)
      (cadr-agent:refresh-cache-warmer
       warmer (cadr-agent::cache-warmer-run warmer))
      (is (zerop calls))
      (is (equal '(:state :inactive
                   :reason "cache refresh deadline missed")
                 (cadr-agent:cache-warmer-status warmer))))))
