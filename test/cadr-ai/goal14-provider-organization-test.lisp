(in-package #:cadr-ai/tests)

(in-suite cadr-ai-suite)

(defparameter +goal14-provider-baseline-commit+
  "53fa77ccd8a279eb87e92294ef3687b03ff80112")

(defparameter +goal14-provider-owner-files+
  '("src/cadr-ai/oauth/providers/xai.lisp"
    "src/cadr-ai/oauth/providers/kimi.lisp"
    "src/cadr-ai/oauth/providers/github-copilot.lisp"
    "src/cadr-ai/oauth/providers/openrouter.lisp"
    "src/cadr-ai/oauth/providers/radius.lisp"
    "src/cadr-ai/oauth/providers/openai-device.lisp"
    "src/cadr-ai/oauth/providers/anthropic.lisp"
    "src/cadr-ai/oauth/pkce.lisp"
    "src/cadr-ai/oauth/callback.lisp"
    "src/cadr-ai/oauth/page.lisp"
    "src/cadr-ai/oauth/openai-anthropic.lisp"
    "src/cadr-ai/auth/bedrock.lisp"
    "src/cadr-ai/auth/vertex.lisp"
    "src/cadr-ai/auth/device-code.lisp"
    "src/cadr-ai/auth/github-copilot.lisp"
    "src/cadr-ai/auth/radius-cloudflare.lisp"
    "src/cadr-ai/providers/azure-openai.lisp"
    "src/cadr-ai/providers/codex.lisp"
    "src/cadr-ai/providers/mistral.lisp"
    "src/cadr-ai/providers/vertex.lisp"
    "src/cadr-ai/providers/bedrock.lisp"
    "src/cadr-ai/providers/pi-messages.lisp"
    "src/cadr-ai/providers/definitions.lisp"
    "src/cadr-ai/providers/registry.lisp"
    "src/cadr-ai/providers/runtime-projection.lisp"))

(defparameter +goal14-retired-provider-owner-files+
  '("src/cadr-ai/oauth-flows.lisp"
    "src/cadr-ai/oauth.lisp"
    "src/cadr-ai/provider-auth.lisp"
    "src/cadr-ai/providers/independent.lisp"
    "src/cadr-ai/registry.lisp"))

(defun goal14-json-value (object key)
  (let ((value (cadr-ai::json-get object key)))
    (if (member value '(null :null)) nil value)))

(defun goal14-json-list (object key)
  (coerce (goal14-json-value object key) 'list))

(defun goal14-keyword (value)
  (and value (intern (string-upcase value) :keyword)))

(defun goal14-keyword-list (values)
  (mapcar #'goal14-keyword (coerce values 'list)))

(defun goal14-private-provider-field (definition accessor)
  (if (fboundp accessor)
      (funcall (symbol-function accessor) definition)
      :goal14-missing-accessor))

(defun goal14-provider-matrix ()
  (parse-json (read-fixture "test/fixtures/goal14-provider-baseline.json")))

(test goal14-provider-matrix-is-fixed-baseline-derived-and-complete
  (let* ((matrix (goal14-provider-matrix))
         (providers (goal14-json-value matrix "providers")))
    (is (string= "cadr-goal14-provider-baseline-v1"
                 (goal14-json-value matrix "schema")))
    (is (string= +goal14-provider-baseline-commit+
                 (goal14-json-value matrix "baselineCommit")))
    (is (= 38 (goal14-json-value matrix "providerCount")))
    (is (= 38 (length providers)))
    (is (= 38 (length (remove-duplicates
                       (loop for row across providers
                             collect (goal14-json-value row "id"))
                       :test #'string=))))
    (loop for row across providers
          for source = (goal14-json-value row "source")
          do (is (search "packages/ai/src/providers/" source))
             (is (find #\: source :from-end t)))))

(test goal14-every-provider-definition-field-matches-fixed-baseline-matrix
  (let ((providers (goal14-json-value (goal14-provider-matrix) "providers")))
    (loop for row across providers
          for id = (goal14-keyword (goal14-json-value row "id"))
          for definition = (cadr-ai:find-provider-definition id)
          for metadata = (goal14-json-value row "oauthMetadata")
          do
             (is (eq id (cadr-ai:provider-definition-id definition)))
             (is (string= (goal14-json-value row "source")
                          (goal14-private-provider-field
                           definition
                           'cadr-ai::provider-definition-baseline-source)))
             (is (string= (goal14-json-value row "name")
                          (cadr-ai:provider-definition-name definition)))
             (is (eq (goal14-keyword (goal14-json-value row "protocol"))
                     (cadr-ai:provider-definition-protocol definition)))
             (is (equal (goal14-keyword-list
                         (goal14-json-value row "protocols"))
                        (goal14-private-provider-field
                         definition
                         'cadr-ai::provider-definition-protocols)))
             (is (string= (goal14-json-value row "baseUrl")
                          (cadr-ai:provider-definition-base-url definition)))
             (is (equal (goal14-keyword-list
                         (goal14-json-value row "authTypes"))
                        (cadr-ai:provider-definition-auth-types definition)))
             (is (string= (goal14-json-value row "defaultModel")
                          (cadr-ai:provider-definition-default-model definition)))
             (is (equal (goal14-json-value row "keyEnvironment")
                        (cadr-ai:provider-definition-key-environment definition)))
             (is (equal (goal14-json-list row "requiredEnvironment")
                        (cadr-ai:provider-definition-required-environment definition)))
             (is (eq (not (null (goal14-json-value row "dynamicModels")))
                     (cadr-ai:provider-definition-dynamic-models-p definition)))
             (is (eq (not (null (goal14-json-value row "supportsImages")))
                     (cadr-ai:provider-definition-supports-images-p definition)))
             (is (eq (not (null (goal14-json-value row "supportsTools")))
                     (cadr-ai:provider-definition-supports-tools-p definition)))
             (is (eq (not (null (goal14-json-value row "reasoning")))
                     (cadr-ai:provider-definition-reasoning-p definition)))
             (is (equal (goal14-json-value row "apiKeyName")
                        (goal14-private-provider-field
                         definition
                         'cadr-ai::provider-definition-api-key-name)))
             (is (equal (goal14-json-list row "environmentNames")
                        (goal14-private-provider-field
                         definition
                         'cadr-ai::provider-definition-environment-names)))
             (dolist (entry
                       '(("apiKeyAuthStrategy"
                          cadr-ai::provider-definition-api-key-auth-strategy)
                         ("oauthLoginStrategy"
                          cadr-ai::provider-definition-oauth-login-strategy)
                         ("oauthRefreshStrategy"
                          cadr-ai::provider-definition-oauth-refresh-strategy)
                         ("oauthToAuthStrategy"
                          cadr-ai::provider-definition-oauth-to-auth-strategy)
                         ("modelFilterStrategy"
                          cadr-ai::provider-definition-model-filter-strategy)))
               (destructuring-bind (field accessor) entry
                 (is (eq (goal14-keyword (goal14-json-value row field))
                         (goal14-private-provider-field definition accessor)))))
             (if metadata
                 (let ((actual
                         (cadr-ai::provider-definition-oauth-metadata
                          definition)))
                   (is (string= (goal14-json-value metadata "providerName")
                                (cadr-ai::oauth-provider-metadata-provider-name
                                 actual)))
                   (is (string= (goal14-json-value metadata "methodName")
                                (cadr-ai::oauth-provider-metadata-method-name
                                 actual)))
                   (is (equal (goal14-json-value metadata "loginLabel")
                              (cadr-ai::oauth-provider-metadata-login-label
                               actual)))
                   (is (equal
                        (goal14-json-value metadata "authUrlInstructions")
                        (cadr-ai::oauth-provider-metadata-auth-url-instructions
                         actual)))
                   (is (equal
                        (goal14-json-value metadata "manualInputMessage")
                        (cadr-ai::oauth-provider-metadata-manual-input-message
                         actual))))
                 (is (null (cadr-ai::provider-definition-oauth-metadata
                            definition)))))))

(test goal14-provider-declarations-own-runtime-decisions-once
  (is (= 40 (length cadr-ai::*built-in-provider-definition-rows*)))
  (is (= 40 (length (cadr-ai:list-provider-definitions))))
  (let* ((definitions (cadr-ai:list-provider-definitions))
         (declared
           (sort
            (remove-duplicates
             (loop for definition in definitions
                   for names =
                     (goal14-private-provider-field
                      definition
                      'cadr-ai::provider-definition-environment-names)
                   when (listp names)
                     append names)
             :test #'string=)
            #'string<))
         (runtime
           (sort (copy-list cadr-ai::+built-in-runtime-environment-names+)
                 #'string<)))
    (is (equal declared runtime)))
  (dolist (definition (cadr-ai:list-provider-definitions))
    (let ((auth-types (cadr-ai:provider-definition-auth-types definition)))
      (is (eq (not (null (member :api-key auth-types)))
              (not (null
                    (goal14-private-provider-field
                     definition
                     'cadr-ai::provider-definition-api-key-auth-strategy)))))
      (is (eq (not (null (member :oauth auth-types)))
              (not (null
                    (goal14-private-provider-field
                     definition
                     'cadr-ai::provider-definition-oauth-login-strategy))))))))

(test goal14-provider-auth-files-have-one-real-owner-each
  (dolist (relative +goal14-provider-owner-files+)
    (is (probe-file (fixture-path relative))))
  (dolist (relative +goal14-retired-provider-owner-files+)
    (is (not (probe-file (fixture-path relative)))))
  (let ((asd (read-fixture "cadr-ai.asd")))
    (dolist (name '("pkce" "callback" "page" "openai-anthropic"
                    "bedrock" "vertex" "device-code" "github-copilot"
                    "radius-cloudflare" "definitions" "registry"
                    "runtime-projection"))
      (is (search (format nil "(:file \"~A\")" name) asd)))
    (dolist (name '("oauth-flows" "oauth" "provider-auth" "independent"))
      (is (not (search (format nil "(:file \"~A\")" name) asd))))))
