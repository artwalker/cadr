(in-package #:cadr-cli/tests)

(in-suite cadr-cli-suite)

(test goal20-part-b-ledger-scripts-and-anchors
  (let* ((root (asdf:system-source-directory "cadr-cli"))
         (python
           (merge-pathnames "test/goal20-part-b-ledger-test.py" root))
         (matrix
           (uiop:read-file-string
            (merge-pathnames "docs/test-matrix.md" root)))
         (perf
           (uiop:read-file-string
            (merge-pathnames "docs/performance.md" root))))
    (is-true (probe-file python))
    (is-true
     (probe-file
      (merge-pathnames "docs/benchmarks/goal20-paired-paths.json" root)))
    (is (search "GOAL20_TEST_CHECKS" matrix))
    (is (search "GOAL20_PAIRED_PATHS_START" perf))
    (is (search "GOAL20_PAIRED_PATHS_END" perf))
    (multiple-value-bind (output error-output status)
        (uiop:run-program
         (list "python3" (namestring python))
         :output :string
         :error-output :string
         :ignore-error-status t)
      (is (zerop status)
          "Part B ledger regressions failed:~%~A~A"
          output error-output)
      (is (search "OK" error-output)))))
