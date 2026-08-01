(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defun test-live-result
    (name status &key (checks 1) (passes 0) (skips 0)
                       (failures 0) skip-reason failure-output
                       nature basis)
  (cadr-live-test-support:make-live-test-result
   :name name
   :status status
   :checks checks
   :passes passes
   :skips skips
   :failures failures
   :skip-reason skip-reason
   :failure-output failure-output
   :nature nature
   :basis basis))

(test live-runner-continues-after-a-failed-item
  (let ((visited nil)
        (specs
          (list
           (cadr-live-test-support:make-live-test-spec
            :name 'first-live-test)
           (cadr-live-test-support:make-live-test-spec
            :name 'second-live-test))))
    (let ((results
            (cadr-live-test-support:execute-live-test-specs
             specs
             (lambda (spec)
               (push
                (cadr-live-test-support:live-test-spec-name spec)
                visited)
               (if (eq
                    'first-live-test
                    (cadr-live-test-support:live-test-spec-name spec))
                   (error "first item exploded")
                   (test-live-result
                    'second-live-test :pass
                    :passes 1))))))
      (is (equal '(first-live-test second-live-test)
                 (nreverse visited)))
      (is (= 2 (length results)))
      (is (eq :fail
              (cadr-live-test-support:live-test-result-status
               (first results))))
      (is (eq :unable-to-determine
              (cadr-live-test-support:live-test-result-nature
               (first results))))
      (is (search
           "first item exploded"
           (cadr-live-test-support:live-test-result-failure-output
            (first results))))
      (is (eq :pass
              (cadr-live-test-support:live-test-result-status
               (second results)))))))

(test live-report-lists-every-item-and-complete-counts
  (let* ((results
           (list
            (test-live-result
             'ran-and-passed :pass
             :checks 2 :passes 2)
            (test-live-result
             'credential-was-absent :skip
             :checks 1 :skips 1
             :skip-reason "ANTHROPIC_API_KEY is not set")
            (test-live-result
             'model-varied :fail
             :checks 3 :passes 2 :failures 1
             :failure-output "expected SELF_EXTENSION_OK"
             :nature :suspected-model-output-variation
             :basis "The provider returned, but a behavioral assertion failed.")))
         (stream (make-string-output-stream)))
    (is (not
         (cadr-live-test-support:write-live-test-report
          results stream)))
    (let ((report (get-output-stream-string stream)))
      (is (search "PASS RAN-AND-PASSED (2 checks)" report))
      (is (search
           "SKIP CREDENTIAL-WAS-ABSENT: ANTHROPIC_API_KEY is not set"
           report))
      (is (search
           "FAIL MODEL-VARIED [疑似模型输出波动]"
           report))
      (is (search "expected SELF_EXTENSION_OK" report))
      (is (search
           "Basis: The provider returned, but a behavioral assertion failed."
           report))
      (is (search
           "Checks: 6, pass: 4, skip: 1, fail: 1"
           report))
      (is (search
           "Items: 3, run: 2, pass: 1, skip: 1, fail: 1"
           report)))))

(test deterministic-systems-exclude-network-live-files
  (labels ((component-pathnames (component)
             (let ((children
                     (ignore-errors
                       (asdf:component-children component))))
               (if children
                   (mapcan #'component-pathnames children)
                   (let ((pathname
                           (asdf:component-pathname component)))
                     (and pathname
                          (list (namestring pathname))))))))
    (dolist (case
              '(("cadr-ai/tests" "live-provider-test.lisp")
                ("cadr-cli/tests" "live-test.lisp")
                ("cadr-evals/tests" "live-evals-test.lisp")))
      (destructuring-bind (system forbidden-suffix) case
        (is (notany
             (lambda (pathname)
               (uiop:string-suffix-p
                forbidden-suffix pathname))
             (component-pathnames
              (asdf:find-system system))))))
    (dolist (system
              '("cadr-ai/live-tests"
                "cadr-cli/live-tests"
                "cadr-evals/live-tests"))
      (is (not (null (asdf:find-system system nil)))))))
