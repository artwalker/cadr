(in-package #:cadr-cli)

(defun clipboard-command-candidates
    (&key
       platform
       termux-p
       wayland-p
       wayland-display-p
       x11-display-p)
  (cond
    ((eq platform :darwin)
     '(("pbcopy")))
    ((eq platform :windows)
     '(("clip")))
    (t
     (append
      (and termux-p
           '(("termux-clipboard-set")))
      (and wayland-p wayland-display-p
           '(("wl-copy")))
      (and x11-display-p
           '(("xclip" "-selection" "clipboard")
             ("xsel" "--clipboard" "--input")))))))

(defun osc52-copy-sequence
    (text &key (maximum-bytes 100000))
  (let* ((bytes (cadr-ai::utf8-octets text))
         (encoded
           (encode-base64-bytes bytes)))
    (when (<= (length encoded)
              maximum-bytes)
      (format nil "~C]52;c;~A~C"
              #\Escape encoded
              (code-char 7)))))

(defun read-clipboard-text (&key native-getter)
  (when native-getter
    (handler-case
        (let ((text
                (funcall native-getter)))
          (and (stringp text)
               (plusp (length text))
               text))
      (condition () nil))))

(defun clipboard-process-argv (argv)
  ;; v1.4.0 runClipboardCommand sets detached on POSIX. That is
  ;; setsid(2): the helper becomes its own session, so Ctrl+Z
  ;; (SIGTSTP to this process group) does not stop a daemonized
  ;; wl-copy, xclip, or xsel (#11179). Windows stays in the parent
  ;; group. --wait keeps the helper's exit status; without it a
  ;; setsid that has to fork reports success for a failed command.
  (if (or (uiop:os-windows-p)
          (not (probe-file #P"/usr/bin/setsid")))
      argv
      (list* "/usr/bin/setsid" "--wait" argv)))

(defun default-clipboard-copy-runner (argv input)
  (handler-case
      (let ((stream
              (make-string-input-stream (or input "")))
            (program (first argv))
            (argv (clipboard-process-argv argv)))
        (if (member program
                    '("wslpath" "powershell.exe")
                    :test #'string=)
            (values
             t
             (uiop:run-program
              argv
              :input stream
              :output :string
              :error-output nil))
            (progn
              (uiop:run-program
               argv
               :input stream
               :output nil
               :error-output nil)
              t)))
    (condition () nil)))

(defun default-clipboard-text-temporary-path ()
  (merge-pathnames
   (format nil "cadr-wsl-clip-~A.txt"
           (cadr-ai:uuid-v7))
   (uiop:temporary-directory)))

(defun copy-text-via-windows-clipboard
    (text command-runner temporary-path-provider)
  (let ((temporary (funcall temporary-path-provider)))
    (unwind-protect
         (handler-case
             (progn
               (ensure-directories-exist temporary)
               (with-open-file
                   (stream temporary
                           :direction :output
                           :if-exists :supersede
                           :if-does-not-exist :create
                           :external-format :utf-8)
                 (write-string text stream))
               (sb-posix:chmod
                (namestring temporary) #o600)
               (multiple-value-bind (ok output)
                   (funcall
                    command-runner
                    (list "wslpath" "-w"
                          (namestring temporary))
                    "")
                 (let ((windows-path
                         (string-trim
                          '(#\Space #\Tab #\Newline #\Return)
                          (or output ""))))
                   (when (or (not ok)
                             (zerop (length windows-path)))
                     (return-from
                         copy-text-via-windows-clipboard
                       nil))
                   (funcall
                    command-runner
                    (list
                     "powershell.exe" "-NoProfile" "-Command"
                     (format
                      nil
                      "Set-Clipboard -Value ([System.IO.File]::ReadAllText('~A', [System.Text.Encoding]::UTF8))"
                      (powershell-single-quote
                       windows-path)))
                    ""))))
           (condition () nil))
      (when (probe-file temporary)
        (delete-file temporary)))))

(defun emit-clipboard-osc52 (text output)
  (let ((sequence (osc52-copy-sequence text)))
    (when sequence
      (write-string sequence output)
      (finish-output output)
      sequence)))

(defun clipboard-unavailable-message
    (&key platform termux-p wayland-display-p x11-display-p oversized-p)
  ;; A failed local write names the missing backend. Headless and
  ;; remote paths use OSC 52. This message is only for backends that
  ;; were attempted and failed.
  (cond
    (oversized-p
     "Clipboard unavailable: text exceeds the OSC 52 size limit")
    ((eq platform :linux)
     (cond
       (termux-p
        "Clipboard unavailable: install the Termux:API app and `termux-api` package")
       (wayland-display-p
        "Clipboard unavailable: install `wl-clipboard` (`wl-copy`) or check Wayland access")
       (x11-display-p
        "Clipboard unavailable: install `xclip` or `xsel`, or check X11 access")
       (t "Clipboard unavailable")))
    (t "Clipboard unavailable")))

(defun copy-to-clipboard
    (text
     &key
       (platform :linux)
       termux-p
       wayland-p
       wayland-display-p
       x11-display-p
       remote-p
       (wsl-p nil wsl-p-supplied-p)
       (windows-terminal-p nil windows-terminal-p-supplied-p)
       environment
       native-setter
       (command-runner
         #'default-clipboard-copy-runner)
       (temporary-path-provider
         #'default-clipboard-text-temporary-path)
       (output *standard-output*))
  (let* ((wsl-session-p
           (and (eq platform :linux)
                (if wsl-p-supplied-p
                    wsl-p
                    (clipboard-wsl-p environment))))
         (windows-terminal-session-p
           (if windows-terminal-p-supplied-p
               windows-terminal-p
               (not
                (null
                 (clipboard-environment-value
                  environment "WT_SESSION")))))
         (headless-p
           (and (eq platform :linux)
                (not termux-p)
                (not wayland-display-p)
                (not x11-display-p)))
         ;; v1.4.0 clipboard.ts isRemoteSession. A non-empty SSH or
         ;; mosh marker is remote. Exact "1" is a remote client that
         ;; left no marker, so OSC 52 follows a successful local write.
         ;; The runtime name is CADR_CLIPBOARD_OSC52.
         (session-remote-p
           (or remote-p
               (clipboard-remote-session-p environment)))
         (copied-p nil)
         (native-p nil)
         (shell-p nil)
         (osc52 nil)
         (oversized-p nil))
    (when (and native-setter
               (not (eq platform :linux)))
      (handler-case
          (progn
            (funcall native-setter text)
            (setf copied-p t
                  native-p t))
        (condition () nil)))
    (when (and copied-p
               (not session-remote-p))
      (return-from copy-to-clipboard :native))
    (unless copied-p
      (dolist
          (argv
           (clipboard-command-candidates
            :platform platform
            :termux-p termux-p
            :wayland-p wayland-p
            :wayland-display-p wayland-display-p
            :x11-display-p x11-display-p))
        (when
            (handler-case
                (funcall command-runner argv text)
              (condition () nil))
          (setf copied-p t
                shell-p t)
          (return))))
    (when (and (not copied-p) wsl-session-p)
      (when (and windows-terminal-session-p
                 (emit-clipboard-osc52 text output))
        (setf osc52 t
              copied-p t))
      (unless copied-p
        (when (copy-text-via-windows-clipboard
               text command-runner
               temporary-path-provider)
          (setf copied-p t
                shell-p t))))
    (unless osc52
      (when (or session-remote-p
                (and (not copied-p) headless-p))
        (if (emit-clipboard-osc52 text output)
            (setf osc52 t
                  copied-p t)
            (setf oversized-p t))))
    (unless copied-p
      (error
       'cadr-ai:configuration-error
       :message
       (clipboard-unavailable-message
        :platform platform
        :termux-p termux-p
        :wayland-display-p wayland-display-p
        :x11-display-p x11-display-p
        :oversized-p oversized-p)))
    (cond
      ((and native-p osc52) :native+osc52)
      ((and shell-p osc52) :shell+osc52)
      (native-p :native)
      (shell-p :shell)
      (osc52 :osc52)
      (t :unknown))))

(defstruct clipboard-image
  bytes
  mime-type)

(declaim (ftype function process-image-bytes))

(defparameter +clipboard-image-mime-preference+
  '("image/png" "image/jpeg" "image/webp"
    "image/gif"))

(defun clipboard-environment-value
    (environment name)
  (if environment
      (cdr
       (assoc name environment :test #'string=))
      (uiop:getenv name)))

(defun clipboard-truthy-environment-p (environment name)
  ;; JS Boolean(env[name]): missing and "" are false. Any other string is true.
  (let ((value (clipboard-environment-value environment name)))
    (and (stringp value) (plusp (length value)))))

(defun clipboard-remote-session-p (environment)
  ;; v1.4.0 clipboard.ts isRemoteSession, with the product env name.
  (or (clipboard-truthy-environment-p
       environment "SSH_CONNECTION")
      (clipboard-truthy-environment-p
       environment "SSH_CLIENT")
      (clipboard-truthy-environment-p
       environment "MOSH_CONNECTION")
      (equal
       "1"
       (clipboard-environment-value
        environment "CADR_CLIPBOARD_OSC52"))))

(defun clipboard-wayland-p (environment)
  (or
   (clipboard-environment-value
    environment "WAYLAND_DISPLAY")
   (string-equal
    (or
     (clipboard-environment-value
      environment "XDG_SESSION_TYPE")
     "")
    "wayland")))

(defun clipboard-wsl-p (environment)
  (or
   (clipboard-environment-value
    environment "WSL_DISTRO_NAME")
   (clipboard-environment-value
    environment "WSL_INTEROP")
   (clipboard-environment-value
    environment "WSLENV")
   (ignore-errors
     (search
      "microsoft"
      (string-downcase
       (uiop:read-file-string
        #P"/proc/version"
        :external-format :utf-8))))))

(defun clipboard-base-mime-type (value)
  (string-downcase
   (string-trim
    '(#\Space #\Tab)
    (first
     (uiop:split-string
      value :separator '(#\;))))))

(defun preferred-clipboard-image-mime
    (text)
  (let ((types
          (remove
           ""
           (mapcar
            (lambda (line)
              (string-trim
               '(#\Space #\Tab #\Return)
               line))
            (uiop:split-string
             text :separator '(#\Newline)))
           :test #'string=)))
    (or
     (loop for preferred
           in +clipboard-image-mime-preference+
           thereis
           (find
            preferred types
            :test
            (lambda (left right)
              (string=
               left
               (clipboard-base-mime-type
                right)))))
     (find-if
      (lambda (value)
        (uiop:string-prefix-p
         "image/"
         (clipboard-base-mime-type value)))
      types))))

(defun default-clipboard-image-runner (argv)
  (handler-case
      (let ((bytes
              (uiop:run-program
               (clipboard-process-argv argv)
               :output :byte-vector
               :error-output nil)))
        (values bytes t))
    (condition ()
      (values
       (make-array
        0 :element-type '(unsigned-byte 8))
       nil))))

(defun clipboard-command-text (bytes)
  (handler-case
      (sb-ext:octets-to-string
       bytes :external-format :utf-8)
    (condition () "")))

(defun clipboard-image-from-bytes
    (bytes mime-type)
  (when (and bytes
             (plusp (length bytes)))
    (let ((base
            (clipboard-base-mime-type
             mime-type)))
      (if
          (member
           base
           +clipboard-image-mime-preference+
           :test #'string=)
          (make-clipboard-image
           :bytes bytes
           :mime-type base)
          (let ((processed
                  (process-image-bytes
                   bytes base
                   :auto-resize-p nil)))
            (when
                (and
                 (image-process-result-mime-type
                  processed)
                 (member
                  (image-process-result-mime-type
                   processed)
                  +clipboard-image-mime-preference+
                  :test #'string=))
              (make-clipboard-image
               :bytes
               (image-process-result-bytes
                processed)
               :mime-type
               (image-process-result-mime-type
                processed))))))))

(defun read-clipboard-image-via-wl-paste
    (runner)
  (multiple-value-bind (type-bytes ok)
      (funcall runner
               '("wl-paste" "--list-types"))
    (when ok
      (let ((mime
              (preferred-clipboard-image-mime
               (clipboard-command-text type-bytes))))
        (when mime
          (multiple-value-bind (bytes read-ok)
              (funcall
               runner
               (list
                "wl-paste" "--type" mime
                "--no-newline"))
            (when read-ok
              (clipboard-image-from-bytes
               bytes mime))))))))

(defun read-clipboard-image-via-xclip
    (runner)
  (multiple-value-bind (target-bytes target-ok)
      (funcall
       runner
       '("xclip" "-selection" "clipboard"
         "-t" "TARGETS" "-o"))
    (let* ((preferred
             (and target-ok
                  (preferred-clipboard-image-mime
                   (clipboard-command-text
                    target-bytes))))
           (types
             (remove-duplicates
              (append
               (and preferred (list preferred))
               +clipboard-image-mime-preference+)
              :test #'string=)))
      (dolist (mime types)
        (multiple-value-bind (bytes ok)
            (funcall
             runner
             (list
              "xclip" "-selection" "clipboard"
              "-t" mime "-o"))
          (when ok
            (let ((image
                    (clipboard-image-from-bytes
                     bytes mime)))
              (when image
                (return-from
                    read-clipboard-image-via-xclip
                  image)))))))))

(defun read-clipboard-image-via-native
    (native-image-reader)
  (when native-image-reader
    (handler-case
        (multiple-value-bind (bytes mime-type)
            (funcall native-image-reader)
          (clipboard-image-from-bytes
           bytes (or mime-type "image/png")))
      (condition () nil))))

(defun default-clipboard-temporary-path ()
  (merge-pathnames
   (format nil "cadr-wsl-clip-~A.png"
           (cadr-ai:uuid-v7))
   (uiop:temporary-directory)))

(defun powershell-single-quote (text)
  (cl-ppcre:regex-replace-all
   "'" text "''"))

(defun read-clipboard-image-via-powershell
    (runner temporary-path-provider)
  (let ((temporary
          (funcall temporary-path-provider)))
    (unwind-protect
         (handler-case
             (multiple-value-bind
                   (path-bytes path-ok)
                 (funcall
                  runner
                  (list
                   "wslpath" "-w"
                   (namestring temporary)))
               (unless path-ok
                 (return-from
                     read-clipboard-image-via-powershell
                   nil))
               (let ((windows-path
                       (string-trim
                        '(#\Space #\Tab #\Newline
                          #\Return)
                        (clipboard-command-text
                         path-bytes))))
                 (when
                     (zerop (length windows-path))
                   (return-from
                       read-clipboard-image-via-powershell
                     nil))
                 (let ((script
                         (format
                          nil
                          "~{~A~^; ~}"
                          (list
                           "Add-Type -AssemblyName System.Windows.Forms"
                           "Add-Type -AssemblyName System.Drawing"
                           (format
                            nil "$path = '~A'"
                            (powershell-single-quote
                             windows-path))
                           "$img = [System.Windows.Forms.Clipboard]::GetImage()"
                           "if ($img) { $img.Save($path, [System.Drawing.Imaging.ImageFormat]::Png); Write-Output 'ok' } else { Write-Output 'empty' }"))))
                   (multiple-value-bind
                         (output ok)
                       (funcall
                        runner
                        (list
                         "powershell.exe"
                         "-NoProfile"
                         "-Command"
                         script))
                     (when
                         (and
                          ok
                          (string=
                           "ok"
                           (string-trim
                            '(#\Space #\Tab
                              #\Newline #\Return)
                            (clipboard-command-text
                             output)))
                          (probe-file temporary))
                       (let ((bytes
                               (read-binary-file
                                temporary)))
                         (when
                             (plusp (length bytes))
                           (make-clipboard-image
                            :bytes bytes
                            :mime-type
                            "image/png"))))))))
           (condition () nil))
      (when (probe-file temporary)
        (delete-file temporary)))))

(defun read-clipboard-image
    (&key
       environment
       (platform :linux)
       (command-runner
         #'default-clipboard-image-runner)
       native-image-reader
       (temporary-path-provider
         #'default-clipboard-temporary-path))
  (when
      (clipboard-environment-value
       environment "TERMUX_VERSION")
    (return-from read-clipboard-image nil))
  (if (eq platform :linux)
      (let* ((wayland-p
               (clipboard-wayland-p environment))
             (wsl-p
               (clipboard-wsl-p environment))
             (image
               (and
                (or wayland-p wsl-p)
                (or
                 (read-clipboard-image-via-wl-paste
                  command-runner)
                 (read-clipboard-image-via-xclip
                  command-runner)))))
        (or
         image
         (and
          wsl-p
          (read-clipboard-image-via-powershell
           command-runner
           temporary-path-provider))
         (and
          (not wayland-p)
          (or
           (read-clipboard-image-via-native
            native-image-reader)
           (read-clipboard-image-via-xclip
            command-runner)))))
      (read-clipboard-image-via-native
       native-image-reader)))

(defun read-windows-clipboard-text (&key command-runner)
  ;; pi@4a080252f win32-platform.c clipboard_execute reads
  ;; CF_UNICODETEXT. cadr has no Node addon, so Windows reads the
  ;; same text through PowerShell and writes it with no extra newline.
  (let ((argv
          '("powershell.exe" "-NoProfile" "-Command"
            "[Console]::OutputEncoding = [System.Text.Encoding]::UTF8; $t = Get-Clipboard -Raw; if ($null -ne $t) { [Console]::Out.Write($t) }")))
    (handler-case
        (let ((text
                (if command-runner
                    (funcall command-runner argv)
                    (uiop:run-program
                     argv
                     :output :string
                     :error-output nil
                     :ignore-error-status t))))
          (and (stringp text) text))
      (condition () nil))))

(define-condition clipboard-paste-error (error)
  ((message :initarg :message :reader clipboard-paste-error-message))
  (:report
   (lambda (condition stream)
     (write-string
      (clipboard-paste-error-message condition)
      stream))))

(defun clipboard-condition-message (condition)
  (cond
    ((typep condition 'clipboard-paste-error)
     (clipboard-paste-error-message condition))
    ((typep condition 'simple-condition)
     (apply #'format nil
            (simple-condition-format-control condition)
            (simple-condition-format-arguments condition)))
    (t (princ-to-string condition))))

(defun clipboard-control-character-p (character)
  ;; pi@4a080252f interactive-mode.ts /\p{Cc}/u
  (eq (sb-unicode:general-category character) :cc))

(defun clipboard-js-whitespace-p (character)
  ;; Node /\s/ without the unicode flag. The set is the 25 WhiteSpace
  ;; and LineTerminator code points that paste spacing uses.
  (let ((code (char-code character)))
    (or (member code
                '(9 10 11 12 13 32 160
                  #x1680 #x2028 #x2029 #x202f
                  #x205f #x3000 #xfeff))
        (<= #x2000 code #x200a))))

(defun clipboard-shell-safe-char-p (character)
  ;; pi@4a080252f quoteIfNeeded: ASCII letters, digits, and _-./~:@
  (let ((code (char-code character)))
    (or (<= 48 code 57)
        (<= 65 code 90)
        (<= 97 code 122)
        (find character "_-./~:@" :test #'char=))))

(defun clipboard-quote-if-needed (value)
  (if (and (plusp (length value))
           (every #'clipboard-shell-safe-char-p value))
      value
      (with-output-to-string (output)
        (write-char #\' output)
        (loop for character across value
              do (if (char= character #\')
                     (write-string "'\\''" output)
                     (write-char character output)))
        (write-char #\' output))))

(defun read-clipboard-file-paths (&key native-getter)
  ;; pi@4a080252f clipboard.ts readClipboardFilePaths. An empty list
  ;; is the same as a missing getter: the paste falls through.
  (unless native-getter
    (return-from read-clipboard-file-paths nil))
  (let ((paths (funcall native-getter)))
    (when (and paths (plusp (length paths)))
      (coerce paths 'list))))

(defun clipboard-editor-line (text line)
  (let ((lines
          (uiop:split-string
           (or text "")
           :separator '(#\Newline))))
    (or (nth (or line 0) lines) "")))

(defun clipboard-line-character (line index)
  (and line index
       (>= index 0)
       (< index (length line))
       (char line index)))

(defun clipboard-file-path-insertion
    (paths &key text line column bash-mode-p)
  (let* ((rendered
           (mapcar
            (lambda (path)
              (if bash-mode-p
                  (clipboard-quote-if-needed path)
                  path))
            paths))
         (joined
           (with-output-to-string (output)
             (loop for part in rendered
                   for first-p = t then nil
                   do (unless first-p
                        (write-char
                         (if bash-mode-p #\Space #\Newline)
                         output))
                      (write-string part output))))
         (current
           (clipboard-editor-line text line))
         (before
           (clipboard-line-character
            current (and column (1- column))))
         (after
           (clipboard-line-character current column))
         (leading
           (if (and before
                    (not (clipboard-js-whitespace-p before)))
               " "
               ""))
         (trailing
           (if (and after
                    (not (clipboard-js-whitespace-p after)))
               " "
               "")))
    (concatenate 'string leading joined trailing)))

(defun clipboard-image-extension (mime-type)
  (let ((base (clipboard-base-mime-type (or mime-type ""))))
    (cond
      ((string= base "image/png") "png")
      ((string= base "image/jpeg") "jpg")
      ((string= base "image/webp") "webp")
      ((string= base "image/gif") "gif")
      (t "png"))))

(defun write-clipboard-image-file (image)
  (let ((path
          (namestring
           (merge-pathnames
            (format nil "cadr-clipboard-~A.~A"
                    (cadr-ai:uuid-v7)
                    (clipboard-image-extension
                     (clipboard-image-mime-type image)))
            (uiop:temporary-directory)))))
    (with-open-file
        (stream path
                :direction :output
                :if-exists :supersede
                :if-does-not-exist :create
                :element-type '(unsigned-byte 8))
      (write-sequence (clipboard-image-bytes image) stream))
    path))

(defun handle-clipboard-paste
    (&key file-path-reader image-reader text-reader
          editor-text editor-line editor-column bash-mode-p
          insert show-error)
  ;; pi@4a080252f interactive-mode.ts handleClipboardPaste. File paths
  ;; win over the Finder icon image. A control character or a reader
  ;; error is shown and does not fall through.
  (handler-case
      (let ((paths
              (and file-path-reader
                   (funcall file-path-reader))))
        (cond
          (paths
           (when (some
                  (lambda (path)
                    (some #'clipboard-control-character-p path))
                  paths)
             (error 'clipboard-paste-error
                    :message
                    "Clipboard file path contains control characters"))
           (when insert
             (funcall
              insert
              (clipboard-file-path-insertion
               paths
               :text editor-text
               :line editor-line
               :column editor-column
               :bash-mode-p bash-mode-p))))
          (t
           (let ((image
                   (and image-reader
                        (funcall image-reader))))
             (cond
               (image
                (when insert
                  (funcall
                   insert
                   (write-clipboard-image-file image))))
               (t
                (let ((text
                        (and text-reader
                             (funcall text-reader))))
                  (when (and insert
                             (stringp text)
                             (plusp (length text)))
                    (funcall insert text)))))))))
    (error (condition)
      (when show-error
        (funcall
         show-error
         (format nil "Failed to paste from clipboard: ~A"
                 (clipboard-condition-message condition)))))))
