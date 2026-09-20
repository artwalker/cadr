(asdf:defsystem "cadr-ai"
  :description "Common Lisp provider layer for cadr"
  :version (:read-file-form "version.sexp")
  :license "MIT"
  :depends-on ("cl+ssl"
               "cadr-core")
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
                             (:module "support"
                              :serial t
                              :components ((:file "threads")
                                           (:file "release")
                                           (:file "retry")
                                           (:file "token-estimation")
                                           (:file "overflow")
                                           (:file "grammar-coercion")
                                           (:file "uuid")
                                           (:file "attribution")
                                           (:file "transcript")))
                             (:module "capabilities"
                              :serial t
                              :components ((:file "streaming-json")
                                           (:file "event-stream")
                                           (:file "grammar-tools")
                                           (:file "session-resources")
                                           (:file "proxy-config")
                                           (:file "image-runtime")))
                             (:file "sse")
                             (:module "transport"
                              :serial t
                              :components ((:file "http")
                                           (:file "aws-event-stream")))
                             (:file "provider")
                             (:file "auth")
                             (:module "oauth-core"
                              :pathname "oauth"
                              :serial t
                              :components ((:file "pkce")
                                           (:file "callback")
                                           (:file "page")
                                           (:file "openai-anthropic")))
                             (:module "runtime"
                              :serial t
                              :components ((:file "models")
                                           (:file "faux-provider")))
                             (:file "crypto")
                             (:file "model-data")
                             (:module "auth-implementations"
                              :pathname "auth"
                              :serial t
                              :components ((:file "bedrock")
                                           (:file "vertex")
                                           (:file "device-code")
                                           (:file "github-copilot")
                                           (:file "radius-cloudflare")))
                             (:module "oauth-providers"
                              :pathname "oauth/providers"
                              :serial t
                              :components ((:file "xai")
                                           (:file "kimi")
                                           (:file "github-copilot")
                                           (:file "openrouter")
                                           (:file "radius")
                                           (:file "openai-device")
                                           (:file "anthropic")))
                             (:file "images")
                             (:module "providers"
                              :serial t
                              :components ((:file "anthropic")
                                           (:file "openai")
                                           (:file "openai-completions")
                                           (:file "google")
                                           (:file "azure-openai")
                                           (:file "codex")
                                           (:file "mistral")
                                           (:file "vertex")
                                           (:file "bedrock")
                                           (:file "pi-messages")
                                           (:file "definitions")
                                           (:file "registry")
                                           (:file "runtime-projection")))
                             (:file "websocket")
                             (:file "crash"))))
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
                             (:file "goal28-http-idle-stream-test")
                             (:file "provider-payloads-test")
                             (:file "provider-compat-test")
                             (:file "anthropic-mid-conversation-effort-test")
                             (:file "google-thinking-level-map-test")
                             (:file "provider-history-test")
                             (:file "provider-responses-test")
                             (:file "provider-streams-test")
                             (:file "goal24-transcript-context-stream-test")
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
                             (:file "goal12-provider-capabilities-test")
                             (:file "goal14-provider-organization-test")
                             (:file "goal12-auth-test")
                             (:file "goal18-auth-test")
                             (:file "goal12-model-data-test")
                             (:file "goal12-codex-websocket-test")
                             (:file "goal20-websocket-test")
                             (:file "goal20-stream-accumulation-test")
                             (:file "goal20-json-parse-windows-test"))))
  :perform (test-op (operation component)
             (declare (ignore operation component))
             (unless (uiop:symbol-call :cadr-ai/tests :run-tests)
               (error "cadr-ai tests failed"))))

(asdf:defsystem "cadr-ai/live-tests"
  :description "Credential-gated live tests for cadr-ai"
  :depends-on ("fiveam" "cadr-ai" "cadr-live-test-support")
  :serial t
  :components ((:module "test/cadr-ai"
                :serial t
                :components ((:file "live-package")
                             (:file "live-provider-test")
                             (:file "opencode-go-live-test")))))
