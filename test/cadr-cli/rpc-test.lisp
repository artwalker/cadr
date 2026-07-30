(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defun rpc-output-records (stream)
  (loop
    for line in
    (uiop:split-string
     (get-output-stream-string stream)
     :separator '(#\Newline))
    unless (zerop (length line))
      collect (cadr-ai::parse-json line)))

(defun make-rpc-test-agent
    (directory &optional responses)
  (let ((remaining
          (copy-list
           (or responses
               (list
                (cli-test-assistant "done"))))))
    (cadr-agent:make-agent
     :provider :mock
     :model
     (cadr-ai:make-model
      :id "mock"
      :name "Mock"
      :provider :openai
      :api :openai-responses
      :base-url "https://example.invalid"
      :max-tokens 1024)
     :session
     (cadr-agent:create-session
      :directory directory
      :cwd directory)
     :stream-function
     (lambda
         (provider model context on-event
          &key max-tokens temperature abort-p)
       (declare
        (ignore
         provider model context max-tokens
         temperature abort-p))
       (let ((message (pop remaining)))
         (funcall
          on-event
          (cadr-ai:make-stream-event
           :type :start
           :message message))
         (dolist
             (block
              (cadr-ai:assistant-message-content
               message))
           (when (typep block 'cadr-ai:text-content)
             (funcall
              on-event
              (cadr-ai:make-stream-event
               :type :text-delta
               :delta
               (cadr-ai:text-content-text block)
               :message message))))
         message)))))

(defun make-rpc-test-state
    (directory output &optional responses)
  (let* ((manager
           (cadr-cli::make-cli-extension-manager
            :cwd directory
            :global-directory
            (merge-pathnames "extensions/" directory)
            :output
            (make-string-output-stream)
            :mode :rpc))
         (agent
           (make-rpc-test-agent
            directory responses))
         (state
           (cadr-cli::%make-rpc-state
            :agent agent
            :extension-manager manager
            :input
            (make-string-input-stream "")
            :output output
            :error-output
            (make-string-output-stream))))
    (setf
     (cadr-agent::extension-host-ui-function
      (cadr-cli::cli-extension-manager-host
       manager))
     (cadr-cli::rpc-extension-ui-callback
      state))
    (setf
     (cadr-agent::agent-on-event agent)
     (lambda (event)
       (cadr-cli::rpc-write-object
        state
        (cadr-cli::agent-event-to-json event))))
    state))

(test rpc-jsonl-framing-is-lf-only-and-keeps-final-frame
  (let ((lines nil))
    (cadr-cli::read-rpc-jsonl-lines
     (make-string-input-stream
      (format nil
              "{\"text\":\"a~Cb~Cc\"}~C~C{\"n\":1}~C{\"last\":true}"
              (code-char #x2028)
              (code-char #x2029)
              #\Return #\Newline #\Newline))
     (lambda (line)
       (push line lines)))
    (setf lines (nreverse lines))
    (is (= 3 (length lines)))
    (is (search
         (string (code-char #x2028))
         (first lines)))
    (is (search
         (string (code-char #x2029))
         (first lines)))
    (is (string= "{\"n\":1}"
                 (second lines)))
    (is (string= "{\"last\":true}"
                 (third lines)))))

(test rpc-command-responses-preserve-id-and-parse-errors-use-parse
  (with-test-directory (directory)
    (let* ((output
             (make-string-output-stream))
           (state
             (make-rpc-test-state
              directory output)))
      (cadr-cli::rpc-handle-line
       state
       "{\"id\":\"state-1\",\"type\":\"get_state\"}")
      (cadr-cli::rpc-handle-line
       state
       "{\"id\":\"unknown-1\",\"type\":\"nope\"}")
      (cadr-cli::rpc-handle-line
       state
       "{broken")
      (let ((records
              (rpc-output-records output)))
        (is (= 3 (length records)))
        (is (eq t
                (cadr-ai::json-get
                 (first records) "success")))
        (is
         (not
          (cadr-ai::json-present-p
           (cadr-ai::json-get
            (first records) "data")
           "sessionName")))
        (is (string=
             "state-1"
             (cadr-ai::json-get
              (first records) "id")))
        (is (string=
             "unknown-1"
             (cadr-ai::json-get
              (second records) "id")))
        (is (not
             (cadr-ai::json-get
              (second records) "success")))
        (is (string=
             "parse"
             (cadr-ai::json-get
              (third records) "command")))))))

(test rpc-prompt-acknowledges-once-and-streams-agent-events
  (with-test-directory (directory)
    (let* ((output
             (make-string-output-stream))
           (state
             (make-rpc-test-state
              directory output)))
      (cadr-cli::rpc-handle-line
       state
       "{\"id\":\"p1\",\"type\":\"prompt\",\"message\":\"hello\"}")
      (cadr-agent:agent-wait-for-idle
       (cadr-cli::rpc-state-agent state))
      (loop repeat 100
            until
            (null
             (cadr-cli::rpc-state-prompt-thread
              state))
            do (sleep 0.01))
      (let* ((records
               (rpc-output-records output))
             (responses
               (remove-if-not
                (lambda (record)
                  (and
                   (string=
                    "response"
                    (cadr-ai::json-get
                     record "type"))
                   (string=
                    "p1"
                    (cadr-ai::json-get
                     record "id"))))
                records)))
        (is (= 1 (length responses)))
        (is (eq t
                (cadr-ai::json-get
                 (first responses)
                 "success")))
        (is
         (find
          "agent_end"
          records
          :key
          (lambda (record)
            (cadr-ai::json-get
             record "type"))
          :test #'string=))))))

(test rpc-extension-ui-response-cancel-timeout-signal-unknown-and-eof
  (with-test-directory (directory)
    (let* ((output
             (make-string-output-stream))
           (state
             (make-rpc-test-state
              directory output))
           (callback
             (cadr-cli::rpc-extension-ui-callback
              state))
           (selected :unset)
           (thread
             (sb-thread:make-thread
              (lambda ()
                (setf
                 selected
                 (funcall
                  callback :select
                  '(:title "Pick"
                    :options ("a" "b")
                    :timeout-ms 1000))))
              :name "rpc-ui-select-test")))
      (loop repeat 100
            for records =
              (rpc-output-records output)
            for request =
              (find
               "extension_ui_request"
               records
               :key
               (lambda (record)
                 (cadr-ai::json-get
                  record "type"))
               :test #'string=)
            when request
              do
              (cadr-cli::rpc-handle-ui-response
               state
               (cadr-ai::json-object
                "type"
                "extension_ui_response"
                "id"
                (cadr-ai::json-get
                 request "id")
                "value" "b"))
              (return)
            do (sleep 0.01))
      (sb-thread:join-thread thread)
      (is (string= "b" selected))
      (is
       (null
        (funcall
         callback :input
         '(:title "Input"
           :timeout-ms 1))))
      (let ((signal
              (cadr-agent::make-extension-cancellation-signal)))
        (cadr-agent::abort-extension-cancellation-signal
         signal)
        (is
         (null
          (funcall
           callback :confirm
           (list
            :title "Confirm"
            :message "Proceed?"
            :signal signal
            :timeout-ms 1000)))))
      (cadr-cli::rpc-handle-ui-response
       state
       (cadr-ai::json-object
        "type" "extension_ui_response"
        "id" "missing"
        "cancelled" t))
      (let ((records
              (rpc-output-records output)))
        (is
         (find-if
          (lambda (record)
            (and
             (string=
              "extension_ui_response"
              (cadr-ai::json-get
               record "command"))
             (not
              (cadr-ai::json-get
               record "success"))))
          records)))
      (let* ((value :waiting)
             (eof-thread
              (sb-thread:make-thread
               (lambda ()
                 (setf
                  value
                  (funcall
                   callback :editor
                   '(:title "Edit"))))
               :name "rpc-ui-eof-test")))
        (loop repeat 100
              until
              (plusp
               (hash-table-count
                (cadr-cli::rpc-state-pending
                 state)))
              do (sleep 0.01))
        (cadr-cli::rpc-close-pending-dialogs
         state)
        (sb-thread:join-thread eof-thread)
        (is (null value))
        (is
         (zerop
           (hash-table-count
            (cadr-cli::rpc-state-pending
             state))))))))

(test rpc-bash-returns-reference-result-shape-and-aborts-on-request
  (with-test-directory (directory)
    (let* ((output
             (make-string-output-stream))
           (state
             (make-rpc-test-state
              directory output)))
      (cadr-cli::rpc-handle-line
       state
       "{\"id\":\"bash-1\",\"type\":\"bash\",\"command\":\"printf 'out'; printf 'err' >&2; exit 7\"}")
      (loop repeat 500
            for records = (rpc-output-records output)
            for response =
              (find
               "bash-1" records
               :key
               (lambda (record)
                 (cadr-ai::json-get record "id"))
               :test #'string=)
            when response
              do
              (let ((data
                      (cadr-ai::json-get
                       response "data")))
                (is
                 (string=
                  "outerr"
                  (cadr-ai::json-get
                   data "output")))
                (is (= 7
                       (cadr-ai::json-get
                        data "exitCode")))
                (is
                 (not
                  (cadr-ai::json-get
                   data "cancelled")))
                (is
                 (not
                  (cadr-ai::json-get
                   data "truncated")))
                (is
                 (not
                  (cadr-ai::json-present-p
                   data "fullOutputPath"))))
              (return)
            do (sleep 0.01)
            finally
            (fail
             "Timed out waiting for bash response"))
      (cadr-cli::rpc-handle-line
       state
       "{\"id\":\"bash-2\",\"type\":\"bash\",\"command\":\"sleep 30\"}")
      (loop repeat 500
            when
            (let ((thread
                    (cadr-cli::rpc-state-bash-thread
                     state)))
              (and
               thread
               (sb-thread:thread-alive-p thread)))
              do (return)
            do (sleep 0.01)
            finally
            (fail
             "Timed out waiting for bash worker; records: ~S"
             (list
              :records (rpc-output-records output)
              :thread
              (cadr-cli::rpc-state-bash-thread state)
              :token
              (cadr-cli::rpc-state-bash-token state))))
      (cadr-cli::rpc-handle-line
       state
       "{\"id\":\"abort-1\",\"type\":\"abort_bash\"}")
      (loop repeat 500
            for records = (rpc-output-records output)
            for bash-response =
              (find
               "bash-2" records
               :key
               (lambda (record)
                 (cadr-ai::json-get record "id"))
               :test #'string=)
            for abort-response =
              (find
               "abort-1" records
               :key
               (lambda (record)
                 (cadr-ai::json-get record "id"))
               :test #'string=)
            when (and bash-response abort-response)
              do
              (let ((data
                      (cadr-ai::json-get
                       bash-response "data")))
                (is
                 (eq t
                     (cadr-ai::json-get
                      data "cancelled")))
                (is
                 (eq 'null
                     (cadr-ai::json-get
                      data "exitCode")))
                (is
                 (eq t
                     (cadr-ai::json-get
                      abort-response "success"))))
              (return)
            do (sleep 0.01)
            finally
            (fail
             "Timed out waiting for abort responses")))))
