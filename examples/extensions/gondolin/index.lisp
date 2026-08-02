(load (merge-pathnames "../support.lisp" *load-truename*))

(defconstant +gondolin-version+ "0.12.0")
(defconstant +gondolin-workspace+ "/workspace")

(defstruct gondolin-session
  process
  id
  output-thread
  error-thread)

(defvar *gondolin-session* nil)
(defvar *gondolin-lock*
  (sb-thread:make-mutex :name "cadr example gondolin session"))

(defclass gondolin-execution-context (cadr-agent:execution-tool-context)
  ((host-cwd :initarg :host-cwd :reader gondolin-context-host-cwd)))

(defun gondolin-program ()
  (or (uiop:getenv "CADR_GONDOLIN")
      (example-program-path "gondolin")))

(defun gondolin-shell-quote (value)
  (format nil "'~A'"
          (with-output-to-string (output)
            (loop for character across (princ-to-string value)
                  if (char= character #\')
                    do (write-string "'\\''" output)
                  else
                    do (write-char character output)))))

(defun gondolin-command-string (arguments)
  (format nil "~{~A~^ ~}" (mapcar #'gondolin-shell-quote arguments)))

(defun gondolin-normalize-guest-path (path)
  (let ((parts nil))
    (dolist (part (uiop:split-string path :separator '(#\/)))
      (cond ((or (zerop (length part)) (string= part ".")))
            ((string= part "..") (when parts (pop parts)))
            (t (push part parts))))
    (format nil "/~{~A~^/~}" (nreverse parts))))

(defun gondolin-guest-path (host-cwd value)
  (let* ((text (string-trim '(#\Space #\Tab) (princ-to-string value)))
         (text (if (uiop:string-prefix-p "@" text) (subseq text 1) text))
         (root (string-right-trim "/" (namestring
                                        (uiop:ensure-directory-pathname
                                         host-cwd)))))
    (cond
      ((zerop (length text)) +gondolin-workspace+)
      ((uiop:string-prefix-p +gondolin-workspace+ text)
       (gondolin-normalize-guest-path text))
      ((uiop:absolute-pathname-p (pathname text))
       (if (or (string= text root)
               (uiop:string-prefix-p (concatenate 'string root "/") text))
           (gondolin-normalize-guest-path
            (concatenate 'string +gondolin-workspace+ (subseq text (length root))))
           (gondolin-normalize-guest-path text)))
      (t
       (gondolin-normalize-guest-path
        (format nil "~A/~A" +gondolin-workspace+ text))))))

(defun gondolin-base64-value (character)
  (position character
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"))

(defun gondolin-base64-decode (text)
  (let* ((clean (remove-if (lambda (character)
                             (find character '(#\Space #\Tab #\Newline #\Return)))
                           text))
         (output (make-array (* 3 (ceiling (length clean) 4))
                             :element-type '(unsigned-byte 8)
                             :fill-pointer 0)))
    (loop for start from 0 below (length clean) by 4
          for c0 = (char clean start)
          for c1 = (char clean (1+ start))
          for c2 = (and (< (+ start 2) (length clean)) (char clean (+ start 2)))
          for c3 = (and (< (+ start 3) (length clean)) (char clean (+ start 3)))
          for v0 = (gondolin-base64-value c0)
          for v1 = (gondolin-base64-value c1)
          for v2 = (and c2 (not (char= c2 #\=)) (gondolin-base64-value c2))
          for v3 = (and c3 (not (char= c3 #\=)) (gondolin-base64-value c3))
          do
          (unless (and v0 v1) (error "Invalid Gondolin base64 response"))
          (vector-push (logior (ash v0 2) (ldb (byte 2 4) v1)) output)
          (when v2
            (vector-push (logior (ash (ldb (byte 4 0) v1) 4)
                                 (ldb (byte 4 2) v2)) output))
          (when v3
            (vector-push (logior (ash (ldb (byte 2 0) v2) 6) v3) output)))
    output))

(defun gondolin-drain-stream (stream)
  (lambda ()
    (ignore-errors
      (loop while (read-line stream nil nil)))))

(defun gondolin-session-id-for-pid (pid)
  (let ((result (example-exec (gondolin-program) '("list" "--all"))))
    (when (zerop (example-exec-code result))
      (dolist (line (uiop:split-string (example-exec-output result)
                                       :separator '(#\Newline)))
        (let ((columns
                (remove "" (uiop:split-string line :separator '(#\Space #\Tab))
                        :test #'string=)))
          (when (and (>= (length columns) 4)
                     (string= (second columns) (princ-to-string pid))
                     (string-equal (fourth columns) "yes"))
            (return-from gondolin-session-id-for-pid (first columns))))))))

(defun gondolin-wait-for-session-id (process)
  (loop repeat 300
        do
        (unless (uiop:process-alive-p process)
          (error "Gondolin ~A exited before its session became ready"
                 +gondolin-version+))
        (let ((id
                (gondolin-session-id-for-pid
                 (uiop:process-info-pid process))))
          (when id
            (return id)))
        (sleep 0.1)
        finally
          (error "Gondolin ~A did not publish a session within 30 seconds"
                 +gondolin-version+)))

(defun gondolin-start (cwd)
  (sb-thread:with-mutex (*gondolin-lock*)
    (when (and *gondolin-session*
               (uiop:process-alive-p
                (gondolin-session-process *gondolin-session*)))
      (return-from gondolin-start *gondolin-session*))
    (let* ((process
             (uiop:launch-program
              (list
               (gondolin-program) "bash"
               "--mount-hostfs"
               (format nil "~A:~A" (namestring cwd) +gondolin-workspace+)
               "--cwd" +gondolin-workspace+
               "--" "/bin/sh" "-lc"
               "while :; do sleep 3600; done")
              :input :stream :output :stream :error-output :stream))
           (output-thread
             (sb-thread:make-thread
              (gondolin-drain-stream (uiop:process-info-output process))
              :name "cadr gondolin stdout drain"))
           (error-thread
             (sb-thread:make-thread
              (gondolin-drain-stream (uiop:process-info-error-output process))
              :name "cadr gondolin stderr drain")))
      (handler-case
          (setf *gondolin-session*
                (make-gondolin-session
                 :process process
                 :id (gondolin-wait-for-session-id process)
                 :output-thread output-thread
                 :error-thread error-thread))
        (condition (condition)
          (when (uiop:process-alive-p process)
            (uiop:terminate-process process))
          (error condition))))))

(defun gondolin-stop ()
  (sb-thread:with-mutex (*gondolin-lock*)
    (let ((session *gondolin-session*))
      (setf *gondolin-session* nil)
      (when session
        (let ((process (gondolin-session-process session)))
          (when (uiop:process-alive-p process)
            (uiop:terminate-process process))
          (ignore-errors (uiop:wait-process process)))
        (dolist (thread
                 (list (gondolin-session-output-thread session)
                       (gondolin-session-error-thread session)))
          (when (and thread (sb-thread:thread-alive-p thread))
            (ignore-errors (sb-thread:join-thread thread)))))))
  nil)

(defun gondolin-exec (cwd command signal &key timeout on-stdout on-stderr)
  (let* ((session (gondolin-start cwd))
         (environment (cadr-agent:make-node-execution-env :cwd cwd))
         (arguments
           (list (gondolin-program) "attach" (gondolin-session-id session)
                 "--cwd" +gondolin-workspace+
                 "--" "/bin/bash" "-lc" command)))
    (cadr-agent:execution-env-exec
     environment (gondolin-command-string arguments)
     :cwd (namestring cwd) :timeout timeout :signal signal
     :on-stdout on-stdout :on-stderr on-stderr)))

(defmethod cadr-agent:execution-tool-resolve-path
    ((context gondolin-execution-context) path &optional base-directory)
  (values
   (gondolin-guest-path
    (gondolin-context-host-cwd context)
    (if (and base-directory
             (not (uiop:absolute-pathname-p (pathname (princ-to-string path)))))
        (format nil "~A/~A" base-directory path)
        path))
   nil))

(defmethod cadr-agent:execution-tool-read-binary
    ((context gondolin-execution-context) path)
  (multiple-value-bind (result operation-error)
      (gondolin-exec
       (gondolin-context-host-cwd context)
       (format nil "base64 ~A | tr -d '\\n'" (gondolin-shell-quote path))
       nil)
    (if operation-error
        (values nil operation-error)
        (if (zerop (cadr-agent:execution-result-exit-code result))
            (values
             (gondolin-base64-decode
              (cadr-agent:execution-result-stdout result)) nil)
            (values nil
                    (cadr-agent:make-harness-operation-error
                     :code :unknown
                     :message (cadr-agent:execution-result-stderr result)
                     :path path))))))

(defmethod cadr-agent:execution-tool-read-text
    ((context gondolin-execution-context) path)
  (multiple-value-bind (bytes operation-error)
      (cadr-agent:execution-tool-read-binary context path)
    (values (and bytes (cadr-ai::utf8-string bytes)) operation-error)))

(defmethod cadr-agent:execution-tool-write
    ((context gondolin-execution-context) path content)
  (let ((encoded
          (cadr-ai::standard-base64-encode
           (if (stringp content) (cadr-ai::utf8-octets content) content))))
    (multiple-value-bind (result operation-error)
        (gondolin-exec
         (gondolin-context-host-cwd context)
         (format nil
                 "mkdir -p -- $(dirname -- ~A) && printf %s ~A | base64 -d > ~A"
                 (gondolin-shell-quote path)
                 (gondolin-shell-quote encoded)
                 (gondolin-shell-quote path))
         nil)
      (if operation-error
          (values nil operation-error)
          (if (zerop (cadr-agent:execution-result-exit-code result))
              (values nil nil)
              (values nil
                      (cadr-agent:make-harness-operation-error
                       :code :unknown
                       :message (cadr-agent:execution-result-stderr result)
                       :path path)))))))

(defmethod cadr-agent:execution-tool-exec
    ((context gondolin-execution-context) command
     &key cwd timeout signal on-stdout on-stderr)
  (gondolin-exec
   (gondolin-context-host-cwd context)
   (if cwd
       (format nil "cd -- ~A && ~A"
               (gondolin-shell-quote
                (gondolin-guest-path
                 (gondolin-context-host-cwd context) cwd))
               command)
       command)
   signal
   :timeout timeout :on-stdout on-stdout :on-stderr on-stderr))

(defun gondolin-bash-operation (command cwd timeout signal on-update)
  (funcall on-update "Running in Gondolin micro-VM…")
  (multiple-value-bind (result operation-error)
      (gondolin-exec cwd command signal :timeout timeout)
    (when operation-error
      (return-from gondolin-bash-operation
        (list :output
              (cadr-agent:harness-operation-error-message operation-error)
              :exit-code
              (if (eq :aborted
                      (cadr-agent:harness-operation-error-code operation-error))
                  130 1)
              :cancelled-p
              (eq :aborted
                  (cadr-agent:harness-operation-error-code operation-error)))))
    (list
     :output
     (concatenate 'string
                  (cadr-agent:execution-result-stdout result)
                  (cadr-agent:execution-result-stderr result))
     :exit-code (cadr-agent:execution-result-exit-code result))))

(let ((tool-context
        (make-instance 'gondolin-execution-context
                       :host-cwd (uiop:getcwd))))
  (dolist (tool
           (list (cadr-cli:make-read-tool +gondolin-workspace+
                                          :context tool-context)
                 (cadr-cli:make-write-tool +gondolin-workspace+
                                           :context tool-context)
                 (cadr-cli:make-edit-tool +gondolin-workspace+
                                          :context tool-context)))
    (let ((copy tool))
      (cadr-agent:define-rich-tool
       (cadr-ai:tool-name copy)
       :label (string-capitalize (cadr-ai:tool-name copy))
       :description (cadr-ai:tool-description copy)
       :parameters (cadr-ai:tool-parameters copy)
       :execution-mode (cadr-ai:tool-execution-mode copy)
       :handler
       (lambda (call-id arguments signal on-update context)
         (declare (ignore signal on-update context))
         (example-execute-tool copy call-id arguments))))))

(defun gondolin-path-tool
    (name label description local-tool command-builder)
  (cadr-agent:define-rich-tool
   name :label label :description description
   :parameters (cadr-ai:tool-parameters local-tool)
   :handler
   (lambda (call-id arguments signal on-update context)
     (declare (ignore call-id))
     (funcall on-update (format nil "Running ~A in Gondolin…" name))
     (multiple-value-bind (result operation-error)
         (gondolin-exec
          (cadr-agent:extension-context-cwd context)
          (funcall command-builder arguments context)
          signal)
       (if operation-error
           (example-result
            (cadr-agent:harness-operation-error-message operation-error))
           (example-result
            (let ((output (cadr-agent:execution-result-stdout result)))
              (if (zerop (length output))
                  (case (intern (string-upcase name) :keyword)
                    (:grep "No matches found")
                    (t ""))
                  (string-right-trim '(#\Newline #\Return) output)))
            :details
            (list :exit-code (cadr-agent:execution-result-exit-code result))))))))

(gondolin-path-tool
 "ls" "Gondolin Ls" "List files in the Gondolin guest"
 (cadr-cli:make-ls-tool (uiop:getcwd))
 (lambda (arguments context)
   (let ((path
           (gondolin-guest-path
            (cadr-agent:extension-context-cwd context)
            (or (example-argument arguments "path") ".")))
         (limit (or (example-argument arguments "limit") 500)))
     (format nil "find ~A -mindepth 1 -maxdepth 1 -printf '%f\\n' | sort | head -n ~D"
             (gondolin-shell-quote path) limit))))

(gondolin-path-tool
 "find" "Gondolin Find" "Find files in the Gondolin guest"
 (cadr-cli:make-find-tool (uiop:getcwd))
 (lambda (arguments context)
   (let ((path
           (gondolin-guest-path
            (cadr-agent:extension-context-cwd context)
            (or (example-argument arguments "path") ".")))
         (pattern (or (example-argument arguments "pattern") "*"))
         (limit (or (example-argument arguments "limit") 1000)))
     (format nil
             "find ~A -type f -not -path '*/.git/*' -not -path '*/node_modules/*' -name ~A | sed 's#^/workspace/##' | head -n ~D"
             (gondolin-shell-quote path) (gondolin-shell-quote pattern) limit))))

(gondolin-path-tool
 "grep" "Gondolin Grep" "Search text in the Gondolin guest"
 (cadr-cli:make-grep-tool (uiop:getcwd))
 (lambda (arguments context)
   (let ((path
           (gondolin-guest-path
            (cadr-agent:extension-context-cwd context)
            (or (example-argument arguments "path") ".")))
         (pattern (or (example-argument arguments "pattern") ""))
         (limit (or (example-argument arguments "limit") 100)))
     (format nil
             "grep -RIn~:[~;F~]~:[~;i~] --exclude-dir=.git --exclude-dir=node_modules -- ~A ~A | sed 's#^/workspace/##' | head -n ~D"
             (example-boolean (example-argument arguments "literal"))
             (example-boolean (example-argument arguments "ignoreCase"))
             (gondolin-shell-quote pattern) (gondolin-shell-quote path) limit))))

(cadr-agent:define-rich-tool
 "bash"
 :label "Gondolin Bash"
 :description "Execute bash in a persistent opt-in Gondolin micro-VM"
 :parameters
 (example-object-schema
  "command" "string" "Guest command"
  "timeout" "number" "Timeout in seconds")
 :execution-mode :sequential
 :handler
 (lambda (call-id arguments signal on-update context)
   (declare (ignore call-id))
   (let ((result
           (gondolin-bash-operation
            (example-argument arguments "command" "")
            (cadr-agent:extension-context-cwd context)
            (example-argument arguments "timeout")
            signal on-update)))
     (values (getf result :output)
             (list :exit-code (getf result :exit-code)
                   :cancelled-p (getf result :cancelled-p))
             nil))))

(cadr-agent:define-event-hook
 :session-start
 :handler
 (lambda (event context)
   (declare (ignore event))
   (let ((session (gondolin-start (cadr-agent:extension-context-cwd context))))
     (cadr-agent:extension-context-set-status
      context "gondolin"
      (format nil "Gondolin: ~A (~A)"
              (gondolin-session-id session) +gondolin-workspace+)))))

(cadr-agent:define-event-hook
 :session-shutdown
 :handler
 (lambda (event context)
   (declare (ignore event))
   (gondolin-stop)
   (cadr-agent:extension-context-set-status context "gondolin" nil)))

(cadr-agent:define-event-hook
 :user-bash
 :handler
 (lambda (event context)
   (let ((cwd (cadr-agent:extension-context-cwd context))
         (signal
           (or (cadr-agent:extension-context-signal context)
               (cadr-agent:make-extension-cancellation-signal))))
     (list
      :operations
      (lambda (command ignored-cwd timeout)
        (declare (ignore ignored-cwd))
        (let ((result
                (gondolin-bash-operation
                 command cwd timeout signal
                 (lambda (update) (declare (ignore update))))))
          (values result
                  (list :exit-code (getf result :exit-code)))))))))

(cadr-agent:define-event-hook
 :before-agent-start
 :handler
 (lambda (event context)
   (declare (ignore context))
   (let* ((prompt (or (example-event-value event :system-prompt) ""))
          (line (format nil "Current working directory: ~A" (uiop:getcwd)))
          (replacement
            (format nil
                    "Current working directory: ~A (Gondolin VM; host workspace mounted from ~A)"
                    +gondolin-workspace+ (uiop:getcwd))))
     (list
      :system-prompt
      (if (search line prompt)
          (concatenate 'string
                       (subseq prompt 0 (search line prompt))
                       replacement
                       (subseq prompt (+ (search line prompt) (length line))))
          (format nil "~A~%~%~A" prompt replacement))))))

(cadr-agent:define-command
 "gondolin"
 :description "Show the active Gondolin VM status"
 :handler
 (lambda (arguments context)
   (declare (ignore arguments))
   (let ((session (gondolin-start (cadr-agent:extension-context-cwd context))))
     (cadr-agent:extension-context-notify
      context
      (format nil "Gondolin ~A session ~A; host ~A mounted at ~A"
              +gondolin-version+ (gondolin-session-id session)
              (cadr-agent:extension-context-cwd context)
              +gondolin-workspace+)))))
