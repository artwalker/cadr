(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(test repl-consumes-multiple-lines-and-streams-text
  (let ((prompts nil)
        (output (make-string-output-stream)))
    (run-repl
     (lambda (prompt)
       (push prompt prompts)
       (cadr-ai:make-assistant-message
        :content
        (list (cadr-ai:make-text-content
               :text (string-upcase prompt)))
        :api :openai-responses
        :provider :openai
        :model "mock"
        :stop-reason :stop))
     :input
     (make-string-input-stream
      (format nil "hello~%~%world~%"))
     :output output)
    (is (equal '("hello" "world") (nreverse prompts)))
    (let ((text (get-output-stream-string output)))
      (is (search "cadr> " text))
      (is (search "assistant> HELLO" text))
      (is (search "assistant> WORLD" text)))))

(test repl-runs-a-faux-provider-through-real-read-edit-and-bash-tools
  (with-test-directory (directory)
    (write-text
     (merge-pathnames "calc.lisp" directory)
     (format nil "(defun add (a b) (- a b))~%"))
    (labels
        ((assistant (content &optional (stop-reason :stop))
           (cadr-ai:make-assistant-message
            :content content
            :api :openai-responses
            :provider :openai
            :model "mock"
            :stop-reason stop-reason)))
      (let* ((responses
               (list
                (assistant
                 (list
                  (cadr-ai:make-tool-call
                   :id "read-1"
                   :name "read"
                   :arguments (args "path" "calc.lisp")))
                 :tool-use)
                (assistant
                 (list
                  (cadr-ai:make-tool-call
                   :id "edit-1"
                   :name "edit"
                   :arguments
                   (args
                    "path" "calc.lisp"
                    "edits"
                    (vector
                     (args
                      "oldText" "(- a b)"
                      "newText" "(+ a b)")))))
                 :tool-use)
                (assistant
                 (list
                  (cadr-ai:make-tool-call
                   :id "bash-1"
                   :name "bash"
                   :arguments
                   (args
                    "command"
                    "grep -Fq '(+ a b)' calc.lisp")))
                 :tool-use)
                (assistant
                 (list
                  (cadr-ai:make-text-content :text "fixed")))))
             (model
               (cadr-ai:make-model
                :id "mock"
                :provider :openai
                :api :openai-responses
                :base-url "https://example.invalid"
                :max-tokens 1024))
             (agent
               (cadr-agent:make-agent
                :provider :mock
                :model model
                :tools (cadr-cli:make-coding-tools directory)
                :stream-function
                (lambda (provider stream-model context on-event
                         &key max-tokens temperature abort-p)
                  (declare
                   (ignore provider stream-model context max-tokens
                           temperature abort-p))
                  (let ((message (pop responses)))
                    (funcall
                     on-event
                     (cadr-ai:make-stream-event
                      :type :start :message message))
                    (dolist
                        (block
                         (cadr-ai:assistant-message-content message))
                      (when (typep block 'cadr-ai:text-content)
                        (funcall
                         on-event
                         (cadr-ai:make-stream-event
                          :type :text-delta
                          :delta (cadr-ai:text-content-text block)
                          :message message))))
                    (funcall
                     on-event
                     (cadr-ai:make-stream-event
                      :type :done :message message
                      :reason
                      (cadr-ai:assistant-message-stop-reason
                       message)))
                    message))))
             (output (make-string-output-stream)))
        (run-repl
         (lambda (prompt)
           (cadr-agent:agent-prompt agent prompt))
         :input
         (make-string-input-stream (format nil "fix it~%"))
         :output output)
        (is (string=
             (format nil "(defun add (a b) (+ a b))~%")
             (read-text (merge-pathnames "calc.lisp" directory))))
        (is (= 8 (length (cadr-agent:agent-messages agent))))
        (is (null responses))
        (is (search "assistant> fixed"
                    (get-output-stream-string output)))))))

(test event-renderer-streams-each-delta-and-reports-terminal-errors-once
  (let* ((output (make-string-output-stream))
         (renderer (cadr-cli::make-agent-event-renderer output))
         (message
           (cadr-ai:make-assistant-message
            :api :openai-responses
            :provider :openai
            :model "mock")))
    (funcall
     renderer
     (cadr-agent::make-agent-event
      :type :message-start :message message))
    (funcall
     renderer
     (cadr-agent::make-agent-event
      :type :message-update
      :message message
      :stream-event
      (cadr-ai:make-stream-event
       :type :text-delta :delta "hel" :message message)))
    (funcall
     renderer
     (cadr-agent::make-agent-event
      :type :message-update
      :message message
      :stream-event
      (cadr-ai:make-stream-event
       :type :text-delta :delta "lo" :message message)))
    (funcall
     renderer
     (cadr-agent::make-agent-event
      :type :message-end :message message))
    (let ((error-message
            (cadr-ai:make-assistant-message
             :api :openai-responses
             :provider :openai
             :model "mock"
             :stop-reason :error
             :error-message "network down")))
      (funcall
       renderer
       (cadr-agent::make-agent-event
        :type :message-start :message error-message))
      (funcall
       renderer
       (cadr-agent::make-agent-event
        :type :message-end :message error-message)))
    (let ((text (get-output-stream-string output)))
      (is (search "assistant> hello" text))
      (is (= 1
             (count-substring "network down" text))))))

(test faux-repo-task-observes-failing-test-fixes-and-passes
  (with-test-directory (directory)
    (write-text
     (merge-pathnames "calc.lisp" directory)
     (format nil "(defun add (a b) (- a b))~%"))
    (labels
        ((assistant (content &optional (stop-reason :stop))
           (cadr-ai:make-assistant-message
            :content content
            :api :openai-responses
            :provider :openai
            :model "mock"
            :stop-reason stop-reason))
         (call (id name arguments)
           (assistant
            (list
             (cadr-ai:make-tool-call
              :id id :name name :arguments arguments))
            :tool-use)))
      (let* ((responses
               (list
                (call "read" "read"
                      (args "path" "calc.lisp"))
                (call
                 "wrong-edit" "edit"
                 (args
                  "path" "calc.lisp"
                  "edits"
                  (vector
                   (args "oldText" "(- a b)"
                         "newText" "(* a b)"))))
                (call
                 "failing-test" "bash"
                 (args
                  "command"
                  "grep -Fq '(+ a b)' calc.lisp"))
                (call
                 "fix-edit" "edit"
                 (args
                  "path" "calc.lisp"
                  "edits"
                  (vector
                   (args "oldText" "(* a b)"
                         "newText" "(+ a b)"))))
                (call
                 "passing-test" "bash"
                 (args
                  "command"
                  "grep -Fq '(+ a b)' calc.lisp"))
                (assistant
                 (list
                  (cadr-ai:make-text-content
                   :text "tests pass")))))
             (model
               (cadr-ai:make-model
                :id "mock"
                :provider :openai
                :api :openai-responses
                :base-url "https://example.invalid"
                :max-tokens 1024))
             (agent
               (cadr-agent:make-agent
                :provider :mock
                :model model
                :tools (cadr-cli:make-coding-tools directory)
                :stream-function
                (lambda (provider stream-model context on-event
                         &key max-tokens temperature abort-p)
                  (declare
                   (ignore provider stream-model context max-tokens
                           temperature abort-p))
                  (let ((message (pop responses)))
                    (funcall
                     on-event
                     (cadr-ai:make-stream-event
                      :type :start :message message))
                    (funcall
                     on-event
                     (cadr-ai:make-stream-event
                      :type :done
                      :message message
                      :reason
                      (cadr-ai:assistant-message-stop-reason
                       message)))
                    message)))))
        (cadr-agent:agent-prompt agent "fix add and run its test")
        (let ((bash-results
                (loop for message
                        in (cadr-agent:agent-messages agent)
                      when
                        (and
                         (typep
                          message 'cadr-ai:tool-result-message)
                         (string=
                          "bash"
                          (cadr-ai:tool-result-message-tool-name
                           message)))
                        collect
                        (list
                         :exit-code
                         (getf
                          (cadr-ai:tool-result-message-details
                           message)
                          :exit-code)
                         :error-p
                         (cadr-ai:tool-result-message-is-error
                          message)))))
          (is (equal
               '((:exit-code nil :error-p t)
                 (:exit-code 0 :error-p nil))
               bash-results)))
        (is (string=
             (format nil "(defun add (a b) (+ a b))~%")
             (read-text
              (merge-pathnames "calc.lisp" directory))))
        (is (null responses))))))
