(asdf:defsystem "cadr-chord"
  :description "Host runtime for contracts, replicated JSON, and JSON links"
  :version (:read-file-form "version.sexp")
  :license "MIT"
  :depends-on ("sqlite")
  :serial t
  :components ((:module "src/cadr-chord"
                :serial t
                :components ((:file "package")
                             (:file "errors")
                             (:file "json")
                             (:file "schema")
                             (:file "contract")
                             (:file "delta")
                             (:file "link")
                             (:file "host")
                             (:file "manager")
                             (:file "sqlite")))))
