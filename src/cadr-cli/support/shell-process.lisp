(in-package #:cadr-cli)

(defstruct shell-config
  shell
  (arguments nil :type list)
  command-transport)

(defun non-empty-environment-value (environment-function name)
  (let ((value (funcall environment-function name)))
    (and value (plusp (length value)) value)))

(defun windows-path-join (&rest parts)
  (reduce (lambda (left right)
            (format nil "~A\\~A"
                    (string-right-trim '(#\\ #\/) left)
                    (string-left-trim '(#\\ #\/) right)))
          parts))

(defun windows-drive-prefix-p (part)
  (and (= (length part) 2)
       (alpha-char-p (char part 0))
       (char= (char part 1) #\:)))

(defun normalize-windows-path (path)
  (let* ((slash (substitute #\\ #\/ path))
         (unc-p (and (>= (length slash) 2)
                     (char= (char slash 0) #\\)
                     (char= (char slash 1) #\\)))
         (trailing-p (and (plusp (length slash))
                          (char= (char slash (1- (length slash))) #\\)))
         (parts (remove ""
                        (uiop:split-string slash :separator '(#\\))
                        :test #'string=))
         (stack nil))
    (dolist (part parts)
      (cond
        ((string= part ".") nil)
        ((string= part "..")
         (cond
           ((null stack) (push part stack))
           ((windows-drive-prefix-p (first stack)) nil)
           ((string= (first stack) "..") (push part stack))
           (t (pop stack))))
        (t (push part stack))))
    (let* ((ordered (nreverse stack))
           (joined
             (cond
               ((null ordered) (if unc-p "\\\\" ""))
               (unc-p (format nil "\\\\~{~A~^\\~}" ordered))
               (t (format nil "~{~A~^\\~}" ordered)))))
      (if (and trailing-p
               (plusp (length joined))
               (not (char= (char joined (1- (length joined))) #\\)))
          (concatenate 'string joined "\\")
          joined))))

(defun legacy-wsl-bash-path-p
    (path &key (environment-function #'uiop:getenv))
  (let ((normalized (string-downcase (normalize-windows-path path)))
        (system-root
          (non-empty-environment-value environment-function
                                       "SystemRoot")))
    (if system-root
        (and (cl-ppcre:scan "(?i)^[a-z]:[\\\\/]" system-root)
             (some (lambda (directory)
                     (string=
                      normalized
                      (string-downcase
                       (normalize-windows-path
                        (windows-path-join system-root directory
                                           "bash.exe")))))
                   '("System32" "Sysnative")))
        (cl-ppcre:scan
         "^[a-z]:\\\\windows\\\\(?:system32|sysnative)\\\\bash\\.exe$"
         normalized))))

(defun bash-shell-config
    (shell &key (environment-function #'uiop:getenv))
  (if (legacy-wsl-bash-path-p
       shell :environment-function environment-function)
      (make-shell-config :shell shell :arguments '("-s")
                         :command-transport :stdin)
      (make-shell-config :shell shell :arguments '("-c"))))

(defun executable-on-path
    (name &key (environment-function #'uiop:getenv)
               (path-exists-function #'probe-file)
               (windows-p (uiop:os-windows-p)))
  (let ((separator (if windows-p #\; #\:)))
    (loop for directory in (uiop:split-string
                            (or (funcall environment-function "PATH") "")
                            :separator (list separator))
          unless (string= directory "")
            do (let* ((root (uiop:ensure-directory-pathname directory))
                      (candidate (merge-pathnames name root))
                      (windows-candidate
                        (and windows-p
                             (merge-pathnames
                              (concatenate 'string name ".exe")
                              root))))
                 (cond
                   ((funcall path-exists-function candidate)
                    (return (namestring candidate)))
                   ((and windows-candidate
                         (funcall path-exists-function
                                  windows-candidate))
                    (return (namestring windows-candidate))))))))

(defparameter +powershell-args+
  '("-NoProfile" "-NonInteractive" "-ExecutionPolicy" "Bypass" "-Command"))

(defun get-powershell-config
    (&key (windows-p (uiop:os-windows-p))
          (environment-function #'uiop:getenv)
          (path-exists-function #'probe-file)
          (find-on-path
           (lambda (name)
             (executable-on-path
              name
              :environment-function environment-function
              :path-exists-function path-exists-function
              :windows-p windows-p))))
  (unless windows-p
    (error "The powershell tool is only available on Windows."))
  (let ((shell (funcall find-on-path "pwsh.exe")))
    (unless shell
      (let ((program-files
              (non-empty-environment-value environment-function
                                           "ProgramFiles")))
        (when program-files
          (let ((pwsh7
                  (windows-path-join program-files "PowerShell" "7"
                                     "pwsh.exe")))
            (when (funcall path-exists-function pwsh7)
              (setf shell pwsh7))))))
    (unless shell
      (setf shell (funcall find-on-path "powershell.exe")))
    (unless shell
      (let ((system-root
              (non-empty-environment-value environment-function
                                           "SystemRoot")))
        (when system-root
          (let ((windows-powershell
                  (windows-path-join
                   system-root "System32" "WindowsPowerShell" "v1.0"
                   "powershell.exe")))
            (when (funcall path-exists-function windows-powershell)
              (setf shell windows-powershell))))))
    (unless shell
      (error
       "No PowerShell executable found. Install PowerShell or add powershell.exe/pwsh.exe to PATH."))
    (make-shell-config
     :shell shell
     :arguments (copy-list +powershell-args+))))

(defun get-shell-config
    (&optional custom-shell-path
     &key (windows-p (uiop:os-windows-p))
          (environment-function #'uiop:getenv)
          (path-exists-function #'probe-file)
          (find-on-path
           (lambda (name)
             (executable-on-path
              name
              :environment-function environment-function
              :path-exists-function path-exists-function
              :windows-p windows-p))))
  (cond
    (custom-shell-path
     (if (funcall path-exists-function custom-shell-path)
         (bash-shell-config
          custom-shell-path
          :environment-function environment-function)
         (error "Custom shell path not found: ~A" custom-shell-path)))
    (windows-p
     (let ((candidates
             (remove nil
                     (loop for name in '("ProgramFiles"
                                         "ProgramFiles(x86)")
                           for root =
                             (non-empty-environment-value
                              environment-function name)
                           collect
                           (and root
                                (windows-path-join root "Git" "bin"
                                                   "bash.exe"))))))
       (let ((shell (or (find-if path-exists-function candidates)
                        (funcall find-on-path "bash.exe"))))
         (if shell
             (bash-shell-config
              shell :environment-function environment-function)
             (error "No bash shell found. Install Git for Windows, add bash to PATH, or set shellPath in settings.json")))))
    ((funcall path-exists-function "/bin/bash")
     (bash-shell-config
      "/bin/bash" :environment-function environment-function))
    ((funcall find-on-path "bash")
     (bash-shell-config
      (funcall find-on-path "bash")
      :environment-function environment-function))
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

(defun kill-process-tree
    (pid &key runner
              (windows-p (uiop:os-windows-p))
              (environment-function #'uiop:getenv))
  (labels ((run (command)
             (ignore-errors
               (if runner
                   (funcall runner command)
                   (uiop:run-program command :output nil :error-output nil
                                             :ignore-error-status t)))))
    (if windows-p
        (run (list
              (let ((root
                      (or (non-empty-environment-value
                           environment-function "SystemRoot")
                          "C:\\Windows")))
                (windows-path-join root "System32" "taskkill.exe"))
              "/F" "/T" "/PID" (princ-to-string pid)))
        (multiple-value-bind (stdout stderr status)
            (run (list "/bin/kill" "-KILL" "--" (format nil "-~D" pid)))
          (declare (ignore stdout stderr))
          (unless (and (integerp status) (zerop status))
            (run (list "/bin/kill" "-KILL" "--" (princ-to-string pid)))))))
  nil)

(defun kill-tracked-detached-children
    (&key runner
          (windows-p (uiop:os-windows-p))
          (environment-function #'uiop:getenv))
  (let ((pids
          (sb-thread:with-mutex (*tracked-detached-child-lock*)
            (prog1
                (loop for pid being the hash-keys of *tracked-detached-child-pids*
                      collect pid)
              (clrhash *tracked-detached-child-pids*)))))
    (dolist (pid pids)
      (kill-process-tree pid
                         :runner runner
                         :windows-p windows-p
                         :environment-function environment-function)))
  nil)
