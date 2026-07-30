(in-package #:pi-agent/tests)
(in-suite pi-agent-suite)

(defun schema-object (&rest pairs)
  (apply #'pi-ai::json-object pairs))

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
            (pi-agent:validate-tool-arguments
             tool arguments)))
    (handler-case
        (progn
          (pi-agent:validate-tool-arguments
           tool
           (schema-object
            "path" "README.md"
            "edits"
            (vector (schema-object "oldText" "old"))))
          (fail "Expected nested validation failure"))
      (pi-agent:schema-validation-error (condition)
        (is
         (string=
          "/edits/0"
          (pi-agent:schema-validation-error-json-pointer
           condition)))))
    (handler-case
        (progn
          (pi-agent:validate-tool-arguments
           tool
           (schema-object
            "path" "README.md"
            "edits"
            (vector
             (schema-object
              "oldText" "old" "newText" "new" "surprise" t))))
          (fail "Expected additional property failure"))
      (pi-agent:schema-validation-error (condition)
        (is
         (string=
          "/edits/0/surprise"
          (pi-agent:schema-validation-error-json-pointer
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
      (pi-agent::validate-json-schema-instance
       schema "ok")))
    (signals pi-agent::native-schema-error
      (pi-agent::validate-json-schema-instance schema "NO"))
    (signals pi-agent::native-schema-error
      (pi-agent::validate-json-schema-instance schema "x")))
  (let ((schema
          (schema-object
           "oneOf"
           (vector
            (schema-object "type" "integer" "minimum" 1)
            (schema-object "type" "string" "const" "auto")))))
    (is (= 2
           (pi-agent::validate-json-schema-instance schema 2)))
    (is
     (string=
      "auto"
      (pi-agent::validate-json-schema-instance schema "auto")))
    (signals pi-agent::native-schema-error
      (pi-agent::validate-json-schema-instance schema 0))))

(test native-schema-definition-rejects-malformed-keywords
  (signals pi-agent::native-schema-error
    (pi-agent::validate-json-schema-definition
     (schema-object "type" "wat")))
  (signals pi-agent::native-schema-error
    (pi-agent::validate-json-schema-definition
     (schema-object "required" (vector "x" "x"))))
  (signals pi-agent::native-schema-error
    (pi-agent::validate-json-schema-definition
     (schema-object "pattern" "[")))
  (signals pi-agent::native-schema-error
    (pi-agent::validate-json-schema-definition
     (schema-object "$ref" "#/$defs/missing"))))
