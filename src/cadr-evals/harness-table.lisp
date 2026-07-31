(in-package #:cadr-evals)

(defparameter +eval-harness-iteration-artifact+
  "vitestEvalsHarnessIteration")

(defstruct (eval-harness
            (:constructor
                %make-eval-harness
                (&key name run-function)))
  (name "" :type string)
  (run-function
    (error "Eval harness run function is required")
    :type function))

(defstruct eval-harness-row
  harness
  (name "" :type string)
  (repetition 1 :type (integer 1 *)))

(defun make-eval-harness (&key name run)
  (unless
      (and (stringp name)
           (functionp run))
    (artifact-type-error
     (list name run)
     '(cons string function)))
  (%make-eval-harness
   :name name
   :run-function run))

(defun copy-json-object (source)
  (let ((copy
          (make-hash-table :test #'equal)))
    (when source
      (maphash
       (lambda (key value)
         (setf (gethash key copy)
               value))
       source))
    copy))

(defun run-eval-harness
    (harness input &optional artifacts)
  (unless (typep harness 'eval-harness)
    (artifact-type-error harness 'eval-harness))
  (let ((context-artifacts
          (copy-json-object artifacts)))
    (let ((result
            (funcall
             (eval-harness-run-function
              harness)
             input
             (lambda (name value)
               (setf
                (gethash name context-artifacts)
                value)))))
      (unless (typep result 'eval-result)
        (artifact-type-error result 'eval-result))
      (let ((merged
              (copy-json-object
               context-artifacts)))
        (maphash
         (lambda (name value)
           (setf (gethash name merged)
                 value))
         (or
          (eval-result-artifacts result)
          (make-hash-table :test #'equal)))
        (setf (eval-result-artifacts result)
              merged))
      result)))

(defun finite-json-number-p (value)
  (and
   (realp value)
   (or
    (not (floatp value))
    (and
     (not (sb-ext:float-infinity-p value))
     (not (sb-ext:float-nan-p value))))))

(defun validate-canonical-json
    (value ancestors)
  (cond
    ((or (eq value 'null)
         (eq value t)
         (null value)
         (stringp value)
         (finite-json-number-p value))
     value)
    ((and (numberp value)
          (not (finite-json-number-p value)))
     (artifact-type-error
      value '(and real
             (satisfies finite-json-number-p))))
    ((or (vectorp value)
         (hash-table-p value))
     (when (gethash value ancestors)
       (artifact-type-error
        value
        '(satisfies acyclic-json-value-p)))
     (setf (gethash value ancestors) t)
     (unwind-protect
          (cond
            ((vectorp value)
             (map nil
                  (lambda (item)
                    (validate-canonical-json
                     item ancestors))
                  value))
            (t
             (maphash
              (lambda (key item)
                (unless (stringp key)
                  (artifact-type-error
                   key 'string))
                (validate-canonical-json
                 item ancestors))
              value)))
       (remhash value ancestors))
     value)
    (t
     (artifact-type-error
      value
      '(or null boolean string
        real vector hash-table)))))

(defun canonical-json-text (value)
  (validate-canonical-json
   value
   (make-hash-table :test #'eq))
  (cadr-ai::stringify-json value))

(defun json-object-id (input)
  (when (hash-table-p input)
    (let ((id
            (cadr-ai::json-get input "id")))
      (when (stringp id)
        (let ((trimmed
                (string-trim
                 '(#\Space #\Tab
                   #\Newline #\Return)
                 id)))
          (and (plusp (length trimmed))
               trimmed))))))

(defun derive-eval-input-key (input)
  (or
   (json-object-id input)
   (sha256-hex
    (canonical-json-text input))))

(defun derive-eval-group-key
    (input repetition)
  (unless
      (and (integerp repetition)
           (plusp repetition))
    (artifact-type-error
     repetition '(integer 1 *)))
  (cadr-ai::stringify-json
   (vector
    (derive-eval-input-key input)
    repetition)))

(defun parse-eval-harness-iteration-artifact
    (value)
  (when (hash-table-p value)
    (let ((schema-version
            (cadr-ai::json-get
             value "schemaVersion"))
          (eval-set
            (cadr-ai::json-get value "evalSet"))
          (group-key
            (cadr-ai::json-get value "groupKey"))
          (harness
            (cadr-ai::json-get value "harness"))
          (baseline
            (cadr-ai::json-get value "baseline"))
          (candidates
            (cadr-ai::json-get
             value "candidates"))
          (repetition
            (cadr-ai::json-get
             value "repetition")))
      (when
          (and
           (numberp schema-version)
           (= 1 schema-version)
           (stringp eval-set)
           (stringp group-key)
           (stringp harness)
           (stringp baseline)
           (vectorp candidates)
           (every #'stringp candidates)
           (numberp repetition))
        value))))

(defun make-coding-agent-eval-harness
    (&key
       (name "cadr-coding-agent")
       provider model no-tools selector
       transform-system-prompt abort-p)
  (make-eval-harness
   :name name
   :run
   (lambda (input set-artifact)
     (let ((result
             (run-coding-agent-eval
              input
              :provider provider
              :model model
              :no-tools no-tools
              :selector selector
              :transform-system-prompt
              transform-system-prompt
              :abort-p abort-p)))
       (maphash
        set-artifact
        (eval-result-artifacts result))
       result))))

(defun validate-eval-harness-table-options
    (eval-set baseline candidates repetitions)
  (unless
      (and
       (stringp eval-set)
       (plusp
        (length
         (string-trim
          '(#\Space #\Tab
            #\Newline #\Return)
          eval-set))))
    (artifact-type-error
     eval-set '(and string
               (satisfies non-empty-string-p))))
  (unless (typep baseline 'eval-harness)
    (artifact-type-error baseline 'eval-harness))
  (unless
      (and candidates
           (every
            (lambda (candidate)
              (typep candidate
                     'eval-harness))
            candidates))
    (artifact-type-error
     candidates
     '(cons eval-harness list)))
  (let ((names
          (mapcar #'eval-harness-name
                  (cons baseline candidates))))
    (unless
        (= (length names)
           (length
            (remove-duplicates
             names :test #'string=)))
      (artifact-type-error
       names
       '(satisfies unique-string-list-p))))
  (unless
      (and (integerp repetitions)
           (plusp repetitions))
    (artifact-type-error
     repetitions '(integer 1 *))))

(defun wrap-eval-harness
    (harness eval-set baseline candidates
     repetition)
  (make-eval-harness
   :name
   (eval-harness-name harness)
   :run
   (lambda (input set-artifact)
     (let* ((artifact
              (cadr-ai::json-object
               "schemaVersion" 1
               "evalSet" eval-set
               "groupKey"
               (derive-eval-group-key
                input repetition)
               "harness"
               (eval-harness-name harness)
               "baseline"
               (eval-harness-name baseline)
               "candidates"
               (coerce
                (mapcar
                 #'eval-harness-name
                 candidates)
                'vector)
               "repetition" repetition))
            (context
              (make-hash-table
               :test #'equal)))
       (funcall
        set-artifact
        +eval-harness-iteration-artifact+
        artifact)
       (let ((result
               (funcall
                (eval-harness-run-function
                 harness)
                input
                (lambda (name value)
                  (setf (gethash name context)
                        value)))))
         (unless (typep result 'eval-result)
           (artifact-type-error result
                                'eval-result))
         (let ((merged
                 (copy-json-object context)))
           (maphash
            (lambda (name value)
              (setf (gethash name merged)
                    value))
            (or
             (eval-result-artifacts result)
             (make-hash-table
              :test #'equal)))
           (setf
            (gethash
             +eval-harness-iteration-artifact+
             merged)
            artifact
            (eval-result-artifacts result)
            merged))
         result)))))

(defun eval-harness-table
    (eval-set
     &key baseline candidate candidates
       (repetitions 1))
  (when (and candidate candidates)
    (artifact-type-error
     (list candidate candidates)
     '(or eval-harness
       (cons eval-harness list))))
  (let ((selected-candidates
          (if candidate
              (list candidate)
              candidates)))
    (validate-eval-harness-table-options
     eval-set baseline
     selected-candidates repetitions)
    (loop
      for repetition from 1 to repetitions
      append
      (loop
        for harness in
        (cons baseline selected-candidates)
        collect
        (make-eval-harness-row
         :harness
         (wrap-eval-harness
          harness eval-set
          baseline selected-candidates
          repetition)
         :name
         (eval-harness-name harness)
         :repetition repetition)))))
