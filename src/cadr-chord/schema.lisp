(in-package #:cadr-chord)

(defun u32 (value)
  (logand value #xffffffff))

(defun imul32 (left right)
  (let ((product (* (if (logbitp 31 (u32 left))
                        (- (u32 left) #x100000000)
                        (u32 left))
                    (if (logbitp 31 (u32 right))
                        (- (u32 right) #x100000000)
                        (u32 right)))))
    (u32 product)))

(defun hash64 (text)
  (let ((a #x811c9dc5)
        (b (logxor #x01000193 #x5bd1e995)))
    (loop for character across text
          for code = (char-code character)
          do (setf a (imul32 (logxor (u32 a) code) #x01000193)
                   b (logxor (imul32 (logxor (u32 b) code) #x5bd1e995)
                             (ash (u32 b) -13))))
    (format nil "~(~8,'0x~8,'0x~)" (u32 a) (u32 b))))

(defun schema-type (schema)
  (and (hash-table-p schema) (gethash "type" schema)))

(defun schema-string ()
  (json-object "type" "string"))

(defun schema-number (&key default)
  (let ((schema (json-object "type" "number")))
    (when default (json-put schema "default" default))
    schema))

(defun schema-integer ()
  (json-object "type" "integer"))

(defun schema-boolean ()
  (json-object "type" "boolean"))

(defun schema-unknown ()
  (json-object))

(defun schema-object (properties)
  (let ((table (json-object))
        (required (json-array)))
    (dolist (property properties)
      (destructuring-bind (name schema &key optional) property
        (json-put table name schema)
        (unless optional (vector-push-extend name required))))
    (json-object "type" "object" "properties" table "required" required)))

(defun schema-function (parameters return-type)
  (json-object "type" "function"
               "parameters" (apply #'json-array parameters)
               "returnType" return-type))

(defun schema-types (schema)
  (let ((type (schema-type schema)))
    (cond
      ((stringp type) (list type))
      ((and (vectorp type) (not (stringp type))) (coerce type 'list))
      (t nil))))

(defparameter +schema-annotations+
  '("title" "description" "default" "examples" "$id" "$schema" "$comment"
    "readOnly" "writeOnly" "deprecated"))

(defparameter +schema-constraints+
  '("minLength" "maxLength" "pattern" "format" "minimum" "maximum"
    "exclusiveMinimum" "exclusiveMaximum" "multipleOf" "minItems" "maxItems"
    "uniqueItems" "minProperties" "maxProperties"))

(defparameter +schema-known+
  (append +schema-constraints+
          '("type" "properties" "required" "additionalProperties" "patternProperties"
            "items" "additionalItems" "const" "enum" "anyOf" "parameters" "returnType")))

(defun schema-without-annotations (schema)
  (if (not (hash-table-p schema))
      (json-object)
      (let ((copy (json-object)))
        (dolist (key (json-keys schema))
          (unless (member key +schema-annotations+ :test #'string=)
            (json-put copy key (gethash key schema))))
        copy)))

(defun json-deep-equal (left right)
  (string= (canonical-json left) (canonical-json right)))

(defun schema-fits (sub-schema sup-schema)
  (let ((sub (schema-without-annotations (if (hash-table-p sub-schema) sub-schema (json-object))))
        (sup (schema-without-annotations (if (hash-table-p sup-schema) sup-schema (json-object)))))
    (cond
      ((zerop (hash-table-count sup)) t)
      ((json-deep-equal sub sup) t)
      ((some (lambda (key) (not (member key +schema-known+ :test #'string=)))
             (json-keys sup))
       nil)
      ((and (nth-value 1 (gethash "additionalProperties" sup))
            (not (member (gethash "additionalProperties" sup) '(t nil))))
       nil)
      ((gethash "anyOf" sub)
       (every (lambda (branch) (schema-fits branch sup)) (coerce (gethash "anyOf" sub) 'list)))
      ((gethash "anyOf" sup)
       (some (lambda (branch) (schema-fits sub branch)) (coerce (gethash "anyOf" sup) 'list)))
      ((nth-value 1 (gethash "const" sup))
       (and (nth-value 1 (gethash "const" sub))
            (json-deep-equal (gethash "const" sub) (gethash "const" sup))))
      (t
       (let ((sup-types (schema-types sup))
             (sub-types (schema-types sub)))
         (and (every (lambda (key)
                       (or (not (nth-value 1 (gethash key sup)))
                           (json-deep-equal (gethash key sub) (gethash key sup))))
                     +schema-constraints+)
              sup-types
              sub-types
              (every (lambda (type)
                       (or (member type sup-types :test #'string=)
                           (and (string= type "integer")
                                (member "number" sup-types :test #'string=))))
                     sub-types)
              (or (nth-value 1 (gethash "const" sub))
                  (gethash "enum" sub)
                  (and (or (not (member "object" sub-types :test #'string=))
                           (object-fits sub sup))
                       (or (not (member "array" sub-types :test #'string=))
                           (array-fits sub sup))
                       (or (not (member "function" sub-types :test #'string=))
                           (function-fits sub sup))))))))))

(defun object-fits (sub sup)
  (let* ((sub-properties (or (gethash "properties" sub) (json-object)))
         (sup-properties (or (gethash "properties" sup) (json-object)))
         (sub-required (coerce (or (gethash "required" sub) (json-array)) 'list))
         (sup-required (coerce (or (gethash "required" sup) (json-array)) 'list)))
    (and (every (lambda (key) (member key sub-required :test #'string=)) sup-required)
         (every (lambda (key)
                  (or (not (nth-value 1 (gethash key sub-properties)))
                      (schema-fits (gethash key sub-properties) (gethash key sup-properties))))
                (json-keys sup-properties))
         (or (not (and (nth-value 1 (gethash "additionalProperties" sup))
                           (eq (gethash "additionalProperties" sup) nil)))
             (and (eq (gethash "additionalProperties" sub) nil)
                  (every (lambda (key) (nth-value 1 (gethash key sup-properties)))
                         (json-keys sub-properties)))))))

(defun array-fits (sub sup)
  (schema-fits (gethash "items" sub) (gethash "items" sup)))

(defun function-fits (sub sup)
  (let ((sub-parameters (coerce (or (gethash "parameters" sub) (json-array)) 'list))
        (sup-parameters (coerce (or (gethash "parameters" sup) (json-array)) 'list)))
    (and (<= (length sub-parameters) (length sup-parameters))
         (loop for parameter in sub-parameters
               for index from 0
               always (schema-fits (nth index sup-parameters) parameter))
         (schema-fits (gethash "returnType" sub) (gethash "returnType" sup)))))

(defun schema-default (schema value)
  (cond
    ((and (vectorp value) (not (stringp value)))
     (let ((copy (json-array)))
       (loop for element across value
             do (vector-push-extend (schema-default (gethash "items" schema) element) copy))
       copy))
    ((hash-table-p value)
     (let* ((properties (or (gethash "properties" schema) (json-object)))
            (copy (json-object)))
       (dolist (key (json-keys properties))
         (let ((property (gethash key properties)))
           (multiple-value-bind (present found) (gethash key value)
             (cond
               (found (json-put copy key (schema-default property present)))
               ((nth-value 1 (gethash "default" property))
                (json-put copy key (copy-json (gethash "default" property))))))))
       copy))
    (t value)))

(defun schema-clean (schema value)
  (cond
    ((and (vectorp value) (not (stringp value)))
     (let ((copy (json-array)))
       (loop for element across value
             do (vector-push-extend (schema-clean (gethash "items" schema) element) copy))
       copy))
    ((hash-table-p value)
     (let* ((properties (or (gethash "properties" schema) (json-object)))
            (copy (json-object)))
       (dolist (key (json-keys properties))
         (multiple-value-bind (present found) (gethash key value)
           (when found
             (json-put copy key (schema-clean (gethash key properties) present)))))
       copy))
    (t value)))

(defun schema-type-matches-p (schema value)
  (let ((types (schema-types schema)))
    (or (null types)
        (some (lambda (type)
                (cond
                  ((string= type "object") (hash-table-p value))
                  ((string= type "array") (and (vectorp value) (not (stringp value))))
                  ((string= type "string") (stringp value))
                  ((string= type "number") (json-number-p value))
                  ((string= type "integer") (integerp value))
                  ((string= type "boolean") (member value '(t nil)))
                  ((string= type "null") (json-null-p value))
                  ((string= type "void") t)
                  ((string= type "function") (functionp value))
                  (t nil)))
              types))))

(defun schema-errors (schema value &optional (path "/"))
  (let ((errors nil))
    (unless (schema-type-matches-p schema value)
      (push (format nil "~A must be ~A" path (or (schema-type schema) "valid")) errors))
    (when (and (hash-table-p value) (string= (or (schema-type schema) "") "object"))
      (let ((required (coerce (or (gethash "required" schema) (json-array)) 'list))
            (properties (or (gethash "properties" schema) (json-object))))
        (let ((missing (remove-if (lambda (key) (nth-value 1 (gethash key value))) required)))
          (when missing
            (push (format nil "~A must have required properties ~{~A~^,~}" path missing) errors)))
        (dolist (key (json-keys properties))
          (multiple-value-bind (present found) (gethash key value)
            (when found
              (unless (schema-type-matches-p (gethash key properties) present)
                (push (format nil "~A~A must be ~A"
                              path key (schema-type (gethash key properties)))
                      errors)))))))
    (nreverse errors)))

(defun schema-assert (reason what schema value)
  (let ((errors (schema-errors schema value)))
    (when errors
      (invalid reason (format nil "~A: ~{~A~^; ~}" what errors) errors))))

(defun schema-normalize (schema value what)
  (let* ((seed (if (null value) (json-object) (copy-json value)))
         (defaulted (schema-default schema seed))
         (cleaned (schema-clean schema defaulted)))
    (schema-assert "input" what schema cleaned)
    cleaned))

(defun strip-defaults (schema value)
  (cond
    ((and (vectorp value) (not (stringp value)))
     (let ((copy (json-array)))
       (loop for element across value
             do (vector-push-extend (strip-defaults (gethash "items" schema) element) copy))
       copy))
    ((hash-table-p value)
     (let ((properties (or (gethash "properties" schema) (json-object)))
           (result (json-object)))
       (dolist (key (json-keys value))
         (let* ((item (gethash key value))
                (property (or (gethash key properties) (json-object))))
           (unless (and (nth-value 1 (gethash "default" property))
                        (json-deep-equal (gethash "default" property) item))
             (json-put result key (strip-defaults property item)))))
       result))
    (t value)))

(defun canonical-identity (schema value)
  (canonical-json (strip-defaults schema value)))
