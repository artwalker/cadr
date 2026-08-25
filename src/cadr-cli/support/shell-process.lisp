(in-package #:cadr-cli)

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

(defparameter +powershell-args+
  '("-NoProfile" "-NonInteractive" "-ExecutionPolicy" "Bypass" "-Command"))

(defun get-powershell-config ()
  (unless (uiop:os-windows-p)
    (error "The powershell tool is only available on Windows."))
  (let ((shell (or (executable-on-path "pwsh.exe")
                   (executable-on-path "powershell.exe"))))
    (unless shell
      (error
       "No PowerShell executable found. Install PowerShell or add powershell.exe/pwsh.exe to PATH."))
    (make-shell-config
     :shell shell
     :arguments (copy-list +powershell-args+))))

(defun get-shell-config (&optional custom-shell-path)
  (cond
    (custom-shell-path
     (if (probe-file custom-shell-path)
         (bash-shell-config custom-shell-path)
         (error "Custom shell path not found: ~A" custom-shell-path)))
    ((uiop:os-windows-p)
     (let ((candidates
             (remove nil
                     (loop for name in '("ProgramFiles"
                                         "ProgramFiles(x86)")
                           for root = (uiop:getenv name)
                           collect
                           (and root
                                (format nil "~A\\Git\\bin\\bash.exe"
                                        root))))))
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
