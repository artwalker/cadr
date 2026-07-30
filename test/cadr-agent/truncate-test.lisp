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
