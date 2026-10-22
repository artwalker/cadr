(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

;;; Locked to pi 61060ddf8 (coding-agent shell / tools-manager).

(defun goal26-env (&rest pairs)
  (lambda (name)
    (loop for (key value) on pairs by #'cddr
          when (string-equal (string key) name)
            return value)))

(defun goal26-path-exists (existing)
  (lambda (path)
    (member (if (stringp path) path (namestring path))
            existing
            :test #'string-equal)))

(test goal26-powershell-prefers-pwsh-on-path
  ;; Upstream: prefers PowerShell 7 on PATH over known installation locations.
  (let* ((shell "E:\\Tools\\pwsh.exe")
         (config
           (cadr-cli:get-powershell-config
            :windows-p t
            :environment-function
            (goal26-env :ProgramFiles "D:\\Applications"
                        :SystemRoot "E:\\WinNT")
            :path-exists-function (constantly nil)
            :find-on-path
            (lambda (name)
              (when (string= name "pwsh.exe") shell)))))
    (is (string= shell (cadr-cli:shell-config-shell config)))
    (is (equal cadr-cli:+powershell-args+
               (cadr-cli:shell-config-arguments config)))))

(test goal26-powershell-finds-pwsh7-under-program-files
  ;; Upstream: finds PowerShell 7 under ProgramFiles before Windows PowerShell on PATH.
  (let* ((pwsh7 "D:\\Applications\\PowerShell\\7\\pwsh.exe")
         (windows-powershell
           "E:\\WinNT\\System32\\WindowsPowerShell\\v1.0\\powershell.exe")
         (config
           (cadr-cli:get-powershell-config
            :windows-p t
            :environment-function
            (goal26-env :ProgramFiles "D:\\Applications"
                        :SystemRoot "E:\\WinNT")
            :path-exists-function
            (goal26-path-exists (list pwsh7 windows-powershell))
            :find-on-path
            (lambda (name)
              (when (string= name "powershell.exe")
                windows-powershell)))))
    (is (string= pwsh7 (cadr-cli:shell-config-shell config)))))

(test goal26-powershell-prefers-path-powershell-over-system
  ;; Upstream: prefers Windows PowerShell on PATH over its system installation.
  (let* ((shell "E:\\Tools\\powershell.exe")
         (windows-powershell
           "E:\\WinNT\\System32\\WindowsPowerShell\\v1.0\\powershell.exe")
         (config
           (cadr-cli:get-powershell-config
            :windows-p t
            :environment-function
            (goal26-env :ProgramFiles "D:\\Applications"
                        :SystemRoot "E:\\WinNT")
            :path-exists-function
            (goal26-path-exists (list shell windows-powershell))
            :find-on-path
            (lambda (name)
              (cond
                ((string= name "pwsh.exe") nil)
                ((string= name "powershell.exe") shell))))))
    (is (string= shell (cadr-cli:shell-config-shell config)))))

(test goal26-powershell-finds-system-installation
  ;; Upstream: finds Windows PowerShell under SystemRoot when PATH lookup is unavailable.
  (let* ((windows-powershell
           "E:\\WinNT\\System32\\WindowsPowerShell\\v1.0\\powershell.exe")
         (config
           (cadr-cli:get-powershell-config
            :windows-p t
            :environment-function
            (goal26-env :ProgramFiles "D:\\Applications"
                        :SystemRoot "E:\\WinNT")
            :path-exists-function
            (goal26-path-exists (list windows-powershell))
            :find-on-path (constantly nil))))
    (is (string= windows-powershell
                 (cadr-cli:shell-config-shell config)))))

(test goal26-powershell-errors-when-missing
  (let ((message
          (handler-case
              (progn
                (cadr-cli:get-powershell-config
                 :windows-p t
                 :environment-function
                 (goal26-env :ProgramFiles "D:\\Applications"
                             :SystemRoot "E:\\WinNT")
                 :path-exists-function (constantly nil)
                 :find-on-path (constantly nil))
                nil)
            (error (condition)
              (princ-to-string condition)))))
    (is (search "No PowerShell executable found" message))))

(test goal26-legacy-wsl-bash-uses-system-root
  ;; Upstream windows-shell-config.test.ts cases for #9490.
  (dolist (case
           '(("D:\\WinNT\\" "d:/WINNT/System32/BASH.EXE" t)
             ("D:\\WinNT" "D:\\WinNT\\Sysnative\\bash.exe" t)
             (nil "E:\\Windows\\System32\\bash.exe" t)
             (nil "E:\\foo\\..\\Windows\\System32\\bash.exe" t)
             ("D:\\WinNT" "D:\\WinNT\\System32\\..\\System32\\bash.exe" t)
             ("D:\\WinNT" "D:/WinNT/System32/./bash.exe" t)
             ("D:\\WinNT" "D:\\Git\\bin\\bash.exe" nil)
             ("D:\\WinNT" "E:\\Windows\\System32\\bash.exe" nil)
             ("WinNT" "C:\\Windows\\System32\\bash.exe" nil)))
    (destructuring-bind (system-root shell stdin-p) case
      (let ((config
              (cadr-cli:get-shell-config
               shell
               :windows-p t
               :environment-function
               (lambda (name)
                 (when (string= name "SystemRoot") system-root))
               :path-exists-function (constantly t))))
        (if stdin-p
            (progn
              (is (equal '("-s") (cadr-cli:shell-config-arguments config)))
              (is (eq :stdin
                      (cadr-cli:shell-config-command-transport config))))
            (progn
              (is (equal '("-c") (cadr-cli:shell-config-arguments config)))
              (is (null
                   (cadr-cli:shell-config-command-transport
                    config)))))))))

(test goal26-taskkill-falls-back-for-empty-system-root
  ;; Upstream #9490 / #6596: missing or empty SystemRoot keeps absolute taskkill.
  (dolist (case
           '(("D:\\CustomWindows" "D:\\CustomWindows")
             (nil "C:\\Windows")
             ("" "C:\\Windows")))
    (destructuring-bind (system-root expected-root) case
      (let ((commands nil))
        (cadr-cli:kill-process-tree
         1234
         :windows-p t
         :environment-function
         (lambda (name)
           (when (string= name "SystemRoot") system-root))
         :runner
         (lambda (argv)
           (push argv commands)
           (values nil nil 0)))
        (is (equal
             (list (format nil "~A\\System32\\taskkill.exe" expected-root)
                   "/F" "/T" "/PID" "1234")
             (first commands)))))))

(test goal26-windows-tar-ignores-windir
  ;; Upstream 61060ddf8: getWindowsTarCommand reads SystemRoot only.
  (is (string=
       "D:\\WinNT\\System32\\tar.exe"
       (cadr-cli::windows-tar-command
        :environment-function
        (goal26-env :SystemRoot "D:\\WinNT"
                    :WINDIR "E:\\Legacy")
        :path-exists-function
        (goal26-path-exists
         '("D:\\WinNT\\System32\\tar.exe"
           "E:\\Legacy\\System32\\tar.exe")))))
  (is (string=
       "tar.exe"
       (cadr-cli::windows-tar-command
        :environment-function
        (goal26-env :WINDIR "E:\\Legacy")
        :path-exists-function
        (goal26-path-exists '("E:\\Legacy\\System32\\tar.exe")))))
  (is (string=
       "tar.exe"
       (cadr-cli::windows-tar-command
        :environment-function
        (goal26-env :SystemRoot ""
                    :WINDIR "E:\\Legacy")
        :path-exists-function
        (goal26-path-exists '("E:\\Legacy\\System32\\tar.exe"))))))
