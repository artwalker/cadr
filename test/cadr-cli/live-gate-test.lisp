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
           "FAIL MODEL-VARIED [suspected model-output variance]"
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

(test live-quota-exhaustion-is-classified-as-environmental-skip
  (let ((kimi-message
          "You've reached your usage limit for this billing cycle. Your
quota will be refreshed in the next cycle. To continue now, purchase extra
usage or upgrade your plan: https://www.kimi.com/code/#pricing")
        (product-defect-message
          "Unexpected SSL failure on stream #<FLEXI-STREAM ...>"))
    (is
     (cadr-live-test-support:provider-quota-exhausted-p
      kimi-message))
    (is
     (cadr-live-test-support:provider-quota-exhausted-p
      "insufficient_quota"))
    (is
     (cadr-live-test-support:provider-quota-exhausted-p
      "Monthly usage limit reached"))
    (is
     (not
      (cadr-live-test-support:provider-quota-exhausted-p
       product-defect-message)))
    (is
     (not
      (cadr-live-test-support:provider-quota-exhausted-p
       nil)))
    (let* ((result
             (cadr-live-test-support:make-live-test-result
              :name 'quota-blocked-live-item
              :status :skip
              :checks 3
              :passes 0
              :skips 3
              :skip-reason
              "Provider account quota/usage limit reached; live verification cannot run"))
           (stream (make-string-output-stream)))
      (cadr-live-test-support:write-live-test-report
       (list result) stream)
      (let ((report (get-output-stream-string stream)))
        (is
         (search
          "SKIP QUOTA-BLOCKED-LIVE-ITEM: Provider account quota/usage limit reached; live verification cannot run"
          report))
        (is
         (search
          "Checks: 3, pass: 0, skip: 3, fail: 0"
          report))))))

(test deterministic-systems-exclude-network-live-files
  (let ((root (asdf:system-source-directory "cadr-cli")))
    (dolist (asd '("cadr-ai.asd" "cadr-cli.asd" "cadr-evals.asd"))
      (asdf:load-asd (merge-pathnames asd root)))
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
                  ("cadr-ai/tests" "opencode-go-live-test.lisp")
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
        (is (not (null (asdf:find-system system nil))))))))

(test goal9-part-d-verify-entrypoint-has-approved-stage-contract
  (let* ((root (asdf:system-source-directory "cadr-cli"))
         (path (merge-pathnames "scripts/verify.sh" root))
         (source
           (and (probe-file path)
                (uiop:read-file-string path)))
         (script-paths
           '("scripts/check-root-binary.sh"
             "scripts/check-code-organization.py"
             "test/code-organization-gate-test.py"
             "scripts/check-source-parity-drift.sh"
             "scripts/test-source-parity-drift.sh"
             "scripts/check-summarization-choke-point.sh"
             "scripts/test-summarization-choke-point.sh"
             "scripts/test-cl.sh"
             "scripts/write-test-check-anchor.py"
             "build.sh"
             "build-server.sh"
             "scripts/bench.sh"
             "scripts/goal11-stability.sh"
             "scripts/goal11-performance-gate.py"
             "scripts/acceptance-smoke.sh"
             "scripts/test-wave2-process-modes.sh"
             "scripts/migration-smoke.sh"
             "scripts/server-smoke.sh"
             "scripts/goal9-a2-pty.sh"
             "scripts/goal5-manual-tui-smoke.sh"
             "scripts/goal20-liveness-check.py"
             "test/goal20-liveness-check-test.py"
             "scripts/render-diff.py"
             "test/render-diff-gate-test.py"
             "test/fixtures/render-diff/scenarios.json"
             "test/fixtures/render-diff/dispositions.json"
             "scripts/test-live.sh"
             "scripts/live-tui-smoke.sh"))
         (stage-labels
           '("root cadr binary freshness"
             "code organization gate"
             "real source parity ledger"
             "source parity drift self-test"
             "cadr-side mapping existence"
             "image-derived mapping freshness"
             "summarization choke point"
             "deterministic FiveAM"
             "FiveAM check-count ledger"
             "isolated cadr build"
             "isolated cadr-server build"
             "statistical liveness"
             "Goal 11 performance and stability gate"
             "native acceptance smoke"
             "native process modes"
             "migration PTY smoke"
             "Unix socket server smoke"
             "terminal lifecycle PTY"
             "deterministic TUI harness"
             "fixed-baseline render differential"
             "credential-gated FiveAM"
             "OpenCode Go live TUI")))
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
      (is (search "goal11-performance.json" source))
      (is (search "goal11-stability.json" source))
      (is (search "render-diff.py\" gate" source))
      (is (search "render-diff-analysis" source))
      (is (search "OPENCODE_API_KEY" source))
      (is (search "Deterministic stages" source))
      (is (search "Live stages" source))
      (is (not (search ".github/workflows" source)))
      ;; CI-1f: isolated tar has no .git; render-diff capture then
      ;; dies "fatal: not a git repository" in ~1s. Same cwd as the
      ;; render-diff gate (PROJECT_DIRECTORY).
      (let* ((start (search "run_statistical_liveness()" source))
             (end (and start (search "run_goal11_gate()" source
                                     :start2 start)))
             (body (and start end (subseq source start end))))
        (is (not (null body)))
        (when body
          (is (search "cd \"$PROJECT_DIRECTORY\"" body))
          (is (not (search "cd \"$ISOLATED_PROJECT\"" body))))))))

(test goal15-part-d-render-diff-gate-covers-the-real-complete-manifest
  (let* ((root (asdf:system-source-directory "cadr-cli"))
         (test-path
           (merge-pathnames "test/render-diff-gate-test.py" root)))
    (multiple-value-bind (output error-output status)
        (uiop:run-program
         (list "python3" (namestring test-path))
         :output :string
         :error-output :string
         :ignore-error-status t)
      (is (zerop status)
          "Render-diff gate orchestration regressions failed:~%~A~A"
          output error-output)
      (let ((summary-start (search "Ran " error-output)))
        (is (and summary-start
                 (plusp
                  (or (parse-integer
                       error-output
                       :start (+ summary-start (length "Ran "))
                       :junk-allowed t)
                      0)))
            "Render-diff gate did not execute any orchestration tests:~%~A"
            error-output))
      (is (search "OK" error-output)))))

(test goal11-continuous-alt-input-benchmarks-are-release-gated
  (let* ((root (asdf:system-source-directory "cadr-cli"))
         (bench
           (uiop:read-file-string
            (merge-pathnames "scripts/goal11-bench.lisp" root)))
         (baseline-bench
           (uiop:read-file-string
            (merge-pathnames
             "scripts/goal11-pi-baseline-bench.mjs" root)))
         (gate
           (uiop:read-file-string
            (merge-pathnames
             "scripts/goal11-performance-gate.py" root)))
         (profile-builder
           (uiop:read-file-string
            (merge-pathnames
             "scripts/goal13-session-scale-profile.py" root)))
         (profile
           (uiop:read-file-string
            (merge-pathnames
             "docs/benchmarks/goal-v13-session-scale.json" root))))
    (dolist (required
              '("mouse_drag_to_frame"
                "wheel_to_frame"
                "continuous_alt_input"
                "common_continuous_input"
                "sustained_mixed_interaction"
                "sustained-duration-seconds"
                "editor_key"
                "goal-v13-session-scale.json"
                "renderer_object_id"
                "1024"
                "renderer-handle-input"
                ":force-p t"))
      (is (search required bench)
          "Missing continuous-input benchmark contract: ~A"
          required))
    (dolist (required
              '("mouse_drag_to_frame"
                "wheel_to_frame"
                "continuous_alt_input"
                "common_continuous_input"
                "sustained_mixed_interaction"
                "sustained mixed interaction p99.9"
                "sustained mixed interaction memory"
                "gc_pause_samples_us"
                "editor_key"
                "absolute interaction target"
                "COMMON_ABSOLUTE_P99_US = 16_000"
                "fixed baseline regression"
                "renderer_object_id"
                "event_count"
                "p99_us"
                "gc_affected_max_us"))
      (is (search required gate)
          "Missing continuous-input release gate: ~A"
          required))
    (dolist (required
              '("TuiAltScreen"
                "mouse_drag_to_frame"
                "wheel_to_frame"
                "continuous_alt_input"
                "continuousEvents = 1024"
                "retained_heap_delta_bytes_per_event"
                "sampled_allocated_bytes_per_event"
                "allocation_sample_event_count"
                "loaded_dist_tree_sha256"
                "installed_dependency_tree_sha256"
                "paired_fresh_fixture_per_run"
                "event_trace_sha256"
                "renderer_mode"
                "emitInput"))
      (is (search required baseline-bench)
          "Missing fixed-baseline continuous-input benchmark contract: ~A"
          required))
    (dolist (required
              '("--baseline"
                "baseline_mouse_ratio"
                "baseline_wheel_ratio"
                "baseline_continuous_p99_ratio"
                "baseline_same_machine"
                "baseline_relative_gate"
                "FIXED_BASELINE_DIST_SHA256"
                "FIXED_BASELINE_ARTIFACT_SHA256"
                "gc_affected_samples_us"
                "production-request-immediate-flush"
                "paired_continuous_alt_input"
                "event_trace_sha256"))
      (is (search required gate)
          "Missing baseline-derived continuous-input release gate: ~A"
          required))
    (dolist (required
              '("parentId"
                "parent is False"
                "contains_message_content"
                "valid_session_count"
                "entry_percentiles"
                "tiers"))
      (is (search required profile-builder)
          "Missing anonymous session-scale profile contract: ~A"
          required))
    (dolist (required
              '("\"source_file_count\":45"
                "\"valid_session_count\":45"
                "\"invalid_session_count\":0"
                "\"common\":58"
                "\"stress\":5000"))
      (is (search required profile)
          "Missing checked-in anonymous session-scale fact: ~A"
          required))
    (multiple-value-bind (output error-output status)
        (uiop:run-program
         (list
          "python3"
          (namestring
           (merge-pathnames
            "test/goal11-performance-gate-test.py"
            root)))
         :output :string
         :error-output :string
         :ignore-error-status t)
      (is (zerop status)
          "Synthetic gate regressions failed:~%~A~A"
          output error-output)
      (is (search "Ran 11 tests" error-output))
      (is (search "OK" error-output)))))

(test delivery-binary-freshness-check-rejects-missing-stale-and-dirty-images
  (let* ((root (asdf:system-source-directory "cadr-cli"))
         (checker
           (merge-pathnames "scripts/check-root-binary.sh" root)))
    (is-true (probe-file checker))
    (when (probe-file checker)
      (with-test-directory (fixture-root)
        (let* ((project (merge-pathnames "project/" fixture-root))
               (source (merge-pathnames "src/example.lisp" project))
               (binary (merge-pathnames "cadr" project)))
          (write-text
           source
           (format nil "(in-package #:cl-user)~%"))
          (dolist
              (argv
               (list
                (list "git" "init" "-q" (namestring project))
                (list "git" "-C" (namestring project)
                      "config" "user.email" "cadr@example.invalid")
                (list "git" "-C" (namestring project)
                      "config" "user.name" "cadr test")
                (list "git" "-C" (namestring project)
                      "add" "src/example.lisp")
                (list
                 "env"
                 "GIT_AUTHOR_DATE=2030-01-01T00:00:00Z"
                 "GIT_COMMITTER_DATE=2030-01-01T00:00:00Z"
                 "git" "-C" (namestring project)
                 "commit" "-q" "-m" "fixture")))
            (uiop:run-program argv :output nil :error-output nil))
          (labels
              ((check ()
                 (multiple-value-bind (output error-output status)
                     (uiop:run-program
                      (list
                       (namestring checker)
                       "--project-directory"
                       (namestring project))
                      :output :string
                      :error-output :string
                      :ignore-error-status t)
                   (values
                    status
                    (concatenate 'string output error-output)))))
            (multiple-value-bind (status output) (check)
              (is (not (zerop status)))
              (is (search "root cadr binary is missing" output)))
            (write-text
             binary
             (format
              nil
              "#!/bin/sh~%printf '%s\\n' 'cadr fixture-version'~%"))
            (uiop:run-program
             (list "chmod" "+x" (namestring binary)))
            (uiop:run-program
             (list "touch" "-d" "2029-01-01T00:00:00Z"
                   (namestring binary)))
            (multiple-value-bind (status output) (check)
              (is (not (zerop status)))
              (is (search "root cadr binary is stale" output))
              ;; git %cI is either ...+00:00 or ...Z depending on version
              (is (search "2030-01-01T00:00:00" output)))
            (uiop:run-program
             (list "touch" "-d" "2031-01-01T00:00:00Z"
                   (namestring binary)))
            (multiple-value-bind (status output) (check)
              (is (zerop status))
              (is (search "cadr fixture-version" output))
              (is (search "root cadr binary is fresh" output)))
            (uiop:run-program
             (list "touch" "-d" "2032-01-01T00:00:00Z"
                   (namestring source)))
            (multiple-value-bind (status output) (check)
              (is (not (zerop status)))
              (is (search "root cadr binary is stale" output)))))))))

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
                  "PATH=%s/sbcl/bin:%s"
                  "$GITHUB_ENV"
                  "ANTHROPIC_API_KEY: \"\""
                  "DEEPSEEK_API_KEY: \"\""
                  "OPENAI_API_KEY: \"\""
                  "OPENCODE_API_KEY: \"\""
                  "actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd"
                  "persist-credentials: false"
                  "fetch-depth: 0"
                  "bsdutils"
                  "ca-certificates"
                  "fd-find"
                  "ripgrep"
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
                  "\"slynk\""
                  "./scripts/verify.sh"
                  "grep -Fx 'Items: 9, run: 0, pass: 0, skip: 9, fail: 0'"
                  "grep -Fx 'Checks: 9, pass: 0, skip: 9, fail: 0'"
                  "grep -Fx 'OpenCode Go live TUI                             SKIP (OpenCode Go API key is not configured)'"
                  "workflow_dispatch:"))
        (is (search required source) "Missing CI contract: ~A" required))
      (is (= 1 (count-substring "./scripts/verify.sh" source)))
      (is (= 3 (count-substring "\"$SBCL\"" source)))
      (dolist (forbidden
                '("./build.sh"
                  "./build-server.sh"
                  "./scripts/test-cl.sh"
                  "./scripts/test-live.sh"
                  "pull_request_target"
                  "push:"
                  "pull_request:"
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
