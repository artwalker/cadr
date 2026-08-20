(in-package #:cadr-ai)

(defstruct grammar-json-buffer
  (input "" :type string)
  (started-p nil :type boolean)
  (closed-p nil :type boolean))

(defun json-string-interior (value)
  (let ((encoded (stringify-json value)))
    (subseq encoded 1 (1- (length encoded)))))

(defun append-grammar-json-delta
    (buffer input-property next-input close-p)
  (when (grammar-json-buffer-closed-p buffer)
    (if (and close-p
             (string=
              next-input (grammar-json-buffer-input buffer)))
        (return-from append-grammar-json-delta nil)
        (error
         "grammar tool input for property ~S changed after it was closed"
         input-property)))
  (unless
      (uiop:string-prefix-p
       (grammar-json-buffer-input buffer) next-input)
    (error
     "grammar tool input for property ~S changed non-monotonically"
     input-property))
  (let* ((old (grammar-json-buffer-input buffer))
         (input-delta (subseq next-input (length old))))
    (when (and (not close-p)
               (zerop (length input-delta)))
      (return-from append-grammar-json-delta nil))
    (prog1
        (with-output-to-string (output)
          (unless (grammar-json-buffer-started-p buffer)
            (format output "{~A:\""
                    (stringify-json input-property))
            (setf (grammar-json-buffer-started-p buffer) t))
          (write-string (json-string-interior input-delta) output)
          (when close-p
            (write-string "\"}" output)
            (setf (grammar-json-buffer-closed-p buffer) t)))
      (setf (grammar-json-buffer-input buffer) next-input))))

(defun schema-types (schema)
  (let ((type (json-get schema "type")))
    (cond
      ((stringp type) (list type))
      ((vectorp type)
       (remove-if-not #'stringp (coerce type 'list)))
      ((listp type) (remove-if-not #'stringp type))
      (t nil))))

(defun json-type-p (value type)
  (cond
    ((string= type "number") (numberp value))
    ((string= type "integer") (integerp value))
    ((string= type "boolean") (or (eq value t) (null value)))
    ((string= type "string") (stringp value))
    ((string= type "null") (json-null-p value))
    ((string= type "array")
     (and (or (vectorp value) (listp value))
          (not (json-object-pairs-p value))))
    ((string= type "object") (json-object-p value))
    (t nil)))

(defun parse-coercible-number (value integer-p)
  (when (and (stringp value)
             (plusp (length (string-trim '(#\Space #\Tab) value))))
    (handler-case
        (multiple-value-bind (number position)
            (read-from-string value)
          (when (and (numberp number)
                     (or (not integer-p) (integerp number))
                     (= position (length value)))
            number))
      (error () nil))))

(defun coerce-primitive (value type)
  (cond
    ((string= type "number")
     (cond
       ((json-null-p value) (values 0 t))
       ((or (eq value t) (null value))
        (values (if value 1 0) t))
       ((parse-coercible-number value nil)
        (values (parse-coercible-number value nil) t))
       (t (values value nil))))
    ((string= type "integer")
     (cond
       ((json-null-p value) (values 0 t))
       ((or (eq value t) (null value))
        (values (if value 1 0) t))
       ((parse-coercible-number value t)
        (values (parse-coercible-number value t) t))
       (t (values value nil))))
    ((string= type "boolean")
     (cond
       ((json-null-p value) (values nil t))
       ((and (stringp value) (string= value "true"))
        (values t t))
       ((and (stringp value) (string= value "false"))
        (values nil t))
       ((and (numberp value) (= value 1)) (values t t))
       ((and (numberp value) (zerop value)) (values nil t))
       (t (values value nil))))
    ((string= type "string")
     (cond
       ((json-null-p value) (values "" t))
       ((eq value t) (values "true" t))
       ((null value) (values "false" t))
       ((numberp value) (values (princ-to-string value) t))
       (t (values value nil))))
    ((string= type "null")
     (if (or (and (stringp value) (string= value ""))
             (and (numberp value) (zerop value))
             (null value))
         (values 'null t)
         (values value nil)))
    (t (values value nil))))

(defun schema-valid-p (value schema)
  (let ((types (schema-types schema)))
    (and
     (or (null types)
         (some (lambda (type) (json-type-p value type)) types))
     (or
      (not (json-object-p value))
      (not (member "object" types :test #'string=))
      (let ((properties (json-get schema "properties"))
            (required
              (coerce (or (json-get schema "required") #()) 'list)))
        (and
         (every
          (lambda (name) (json-present-p value name))
          required)
         (or
          (not (json-object-p properties))
          (loop for key in (json-keys properties)
                always
                (or
                 (not (json-present-p value key))
                 (schema-valid-p
                  (json-get value key)
                  (json-get properties key))))))))
     (or
      (not
       (and (member "array" types :test #'string=)
            (or (vectorp value)
                (and (listp value)
                     (not (json-object-pairs-p value))))))
      (let ((items (json-get schema "items")))
        (or
         (not (json-object-p items))
         (every
          (lambda (item) (schema-valid-p item items))
          (coerce value 'list))))))))

(defun coerce-schema-value (value schema)
  (let ((types (schema-types schema))
        (next value))
    (unless
        (and (> (length types) 1)
             (some (lambda (type) (json-type-p next type)) types))
      (dolist (type types)
        (multiple-value-bind (candidate changed-p)
            (coerce-primitive next type)
          (when changed-p
            (setf next candidate)
            (return)))))
    (when
        (and (json-object-p next)
             (member "object" types :test #'string=))
      (let ((properties (json-get schema "properties"))
            (additional (json-get schema "additionalProperties")))
        (when (json-object-p properties)
          (json-map-entries
           next
           (lambda (key val)
             (let ((nested
                     (if (json-present-p properties key)
                         (json-get properties key)
                         (and (json-object-p additional) additional))))
               (when nested
                 (json-put
                  next key
                  (coerce-schema-value val nested)))))))))
    (when
        (and (or (vectorp next)
                 (and (listp next)
                      (not (json-object-pairs-p next))))
             (member "array" types :test #'string=)
             (json-object-p (json-get schema "items")))
      (if (vectorp next)
          (loop for index below (length next)
                do
                (setf (aref next index)
                      (coerce-schema-value
                       (aref next index)
                       (json-get schema "items"))))
          (setf next
                (mapcar
                 (lambda (item)
                   (coerce-schema-value
                    item (json-get schema "items")))
                 next))))
    next))

(defun copy-json-value (value)
  (parse-json (stringify-json value)))

(defun schema-rejects-null-p (schema)
  ;; Baseline: getSubSchemaValidator(schema)?.Check(null) === false.  An
  ;; uncompilable schema is not false, so the baseline keeps the key;
  ;; anything but a clean rejection is treated as "does not reject".
  (cond
    ((eq schema t) nil)
    ((null schema) t)
    ((not (json-object-p schema)) nil)
    (t (not (schema-valid-p 'null schema)))))

(defun normalize-optional-nulls (value schema)
  ;; Baseline utils/validation.ts normalizeOptionalNulls: delete object
  ;; properties whose value is null when the property is not required and
  ;; its schema rejects null.  Runs before Value.Convert in the baseline;
  ;; here before coerce-schema-value.  Twin of the full-validator version
  ;; in src/cadr-agent/schema.lisp.
  (cond
    ((vectorp value)
     (let ((items (json-get schema "items")))
       (cond
         ((vectorp items)
          (loop for index below (min (length value) (length items))
                do (normalize-optional-nulls
                    (aref value index) (aref items index))))
         ((json-object-p items)
          (loop for item across value
                do (normalize-optional-nulls item items))))))
    ((json-object-p value)
     (let ((properties (json-get schema "properties")))
       (when (json-object-p properties)
         (let ((required
                 (coerce (or (json-get schema "required") #()) 'list)))
           (dolist (key (json-keys properties))
             (let ((property-schema (json-get properties key)))
               (when (json-present-p value key)
                 (let ((property-value (json-get value key)))
                   (if (and (eq property-value 'null)
                            (not (member key required :test #'string=))
                            (not
                             (and (json-object-p property-schema)
                                  (stringp
                                   (json-get property-schema "$ref"))))
                            (schema-rejects-null-p property-schema))
                       (json-delete value key)
                       (normalize-optional-nulls
                        property-value property-schema))))))))))
    (t nil)))

(defun validate-tool-arguments (tool call)
  (let* ((schema (tool-parameters tool))
         (arguments
           (copy-json-value (tool-call-arguments call))))
    ;; normalize-optional-nulls mutates the clone, mirroring the baseline
    ;; structuredClone-then-delete order.
    (normalize-optional-nulls arguments schema)
    (let ((coerced (coerce-schema-value arguments schema)))
      (unless (schema-valid-p coerced schema)
        (error
         "Validation failed for tool ~S.~%Received arguments:~%~A"
         (tool-call-name call)
         (stringify-json (tool-call-arguments call))))
      coerced)))

(defun validate-tool-call (tools call)
  (let ((tool
          (find
           (tool-call-name call) tools
           :key #'tool-name :test #'string=)))
    (unless tool
      (error "Tool ~S not found" (tool-call-name call)))
    (validate-tool-arguments tool call)))
