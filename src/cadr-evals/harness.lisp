(in-package #:cadr-evals)

(defstruct eval-result
  output
  (events nil)
  usage
  (errors nil)
  (recorded-artifacts nil :type list)
  (artifacts
    (make-hash-table :test #'equal)
    :type hash-table)
  (timings
    (make-hash-table :test #'equal)
    :type hash-table))

(defun eval-result-json (result)
  (cadr-ai::json-object
   "output" (eval-result-output result)
   "events"
   (cadr-ai::list-json-array
    (eval-result-events result))
   "usage" (eval-result-usage result)
   "errors"
   (cadr-ai::list-json-array
    (eval-result-errors result))
   "artifacts"
   (eval-result-artifacts result)
   "timings"
   (eval-result-timings result)))

(defparameter *eval-environment-function*
  #'uiop:getenv)

(defparameter *eval-root-observer*
  (constantly nil))

(defvar *eval-reload-reports* nil)

(defun default-eval-model-resolver
    (provider model)
  (let ((config
          (cadr-cli::resolve-provider-config
           :provider provider
           :model model)))
    (values
     (cadr-cli::provider-config-provider
      config)
     (cadr-cli::provider-config-model
      config)
     #'cadr-ai:stream-chat)))

(defparameter *eval-model-resolver*
  #'default-eval-model-resolver)

(defun make-eval-prompt-step (content)
  (list :type :prompt
        :content content))

(defun make-eval-reload-step ()
  (list :type :reload))

(defun eval-environment (name)
  (let ((value
          (funcall
           *eval-environment-function*
           name)))
    (and value
         (string-trim
          '(#\Space #\Tab
            #\Newline #\Return)
          value))))

(defun resolve-eval-selection
    (provider model)
  (flet ((trim-selection (value)
           (and
            value
            (string-trim
             '(#\Space #\Tab
               #\Newline #\Return)
             value))))
    (let ((resolved-provider
            (trim-selection
             (if provider
                 provider
                 (eval-environment
                  "CADR_EVAL_PROVIDER"))))
          (resolved-model
            (trim-selection
             (if model
                 model
                 (eval-environment
                  "CADR_EVAL_MODEL")))))
    (unless
        (and resolved-provider
             (plusp
              (length
               resolved-provider))
             resolved-model
             (plusp
              (length
               resolved-model)))
      (error
       'cadr-ai:configuration-error
       :message
       "Eval provider and model must both be selected explicitly"))
    (values resolved-provider
            resolved-model))))

(defun make-eval-root ()
  (let* ((base
           (uiop:ensure-directory-pathname
            (uiop:temporary-directory)))
         (root
           (merge-pathnames
            (format nil
                    "cadr-eval-~A/"
                    (cadr-ai:uuid-v7))
            base)))
    (when (probe-file root)
      (error "Eval directory collision: ~A"
             root))
    (ensure-directories-exist
     (merge-pathnames "anchor" root))
    root))

(defun step-value (step name)
  (cond
    ((hash-table-p step)
     (cadr-ai::json-get
      step
      (string-downcase
       (symbol-name name))))
    ((listp step)
     (or (getf step name)
         (getf step
               (intern
                (symbol-name name)
                :keyword))))
    (t nil)))

(defun normalize-step-type (value)
  (cond
    ((keywordp value) value)
    ((symbolp value)
     (intern
      (string-upcase
       (symbol-name value))
      :keyword))
    ((stringp value)
     (intern
      (string-upcase value)
      :keyword))
    (t nil)))

(defun normalize-eval-steps (input)
  (cond
    ((stringp input)
     (list
      (make-eval-prompt-step
       input)))
    ((and (listp input)
          (keywordp (first input)))
     (list input))
    ((or (listp input)
         (vectorp input))
     (coerce input 'list))
    (t
     (error
      'cadr-ai:configuration-error
      :message
      "Eval input must be a prompt string or a prompt/reload sequence"))))

(defun selected-eval-tools
    (cwd no-tools)
  (let ((tools
          (cadr-cli:make-coding-tools
           cwd)))
    (cond
      ((eq no-tools :all) nil)
      ((listp no-tools)
       (remove-if
        (lambda (tool)
          (member
           (cadr-ai:tool-name tool)
           no-tools
           :test #'string=))
        tools))
      (t tools))))

(defun eval-agent-tools (agent)
  (cadr-agent::registry-tools
   (cadr-agent::agent-tool-registry
    agent)))

(defun eval-extension-paths (agent)
  (let ((host
          (cadr-agent::agent-extension-host
           agent)))
    (if (not host)
        nil
        (loop
          for bundle in
          (cadr-agent::extension-snapshot-bundles
           (cadr-agent::extension-host-current-snapshot
            host))
          unless
          (cadr-agent::extension-bundle-hidden-p
           bundle)
            collect
            (cadr-agent::extension-bundle-path
             bundle)))))

(defun message-content-text (content)
  (cadr-ai:content-text content))

(defun transcript-message-event
    (role content)
  (cadr-ai::json-object
   "type" "message"
   "role" role
   "content" content))

(defun messages-to-transcript (messages)
  (let ((events nil))
    (dolist (message messages)
      (cond
        ((typep message
                'cadr-ai:user-message)
         (push
          (transcript-message-event
           "user"
           (message-content-text
            (cadr-ai:user-message-content
             message)))
          events))
        ((typep message
                'cadr-ai:assistant-message)
         (let ((text
                 (message-content-text
                  (cadr-ai:assistant-message-content
                   message))))
           (when (plusp (length text))
             (push
              (transcript-message-event
               "assistant" text)
              events)))
         (dolist
             (block
              (cadr-ai:assistant-message-content
               message))
           (when
               (typep block
                      'cadr-ai:tool-call)
             (push
              (cadr-ai::json-object
               "type" "tool_call"
               "id"
               (cadr-ai:tool-call-id block)
               "name"
               (cadr-ai:tool-call-name block)
               "arguments"
               (cadr-ai:tool-call-arguments
                block))
              events))))
        ((typep message
                'cadr-ai:tool-result-message)
         (let ((text
                 (message-content-text
                  (cadr-ai:tool-result-message-content
                   message))))
           (push
            (let ((event
                    (cadr-ai::json-object
                     "type" "tool_result"
                     "toolCallId"
                     (cadr-ai:tool-result-message-tool-call-id
                      message)
                     "name"
                     (cadr-ai:tool-result-message-tool-name
                      message)
                     "content" text)))
              (when
                  (cadr-ai:tool-result-message-is-error
                   message)
                (cadr-ai::json-put
                 event "error"
                 (cadr-ai::json-object
                  "message"
                  (if (plusp
                       (length text))
                      text
                      "Tool failed"))))
              event)
            events)))))
    (nreverse events)))

(defun eval-usage
    (messages model)
  (let ((input 0)
        (output 0)
        (cache-read 0)
        (cache-write 0)
        (tool-calls 0)
        (estimated-cost 0d0))
    (dolist (message messages)
      (when
          (typep message
                 'cadr-ai:assistant-message)
        (incf
         tool-calls
         (count-if
          (lambda (block)
            (typep block
                   'cadr-ai:tool-call))
          (cadr-ai:assistant-message-content
           message)))
        (let ((usage
                (cadr-ai:assistant-message-usage
                 message)))
          (when usage
            (incf input
                  (cadr-ai:usage-input
                   usage))
            (incf output
                  (cadr-ai:usage-output
                   usage))
            (incf cache-read
                  (cadr-ai:usage-cache-read
                   usage))
            (incf cache-write
                  (cadr-ai:usage-cache-write
                   usage))
            (incf
             estimated-cost
             (cadr-ai:cost-total
              (cadr-ai:usage-cost
               usage)))))))
    (let ((metadata
            (cadr-ai::json-object
             "cacheReadTokens" cache-read
             "cacheWriteTokens" cache-write)))
      (when (plusp estimated-cost)
        (cadr-ai::json-put
         metadata "estimatedCostUsd"
         estimated-cost))
      (cadr-ai::json-object
       "provider"
       (string-downcase
        (symbol-name
         (cadr-ai:model-provider model)))
       "model" (cadr-ai:model-id model)
       "inputTokens" input
       "outputTokens" output
       "totalTokens"
       (+ input output
          cache-read cache-write)
       "toolCalls" tool-calls
       "metadata" metadata))))

(defun eval-elapsed-milliseconds (started)
  (* 1000d0
     (/ (- (get-internal-real-time)
           started)
        internal-time-units-per-second)))

(defun last-assistant-since
    (agent start)
  (find-if
   (lambda (message)
     (typep message
            'cadr-ai:assistant-message))
   (nthcdr
    start
    (cadr-agent:agent-messages
     agent))
   :from-end t))

(defun prompt-eval-agent
    (agent content)
  (let ((start
          (length
           (cadr-agent:agent-messages
            agent))))
    (cadr-agent:agent-prompt
     agent content)
    (let ((assistant
            (last-assistant-since
             agent start)))
      (unless assistant
        (error
         "Agent run completed without an assistant message"))
      (unless
          (eq :stop
              (cadr-ai:assistant-message-stop-reason
               assistant))
        (error
         "~A"
         (or
          (cadr-ai:assistant-message-error-message
           assistant)
          (format nil
                  "Agent run ended with unexpected stop reason: ~A"
                  (cadr-ai:assistant-message-stop-reason
                   assistant)))))
      (let ((output
              (message-content-text
               (cadr-ai:assistant-message-content
                assistant))))
        (when (zerop (length output))
          (error
           "Agent run produced no assistant text"))
        output))))

(defun reload-eval-extensions
    (manager agent
     &key (errors-are-fatal-p t))
  (let ((report
          (cadr-cli::reload-cli-extensions
           manager)))
    (push report *eval-reload-reports*)
    (when (and errors-are-fatal-p
               (getf report :errors))
      (error
       "Eval extension reload failed: ~{~A~^; ~}"
       (getf report :errors)))
    (cadr-agent::refresh-agent-extension-tools
     agent)
    report))

(defun release-eval-extensions (manager)
  (when manager
    (ignore-errors
      (cadr-agent::replace-extension-bundles
       (cadr-cli::cli-extension-manager-host
        manager)
       nil)))
  nil)

(defun shutdown-eval-agent (agent)
  (when agent
    (let ((host
            (cadr-agent::agent-extension-host
             agent)))
      (when
          (and host
               (cadr-agent::extension-host-session-started-p
                host))
        (ignore-errors
          (cadr-agent::run-extension-lifecycle-hooks
           host :session-shutdown
           :payload
           '(:reason :exit))))))
  nil)

(defun run-coding-agent-eval
    (input
     &key provider model no-tools
       selector
       transform-system-prompt
       abort-p
       allow-extension-errors-p)
  (let ((*eval-reload-reports* nil)
        (started
          (get-internal-real-time)))
    (multiple-value-bind
        (provider-name model-id)
      (resolve-eval-selection
       provider model)
    (multiple-value-bind
          (provider-object model-object
           stream-function)
        (funcall
         *eval-model-resolver*
         provider-name model-id)
      (unless model-object
        (error
         'cadr-ai:configuration-error
         :message
         (format nil
                 "Eval model not found: ~A/~A"
                 provider-name model-id)))
      (let* ((root (make-eval-root))
             (cwd
               (merge-pathnames
                "workspace/" root))
             (agent-directory
               (merge-pathnames
                "agent/" root))
             (session-directory
               (merge-pathnames
                "sessions/" agent-directory))
             (extension-directory
               (merge-pathnames
                "extensions/" agent-directory))
             (manager nil)
             (agent nil)
             (outcome nil)
             (failure nil))
        (funcall *eval-root-observer*
                 root)
        (unwind-protect
             (handler-case
                 (progn
                   (ensure-directories-exist
                    (merge-pathnames
                     "anchor" cwd))
                   (ensure-directories-exist
                    (merge-pathnames
                     "anchor"
                     agent-directory))
                   (setf
                    manager
                    (cadr-cli::make-cli-extension-manager
                     :cwd cwd
                     :global-directory
                     extension-directory
                     :output
                     (make-string-output-stream)
                     :mode :rpc))
                   ;; The eval package mirrors the baseline's empty,
                   ;; isolated extension start. Bundled CLI factories
                   ;; are not eval inputs.
                   (setf
                    (cadr-cli::cli-extension-manager-extension-factories
                     manager)
                    nil)
                   (let ((initial
                           (cadr-cli::reload-cli-extensions
                            manager)))
                     (when
                         (or
                          (getf initial :errors)
                          (plusp
                           (getf initial :active)))
                       (error
                        "Expected isolated eval session to start without extensions")))
                   (let* ((tools
                            (selected-eval-tools
                             cwd no-tools))
                          (host
                            (cadr-cli::cli-extension-manager-host
                             manager))
                          (session
                            (cadr-agent:create-session
                             :directory
                             session-directory
                             :cwd cwd))
                          (default-system-prompt
                            (cadr-cli::build-system-prompt
                             :selected-tools
                             (mapcar
                              #'cadr-ai:tool-name
                              tools)
                             :tool-snippets
                             (cadr-cli::tool-prompt-snippets
                              tools)
                             :cwd
                             (namestring cwd)))
                          (system-prompt
                            (if transform-system-prompt
                                (funcall
                                 transform-system-prompt
                                 default-system-prompt)
                                default-system-prompt)))
                     (unless
                         (and
                          (stringp system-prompt)
                          (plusp
                           (length
                            (string-trim
                             '(#\Space #\Tab
                               #\Newline #\Return)
                             system-prompt))))
                       (error
                        "Transformed eval system prompt must not be empty"))
                     (setf
                      agent
                      (cadr-agent:make-agent
                       :provider provider-object
                       :model model-object
                       :system-prompt system-prompt
                       :tools tools
                       :extension-host host
                       :session session
                       :abort-p abort-p
                       :auto-compact-p nil
                       :stream-function
                       (cadr-cli::make-extension-aware-stream-function
                        host
                        :stream-function
                        stream-function
                        :session-id
                        (cadr-agent:session-id
                         session))))
                     (let ((response nil))
                       (dolist
                           (step
                            (normalize-eval-steps
                             input))
                         (case
                             (normalize-step-type
                              (step-value
                               step :type))
                           (:prompt
                            (let ((content
                                    (step-value
                                     step
                                     :content)))
                              (unless
                                  (stringp content)
                                (error
                                 "Eval prompt content must be a string"))
                              (setf response
                                    (prompt-eval-agent
                                     agent content))))
                           (:reload
                            (reload-eval-extensions
                             manager agent
                             :errors-are-fatal-p
                             (not
                              allow-extension-errors-p)))
                           (otherwise
                            (error
                             "Unknown eval step: ~S"
                             step))))
                       (unless response
                         (error
                          "Eval input must include at least one prompt step"))
                       (let ((messages
                               (cadr-agent:agent-messages
                                agent)))
                         (setf
                          outcome
                          (make-eval-result
                           :output
                           (if selector
                               (funcall
                                selector
                                response agent
                                manager)
                               response)
                           :events
                           (messages-to-transcript
                            messages)
                           :usage
                           (eval-usage
                            messages
                            model-object)
                           :errors
                           (loop
                             for report in
                             (reverse
                              *eval-reload-reports*)
                             append
                             (copy-list
                              (getf report :errors)))
                           :artifacts
                           (cadr-ai::json-object
                            "runId"
                            (cadr-agent:session-id
                             session))))))))
               (error (cause)
                 (setf failure cause)))
          (shutdown-eval-agent agent)
          (release-eval-extensions
           manager)
          (when (and outcome agent)
            (handler-case
                (let* ((session
                         (cadr-agent:agent-session
                          agent))
                       (path
                         (and
                          session
                          (cadr-agent:session-path
                           session))))
                  (when (and path
                             (probe-file path))
                    (setf
                     (gethash
                      +cadr-session-snapshot-artifact+
                      (eval-result-artifacts
                       outcome))
                     (uiop:read-file-string
                      path
                      :external-format
                      :utf-8))))
              (error (snapshot-cause)
                (if failure
                    (setf
                     failure
                     (make-condition
                      'simple-error
                      :format-control
                      "Eval failed (~A) and session snapshot failed (~A)"
                      :format-arguments
                      (list failure
                            snapshot-cause)))
                    (setf failure
                          snapshot-cause)))))
          (when (probe-file root)
            (handler-case
                (uiop:delete-directory-tree
                 root
                 :validate t
                 :if-does-not-exist
                 :ignore)
              (error (cleanup-cause)
                (if failure
                    (setf
                     failure
                     (make-condition
                      'simple-error
                      :format-control
                      "Eval failed (~A) and cleanup failed (~A)"
                      :format-arguments
                      (list failure
                            cleanup-cause)))
                    (setf failure
                          cleanup-cause))))))
        (when failure
          (error failure))
        (setf
         (eval-result-timings outcome)
         (cadr-ai::json-object
          "totalMs"
          (eval-elapsed-milliseconds
           started)))
        outcome)))))
