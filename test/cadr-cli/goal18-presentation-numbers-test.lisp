(in-package #:cadr-cli/tests)

(in-suite cadr-cli-suite)

;;; Goal 18 I4: the presentation ledger's scale numbers must be
;;; machine-reconciled against the real artifacts — scenario/capture
;;; counts from scenarios.json, site/branch obligation counts from
;;; baseline-visible-strings.json, and snapshot case counts from the
;;; live case constructors — never hand-synced from memory.

(defun goal18-json-array (value)
  (cond
    ((vectorp value) (coerce value 'list))
    ((listp value) value)
    (t nil)))

(defun goal18-read-json (root relative)
  (cadr-ai::parse-json
   (uiop:read-file-string
    (merge-pathnames relative root)
    :external-format :utf-8)))

(defun goal18-scenario-counts (root)
  (let* ((data
          (goal18-read-json
           root "test/fixtures/render-diff/scenarios.json"))
         (scenarios
          (goal18-json-array (cadr-ai::json-get data "scenarios")))
         (core
          (remove-if
           (lambda (scenario)
             (string=
              (cadr-ai::json-get scenario "tier" "core")
              "full"))
           scenarios)))
    (values (length core) (length scenarios))))

(defun goal18-visible-string-counts (root)
  (let* ((data
          (goal18-read-json
           root
           "test/fixtures/render-diff/baseline-visible-strings.json"))
         (entries
          (goal18-json-array (cadr-ai::json-get data "entries")))
         (printable
          (remove-if-not
           (lambda (entry)
             (string=
              (cadr-ai::json-get
               (cadr-ai::json-get entry "sink")
               "channel")
              "printable-visible"))
           entries))
         (branches
          (remove-duplicates
           (loop for entry in printable
                 append
                 (loop for branch
                       in (goal18-json-array
                           (cadr-ai::json-get entry "branches"))
                       collect (cadr-ai::json-get branch "id")))
           :test #'string=)))
    (values (length printable) (length branches))))

(test goal18-presentation-ledger-numbers-match-the-real-artifacts
  (let ((root (asdf:system-source-directory "cadr-cli")))
    (multiple-value-bind (core-count full-count)
        (goal18-scenario-counts root)
      (multiple-value-bind (sites branches)
          (goal18-visible-string-counts root)
        (let* ((ledger
                (uiop:read-file-string
                 (merge-pathnames "docs/presentation-parity.md" root)
                 :external-format :utf-8))
               (base-screens
                (length (goal9-b3-base-screen-cases)))
               (overlays
                (length (goal9-b3-overlay-screen-cases)))
               (expected
                (format
                 nil
                 "~D base-screen and ~D overlay snapshots with independent baseline assertions; fixed-baseline PTY render differential: ~D scenarios/~D captures in `verify.sh`, ~D/~D in the mandatory pre-tag and post-upstream full gate; the latter proves all ~D printable sites/~D printable branch obligations are captured or explicitly exempted"
                 base-screens
                 overlays
                 core-count
                 (* 2 core-count)
                 full-count
                 (* 2 full-count)
                 sites
                 branches)))
          (is (not (null (search expected ledger)))
              "presentation-parity.md C-01 drifted from the artifacts; expected:~%~A"
              expected))))))
