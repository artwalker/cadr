(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defun rpc-output-records (stream)
  (loop
    for line in
    (uiop:split-string
     (if (typep stream 'notifying-string-output-stream)
         (notifying-output-string stream)
         (get-output-stream-string stream))
     :separator '(#\Newline))
    unless (zerop (length line))
      collect (cadr-ai::parse-json line)))

(defun wait-for-rpc-records (stream predicate)
  (loop with records = nil
        do
        (setf records
              (nconc records (rpc-output-records stream)))
        when (funcall predicate records)
          return records
        do
        (sb-thread:wait-on-semaphore
         (notifying-output-notification stream))))

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

(test rpc-get-state-succeeds-when-agent-model-is-nil
  (with-test-directory (directory)
    (let* ((output
             (make-string-output-stream))
           (state
             (make-rpc-test-state
              directory output))
           (agent
             (cadr-cli::rpc-state-agent state)))
      (setf (cadr-agent:agent-model agent) nil)
      (cadr-cli::rpc-handle-line
       state
       "{\"id\":\"state-nil\",\"type\":\"get_state\"}")
      (let* ((records
               (rpc-output-records output))
             (record (first records))
             (data
               (cadr-ai::json-get record "data")))
        (is (= 1 (length records)))
        (is (eq t
                (cadr-ai::json-get
                 record "success")))
        (is (string=
             "get_state"
             (cadr-ai::json-get
              record "command")))
        (is (not
             (cadr-ai::json-present-p
              data "model")))
        (is (stringp
             (cadr-ai::json-get
              data "sessionId")))
        (is (plusp
             (length
              (cadr-ai::json-get
               data "sessionId"))))))))

(test rpc-get-state-reports-in-flight-compaction
  (with-test-directory (directory)
    (let* ((output (make-string-output-stream))
           (state (make-rpc-test-state directory output))
           (agent (cadr-cli::rpc-state-agent state)))
      (cadr-cli::rpc-handle-line
       state
       "{\"id\":\"idle\",\"type\":\"get_state\"}")
      (setf (cadr-agent::agent-compaction-cancellation agent) t)
      (cadr-cli::rpc-handle-line
       state
       "{\"id\":\"compacting\",\"type\":\"get_state\"}")
      (let* ((records (rpc-output-records output))
             (idle (cadr-ai::json-get (first records) "data"))
             (compacting (cadr-ai::json-get (second records) "data")))
        (is (cadr-ai::json-present-p idle "isCompacting"))
        (is (null (cadr-ai::json-get idle "isCompacting")))
        (is (eq t (cadr-ai::json-get compacting "isCompacting")))))))

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
      (join-rpc-prompt-worker state)
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
             (make-instance
              'notifying-string-output-stream))
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
      (let* ((records
               (wait-for-rpc-records
                output
                (lambda (records)
                  (find
                   "extension_ui_request" records
                   :key
                   (lambda (record)
                     (cadr-ai::json-get record "type"))
                   :test #'string=))))
             (request
               (find
                "extension_ui_request" records
                :key
                (lambda (record)
                  (cadr-ai::json-get record "type"))
                :test #'string=)))
        (cadr-cli::rpc-handle-ui-response
         state
         (cadr-ai::json-object
          "type" "extension_ui_response"
          "id" (cadr-ai::json-get request "id")
          "value" "b")))
      (sb-thread:join-thread thread)
      (is (string= "b" selected))
      (is
       (null
        (funcall
         callback :input
         '(:title "Input"
           :timeout-ms 0))))
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
        (wait-for-rpc-records
         output
         (lambda (records)
           (find-if
            (lambda (record)
              (and
               (string= "extension_ui_request"
                        (cadr-ai::json-get record "type"))
               (string= "editor"
                        (cadr-ai::json-get record "method"))))
            records)))
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
      (let ((thread
              (cadr-cli::rpc-state-bash-thread state)))
        (when thread
          (sb-thread:join-thread thread)))
      (let* ((records (rpc-output-records output))
             (response
               (find
                "bash-1" records
                :key
                (lambda (record)
                  (cadr-ai::json-get record "id"))
                :test #'string=))
             (data
               (and response
                    (cadr-ai::json-get response "data"))))
        (is (not (null response)))
        (is (string= "outerr"
                     (cadr-ai::json-get data "output")))
        (is (= 7 (cadr-ai::json-get data "exitCode")))
        (is (not (cadr-ai::json-get data "cancelled")))
        (is (not (cadr-ai::json-get data "truncated")))
        (is (not
             (cadr-ai::json-present-p
              data "fullOutputPath"))))
      (cadr-cli::rpc-handle-line
       state
       "{\"id\":\"bash-2\",\"type\":\"bash\",\"command\":\"exec /usr/bin/tail -f /dev/null\"}")
      (is (sb-thread:thread-alive-p
           (cadr-cli::rpc-state-bash-thread state)))
      (cadr-cli::rpc-handle-line
       state
       "{\"id\":\"abort-1\",\"type\":\"abort_bash\"}")
      (let* ((records (rpc-output-records output))
             (bash-response
               (find
                "bash-2" records
                :key
                (lambda (record)
                  (cadr-ai::json-get record "id"))
                :test #'string=))
             (abort-response
               (find
                "abort-1" records
                :key
                (lambda (record)
                  (cadr-ai::json-get record "id"))
                :test #'string=))
             (data
               (and bash-response
                    (cadr-ai::json-get bash-response "data"))))
        (is (not (null bash-response)))
        (is (not (null abort-response)))
        (is (eq t (cadr-ai::json-get data "cancelled")))
        (is (eq 'null (cadr-ai::json-get data "exitCode")))
        (is (eq t
                (cadr-ai::json-get abort-response "success")))))))

(test rpc-clear-queue-returns-steering-and-follow-up-text
  (with-test-directory (directory)
    (let* ((output (make-string-output-stream))
           (state (make-rpc-test-state directory output))
           (agent (cadr-cli::rpc-state-agent state)))
      (cadr-agent:agent-steer agent "steer-me")
      (cadr-agent:agent-follow-up agent "later")
      (cadr-cli::rpc-handle-line
       state
       "{\"id\":\"cq1\",\"type\":\"clear_queue\"}")
      (let* ((records (rpc-output-records output))
             (record
               (find
                "cq1" records
                :key
                (lambda (candidate)
                  (cadr-ai::json-get candidate "id"))
                :test #'string=))
             (data (and record (cadr-ai::json-get record "data"))))
        (is (not (null record)))
        (is (eq t (cadr-ai::json-get record "success")))
        (is (string= "clear_queue"
                     (cadr-ai::json-get record "command")))
        (is (equalp #("steer-me")
                    (cadr-ai::json-get data "steering")))
        (is (equalp #("later")
                    (cadr-ai::json-get data "followUp")))
        (is (null (cadr-agent::agent-steering-queue agent)))
        (is (null (cadr-agent::agent-follow-up-queue agent)))))))

(defun rpc-response-for (state json id)
  (cadr-cli::rpc-handle-line state json)
  (find-if
   (lambda (record)
     (and (equal "response"
                 (cadr-ai::json-get record "type"))
          (equal id
                 (cadr-ai::json-get record "id"))))
   (rpc-output-records
    (cadr-cli::rpc-state-output state))))

(defun rpc-response-data (record)
  (cadr-ai::json-get record "data"))

(defun rpc-install-switch-cancel (state)
  (let* ((agent (cadr-cli::rpc-state-agent state))
         (host
           (cadr-cli::cli-extension-manager-host
            (cadr-cli::rpc-state-extension-manager
             state)))
         (bundle
           (cadr-agent::make-extension-bundle
            :id "rpc-cancel"
            :path "/tmp/rpc-cancel.lisp")))
    (setf (cadr-agent::agent-extension-host agent) host)
    (cadr-agent::call-with-extension-registration
     bundle
     (lambda ()
       (cadr-agent:define-event-hook
        :session-before-switch
        :handler
        (lambda (event context)
          (declare (ignore event context))
          '(:cancel-p t)))))
    (cadr-agent::replace-extension-bundles
     host (list bundle))))

(defun rpc-usage (input output cost)
  (cadr-ai:make-usage
   :input input
   :output output
   :cache-read 0
   :cache-write 0
   :total (+ input output)
   :cost (cadr-ai:make-cost :total (float cost 1d0))))

(test rpc-new-session-reports-cancel-and-stores-parent
  ;; pi@4a080252f rpc-mode.ts new_session. A hook that cancels
  ;; session_before_switch leaves the session in place.
  (with-test-directory (directory)
    (let* ((output (make-string-output-stream))
           (state (make-rpc-test-state directory output))
           (agent (cadr-cli::rpc-state-agent state))
           (before
             (cadr-agent:session-id
              (cadr-agent:agent-session agent)))
           (parent "/tmp/cadr-parent-session.jsonl"))
      (let* ((record
               (rpc-response-for
                state
                (format nil
                        "{\"id\":\"ns1\",\"type\":\"new_session\",\"parentSession\":~A}"
                        (cadr-ai::stringify-json parent))
                "ns1"))
             (data (rpc-response-data record))
             (session (cadr-agent:agent-session agent)))
        (is (eq t (cadr-ai::json-get record "success")))
        (is (cadr-ai::json-present-p data "cancelled"))
        (is (null (cadr-ai::json-get data "cancelled")))
        (is (not (string= before (cadr-agent:session-id session))))
        (is (string= parent
                     (cadr-agent:session-parent-session session))))
      (rpc-install-switch-cancel state)
      (let* ((kept
               (cadr-agent:session-id
                (cadr-agent:agent-session agent)))
             (record
               (rpc-response-for
                state
                "{\"id\":\"ns2\",\"type\":\"new_session\"}"
                "ns2"))
             (data (rpc-response-data record)))
        (is (eq t (cadr-ai::json-get record "success")))
        (is (eq t (cadr-ai::json-get data "cancelled")))
        (is (string= kept
                     (cadr-agent:session-id
                      (cadr-agent:agent-session agent))))))))

(test rpc-switch-session-loads-the-file-unless-cancelled
  (with-test-directory (directory)
    (let* ((output (make-string-output-stream))
           (state (make-rpc-test-state directory output))
           (agent (cadr-cli::rpc-state-agent state))
           (original (cadr-agent:agent-session agent))
           (other
             (cadr-agent:create-session
              :directory directory
              :cwd directory)))
      (cadr-agent:session-append-message
       original
       (cadr-ai:make-user-message :content "stay"))
      (cadr-agent:session-append-message
       original
       (cadr-ai:make-assistant-message
        :content
        (list (cadr-ai:make-text-content :text "kept"))
        :api :openai-responses
        :provider :openai
        :model "mock"
        :stop-reason :stop))
      (cadr-agent:session-append-message
       other
       (cadr-ai:make-user-message :content "there"))
      (cadr-agent:session-append-message
       other
       (cadr-ai:make-assistant-message
        :content
        (list (cadr-ai:make-text-content :text "switched"))
        :api :openai-responses
        :provider :openai
        :model "mock"
        :stop-reason :stop))
      (let* ((record
               (rpc-response-for
                state
                (format nil
                        "{\"id\":\"sw1\",\"type\":\"switch_session\",\"sessionPath\":~A}"
                        (cadr-ai::stringify-json
                         (namestring
                          (cadr-agent:session-path other))))
                "sw1"))
             (data (rpc-response-data record)))
        (is (eq t (cadr-ai::json-get record "success")))
        (is (null (cadr-ai::json-get data "cancelled")))
        (is (string=
             (cadr-agent:session-id other)
             (cadr-agent:session-id
              (cadr-agent:agent-session agent)))))
      (rpc-install-switch-cancel state)
      (let* ((kept
               (cadr-agent:session-id
                (cadr-agent:agent-session agent)))
             (record
               (rpc-response-for
                state
                (format nil
                        "{\"id\":\"sw2\",\"type\":\"switch_session\",\"sessionPath\":~A}"
                        (cadr-ai::stringify-json
                         (namestring
                          (cadr-agent:session-path original))))
                "sw2"))
             (data (rpc-response-data record)))
        (is (eq t (cadr-ai::json-get record "success")))
        (is (eq t (cadr-ai::json-get data "cancelled")))
        (is (string= kept
                     (cadr-agent:session-id
                      (cadr-agent:agent-session agent))))))))

(test rpc-cycle-model-advances-past-a-missing-current-and-wraps
  ;; pi@4a080252f agent-session.ts cycleModel. A current model that is
  ;; not in the pool is treated as index 0, then the cycle steps
  ;; forward. One model returns no selection. An explicit scoped
  ;; thinking level wins; otherwise the settings default, then the
  ;; current level.
  (with-test-directory (directory)
    (let* ((output (make-string-output-stream))
           (state (make-rpc-test-state directory output))
           (agent (cadr-cli::rpc-state-agent state))
           (models (cadr-cli::rpc-available-models state))
           (reasoning
             (remove-if-not
              #'cadr-ai:model-reasoning-p models)))
      (is (>= (length models) 2))
      (is (>= (length reasoning) 2))
      (setf (cadr-cli::rpc-state-scoped-models state)
            (list (list :model (first reasoning))
                  (list :model (second reasoning))))
      (let* ((record
               (rpc-response-for
                state
                "{\"id\":\"cm1\",\"type\":\"cycle_model\"}"
                "cm1"))
             (data (rpc-response-data record))
             (model (cadr-ai::json-get data "model")))
        (is (eq t (cadr-ai::json-get record "success")))
        (is (string= (cadr-ai:model-id (second reasoning))
                     (cadr-ai::json-get model "id")))
        (is (string=
             (string-downcase
              (symbol-name
               (cadr-ai:model-provider (second reasoning))))
             (cadr-ai::json-get model "provider")))
        (is (eq t (cadr-ai::json-get data "isScoped")))
        (is (string= "off"
                     (cadr-ai::json-get data "thinkingLevel"))))
      (let ((settings
              (cadr-cli::make-memory-settings-manager)))
        (cadr-cli::settings-set-default-thinking-level
         settings :medium)
        (setf (cadr-cli::rpc-state-settings state) settings)
        (setf (cadr-agent:agent-model agent) (second reasoning))
        (let* ((record
                 (rpc-response-for
                  state
                  "{\"id\":\"cm2\",\"type\":\"cycle_model\"}"
                  "cm2"))
               (data (rpc-response-data record)))
          (is (string= (cadr-ai:model-id (first reasoning))
                       (cadr-ai::json-get
                        (cadr-ai::json-get data "model")
                        "id")))
          (is (string= "medium"
                       (cadr-ai::json-get
                        data "thinkingLevel")))))
      (setf (cadr-cli::rpc-state-scoped-models state)
            (list (list :model (first reasoning) :thinking :high)
                  (list :model (second reasoning))))
      (setf (cadr-agent:agent-model agent) (second reasoning))
      (let* ((record
               (rpc-response-for
                state
                "{\"id\":\"cm3\",\"type\":\"cycle_model\"}"
                "cm3"))
             (data (rpc-response-data record)))
        (is (string= (cadr-ai:model-id (first reasoning))
                     (cadr-ai::json-get
                      (cadr-ai::json-get data "model")
                      "id")))
        (is (string= "high"
                     (cadr-ai::json-get data "thinkingLevel"))))
      (setf (cadr-cli::rpc-state-scoped-models state)
            (list (list :model (first reasoning))))
      (let ((before (cadr-agent:agent-model agent))
            (record
              (rpc-response-for
               state
               "{\"id\":\"cm4\",\"type\":\"cycle_model\"}"
               "cm4")))
        (is (eq 'null (rpc-response-data record)))
        (is (eq before (cadr-agent:agent-model agent))))
      (setf (cadr-cli::rpc-state-scoped-models state) nil)
      (setf (cadr-cli::rpc-state-settings state) nil)
      (setf (cadr-agent::agent-thinking-level agent) :off)
      (setf (cadr-agent:agent-model agent)
            (cadr-ai:make-model
             :id "mock" :name "Mock" :provider :openai
             :api :openai-responses
             :base-url "https://example.invalid"
             :max-tokens 1024))
      (let* ((record
               (rpc-response-for
                state
                "{\"id\":\"cm5\",\"type\":\"cycle_model\"}"
                "cm5"))
             (data (rpc-response-data record))
             (model (cadr-ai::json-get data "model")))
        (is (string= (cadr-ai:model-id (second models))
                     (cadr-ai::json-get model "id")))
        (is (cadr-ai::json-present-p data "isScoped"))
        (is (null (cadr-ai::json-get data "isScoped")))
        (is (string= "off"
                     (cadr-ai::json-get data "thinkingLevel"))))
      (setf (cadr-agent:agent-model agent) (car (last models)))
      (let* ((record
               (rpc-response-for
                state
                "{\"id\":\"cm6\",\"type\":\"cycle_model\"}"
                "cm6"))
             (data (rpc-response-data record)))
        (is (string= (cadr-ai:model-id (first models))
                     (cadr-ai::json-get
                      (cadr-ai::json-get data "model")
                      "id")))
        (is (null (cadr-ai::json-get data "isScoped")))))))

(test rpc-cycle-thinking-level-follows-supported-levels
  ;; pi@4a080252f agent-session.ts cycleThinkingLevel. A model that
  ;; does not reason returns no level. A reasoning model walks
  ;; off, minimal, low, medium, high when xhigh and max are absent.
  (with-test-directory (directory)
    (let* ((output (make-string-output-stream))
           (state (make-rpc-test-state directory output))
           (agent (cadr-cli::rpc-state-agent state)))
      (let ((record
              (rpc-response-for
               state
               "{\"id\":\"ct0\",\"type\":\"cycle_thinking_level\"}"
               "ct0")))
        (is (eq t (cadr-ai::json-get record "success")))
        (is (eq 'null (rpc-response-data record))))
      (setf (cadr-agent:agent-model agent)
            (cadr-ai:make-model
             :id "reasoner" :name "Reasoner" :provider :openai
             :api :openai-responses
             :base-url "https://example.invalid"
             :max-tokens 128
             :reasoning-p t))
      (setf (cadr-agent::agent-thinking-level agent) :off)
      (let ((record
              (rpc-response-for
               state
               "{\"id\":\"ctl\",\"type\":\"get_available_thinking_levels\"}"
               "ctl")))
        (is (equalp #("off" "minimal" "low" "medium" "high")
                    (cadr-ai::json-get
                     (rpc-response-data record)
                     "levels"))))
      (dolist (level '("minimal" "low" "medium" "high" "off"))
        (let* ((record
                 (rpc-response-for
                  state
                  (format nil
                          "{\"id\":\"ct-~A\",\"type\":\"cycle_thinking_level\"}"
                          level)
                  (format nil "ct-~A" level)))
               (data (rpc-response-data record))
               (state-record
                 (rpc-response-for
                  state
                  (format nil
                          "{\"id\":\"st-~A\",\"type\":\"get_state\"}"
                          level)
                  (format nil "st-~A" level))))
          (is (string= level
                       (cadr-ai::json-get data "level")))
          (is (string= level
                       (cadr-ai::json-get
                        (rpc-response-data state-record)
                        "thinkingLevel"))))))))

(test rpc-compact-errors-match-the-upstream-sentences
  ;; pi@4a080252f agent-session.ts compact. No model reports the
  ;; login guidance. A null preparation is "Already compacted" when
  ;; the leaf is a compaction entry, otherwise the session is too
  ;; small.
  (with-test-directory (directory)
    (let* ((output (make-string-output-stream))
           (state (make-rpc-test-state directory output))
           (agent (cadr-cli::rpc-state-agent state))
           (model (cadr-agent:agent-model agent)))
      (setf (cadr-agent:agent-model agent) nil)
      (let* ((record
               (rpc-response-for
                state
                "{\"id\":\"cp0\",\"type\":\"compact\"}"
                "cp0"))
             (error-text
               (cadr-ai::json-get record "error")))
        (is (null (cadr-ai::json-get record "success")))
        (is (string= "No model selected."
                     (subseq error-text 0
                             (min 18 (length error-text)))))
        (is (search "Use /login to log into a provider via OAuth or API key."
                    error-text))
        (is (search "Then use /model to select a model."
                    error-text)))
      (setf (cadr-agent:agent-model agent) model)
      (let ((record
              (rpc-response-for
               state
               "{\"id\":\"cp1\",\"type\":\"compact\"}"
               "cp1")))
        (is (null (cadr-ai::json-get record "success")))
        (is (string= "Nothing to compact (session too small)"
                     (cadr-ai::json-get record "error"))))
      (cadr-agent:session-append-compaction
       (cadr-agent:agent-session agent)
       "already" nil nil 0)
      (let ((record
              (rpc-response-for
               state
               "{\"id\":\"cp2\",\"type\":\"compact\"}"
               "cp2")))
        (is (null (cadr-ai::json-get record "success")))
        (is (string= "Already compacted"
                     (cadr-ai::json-get record "error")))))))

(test rpc-auto-compaction-retry-and-abort-retry
  (with-test-directory (directory)
    (let* ((output (make-string-output-stream))
           (state (make-rpc-test-state directory output))
           (agent (cadr-cli::rpc-state-agent state)))
      (is (eq t
              (cadr-ai::json-get
               (rpc-response-for
                state
                "{\"id\":\"ac0\",\"type\":\"set_auto_compaction\",\"enabled\":false}"
                "ac0")
               "success")))
      (is (null
           (cadr-ai::json-get
            (rpc-response-data
             (rpc-response-for
              state
              "{\"id\":\"gs0\",\"type\":\"get_state\"}"
              "gs0"))
            "autoCompactionEnabled")))
      (rpc-response-for
       state
       "{\"id\":\"ac1\",\"type\":\"set_auto_compaction\",\"enabled\":true}"
       "ac1")
      (is (eq t
              (cadr-ai::json-get
               (rpc-response-data
                (rpc-response-for
                 state
                 "{\"id\":\"gs1\",\"type\":\"get_state\"}"
                 "gs1"))
               "autoCompactionEnabled")))
      (is (eq t
              (cadr-ai::json-get
               (rpc-response-for
                state
                "{\"id\":\"ar0\",\"type\":\"set_auto_retry\",\"enabled\":false}"
                "ar0")
               "success")))
      (is (null (cadr-agent::agent-auto-retry-p agent)))
      (rpc-response-for
       state
       "{\"id\":\"ar1\",\"type\":\"set_auto_retry\",\"enabled\":true}"
       "ar1")
      (is (eq t (cadr-agent::agent-auto-retry-p agent)))
      (is (eq t
              (cadr-ai::json-get
               (rpc-response-for
                state
                "{\"id\":\"ab0\",\"type\":\"abort_retry\"}"
                "ab0")
               "success")))
      (is (null (cadr-agent::agent-retry-abort-requested-p agent)))
      (setf (cadr-agent::agent-retry-in-progress-p agent) t)
      (is (eq t
              (cadr-ai::json-get
               (rpc-response-for
                state
                "{\"id\":\"ab1\",\"type\":\"abort_retry\"}"
                "ab1")
               "success")))
      (is (eq t
              (cadr-agent::agent-retry-abort-requested-p
               agent))))))

(test rpc-session-stats-count-every-usage-source
  ;; pi@4a080252f agent-session.ts getSessionStats and
  ;; getContextUsage. Bash counts in totalMessages. Usage entries,
  ;; tool results, and compaction usage add tokens and cost. After
  ;; compaction the context count stays unknown until a later
  ;; assistant reports usage. Entries from before the compaction
  ;; remain.
  (with-test-directory (directory)
    (let* ((output (make-string-output-stream))
           (state (make-rpc-test-state directory output))
           (agent (cadr-cli::rpc-state-agent state))
           (session (cadr-agent:agent-session agent))
           (model (cadr-agent:agent-model agent)))
      (setf (cadr-ai:model-context-window model) 10000)
      (cadr-agent:agent-append-message
       agent
       (cadr-ai:make-user-message :content "hello"))
      (cadr-agent:agent-append-message
       agent
       (cadr-ai:make-assistant-message
        :content
        (list
         (cadr-ai:make-text-content :text "ok")
         (cadr-ai:make-tool-call :id "call-1" :name "read"))
        :api :openai-responses
        :provider :openai
        :model "mock"
        :usage (rpc-usage 10 1 1d0)
        :stop-reason :stop))
      (let* ((data
               (rpc-response-data
                (rpc-response-for
                 state
                 "{\"id\":\"st1\",\"type\":\"get_session_stats\"}"
                 "st1")))
             (tokens (cadr-ai::json-get data "tokens"))
             (context
               (cadr-ai::json-get data "contextUsage")))
        (is (= 1 (cadr-ai::json-get data "userMessages")))
        (is (= 1 (cadr-ai::json-get data "assistantMessages")))
        (is (= 1 (cadr-ai::json-get data "toolCalls")))
        (is (= 0 (cadr-ai::json-get data "toolResults")))
        (is (= 2 (cadr-ai::json-get data "totalMessages")))
        (is (= 10 (cadr-ai::json-get tokens "input")))
        (is (= 1 (cadr-ai::json-get tokens "output")))
        (is (= 11 (cadr-ai::json-get tokens "total")))
        (is (= 1d0 (cadr-ai::json-get data "cost")))
        (is (= 11 (cadr-ai::json-get context "tokens")))
        (is (= 10000
               (cadr-ai::json-get context "contextWindow")))
        (is (< (abs
                (- (cadr-ai::json-get context "percent")
                   (* 100d0 (/ 11d0 10000d0))))
               1d-6)))
      (let ((user-id
              (cadr-agent:session-entry-id
               (first (cadr-agent:session-entries session)))))
        (cadr-agent:agent-append-message
         agent
         (cadr-ai:make-tool-result-message
          :tool-call-id "call-1"
          :tool-name "read"
          :content nil
          :usage (rpc-usage 2 0 2d0)))
        (cadr-agent:agent-append-message
         agent
         (cadr-agent:make-bash-execution-message
          :command "echo" :output "hi" :exit-code 0))
        (cadr-agent:session-append-usage
         session "turn" "openai" "mock"
         (rpc-usage 3 0 3d0))
        (cadr-agent:session-append-compaction
         session "folded" nil user-id 11
         :usage (rpc-usage 4 0 4d0))
        (let* ((data
                 (rpc-response-data
                  (rpc-response-for
                   state
                   "{\"id\":\"st2\",\"type\":\"get_session_stats\"}"
                   "st2")))
               (tokens (cadr-ai::json-get data "tokens"))
               (context
                 (cadr-ai::json-get data "contextUsage"))
               (entries
                 (cadr-ai::json-get
                  (rpc-response-data
                   (rpc-response-for
                    state
                    "{\"id\":\"en1\",\"type\":\"get_entries\"}"
                    "en1"))
                  "entries"))
               (ids
                 (map 'list
                      (lambda (entry)
                        (cadr-ai::json-get entry "id"))
                      entries)))
          (is (= 4 (cadr-ai::json-get data "totalMessages")))
          (is (= 1 (cadr-ai::json-get data "toolResults")))
          (is (= 19 (cadr-ai::json-get tokens "input")))
          (is (= 1 (cadr-ai::json-get tokens "output")))
          (is (= 10d0 (cadr-ai::json-get data "cost")))
          (is (eq 'null (cadr-ai::json-get context "tokens")))
          (is (eq 'null (cadr-ai::json-get context "percent")))
          (is (= 10000
                 (cadr-ai::json-get context "contextWindow")))
          (is (member user-id ids :test #'string=))
          (is (< (position user-id ids :test #'string=)
                 (position-if
                  (lambda (entry)
                    (string= "compaction"
                             (cadr-ai::json-get entry "type")))
                  entries))))))))

(test rpc-export-html-uses-the-cadr-session-name
  ;; pi@4a080252f export-html/index.ts. No session file and a file
  ;; that has not been written yet are errors. The default name is
  ;; cadr-session-<basename>.html. A requested path is returned as
  ;; given.
  (with-test-directory (directory)
    (uiop:with-current-directory (directory)
      (let* ((output (make-string-output-stream))
             (state (make-rpc-test-state directory output))
             (agent (cadr-cli::rpc-state-agent state))
             (session (cadr-agent:agent-session agent)))
        (let ((record
                (rpc-response-for
                 state
                 "{\"id\":\"ex0\",\"type\":\"export_html\"}"
                 "ex0")))
          (is (null (cadr-ai::json-get record "success")))
          (is (string=
               "Nothing to export yet - start a conversation first"
               (cadr-ai::json-get record "error"))))
        (cadr-agent:agent-append-message
         agent
         (cadr-ai:make-user-message :content "hello"))
        (cadr-agent:agent-append-message
         agent
         (cadr-ai:make-assistant-message
          :content
          (list (cadr-ai:make-text-content :text "persisted"))
          :api :openai-responses
          :provider :openai
          :model "mock"
          :stop-reason :stop))
        (let* ((record
                 (rpc-response-for
                  state
                  "{\"id\":\"ex1\",\"type\":\"export_html\"}"
                  "ex1"))
               (relative
                 (format nil "cadr-session-~A.html"
                         (cadr-agent:session-id session)))
               (data (rpc-response-data record)))
          (is (eq t (cadr-ai::json-get record "success")))
          (is (string= relative
                       (cadr-ai::json-get data "path")))
          (is (probe-file
               (merge-pathnames relative directory))))
        (let* ((requested
                 (namestring
                  (merge-pathnames "out.html" directory)))
               (record
                 (rpc-response-for
                  state
                  (format nil
                          "{\"id\":\"ex2\",\"type\":\"export_html\",\"outputPath\":~A}"
                          (cadr-ai::stringify-json requested))
                  "ex2")))
          (is (string= requested
                       (cadr-ai::json-get
                        (rpc-response-data record)
                        "path")))
          (is (probe-file requested)))
        (setf (cadr-agent:session-path session) nil)
        (let ((record
                (rpc-response-for
                 state
                 "{\"id\":\"ex3\",\"type\":\"export_html\"}"
                 "ex3")))
          (is (null (cadr-ai::json-get record "success")))
          (is (string= "Cannot export in-memory session to HTML"
                       (cadr-ai::json-get record "error"))))))))

(test rpc-entries-tree-messages-and-last-assistant-text
  ;; pi@4a080252f session-manager.ts getTree and getEntries, and
  ;; agent-session.ts getLastAssistantText. since is exclusive.
  ;; Children are oldest first. A missing parent is a root. A label
  ;; carries the label entry's timestamp. Text blocks are joined
  ;; with no separator and trimmed; an aborted empty assistant is
  ;; skipped; whitespace is no text.
  (with-test-directory (directory)
    (let* ((output (make-string-output-stream))
           (state (make-rpc-test-state directory output))
           (agent (cadr-cli::rpc-state-agent state))
           (session (cadr-agent:agent-session agent)))
      (let ((data
              (rpc-response-data
               (rpc-response-for
                state
                "{\"id\":\"ge0\",\"type\":\"get_entries\"}"
                "ge0"))))
        (is (equalp #() (cadr-ai::json-get data "entries")))
        (is (eq 'null (cadr-ai::json-get data "leafId"))))
      (cadr-agent:agent-append-message
       agent (cadr-ai:make-user-message :content "one"))
      (cadr-agent:agent-append-message
       agent (cadr-ai:make-user-message :content "two"))
      (cadr-agent:agent-append-message
       agent (cadr-ai:make-user-message :content "three"))
      (let* ((entries
               (cadr-agent:session-entries session))
             (first (first entries))
             (second (second entries))
             (third (third entries)))
        (setf (cadr-agent:session-entry-parent-id third)
              (cadr-agent:session-entry-id first))
        (setf (cadr-agent:session-entry-timestamp third)
              (- (cadr-agent:session-entry-timestamp second)
                 60000))
        (let* ((all
                 (cadr-ai::json-get
                  (rpc-response-data
                   (rpc-response-for
                    state
                    "{\"id\":\"ge1\",\"type\":\"get_entries\"}"
                    "ge1"))
                  "entries"))
               (rest
                 (cadr-ai::json-get
                  (rpc-response-data
                   (rpc-response-for
                    state
                    (format nil
                            "{\"id\":\"ge2\",\"type\":\"get_entries\",\"since\":~A}"
                            (cadr-ai::stringify-json
                             (cadr-agent:session-entry-id first)))
                    "ge2"))
                  "entries"))
               (missing
                 (rpc-response-for
                  state
                  "{\"id\":\"ge3\",\"type\":\"get_entries\",\"since\":\"missing\"}"
                  "ge3")))
          (is (= 3 (length all)))
          (is (= 2 (length rest)))
          (is (string=
               (cadr-agent:session-entry-id second)
               (cadr-ai::json-get (aref rest 0) "id")))
          (is (null (cadr-ai::json-get missing "success")))
          (is (string= "Entry not found: missing"
                       (cadr-ai::json-get missing "error"))))
        (let* ((data
                 (rpc-response-data
                  (rpc-response-for
                   state
                   "{\"id\":\"tr1\",\"type\":\"get_tree\"}"
                   "tr1")))
               (tree (cadr-ai::json-get data "tree"))
               (root (aref tree 0))
               (children
                 (cadr-ai::json-get root "children")))
          (is (= 1 (length tree)))
          (is (string=
               (cadr-agent:session-entry-id first)
               (cadr-ai::json-get
                (cadr-ai::json-get root "entry")
                "id")))
          (is (string=
               (cadr-agent:session-entry-id third)
               (cadr-ai::json-get
                (cadr-ai::json-get (aref children 0) "entry")
                "id")))
          (is (string=
               (cadr-agent:session-entry-id second)
               (cadr-ai::json-get
                (cadr-ai::json-get (aref children 1) "entry")
                "id")))
          (is (string=
               (cadr-agent:session-leaf-id session)
               (cadr-ai::json-get data "leafId"))))
        (cadr-agent:session-set-label
         session
         (cadr-agent:session-entry-id first)
         "checkpoint")
        (let* ((entries
                 (cadr-ai::json-get
                  (rpc-response-data
                   (rpc-response-for
                    state
                    "{\"id\":\"ge4\",\"type\":\"get_entries\"}"
                    "ge4"))
                  "entries"))
               (label
                 (find "label"
                       (coerce entries 'list)
                       :key
                       (lambda (entry)
                         (cadr-ai::json-get entry "type"))
                       :test #'string=))
               (root
                 (aref
                  (cadr-ai::json-get
                   (rpc-response-data
                    (rpc-response-for
                     state
                     "{\"id\":\"tr2\",\"type\":\"get_tree\"}"
                     "tr2"))
                   "tree")
                  0)))
          (is (string= "checkpoint"
                       (cadr-ai::json-get root "label")))
          (is (string=
               (cadr-ai::json-get label "timestamp")
               (cadr-ai::json-get root "labelTimestamp"))))
        (setf (cadr-agent:session-entry-parent-id third)
              "missing")
        (let ((tree
                (cadr-ai::json-get
                 (rpc-response-data
                  (rpc-response-for
                   state
                   "{\"id\":\"tr3\",\"type\":\"get_tree\"}"
                   "tr3"))
                 "tree")))
          (is (= 2 (length tree)))))
      (let* ((messages
               (cadr-ai::json-get
                (rpc-response-data
                 (rpc-response-for
                  state
                  "{\"id\":\"gm1\",\"type\":\"get_messages\"}"
                  "gm1"))
                "messages"))
             (first (aref messages 0)))
        (is (string= "user" (cadr-ai::json-get first "role")))
        (is (string= "one" (cadr-ai::json-get first "content"))))
      (let ((empty
              (rpc-response-data
               (rpc-response-for
                state
                "{\"id\":\"la0\",\"type\":\"get_last_assistant_text\"}"
                "la0"))))
        (is (eq 'null (cadr-ai::json-get empty "text"))))
      (cadr-agent:agent-append-message
       agent
       (cadr-ai:make-assistant-message
        :content
        (list
         (cadr-ai:make-text-content :text " Hello ")
         (cadr-ai:make-text-content :text "world "))
        :api :openai-responses
        :provider :openai
        :model "mock"
        :stop-reason :stop))
      (cadr-agent:agent-append-message
       agent
       (cadr-ai:make-assistant-message
        :content nil
        :api :openai-responses
        :provider :openai
        :model "mock"
        :stop-reason :aborted))
      (is (string=
           "Hello world"
           (cadr-ai::json-get
            (rpc-response-data
             (rpc-response-for
              state
              "{\"id\":\"la1\",\"type\":\"get_last_assistant_text\"}"
              "la1"))
            "text")))
      (cadr-agent:agent-append-message
       agent
       (cadr-ai:make-assistant-message
        :content
        (list (cadr-ai:make-text-content :text "  "))
        :api :openai-responses
        :provider :openai
        :model "mock"
        :stop-reason :stop))
      (is (eq 'null
              (cadr-ai::json-get
               (rpc-response-data
                (rpc-response-for
                 state
                 "{\"id\":\"la2\",\"type\":\"get_last_assistant_text\"}"
                 "la2"))
               "text"))))))

(test rpc-get-commands-lists-extension-prompts-and-skills
  ;; pi@4a080252f agent-session.ts getCommands. Extension commands,
  ;; file prompt templates, then skill:<name>. User files are local
  ;; top-level resources. A skill's baseDir is its own directory; a
  ;; prompt's baseDir is the prompts root.
  (with-test-directory (directory)
    (let* ((agent-dir (merge-pathnames "agent/" directory))
           (skill-dir
             (merge-pathnames "skills/demo/" agent-dir))
           (prompt-dir
             (merge-pathnames "prompts/" agent-dir))
           (output (make-string-output-stream))
           (state (make-rpc-test-state directory output))
           (bundle
             (cadr-agent::make-extension-bundle
              :id "review-ext"
              :path "/tmp/review-ext.lisp"))
           (host
             (cadr-cli::cli-extension-manager-host
              (cadr-cli::rpc-state-extension-manager state)))
           (loader
             (cadr-cli::make-default-resource-loader
              :cwd directory
              :agent-directory agent-dir)))
      (write-text
       (merge-pathnames "SKILL.md" skill-dir)
       (format nil "---~%name: demo~%description: Demo skill~%---~%body~%"))
      (write-text
       (merge-pathnames "fix-tests.md" prompt-dir)
       (format nil "---~%description: Fix failing tests~%---~%do it~%"))
      (cadr-cli::reload-resources loader)
      (setf (cadr-cli::rpc-state-resources state) loader)
      (cadr-agent::call-with-extension-registration
       bundle
       (lambda ()
         (cadr-agent:define-command
          "review"
          :description "Review the diff"
          :handler
          (lambda (arguments context)
            (declare (ignore arguments context))))))
      (cadr-agent::replace-extension-bundles host (list bundle))
      (let* ((commands
               (coerce
                (cadr-ai::json-get
                 (rpc-response-data
                  (rpc-response-for
                   state
                   "{\"id\":\"gc1\",\"type\":\"get_commands\"}"
                   "gc1"))
                 "commands")
                'list))
             (names
               (mapcar
                (lambda (command)
                  (cadr-ai::json-get command "name"))
                commands))
             (review
               (find "review" commands
                     :key
                     (lambda (command)
                       (cadr-ai::json-get command "name"))
                     :test #'string=))
             (prompt
               (find "fix-tests" commands
                     :key
                     (lambda (command)
                       (cadr-ai::json-get command "name"))
                     :test #'string=))
             (skill
               (find "skill:demo" commands
                     :key
                     (lambda (command)
                       (cadr-ai::json-get command "name"))
                     :test #'string=))
             (prompt-info
               (cadr-ai::json-get prompt "sourceInfo"))
             (skill-info
               (cadr-ai::json-get skill "sourceInfo")))
        (is (< (position "review" names :test #'string=)
               (position "fix-tests" names :test #'string=)
               (position "skill:demo" names :test #'string=)))
        (is (string= "extension"
                     (cadr-ai::json-get review "source")))
        (is (string= "/tmp/review-ext.lisp"
                     (cadr-ai::json-get
                      (cadr-ai::json-get review "sourceInfo")
                      "path")))
        (is (string= "prompt"
                     (cadr-ai::json-get prompt "source")))
        (is (string= "Fix failing tests"
                     (cadr-ai::json-get prompt "description")))
        (is (string= "local"
                     (cadr-ai::json-get prompt-info "source")))
        (is (string= "user"
                     (cadr-ai::json-get prompt-info "scope")))
        (is (string= "top-level"
                     (cadr-ai::json-get prompt-info "origin")))
        (is (string=
             (string-right-trim
              "/"
              (namestring
               (uiop:ensure-directory-pathname prompt-dir)))
             (cadr-ai::json-get prompt-info "baseDir")))
        (is (string= "skill"
                     (cadr-ai::json-get skill "source")))
        (is (string= "Demo skill"
                     (cadr-ai::json-get skill "description")))
        (is (string= "user"
                     (cadr-ai::json-get skill-info "scope")))
        (is (string=
             (string-right-trim
              "/"
              (namestring
               (uiop:ensure-directory-pathname skill-dir)))
             (cadr-ai::json-get skill-info "baseDir")))))))
