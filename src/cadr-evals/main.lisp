(in-package #:cadr-evals)

(defun argument-after-prefix (argument prefix)
  ;; One owner of --flag= . Baseline run-evals.mjs:36-44 copies
  ;; startsWith+slice per option and recomputes the prefix length
  ;; each time. Empty suffix stays unknown: the baseline only
  ;; slices when the argument is longer than the prefix.
  (let ((prefix-length (length prefix)))
    (when (and (> (length argument) prefix-length)
               (string= prefix argument :end2 prefix-length))
      (subseq argument prefix-length))))

(defun parse-eval-arguments (arguments)
  (let ((provider nil)
        (model nil)
        (suite "smoke"))
    (loop
      while arguments
      for argument = (pop arguments)
      do
         (cond
           ((string= argument
                     "--provider")
            (unless arguments
              (error
               "Missing value for --provider"))
            (setf provider
                  (pop arguments)))
           ((string= argument
                     "--model")
            (unless arguments
              (error
               "Missing value for --model"))
            (setf model
                  (pop arguments)))
           ((string= argument
                     "--suite")
            (unless arguments
              (error
               "Missing value for --suite"))
            (setf suite
                  (pop arguments)))
           ((let ((value
                    (argument-after-prefix
                     argument "--provider=")))
              (when value
                (setf provider value)
                t)))
           ((let ((value
                    (argument-after-prefix
                     argument "--model=")))
              (when value
                (setf model value)
                t)))
           ((let ((value
                    (argument-after-prefix
                     argument "--suite=")))
              (when value
                (setf suite value)
                t)))
           (t
            (error
             "Unknown eval argument: ~A"
             argument))))
    (values provider model suite)))

(defun validate-smoke-result (result)
  (unless
      (string=
       "Paris"
       (string-trim
        '(#\Space #\Tab
          #\Newline #\Return)
        (eval-result-output
         result)))
    (error
     "Smoke eval expected Paris, got ~S"
     (eval-result-output result)))
  (unless
      (plusp
       (cadr-ai::json-get
        (eval-result-usage result)
        "totalTokens"))
    (error
     "Smoke eval reported no token usage"))
  result)

(defun validate-extension-result (result)
  (let ((output
          (eval-result-output
           result)))
    (unless
        (string=
         "Hello, Bob!"
         (cadr-ai::json-get
          output "response"))
      (error
       "Extension eval greeting mismatch: ~S"
       (cadr-ai::json-get
        output "response")))
    (unless
        (= 1
           (length
            (cadr-ai::json-get
             output
             "extensionPaths")))
      (error
       "Extension eval did not load exactly one extension")))
  result)

(defun %eval-main ()
  (handler-case
      (multiple-value-bind
            (provider model suite)
          (parse-eval-arguments
           (uiop:command-line-arguments))
        (let ((value
                (cond
                  ((string= suite
                            "smoke")
                   (validate-smoke-result
                    (run-smoke-eval
                     :provider provider
                     :model model)))
                  ((string= suite
                            "extensions")
                   (validate-extension-result
                    (run-extension-eval
                     :provider provider
                     :model model)))
                  ((string= suite
                            "extension-authoring")
                   (run-extension-authoring-eval-suite
                    :provider provider
                    :model model))
                  (t
                   (error
                    "Unknown eval suite: ~A"
                    suite)))))
          (write-line
           (cadr-ai::stringify-json
            (if (typep value 'eval-result)
                (eval-result-json value)
                value)))
          (finish-output)))
    (error (cause)
      (format
       *error-output*
       "cadr-evals: ~A~%"
       cause)
      (finish-output
       *error-output*)
      (uiop:quit 1))))

(defun eval-main ()
  (cadr-cli::call-with-fatal-condition-boundary
   #'%eval-main
   :program-name "cadr-evals"))
