(defpackage #:cadr-evals
  (:use #:cl)
  (:export
   #:eval-result
   #:eval-result-output
   #:eval-result-events
   #:eval-result-usage
   #:eval-result-errors
   #:make-eval-prompt-step
   #:make-eval-reload-step
   #:run-coding-agent-eval
   #:run-smoke-eval
   #:run-extension-eval
   #:eval-main))
