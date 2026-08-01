(asdf:defsystem "cadr-ai"
  :description "Common Lisp provider layer for cadr"
  :version (:read-file-form "version.sexp")
  :license "MIT"
  :depends-on ("cl+ssl")
  :serial t
  :components ((:module "src/cadr-ai"
                :serial t
                :components ((:file "package")
                             (:file "conditions")
                             (:file "types")
                             (:file "json")
                             (:file "models")
                             (:file "models.generated")
                             (:file "image-models.generated")
                             (:file "utilities")
                             (:file "capabilities")
                             (:file "sse")
                             (:file "http")
                             (:file "provider")
                             (:file "auth")
                             (:file "oauth")
                             (:file "models-runtime")
                             (:file "crypto")
                             (:file "provider-auth")
                             (:file "registry")
                             (:file "images")
                             (:module "providers"
                              :serial t
                              :components ((:file "anthropic")
                                           (:file "openai")
                                           (:file "openai-completions")
                                           (:file "google")
                                           (:file "independent"))))))
  :in-order-to ((test-op (test-op "cadr-ai/tests"))))

(asdf:defsystem "cadr-ai/tests"
  :description "Tests for cadr-ai"
  :depends-on ("fiveam"
               "cadr-ai"
               "babel"
               "bordeaux-threads"
               "flexi-streams"
               "usocket"
               "trivial-gray-streams")
  :serial t
  :components ((:module "test/cadr-ai"
                :serial t
                :components ((:file "package")
                             (:file "helpers")
                             (:file "types-test")
                             (:file "utilities-test")
                             (:file "json-test")
                             (:file "sse-test")
                             (:file "http-test")
                             (:file "provider-payloads-test")
                             (:file "provider-compat-test")
                             (:file "provider-history-test")
                             (:file "provider-responses-test")
                             (:file "provider-streams-test")
                             (:file "retry-test")
                             (:file "provider-registry-test")
                             (:file "provider-wave1-test")
                             (:file "provider-wave3-test")
                             (:file "bedrock-error-metadata-test")
                             (:file "models-runtime-test")
                             (:file "faux-provider-test")
                             (:file "openai-completions-test")
                             (:file "image-model-test")
                             (:file "image-generation-test")
                             (:file "auth-test")
                             (:file "goal12-capabilities-test")
                             (:file "goal12-provider-capabilities-test"))))
  :perform (test-op (operation component)
             (declare (ignore operation component))
             (unless (uiop:symbol-call :cadr-ai/tests :run-tests)
               (error "cadr-ai tests failed"))))

(asdf:defsystem "cadr-ai/live-tests"
  :description "Credential-gated live tests for cadr-ai"
  :depends-on ("fiveam" "cadr-ai")
  :serial t
  :components ((:module "test/cadr-ai"
                :serial t
                :components ((:file "live-package")
                             (:file "live-provider-test")))))
