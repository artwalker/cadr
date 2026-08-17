(in-package #:cadr-evals)

(defstruct eval-reporter-case
  (id "" :type string)
  (file "" :type string)
  (name "" :type string)
  (full-name "" :type string)
  status
  (harness-name "" :type string)
  result
  score
  (artifacts nil :type list))

(defstruct (eval-harness-reporter
            (:constructor
                %make-eval-harness-reporter))
  artifact-directory
  (output *standard-output* :type stream)
  (observations nil :type list))

(defun make-eval-harness-reporter
    (&key artifact-directory
       (output *standard-output*))
  (%make-eval-harness-reporter
   :artifact-directory
   (or artifact-directory
       (eval-environment
        "CADR_EVAL_ARTIFACT_DIR"))
   :output output))

(defun reporter-finite-number (value)
  (and value
       (finite-observation-number-p value)
       value))

(defun reporter-status-name (status)
  (string-downcase
   (if (symbolp status)
       (symbol-name status)
       (princ-to-string status))))

(defun reporter-artifact-metadata (result)
  (let ((metadata
          (make-hash-table :test #'equal)))
    (maphash
     (lambda (name value)
       (unless
           (member
            name
            (list
             "runId"
             +cadr-session-snapshot-artifact+)
            :test #'string=)
         (setf (gethash name metadata)
               value)))
     (eval-result-artifacts result))
    metadata))

(defun reporter-run-id (result)
  (let ((run-id
          (cadr-ai::json-get
           (eval-result-artifacts result)
           "runId")))
    (if (stringp run-id)
        run-id
        (cadr-ai:uuid-v7))))

(defun reporter-artifacts
    (case result)
  (remove
   nil
   (append
    (list
     (record-eval-session-artifact
      (eval-result-artifacts result)))
    (eval-result-recorded-artifacts result)
    (eval-reporter-case-artifacts case))))

(defun artifact-reference-json (reference)
  (cadr-ai::json-object
   "name"
   (eval-artifact-reference-name reference)
   "path"
   (eval-artifact-reference-path reference)))

(defun ensure-reporter-directory (directory)
  (let ((root
          (uiop:ensure-directory-pathname
           directory)))
    (ensure-directories-exist
     (merge-pathnames "anchor" root))
    (sb-posix:chmod
     (namestring root) #o700)
    root))

(defun append-reporter-record
    (case directory)
  (let* ((result
           (eval-reporter-case-result case))
         (run-id
           (reporter-run-id result))
         (root
           (ensure-reporter-directory
            directory))
         (references
           (persist-eval-artifact-references
            (reporter-artifacts
             case result)
            run-id root))
         (metadata
           (reporter-artifact-metadata
            result))
         (test
           (cadr-ai::json-object
            "id"
            (eval-reporter-case-id case)
            "file"
            (eval-reporter-case-file case)
            "name"
            (eval-reporter-case-name case)
            "fullName"
            (eval-reporter-case-full-name case)
            "status"
            (reporter-status-name
             (eval-reporter-case-status case))))
         (record
           (cadr-ai::json-object
            "schemaVersion" 1
            "runId" run-id
            "test" test
            "harness"
            (eval-reporter-case-harness-name
             case)
            "usage"
            (eval-result-usage result)
            "artifacts"
            (coerce
             (mapcar
              #'artifact-reference-json
              references)
             'vector))))
    (when (eval-result-timings result)
      (cadr-ai::json-put
       record "timings"
       (eval-result-timings result)))
    (when (eval-result-errors result)
      (cadr-ai::json-put
       record "errors"
       (coerce
        (eval-result-errors result)
        'vector)))
    (when (plusp (hash-table-count metadata))
      (cadr-ai::json-put
       record "metadata" metadata))
    (let ((path
            (merge-pathnames
             "runs.jsonl" root)))
      (cadr-core:append-string-to-file
       path
       (format nil "~A~%"
               (cadr-ai::stringify-json record))
       :mode #o600
       :durability :flush))
    record))

(defun reporter-case-observation (case)
  (let* ((result
           (eval-reporter-case-result case))
         (iteration
           (parse-eval-harness-iteration-artifact
            (cadr-ai::json-get
             (eval-result-artifacts result)
             +eval-harness-iteration-artifact+))))
    (when iteration
      (let* ((usage
               (eval-result-usage result))
             (usage-metadata
               (and usage
                    (cadr-ai::json-get
                     usage "metadata")))
             (timings
               (eval-result-timings result))
             (score
               (reporter-finite-number
                (eval-reporter-case-score case)))
             (status
               (eval-reporter-case-status case))
             (outcome
               (cond
                 ((eval-result-errors result)
                  :errored)
                 (score :scored)
                 ((member status
                          '(:passed "passed")
                          :test #'equal)
                  :unscored)
                 ((member status
                          '(:failed "failed")
                          :test #'equal)
                  :errored)
                 ((symbolp status) status)
                 (t
                  (intern
                   (string-upcase
                    (princ-to-string status))
                   :keyword)))))
        (make-harness-observation
         :eval-set
         (cadr-ai::json-get
          iteration "evalSet")
         :group-key
         (cadr-ai::json-get
          iteration "groupKey")
         :test-name
         (eval-reporter-case-name case)
         :file
         (eval-reporter-case-file case)
         :harness
         (cadr-ai::json-get
          iteration "harness")
         :baseline
         (cadr-ai::json-get
          iteration "baseline")
         :candidates
         (coerce
          (cadr-ai::json-get
           iteration "candidates")
          'list)
         :repetition
         (cadr-ai::json-get
          iteration "repetition")
         :outcome outcome
         :score score
         :total-tokens
         (and usage
              (reporter-finite-number
               (cadr-ai::json-get
                usage "totalTokens")))
         :total-ms
         (and timings
              (reporter-finite-number
               (cadr-ai::json-get
                timings "totalMs")))
         :estimated-cost-usd
         (and usage-metadata
              (reporter-finite-number
               (cadr-ai::json-get
                usage-metadata
                "estimatedCostUsd"))))))))

(defun eval-reporter-record-case
    (reporter case)
  (unless
      (and
       (typep reporter
              'eval-harness-reporter)
       (typep case
              'eval-reporter-case)
       (typep
        (eval-reporter-case-result case)
        'eval-result))
    (artifact-type-error
     (list reporter case)
     '(cons eval-harness-reporter
       eval-reporter-case)))
  (when
      (eval-harness-reporter-artifact-directory
       reporter)
    (append-reporter-record
     case
     (eval-harness-reporter-artifact-directory
      reporter)))
  (let ((observation
          (reporter-case-observation case)))
    (when observation
      ;; append-at-end is the TS array-push transliteration
      ;; (O(n) copy per case). push is O(1); finish nreverses
      ;; so the exported list and the summary stay chronological.
      (push
       observation
       (eval-harness-reporter-observations
        reporter))))
  case)

(defun eval-reporter-finish
    (reporter reason)
  (unless
      (typep reporter
             'eval-harness-reporter)
    (artifact-type-error
     reporter 'eval-harness-reporter))
  (setf
   (eval-harness-reporter-observations
    reporter)
   (nreverse
    (eval-harness-reporter-observations
     reporter)))
  (let ((output
          (eval-harness-reporter-output
           reporter)))
    (if (eq reason :interrupted)
        (format
         output
         "~%Eval comparisons unavailable: test run interrupted.~%")
        (let ((formatted
                (format-harness-comparison-report
                 (summarize-harness-comparisons
                  (eval-harness-reporter-observations
                   reporter)))))
          (when (plusp (length formatted))
            (format output "~%~A~%"
                    formatted))))
    (finish-output output))
  reporter)
