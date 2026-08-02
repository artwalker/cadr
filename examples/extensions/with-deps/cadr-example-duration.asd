(asdf:defsystem "cadr-example-duration"
  :description "Local dependency used by the Goal 12 extension example"
  :version "1.0.0"
  :depends-on ("cl-ppcre")
  :serial t
  :components ((:file "duration")))
