(require :asdf)

(defparameter *goal9-a2-child-arguments*
  (uiop:command-line-arguments))

(when (< (length *goal9-a2-child-arguments*) 3)
  (format *error-output*
          "usage: goal9-a2-faux-mode-child.lisp PROJECT QUICKLISP CLI-ARGS...~%")
  (uiop:quit 2))

(let* ((project
         (uiop:ensure-directory-pathname
          (pathname (first *goal9-a2-child-arguments*))))
       (quicklisp
         (pathname (second *goal9-a2-child-arguments*)))
       (sink (make-broadcast-stream)))
  (unless (probe-file quicklisp)
    (format *error-output*
            "Quicklisp setup not found: ~A~%"
            (namestring quicklisp))
    (uiop:quit 2))
  (let ((*standard-output* sink)
        (*error-output* sink)
        (*trace-output* sink))
    (load quicklisp)
    (dolist (name '("cadr-ai.asd"
                    "cadr-agent.asd"
                    "cadr-tui.asd"
                    "cadr-cli.asd"))
      (asdf:load-asd
       (truename (merge-pathnames name project))))
    (asdf:load-system "cadr-cli")))

(defpackage #:goal9-a2-faux-mode-child
  (:use #:cl))

(in-package #:goal9-a2-faux-mode-child)

(defparameter +json-text+
  "The exit code was 7 and there are 12 steps and 3 files. 中文🙂")

(defun make-agent (responses &key session extension-host)
  (let ((handle
          (cadr-ai:make-faux-provider
           :token-min 1 :token-max 1)))
    (cadr-ai:faux-set-responses handle responses)
    (values
     (cadr-agent:make-agent
      :provider :faux
      :model (cadr-ai:faux-get-model handle)
      :session session
      :extension-host extension-host
      :auto-compact-p nil
      :stream-function
      (lambda (provider model context on-event &rest options)
        (declare (ignore provider))
        (apply
         #'cadr-ai:faux-stream
         handle model context on-event options)))
     handle)))

(defun check-consumed (handle status)
  (let ((remaining
          (cadr-ai:faux-pending-response-count handle)))
    (if (zerop remaining)
        status
        (progn
          (format *error-output*
                  "Faux child left ~D response~:P unconsumed~%"
                  remaining)
          1))))

(defun run-print (command mode)
  (multiple-value-bind (agent handle)
      (make-agent
       (if (eq mode :text)
           (list
            (cadr-ai:faux-assistant-message "intermediate")
            (cadr-ai:faux-assistant-message "final-only"))
           (list
            (cadr-ai:faux-assistant-message +json-text+))))
    (unwind-protect
         (multiple-value-bind (initial messages)
             (cadr-cli::build-cli-print-prompts command nil)
           (check-consumed
            handle
            (cadr-cli::run-print-mode
             agent initial messages :mode mode
             :output *standard-output*
             :error-output *error-output*)))
      (cadr-agent:agent-shutdown agent))))

(defun call-with-temporary-directory (function)
  (uiop:with-temporary-file
      (:pathname marker :keep t)
    (delete-file marker)
    (let ((directory
            (uiop:ensure-directory-pathname
             (pathname
              (format nil "~A-dir/"
                      (namestring marker))))))
      (ensure-directories-exist
       (merge-pathnames "anchor" directory))
      (unwind-protect
           (funcall function directory)
        (when (probe-file directory)
          (uiop:delete-directory-tree
           directory :validate t
           :if-does-not-exist :ignore))))))

(defun run-rpc ()
  (call-with-temporary-directory
   (lambda (directory)
     (let* ((manager
              (cadr-cli::make-cli-extension-manager
               :cwd directory
               :global-directory
               (merge-pathnames "extensions/" directory)
               :no-discovery-p t
               :output *error-output*
               :mode :rpc))
            (session
              (cadr-agent:create-session
               :directory
               (merge-pathnames "sessions/" directory)
               :cwd directory
               :id "goal9-a2-process-faux")))
       (multiple-value-bind (agent handle)
           (make-agent
            (list
             (cadr-ai:faux-assistant-message "rpc-final"))
            :session session
            :extension-host
            (cadr-cli::cli-extension-manager-host manager))
         (unwind-protect
              (check-consumed
               handle
               (cadr-cli::run-rpc-mode
                agent manager
                :input *standard-input*
                :output *standard-output*
                :error-output *error-output*))
           (cadr-agent:agent-shutdown agent)))))))

(defun main (arguments)
  (let* ((command
           (cadr-cli::parse-cli-arguments arguments))
         (mode
           (cadr-cli::resolve-cli-mode
            command nil nil)))
    (case mode
      (:text (run-print command :text))
      (:json (run-print command :json))
      (:rpc (run-rpc))
      (t
       (format *error-output*
               "Unsupported faux child mode: ~S~%" mode)
       2))))

(uiop:quit
 (main
  (cddr cl-user::*goal9-a2-child-arguments*)))
