(asdf:defsystem "cadr-protocol"
  :description "Strict CBOR remote-session protocol for cadr"
  :version "0.1.0"
  :license "MIT"
  :serial t
  :components ((:module "src/cadr-protocol"
                :serial t
                :components ((:file "package")
                             (:file "cbor")
                             (:file "framing")
                             (:file "schema")
                             (:file "codec"))))
  :in-order-to ((test-op (test-op "cadr-protocol/tests"))))

(asdf:defsystem "cadr-protocol/tests"
  :description "Tests for cadr-protocol"
  :depends-on ("fiveam" "cadr-protocol")
  :serial t
  :components ((:module "test/cadr-protocol"
                :serial t
                :components ((:file "package")
                             (:file "cbor-test")
                             (:file "framing-test")
                             (:file "protocol-test"))))
  :perform (test-op (operation component)
             (declare (ignore operation component))
             (unless (uiop:symbol-call
                      :cadr-protocol/tests
                      :run-tests)
               (error "cadr-protocol tests failed"))))
