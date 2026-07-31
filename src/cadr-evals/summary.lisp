(in-package #:cadr-evals)

(defstruct harness-observation
  (eval-set "" :type string)
  (group-key "" :type string)
  (test-name "" :type string)
  (file "" :type string)
  (harness "" :type string)
  (baseline "" :type string)
  (candidates nil :type list)
  (repetition 1 :type number)
  outcome
  score
  total-tokens
  total-ms
  estimated-cost-usd)

(defstruct paired-metric-summary
  (total-pairs 0 :type (integer 0 *))
  (eligible-pairs 0 :type (integer 0 *))
  baseline-mean
  candidate-mean
  mean-delta)

(defstruct correctness-lift-summary
  (total-pairs 0 :type (integer 0 *))
  (eligible-pairs 0 :type (integer 0 *))
  baseline-pass-rate
  candidate-pass-rate
  lift
  (baseline-wins 0 :type (integer 0 *))
  (candidate-wins 0 :type (integer 0 *))
  (ties 0 :type (integer 0 *)))

(defstruct harness-pair-comparison
  (baseline "" :type string)
  (candidate "" :type string)
  correctness
  total-tokens
  total-ms
  estimated-cost-usd)

(defstruct harness-comparison-diagnostic
  (eval-set "" :type string)
  (group-key "" :type string)
  (test-name "" :type string)
  (file "" :type string)
  (repetition 1 :type number)
  (harness "" :type string)
  reason)

(defstruct harness-eval-set-report
  (eval-set "" :type string)
  (comparisons nil :type list))

(defstruct harness-comparison-report
  (schema-version 1 :type (eql 1))
  (eval-sets nil :type list)
  (diagnostics nil :type list))

(defstruct observation-group
  (eval-set "" :type string)
  (group-key "" :type string)
  (test-name "" :type string)
  (file "" :type string)
  (repetition 1 :type number)
  (observations
    (make-hash-table :test #'equal)
    :type hash-table))

(defstruct eval-set-data
  (baseline "" :type string)
  (candidates nil :type list)
  (groups
    (make-hash-table :test #'equal)
    :type hash-table))

(defun hash-get-or-create
    (table key function)
  (multiple-value-bind
        (value present-p)
      (gethash key table)
    (if present-p
        value
        (setf
         (gethash key table)
         (funcall function)))))

(defun append-unique-string
    (items item)
  (if (member item items :test #'string=)
      items
      (append items (list item))))

(defun group-harness-observations
    (observations)
  (let ((sets
          (make-hash-table :test #'equal)))
    (dolist (observation observations)
      (unless
          (typep observation
                 'harness-observation)
        (artifact-type-error
         observation 'harness-observation))
      (let* ((set
               (hash-get-or-create
                sets
                (harness-observation-eval-set
                 observation)
                (lambda ()
                  (make-eval-set-data
                   :baseline
                   (harness-observation-baseline
                    observation)))))
             (group-key
               (list
                (harness-observation-file
                 observation)
                (harness-observation-test-name
                 observation)
                (harness-observation-group-key
                 observation)))
             (group
               (hash-get-or-create
                (eval-set-data-groups set)
                group-key
                (lambda ()
                  (make-observation-group
                   :eval-set
                   (harness-observation-eval-set
                    observation)
                   :group-key
                   (harness-observation-group-key
                    observation)
                   :test-name
                   (harness-observation-test-name
                    observation)
                   :file
                   (harness-observation-file
                    observation)
                   :repetition
                   (harness-observation-repetition
                    observation))))))
        (dolist
            (candidate
             (harness-observation-candidates
              observation))
          (setf
           (eval-set-data-candidates set)
           (append-unique-string
            (eval-set-data-candidates set)
            candidate)))
        (push
         observation
         (gethash
          (harness-observation-harness
           observation)
          (observation-group-observations
           group)))))
    sets))

(defun sorted-hash-values
    (table predicate)
  (sort
   (loop
     for value being the hash-values
     of table
     collect value)
   predicate))

(defun ordered-observation-groups (set)
  (sorted-hash-values
   (eval-set-data-groups set)
   (lambda (left right)
     (or
      (string<
       (observation-group-group-key left)
       (observation-group-group-key right))
      (and
       (string=
        (observation-group-group-key left)
        (observation-group-group-key right))
       (<
        (observation-group-repetition left)
        (observation-group-repetition right)))))))

(defun diagnostic-reason (observations)
  (cond
    ((null observations)
     :missing-observation)
    ((cdr observations)
     :duplicate-observation)
    ((eq
      :errored
      (harness-observation-outcome
       (first observations)))
     :harness-error)
    ((eq
      :unscored
      (harness-observation-outcome
       (first observations)))
     :missing-score)
    ((not
      (eq
       :scored
       (harness-observation-outcome
        (first observations))))
     :unscorable-outcome)
    (t nil)))

(defun collect-comparison-diagnostics
    (set groups)
  (let ((harnesses
          (cons
           (eval-set-data-baseline set)
           (eval-set-data-candidates set)))
        (diagnostics nil))
    (dolist (group groups)
      (dolist (harness harnesses)
        (let* ((observations
                 (gethash
                  harness
                  (observation-group-observations
                   group)))
               (reason
                 (diagnostic-reason
                  observations)))
          (when reason
            (push
             (make-harness-comparison-diagnostic
              :eval-set
              (observation-group-eval-set group)
              :group-key
              (observation-group-group-key group)
              :test-name
              (observation-group-test-name group)
              :file
              (observation-group-file group)
              :repetition
              (observation-group-repetition group)
              :harness harness
              :reason reason)
             diagnostics)))))
    (nreverse diagnostics)))

(defun pair-harness-observations
    (groups baseline candidate)
  (loop
    for group in groups
    for baseline-observations =
      (gethash
       baseline
       (observation-group-observations
        group))
    for candidate-observations =
      (gethash
       candidate
       (observation-group-observations
        group))
    when
    (and
     (= 1 (length baseline-observations))
     (= 1 (length candidate-observations)))
      collect
      (cons
       (first baseline-observations)
       (first candidate-observations))))

(defun scored-observation-p (observation)
  (eq :scored
      (harness-observation-outcome
       observation)))

(defun finite-observation-number-p (value)
  (and
   (numberp value)
   (realp value)
   (or
    (not (floatp value))
    (and
     (not (sb-ext:float-infinity-p value))
     (not (sb-ext:float-nan-p value))))))

(defun arithmetic-mean (values)
  (and
   values
   (/ (reduce #'+ values)
      (length values))))

(defun summarize-paired-metric
    (pairs selector total-pairs)
  (let ((baseline-values nil)
        (candidate-values nil))
    (dolist (pair pairs)
      (let ((baseline (car pair))
            (candidate (cdr pair)))
        (when
            (and
             (scored-observation-p baseline)
             (scored-observation-p candidate))
          (let ((baseline-value
                  (funcall selector baseline))
                (candidate-value
                  (funcall selector candidate)))
            (when
                (and
                 (finite-observation-number-p
                  baseline-value)
                 (finite-observation-number-p
                  candidate-value))
              (push baseline-value
                    baseline-values)
              (push candidate-value
                    candidate-values))))))
    (let ((baseline-mean
            (arithmetic-mean
             baseline-values))
          (candidate-mean
            (arithmetic-mean
             candidate-values)))
      (make-paired-metric-summary
       :total-pairs total-pairs
       :eligible-pairs
       (length baseline-values)
       :baseline-mean baseline-mean
       :candidate-mean candidate-mean
       :mean-delta
       (and baseline-mean
            candidate-mean
            (- candidate-mean
               baseline-mean))))))

(defun summarize-paired-correctness
    (pairs total-pairs)
  (let ((eligible-pairs 0)
        (baseline-passes 0)
        (candidate-passes 0)
        (baseline-wins 0)
        (candidate-wins 0)
        (ties 0))
    (dolist (pair pairs)
      (let ((baseline (car pair))
            (candidate (cdr pair)))
        (when
            (and
             (scored-observation-p baseline)
             (scored-observation-p candidate))
          (incf eligible-pairs)
          (let ((baseline-passed
                  (>=
                   (harness-observation-score
                    baseline)
                   1))
                (candidate-passed
                  (>=
                   (harness-observation-score
                    candidate)
                   1)))
            (when baseline-passed
              (incf baseline-passes))
            (when candidate-passed
              (incf candidate-passes))
            (cond
              ((eq baseline-passed
                   candidate-passed)
               (incf ties))
              (baseline-passed
               (incf baseline-wins))
              (t
               (incf candidate-wins)))))))
    (let ((baseline-rate
            (and
             (plusp eligible-pairs)
             (/ baseline-passes
                eligible-pairs)))
          (candidate-rate
            (and
             (plusp eligible-pairs)
             (/ candidate-passes
                eligible-pairs))))
      (make-correctness-lift-summary
       :total-pairs total-pairs
       :eligible-pairs eligible-pairs
       :baseline-pass-rate baseline-rate
       :candidate-pass-rate candidate-rate
       :lift
       (and baseline-rate
            candidate-rate
            (- candidate-rate
               baseline-rate))
       :baseline-wins baseline-wins
       :candidate-wins candidate-wins
       :ties ties))))

(defun compare-eval-harnesses
    (baseline candidate groups)
  (let ((pairs
          (pair-harness-observations
           groups baseline candidate))
        (total-pairs
          (length groups)))
    (make-harness-pair-comparison
     :baseline baseline
     :candidate candidate
     :correctness
     (summarize-paired-correctness
      pairs total-pairs)
     :total-tokens
     (summarize-paired-metric
      pairs
      #'harness-observation-total-tokens
      total-pairs)
     :total-ms
     (summarize-paired-metric
      pairs
      #'harness-observation-total-ms
      total-pairs)
     :estimated-cost-usd
     (summarize-paired-metric
      pairs
      #'harness-observation-estimated-cost-usd
      total-pairs))))

(defun diagnostic-less-p (left right)
  (let ((left-fields
          (list
           (harness-comparison-diagnostic-eval-set
            left)
           (harness-comparison-diagnostic-file left)
           (harness-comparison-diagnostic-group-key
            left)))
        (right-fields
          (list
           (harness-comparison-diagnostic-eval-set
            right)
           (harness-comparison-diagnostic-file
            right)
           (harness-comparison-diagnostic-group-key
            right))))
    (loop
      for left-field in left-fields
      for right-field in right-fields
      when (string< left-field right-field)
        return t
      when (string> left-field right-field)
        return nil
      finally
      (return
        (or
         (<
          (harness-comparison-diagnostic-repetition
           left)
          (harness-comparison-diagnostic-repetition
           right))
         (and
          (=
           (harness-comparison-diagnostic-repetition
            left)
           (harness-comparison-diagnostic-repetition
            right))
          (string<
           (harness-comparison-diagnostic-harness
            left)
           (harness-comparison-diagnostic-harness
            right))))))))

(defun summarize-harness-comparisons
    (observations)
  (let ((sets
          (group-harness-observations
           observations))
        (reports nil)
        (diagnostics nil))
    (dolist
        (eval-set
         (sort
          (loop
            for key being the hash-keys
            of sets
            collect key)
          #'string<))
      (let* ((set
               (gethash eval-set sets))
             (groups
               (ordered-observation-groups
                set)))
        (push
         (make-harness-eval-set-report
          :eval-set eval-set
          :comparisons
          (mapcar
           (lambda (candidate)
             (compare-eval-harnesses
              (eval-set-data-baseline set)
              candidate groups))
           (eval-set-data-candidates set)))
         reports)
        (setf diagnostics
              (nconc
               diagnostics
               (collect-comparison-diagnostics
                set groups)))))
    (make-harness-comparison-report
     :eval-sets (nreverse reports)
     :diagnostics
     (sort diagnostics
           #'diagnostic-less-p))))

(defun format-summary-percentage (value)
  (if (null value)
      "unavailable"
      (format nil "~,1F%"
              (* 100d0 value))))

(defun format-summary-signed
    (value fraction-digits)
  (declare (ignore fraction-digits))
  (format nil "~A~,1F"
          (if (minusp value)
              "-"
              "+")
          (abs value)))

(defun format-summary-coverage
    (eligible total)
  (format nil "(~D/~D pairs)"
          eligible total))

(defun format-summary-line (label value)
  (format nil "    ~9@A  ~A"
          label value))

(defun format-summary-metric
    (label metric value-formatter
     delta-formatter comparison-pairs)
  (let ((coverage
          (if
              (or
               (zerop
                (paired-metric-summary-eligible-pairs
                 metric))
               (=
                (paired-metric-summary-eligible-pairs
                 metric)
                comparison-pairs))
              ""
              (format
               nil " ~A"
               (format-summary-coverage
                (paired-metric-summary-eligible-pairs
                 metric)
                (paired-metric-summary-total-pairs
                 metric))))))
    (if
        (or
         (null
          (paired-metric-summary-baseline-mean
           metric))
         (null
          (paired-metric-summary-candidate-mean
           metric))
         (null
          (paired-metric-summary-mean-delta
           metric)))
        (format-summary-line
         label
         (format nil "unavailable~A"
                 coverage))
        (format-summary-line
         label
         (format
          nil "~A (candidate ~A, baseline ~A)~A"
          (funcall
           delta-formatter
           (paired-metric-summary-mean-delta
            metric))
          (funcall
           value-formatter
           (paired-metric-summary-candidate-mean
            metric))
          (funcall
           value-formatter
           (paired-metric-summary-baseline-mean
            metric))
          coverage)))))

(defun format-harness-comparison-report (report)
  (unless
      (typep report
             'harness-comparison-report)
    (artifact-type-error
     report 'harness-comparison-report))
  (when
      (every
       (lambda (set)
         (null
          (harness-eval-set-report-comparisons
           set)))
       (harness-comparison-report-eval-sets
        report))
    (return-from
        format-harness-comparison-report
      ""))
  (with-output-to-string (stream)
    (write-string "Eval Comparisons"
                  stream)
    (dolist
        (set
         (harness-comparison-report-eval-sets
          report))
      (format stream "~%  ~A"
              (harness-eval-set-report-eval-set
               set))
      (loop
        for comparison in
        (harness-eval-set-report-comparisons
         set)
        for index from 0
        do
        (when (plusp index)
          (terpri stream))
        (let ((correctness
                (harness-pair-comparison-correctness
                 comparison)))
          (format stream "~%~A"
                  (format-summary-line
                   "Baseline"
                   (harness-pair-comparison-baseline
                    comparison)))
          (format stream "~%~A"
                  (format-summary-line
                   "Candidate"
                   (format
                    nil "~A ~A"
                    (harness-pair-comparison-candidate
                     comparison)
                    (format-summary-coverage
                     (correctness-lift-summary-eligible-pairs
                      correctness)
                     (correctness-lift-summary-total-pairs
                      correctness)))))
          (format stream "~%~A"
                  (format-summary-line
                   "Pass rate"
                   (if
                       (null
                        (correctness-lift-summary-lift
                         correctness))
                       "unavailable"
                       (format
                        nil "~A pp (candidate ~A, baseline ~A)"
                        (format-summary-signed
                         (*
                          100d0
                          (correctness-lift-summary-lift
                           correctness))
                         1)
                        (format-summary-percentage
                         (correctness-lift-summary-candidate-pass-rate
                          correctness))
                        (format-summary-percentage
                         (correctness-lift-summary-baseline-pass-rate
                          correctness))))))
          (format stream "~%~A"
                  (format-summary-metric
                   "Tokens"
                   (harness-pair-comparison-total-tokens
                    comparison)
                   (lambda (value)
                     (format nil "~,1F"
                             value))
                   (lambda (value)
                     (format-summary-signed
                      value 1))
                   (correctness-lift-summary-eligible-pairs
                    correctness)))
          (format stream "~%~A"
                  (format-summary-metric
                   "Latency"
                   (harness-pair-comparison-total-ms
                    comparison)
                   (lambda (value)
                     (format nil "~,1Fms"
                             value))
                   (lambda (value)
                     (format nil "~Ams"
                             (format-summary-signed
                              value 1)))
                   (correctness-lift-summary-eligible-pairs
                    correctness)))
          (format stream "~%~A"
                  (format-summary-metric
                   "Est. cost"
                   (harness-pair-comparison-estimated-cost-usd
                    comparison)
                   (lambda (value)
                     (format nil "$~,4F"
                             value))
                   (lambda (value)
                     (format
                      nil "~A$~,4F"
                      (if (minusp value)
                          "-"
                          "+")
                      (abs value)))
                   (correctness-lift-summary-eligible-pairs
                    correctness))))))
    (when
        (harness-comparison-report-diagnostics
         report)
      (write-string
       "
  Incomplete observations"
       stream)
      (dolist
          (diagnostic
           (harness-comparison-report-diagnostics
            report))
        (format
         stream
         "~%    ~A: ~A/~A repetition ~A, harness ~A"
         (string-downcase
          (symbol-name
           (harness-comparison-diagnostic-reason
            diagnostic)))
         (harness-comparison-diagnostic-file
          diagnostic)
         (harness-comparison-diagnostic-test-name
          diagnostic)
         (harness-comparison-diagnostic-repetition
          diagnostic)
         (harness-comparison-diagnostic-harness
          diagnostic))))))
