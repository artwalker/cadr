(in-package #:cadr-evals/tests)

(in-suite cadr-evals-suite)

(defun make-test-eval-harness (name)
  (cadr-evals:make-eval-harness
   :name name
   :run
   (lambda (input set-artifact)
     (declare (ignore set-artifact))
     (cadr-evals::make-eval-result
      :output
      (cadr-ai::json-object
       "harness" name
       "inputId"
       (cadr-ai::json-get input "id"))
      :artifacts
      (make-hash-table :test #'equal)))))

(test eval-group-key-prefers-trimmed-id-and-canonicalizes-json
  (is (string=
       "[\"input-1\",2]"
       (cadr-evals:derive-eval-group-key
        (cadr-ai::json-object
         "id" " input-1 "
         "prompt" "hello")
        2)))
  (let ((left
          (cadr-ai::json-object
           "first" 1
           "second" (vector t "value")))
        (right
          (cadr-ai::json-object
           "second" (vector t "value")
           "first" 1)))
    (is (string=
         (cadr-evals:derive-eval-group-key left 1)
         (cadr-evals:derive-eval-group-key right 1)))
    (is (not
         (string=
          (cadr-evals:derive-eval-group-key left 1)
          (cadr-evals:derive-eval-group-key
           (cadr-ai::json-object
            "first" 2
            "second" (vector t "value"))
           1))))
    (is (not
         (string=
          (cadr-evals:derive-eval-group-key left 1)
          (cadr-evals:derive-eval-group-key left 2))))))

(test eval-group-key-rejects-non-json-circular-input
  (let ((circular (make-array 1)))
    (setf (aref circular 0) circular)
    (signals type-error
      (cadr-evals:derive-eval-group-key
       circular 1)))
  (signals type-error
    (cadr-evals:derive-eval-group-key
     (make-pathname :name "not-json")
     1)))

(test eval-harness-table-plans-and-attaches-iteration-metadata
  (let* ((rows
           (cadr-evals:eval-harness-table
            "local multi-harness eval"
            :baseline
            (make-test-eval-harness "withoutSkill")
            :candidates
            (list
             (make-test-eval-harness "withSkill"))
            :repetitions 2))
         (plans
           (mapcar
            (lambda (row)
              (list
               (cadr-evals:eval-harness-row-name row)
               (cadr-evals:eval-harness-row-repetition
                row)))
            rows)))
    (is (equal
         '(("withoutSkill" 1)
           ("withSkill" 1)
           ("withoutSkill" 2)
           ("withSkill" 2))
         plans))
    (dolist (row rows)
      (let* ((input
               (cadr-ai::json-object
                "id" "first"))
             (result
               (cadr-evals:run-eval-harness
                (cadr-evals:eval-harness-row-harness
                 row)
                input))
             (artifact
               (cadr-evals:parse-eval-harness-iteration-artifact
                (gethash
                 cadr-evals:+eval-harness-iteration-artifact+
                 (cadr-evals:eval-result-artifacts
                  result)))))
        (is (string=
             (cadr-evals:eval-harness-row-name row)
             (cadr-ai::json-get
              (cadr-evals:eval-result-output result)
              "harness")))
        (is (= 1
               (cadr-ai::json-get
                artifact "schemaVersion")))
        (is (string=
             "local multi-harness eval"
             (cadr-ai::json-get artifact "evalSet")))
        (is (string=
             (cadr-evals:derive-eval-group-key
              input
              (cadr-evals:eval-harness-row-repetition
               row))
             (cadr-ai::json-get artifact "groupKey")))
        (is (string=
             (cadr-evals:eval-harness-row-name row)
             (cadr-ai::json-get artifact "harness")))
        (is (string=
             "withoutSkill"
             (cadr-ai::json-get artifact "baseline")))
        (is (equalp
             #("withSkill")
             (cadr-ai::json-get artifact "candidates")))))))

(test eval-harness-table-validates-declarations
  (signals type-error
    (cadr-evals:eval-harness-table
     ""
     :baseline
     (make-test-eval-harness "base")
     :candidate
     (make-test-eval-harness "candidate")))
  (signals type-error
    (cadr-evals:eval-harness-table
     "set"
     :baseline
     (make-test-eval-harness "same")
     :candidate
     (make-test-eval-harness "same")))
  (signals type-error
    (cadr-evals:eval-harness-table
     "set"
     :baseline
     (make-test-eval-harness "base")
     :candidate
     (make-test-eval-harness "candidate")
     :repetitions 0)))

(test wrap-eval-harness-reuses-run-eval-harness-merge
  (let* ((inner
           (cadr-evals:make-eval-harness
            :name "inner"
            :run
            (lambda (input set-artifact)
              (declare (ignore input))
              (funcall set-artifact
                       "from-setter" "via-setter")
              (let ((result
                      (cadr-evals::make-eval-result
                       :output "ok"
                       :artifacts
                       (make-hash-table
                        :test #'equal))))
                (setf
                 (gethash
                  "from-result"
                  (cadr-evals:eval-result-artifacts
                   result))
                 "via-result")
                result))))
         (rows
           (cadr-evals:eval-harness-table
            "set"
            :baseline inner
            :candidate
            (make-test-eval-harness "other")))
         (result
           (cadr-evals:run-eval-harness
            (cadr-evals:eval-harness-row-harness
             (first rows))
            (cadr-ai::json-object "id" "x")))
         (artifacts
           (cadr-evals:eval-result-artifacts
            result)))
    (is (string=
         "via-setter"
         (gethash "from-setter" artifacts)))
    (is (string=
         "via-result"
         (gethash "from-result" artifacts)))
    (is (not
         (null
          (cadr-evals:parse-eval-harness-iteration-artifact
           (gethash
            cadr-evals:+eval-harness-iteration-artifact+
            artifacts)))))))
