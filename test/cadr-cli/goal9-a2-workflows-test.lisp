(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defun goal9-a2-message-transcript (messages)
  (with-output-to-string (stream)
    (dolist (message messages)
      (cond
        ((typep message 'cadr-ai:user-message)
         (let ((content
                 (cadr-ai:user-message-content message)))
           (when (stringp content)
             (write-string content stream))))
        ((typep message 'cadr-ai:assistant-message)
         (dolist (block
                  (cadr-ai:assistant-message-content message))
           (when (typep block 'cadr-ai:text-content)
             (write-string
              (cadr-ai:text-content-text block)
              stream))))))))

(defun goal9-a2-session-faux-agent (session responses)
  (multiple-value-bind (agent remaining)
      (cli-faux-agent responses)
    (setf (cadr-agent:agent-session agent) session
          (cadr-agent:agent-messages agent)
          (cadr-agent:session-messages session)
          (cadr-ai:model-context-window
           (cadr-agent:agent-model agent))
          16
          (cadr-agent::agent-auto-compact-p agent)
          nil)
    (values agent remaining)))

(test goal9-a2-session-workflows-are-deterministic-and-branches-stay-isolated
  (with-test-directory (root)
    (let* ((sessions (merge-pathnames "sessions/" root))
           (cwd (merge-pathnames "project/" root))
           (_
             (ensure-directories-exist
              (merge-pathnames "anchor" cwd)))
           (source
             (cadr-agent:create-session
              :directory sessions :cwd cwd :id "source"))
           (other
             (cadr-agent:create-session
              :directory sessions :cwd cwd :id "other"
              :timestamp 1))
           (output (make-string-output-stream))
           (export-path (merge-pathnames "workflow.html" root))
           (common-id
             (cadr-agent:session-append-message
              source
              (cadr-ai:make-user-message
               :content "common-root"))))
      (declare (ignore _))
      (cadr-agent:session-append-message
       other
       (cadr-ai:make-assistant-message
        :content
        (list
         (cadr-ai:make-text-content :text "other-session"))
        :api :openai-responses
        :provider :openai
        :model "mock"
        :stop-reason :stop
        :timestamp 1))
      (multiple-value-bind (agent remaining)
          (goal9-a2-session-faux-agent
           source
           (list
            (cli-test-assistant "branch-a-assistant")
            (cli-test-assistant "branch-b-assistant")
            (cli-test-assistant "compact-summary")))
        (is
         (cadr-cli::handle-session-command
          "/name workflow"
          agent :directory sessions :cwd cwd :output output))
        (is (string= "workflow"
                     (cadr-agent:session-name source)))

        (cadr-agent:session-branch source common-id)
        (setf (cadr-agent:agent-messages agent)
              (cadr-agent:session-messages source))
        (cadr-agent:agent-prompt agent "branch-a-user")
        (let ((branch-a-leaf
                (cadr-agent::session-leaf-id source)))
          (cadr-agent:session-branch source common-id)
          (setf (cadr-agent:agent-messages agent)
                (cadr-agent:session-messages source))
          (cadr-agent:agent-prompt agent "branch-b-user")
          (let* ((branch-b-leaf
                   (cadr-agent::session-leaf-id source))
                 (branch-a
                   (goal9-a2-message-transcript
                    (cadr-agent:session-messages
                     source branch-a-leaf)))
                 (branch-b
                   (goal9-a2-message-transcript
                    (cadr-agent:session-messages
                     source branch-b-leaf))))
            (is (search "branch-a-user" branch-a))
            (is (search "branch-a-assistant" branch-a))
            (is (not (search "branch-b-user" branch-a)))
            (is (not (search "branch-b-assistant" branch-a)))
            (is (search "branch-b-user" branch-b))
            (is (search "branch-b-assistant" branch-b))
            (is (not (search "branch-a-user" branch-b)))
            (is (not (search "branch-a-assistant" branch-b)))))

        (is
         (cadr-cli::handle-session-command
          "/compact preserve the branch decision"
          agent :directory sessions :cwd cwd :output output))
        (is
         (find :compaction
               (cadr-agent:session-entries source)
               :key #'cadr-agent:session-entry-type))
        (is (search
             "compact-summary"
             (goal9-a2-message-transcript
              (cadr-agent:agent-messages agent))))

        (is
         (cadr-cli::handle-session-command
          (format nil "/export ~A" (namestring export-path))
          agent :directory sessions :cwd cwd :output output))
        (is (probe-file export-path))
        (let ((html (read-text export-path)))
          (is (search "branch-a-user" html))
          (is (search "branch-b-user" html)))

        (cadr-cli::switch-agent-session agent other)
        (is (string= "other"
                     (cadr-agent:session-id
                      (cadr-agent:agent-session agent))))
        (cadr-cli::switch-agent-session agent source)
        (is (string= "source"
                     (cadr-agent:session-id
                      (cadr-agent:agent-session agent))))

        (is
         (cadr-cli::handle-session-command
          "/new"
          agent :directory sessions :cwd cwd :output output))
        (is (not
             (string= "source"
                      (cadr-agent:session-id
                       (cadr-agent:agent-session agent)))))
        (cadr-cli::switch-agent-session agent source)

        (let ((continue-arguments
                (cadr-cli::parse-cli-arguments '("--continue")))
              (resume-arguments
                (cadr-cli::parse-cli-arguments
                 '("--resume" "source"))))
          (is (cadr-cli::cli-arguments-continue-p
               continue-arguments))
          (is (string= "source"
                       (cadr-cli::cli-arguments-resume
                        resume-arguments)))
          (is (string=
               "source"
               (cadr-agent:session-id
                (cadr-cli::resolve-cli-session
                 :continue-p t
                 :cwd cwd
                 :directory sessions
                 :output output))))
          (is (string=
               "source"
               (cadr-agent:session-id
                (cadr-cli::resolve-cli-session
                 :resume-id "source"
                 :cwd cwd
                 :directory sessions
                 :output output)))))
        (is (null (funcall remaining)))
        (let ((text (get-output-stream-string output)))
          (is (search "Session name set: workflow" text))
          (is (search "New session started" text))
          (is (search "Exported" text)))))))

(defun goal9-a2-json-lines (text)
  (loop for line in
          (uiop:split-string text :separator '(#\Newline))
        unless (zerop (length line))
          collect (cadr-ai::parse-json line)))

(defun goal9-a2-wait-for-rpc-prompt (state)
  (join-rpc-prompt-worker state))

(test goal9-a2-print-json-and-rpc-modes-cover-the-real-contract
  (multiple-value-bind (agent remaining)
      (cli-faux-agent
       (list
        (cli-test-assistant "intermediate")
        (cli-test-assistant "final-only")))
    (let ((output (make-string-output-stream))
          (errors (make-string-output-stream)))
      (is (= 0
             (cadr-cli::run-print-mode
              agent "first" '("second")
              :mode :text
              :output output
              :error-output errors)))
      (is (string= (format nil "final-only~%")
                   (get-output-stream-string output)))
      (is (string= "" (get-output-stream-string errors)))
      (is (null (funcall remaining)))))

  (multiple-value-bind (agent remaining)
      (cli-faux-agent
       (list (cli-test-assistant "json-final")))
    (let ((output (make-string-output-stream))
          (errors (make-string-output-stream)))
      (is (= 0
             (cadr-cli::run-print-mode
              agent "json-prompt" nil
              :mode :json
              :output output
              :error-output errors)))
      (let ((records
              (goal9-a2-json-lines
               (get-output-stream-string output))))
        (is (equal
             '("agent_start"
               "turn_start"
               "message_start"
               "message_end"
               "message_start"
               "message_update"
               "message_end"
               "turn_end"
               "agent_end"
               "agent_settled")
             (mapcar
              (lambda (record)
                (cadr-ai::json-get record "type"))
              records))))
      (is (string= "" (get-output-stream-string errors)))
      (is (null (funcall remaining)))))

  (with-test-directory (directory)
    (let* ((output (make-string-output-stream))
           (state
             (make-rpc-test-state
              directory output
              (list (cli-test-assistant "rpc-final")))))
      (cadr-cli::rpc-handle-line
       state
       "{\"id\":\"state-1\",\"type\":\"get_state\"}")
      (cadr-cli::rpc-handle-line
       state
       "{\"id\":\"prompt-1\",\"type\":\"prompt\",\"message\":\"rpc-prompt\"}")
      (goal9-a2-wait-for-rpc-prompt state)
      (let* ((records (rpc-output-records output))
             (state-response
               (find "state-1" records
                     :key (lambda (record)
                            (cadr-ai::json-get record "id"))
                     :test #'string=))
             (prompt-responses
               (remove-if-not
                (lambda (record)
                  (and
                   (string= "response"
                            (cadr-ai::json-get record "type"))
                   (string= "prompt-1"
                            (cadr-ai::json-get record "id"))))
                records))
             (events
               (remove-if
                (lambda (record)
                  (string= "response"
                           (cadr-ai::json-get record "type")))
                records)))
        (is (not (null state-response)))
        (is (eq t (cadr-ai::json-get state-response "success")))
        (is (= 1 (length prompt-responses)))
        (is (eq t
                (cadr-ai::json-get
                 (first prompt-responses) "success")))
        (is (equal
             '("agent_start"
               "turn_start"
               "message_start"
               "message_end"
               "message_start"
               "message_update"
               "message_end"
               "turn_end"
               "agent_end"
               "agent_settled")
             (mapcar
              (lambda (record)
                (cadr-ai::json-get record "type"))
              events)))))))

(defun goal9-a2-extension-source ()
  (format
   nil
   "(defparameter *goal9-a2-api* (current-extension-api))~%
(define-flag \"goal9-a2-enabled\" :type :boolean :default t)~%
(define-prompt-template \"goal9-a2-template\" :template \"legacy=$1\")~%
(define-command \"goal9-a2-command\"~%
  :description \"Legacy-compatible command\"~%
  :handler (lambda (arguments context)~%
             (extension-context-notify context (format nil \"command:~~A\" arguments))~%
             (extension-context-custom context (lambda () '(\"custom-ui\")) :overlay-p t :overlay-options '(:width 40))))~%
(define-tool \"goal9-a2-tool\"~%
  :description \"Legacy-compatible tool\"~%
  :parameters (cadr-ai::json-object \"type\" \"object\" \"properties\" (cadr-ai::json-object \"value\" (cadr-ai::json-object \"type\" \"string\")) \"required\" (vector \"value\") \"additionalProperties\" nil)~%
  :handler (lambda (call-id arguments context)~%
             (declare (ignore call-id context))~%
             (values (list (cadr-ai:make-text-content :text (format nil \"tool:~~A\" (cadr-ai::json-get arguments \"value\")))) nil)))~%
(define-event-hook :agent-start~%
  :handler (lambda (event context)~%
             (declare (ignore event))~%
             (extension-context-notify context \"hook:agent-start\")))~%
(define-message-renderer \"goal9-a2-message\"~%
  :renderer (lambda (&rest values) (declare (ignore values)) '(\"custom-message-renderer\")))~%
(define-tool-renderer \"goal9-a2-tool\"~%
  :call (lambda (arguments context)~%
          (declare (ignore context))~%
          (list (format nil \"custom-tool-renderer:~~A\" (getf arguments :value)))))~%"))

(defun goal9-a2-extension-bundle (host source-path)
  (find
   (namestring (truename source-path))
   (cadr-agent::extension-snapshot-bundles
    (cadr-agent::extension-host-current-snapshot host))
   :key #'cadr-agent::extension-bundle-path
   :test #'string=))

(test goal9-a2-extension-workflow-covers-legacy-ui-renderers-and-stale-reload
  (with-test-directory (root)
    (let* ((cwd (merge-pathnames "project/" root))
           (global (merge-pathnames "global/" root))
           (source (merge-pathnames "goal9-a2.lisp" global))
           (output (make-string-output-stream))
           (custom-calls nil)
           (notifications nil)
           (manager
             (make-test-extension-manager cwd global output)))
      (ensure-directories-exist
       (merge-pathnames "anchor" cwd))
      (write-text source (goal9-a2-extension-source))
      (let ((report
              (cadr-cli::reload-cli-extensions manager)))
        (is (null (getf report :errors))))
      (setf
       (cadr-agent::extension-host-ui-function
        (cadr-cli::cli-extension-manager-host manager))
       (lambda (method arguments)
         (when (eq method :notify)
           (push (getf arguments :message) notifications))))
      (cadr-cli::configure-extension-ui-bridge
       manager
       :custom-function
       (lambda (factory overlay-p overlay-options)
         (push (list (funcall factory)
                     overlay-p overlay-options)
               custom-calls)
         :custom-result))
      (let* ((host
               (cadr-cli::cli-extension-manager-host manager))
             (bundle (goal9-a2-extension-bundle host source))
             (package
               (and bundle
                    (cadr-agent::extension-bundle-package bundle)))
             (api-symbol
               (and package
                    (find-symbol "*GOAL9-A2-API*" package)))
             (old-api (and api-symbol (symbol-value api-symbol))))
        (is (not (null bundle)))
        (is (not (null old-api)))
        (multiple-value-bind (template found-p)
            (cadr-cli::expand-cli-extension-prompt
             manager "/goal9-a2-template value")
          (is (not (null found-p)))
          (is (string= "legacy=value" template)))
        (is
         (cadr-cli::handle-extension-command
          "/goal9-a2-command payload" manager))
        (is (equal
             '(("custom-ui") t (:width 40))
             (first custom-calls)))
        (let ((renderer
                (cadr-agent::find-extension-message-renderer
                 host "goal9-a2-message")))
          (is (not (null renderer)))
          (is (equal
               '("custom-message-renderer")
               (funcall
                (cadr-agent::extension-renderer-definition-renderer
                 renderer)))))
        (multiple-value-bind (rendered handled-p)
            (cadr-agent::render-extension-tool-call
             host "goal9-a2-tool"
             '(:value "rendered")
             (list :state (make-hash-table)))
          (is (not (null handled-p)))
          (is (equal
               '("custom-tool-renderer:rendered")
               rendered)))

        (let* ((session
                 (cadr-agent:create-session
                  :directory (merge-pathnames "sessions/" root)
                  :cwd cwd :id "extension-workflow"))
               (responses
                 (list
                  (cadr-ai:make-assistant-message
                   :content
                   (list
                    (cadr-ai:make-tool-call
                     :id "goal9-a2-call"
                     :name "goal9-a2-tool"
                     :arguments (args "value" "ok")))
                   :api :openai-responses
                   :provider :openai
                   :model "mock"
                   :stop-reason :tool-use)
                  (cli-test-assistant "extension-finished")))
               (agent
                 (cadr-agent:make-agent
                  :provider :mock
                  :model (cli-mock-model)
                  :session session
                  :extension-host host
                  :auto-compact-p nil
                  :stream-function
                  (lambda (provider model context on-event
                           &key max-tokens temperature abort-p)
                    (declare
                     (ignore provider model context max-tokens
                             temperature abort-p))
                    (let ((message (pop responses)))
                      (funcall
                       on-event
                       (cadr-ai:make-stream-event
                        :type :start :message message))
                      message)))))
          (cadr-agent:agent-prompt agent "use the extension tool")
          (let ((result
                  (find-if
                   (lambda (message)
                     (and
                      (typep message
                             'cadr-ai:tool-result-message)
                      (string=
                       "goal9-a2-call"
                       (cadr-ai:tool-result-message-tool-call-id
                        message))))
                   (cadr-agent:agent-messages agent))))
            (is (not (null result)))
            (is (string=
                 "tool:ok"
                 (result-text
                  (cadr-ai:tool-result-message-content result)))))
          (is (null responses)))

        (is (find "command:payload" notifications
                  :test #'string=))
        (is (find "hook:agent-start" notifications
                  :test #'string=))
        (is
         (cadr-cli::handle-extension-command
          "/reload" manager))
        (signals cadr-agent:stale-extension-context
          (cadr-agent::extension-api-get-flag
           old-api "goal9-a2-enabled"))
        (multiple-value-bind (template found-p)
            (cadr-cli::expand-cli-extension-prompt
             manager "/goal9-a2-template after")
          (is (not (null found-p)))
          (is (string= "legacy=after" template)))))))
