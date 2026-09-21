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

(defun default-clipboard-copy-runner (argv input)
  (handler-case
      (let ((stream
              (make-string-input-stream (or input ""))))
        (if (member (first argv)
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
               (not remote-p))
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
      (when (or remote-p
                (and (not copied-p) headless-p))
        (if (emit-clipboard-osc52 text output)
            (setf osc52 t
                  copied-p t)
            (setf oversized-p t))))
    (unless copied-p
      (error
       'cadr-ai:configuration-error
       :message
       (cond
         (oversized-p
          "Clipboard unavailable: text exceeds the OSC 52 size limit")
         ((and (eq platform :linux) termux-p)
          "Clipboard unavailable: install the Termux:API app and `termux-api` package")
         ((and (eq platform :linux) wayland-display-p)
          "Clipboard unavailable: install `wl-clipboard` (`wl-copy`) or check Wayland access")
         ((and (eq platform :linux) x11-display-p)
          "Clipboard unavailable: install `xclip` or `xsel`, or check X11 access")
         (t "Clipboard unavailable"))))
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
               argv
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
