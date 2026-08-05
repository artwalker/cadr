(require :asdf)

(defparameter *event-diff-arguments* (uiop:command-line-arguments))

(when (< (length *event-diff-arguments*) 9)
  (format *error-output*
          "usage: cadr-driver.lisp PROJECT QUICKLISP MANIFEST SCENARIO MODE CWD AGENT-DIR SESSION-DIR SIDECAR~%")
  (uiop:quit 2))

(let* ((project
         (uiop:ensure-directory-pathname
          (pathname (first *event-diff-arguments*))))
       (quicklisp (pathname (second *event-diff-arguments*)))
       (sink (make-broadcast-stream)))
  (let ((*standard-output* sink)
        (*error-output* sink)
        (*trace-output* sink))
    (load quicklisp)
    (dolist (name '("cadr-core.asd" "cadr-ai.asd" "cadr-agent.asd"
                    "cadr-tui.asd" "cadr-cli.asd"))
      (asdf:load-asd (truename (merge-pathnames name project))))
    (asdf:load-system "cadr-cli")))

(defpackage #:goal17-event-diff-cadr-driver
  (:use #:cl))

(in-package #:goal17-event-diff-cadr-driver)

(defconstant +fixed-timestamp+ 1700000000000)

(setf (symbol-function 'cadr-core:unix-milliseconds)
      (lambda () +fixed-timestamp+))

(defun json-get (object key &optional default)
  (if (hash-table-p object)
      (multiple-value-bind (value present-p) (gethash key object)
        (if present-p value default))
      default))

(defun json-list (value)
  (if (vectorp value) (coerce value 'list) nil))

(defun find-scenario (manifest name)
  (or
   (find name
         (json-list (json-get manifest "scenarios"))
         :test #'string=
         :key (lambda (scenario) (json-get scenario "name")))
   (error "Unknown event-diff scenario: ~A" name)))

(defun stop-reason (value)
  (cond
    ((or (null value) (string= value "stop")) :stop)
    ((string= value "toolUse") :tool-use)
    ((string= value "error") :error)
    ((string= value "aborted") :aborted)
    (t (error "Unsupported faux stop reason: ~A" value))))

(defun response-block (spec)
  (let ((type (json-get spec "type")))
    (cond
      ((string= type "text")
       (cadr-ai:faux-text (json-get spec "text" "")))
      ((string= type "toolCall")
       (cadr-ai:faux-tool-call
        (json-get spec "name" "")
        (or (json-get spec "arguments") (cadr-ai::json-object))
        :id (json-get spec "id")))
      (t (error "Unsupported event-diff response block: ~A" type)))))

(defun response-message (spec)
  (cadr-ai:faux-assistant-message
   (mapcar #'response-block (json-list (json-get spec "content")))
   :stop-reason (stop-reason (json-get spec "stopReason"))
   :error-message (json-get spec "errorMessage")
   :response-id "event-diff-response"
   :timestamp +fixed-timestamp+))

(defun seed-message (spec index)
  (let ((timestamp (+ +fixed-timestamp+ index)))
    (if (string= (json-get spec "role") "user")
        (cadr-ai:make-user-message
         :content (json-get spec "text" "")
         :timestamp timestamp)
        (cadr-ai:faux-assistant-message
         (json-get spec "text" "")
         :response-id (format nil "event-seed-~D" index)
         :timestamp timestamp))))

(defun write-sidecar (path count)
  (with-open-file (stream path
                          :direction :output
                          :if-exists :supersede
                          :if-does-not-exist :create)
    (write-line
     (cadr-ai::stringify-json
      (cadr-ai::json-object "toolCallErrorHooks" count))
     stream)
    (finish-output stream)))

(defun configure-event-extension-host (host scenario sidecar)
  (let ()
    (when (json-get scenario "toolCallErrorSidecar")
      (let ((count 0)
            (bundle
              (cadr-agent::make-extension-bundle
               :id "event-diff-tool-call-error"
               :path "<event-diff>"
               :scope :project)))
        (cadr-agent::call-with-extension-registration
         bundle
         (lambda ()
           (cadr-agent:define-event-hook
            :tool-call-error
            :handler
            (lambda (event context)
              (declare (ignore event context))
              (incf count)
              (write-sidecar sidecar count)
              nil))))
        (cadr-agent::replace-extension-bundles host (list bundle))))
    host))

(defun fixture-tool ()
  (cadr-ai:make-tool
   :name "fixture_fail"
   :description "Deterministically fails for event differential coverage."
   :parameters
   (cadr-ai::json-object
    "type" "object"
    "properties"
    (cadr-ai::json-object
     "value" (cadr-ai::json-object "type" "string"))
    "required" (vector "value"))
   :executor
   (lambda (call-id arguments)
     (declare (ignore call-id arguments))
     (error "fixture tool failure"))))

(defun split-faux-text (text token-size)
  (loop for start from 0 below (length text) by (* 4 token-size)
        collect (subseq text start
                        (min (length text) (+ start (* 4 token-size))))))

(defun aligned-faux-stream
    (handle agent mode action token-size model context on-event options)
  (let* ((empty-queue-p
           (zerop (cadr-ai:faux-pending-response-count handle)))
         (effective-options
           (append options (list :session-id "event-diff-session")))
         (message (cadr-ai::faux-resolve
                   handle model context effective-options)))
    ;; The fixed-baseline faux provider estimates usage even for its synthesized
    ;; empty-queue error, and emits that finalized error without a preceding
    ;; pending start event.  The production Cadr faux provider intentionally has
    ;; a smaller test-only contract, so align that one terminal fixture here.
    (when empty-queue-p
      (cadr-ai::faux-with-usage
       handle message context "event-diff-session"
       (getf effective-options :cache-retention))
      (cadr-ai::faux-emit on-event :error message :reason :error)
      (return-from aligned-faux-stream message))
    (when (member (cadr-ai:assistant-message-stop-reason message)
                  '(:error :aborted))
      (cadr-ai::faux-emit
       on-event :start
       (cadr-ai:make-assistant-message
        :api (cadr-ai:assistant-message-api message)
        :provider (cadr-ai:assistant-message-provider message)
        :model (cadr-ai:assistant-message-model message)
        :content (copy-list (cadr-ai:assistant-message-content message))
        :usage (cadr-ai:assistant-message-usage message)
        :stop-reason :pending
        :error-message (cadr-ai:assistant-message-error-message message)
        :response-id (cadr-ai:assistant-message-response-id message)
        :timestamp (cadr-ai:assistant-message-timestamp message)))
      (cadr-ai::faux-emit
       on-event :error message
       :reason (cadr-ai:assistant-message-stop-reason message))
      (return-from aligned-faux-stream message))
    (let ((partial
            (cadr-ai:make-assistant-message
             :api (cadr-ai:assistant-message-api message)
             :provider (cadr-ai:assistant-message-provider message)
             :model (cadr-ai:assistant-message-model message)
             :content nil
             :usage (cadr-ai:assistant-message-usage message)
             :stop-reason :pending
             :response-id (cadr-ai:assistant-message-response-id message)
             :timestamp (cadr-ai:assistant-message-timestamp message))))
      (cadr-ai::faux-emit on-event :start partial)
      (loop for block in (cadr-ai:assistant-message-content message)
            for index from 0
            do
            (cond
              ((typep block 'cadr-ai:text-content)
               (let ((partial-block
                       (cadr-ai:make-text-content
                        :text
                        (if (string= action "abort")
                            ""
                            (cadr-ai:text-content-text block)))))
                 (setf (cadr-ai:assistant-message-content partial)
                       (append (cadr-ai:assistant-message-content partial)
                               (list partial-block)))
                 (cadr-ai::faux-emit
                  on-event :text-start partial :content-index index)
                 (setf (cadr-ai:text-content-text partial-block) "")
                 (dolist (chunk
                          (split-faux-text
                           (cadr-ai:text-content-text block) token-size))
                   (setf (cadr-ai:text-content-text partial-block)
                         (concatenate
                          'string
                          (cadr-ai:text-content-text partial-block)
                          chunk))
                   (cadr-ai::faux-emit
                    on-event :text-delta partial
                    :content-index index :delta chunk)
                   (when (string= action "abort")
                     (if (eq mode :json)
                         (cadr-agent:agent-abort agent)
                         (loop repeat 500
                               until (cadr-agent::agent-aborted-p agent)
                               do (sleep 0.002)))
                     (when (cadr-agent::agent-aborted-p agent)
                       (let ((aborted
                               (cadr-ai:make-assistant-message
                                :api (cadr-ai:assistant-message-api partial)
                                :provider (cadr-ai:assistant-message-provider partial)
                                :model (cadr-ai:assistant-message-model partial)
                                :content (copy-list
                                          (cadr-ai:assistant-message-content partial))
                                :usage (cadr-ai:assistant-message-usage partial)
                                :stop-reason :aborted
                                :error-message "Request was aborted"
                                :response-id
                                (cadr-ai:assistant-message-response-id partial)
                                :timestamp +fixed-timestamp+)))
                         (cadr-ai::faux-emit
                          on-event :error aborted :reason :aborted)
                         (return-from aligned-faux-stream aborted)))))
                 (cadr-ai::faux-emit
                  on-event :text-end partial :content-index index
                  :content (cadr-ai:text-content-text block))))
              ((typep block 'cadr-ai:tool-call)
               (setf (cadr-ai:assistant-message-content partial)
                     (append
                      (cadr-ai:assistant-message-content partial)
                      (list
                       (cadr-ai:make-tool-call
                        :id (cadr-ai:tool-call-id block)
                        :name (cadr-ai:tool-call-name block)
                        :arguments (cadr-ai:tool-call-arguments block)))))
               (cadr-ai::faux-emit
                on-event :tool-call-start partial :content-index index)
               (cadr-ai::faux-emit
                on-event :tool-call-delta partial :content-index index
                :delta (cadr-ai::stringify-json
                        (cadr-ai:tool-call-arguments block)))
               (cadr-ai::faux-emit
                on-event :tool-call-end partial :content-index index
                :tool-call block))
              (t
               (error "Unsupported aligned faux content block: ~S" block))))
      (cadr-ai::faux-emit
       on-event :done message
       :reason (cadr-ai:assistant-message-stop-reason message))
      message)))

(defun make-session (directory cwd scenario)
  (let ((session
          (cadr-agent:create-session
           :directory directory
           :cwd cwd
           :id "event-diff-session"
           :timestamp +fixed-timestamp+)))
    (loop for spec in (json-list (json-get scenario "seedMessages"))
          for index from 0
          do (cadr-agent:session-append-message
              session (seed-message spec index)))
    session))

(defun run-scenario
    (scenario mode cwd agent-directory session-directory sidecar)
  (declare (ignore agent-directory))
  (write-sidecar sidecar 0)
  (let* ((context-window (json-get scenario "contextWindow" 128000))
         (compaction (json-get scenario "compaction"))
         (reserve (json-get compaction "reserveTokens" 16))
         (keep-recent (json-get compaction "keepRecentTokens" 16))
         (retry (json-get scenario "retry"))
         (handle
           (cadr-ai:make-faux-provider
            :api :event-diff-faux
            :provider-id :faux
            :model-definitions
            (list
             (list :id "faux-1" :name "Faux Model"
                   :context-window context-window
                   :max-tokens 16384))
            :token-min (json-get (json-get scenario "stream") "tokenSize" 4096)
            :token-max (json-get (json-get scenario "stream") "tokenSize" 4096)))
         (session (make-session session-directory cwd scenario))
         (manager
           (cadr-cli::make-cli-extension-manager
            :cwd cwd
            :global-directory (merge-pathnames "extensions/" cwd)
            :no-discovery-p t
            :output *error-output*
            :mode mode))
         (host nil)
         (agent nil)
         (token-size
           (json-get (json-get scenario "stream") "tokenSize" 4096))
         (base-stream
           (lambda (provider model context on-event &rest options)
             (declare (ignore provider))
             (aligned-faux-stream
              handle agent mode
              (json-get scenario "action")
              token-size model context on-event options))))
    (setf host (cadr-cli::cli-extension-manager-host manager))
    (configure-event-extension-host host scenario sidecar)
    (cadr-ai:faux-set-responses
     handle
     (mapcar #'response-message
             (json-list (json-get scenario "responses"))))
    (setf
     agent
     (cadr-agent:make-agent
      :provider :faux
      :model (cadr-ai:faux-get-model handle)
      :system-prompt
      (format nil
              "Event differential fixed system prompt.~%Current working directory: ~A"
              (string-right-trim "/" (namestring cwd)))
      :tools (list (fixture-tool))
      :extension-host host
      :session session
      :auto-compact-p
      (not (null (search "compaction" (json-get scenario "action"))))
      :compaction-reserve-tokens reserve
      :compaction-keep-recent-tokens keep-recent
      :stream-function base-stream))
    (setf
     (cadr-agent::agent-auto-retry-p agent)
     (not (null (json-get retry "enabled" nil)))
     (cadr-agent::agent-auto-retry-max-attempts agent)
     (json-get retry "maxRetries" 0)
     (cadr-agent::agent-auto-retry-base-delay agent)
     (/ (json-get retry "baseDelayMs" 0) 1000d0))
    (unwind-protect
         (cond
           ((eq mode :rpc)
            (cadr-cli::run-rpc-mode
             agent manager
             :input *standard-input*
             :output *standard-output*
             :error-output *error-output*))
           ((string= (json-get scenario "action") "manual-compaction")
            (cadr-cli::write-json-line
             (cadr-cli::wire-session-header-to-json session)
             *standard-output*)
            (setf
             (cadr-agent::agent-on-event agent)
             (cadr-cli::make-json-event-renderer *standard-output*))
            (cadr-agent:compact-agent agent :force-p t :reason :manual))
           (t
            (cadr-cli::run-print-mode
             agent
             (json-get scenario "prompt")
             nil
             :mode :json
             :output *standard-output*
             :error-output *error-output*)))
        (unless (cadr-agent::agent-shutdown-p agent)
          (cadr-agent:agent-shutdown agent)))))

(defun main ()
  (destructuring-bind
      (project quicklisp manifest-path scenario-name mode-name cwd-path
       agent-directory-path session-directory-path sidecar-path)
      (subseq cl-user::*event-diff-arguments* 0 9)
    (declare (ignore project quicklisp))
    (let* ((manifest
             (cadr-ai::parse-json
              (uiop:read-file-string manifest-path)))
           (scenario (find-scenario manifest scenario-name))
           (mode (if (string= mode-name "rpc") :rpc :json))
           (cwd (uiop:ensure-directory-pathname (pathname cwd-path)))
           (agent-directory
             (uiop:ensure-directory-pathname
              (pathname agent-directory-path)))
           (session-directory
             (uiop:ensure-directory-pathname
              (pathname session-directory-path))))
      (run-scenario
       scenario mode cwd agent-directory session-directory sidecar-path))))

(cadr-cli::call-with-fatal-condition-boundary #'main)
