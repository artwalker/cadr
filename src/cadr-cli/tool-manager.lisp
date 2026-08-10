(in-package #:cadr-cli)

(defun cadr-bin-directory ()
  (cadr-core:agent-bin-directory))

(defun tool-binary-name (tool)
  (ecase tool (:fd "fd") (:rg "rg")))

(defun system-tool-names (tool)
  (ecase tool (:fd '("fd" "fdfind")) (:rg '("rg"))))

(defun get-tool-path (tool &key (bin-directory (cadr-bin-directory)))
  (let* ((binary (tool-binary-name tool))
         (local
           (merge-pathnames
            (if (uiop:os-windows-p)
                (concatenate 'string binary ".exe") binary)
            bin-directory)))
    (cond
      ((probe-file local) (namestring local))
      (t
       (loop for name in (system-tool-names tool)
             for path = (ignore-errors (executable-on-path name))
             when path return name)))))

(defun truthy-env-flag-p (name)
  (member (string-downcase (or (uiop:getenv name) ""))
          '("1" "true" "yes") :test #'string=))

(defun offline-mode-p ()
  (truthy-env-flag-p "CADR_OFFLINE"))

(defun host-platform-name ()
  (cond ((uiop:os-windows-p) :windows)
        ((uiop:os-macosx-p) :darwin)
        ((uiop:os-unix-p) :linux)
        (t :unknown)))

(defun host-architecture-name ()
  (let ((machine (string-downcase (machine-type))))
    (cond
      ((or (search "aarch64" machine) (search "arm64" machine)) :arm64)
      ((or (search "x86-64" machine) (search "x86_64" machine)
           (search "amd64" machine)) :x64)
      (t :unknown))))

(defun tool-repository (tool)
  (ecase tool (:fd "sharkdp/fd") (:rg "BurntSushi/ripgrep")))

(defun tool-display-name (tool)
  (ecase tool (:fd "fd") (:rg "ripgrep")))

(defun tool-release-asset (tool version platform architecture)
  (let ((arch (ecase architecture (:arm64 "aarch64") (:x64 "x86_64"))))
    (ecase tool
      (:fd
       (ecase platform
         (:darwin (format nil "fd-v~A-~A-apple-darwin.tar.gz" version arch))
         (:linux (format nil "fd-v~A-~A-unknown-linux-gnu.tar.gz" version arch))
         (:windows (format nil "fd-v~A-~A-pc-windows-msvc.zip" version arch))))
      (:rg
       (ecase platform
         (:darwin (format nil "ripgrep-~A-~A-apple-darwin.tar.gz" version arch))
         (:linux
          (format nil "ripgrep-~A-~A-unknown-linux-~A.tar.gz"
                  version arch (if (eq architecture :arm64) "gnu" "musl")))
         (:windows (format nil "ripgrep-~A-~A-pc-windows-msvc.zip" version arch)))))))

(defun default-tool-command-runner (arguments &key output-file)
  (if output-file
      (with-open-file (output output-file :direction :output
                             :if-exists :supersede
                             :if-does-not-exist :create
                             :element-type '(unsigned-byte 8))
        (uiop:run-program arguments :output output :error-output :string
                                   :ignore-error-status t))
      (uiop:run-program arguments :output :string :error-output :string
                                 :ignore-error-status t)))

(defun latest-tool-version (tool runner)
  (multiple-value-bind (stdout stderr status)
      (funcall runner
               (list "curl" "-fsSL" "--max-time" "10"
                     (format nil "https://api.github.com/repos/~A/releases/latest"
                             (tool-repository tool))))
    (declare (ignore stderr))
    (unless (and (integerp status) (zerop status))
      (error "GitHub API error for ~A" (tool-repository tool)))
    (let* ((object (cadr-ai::parse-json stdout))
           (tag (cadr-ai::json-get object "tag_name")))
      (unless (and (stringp tag) (plusp (length tag)))
        (error "GitHub release response omitted tag_name"))
      (string-left-trim "v" tag))))

(defun find-file-recursively (directory name)
  (labels ((walk (root)
             (dolist (path (uiop:directory-files root))
               (when (string= name (file-namestring path))
                 (return-from find-file-recursively path)))
             (dolist (child (uiop:subdirectories root))
               (walk child))))
    (walk (uiop:ensure-directory-pathname directory))
    nil))

(defun call-with-temporary-tool-directory (function)
  (let ((directory
          (loop repeat 100
                for candidate =
                  (merge-pathnames
                   (format nil "cadr-tool-~16,'0X/"
                           (random (ash 1 64)))
                   (uiop:temporary-directory))
                unless (probe-file candidate)
                  do (ensure-directories-exist
                      (merge-pathnames "placeholder" candidate))
                     (return candidate)
                finally (error "Unable to allocate a temporary tool directory"))))
    (unwind-protect
         (funcall function directory)
      (uiop:delete-directory-tree
       directory :validate t :if-does-not-exist :ignore))))

(defun windows-tar-command ()
  (let* ((root (or (uiop:getenv "SystemRoot") (uiop:getenv "WINDIR")))
         (path (and root (format nil "~A\\System32\\tar.exe" root))))
    (if (and path (probe-file path)) path "tar.exe")))

(defun tool-extraction-commands (asset archive extract platform)
  (cond
    ((uiop:string-suffix-p asset ".tar.gz")
     (list (list "tar" "xzf" (namestring archive)
                 "-C" (namestring extract))))
    ((not (uiop:string-suffix-p asset ".zip"))
     (error "Unsupported archive format: ~A" asset))
    ((eq platform :windows)
     (list
      (list (windows-tar-command) "xf" (namestring archive)
            "-C" (namestring extract))
      (list
       "powershell.exe" "-NoLogo" "-NoProfile" "-NonInteractive"
       "-ExecutionPolicy" "Bypass" "-Command"
       "& { param($archive, $destination) $ErrorActionPreference = 'Stop'; Expand-Archive -LiteralPath $archive -DestinationPath $destination -Force }"
       (namestring archive) (namestring extract))))
    (t
     (list
      (list "unzip" "-q" (namestring archive) "-d" (namestring extract))
      (list "tar" "xf" (namestring archive) "-C" (namestring extract))))))

(defun extract-tool-archive (runner asset archive extract platform)
  (let ((failures nil))
    (dolist (command (tool-extraction-commands asset archive extract platform))
      (multiple-value-bind (stdout stderr status) (funcall runner command)
        (when (and (integerp status) (zerop status))
          (return-from extract-tool-archive t))
        (push (format nil "~A: ~A"
                      (first command)
                      (or (and stderr (plusp (length stderr)) stderr)
                          (and stdout (plusp (length stdout)) stdout)
                          (format nil "exit status ~A" status)))
              failures)))
    (error "Failed to extract ~A: ~{~A~^; ~}"
           asset (nreverse failures))))

(defun install-tool-from-release
    (tool &key (bin-directory (cadr-bin-directory))
               (runner #'default-tool-command-runner))
  (let* ((platform (host-platform-name))
         (architecture (host-architecture-name)))
    (when (or (eq platform :unknown) (eq architecture :unknown))
      (error "Unsupported platform: ~A/~A" platform architecture))
    (let* ((version (latest-tool-version tool runner))
           (version
             (if (and (eq tool :fd) (eq platform :darwin)
                      (eq architecture :x64))
                 "10.3.0" version))
           (asset (tool-release-asset tool version platform architecture))
           (tag (if (eq tool :fd) (concatenate 'string "v" version) version))
           (url (format nil "https://github.com/~A/releases/download/~A/~A"
                        (tool-repository tool) tag asset)))
      (call-with-temporary-tool-directory
       (lambda (temporary)
         (let* ((archive (merge-pathnames asset temporary))
                (extract (merge-pathnames "extract/" temporary))
                (binary-name
                  (if (eq platform :windows)
                      (concatenate 'string (tool-binary-name tool) ".exe")
                      (tool-binary-name tool))))
           (ensure-directories-exist (merge-pathnames "placeholder" extract))
           (multiple-value-bind (stdout stderr status)
               (funcall runner
                        (list "curl" "-fL" "--max-time" "120"
                              "-o" (namestring archive) url))
             (declare (ignore stdout))
             (unless (and (integerp status) (zerop status))
               (error "Failed to download ~A: ~A" asset stderr)))
           (extract-tool-archive runner asset archive extract platform)
           (let ((source (find-file-recursively extract binary-name))
                 (target (merge-pathnames binary-name bin-directory)))
             (unless source
               (error "Binary not found in archive: ~A" binary-name))
             (ensure-directories-exist target)
             (uiop:copy-file source target)
             (unless (eq platform :windows)
               (funcall runner (list "chmod" "755" (namestring target))))
             (namestring target))))))))

(defun ensure-tool
    (tool &key silent-p (installer #'install-tool-from-release)
               (output *standard-output*))
  (or (get-tool-path tool)
      (cond
        ((offline-mode-p)
         (unless silent-p
           (format output "~A not found. Offline mode enabled, skipping download.~%"
                   (tool-display-name tool)))
         nil)
        ((or (search "android" (string-downcase (software-type)))
             (uiop:getenv "TERMUX_VERSION"))
         (unless silent-p
           (format output "~A not found. Install with: pkg install ~A~%"
                   (tool-display-name tool)
                   (if (eq tool :rg) "ripgrep" "fd")))
         nil)
        (t
         (unless silent-p
           (format output "~A not found. Downloading...~%"
                   (tool-display-name tool)))
         (handler-case
             (let ((path (funcall installer tool)))
               (unless silent-p
                 (format output "~A installed to ~A~%"
                         (tool-display-name tool) path))
               path)
           (error (condition)
             (unless silent-p
               (format output "Failed to download ~A: ~A~%"
                       (tool-display-name tool) condition))
             nil))))))

(defparameter +windows-native-quarantine-directory+ ".cadr-native-quarantine/")
(defparameter *loaded-shared-object-paths-function*
  (lambda ()
    (loop for object in sb-sys:*shared-objects*
          for path = (cond ((pathnamep object) object)
                           ((stringp object) (pathname object)))
          when path collect path)))

(defun native-quarantine-root (package-directory)
  (let ((current (uiop:ensure-directory-pathname
                  (truename package-directory))))
    (loop
      (when (string-equal "node_modules"
                          (car (last (pathname-directory current))))
        (return
          (merge-pathnames +windows-native-quarantine-directory+ current)))
      (let ((parent (uiop:pathname-parent-directory-pathname current)))
        (when (equal parent current)
          (return nil))
        (setf current parent)))))

(defun cleanup-windows-self-update-quarantine (package-directory)
  (let ((root (ignore-errors (native-quarantine-root package-directory))))
    (when root
      (ignore-errors (uiop:delete-directory-tree root :validate t :if-does-not-exist :ignore))))
  nil)

(defun quarantine-windows-native-dependencies
    (package-directory &key loaded-paths)
  (let* ((package (uiop:ensure-directory-pathname (truename package-directory)))
         (root (native-quarantine-root package)))
    (when root
      (let ((run-directory
              (merge-pathnames
               (format nil "~D-~D/" (get-universal-time)
                       (random most-positive-fixnum))
               root)))
        (dolist (path (or loaded-paths
                          (funcall *loaded-shared-object-paths-function*)))
          (let ((relative (ignore-errors (enough-namestring (truename path) package))))
            (when (and relative
                       (not (uiop:string-prefix-p "../" relative)))
              (let ((target (merge-pathnames relative run-directory)))
                (ensure-directories-exist target)
                (rename-file path target)
                (uiop:copy-file target path))))))))
  nil)
