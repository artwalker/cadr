(require :asdf)

(defparameter *render-diff-arguments* (uiop:command-line-arguments))

(when (< (length *render-diff-arguments*) 6)
  (format *error-output*
          "usage: cadr-driver.lisp PROJECT QUICKLISP MANIFEST SCENARIO CWD AGENT-DIR~%")
  (uiop:quit 2))

(let* ((project
         (uiop:ensure-directory-pathname
          (pathname (first *render-diff-arguments*))))
       (quicklisp (pathname (second *render-diff-arguments*)))
       (sink (make-broadcast-stream)))
  (let ((*standard-output* sink)
        (*error-output* sink)
        (*trace-output* sink))
    (load quicklisp)
    (dolist (name '("cadr-core.asd" "cadr-ai.asd" "cadr-agent.asd"
                    "cadr-tui.asd" "cadr-cli.asd"))
      (asdf:load-asd (truename (merge-pathnames name project))))
    (asdf:load-system "cadr-cli")))

(defpackage #:goal15-render-diff-cadr-driver
  (:use #:cl))

(in-package #:goal15-render-diff-cadr-driver)

(defconstant +fixed-timestamp+ 1700000000000)

(defun json-get (object key &optional default)
  (if (hash-table-p object)
      (multiple-value-bind (value present-p) (gethash key object)
        (if present-p value default))
      default))

(defun json-vector-list (value)
  (if (vectorp value) (coerce value 'list) nil))

(defun find-scenario (manifest scenario-id)
  (or
   (find scenario-id
         (json-vector-list (json-get manifest "scenarios"))
         :test #'string=
         :key (lambda (candidate) (json-get candidate "id")))
   (error "Unknown render-diff scenario: ~A" scenario-id)))

(defun stop-reason (value)
  (cond
    ((or (null value) (string= value "stop")) :stop)
    ((string= value "toolUse") :tool-use)
    ((string= value "length") :length)
    ((string= value "error") :error)
    ((string= value "aborted") :aborted)
    (t (error "Unsupported faux stop reason: ~A" value))))

(defun response-block (spec)
  (let ((type (json-get spec "type")))
    (cond
      ((string= type "text")
       (cadr-ai:faux-text (json-get spec "text" "")))
      ((string= type "thinking")
       (cadr-ai:faux-thinking (json-get spec "text" "")))
      ((string= type "toolCall")
       (cadr-ai:faux-tool-call
        (json-get spec "name" "")
        (or (json-get spec "arguments") (cadr-ai::json-object))
        :id (json-get spec "id")))
      (t (error "Unsupported faux block type: ~A" type)))))

(defun response-message (spec)
  (cadr-ai:faux-assistant-message
   (mapcar #'response-block
           (json-vector-list (json-get spec "content")))
   :stop-reason (stop-reason (json-get spec "stopReason"))
   :error-message (json-get spec "errorMessage")
   :response-id "render-diff-response"
   :timestamp +fixed-timestamp+))

(defun write-ready-marker ()
  (let ((path (uiop:getenv "RENDER_DIFF_READY_PATH")))
    (when (and path (plusp (length path)))
      (with-open-file (stream path :direction :output
                                   :if-exists :supersede
                                   :if-does-not-exist :create)
        (write-line "ready" stream)
        (finish-output stream)))))

(defun seed-message (spec index)
  (let ((role (json-get spec "role"))
        (text (json-get spec "text" ""))
        (timestamp (+ +fixed-timestamp+ index)))
    (cond
      ((string= role "user")
       (cadr-ai:make-user-message
        :content text :timestamp timestamp))
      ((string= role "assistant")
       (cadr-ai:make-assistant-message
        :content (list (cadr-ai:make-text-content :text text))
        :api :faux :provider :faux :model "faux-1"
        :usage (cadr-ai:make-usage)
        :stop-reason :stop
        :response-id (format nil "render-seed-~D" index)
        :timestamp timestamp))
      (t (error "Unsupported seed role: ~A" role)))))

(defun append-seed-messages (session setup)
  (loop for spec in
          (json-vector-list (json-get setup "seedMessages"))
        for index from 0
        do (cadr-agent:session-append-message
            session (seed-message spec index)))
  session)

(defun make-render-session (cwd agent-dir scenario)
  (let* ((setup (json-get scenario "setup"))
         (persistent-p
           (not (null (json-get setup "persistentSession"))))
         (directory
           (uiop:ensure-directory-pathname
            (merge-pathnames "render-sessions/" agent-dir)))
         (session
           (cadr-agent:create-session
            :directory directory
            :cwd cwd
            :id "render-session"
            :timestamp +fixed-timestamp+))
         (sessions (list session)))
    (append-seed-messages session setup)
    (when persistent-p
      (let ((other
              (cadr-agent:create-session
               :directory directory
               :cwd cwd
               :id "other-session"
               :timestamp +fixed-timestamp+)))
        (dolist
            (message
             (list
              (cadr-ai:make-user-message
               :content "other session question"
               :timestamp +fixed-timestamp+)
              (cadr-ai:make-assistant-message
               :content
               (list
                (cadr-ai:make-text-content
                 :text "other session answer"))
               :api :faux :provider :faux :model "faux-1"
               :usage (cadr-ai:make-usage)
               :stop-reason :stop
               :timestamp (1+ +fixed-timestamp+))))
          (cadr-agent:session-append-message other message))
        (setf sessions (append sessions (list other)))))
    (values session directory persistent-p sessions)))

(defun stream-aborted-p (options)
  (cadr-core:cancellation-predicate-aborted-p
   (getf options :abort-p)))

(defun emit-stream-abort (handle model on-event)
  (let ((message
          (cadr-ai::faux-error-message
           handle model "Request was aborted" t)))
    (cadr-ai::faux-emit
     on-event :error message :reason :aborted)
    message))

(defun slow-faux-stream
    (handle model context on-event options
     chunk-characters tokens-per-second)
  (let* ((message
          (if (stream-aborted-p options)
              nil
              (cadr-ai::faux-resolve
               handle model context options)))
         (partial
           (and
            message
            (cadr-ai:make-assistant-message
             :api (cadr-ai:assistant-message-api message)
             :provider (cadr-ai:assistant-message-provider message)
             :model (cadr-ai:assistant-message-model message)
             :content nil
             :usage (cadr-ai:assistant-message-usage message)
             :stop-reason :pending
             :response-id
             (cadr-ai:assistant-message-response-id message)
             :timestamp
             (cadr-ai:assistant-message-timestamp message)))))
    (unless message
      (return-from slow-faux-stream
        (emit-stream-abort handle model on-event)))
    (when (member (cadr-ai:assistant-message-stop-reason message)
                  '(:error :aborted))
      (cadr-ai::faux-emit
       on-event :error message
       :reason (cadr-ai:assistant-message-stop-reason message))
      (return-from slow-faux-stream message))
    (cadr-ai::faux-emit on-event :start partial)
    (loop for block in (cadr-ai:assistant-message-content message)
          for index from 0
          do
          (cond
            ((typep block 'cadr-ai:text-content)
             (let* ((text (cadr-ai:text-content-text block))
                    (partial-block
                      (cadr-ai:make-text-content :text "")))
               (setf
                (cadr-ai:assistant-message-content partial)
                (append
                 (cadr-ai:assistant-message-content partial)
                 (list partial-block)))
               (cadr-ai::faux-emit
                on-event :text-start partial :content-index index)
               (loop for start from 0 below (length text)
                     by chunk-characters
                     for end = (min (length text)
                                    (+ start chunk-characters))
                     do
                     (sleep
                      (/ (max 1 (ceiling (- end start) 4))
                         (coerce tokens-per-second 'double-float)))
                     (when (stream-aborted-p options)
                       (return-from slow-faux-stream
                         (emit-stream-abort handle model on-event)))
                     (let ((chunk (subseq text start end)))
                       (setf
                        (cadr-ai:text-content-text partial-block)
                        (concatenate
                         'string
                         (cadr-ai:text-content-text partial-block)
                         chunk))
                       (cadr-ai::faux-emit
                        on-event :text-delta partial
                        :content-index index :delta chunk)))
               (cadr-ai::faux-emit
                on-event :text-end partial
                :content-index index :content text)))
            (t
             (error
              "Slow render-diff stream only supports text blocks"))))
    (cadr-ai::faux-emit
     on-event :done message
     :reason (cadr-ai:assistant-message-stop-reason message))
    message))

(defun render-models ()
  (list
   (cadr-ai:make-model
    :id "faux-1" :name "Faux Model"
    :provider :faux :api :faux
    :base-url "http://localhost:0"
    :reasoning-p t :context-window 128000
    :max-tokens 16384)
   (cadr-ai:make-model
    :id "other-1" :name "Other Model"
    :provider :other :api :openai-completions
    :base-url "https://render.invalid/v1"
    :context-window 64000 :max-tokens 8192)))

(defun render-auth-options ()
  (stable-sort
   (append
    (cadr-cli::login-provider-options
     (cadr-ai:list-provider-definitions))
    (list
     (cadr-cli::make-oauth-selector-option
      :id :render-auth :name "Render Auth"
      :auth-type :oauth
      :method-name "Render Auth account"
      :status '(:type :api-key :source "configured provider"))
     (cadr-cli::make-oauth-selector-option
      :id :render-auth :name "Render Auth"
      :auth-type :api-key
      :method-name "Render Auth API key"
      :status '(:type :api-key :source "configured provider"))))
   #'string-lessp
   :key #'cadr-cli::oauth-selector-option-name))

(defun render-session-items (sessions)
  (mapcar
   (lambda (session)
     (cadr-tui:make-select-item
      :label
      (format nil "~A  ~D messages"
              (cadr-agent:session-id session)
              (length (cadr-agent:session-messages session)))
      :value session))
   sessions))

(defun command-dispatcher
    (agent cwd session-directory settings-manager
     auth-prompt-consumer status-consumer)
  (lambda (line)
    (cond
      ((string= line "/login render-auth")
       (when auth-prompt-consumer
         (funcall
          auth-prompt-consumer
          (list
           :type :manual-code
           :title "Login to Render Auth"
           :url "https://auth.invalid/authorize?state=render-fixed"
           :instructions
           "A browser window should open. Complete login to finish."
           :message
           "Paste the authorization code"
           :cancel-function (constantly nil))))
       (values t nil))
      ((string= line "/reload")
       (let ((message nil))
         (cadr-cli::reload-cli-runtime
          agent settings-manager
          :completion-function
          (lambda (text) (setf message text)))
         (values t message)))
      (t
       (let ((output (make-string-output-stream)))
         (if
             (cadr-cli::handle-session-command
              line agent
              :directory session-directory
              :cwd cwd
              :output output)
             (values t (get-output-stream-string output))
             (values nil nil)))))))

(defun run-scenario (scenario cwd agent-dir)
  (multiple-value-bind
        (session session-directory persistent-p sessions)
      (make-render-session cwd agent-dir scenario)
    (let* ((stream (json-get scenario "stream"))
           (chunk-characters
             (or (json-get stream "chunkCharacters") 4096))
           (tokens-per-second
             (or (json-get stream "tokensPerSecond") 0))
           (handle
             (cadr-ai:make-faux-provider
              :model-definitions
              '((:id "faux-1" :name "Faux Model"
                 :reasoning-p t :context-window 128000
                 :max-tokens 16384))
              :token-min 4096 :token-max 4096))
           (event-consumer nil)
           (auth-url-consumer nil)
           (auth-prompt-consumer nil)
           (status-consumer nil)
           (abort-requested-p nil)
           (settings-manager
             (cadr-cli::make-memory-settings-manager))
           (resources (cadr-cli::make-resource-snapshot))
           (agent
             (cadr-agent:make-agent
              :provider :faux
              :model (cadr-ai:faux-get-model handle)
             :tools (cadr-cli::make-all-coding-tools cwd)
             :session session
              :auto-compact-p t
              :abort-p (lambda () abort-requested-p)
              :stream-function
              (lambda (provider model context on-event &rest options)
                (declare (ignore provider))
                (if (plusp tokens-per-second)
                    (slow-faux-stream
                     handle model context on-event options
                     chunk-characters tokens-per-second)
                    (apply #'cadr-ai:faux-stream
                           handle model context on-event options)))
              :on-event
              (lambda (event)
                (when event-consumer
                  (funcall event-consumer event))))))
      (cadr-ai:faux-set-responses
       handle
       (mapcar #'response-message
               (json-vector-list (json-get scenario "responses"))))
      (cadr-tui:set-current-theme :dark)
      (multiple-value-bind (compact expanded)
          (cadr-cli::make-tui-startup-lines resources)
        (let ((main-thread sb-thread:*current-thread*)
              (crash-after-ms
                (json-get (json-get scenario "setup")
                          "crashAfterMs")))
          (write-ready-marker)
          (when crash-after-ms
            (sb-thread:make-thread
             (lambda ()
               (sleep (/ crash-after-ms 1000d0))
               (sb-thread:interrupt-thread
                main-thread
                (lambda ()
                  (error "render-diff crash sentinel"))))
             :name "render-diff-crash-trigger"))
          (cadr-cli:run-tui
           (lambda (line)
             (cadr-agent:agent-prompt
              agent line :source :interactive))
           :command-function
           (lambda (line)
             (funcall
              (command-dispatcher
               agent cwd session-directory settings-manager
               auth-prompt-consumer status-consumer)
              line))
           :set-event-consumer
           (lambda (consumer) (setf event-consumer consumer))
           :set-auth-url-consumer
           (lambda (consumer) (setf auth-url-consumer consumer))
           :set-auth-prompt-consumer
           (lambda (consumer) (setf auth-prompt-consumer consumer))
           :set-status-consumer
           (lambda (consumer) (setf status-consumer consumer))
           :abort-function
           (lambda ()
             (setf abort-requested-p t)
             (cadr-agent:agent-abort agent))
           :reset-abort-function
           (lambda () (setf abort-requested-p nil))
           :busy-input-function
           (lambda (text)
             (cadr-agent:agent-steer agent text))
           :follow-up-input-function
           (lambda (text)
             (cadr-agent:agent-follow-up agent text))
           :dequeue-function
           (lambda ()
             (multiple-value-bind (steering follow-up)
                 (cadr-agent::clear-live-agent-queues agent)
               (mapcar
                (lambda (message)
                  (cadr-ai::content-text
                   (cadr-ai:user-message-content message)))
                (append steering follow-up))))
           :model-items-function #'render-models
           :model-selector-function
           (lambda (&optional query)
             (let ((state
                     (cadr-cli::make-model-selector-state
                      :all-models (render-models)
                      :scoped-models (render-models)
                      :current-model (first (render-models))
                      :refresh-status-message
                      "Model catalogs refreshed.")))
               (cadr-cli::model-selector-set-query
                state (or query ""))))
           :settings-selector-function
           (lambda ()
             (cadr-cli::make-cli-settings-selector-state
              settings-manager agent resources
              :supports-images-p nil))
           :trust-selector-function
           (lambda ()
             (cadr-cli::make-trust-selector-state
              :cwd (namestring cwd)
              :project-trusted-p
              (not
               (null
                (json-get
                 (json-get scenario "setup")
                 "projectTrusted" t)))))
           :fork-items-function
           (lambda ()
             (list
              (cadr-tui:make-select-item
               :label "overlay question" :value "u1")))
           :session-items-function
           (lambda ()
             (render-session-items sessions))
           :all-session-items-function
           (lambda ()
             (render-session-items sessions))
           :tree-state-function
           (lambda ()
             (cadr-cli::session-tree-selector-data session))
           :login-options-function #'render-auth-options
           :model "faux-1"
           :provider "faux"
           :thinking :high
           :cwd (namestring cwd)
           :footer-cwd (namestring cwd)
           :available-provider-count
           (if (member (json-get scenario "id")
                       '("overlays-core" "overlays-auth")
                       :test #'string=)
               2
               1)
           :context-window 128000
           :session session
           :messages (cadr-agent:agent-messages agent)
           :current-session-path
           (and persistent-p
                (namestring (cadr-agent:session-path session)))
           :startup-compact-lines compact
           :startup-expanded-lines expanded
           :alt-p nil
           :show-hardware-cursor-p nil))
        (when persistent-p
          (cadr-cli::write-session-resume-hint
           session session-directory
           :terminal-p t
           :default-session-directory-p nil)))
      (cadr-agent:agent-shutdown agent))))

(defun main ()
  (destructuring-bind
      (project quicklisp manifest-path scenario-id cwd-path agent-dir-path)
      (subseq cl-user::*render-diff-arguments* 0 6)
    (declare (ignore project quicklisp))
    (let* ((manifest
             (cadr-ai::parse-json
              (uiop:read-file-string manifest-path)))
           (scenario (find-scenario manifest scenario-id))
           (cwd (uiop:ensure-directory-pathname (pathname cwd-path)))
           (agent-dir
             (uiop:ensure-directory-pathname
              (pathname agent-dir-path))))
      (run-scenario scenario cwd agent-dir))))

(cadr-cli::call-with-fatal-condition-boundary #'main)
