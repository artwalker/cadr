(asdf:defsystem "cadr-durable"
  :description "Durable conversations, documents, and tasks."
  :depends-on ("cadr-chord" "cadr-telemetry" "sb-posix")
  :serial t
  :components ((:module "src/cadr-durable"
                :components
                ((:file "package")
                 (:file "errors")
                 (:file "state")
                 (:file "backends")
                 (:file "session")
                 (:file "harness")
                 (:file "tools")
                 (:file "codemode")
                 (:file "telemetry")))))
