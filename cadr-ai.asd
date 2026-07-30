(asdf:defsystem "cadr-ai"
  :description "Common Lisp provider layer for cadr"
  :version "0.1.0"
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
                             (:file "sse")
                             (:file "http")
                             (:file "provider")
                             (:file "registry")
                             (:file "auth")
                             (:file "oauth")
                             (:module "providers"
                              :serial t
                              :components ((:file "anthropic")
                                           (:file "openai")
                                           (:file "openai-completions")
                                           (:file "google"))))))
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
                             (:file "json-test")
                             (:file "sse-test")
                             (:file "http-test")
                             (:file "provider-payloads-test")
                             (:file "provider-history-test")
                             (:file "provider-responses-test")
                             (:file "provider-streams-test")
                             (:file "retry-test")
                             (:file "provider-registry-test")
                             (:file "openai-completions-test")
                             (:file "image-model-test")
                             (:file "auth-test"))))
  :perform (test-op (operation component)
             (declare (ignore operation component))
             (unless (uiop:symbol-call :cadr-ai/tests :run-tests)
               (error "cadr-ai tests failed"))))
