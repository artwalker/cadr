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

(test goal9-part-d-verify-entrypoint-has-approved-stage-contract
  (let* ((root (asdf:system-source-directory "cadr-cli"))
         (path (merge-pathnames "scripts/verify.sh" root))
         (source
           (and (probe-file path)
                (uiop:read-file-string path)))
         (script-paths
           '("scripts/test-cl.sh"
             "build.sh"
             "build-server.sh"
             "scripts/acceptance-smoke.sh"
             "scripts/test-wave2-process-modes.sh"
             "scripts/migration-smoke.sh"
             "scripts/server-smoke.sh"
             "scripts/goal9-a2-pty.sh"
             "scripts/goal5-manual-tui-smoke.sh"
             "scripts/test-live.sh"
             "scripts/live-tui-smoke.sh"))
         (stage-labels
           '("deterministic FiveAM"
             "isolated cadr build"
             "isolated cadr-server build"
             "native acceptance smoke"
             "native process modes"
             "migration PTY smoke"
             "Unix socket server smoke"
             "terminal lifecycle PTY"
             "deterministic TUI harness"
             "credential-gated FiveAM"
             "DeepSeek live TUI")))
    (is-true source)
    (when source
      (let ((previous -1))
        (dolist (stage stage-labels)
          (let ((position
                  (search stage source
                          :start2 (1+ previous))))
            (is-true position)
            (when position
              (setf previous position)))))
      (dolist (path script-paths)
        (is (search path source)))
      (is (search "mktemp -d" source))
      (is (search "--exclude=.git" source))
      (is (search "DEEPSEEK_API_KEY" source))
      (is (search "Deterministic stages" source))
      (is (search "Live stages" source))
      (is (not (search ".github/workflows" source))))))

(test goal10-part-c-ci-workflow-is-pinned-minimal-and-credential-free
  (let* ((root (asdf:system-source-directory "cadr-cli"))
         (path (merge-pathnames ".github/workflows/ci.yml" root))
         (source
           (and (probe-file path)
                (uiop:read-file-string path))))
    (is-true source)
    (when source
      (dolist (required
                  `(,(format nil "permissions:~%  contents: read")
                  "runs-on: ubuntu-24.04"
                  "HOME=%s/cadr-home"
                  "QUICKLISP_SETUP=%s/cadr-home/quicklisp/setup.lisp"
                  "SBCL=%s/sbcl/bin/sbcl"
                  "$GITHUB_ENV"
                  "ANTHROPIC_API_KEY: \"\""
                  "DEEPSEEK_API_KEY: \"\""
                  "OPENAI_API_KEY: \"\""
                  "actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd"
                  "persist-credentials: false"
                  "bsdutils"
                  "ca-certificates"
                  "sbcl-2.6.7-x86-64-linux-binary.tar.bz2?download"
                  "4ed82aa7d5b1d87cbafb41ab9abc87d942d18eeac2485ee5a6c46b95aa694d19"
                  "INSTALL_ROOT=\"$RUNNER_TEMP/sbcl\" sh install.sh"
                  "https://beta.quicklisp.org/quicklisp.lisp"
                  "4a7a5c2aebe0716417047854267397e24a44d0cce096127411e9ce9ccfeb2c17"
                  ":dist-url \\\"http://beta.quicklisp.org/dist/quicklisp/2026-01-01/distinfo.txt\\\""
                  "\"cl+ssl\""
                  "\"cl-ppcre\""
                  "\"sqlite\""
                  "\"cl-jpeg\""
                  "\"png-read\""
                  "\"fiveam\""
                  "\"babel\""
                  "\"bordeaux-threads\""
                  "\"flexi-streams\""
                  "\"usocket\""
                  "\"trivial-gray-streams\""
                  "./scripts/verify.sh"
                  "grep -Fx 'Items: 8, run: 0, pass: 0, skip: 8, fail: 0'"
                  "grep -Fx 'Checks: 8, pass: 0, skip: 8, fail: 0'"
                  "grep -Fx 'DeepSeek live TUI                                SKIP (DEEPSEEK_API_KEY is not set)'"))
        (is (search required source) "Missing CI contract: ~A" required))
      (is (= 1 (count-substring "./scripts/verify.sh" source)))
      (is (= 3 (count-substring "\"$SBCL\"" source)))
      (dolist (forbidden
                '("./build.sh"
                  "./build-server.sh"
                  "./scripts/test-cl.sh"
                  "./scripts/test-live.sh"
                  "pull_request_target"
                  "actions/cache"
                  "actions/upload-artifact"
                  "actions/download-artifact"
                  "sudo sh install.sh"
                  "HOME: ${{ runner.temp"
                  "SBCL: ${{ runner.temp"
                  "QUICKLISP_SETUP: ${{ runner.temp"
                  "secrets."))
        (is (not (search forbidden source :test #'char-equal))
            "Forbidden CI mechanism: ~A" forbidden)))))
