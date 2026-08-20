(in-package #:cadr-agent)

(define-condition native-schema-error (error)
  ((json-pointer
    :initarg :json-pointer
    :initform ""
    :reader native-schema-error-json-pointer)
   (reason
    :initarg :reason
    :reader native-schema-error-reason))
  (:report
   (lambda (condition stream)
     (format stream "~A at ~A"
             (native-schema-error-reason condition)
             (let ((pointer
                     (native-schema-error-json-pointer condition)))
               (if (zerop (length pointer)) "/" pointer))))))

(defmacro with-present ((value present-p object key) &body body)
  ;; Baseline packages/ai/src/utils/validation.ts: a key is present
  ;; when it is not undefined. One owner of gethash's two values;
  ;; pointer/reason text stays at the call site.
  `(multiple-value-bind (,value ,present-p)
       (gethash ,key ,object)
     ,@body))

(defmacro when-present ((value object key) &body body)
  `(with-present (,value present-p ,object ,key)
     (when present-p
       ,@body)))

(defun schema-fail (pointer format-control &rest arguments)
  (error
   'native-schema-error
   :json-pointer pointer
   :reason (apply #'format nil format-control arguments)))

(defun escape-json-pointer-segment (value)
  (with-output-to-string (stream)
    (loop for character across (princ-to-string value)
          do
          (case character
            (#\~ (write-string "~0" stream))
            (#\/ (write-string "~1" stream))
            (otherwise (write-char character stream))))))

(defun schema-pointer (base segment)
  (format nil "~A/~A" base
          (escape-json-pointer-segment segment)))

(defun unescape-json-pointer-segment (value)
  (with-output-to-string (stream)
    (loop with index = 0
          while (< index (length value))
          for character = (char value index)
          do
          (if (and (char= character #\~)
                   (< (1+ index) (length value)))
              (let ((escaped (char value (1+ index))))
                (case escaped
                  (#\0 (write-char #\~ stream))
                  (#\1 (write-char #\/ stream))
                  (otherwise
                   (write-char character stream)
                   (write-char escaped stream)))
                (incf index 2))
              (progn
                (write-char character stream)
                (incf index))))))

(defun resolve-local-schema-reference (root reference pointer)
  (unless (and (stringp reference)
               (or (string= reference "#")
                   (and (> (length reference) 1)
                        (string= reference "#/"
                                 :end1 2 :end2 2))))
    (schema-fail pointer
                 "Only local JSON Schema references are supported, got ~S"
                 reference))
  (if (string= reference "#")
      root
      (loop with current = root
            for raw in
            (uiop:split-string
             (subseq reference 2)
             :separator '(#\/))
            for segment = (unescape-json-pointer-segment raw)
            do
            (unless (hash-table-p current)
              (schema-fail pointer
                           "Reference ~S does not resolve to a schema"
                           reference))
            (with-present (next present-p current segment)
              (unless present-p
                (schema-fail pointer
                             "Reference ~S does not resolve to a schema"
                             reference))
              (setf current next))
            finally
            (unless (hash-table-p current)
              (schema-fail pointer
                           "Reference ~S does not resolve to a schema"
                           reference))
            (return current))))

(defparameter +json-schema-types+
  '("null" "boolean" "object" "array"
    "number" "integer" "string"))

(defun valid-schema-type-p (value)
  (and (stringp value)
       (member value +json-schema-types+ :test #'string=)))

(defun schema-array-p (value)
  (vectorp value))

(defun validate-json-schema-definition (schema)
  (setf schema (cadr-ai::json-ensure-hash-table schema))
  (unless (hash-table-p schema)
    (schema-fail "" "A tool schema must be a JSON object"))
  (labels
      ((validate-type (value pointer)
         (cond
           ((valid-schema-type-p value))
           ((and (schema-array-p value)
                 (plusp (length value))
                 (every #'valid-schema-type-p value)
                 (= (length value)
                    (length
                     (remove-duplicates
                      (coerce value 'list)
                      :test #'string=)))))
           (t
            (schema-fail
             pointer
             "type must be a valid type name or a non-empty array of unique type names"))))
       (validate-nonnegative-integer (node key pointer)
         (with-present (value present-p node key)
           (when (and present-p
                      (not (and (integerp value)
                                (>= value 0))))
             (schema-fail
              (schema-pointer pointer key)
              "~A must be a non-negative integer"
              key))))
       (walk-schema-array (value pointer)
         (unless (and (schema-array-p value)
                      (plusp (length value)))
           (schema-fail pointer
                        "Schema composition must be a non-empty array"))
         (loop for item across value
               for index from 0
               do (walk item (schema-pointer pointer index))))
       (walk-schema-map (value pointer)
         (unless (hash-table-p value)
           (schema-fail pointer "Expected a JSON object"))
         (maphash
          (lambda (key item)
            (unless (stringp key)
              (schema-fail pointer
                           "Schema object keys must be strings"))
            (walk item (schema-pointer pointer key)))
          value))
       (walk (node pointer)
         (unless (hash-table-p node)
           (schema-fail pointer "Expected a JSON Schema object"))
         (with-present (type present-p node "type")
           (when present-p
             (validate-type type
                            (schema-pointer pointer "type"))))
         (dolist (key '("minLength" "maxLength"
                        "minItems" "maxItems"
                        "minProperties" "maxProperties"))
           (validate-nonnegative-integer node key pointer))
         (dolist (key '("minimum" "maximum"
                        "exclusiveMinimum" "exclusiveMaximum"
                        "multipleOf"))
           (with-present (value present-p node key)
             (when (and present-p
                        (not (realp value)))
               (schema-fail
                (schema-pointer pointer key)
                "~A must be a number" key))
             (when (and present-p
                        (string= key "multipleOf")
                        (<= value 0))
               (schema-fail
                (schema-pointer pointer key)
                "multipleOf must be greater than zero"))))
         (with-present (required present-p node "required")
           (when present-p
             (unless (and (schema-array-p required)
                          (every #'stringp required)
                          (= (length required)
                             (length
                              (remove-duplicates
                               (coerce required 'list)
                               :test #'string=))))
               (schema-fail
                (schema-pointer pointer "required")
                "required must be an array of unique strings"))))
         (with-present (enum present-p node "enum")
           (when (and present-p
                      (not (and (schema-array-p enum)
                                (plusp (length enum)))))
             (schema-fail
              (schema-pointer pointer "enum")
              "enum must be a non-empty array")))
         (with-present (pattern present-p node "pattern")
           (when present-p
             (unless (stringp pattern)
               (schema-fail
                (schema-pointer pointer "pattern")
                "pattern must be a string"))
             (handler-case
                 (cl-ppcre:create-scanner pattern)
               (error (condition)
                 (schema-fail
                  (schema-pointer pointer "pattern")
                  "Invalid regular expression: ~A"
                  condition)))))
         (dolist (key '("properties" "patternProperties"
                        "$defs" "definitions"
                        "dependentSchemas"))
           (with-present (value present-p node key)
             (when present-p
               (walk-schema-map
                value (schema-pointer pointer key)))))
         (dolist (key '("additionalProperties"
                        "additionalItems"
                        "contains"
                        "not"
                        "if"
                        "then"
                        "else"
                        "propertyNames"))
           (with-present (value present-p node key)
             (when (and present-p
                        (not (or (eq value t)
                                 (null value))))
               (walk value (schema-pointer pointer key)))))
         (with-present (items present-p node "items")
           (when present-p
             (cond
               ((hash-table-p items)
                (walk items (schema-pointer pointer "items")))
               ((schema-array-p items)
                (loop for item across items
                      for index from 0
                      do
                      (walk item
                            (schema-pointer
                             (schema-pointer pointer "items")
                             index))))
               (t
                (schema-fail
                 (schema-pointer pointer "items")
                 "items must be a schema or an array of schemas")))))
         (dolist (key '("allOf" "anyOf" "oneOf"))
           (with-present (value present-p node key)
             (when present-p
               (walk-schema-array
                value (schema-pointer pointer key)))))
         (with-present (dependencies present-p node "dependentRequired")
           (when present-p
             (unless (hash-table-p dependencies)
               (schema-fail
                (schema-pointer pointer "dependentRequired")
                "dependentRequired must be an object"))
             (maphash
              (lambda (key value)
                (unless
                    (and (stringp key)
                         (schema-array-p value)
                         (every #'stringp value)
                         (= (length value)
                            (length
                             (remove-duplicates
                              (coerce value 'list)
                              :test #'string=))))
                  (schema-fail
                   (schema-pointer
                    (schema-pointer pointer "dependentRequired")
                    key)
                   "Dependency must be an array of unique strings")))
              dependencies)))
         (with-present (reference present-p node "$ref")
           (when present-p
             (resolve-local-schema-reference
              schema reference
              (schema-pointer pointer "$ref"))))))
    (walk schema ""))
  schema)

(defun json-schema-value-equal-p (left right)
  (cond
    ((and (hash-table-p left) (hash-table-p right))
     (and
      (= (hash-table-count left)
         (hash-table-count right))
      (loop for key being the hash-keys of left
            using (hash-value value)
            always
            (with-present (other present-p right key)
              (and present-p
                   (json-schema-value-equal-p
                    value other))))))
    ((and (vectorp left) (vectorp right))
     (and (= (length left) (length right))
          (loop for left-item across left
                for right-item across right
                always
                (json-schema-value-equal-p
                 left-item right-item))))
    ((and (realp left) (realp right))
     (= left right))
    ((and (stringp left) (stringp right))
     (string= left right))
    (t (eq left right))))

(defun json-schema-type-match-p (value type)
  (cond
    ((string= type "null") (eq value 'null))
    ((string= type "boolean")
     (or (eq value t) (null value)))
    ((string= type "object") (hash-table-p value))
    ((string= type "array") (vectorp value))
    ((string= type "number") (realp value))
    ((string= type "integer") (integerp value))
    ((string= type "string") (stringp value))
    (t nil)))

(defun validate-json-schema-instance
    (schema value &key (root schema))
  (setf schema (cadr-ai::json-ensure-hash-table schema)
        value (cadr-ai::json-ensure-hash-table value)
        root (cadr-ai::json-ensure-hash-table root))
  (validate-json-schema-definition root)
  (labels
      ((matches-p (candidate-schema candidate active)
         (handler-case
             (progn
               (walk candidate-schema candidate "" active)
               t)
           (native-schema-error () nil)))
       (walk (node candidate pointer active)
         (when (member (cons node candidate)
                       active
                       :test
                       (lambda (left right)
                         (and (eq (car left) (car right))
                              (eq (cdr left) (cdr right)))))
           (return-from walk candidate))
         (let ((next-active
                 (acons node candidate active)))
           (with-present (reference present-p node "$ref")
             (when present-p
               (walk
                (resolve-local-schema-reference
                 root reference
                 (schema-pointer pointer "$ref"))
                candidate pointer next-active)))
           (with-present (type present-p node "type")
             (when
                 (and present-p
                      (if (stringp type)
                          (not
                           (json-schema-type-match-p
                            candidate type))
                          (notany
                           (lambda (item)
                             (json-schema-type-match-p
                              candidate item))
                           (coerce type 'list))))
               (schema-fail pointer
                            "Expected type ~S" type)))
           (with-present (expected present-p node "const")
             (when (and present-p
                        (not
                         (json-schema-value-equal-p
                          candidate expected)))
               (schema-fail pointer
                            "Value does not match const")))
           (with-present (choices present-p node "enum")
             (when
                 (and present-p
                      (notany
                       (lambda (choice)
                         (json-schema-value-equal-p
                          candidate choice))
                       (coerce choices 'list)))
               (schema-fail pointer
                            "Value is not in enum")))
           (dolist (key '("allOf"))
             (with-present (schemas present-p node key)
               (when present-p
                 (loop for item across schemas
                       do (walk item candidate
                                pointer next-active)))))
           (with-present (schemas present-p node "anyOf")
             (when (and present-p
                        (notany
                         (lambda (item)
                           (matches-p item candidate
                                      next-active))
                         (coerce schemas 'list)))
               (schema-fail pointer
                            "Value does not match anyOf")))
           (with-present (schemas present-p node "oneOf")
             (when
                 (and present-p
                      (/= 1
                          (count-if
                           (lambda (item)
                             (matches-p item candidate
                                        next-active))
                           (coerce schemas 'list))))
               (schema-fail pointer
                            "Value does not match exactly one oneOf schema")))
           (with-present (not-schema present-p node "not")
             (when (and present-p
                        (matches-p not-schema candidate
                                   next-active))
               (schema-fail pointer
                            "Value matches forbidden schema")))
           (with-present (if-schema present-p node "if")
             (when present-p
               (let ((branch
                       (if
                           (matches-p if-schema candidate
                                      next-active)
                           "then"
                           "else")))
                 (with-present (branch-schema branch-present-p node branch)
                   (when branch-present-p
                     (walk branch-schema candidate
                           pointer next-active))))))
           (when (hash-table-p candidate)
             (validate-object node candidate
                              pointer next-active))
           (when (vectorp candidate)
             (validate-array node candidate
                             pointer next-active))
           (when (stringp candidate)
             (validate-string node candidate pointer))
           (when (realp candidate)
             (validate-number node candidate pointer)))
         candidate)
       (validate-object (node object pointer active)
         (with-present (minimum present-p node "minProperties")
           (when (and present-p
                      (< (hash-table-count object) minimum))
             (schema-fail pointer
                          "Object has fewer than ~D properties"
                          minimum)))
         (with-present (maximum present-p node "maxProperties")
           (when (and present-p
                      (> (hash-table-count object) maximum))
             (schema-fail pointer
                          "Object has more than ~D properties"
                          maximum)))
         (with-present (required present-p node "required")
           (when present-p
             (loop for key across required
                   unless (nth-value 1 (gethash key object))
                     do
                     (schema-fail pointer
                                  "Missing required property ~S"
                                  key))))
         (let ((properties
                 (gethash "properties" node))
               (patterns
                 (gethash "patternProperties" node)))
           (when properties
             (maphash
              (lambda (key property-schema)
                (with-present (item present-p object key)
                  (when present-p
                    (walk property-schema item
                          (schema-pointer pointer key)
                          active))))
              properties))
           (maphash
            (lambda (key item)
              (let ((matched-p
                      (and properties
                           (nth-value 1
                                      (gethash key properties)))))
                (when patterns
                  (maphash
                   (lambda (pattern pattern-schema)
                     (when (cl-ppcre:scan pattern key)
                       (setf matched-p t)
                       (walk pattern-schema item
                             (schema-pointer pointer key)
                             active)))
                   patterns))
                (unless matched-p
                  (with-present (additional additional-present-p node "additionalProperties")
                    (when additional-present-p
                      (cond
                        ((null additional)
                         (schema-fail
                          (schema-pointer pointer key)
                          "Additional property is not allowed"))
                        ((hash-table-p additional)
                         (walk additional item
                               (schema-pointer pointer key)
                               active))))))))
            object))
         (with-present (dependencies present-p node "dependentRequired")
           (when present-p
             (maphash
              (lambda (key required)
                (when (nth-value 1 (gethash key object))
                  (loop for dependency across required
                        unless
                        (nth-value 1
                                   (gethash dependency object))
                          do
                          (schema-fail
                           pointer
                           "Property ~S requires property ~S"
                           key dependency))))
              dependencies)))
         (with-present (dependencies present-p node "dependentSchemas")
           (when present-p
             (maphash
              (lambda (key dependency-schema)
                (when (nth-value 1 (gethash key object))
                  (walk dependency-schema object
                        pointer active)))
              dependencies)))
         (with-present (property-schema present-p node "propertyNames")
           (when present-p
             (maphash
              (lambda (key item)
                (declare (ignore item))
                (walk property-schema key
                      (schema-pointer pointer key)
                      active))
              object))))
       (validate-array (node array pointer active)
         (with-present (minimum present-p node "minItems")
           (when (and present-p
                      (< (length array) minimum))
             (schema-fail pointer
                          "Array has fewer than ~D items"
                          minimum)))
         (with-present (maximum present-p node "maxItems")
           (when (and present-p
                      (> (length array) maximum))
             (schema-fail pointer
                          "Array has more than ~D items"
                          maximum)))
         (with-present (unique present-p node "uniqueItems")
           (when (and present-p unique)
             (loop for index below (length array)
                   do
                   (loop for other from (1+ index)
                         below (length array)
                         when
                         (json-schema-value-equal-p
                          (aref array index)
                          (aref array other))
                           do
                           (schema-fail
                            (schema-pointer pointer other)
                            "Array items must be unique")))))
         (with-present (items present-p node "items")
           (when present-p
             (cond
               ((hash-table-p items)
                (loop for item across array
                      for index from 0
                      do (walk items
                               item
                               (schema-pointer pointer index)
                               active)))
               ((vectorp items)
                (loop for item across array
                      for index from 0
                      do
                      (if (< index (length items))
                          (walk (aref items index)
                                item
                                (schema-pointer pointer index)
                                active)
                          (with-present (additional additional-present-p node "additionalItems")
                            (when additional-present-p
                              (cond
                                ((null additional)
                                 (schema-fail
                                  (schema-pointer pointer index)
                                  "Additional array item is not allowed"))
                                ((hash-table-p additional)
                                 (walk additional item
                                       (schema-pointer pointer index)
                                       active)))))))))))
         (with-present (contains present-p node "contains")
           (when (and present-p
                      (notany
                       (lambda (item)
                         (matches-p contains item active))
                       (coerce array 'list)))
             (schema-fail pointer
                          "Array does not contain a matching item"))))
       (validate-string (node string pointer)
         (with-present (minimum present-p node "minLength")
           (when (and present-p
                      (< (length string) minimum))
             (schema-fail pointer
                          "String is shorter than ~D characters"
                          minimum)))
         (with-present (maximum present-p node "maxLength")
           (when (and present-p
                      (> (length string) maximum))
             (schema-fail pointer
                          "String is longer than ~D characters"
                          maximum)))
         (with-present (pattern present-p node "pattern")
           (when (and present-p
                      (not (cl-ppcre:scan pattern string)))
             (schema-fail pointer
                          "String does not match pattern ~S"
                          pattern))))
       (validate-number (node number pointer)
         (dolist (entry
                  `(("minimum" ,#'<)
                    ("maximum" ,#'>)
                    ("exclusiveMinimum" ,#'<=)
                    ("exclusiveMaximum" ,#'>=)))
           (destructuring-bind (key predicate) entry
             (with-present (limit present-p node key)
               (when (and present-p
                          (funcall predicate number limit))
                 (schema-fail pointer
                              "Number violates ~A ~A"
                              key limit)))))
         (with-present (divisor present-p node "multipleOf")
           (when present-p
             (let* ((quotient (/ number divisor))
                    (distance
                      (abs (- quotient
                              (round quotient)))))
               (when (> distance 1d-10)
                 (schema-fail pointer
                              "Number is not a multiple of ~A"
                              divisor)))))))
    (walk schema value "" nil))
  value)

(defun schema-coercion-types (schema)
  (with-present (type present-p schema "type")
    (cond
      ((not present-p) nil)
      ((stringp type) (list type))
      ((vectorp type) (coerce type 'list))
      (t nil))))

(defun coerce-json-number-string (value integer-only-p)
  (let ((trimmed
          (string-trim '(#\Space #\Tab #\Return #\Newline)
                       value)))
    (when (and (plusp (length trimmed))
               (cadr-ai::valid-json-number-token-p trimmed))
      (let ((number
              (cadr-ai::parse-json-number-token trimmed)))
        (when (or (not integer-only-p)
                  (integerp number))
          number)))))

(defun coerce-json-schema-primitive (value type failure)
  (cond
    ((string= type "string")
     (cond
       ((eq value 'null) "")
       ((or (realp value) (eq value t) (null value))
        (cadr-ai::stringify-json value))
       (t failure)))
    ((string= type "number")
     (cond
       ((eq value 'null) 0)
       ((stringp value)
        (or (coerce-json-number-string value nil) failure))
       ((eq value t) 1)
       ((null value) 0)
       (t failure)))
    ((string= type "integer")
     (cond
       ((eq value 'null) 0)
       ((stringp value)
        (or (coerce-json-number-string value t) failure))
       ((eq value t) 1)
       ((null value) 0)
       (t failure)))
    ((string= type "boolean")
     (cond
       ((eq value 'null) nil)
       ((and (stringp value) (string= value "true")) t)
       ((and (stringp value) (string= value "false")) nil)
       ((and (realp value) (= value 1)) t)
       ((and (realp value) (= value 0)) nil)
       (t failure)))
    ((string= type "null")
     (if (or (and (stringp value) (zerop (length value)))
             (and (realp value) (zerop value))
             (null value))
         'null
         failure))
    (t failure)))

(defun coerce-json-schema-instance (schema value &key (root schema))
  "Apply the baseline tool-argument primitive conversions in place."
  (setf schema (cadr-ai::json-ensure-hash-table schema)
        value (cadr-ai::json-ensure-hash-table value)
        root (cadr-ai::json-ensure-hash-table root))
  (let ((failure (gensym "SCHEMA-COERCION-FAILURE")))
    (labels
        ((coerce-type (node candidate)
           (if (some (lambda (type)
                       (json-schema-type-match-p candidate type))
                     (schema-coercion-types node))
               candidate
               (loop for type in (schema-coercion-types node)
                     for converted =
                       (coerce-json-schema-primitive
                        candidate type failure)
                     when (and (not (eq converted failure))
                               (json-schema-type-match-p converted type))
                       return converted
                     finally (return candidate))))
         (walk (node candidate)
           (with-present (reference present-p node "$ref")
             (when present-p
               (setf candidate
                     (walk
                      (resolve-local-schema-reference root reference "")
                      candidate))))
           (setf candidate (coerce-type node candidate))
           (when (hash-table-p candidate)
             (let ((properties (gethash "properties" node))
                   (additional (gethash "additionalProperties" node)))
               (when properties
                 (maphash
                  (lambda (key property-schema)
                    (with-present (item present-p candidate key)
                      (when present-p
                        (setf (gethash key candidate)
                              (walk property-schema item)))))
                  properties))
               (when (hash-table-p additional)
                 (maphash
                  (lambda (key item)
                    (unless (and properties
                                 (nth-value 1 (gethash key properties)))
                      (setf (gethash key candidate)
                            (walk additional item))))
                  candidate))))
           (when (vectorp candidate)
             (with-present (items present-p node "items")
               (when present-p
                 (cond
                   ((hash-table-p items)
                    (loop for index below (length candidate)
                          do (setf (aref candidate index)
                                   (walk items (aref candidate index)))))
                   ((vectorp items)
                    (loop for index below (min (length candidate)
                                               (length items))
                          do (setf (aref candidate index)
                                   (walk (aref items index)
                                         (aref candidate index)))))))))
           (with-present (schemas present-p node "allOf")
             (when present-p
               (loop for item across schemas
                     do (setf candidate (walk item candidate)))))
           candidate))
      (walk schema value))))

(defun schema-rejects-null-p (schema)
  ;; Baseline utils/validation.ts: the deletion test inside
  ;; normalizeOptionalNulls is
  ;; getSubSchemaValidator(schema)?.Check(null) === false.  A schema the
  ;; validator cannot compile yields undefined, which is not false, so the
  ;; baseline keeps the key; mirror that by treating anything but a clean
  ;; validation failure as "does not reject".
  (cond
    ((eq schema t) nil)
    ((null schema) t)
    ((not (cadr-ai::json-object-p schema)) nil)
    (t (handler-case
           (progn (validate-json-schema-instance schema 'null) nil)
         (native-schema-error () t)
         (error () nil)))))

(defun normalize-optional-nulls (value schema)
  (setf value (cadr-ai::json-ensure-hash-table value)
        schema (cadr-ai::json-ensure-hash-table schema))
  ;; Baseline utils/validation.ts normalizeOptionalNulls: delete object
  ;; properties whose value is null when the property is not required and
  ;; its schema rejects null, before coercion.  Runs before
  ;; Value.Convert in the baseline; here it runs before
  ;; coerce-json-schema-instance.
  (cond
    ((vectorp value)
     (when-present (items schema "items")
         (cond
           ((vectorp items)
            (loop for index below (min (length value) (length items))
                  do (normalize-optional-nulls
                      (aref value index) (aref items index))))
           ((hash-table-p items)
            (loop for item across value
                  do (normalize-optional-nulls item items))))))
    ((hash-table-p value)
     (when-present (properties schema "properties")
         (let ((required
                 (coerce (or (gethash "required" schema) #()) 'list)))
           (loop for key being the hash-keys of properties
                 using (hash-value property-schema)
                 do (when-present (property-value value key)
                        (if (and (eq property-value 'null)
                                 (not (member key required
                                              :test #'string=))
                                 (not
                                  (and (hash-table-p property-schema)
                                       (stringp
                                        (gethash "$ref"
                                                 property-schema))))
                                 (schema-rejects-null-p property-schema))
                            (remhash key value)
                            (normalize-optional-nulls
                             property-value property-schema)))))))
    (t nil)))

(defun validate-tool-arguments (tool arguments)
  (handler-case
      (let ((schema (cadr-ai:tool-parameters tool)))
        (normalize-optional-nulls arguments schema)
        (validate-json-schema-instance
         schema
         (coerce-json-schema-instance schema arguments)))
    (native-schema-error (condition)
      (let ((pointer
              (native-schema-error-json-pointer condition))
            (reason
              (native-schema-error-reason condition)))
        (error
         'schema-validation-error
         :tool (cadr-ai:tool-name tool)
         :json-pointer pointer
         :reason reason
         :message
         (format nil
                 "Invalid arguments for tool ~A at ~A: ~A"
                 (cadr-ai:tool-name tool)
                 (if (zerop (length pointer)) "/" pointer)
                 reason))))))
