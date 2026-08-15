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

(defun sampling-value (sampling key)
  (cond
    ((hash-table-p sampling)
     (or (gethash (string-downcase (symbol-name key)) sampling)
         (gethash key sampling)))
    ((listp sampling) (getf sampling key))
    (t nil)))

(defun sampling-type (sampling)
  (let ((type (sampling-value sampling :type)))
    (etypecase type
      (null nil)
      (keyword type)
      (string (intern (string-upcase (substitute #\- #\_ type)) :keyword)))))

(defun schema-value (schema key)
  (cond
    ((hash-table-p schema) (json-get schema key))
    ((listp schema) (getf schema (intern (string-upcase key) :keyword)))
    (t nil)))

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
      (supports-strict-mode-p t)
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
