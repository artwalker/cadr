(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(test cadr-system-and-package-names-are-the-only-public-names
  (dolist (name '("cadr-ai" "cadr-agent" "cadr-tui" "cadr-cli"))
    (is (asdf:find-system name nil))
    (is (find-package (string-upcase name))))
  (dolist (suffix '("ai" "agent" "tui" "cli"))
    (let ((name (format nil "~C~C-~A" #\p #\i suffix)))
      (is (null (asdf:find-system name nil)))
      (is (null (find-package (string-upcase name)))))))

(test cadr-extension-api-is-exported-from-the-frozen-agent-package
  (dolist (name '("DEFINE-TOOL"
                  "DEFINE-COMMAND"
                  "DEFINE-EVENT-HOOK"
                  "DEFINE-PROMPT-TEMPLATE"))
    (multiple-value-bind (symbol status)
        (find-symbol name "CADR-AGENT")
      (is (symbolp symbol))
      (is (eq :external status)))))

(test exported-error-root-uses-the-cadr-name
  (multiple-value-bind (symbol status)
      (find-symbol "CADR-ERROR" "CADR-AI")
    (is (symbolp symbol))
    (is (eq :external status)))
  (is (null
       (find-symbol
        (format nil "~C~C-ERROR" #\P #\I)
        "CADR-AI"))))

(test reference-payload-runner-keeps-typescript-api-type-names
  (let* ((root
           (asdf:system-source-directory "cadr-cli"))
         (runner
           (read-text
            (merge-pathnames
             "scripts/export-ts-payloads.runner.ts.txt"
             root))))
    (is (search "TApi extends Api" runner))
    (is (search "Model<TApi>" runner))
    (is (null (search "Acadr" runner)))
    (is (null (search "TAcadr" runner)))))
