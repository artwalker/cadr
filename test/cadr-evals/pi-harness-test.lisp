(in-package #:cadr-evals/tests)

(in-suite cadr-evals-suite)

(test eval-selection-prefers-explicit-and-trims-environment-defaults
  (let ((cadr-evals::*eval-environment-function*
          (lambda (name)
            (cond
              ((string= name "CADR_EVAL_PROVIDER")
               " openai-codex ")
              ((string= name "CADR_EVAL_MODEL")
               " gpt-5.6-sol ")
              (t nil)))))
    (multiple-value-bind
          (provider model)
        (cadr-evals::resolve-eval-selection
         "anthropic" "claude-opus-4-6")
      (is (string= "anthropic" provider))
      (is (string= "claude-opus-4-6" model)))
    (multiple-value-bind
          (provider model)
        (cadr-evals::resolve-eval-selection
         nil nil)
      (is (string= "openai-codex" provider))
      (is (string= "gpt-5.6-sol" model)))
    (signals cadr-ai:configuration-error
      (cadr-evals::resolve-eval-selection
       "" "gpt-5.6-sol"))))

(test goal16-eval-selection-does-not-read-retired-pi-names
  (let ((cadr-evals::*eval-environment-function*
          (lambda (name)
            (cond
              ((string= name "PI_PROVIDER") "deepseek")
              ((string= name "PI_MODEL") "deepseek-chat")
              (t nil)))))
    (signals cadr-ai:configuration-error
      (cadr-evals::resolve-eval-selection nil nil))))

(test eval-system-prompt-transform-is-applied-and-must-not-be-empty
  (with-faux-eval
      (handle
       (list
        (cadr-ai:faux-assistant-message
         "ok")))
    (let ((result
            (cadr-evals:run-coding-agent-eval
             "hello"
             :provider "faux"
             :model "faux-1"
             :no-tools :all
             :transform-system-prompt
             (lambda (prompt)
               (format nil "~A~%EVAL SENTINEL"
                       prompt))
             :selector
             (lambda (response agent manager)
               (declare (ignore response manager))
               (cadr-agent::agent-system-prompt
                agent)))))
      (is (search
           "EVAL SENTINEL"
           (cadr-evals:eval-result-output
            result)))))
  (with-faux-eval
      (handle
       (list
        (cadr-ai:faux-assistant-message
         "unused")))
    (signals error
      (cadr-evals:run-coding-agent-eval
       "hello"
       :provider "faux"
       :model "faux-1"
       :transform-system-prompt
       (constantly "   ")))))

(test coding-agent-eval-harness-binds-name-model-and-native-artifacts
  (with-faux-eval
      (handle
       (list
        (cadr-ai:faux-assistant-message
         "bound")))
    (let* ((harness
             (cadr-evals:make-coding-agent-eval-harness
              :name "bound-faux"
              :provider "faux"
              :model "faux-1"
              :no-tools :all))
           (result
             (cadr-evals:run-eval-harness
              harness "hello")))
      (is (string=
           "bound-faux"
           (cadr-evals:eval-harness-name
            harness)))
      (is (string=
           "bound"
           (cadr-evals:eval-result-output
            result)))
      (is (stringp
           (cadr-ai::json-get
            (cadr-evals:eval-result-artifacts
             result)
            cadr-evals:+cadr-session-snapshot-artifact+))))))
