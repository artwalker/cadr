(load (merge-pathnames "../support.lisp" *load-truename*))

(defvar *sandbox-network-enabled-p* nil)
(defvar *sandbox-enabled-p* nil)

(defun sandbox-platform ()
  (cond
    ((uiop:os-macosx-p) :macos)
    ((uiop:os-unix-p) :linux)
    (t :unsupported)))

(defun sandbox-bwrap-arguments (cwd command)
  (append
   '("--die-with-parent" "--new-session" "--unshare-all")
   (when *sandbox-network-enabled-p* '("--share-net"))
   (list "--ro-bind" "/" "/"
         "--dev" "/dev" "--proc" "/proc"
         "--tmpfs" "/tmp"
         "--bind" (namestring cwd) (namestring cwd)
         "--chdir" (namestring cwd)
         "--" "/bin/bash" "-lc" command)))

(defun sandbox-macos-profile (cwd)
  (format
   nil
   "(version 1)~%(deny default)~%(allow process*)~%(allow file-read*)~%(allow file-write* (subpath ~S))~A"
   (namestring cwd)
   (if *sandbox-network-enabled-p*
       (format nil "~%(allow network*)")
       "")))

(defun sandbox-program-and-arguments (cwd command)
  (ecase (sandbox-platform)
    (:linux
     (values "bwrap" (sandbox-bwrap-arguments cwd command) :bubblewrap))
    (:macos
     (values
      "sandbox-exec"
      (list "-p" (sandbox-macos-profile cwd) "/bin/bash" "-lc" command)
      :sandbox-exec))
    (:unsupported
     (error "Sandbox extension supports Linux bubblewrap and macOS sandbox-exec only"))))

(defun sandbox-execute (command cwd timeout signal on-update)
  (when (cadr-agent:extension-cancellation-aborted-p signal)
    (return-from sandbox-execute
      (list :output "Sandbox command cancelled"
            :exit-code 130 :cancelled-p t)))
  (multiple-value-bind (program arguments backend)
      (sandbox-program-and-arguments cwd command)
    (funcall on-update
             (format nil "Starting ~A sandbox…"
                     (if (eq backend :bubblewrap)
                         "bubblewrap"
                         "sandbox-exec")))
    (let ((result
            (example-call-program
             program arguments
             :timeout-ms (* 1000 (or timeout 120)))))
      (list
       :output
       (concatenate 'string
                    (example-exec-output result)
                    (example-exec-error result))
       :exit-code (example-exec-code result)
       :sandbox backend
       :network-p *sandbox-network-enabled-p*))))

(cadr-agent:define-flag
 "no-sandbox" :description "Disable OS-level sandboxing for bash commands"
 :type :boolean :default nil)

(cadr-agent:define-rich-tool
 "bash"
 :label "Bash (OS sandbox)"
 :description "Execute bash in an opt-in bubblewrap or sandbox-exec policy"
 :parameters
 (example-object-schema
  "command" "string" "Shell command"
  "timeout" "number" "Timeout in seconds")
 :execution-mode :sequential
 :handler
 (lambda (call-id arguments signal on-update context)
   (if *sandbox-enabled-p*
       (let ((result
               (sandbox-execute
                (example-argument arguments "command" "")
                (cadr-agent:extension-context-cwd context)
                (example-argument arguments "timeout" 120)
                signal on-update)))
         (values
          (getf result :output)
          (list :exit-code (getf result :exit-code)
                :sandbox (getf result :sandbox)
                :network-p (getf result :network-p))
          nil))
       (example-execute-tool
        (cadr-cli:make-bash-tool
         (cadr-agent:extension-context-cwd context))
        call-id arguments))))

(cadr-agent:define-event-hook
 :user-bash
 :handler
 (lambda (event context)
   (when *sandbox-enabled-p*
     (let ((command (or (example-event-value event :command) ""))
           (cwd
             (or (example-event-value event :cwd)
                 (namestring (cadr-agent:extension-context-cwd context))))
           (signal
             (or (cadr-agent:extension-context-signal context)
                 (cadr-agent:make-extension-cancellation-signal))))
       (list
        :operations
        (lambda (ignored-command ignored-cwd timeout)
          (declare (ignore ignored-command ignored-cwd))
          (let ((result
                  (sandbox-execute
                   command (pathname cwd) timeout signal
                   (lambda (update) (declare (ignore update))))))
            (values result
                    (list :exit-code (getf result :exit-code)
                          :sandbox (getf result :sandbox))))))))))

(cadr-agent:define-command
 "sandbox"
 :description "Show sandbox configuration"
 :handler
 (lambda (arguments context)
   (declare (ignore arguments))
   (cadr-agent:extension-context-notify
    context
    (if *sandbox-enabled-p*
        (format nil
                "Sandbox Configuration:~%Backend: ~A~%Network: ~:[isolated~;shared~]~%Writable: ~A and /tmp"
                (ecase (sandbox-platform)
                  (:linux "bubblewrap") (:macos "sandbox-exec"))
                *sandbox-network-enabled-p*
                (namestring (cadr-agent:extension-context-cwd context)))
        "Sandbox is disabled"))))

(cadr-agent:define-event-hook
 :session-start
 :handler
 (lambda (event context)
   (declare (ignore event))
   (setf *sandbox-enabled-p* nil)
   (cond
     ((eq t (cadr-agent:extension-api-get-flag *example-api* "no-sandbox"))
      (cadr-agent:extension-context-notify
       context "Sandbox disabled via --no-sandbox" :level :warning))
     ((eq (sandbox-platform) :unsupported)
      (cadr-agent:extension-context-notify
       context "Sandbox not supported on this platform" :level :warning))
     (t
      (let ((program
              (if (eq (sandbox-platform) :linux)
                  "bwrap" "sandbox-exec")))
        (handler-case
            (progn
              (example-program-path program)
              (setf *sandbox-enabled-p* t)
              (cadr-agent:extension-context-set-status
               context "sandbox" "Sandbox")
              (cadr-agent:extension-context-notify
               context "Sandbox initialized"))
          (error (condition)
            (cadr-agent:extension-context-notify
             context (princ-to-string condition) :level :error))))))))

(cadr-agent:define-event-hook
 :session-shutdown
 :handler
 (lambda (event context)
   (declare (ignore event))
   (setf *sandbox-network-enabled-p* nil *sandbox-enabled-p* nil)
   (cadr-agent:extension-context-set-status context "sandbox" nil)))
