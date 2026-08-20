(in-package #:cadr-ai)

;;; Deferred tools and constrained sampling

(defun normalized-tool-name (name normalizer)
  (funcall (or normalizer #'identity) name))

(defun split-deferred-tools (context enabled-p &optional normalizer)
  (let ((unique (make-hash-table :test #'equal))
        (order nil))
    (dolist (tool (context-tools context))
      (let ((name (normalized-tool-name (tool-name tool) normalizer)))
        (unless (gethash name unique)
          (push name order))
        (setf (gethash name unique) tool)))
    (setf order (nreverse order))
    (unless enabled-p
      (return-from split-deferred-tools
        (values (mapcar (lambda (name) (gethash name unique)) order)
                (make-hash-table :test #'equal))))
    (let ((deferred-names (make-hash-table :test #'equal))
          (used-names (make-hash-table :test #'equal)))
      (dolist (message (context-messages context))
        (cond
          ((typep message 'assistant-message)
           (dolist (block (assistant-message-content message))
             (when (typep block 'tool-call)
               (setf (gethash
                      (normalized-tool-name (tool-call-name block) normalizer)
                      used-names)
                     t))))
          ((typep message 'tool-result-message)
           (dolist (name (tool-result-message-added-tool-names message))
             (let ((normalized (normalized-tool-name name normalizer)))
               (unless (gethash normalized used-names)
                 (setf (gethash normalized deferred-names) t)))))))
      (let ((immediate nil)
            (deferred (make-hash-table :test #'equal)))
        (dolist (name order)
          (if (gethash name deferred-names)
              (setf (gethash name deferred) (gethash name unique))
              (push (gethash name unique) immediate)))
        (values (nreverse immediate) deferred)))))

(defun keyed-collection-value (object key)
  ;; One owner for hash-or-plist lookup. Keywords look up the
  ;; downcased name first (sampling); strings use json-get / intern
  ;; (schema). Inverse conventions stay here, not at each caller.
  (cond
    ((hash-table-p object)
     (if (keywordp key)
         (or (gethash (string-downcase (symbol-name key)) object)
             (gethash key object))
         (json-get object key)))
    ((json-object-pairs-p object)
     (json-get
      object
      (if (keywordp key)
          (string-downcase (symbol-name key))
          key)))
    ((listp object)
     (getf object
           (if (keywordp key)
               key
               (intern (string-upcase key) :keyword))))
    (t nil)))

(defun sampling-value (sampling key)
  (keyed-collection-value sampling key))

(defun sampling-type (sampling)
  (let ((type (sampling-value sampling :type)))
    (etypecase type
      (null nil)
      (keyword type)
      (string (intern (string-upcase (substitute #\- #\_ type)) :keyword)))))

(defun schema-value (schema key)
  (keyed-collection-value schema key))

(defun get-grammar-tool-input (tool-name arguments input-property)
  (let ((value (schema-value arguments input-property)))
    (unless (stringp value)
      (error "Grammar tool call ~S requires argument ~S to be a string."
             tool-name input-property))
    value))

(defun resolve-json-schema-strict-sampling (tool supports-strict-mode-p)
  (let ((config (tool-constrained-sampling tool)))
    (unless (eq :json-schema (sampling-type config))
      (return-from resolve-json-schema-strict-sampling nil))
    (cond
      (supports-strict-mode-p
       ;; v0.84.2: strict is usable only when the schema converts.
       (handler-case
           (progn (make-strict-json-schema (tool-parameters tool)) t)
         (unsupported-strict-json-schema-error (condition)
           (if (eq :require (sampling-value config :strict))
               (error
                "Tool ~S requires JSON-schema constrained sampling, but ~A."
                (tool-name tool) condition)
               (return-from resolve-json-schema-strict-sampling nil)))))
      ((eq :require (sampling-value config :strict))
       (error "Tool ~S requires JSON-schema constrained sampling, but strict tools are unsupported."
              (tool-name tool)))
      (t nil))))

(defun infer-grammar-input-property (tool)
  (let* ((schema (tool-parameters tool))
         (required (schema-value schema "required"))
         (properties (schema-value schema "properties")))
    (unless (string= "object" (or (schema-value schema "type") ""))
      (error "grammar constrained sampling requires an object parameter schema"))
    (unless (and (vectorp required)
                 (= 1 (length required))
                 (stringp (aref required 0)))
      (error "grammar constrained sampling requires exactly one required string property"))
    (let* ((name (aref required 0))
           (property (schema-value properties name)))
      (unless property
        (error "grammar constrained sampling requires a properties entry for ~A" name))
      (unless (string= "string" (or (schema-value property "type") ""))
        (error "grammar constrained sampling property ~A must have type string" name))
      name)))

(defun resolve-grammar-constrained-sampling
    (tool supports-openai-grammar-tools-p)
  (let ((config (tool-constrained-sampling tool)))
    (unless (and (eq :grammar (sampling-type config))
                 supports-openai-grammar-tools-p)
      (return-from resolve-grammar-constrained-sampling nil))
    (let* ((variants (sampling-value config :variants))
           (lark (sampling-value variants :openai-lark))
           (regex (sampling-value variants :openai-regex))
           (lark-p (and (stringp lark) (plusp (length (string-trim '(#\Space) lark)))))
           (regex-p (and (stringp regex) (plusp (length (string-trim '(#\Space) regex))))))
      (unless (or lark-p regex-p)
        (error "Tool ~S cannot use grammar constrained sampling: no supported grammar variant was provided."
               (tool-name tool)))
      (handler-case
          (list :format (if lark-p :lark :regex)
                :definition (if lark-p lark regex)
                :input-property (infer-grammar-input-property tool))
        (error (condition)
          (error "Tool ~S cannot use grammar constrained sampling: ~A."
                 (tool-name tool) condition))))))

(defun create-grammar-tool-input-properties
    (tools supports-openai-grammar-tools-p)
  (let ((properties (make-hash-table :test #'equal)))
    (dolist (tool tools)
      (let ((grammar
              (resolve-grammar-constrained-sampling
               tool supports-openai-grammar-tools-p)))
        (when grammar
          (setf (gethash (tool-name tool) properties)
                (getf grammar :input-property)))))
    properties))

;;; Strict JSON-schema conversion (baseline api/constrained-sampling.ts
;;; makeStrictJsonSchema / getJsonSchemaToolParameters, added in v0.84.2).

(define-condition unsupported-strict-json-schema-error (simple-error) ())

(defparameter +unsupported-strict-schema-keys+
  '("$ref" "$defs" "definitions" "allOf" "oneOf" "patternProperties"
    "dependentSchemas" "dependencies" "unevaluatedProperties"
    "propertyNames" "contains" "prefixItems" "not" "if" "then" "else"))

(defun strict-schema-error (format-control &rest arguments)
  (error 'unsupported-strict-json-schema-error
         :format-control format-control
         :format-arguments arguments))

(defun structured-schema-p (schema)
  ;; Baseline isStructuredSchema.
  (when (json-object-p schema)
    (let ((types
            (let ((present-p (json-present-p schema "type"))
                  (type (json-get schema "type")))
              (cond
                ((not present-p) nil)
                ((stringp type) (list type))
                ((vectorp type) (coerce type 'list))
                (t nil)))))
      (or (member "object" types :test #'string=)
          (member "array" types :test #'string=)
          (json-present-p schema "properties")
          (json-present-p schema "items")))))

(defun schema-allows-null-p (schema)
  ;; Baseline schemaAllowsNull.
  (when (json-object-p schema)
    (let ((present-p (json-present-p schema "type"))
          (type (json-get schema "type")))
      (when (and present-p
                 (or (and (stringp type) (string= type "null"))
                     (and (vectorp type)
                          (find "null" type :test #'string=))))
        (return-from schema-allows-null-p t)))
    (when (and (json-present-p schema "const")
               (eq (json-get schema "const") 'null))
      (return-from schema-allows-null-p t))
    (let ((enum (json-get schema "enum")))
      (when (and (json-present-p schema "enum")
                 (vectorp enum)
                 (find 'null enum))
        (return-from schema-allows-null-p t)))
    (let ((any-of (json-get schema "anyOf")))
      (and (json-present-p schema "anyOf")
           (vectorp any-of)
           (some #'schema-allows-null-p (coerce any-of 'list))))))

(defun make-json-schema-node-strict (schema)
  ;; Baseline makeJsonSchemaNodeStrict; mutates SCHEMA in place.
  (unless (json-object-p schema)
    (strict-schema-error "boolean schemas are unsupported"))
  (dolist (key +unsupported-strict-schema-keys+)
    (when (json-present-p schema key)
      (strict-schema-error "~A schemas are unsupported" key)))
  (let ((any-of-present-p (json-present-p schema "anyOf"))
        (any-of (json-get schema "anyOf")))
    (when any-of-present-p
      (unless (and (vectorp any-of) (plusp (length any-of)))
        (strict-schema-error "anyOf must contain at least one schema"))
      (loop for variant across any-of
            do (when (structured-schema-p variant)
                 (strict-schema-error
                  "object and array unions are unsupported"))
               (make-json-schema-node-strict variant))))
  (let ((items-present-p (json-present-p schema "items"))
        (items (json-get schema "items")))
    (when items-present-p
      (when (vectorp items)
        (strict-schema-error "tuple schemas are unsupported"))
      (make-json-schema-node-strict items)))
  (let ((object-schema-p
          (let ((present-p (json-present-p schema "type"))
                (type (json-get schema "type")))
            (and present-p (stringp type) (string= type "object")))))
    (let ((properties-p (json-present-p schema "properties"))
          (properties (json-get schema "properties")))
      (when (and properties-p (not object-schema-p))
        (strict-schema-error "properties require type object"))
      (unless object-schema-p
        (return-from make-json-schema-node-strict nil))
      (let ((additional-present-p
              (json-present-p schema "additionalProperties"))
            (additional (json-get schema "additionalProperties")))
        ;; JSON false parses to nil: present and false is allowed.
        (when (and additional-present-p (not (null additional)))
          (strict-schema-error
           "schema-valued or true additionalProperties is unsupported")))
      (when (and properties-p (not (json-object-p properties)))
        (strict-schema-error "object properties must be a schema map"))
      (let ((required-p (json-present-p schema "required"))
            (required (json-get schema "required")))
        (when (and required-p
                   (not (and (vectorp required)
                             (loop for item across required
                                   always (stringp item)))))
          (strict-schema-error "object required must be a string array"))
        (let* ((properties
                 (or properties (make-hash-table :test #'equal)))
               (property-names (json-keys properties))
               (required-names
                 (if (and required-p (vectorp required))
                     (coerce required 'list)
                     nil)))
          (when (loop for name in required-names
                      thereis (not (member name property-names
                                           :test #'string=)))
            (strict-schema-error "required contains an unknown property"))
          (dolist (key property-names)
            (let ((property (json-get properties key)))
              (make-json-schema-node-strict property)
              (unless (or (member key required-names :test #'string=)
                          (schema-allows-null-p property))
                (let ((wrapper (make-hash-table :test #'equal))
                      (null-schema (make-hash-table :test #'equal)))
                  (setf (gethash "type" null-schema) "null")
                  (setf (gethash "anyOf" wrapper)
                        (vector property null-schema))
                  (json-put properties key wrapper)))))
          (json-put schema "required" (coerce property-names 'vector))
          (json-put schema "additionalProperties" nil))))))

(defun make-strict-json-schema (parameters)
  ;; Baseline makeStrictJsonSchema: convert a tool schema to the strict
  ;; subset expected by provider constrained sampling.
  (let ((cloned (copy-json-value parameters)))
    (unless (json-object-p cloned)
      (strict-schema-error "root schema must have type object"))
    (make-json-schema-node-strict cloned)
    (let ((present-p (json-present-p cloned "type"))
          (type (json-get cloned "type")))
      (unless (and present-p (stringp type) (string= type "object"))
        (strict-schema-error "root schema must have type object")))
    cloned))

(defun get-json-schema-tool-parameters (tool strict)
  ;; Baseline getJsonSchemaToolParameters.
  (if (eq strict t)
      (make-strict-json-schema (tool-parameters tool))
      (tool-parameters tool)))
