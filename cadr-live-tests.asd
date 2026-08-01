(asdf:defsystem "cadr-live-tests"
  :description "Aggregated credential-gated live tests for cadr"
  :depends-on ("fiveam"
               "cadr-live-test-support"
               "cadr-ai/live-tests"
               "cadr-cli/live-tests"
               "cadr-evals/live-tests")
  :serial t
  :components ((:module "test/cadr-live"
                :serial t
                :components ((:file "package")
                             (:file "runner")))))
