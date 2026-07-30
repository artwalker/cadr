(in-package #:pi-cli/tests)
(in-suite pi-cli-suite)

(test repl-consumes-multiple-lines-and-streams-text
  (let ((prompts nil)
        (output (make-string-output-stream)))
    (run-repl
     (lambda (prompt)
       (push prompt prompts)
       (pi-ai:make-assistant-message
        :content
        (list (pi-ai:make-text-content
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
      (is (search "pi> " text))
      (is (search "assistant> HELLO" text))
      (is (search "assistant> WORLD" text)))))

(test repl-runs-a-faux-provider-through-real-read-edit-and-bash-tools
  (with-test-directory (directory)
    (write-text
     (merge-pathnames "calc.lisp" directory)
     (format nil "(defun add (a b) (- a b))~%"))
    (labels
        ((assistant (content &optional (stop-reason :stop))
           (pi-ai:make-assistant-message
            :content content
            :api :openai-responses
            :provider :openai
            :model "mock"
            :stop-reason stop-reason)))
      (let* ((responses
               (list
                (assistant
                 (list
                  (pi-ai:make-tool-call
                   :id "read-1"
                   :name "read"
                   :arguments (args "path" "calc.lisp")))
                 :tool-use)
                (assistant
                 (list
                  (pi-ai:make-tool-call
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
                  (pi-ai:make-tool-call
                   :id "bash-1"
                   :name "bash"
                   :arguments
                   (args
                    "command"
                    "grep -Fq '(+ a b)' calc.lisp")))
                 :tool-use)
                (assistant
                 (list
                  (pi-ai:make-text-content :text "fixed")))))
             (model
               (pi-ai:make-model
                :id "mock"
                :provider :openai
                :api :openai-responses
                :base-url "https://example.invalid"
                :max-tokens 1024))
             (agent
               (pi-agent:make-agent
                :provider :mock
                :model model
                :tools (pi-cli:make-coding-tools directory)
                :stream-function
                (lambda (provider stream-model context on-event
                         &key max-tokens temperature abort-p)
                  (declare
                   (ignore provider stream-model context max-tokens
                           temperature abort-p))
                  (let ((message (pop responses)))
                    (funcall
                     on-event
                     (pi-ai:make-stream-event
                      :type :start :message message))
                    (dolist
                        (block
                         (pi-ai:assistant-message-content message))
                      (when (typep block 'pi-ai:text-content)
                        (funcall
                         on-event
                         (pi-ai:make-stream-event
                          :type :text-delta
                          :delta (pi-ai:text-content-text block)
                          :message message))))
                    (funcall
                     on-event
                     (pi-ai:make-stream-event
                      :type :done :message message
                      :reason
                      (pi-ai:assistant-message-stop-reason
                       message)))
                    message))))
             (output (make-string-output-stream)))
        (run-repl
         (lambda (prompt)
           (pi-agent:agent-prompt agent prompt))
         :input
         (make-string-input-stream (format nil "fix it~%"))
         :output output)
        (is (string=
             (format nil "(defun add (a b) (+ a b))~%")
             (read-text (merge-pathnames "calc.lisp" directory))))
        (is (= 8 (length (pi-agent:agent-messages agent))))
        (is (null responses))
        (is (search "assistant> fixed"
                    (get-output-stream-string output)))))))

(test event-renderer-streams-each-delta-and-reports-terminal-errors-once
  (let* ((output (make-string-output-stream))
         (renderer (pi-cli::make-agent-event-renderer output))
         (message
           (pi-ai:make-assistant-message
            :api :openai-responses
            :provider :openai
            :model "mock")))
    (funcall
     renderer
     (pi-agent::make-agent-event
      :type :message-start :message message))
    (funcall
     renderer
     (pi-agent::make-agent-event
      :type :message-update
      :message message
      :stream-event
      (pi-ai:make-stream-event
       :type :text-delta :delta "hel" :message message)))
    (funcall
     renderer
     (pi-agent::make-agent-event
      :type :message-update
      :message message
      :stream-event
      (pi-ai:make-stream-event
       :type :text-delta :delta "lo" :message message)))
    (funcall
     renderer
     (pi-agent::make-agent-event
      :type :message-end :message message))
    (let ((error-message
            (pi-ai:make-assistant-message
             :api :openai-responses
             :provider :openai
             :model "mock"
             :stop-reason :error
             :error-message "network down")))
      (funcall
       renderer
       (pi-agent::make-agent-event
        :type :message-start :message error-message))
      (funcall
       renderer
       (pi-agent::make-agent-event
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
           (pi-ai:make-assistant-message
            :content content
            :api :openai-responses
            :provider :openai
            :model "mock"
            :stop-reason stop-reason))
         (call (id name arguments)
           (assistant
            (list
             (pi-ai:make-tool-call
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
                  (pi-ai:make-text-content
                   :text "tests pass")))))
             (model
               (pi-ai:make-model
                :id "mock"
                :provider :openai
                :api :openai-responses
                :base-url "https://example.invalid"
                :max-tokens 1024))
             (agent
               (pi-agent:make-agent
                :provider :mock
                :model model
                :tools (pi-cli:make-coding-tools directory)
                :stream-function
                (lambda (provider stream-model context on-event
                         &key max-tokens temperature abort-p)
                  (declare
                   (ignore provider stream-model context max-tokens
                           temperature abort-p))
                  (let ((message (pop responses)))
                    (funcall
                     on-event
                     (pi-ai:make-stream-event
                      :type :start :message message))
                    (funcall
                     on-event
                     (pi-ai:make-stream-event
                      :type :done
                      :message message
                      :reason
                      (pi-ai:assistant-message-stop-reason
                       message)))
                    message)))))
        (pi-agent:agent-prompt agent "fix add and run its test")
        (let ((bash-codes
                (loop for message
                        in (pi-agent:agent-messages agent)
                      when
                        (and
                         (typep
                          message 'pi-ai:tool-result-message)
                         (string=
                          "bash"
                          (pi-ai:tool-result-message-tool-name
                           message)))
                        collect
                        (getf
                         (pi-ai:tool-result-message-details
                          message)
                         :exit-code))))
          (is (equal '(1 0) bash-codes)))
        (is (string=
             (format nil "(defun add (a b) (+ a b))~%")
             (read-text
              (merge-pathnames "calc.lisp" directory))))
        (is (null responses))))))
