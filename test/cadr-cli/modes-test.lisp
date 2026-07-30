(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defun cli-test-assistant
    (text &optional (stop-reason :stop)
                    error-message)
  (cadr-ai:make-assistant-message
   :content
   (and text
        (list
         (cadr-ai:make-text-content :text text)))
   :api :openai-responses
   :provider :openai
   :model "mock"
   :stop-reason stop-reason
   :error-message error-message))

(defun cli-faux-agent (responses)
  (let ((remaining (copy-list responses)))
    (values
     (cadr-agent:make-agent
      :provider :mock
      :model
      (cadr-ai:make-model
       :id "mock"
       :provider :openai
       :api :openai-responses
       :base-url "https://example.invalid"
       :max-tokens 1024)
      :stream-function
      (lambda
          (provider model context on-event
           &key max-tokens temperature abort-p)
        (declare
         (ignore
          provider model context
          max-tokens temperature abort-p))
        (let ((message (pop remaining)))
          (funcall
           on-event
           (cadr-ai:make-stream-event
            :type :start :message message))
          (dolist
              (block
               (cadr-ai:assistant-message-content message))
            (when
                (typep block 'cadr-ai:text-content)
              (funcall
               on-event
               (cadr-ai:make-stream-event
                :type :text-delta
                :delta
                (cadr-ai:text-content-text block)
                :message message))))
          message)))
     (lambda () remaining))))

(test cli-mode-arguments-and-priority-match-the-reference
  (let ((arguments
          (cadr-cli::parse-cli-arguments
           '("--print"
             "--mode" "json"
             "first"
             "second"))))
    (is (cadr-cli::cli-arguments-print-p arguments))
    (is (eq :json
            (cadr-cli::cli-arguments-mode arguments)))
    (is (equal '("first" "second")
               (cadr-cli::cli-arguments-messages
                arguments)))
    (is
     (eq
      :json
      (cadr-cli::resolve-cli-mode
       arguments t t)))
    (is
     (eq
      :text
      (cadr-cli::resolve-cli-mode
       (cadr-cli::parse-cli-arguments nil)
       nil t)))
    (is
     (eq
      :text
      (cadr-cli::resolve-cli-mode
       (cadr-cli::parse-cli-arguments nil)
       t nil)))
    (is
     (eq
      :repl
      (cadr-cli::resolve-cli-mode
       (cadr-cli::parse-cli-arguments
        '("--no-tui"))
       nil nil)))
    (is
     (eq
      :tui
      (cadr-cli::resolve-cli-mode
       (cadr-cli::parse-cli-arguments nil)
       t t))))
  (signals cadr-ai:configuration-error
    (cadr-cli::parse-cli-arguments
     '("--mode" "yaml"))))

(test piped-stdin-merges-with-only-the-first-cli-message
  (let ((arguments
          (cadr-cli::parse-cli-arguments
           '("Explain it" "Second message"))))
    (multiple-value-bind (initial remaining)
        (cadr-cli::build-cli-print-prompts
         arguments "stdin contents")
      (is
       (string=
        (format nil "stdin contents~%Explain it")
        initial))
      (is (equal '("Second message") remaining))))
  (multiple-value-bind (initial remaining)
      (cadr-cli::build-cli-print-prompts
       (cadr-cli::parse-cli-arguments nil)
       "stdin only")
    (is (string= "stdin only" initial))
    (is (null remaining))))

(test print-mode-emits-only-final-text-and-propagates-errors
  (multiple-value-bind (agent remaining)
      (cli-faux-agent
       (list
        (cli-test-assistant "first")
        (cli-test-assistant "final")))
    (let ((output (make-string-output-stream))
          (errors (make-string-output-stream)))
      (is
       (= 0
          (cadr-cli::run-print-mode
           agent "one" '("two")
           :mode :text
           :output output
           :error-output errors)))
      (is (string=
           (format nil "final~%")
           (get-output-stream-string output)))
      (is (string=
           ""
           (get-output-stream-string errors)))
      (is (null (funcall remaining)))))
  (multiple-value-bind (agent remaining)
      (cli-faux-agent
       (list
        (cli-test-assistant
         nil :error "provider failed")))
    (declare (ignore remaining))
    (let ((output (make-string-output-stream))
          (errors (make-string-output-stream)))
      (is
       (= 1
          (cadr-cli::run-print-mode
           agent "one" nil
           :mode :text
           :output output
           :error-output errors)))
      (is (string= ""
                   (get-output-stream-string output)))
      (is (search
           "provider failed"
           (get-output-stream-string errors))))))

(test json-mode-emits-one-valid-json-object-per-line
  (multiple-value-bind (agent remaining)
      (cli-faux-agent
       (list (cli-test-assistant "done")))
    (declare (ignore remaining))
    (let ((output (make-string-output-stream))
          (errors (make-string-output-stream)))
      (is
       (= 0
          (cadr-cli::run-print-mode
           agent "one" nil
           :mode :json
           :output output
           :error-output errors)))
      (let ((records
              (loop
                for line in
                (uiop:split-string
                 (get-output-stream-string output)
                 :separator '(#\Newline))
                unless (zerop (length line))
                  collect (cadr-ai::parse-json line))))
        (is (equal
             '("agent_start"
               "turn_start"
               "message_start"
               "message_end"
               "message_start"
               "message_update"
               "message_end"
               "turn_end"
               "agent_end")
             (loop for record in records
                   collect
                   (cadr-ai::json-get
                    record "type")))))
      (is (string=
           ""
           (get-output-stream-string errors))))))
