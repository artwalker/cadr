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
   :timestamp 1700000000000))

(defun write-ready-marker ()
  (let ((path (uiop:getenv "RENDER_DIFF_READY_PATH")))
    (when (and path (plusp (length path)))
      (with-open-file (stream path :direction :output
                                   :if-exists :supersede
                                   :if-does-not-exist :create)
        (write-line "ready" stream)
        (finish-output stream)))))

(defun main ()
  (destructuring-bind
      (project quicklisp manifest-path scenario-id cwd-path agent-dir)
      (subseq cl-user::*render-diff-arguments* 0 6)
    (declare (ignore project quicklisp agent-dir))
    (let* ((manifest
             (cadr-ai::parse-json
              (uiop:read-file-string manifest-path)))
           (scenario (find-scenario manifest scenario-id))
           (cwd (uiop:ensure-directory-pathname (pathname cwd-path)))
           (handle
             (cadr-ai:make-faux-provider
              :model-definitions
              '((:id "faux-1" :name "Faux Model"
                 :reasoning-p t :context-window 128000
                 :max-tokens 16384))
              :token-min 4096 :token-max 4096))
           (event-consumer nil)
           (abort-requested-p nil)
           (agent
             (cadr-agent:make-agent
              :provider :faux
              :model (cadr-ai:faux-get-model handle)
              :tools (cadr-cli::make-all-coding-tools cwd)
              :auto-compact-p nil
              :abort-p (lambda () abort-requested-p)
              :stream-function
              (lambda (provider model context on-event &rest options)
                (declare (ignore provider))
                (apply #'cadr-ai:faux-stream
                       handle model context on-event options))
              :on-event
              (lambda (event)
                (when event-consumer
                  (funcall event-consumer event))))))
      (cadr-ai:faux-set-responses
       handle
       (mapcar #'response-message
               (json-vector-list (json-get scenario "responses"))))
      (cadr-tui:set-current-theme :dark)
      (unwind-protect
           (multiple-value-bind (compact expanded)
               (cadr-cli::make-tui-startup-lines
                (cadr-cli::make-resource-snapshot))
             (write-ready-marker)
             (cadr-cli:run-tui
              (lambda (line)
                (cadr-agent:agent-prompt agent line :source :interactive))
              :set-event-consumer
              (lambda (consumer) (setf event-consumer consumer))
              :abort-function
              (lambda ()
                (setf abort-requested-p t)
                (cadr-agent:agent-abort agent))
              :reset-abort-function
              (lambda () (setf abort-requested-p nil))
              :model "faux-1"
              :provider "faux"
              :thinking :high
              :cwd "~/render-diff"
              :context-window 128000
              :messages nil
              :startup-compact-lines compact
              :startup-expanded-lines expanded
              :alt-p nil
              :show-hardware-cursor-p nil))
        (cadr-agent:agent-shutdown agent)))))

(handler-case
    (progn (main) (uiop:quit 0))
  (condition (condition)
    (format *error-output* "render-diff cadr driver failed: ~A~%" condition)
    (uiop:quit 1)))
