(in-package #:cadr-evals/tests)

(in-suite cadr-evals-suite)

(defun artifact-test-file-text (path)
  (uiop:read-file-string
   path :external-format :utf-8))

(test eval-artifacts-record-session-and-source
  (let* ((metadata
           (cadr-ai::json-object
            "runId" "run-1"
            cadr-evals:+cadr-session-snapshot-artifact+
            "{\"type\":\"session\"}\n"))
         (session
           (cadr-evals:record-eval-session-artifact
            metadata))
         (source
           (cadr-evals:record-eval-source-artifact
            "run-1"
            (cadr-evals:make-eval-attachment
             :name "hello.lisp"
             :content-type "text/x-common-lisp"
             :body "(define-tool \"hello\")\n"))))
    (is (eq :session
            (cadr-evals:eval-artifact-type
             session)))
    (is (string=
         "run-1"
         (cadr-evals:eval-artifact-run-id
          session)))
    (is (string=
         "session.jsonl"
         (cadr-evals:eval-attachment-name
          (first
           (cadr-evals:eval-artifact-attachments
            session)))))
    (is (eq :source
            (cadr-evals:eval-artifact-type
             source)))
    (is (string=
         "hello.lisp"
         (cadr-evals:eval-attachment-name
          (first
           (cadr-evals:eval-artifact-attachments
            source)))))))

(test eval-artifacts-persist-only-the-reported-run
  (let ((root (cadr-evals::make-eval-root)))
    (unwind-protect
         (let* ((artifacts
                  (list
                   (cadr-evals:record-eval-session-artifact
                    (cadr-ai::json-object
                     "runId" "run-1"
                     cadr-evals:+cadr-session-snapshot-artifact+
                     "{\"type\":\"session\"}\n"))
                   (cadr-evals:make-eval-artifact
                    :type :session
                    :run-id "run-2"
                    :attachments nil)
                   (cadr-evals:record-eval-source-artifact
                    "run-1"
                    (cadr-evals:make-eval-attachment
                     :name "hello.lisp"
                     :content-type "text/x-common-lisp"
                     :body "(define-tool \"hello\")\n"))
                   (cadr-evals:make-eval-artifact
                    :type :annotation
                    :run-id "run-1"
                    :attachments nil)))
                (references
                  (cadr-evals:persist-eval-artifact-references
                   artifacts "run-1" root)))
           (is (= 2 (length references)))
           (let ((session (first references))
                 (source (second references)))
             (is (string=
                  "session.jsonl"
                  (cadr-evals:eval-artifact-reference-name
                   session)))
             (is (cl-ppcre:scan
                  "^sessions/[a-f0-9]{64}/session\\.jsonl$"
                  (cadr-evals:eval-artifact-reference-path
                   session)))
             (is (string=
                  "hello.lisp"
                  (cadr-evals:eval-artifact-reference-name
                   source)))
             (is (cl-ppcre:scan
                  "^sources/[a-f0-9]{64}/hello\\.lisp$"
                  (cadr-evals:eval-artifact-reference-path
                   source)))
             (is (string=
                  "{\"type\":\"session\"}\n"
                  (artifact-test-file-text
                   (merge-pathnames
                    (cadr-evals:eval-artifact-reference-path
                     session)
                    root))))
             (is (string=
                  "(define-tool \"hello\")\n"
                  (artifact-test-file-text
                   (merge-pathnames
                    (cadr-evals:eval-artifact-reference-path
                     source)
                    root))))))
      (when (probe-file root)
        (uiop:delete-directory-tree
         root :validate t
         :if-does-not-exist :ignore)))))

(test eval-artifacts-reject-invalid-metadata-and-path-names
  (signals type-error
    (cadr-evals:record-eval-session-artifact
     (cadr-ai::json-object
      "runId" 1
      cadr-evals:+cadr-session-snapshot-artifact+
      "session")))
  (signals type-error
    (let ((root (cadr-evals::make-eval-root)))
      (unwind-protect
           (cadr-evals:persist-eval-artifact-references
            (list
             (cadr-evals:record-eval-source-artifact
              "run"
              (cadr-evals:make-eval-attachment
               :name "../escape.lisp"
               :content-type "text/plain"
               :body "escape")))
            "run" root)
        (when (probe-file root)
          (uiop:delete-directory-tree
           root :validate t
           :if-does-not-exist :ignore))))))
