(asdf:defsystem "cadr-telemetry"
  :description "Span, metric, and trace contracts with no-op and in-memory adapters"
  :version (:read-file-form "version.sexp")
  :license "MIT"
  :depends-on ("cadr-core")
  :serial t
  :components ((:module "src/cadr-telemetry"
                :serial t
                :components ((:file "package")
                             (:file "clock")
                             (:file "noop")
                             (:file "memory")
                             (:file "render")
                             (:file "schema")))))
