(in-package #:cadr-cli)

(defparameter +default-thinking-level+ :medium)

(defun docs-directory ()
  (merge-pathnames "docs/" (asdf:system-source-directory "cadr-cli")))

(defun get-provider-login-help ()
  (format nil
          "Use /login to log into a provider via OAuth or API key. See:~%  ~A~%  ~A"
          (namestring (merge-pathnames "providers.md" (docs-directory)))
          (namestring (merge-pathnames "models.md" (docs-directory)))))

(defun format-no-models-available-message ()
  (format nil "No models available. ~A" (get-provider-login-help)))

(defun format-no-model-selected-message ()
  (format nil "No model selected.~%~%~A~%~%Then use /model to select a model."
          (get-provider-login-help)))

(defun format-no-api-key-found-message (provider)
  (format nil "No API key found for ~A.~%~%~A"
          (if (string= provider "unknown") "the selected model" provider)
          (get-provider-login-help)))

(defstruct (event-bus (:constructor %make-event-bus))
  (handlers (make-hash-table :test #'equal) :type hash-table)
  (lock (sb-thread:make-mutex :name "cadr-event-bus"))
  (error-output *error-output*))

(defun make-event-bus (&key (error-output *error-output*))
  (%make-event-bus :error-output error-output))

(defun event-bus-on (bus channel handler)
  (check-type channel string)
  (check-type handler function)
  (sb-thread:with-mutex ((event-bus-lock bus))
    (setf (gethash channel (event-bus-handlers bus))
          (append (gethash channel (event-bus-handlers bus)) (list handler))))
  (let ((active-p t))
    (lambda ()
      (when active-p
        (setf active-p nil)
        (sb-thread:with-mutex ((event-bus-lock bus))
          (setf (gethash channel (event-bus-handlers bus))
                (delete handler (gethash channel (event-bus-handlers bus))
                        :test #'eq :count 1)))))))

(defun event-bus-emit (bus channel data)
  (let ((handlers
          (sb-thread:with-mutex ((event-bus-lock bus))
            (copy-list (gethash channel (event-bus-handlers bus))))))
    (dolist (handler handlers)
      (handler-case (funcall handler data)
        (error (condition)
          (format (event-bus-error-output bus)
                  "Event handler error (~A): ~A~%" channel condition)))))
  nil)

(defun event-bus-clear (bus)
  (sb-thread:with-mutex ((event-bus-lock bus))
    (clrhash (event-bus-handlers bus)))
  nil)

(defparameter *timing-enabled-p*
  (string= (or (uiop:getenv "PI_TIMING") "") "1"))
(defparameter *timing-namespaces* (make-hash-table :test #'eq))
(defparameter *timing-clock*
  (lambda ()
    (round (* 1000 (/ (get-internal-real-time)
                      internal-time-units-per-second)))))

(defun reset-timings (&optional (namespace :main))
  (when *timing-enabled-p*
    (setf (gethash namespace *timing-namespaces*)
          (list :timings nil :last-time (funcall *timing-clock*))))
  nil)

(defun record-timing (label &optional (namespace :main))
  (when *timing-enabled-p*
    (unless (gethash namespace *timing-namespaces*)
      (reset-timings namespace))
    (let* ((state (gethash namespace *timing-namespaces*))
           (now (funcall *timing-clock*)))
      (setf (getf state :timings)
            (append (getf state :timings)
                    (list (cons label (- now (getf state :last-time)))))
            (getf state :last-time) now
            (gethash namespace *timing-namespaces*) state)))
  nil)

(defun print-timings (&optional (output *error-output*))
  (when *timing-enabled-p*
    (maphash
     (lambda (namespace state)
       (let ((timings (remove-if (lambda (entry) (minusp (cdr entry)))
                                 (getf state :timings))))
         (when timings
           (let ((title (format nil "Startup Timings: ~(~A~)" namespace)))
             (format output "~%--- ~A ---~%" title)
             (dolist (entry timings)
               (format output "  ~A: ~Dms~%" (car entry) (cdr entry)))
             (format output "  TOTAL: ~Dms~%~A~%~%"
                     (reduce #'+ timings :key #'cdr :initial-value 0)
                     (make-string (+ (length title) 8)
                                  :initial-element #\-))))))
     *timing-namespaces*))
  nil)

(defparameter +fs-watch-retry-delay-milliseconds+ 5000)

(defstruct (file-watcher (:constructor %make-file-watcher))
  path listener on-error signature thread
  (closed-p nil :type boolean)
  (poll-interval 0.1d0 :type real)
  (lock (sb-thread:make-mutex :name "cadr-file-watcher"))
  (waitqueue (sb-thread:make-waitqueue :name "cadr-file-watcher")))

(defun watched-path-signature (path)
  (let ((file (probe-file path)))
    (and file (list (file-write-date file)
                    (ignore-errors
                      (with-open-file (stream file :direction :input
                                             :element-type '(unsigned-byte 8))
                        (file-length stream)))))))

(defun close-watcher (watcher)
  (when watcher
    (sb-thread:with-mutex ((file-watcher-lock watcher))
      (setf (file-watcher-closed-p watcher) t)
      (sb-thread:condition-broadcast (file-watcher-waitqueue watcher)))
    (let ((thread (file-watcher-thread watcher)))
      (when (and thread
                 (not (eq thread sb-thread:*current-thread*)))
        (stop-thread-for-cleanup thread))))
  nil)

(defun poll-file-watcher-once (watcher)
  (handler-case
      (let ((next (watched-path-signature (file-watcher-path watcher))))
        (unless (equal next (file-watcher-signature watcher))
          (setf (file-watcher-signature watcher) next)
          (funcall (file-watcher-listener watcher)
                   :change (file-watcher-path watcher))
          t))
    (error ()
      (funcall (file-watcher-on-error watcher))
      nil)))

(defun watch-with-error-handler (path listener on-error &key (poll-interval 0.1d0))
  (handler-case
      (let* ((watcher
               (%make-file-watcher
                :path path :listener listener :on-error on-error
                :signature (watched-path-signature path)
                :poll-interval poll-interval))
             (thread
               (sb-thread:make-thread
                (lambda ()
                  (loop
                    (sb-thread:with-mutex ((file-watcher-lock watcher))
                      (when (file-watcher-closed-p watcher)
                        (return))
                      (sb-thread:condition-wait
                       (file-watcher-waitqueue watcher)
                       (file-watcher-lock watcher)
                       :timeout (file-watcher-poll-interval watcher)))
                    (when (file-watcher-closed-p watcher)
                      (return))
                    (poll-file-watcher-once watcher)))
                :name "cadr-file-watcher")))
        (setf (file-watcher-thread watcher) thread)
        watcher)
    (error ()
      (funcall on-error)
      nil)))

(defun strip-json-comments (input)
  (with-output-to-string (output)
    (let ((index 0)
          (in-string-p nil)
          (escaped-p nil))
      (loop while (< index (length input))
            for character = (char input index)
            do
            (cond
              (in-string-p
               (write-char character output)
               (cond
                 (escaped-p (setf escaped-p nil))
                 ((char= character #\\) (setf escaped-p t))
                 ((char= character #\") (setf in-string-p nil)))
               (incf index))
              ((char= character #\")
               (setf in-string-p t)
               (write-char character output)
               (incf index))
              ((and (char= character #\/)
                    (< (1+ index) (length input))
                    (char= #\/ (char input (1+ index))))
               (setf index (or (position #\Newline input :start (+ index 2))
                               (length input))))
              ((char= character #\,)
               (let ((next (position-if-not
                            (lambda (item)
                              (find item '(#\Space #\Tab #\Newline #\Return)))
                            input :start (1+ index))))
                 (if (and next (find (char input next) "}]") )
                     (incf index)
                     (progn (write-char character output) (incf index)))))
              (t (write-char character output) (incf index)))))))

(defparameter +unicode-path-spaces+
  (mapcar #'code-char
          '(#x00a0 #x2000 #x2001 #x2002 #x2003 #x2004 #x2005 #x2006
            #x2007 #x2008 #x2009 #x200a #x202f #x205f #x3000)))

(defun decode-file-url-path (text)
  (let ((octets
          (make-array 0 :element-type '(unsigned-byte 8)
                        :adjustable t :fill-pointer 0)))
    (loop with index = 0
          while (< index (length text))
          do (if (char= #\% (char text index))
                 (progn
                   (when (> (+ index 3) (length text))
                     (error "Invalid percent escape in file URL"))
                   (let ((high (digit-char-p (char text (1+ index)) 16))
                         (low (digit-char-p (char text (+ index 2)) 16)))
                     (unless (and high low)
                       (error "Invalid percent escape in file URL"))
                     (vector-push-extend (+ (ash high 4) low) octets))
                   (incf index 3))
                 (progn
                   (loop for octet across
                         (cadr-ai::utf8-octets (string (char text index)))
                         do (vector-push-extend octet octets))
                   (incf index))))
    (cadr-ai::utf8-string octets)))

(defun normalize-path-input
    (input &key trim-p (expand-tilde-p t) home-directory
                strip-at-prefix-p normalize-unicode-spaces-p)
  (let ((value (if trim-p
                   (string-trim '(#\Space #\Tab #\Newline #\Return) input)
                   input)))
    (when normalize-unicode-spaces-p
      (setf value
            (map 'string
                 (lambda (character)
                   (if (member character +unicode-path-spaces+)
                       #\Space character))
                 value)))
    (when (and strip-at-prefix-p (uiop:string-prefix-p "@" value))
      (setf value (subseq value 1)))
    (when expand-tilde-p
      (let ((home (or home-directory (namestring (user-homedir-pathname)))))
        (cond
          ((string= value "~") (setf value home))
          ((or (uiop:string-prefix-p "~/" value)
               (uiop:string-prefix-p "~\\" value))
           (setf value (namestring
                        (merge-pathnames (subseq value 2)
                                         (uiop:ensure-directory-pathname home))))))))
    (when (uiop:string-prefix-p "file://" value)
      (setf value (decode-file-url-path (subseq value 7))))
    value))

(defun resolve-path-input
    (input &optional (base-directory (uiop:getcwd)) &rest options)
  (let* ((normalized (apply #'normalize-path-input input options))
         (pathname (pathname normalized)))
    (namestring
     (if (uiop:absolute-pathname-p pathname)
         pathname
         (merge-pathnames pathname
                          (uiop:ensure-directory-pathname base-directory))))))

(defun mark-path-ignored-by-cloud-sync (path &key runner)
  (let ((commands
          (cond
            ((uiop:os-macosx-p)
             (list (list "xattr" "-w" "com.dropbox.ignored" "1" path)
                   (list "xattr" "-w" "com.apple.fileprovider.ignore#P" "1" path)))
            ((uiop:os-unix-p)
             (list (list "setfattr" "-n" "user.com.dropbox.ignored"
                         "-v" "1" path))))))
    (dolist (command commands)
      (ignore-errors
        (if runner
            (funcall runner command)
            (uiop:run-program command :output nil :error-output nil
                                      :ignore-error-status t)))))
  nil)

(defstruct shell-config
  shell
  (arguments nil :type list)
  command-transport)

(defun bash-shell-config (shell)
  (let ((normalized (string-downcase (substitute #\\ #\/ shell))))
    (if (cl-ppcre:scan "^[a-z]:\\\\windows\\\\(?:system32|sysnative)\\\\bash\\.exe$"
                       normalized)
        (make-shell-config :shell shell :arguments '("-s")
                           :command-transport :stdin)
        (make-shell-config :shell shell :arguments '("-c")))))

(defun executable-on-path (name)
  (let ((separator (if (uiop:os-windows-p) #\; #\:)))
    (loop for directory in (uiop:split-string (or (uiop:getenv "PATH") "")
                                               :separator (list separator))
          unless (string= directory "")
            do (let* ((root (uiop:ensure-directory-pathname directory))
                      (candidate (merge-pathnames name root))
                      (windows-candidate
                        (and (uiop:os-windows-p)
                             (merge-pathnames (concatenate 'string name ".exe")
                                              root))))
                 (cond
                   ((probe-file candidate) (return (namestring candidate)))
                   ((and windows-candidate (probe-file windows-candidate))
                    (return (namestring windows-candidate))))))))

(defun get-shell-config (&optional custom-shell-path)
  (cond
    (custom-shell-path
     (if (probe-file custom-shell-path)
         (bash-shell-config custom-shell-path)
         (error "Custom shell path not found: ~A" custom-shell-path)))
    ((uiop:os-windows-p)
     (let ((candidates
             (remove nil
                     (list
                      (and (uiop:getenv "ProgramFiles")
                           (format nil "~A\\Git\\bin\\bash.exe"
                                   (uiop:getenv "ProgramFiles")))
                      (and (uiop:getenv "ProgramFiles(x86)")
                           (format nil "~A\\Git\\bin\\bash.exe"
                                   (uiop:getenv "ProgramFiles(x86)")))))))
       (let ((shell (or (find-if #'probe-file candidates)
                        (executable-on-path "bash.exe"))))
         (if shell
             (bash-shell-config shell)
             (error "No bash shell found. Install Git for Windows, add bash to PATH, or set shellPath in settings.json")))))
    ((probe-file "/bin/bash") (bash-shell-config "/bin/bash"))
    ((executable-on-path "bash")
     (bash-shell-config (executable-on-path "bash")))
    (t (make-shell-config :shell "sh" :arguments '("-c")))))

(defun get-shell-env (&key (bin-directory (cadr-bin-directory)))
  (let* ((environment
           (loop for entry in (sb-ext:posix-environ)
                 for separator = (position #\= entry)
                 when separator
                   collect (cons (subseq entry 0 separator)
                                 (subseq entry (1+ separator)))))
         (path-pair
           (or (find-if (lambda (pair) (string-equal "PATH" (car pair)))
                        environment)
               (let ((pair (cons "PATH" "")))
                 (push pair environment)
                 pair)))
         (separator (if (uiop:os-windows-p) #\; #\:))
         (bin (string-right-trim
               '(#\/ #\\)
               (namestring (uiop:ensure-directory-pathname bin-directory))))
         (entries (uiop:split-string (cdr path-pair)
                                     :separator (list separator))))
    (unless (member bin entries :test #'string=)
      (setf (cdr path-pair)
            (if (zerop (length (cdr path-pair)))
                bin
                (format nil "~A~C~A" bin separator (cdr path-pair)))))
    environment))

(defun sanitize-binary-output (text)
  (remove-if
   (lambda (character)
     (let ((code (char-code character)))
       (or (and (<= code #x1f) (not (member code '(#x09 #x0a #x0d))))
           (<= #xfff9 code #xfffb)
           (<= #xd800 code #xdfff))))
   text))

(defparameter *tracked-detached-child-pids* (make-hash-table))
(defparameter *tracked-detached-child-lock*
  (sb-thread:make-mutex :name "cadr-detached-children"))

(defun track-detached-child-pid (pid)
  (sb-thread:with-mutex (*tracked-detached-child-lock*)
    (setf (gethash pid *tracked-detached-child-pids*) t))
  pid)

(defun untrack-detached-child-pid (pid)
  (sb-thread:with-mutex (*tracked-detached-child-lock*)
    (remhash pid *tracked-detached-child-pids*))
  pid)

(defun kill-process-tree (pid &key runner)
  (labels ((run (command)
             (ignore-errors
               (if runner
                   (funcall runner command)
                   (uiop:run-program command :output nil :error-output nil
                                             :ignore-error-status t)))))
    (if (uiop:os-windows-p)
        (run (list "taskkill" "/F" "/T" "/PID" (princ-to-string pid)))
        (multiple-value-bind (stdout stderr status)
            (run (list "/bin/kill" "-KILL" "--" (format nil "-~D" pid)))
          (declare (ignore stdout stderr))
          (unless (and (integerp status) (zerop status))
            (run (list "/bin/kill" "-KILL" "--" (princ-to-string pid)))))))
  nil)

(defun kill-tracked-detached-children (&key runner)
  (let ((pids
          (sb-thread:with-mutex (*tracked-detached-child-lock*)
            (prog1
                (loop for pid being the hash-keys of *tracked-detached-child-pids*
                      collect pid)
              (clrhash *tracked-detached-child-pids*)))))
    (dolist (pid pids)
      (kill-process-tree pid :runner runner)))
  nil)
