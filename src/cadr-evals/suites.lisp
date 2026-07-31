(in-package #:cadr-evals)

(defun run-smoke-eval
    (&key provider model)
  (run-coding-agent-eval
   "What's the capital of France? Respond with only the city name."
   :provider provider
   :model model
   :no-tools :all))

(defun run-extension-eval
    (&key provider model)
  (run-coding-agent-eval
   (list
    (make-eval-prompt-step
     "Create a cadr extension with a hello tool that takes a name and returns a greeting. For example, passing Bob should return `Hello, Bob!`.")
    (make-eval-reload-step)
    (make-eval-prompt-step
     "Use the hello tool to greet Bob."))
   :provider provider
   :model model
   :selector
   (lambda (response agent manager)
     (declare (ignore manager))
     (cadr-ai::json-object
      "response" response
      "extensionPaths"
      (cadr-ai::list-json-array
       (eval-extension-paths agent))
      "toolDefinitions"
      (cadr-ai::list-json-array
       (mapcar
        (lambda (tool)
          (cadr-ai::json-object
           "name"
           (cadr-ai:tool-name tool)
           "description"
           (cadr-ai:tool-description
            tool)))
        (eval-agent-tools
         agent)))))))
