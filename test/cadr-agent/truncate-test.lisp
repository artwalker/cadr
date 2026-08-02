(in-package #:cadr-agent/tests)
(in-suite cadr-agent-suite)

(test harness-truncation-matches-reference-line-and-utf8-boundaries
  (let ((full
          (cadr-agent::truncate-harness-head
           (format nil "aé🙂~%b")
           :max-lines 10
           :max-bytes 100))
        (head
          (cadr-agent::truncate-harness-head
           (format nil "éé~%abc")
           :max-lines 10
           :max-bytes 4))
        (too-wide
          (cadr-agent::truncate-harness-head
           (format nil "éé~%abc")
           :max-lines 10
           :max-bytes 3))
        (tail
          (cadr-agent::truncate-harness-tail
           "aé🙂b"
           :max-lines 10
           :max-bytes 5)))
    (is (not
         (cadr-agent::harness-truncation-result-truncated-p
          full)))
    (is (= 9
           (cadr-agent::harness-truncation-result-total-bytes
            full)))
    (is (string=
         "éé"
         (cadr-agent::harness-truncation-result-content
          head)))
    (is (eq
         :bytes
         (cadr-agent::harness-truncation-result-truncated-by
          head)))
    (is
     (cadr-agent::harness-truncation-result-first-line-exceeds-limit-p
      too-wide))
    (is (string=
         "🙂b"
         (cadr-agent::harness-truncation-result-content
          tail)))
    (is
     (cadr-agent::harness-truncation-result-last-line-partial-p
      tail))
    (is (= 5
           (cadr-agent::harness-truncation-result-output-bytes
            tail)))))

(test harness-truncation-does-not-count-trailing-newline-as-a-line
  (dolist
      (function
       (list
        #'cadr-agent::truncate-harness-head
        #'cadr-agent::truncate-harness-tail))
    (let ((result
            (funcall
             function
             (format nil "one~%two~%three~%")
             :max-lines 3
             :max-bytes 100)))
      (is
       (not
        (cadr-agent::harness-truncation-result-truncated-p
         result)))
      (is (= 3
             (cadr-agent::harness-truncation-result-total-lines
              result))))))

(test harness-tail-never-splits-valid-unicode
  (let ((input "aé🙂中b"))
    (loop for maximum from 0 to 16
          for result =
            (cadr-agent::truncate-harness-tail
             input
             :max-lines 10
             :max-bytes maximum)
          do
      (is
       (<=
        (length
         (cadr-ai::utf8-octets
          (cadr-agent::harness-truncation-result-content
           result)))
        maximum)))))

(test goal12-shared-truncation-api-preserves-baseline-semantics
  (let ((complete
          (cadr-agent::truncate-head
           (format nil "alpha~%beta~%")
           :max-lines 2 :max-bytes 100))
        (head
          (cadr-agent::truncate-head
           (format nil "éé~%abc")
           :max-lines 10 :max-bytes 3))
        (tail
          (cadr-agent::truncate-tail
           "aé🙂b"
           :max-lines 10 :max-bytes 5)))
    (is (typep complete 'cadr-agent::truncation-result))
    (is (string= (format nil "alpha~%beta~%")
                 (cadr-agent::truncation-result-content complete)))
    (is (not (cadr-agent::truncation-result-truncated-p complete)))
    (is (= 2 (cadr-agent::truncation-result-total-lines complete)))
    (is (= 11 (cadr-agent::truncation-result-total-bytes complete)))
    (is (string= "" (cadr-agent::truncation-result-content head)))
    (is (eq :bytes
            (cadr-agent::truncation-result-truncated-by head)))
    (is (cadr-agent::truncation-result-first-line-exceeds-limit-p
         head))
    (is (string= "🙂b"
                 (cadr-agent::truncation-result-content tail)))
    (is (cadr-agent::truncation-result-last-line-partial-p tail)))
  (multiple-value-bind (text truncated-p)
      (cadr-agent::truncate-line "🙂🙂x" 4)
    (is (string= "🙂🙂... [truncated]" text))
    (is (not (null truncated-p))))
  (multiple-value-bind (text truncated-p)
      (cadr-agent::truncate-line "🙂🙂x" 5)
    (is (string= "🙂🙂x" text))
    (is (not truncated-p)))
  (is (string= "1023B" (cadr-agent::format-size 1023)))
  (is (string= "1.0KB" (cadr-agent::format-size 1024)))
  (is (string= "1.0MB" (cadr-agent::format-size (* 1024 1024)))))

(test goal12-file-mutation-queue-is-fifo-and-releases-after-errors
  (let* ((path
           (merge-pathnames
            "goal12-agent-mutation.txt"
            (uiop:temporary-directory)))
         (first-entered (sb-thread:make-semaphore :count 0))
         (release-first (sb-thread:make-semaphore :count 0))
         (second-entered (sb-thread:make-semaphore :count 0))
         (release-second (sb-thread:make-semaphore :count 0))
         (third-entered (sb-thread:make-semaphore :count 0))
         (order nil)
         (guard (sb-thread:make-mutex :name "goal12 mutation order"))
         (state (cadr-agent::file-mutation-queue-lock path)))
    (labels ((record (event)
               (sb-thread:with-mutex (guard)
                 (push event order)))
             (wait-for-pending (count)
               (sb-thread:with-mutex
                   (cadr-agent::*file-mutation-queues-guard*)
                 (loop while
                       (< (cadr-agent::file-mutation-queue-state-pending-count
                           state)
                          count)
                       do
                   (sb-thread:condition-wait
                    (cadr-agent::file-mutation-queue-state-waitqueue state)
                    cadr-agent::*file-mutation-queues-guard*)))))
      (let ((first
              (sb-thread:make-thread
               (lambda ()
                 (handler-case
                     (cadr-agent::with-file-mutation-queue
                      path
                      (lambda ()
                        (record :first-start)
                        (sb-thread:signal-semaphore first-entered)
                        (sb-thread:wait-on-semaphore release-first)
                        (record :first-error)
                        (error "expected mutation failure")))
                   (error () nil))))))
        (sb-thread:wait-on-semaphore first-entered)
        (let ((second
                (sb-thread:make-thread
                 (lambda ()
                   (cadr-agent::with-file-mutation-queue
                    path
                    (lambda ()
                      (record :second)
                      (sb-thread:signal-semaphore second-entered)
                      (sb-thread:wait-on-semaphore release-second)))))))
          (wait-for-pending 2)
          (let ((third
                  (sb-thread:make-thread
                   (lambda ()
                     (cadr-agent::with-file-mutation-queue
                      path
                      (lambda ()
                        (record :third)
                        (sb-thread:signal-semaphore third-entered)))))))
            (wait-for-pending 3)
            (sb-thread:signal-semaphore release-first)
            (sb-thread:wait-on-semaphore second-entered)
            (is (not (sb-thread:try-semaphore third-entered)))
            (sb-thread:signal-semaphore release-second)
            (sb-thread:join-thread first)
            (sb-thread:join-thread second)
            (sb-thread:join-thread third))))
      (is (equal '(:first-start :first-error :second :third)
                 (nreverse order))))))

(test goal12-file-mutation-queue-canonicalizes-aliases-and-parallelizes-files
  (let* ((directory
           (uiop:ensure-directory-pathname
            (merge-pathnames
             (format nil "cadr-goal12-mutation-~36R/" (random most-positive-fixnum))
             (uiop:temporary-directory))))
         (target (merge-pathnames "target.txt" directory))
         (alias (merge-pathnames "alias.txt" directory))
         (other (merge-pathnames "other.txt" directory)))
    (unwind-protect
         (progn
           (ensure-directories-exist target)
           (with-open-file
               (stream target :direction :output
                              :if-exists :supersede
                              :if-does-not-exist :create)
             (write-string "seed" stream))
           (sb-posix:symlink (namestring target) (namestring alias))
           (is (string=
                (cadr-agent::file-mutation-queue-key target)
                (cadr-agent::file-mutation-queue-key alias)))
           (let ((state (cadr-agent::file-mutation-queue-lock target))
                 (target-entered (sb-thread:make-semaphore :count 0))
                 (release-target (sb-thread:make-semaphore :count 0))
                 (alias-entered (sb-thread:make-semaphore :count 0))
                 (other-entered (sb-thread:make-semaphore :count 0)))
             (let ((target-thread
                     (sb-thread:make-thread
                      (lambda ()
                        (cadr-agent::with-file-mutation-queue
                         target
                         (lambda ()
                           (sb-thread:signal-semaphore target-entered)
                           (sb-thread:wait-on-semaphore release-target)))))))
               (sb-thread:wait-on-semaphore target-entered)
               (let ((alias-thread
                       (sb-thread:make-thread
                        (lambda ()
                          (cadr-agent::with-file-mutation-queue
                           alias
                          (lambda ()
                             (sb-thread:signal-semaphore alias-entered))))))
                     (other-thread
                       (sb-thread:make-thread
                        (lambda ()
                          (cadr-agent::with-file-mutation-queue
                           other
                          (lambda ()
                             (sb-thread:signal-semaphore other-entered)))))))
                 (sb-thread:with-mutex
                     (cadr-agent::*file-mutation-queues-guard*)
                   (loop while
                         (< (cadr-agent::file-mutation-queue-state-pending-count
                             state)
                            2)
                         do
                     (sb-thread:condition-wait
                      (cadr-agent::file-mutation-queue-state-waitqueue state)
                      cadr-agent::*file-mutation-queues-guard*)))
                 (sb-thread:wait-on-semaphore other-entered)
                 (is (not (sb-thread:try-semaphore alias-entered)))
                 (sb-thread:signal-semaphore release-target)
                 (sb-thread:join-thread target-thread)
                 (sb-thread:join-thread alias-thread)
                 (sb-thread:join-thread other-thread)))))
      (uiop:delete-directory-tree
       directory :validate t :if-does-not-exist :ignore))))
