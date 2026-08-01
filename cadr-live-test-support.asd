(asdf:defsystem "cadr-live-test-support"
  :description "Shared live-test credential support for cadr"
  :depends-on ("cadr-cli")
  :serial t
  :components ((:file "test/cadr-live-support")))
