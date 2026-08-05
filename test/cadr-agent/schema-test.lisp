(in-package #:cadr-agent/tests)
(in-suite cadr-agent-suite)

(defun schema-object (&rest pairs)
  (apply #'cadr-ai::json-object pairs))

(test native-schema-validates-nested-tool-arguments
  (let* ((edit
           (schema-object
            "type" "object"
            "properties"
            (schema-object
             "path" (schema-object "type" "string" "minLength" 1)
             "edits"
             (schema-object
              "type" "array"
              "minItems" 1
              "items"
              (schema-object
               "type" "object"
               "properties"
               (schema-object
                "oldText" (schema-object "type" "string")
                "newText" (schema-object "type" "string"))
               "required" (vector "oldText" "newText")
               "additionalProperties" nil)))
            "required" (vector "path" "edits")
            "additionalProperties" nil))
         (tool
           (make-tool
            :name "edit"
            :description "Edit"
            :parameters edit
            :executor (lambda (id arguments)
                        (declare (ignore id arguments)))))
         (arguments
           (schema-object
            "path" "README.md"
            "edits"
            (vector
             (schema-object "oldText" "old" "newText" "new")))))
    (is (eq arguments
            (cadr-agent:validate-tool-arguments
             tool arguments)))
    (handler-case
        (progn
          (cadr-agent:validate-tool-arguments
           tool
           (schema-object
            "path" "README.md"
            "edits"
            (vector (schema-object "oldText" "old"))))
          (fail "Expected nested validation failure"))
      (cadr-agent:schema-validation-error (condition)
        (is
         (string=
          "/edits/0"
          (cadr-agent:schema-validation-error-json-pointer
           condition)))))
    (handler-case
        (progn
          (cadr-agent:validate-tool-arguments
           tool
           (schema-object
            "path" "README.md"
            "edits"
            (vector
             (schema-object
              "oldText" "old" "newText" "new" "surprise" t))))
          (fail "Expected additional property failure"))
      (cadr-agent:schema-validation-error (condition)
        (is
         (string=
          "/edits/0/surprise"
          (cadr-agent:schema-validation-error-json-pointer
           condition)))))))

(test native-schema-supports-composition-and-scalar-constraints
  (let ((schema
          (schema-object
           "allOf"
           (vector
            (schema-object "type" "string" "minLength" 2)
            (schema-object "pattern" "^[a-z]+$")
            (schema-object "enum" (vector "ok" "yes"))))))
    (is
     (string=
      "ok"
      (cadr-agent::validate-json-schema-instance
       schema "ok")))
    (signals cadr-agent::native-schema-error
      (cadr-agent::validate-json-schema-instance schema "NO"))
    (signals cadr-agent::native-schema-error
      (cadr-agent::validate-json-schema-instance schema "x")))
  (let ((schema
          (schema-object
           "oneOf"
           (vector
            (schema-object "type" "integer" "minimum" 1)
            (schema-object "type" "string" "const" "auto")))))
    (is (= 2
           (cadr-agent::validate-json-schema-instance schema 2)))
    (is
     (string=
      "auto"
      (cadr-agent::validate-json-schema-instance schema "auto")))
    (signals cadr-agent::native-schema-error
      (cadr-agent::validate-json-schema-instance schema 0))))

(test native-schema-definition-rejects-malformed-keywords
  (signals cadr-agent::native-schema-error
    (cadr-agent::validate-json-schema-definition
     (schema-object "type" "wat")))
  (signals cadr-agent::native-schema-error
    (cadr-agent::validate-json-schema-definition
     (schema-object "required" (vector "x" "x"))))
  (signals cadr-agent::native-schema-error
    (cadr-agent::validate-json-schema-definition
     (schema-object "pattern" "[")))
  (signals cadr-agent::native-schema-error
    (cadr-agent::validate-json-schema-definition
     (schema-object "$ref" "#/$defs/missing"))))

(test native-schema-coerces-tool-arguments-like-baseline
  (let* ((schema
           (schema-object
            "type" "object"
            "properties"
            (schema-object
             "command" (schema-object "type" "string")
             "count" (schema-object "type" "integer")
             "enabled" (schema-object "type" "boolean")
             "items" (schema-object
                      "type" "array"
                      "items" (schema-object "type" "number")))
            "required" (vector "command" "count" "enabled" "items")
            "additionalProperties" nil))
         (tool
           (make-tool
            :name "coercion"
            :description "Coercion parity"
            :parameters schema
            :executor (lambda (id arguments)
                        (declare (ignore id arguments)))))
         (arguments
           (schema-object
            "command" 42
            "count" "7"
            "enabled" "false"
            "items" (vector "1.5" 2))))
    (let ((validated
            (cadr-agent:validate-tool-arguments tool arguments)))
      (is (string= "42" (gethash "command" validated)))
      (is (= 7 (gethash "count" validated)))
      (is (null (gethash "enabled" validated)))
      (is (= 1.5d0 (aref (gethash "items" validated) 0)))
      (is (= 2 (aref (gethash "items" validated) 1))))))
