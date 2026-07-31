(in-package #:cadr-evals/tests)

(in-suite cadr-evals-suite)

(defun comparison-observation
    (harness test-name result
     &key total-tokens total-ms
       estimated-cost-usd
       (baseline "without-tools")
       (candidates '("with-tools"))
       (file "src/tool-access.eval.ts"))
  (apply
   #'cadr-evals:make-harness-observation
   :eval-set "tool access"
   :group-key
   (format nil "[\"~A\",1]" test-name)
   :test-name test-name
   :file file
   :harness harness
   :baseline baseline
   :candidates candidates
   :repetition 1
   :outcome
   (if (member result '(:passed :failed))
       :scored
       result)
   (append
    (when (member result '(:passed :failed))
      (list :score
            (if (eq result :passed)
                1
                0)))
    (when total-tokens
      (list :total-tokens total-tokens))
    (when total-ms
      (list :total-ms total-ms))
    (when estimated-cost-usd
      (list :estimated-cost-usd
            estimated-cost-usd)))))

(defun first-harness-comparison (report)
  (first
   (cadr-evals:harness-eval-set-report-comparisons
    (first
     (cadr-evals:harness-comparison-report-eval-sets
      report)))))

(test harness-summary-computes-correctness-and-efficiency-separately
  (let* ((report
           (cadr-evals:summarize-harness-comparisons
            (list
             (comparison-observation
              "without-tools" "create" :failed
              :total-tokens 100
              :total-ms 1000
              :estimated-cost-usd 0.01d0)
             (comparison-observation
              "with-tools" "create" :passed
              :total-tokens 120
              :total-ms 800
              :estimated-cost-usd 0.02d0)
             (comparison-observation
              "without-tools" "inspect" :passed
              :total-tokens 200)
             (comparison-observation
              "with-tools" "inspect" :passed
              :total-tokens 180))))
         (comparison
           (first-harness-comparison report))
         (correctness
           (cadr-evals:harness-pair-comparison-correctness
            comparison))
         (tokens
           (cadr-evals:harness-pair-comparison-total-tokens
            comparison))
         (latency
           (cadr-evals:harness-pair-comparison-total-ms
            comparison))
         (cost
           (cadr-evals:harness-pair-comparison-estimated-cost-usd
            comparison)))
    (is (= 2
           (cadr-evals:correctness-lift-summary-total-pairs
            correctness)))
    (is (= 2
           (cadr-evals:correctness-lift-summary-eligible-pairs
            correctness)))
    (is (= 0.5d0
           (cadr-evals:correctness-lift-summary-baseline-pass-rate
            correctness)))
    (is (= 1
           (cadr-evals:correctness-lift-summary-candidate-pass-rate
            correctness)))
    (is (= 0.5d0
           (cadr-evals:correctness-lift-summary-lift
            correctness)))
    (is (= 1
           (cadr-evals:correctness-lift-summary-candidate-wins
            correctness)))
    (is (= 1
           (cadr-evals:correctness-lift-summary-ties
            correctness)))
    (is (= 150
           (cadr-evals:paired-metric-summary-baseline-mean
            tokens)))
    (is (= 150
           (cadr-evals:paired-metric-summary-candidate-mean
            tokens)))
    (is (= 0
           (cadr-evals:paired-metric-summary-mean-delta
            tokens)))
    (is (= 1
           (cadr-evals:paired-metric-summary-eligible-pairs
            latency)))
    (is (= -200
           (cadr-evals:paired-metric-summary-mean-delta
            latency)))
    (is (= 0.01d0
           (cadr-evals:paired-metric-summary-mean-delta
            cost)))
    (is (null
         (cadr-evals:harness-comparison-report-diagnostics
          report)))))

(test harness-summary-reports-incomplete-observations-without-coercion
  (let* ((report
           (cadr-evals:summarize-harness-comparisons
            (list
             (comparison-observation
              "without-tools" "create" :failed)
             (comparison-observation
              "with-tools" "create" :passed)
             (comparison-observation
              "without-tools" "inspect" :passed))))
         (comparison
           (first-harness-comparison report))
         (correctness
           (cadr-evals:harness-pair-comparison-correctness
            comparison))
         (tokens
           (cadr-evals:harness-pair-comparison-total-tokens
            comparison))
         (diagnostics
           (cadr-evals:harness-comparison-report-diagnostics
            report)))
    (is (= 2
           (cadr-evals:correctness-lift-summary-total-pairs
            correctness)))
    (is (= 1
           (cadr-evals:correctness-lift-summary-eligible-pairs
            correctness)))
    (is (= 1
           (cadr-evals:correctness-lift-summary-lift
            correctness)))
    (is (= 0
           (cadr-evals:paired-metric-summary-eligible-pairs
            tokens)))
    (is (null
         (cadr-evals:paired-metric-summary-baseline-mean
          tokens)))
    (is (find-if
         (lambda (diagnostic)
           (and
            (string=
             "inspect"
             (cadr-evals:harness-comparison-diagnostic-test-name
              diagnostic))
            (string=
             "with-tools"
             (cadr-evals:harness-comparison-diagnostic-harness
              diagnostic))
            (eq
             :missing-observation
             (cadr-evals:harness-comparison-diagnostic-reason
              diagnostic))))
         diagnostics))))

(test harness-summary-keeps-files-separate-and-errors-unscored
  (let* ((report
           (cadr-evals:summarize-harness-comparisons
            (list
             (comparison-observation
              "without-tools" "shared" :errored
              :total-tokens 100)
             (comparison-observation
              "with-tools" "shared" :passed
              :total-tokens 100)
             (comparison-observation
              "without-tools" "shared" :passed
              :file "src/other.eval.ts")
             (comparison-observation
              "with-tools" "shared" :passed
              :file "src/other.eval.ts"))))
         (comparison
           (first-harness-comparison report))
         (correctness
           (cadr-evals:harness-pair-comparison-correctness
            comparison)))
    (is (= 2
           (cadr-evals:correctness-lift-summary-total-pairs
            correctness)))
    (is (= 1
           (cadr-evals:correctness-lift-summary-eligible-pairs
            correctness)))
    (is (find-if
         (lambda (diagnostic)
           (and
            (eq :harness-error
                (cadr-evals:harness-comparison-diagnostic-reason
                 diagnostic))
            (string=
             "without-tools"
             (cadr-evals:harness-comparison-diagnostic-harness
              diagnostic))))
         (cadr-evals:harness-comparison-report-diagnostics
          report)))))

(test harness-summary-does-not-infer-score-from-completion
  (let* ((report
           (cadr-evals:summarize-harness-comparisons
            (list
             (comparison-observation
              "without-tools" "create" :unscored)
             (comparison-observation
              "with-tools" "create" :unscored))))
         (comparison
           (first-harness-comparison report)))
    (is (= 0
           (cadr-evals:correctness-lift-summary-eligible-pairs
            (cadr-evals:harness-pair-comparison-correctness
             comparison))))
    (is (= 2
           (count
            :missing-score
            (cadr-evals:harness-comparison-report-diagnostics
             report)
            :key
            #'cadr-evals:harness-comparison-diagnostic-reason)))))

(test harness-summary-compares-each-candidate-to-declared-baseline
  (let* ((candidates '("second" "third"))
         (report
           (cadr-evals:summarize-harness-comparisons
            (list
             (comparison-observation
              "first" "input" :passed
              :baseline "first"
              :candidates candidates)
             (comparison-observation
              "second" "input" :passed
              :baseline "first"
              :candidates candidates)
             (comparison-observation
              "third" "input" :passed
              :baseline "first"
              :candidates candidates))))
         (comparisons
           (cadr-evals:harness-eval-set-report-comparisons
            (first
             (cadr-evals:harness-comparison-report-eval-sets
              report)))))
    (is (equal
         '(("first" "second")
           ("first" "third"))
         (mapcar
          (lambda (comparison)
            (list
             (cadr-evals:harness-pair-comparison-baseline
              comparison)
             (cadr-evals:harness-pair-comparison-candidate
              comparison)))
          comparisons)))))

(test harness-summary-diagnoses-duplicates-and-skips-once
  (let* ((candidates '("second" "third"))
         (report
           (cadr-evals:summarize-harness-comparisons
            (list
             (comparison-observation
              "first" "duplicate" :passed
              :baseline "first"
              :candidates candidates)
             (comparison-observation
              "first" "duplicate" :failed
              :baseline "first"
              :candidates candidates)
             (comparison-observation
              "second" "duplicate" :passed
              :baseline "first"
              :candidates candidates)
             (comparison-observation
              "third" "duplicate" :passed
              :baseline "first"
              :candidates candidates)
             (comparison-observation
              "first" "skipped" :skipped
              :baseline "first"
              :candidates candidates)
             (comparison-observation
              "second" "skipped" :passed
              :baseline "first"
              :candidates candidates)
             (comparison-observation
              "third" "skipped" :passed
              :baseline "first"
              :candidates candidates))))
         (diagnostics
           (cadr-evals:harness-comparison-report-diagnostics
            report)))
    (is (= 1
           (count
            :duplicate-observation diagnostics
            :key
            #'cadr-evals:harness-comparison-diagnostic-reason)))
    (is (= 1
           (count
            :unscorable-outcome diagnostics
            :key
            #'cadr-evals:harness-comparison-diagnostic-reason)))))

(test harness-summary-formats-terminal-report
  (let* ((report
           (cadr-evals:summarize-harness-comparisons
            (list
             (comparison-observation
              "without-tools" "create" :failed
              :total-ms 34853.7d0)
             (comparison-observation
              "with-tools" "create" :passed
              :total-ms 30694.2d0))))
         (formatted
           (cadr-evals:format-harness-comparison-report
            report)))
    (is (search "Eval Comparisons" formatted))
    (is (search "Baseline  without-tools" formatted))
    (is (search "Candidate  with-tools (1/1 pairs)" formatted))
    (is (search
         "Pass rate  +100.0 pp (candidate 100.0%, baseline 0.0%)"
         formatted))
    (is (search "Tokens  unavailable" formatted))
    (is (search
         "Latency  -4159.5ms (candidate 30694.2ms, baseline 34853.7ms)"
         formatted))))
