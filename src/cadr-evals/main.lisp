(in-package #:cadr-evals)

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
           ((and
             (> (length argument)
                (length "--provider="))
             (string=
              "--provider="
              argument
              :end2
              (length "--provider=")))
            (setf provider
                  (subseq
                   argument
                   (length "--provider="))))
           ((and
             (> (length argument)
                (length "--model="))
             (string=
              "--model="
              argument
              :end2
              (length "--model=")))
            (setf model
                  (subseq
                   argument
                   (length "--model="))))
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

(defun eval-main ()
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
