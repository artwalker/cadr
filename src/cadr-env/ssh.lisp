(in-package #:cadr-env)

(defconstant +ssh-timeout-ms+ 60000)
(defconstant +upload-timeout-ms+ 300000)

(defun quote-posix (text)
  (with-output-to-string (out)
    (write-char #\' out)
    (loop for character across text
          do (if (char= character #\')
                 (write-string "'\\''" out)
                 (write-char character out)))
    (write-char #\' out)))

(defun quote-powershell (text)
  (format nil "'~A'" (with-output-to-string (out)
                       (loop for character across text
                             do (if (char= character #\')
                                    (write-string "''" out)
                                    (write-char character out))))))

(defun ssh-program (target)
  (or (getf target :ssh) "ssh"))

(defun run-captured (program args &key input timeout-ms)
  (let* ((process (sb-ext:run-program program args
                                      :wait nil :search t
                                      :input :stream :output :stream :error :stream))
         (stdin (spawn-binary-stream (sb-ext:process-input process) :output))
         (stdout (spawn-binary-stream (sb-ext:process-output process) :input))
         (stderr (spawn-binary-stream (sb-ext:process-error process) :input))
         (out (make-array 0 :element-type '(unsigned-byte 8) :adjustable t :fill-pointer 0))
         (err (make-array 0 :element-type '(unsigned-byte 8) :adjustable t :fill-pointer 0))
         (timed-out nil))
    (flet ((slurp (stream into)
             (let ((chunk (make-array 8192 :element-type '(unsigned-byte 8))))
               (loop for count = (handler-case (read-available stream chunk) (error () 0))
                     while (plusp count)
                     do (loop for index below count
                              do (vector-push-extend (aref chunk index) into))))))
      (let ((out-thread (sb-thread:make-thread (lambda () (slurp stdout out)) :name "ssh-stdout"))
            (err-thread (sb-thread:make-thread (lambda () (slurp stderr err)) :name "ssh-stderr")))
        (unwind-protect
             (progn
               (when input
                 (write-sequence input stdin)
                 (finish-output stdin))
               (ignore-errors (close stdin)))
               (let ((deadline (and timeout-ms
                                    (+ (get-internal-real-time)
                                       (round (* timeout-ms
                                                 (/ internal-time-units-per-second 1000)))))))
                 (loop while (sb-ext:process-alive-p process)
                       do (when (and deadline (> (get-internal-real-time) deadline))
                            (setf timed-out t)
                            (ignore-errors (sb-ext:process-kill process 9))
                            (return))
                          (sleep 0.05)))
               (sb-ext:process-wait process))
          (ignore-errors (close stdin))
          (cadr-core:join-active-thread out-thread :reason "ssh stdout")
          (cadr-core:join-active-thread err-thread :reason "ssh stderr")
          (ignore-errors (close stdout))
          (ignore-errors (close stderr))))
    (values out err (if timed-out nil (sb-ext:process-exit-code process)) timed-out)))

(defun run-ssh (target command &key input args (timeout-ms +ssh-timeout-ms+))
  (let* ((program (ssh-program target))
         (argv (append (or args (ssh-arguments target)) (list command))))
    (handler-case
        (multiple-value-bind (stdout stderr code timed-out)
            (run-captured program argv :input input :timeout-ms timeout-ms)
          (let ((output (utf8-string stdout))
                (diagnostics (utf8-string stderr)))
            (cond
              (timed-out
               (error 'ssh-error
                      :exit-code nil
                      :stderr diagnostics
                      :message (format nil "ssh ~A did not finish within ~A s: ~A"
                                       (getf target :host)
                                       (floor timeout-ms 1000)
                                       (string-trim '(#\Space #\Newline #\Return #\Tab) diagnostics))))
              ((eql code 0) output)
              ((search "REMOTE HOST IDENTIFICATION HAS CHANGED" diagnostics)
               (error 'host-key-changed-error
                      :message (format nil "The host key of ~A changed; remove the old key to continue"
                                       (getf target :host))))
              ((or (search "Host key verification failed" diagnostics)
                   (and (search "No " diagnostics) (search " host key is known" diagnostics)))
               (error 'host-key-unknown-error
                      :message (format nil "The host key of ~A is not trusted yet" (getf target :host))))
              (t
               (error 'ssh-error
                      :exit-code code
                      :stderr diagnostics
                      :message (format nil "ssh ~A failed with exit code ~A: ~A"
                                       (getf target :host) code
                                       (string-trim '(#\Space #\Newline #\Return #\Tab) diagnostics)))))))
      (ssh-error (condition) (error condition))
      (host-key-error (condition) (error condition))
      (error (condition)
        (error 'ssh-error :exit-code nil :stderr "" :message (princ-to-string condition))))))

(defun scan-host-key (target)
  (let* ((directory (temp-dir (wire-literal :hostkey-temp)))
         (scanned (concatenate 'string directory "/known_hosts")))
    (unwind-protect
         (progn
           (handler-case
               (run-ssh target "exit 0"
                        :args (ssh-arguments target :strict nil :known-hosts scanned))
             (ssh-error ())
             (host-key-unknown-error ()))
           (let ((lines (known-host-lines scanned)))
             (unless lines
               (error "No host key received from ~A" (getf target :host)))
             (multiple-value-bind (stdout stderr code)
                 (run-captured "ssh-keygen" (list "-lf" scanned))
               (declare (ignore stderr))
               (unless (eql code 0)
                 (error "ssh-keygen failed for ~A" scanned))
               (list :lines lines
                     :fingerprints (loop for line in (split-lines (string-trim '(#\Newline) (utf8-string stdout)))
                                         unless (equal (string-trim '(#\Space) line) "")
                                           collect line)))))
      (ignore-errors
        (uiop:delete-directory-tree (uiop:ensure-directory-pathname directory)
                                    :validate t)))))

(defun split-lines (text)
  (loop for start = 0 then (1+ end)
        for end = (position #\Newline text :start start)
        collect (subseq text start (or end (length text)))
        while end))

(defparameter +posix-probe+
  "sh -c 'echo PI-ENV-PROBE; uname -s; uname -m; uname -o 2>/dev/null || echo -; printf \"%s\\n\" \"$HOME\" \"${TMPDIR:--}\" \"${LD_PRELOAD:--}\"'")

(defun parse-probe (target output)
  (let* ((lines (split-lines output))
         (start (position (probe-banner) lines :test #'equal)))
    (unless start
      (error "Unexpected answer from ~A: ~A" (getf target :host)
             (string-trim '(#\Space #\Newline #\Return #\Tab) output)))
    (let ((rest (nthcdr (1+ start) lines)))
      (list :system (or (first rest) "")
            :machine (or (second rest) "")
            :os (or (third rest) "")
            :home (or (fourth rest) "")
            :tmpdir (or (fifth rest) "-")
            :preload (or (sixth rest) "-")))))

(defun normalize-arch (machine)
  (let ((lower (string-downcase machine)))
    (cond
      ((or (equal lower "x86_64") (equal lower "amd64") (equal lower "x64")) "x64")
      ((or (equal lower "aarch64") (equal lower "arm64")) "arm64")
      (t (error "Unsupported remote architecture: ~A" machine)))))

(defun termux-warnings (probe)
  (let ((warnings nil))
    (when (equal (getf probe :tmpdir) "-")
      (push "TMPDIR is not set; Termux's sshd normally sets it to $PREFIX/tmp." warnings))
    (unless (search "termux-exec" (getf probe :preload))
      (push "termux-exec is not loaded (LD_PRELOAD); scripts with #!/usr/bin/env shebangs will fail."
            warnings))
    (push "Android may suspend Termux; run termux-wake-lock on the device to keep the connection alive."
          warnings)
    (nreverse warnings)))

(defun detect-platform (target)
  (let ((probe (handler-case
                   (parse-probe target (run-ssh target +posix-probe+))
                 (host-key-error (condition) (error condition))
                 (error ()
                   (parse-probe target (run-ssh target (windows-probe)))))))
    (when (or (and (>= (length (getf probe :system)) 5)
                   (string= (getf probe :system) "MINGW" :end1 5))
              (and (>= (length (getf probe :system)) 4)
                   (string= (getf probe :system) "MSYS" :end1 4))
              (and (>= (length (getf probe :system)) 6)
                   (string= (getf probe :system) "CYGWIN" :end1 6)))
      (setf probe (parse-probe target (run-ssh target (windows-probe)))))
    (let ((arch (normalize-arch (getf probe :machine)))
          (system (getf probe :system))
          (home (getf probe :home)))
      (cond
        ((equal system "Windows")
         (list :platform "windows" :arch arch :home home
               :shell (if (search "Windows_NT" (run-ssh target "echo %OS%")) "cmd" "powershell")
               :warnings nil))
        ((equal system "Darwin")
         (list :platform "darwin" :arch arch :home home :warnings nil))
        ((equal system "Linux")
         (let ((android (equal (getf probe :os) "Android")))
           (list :platform (if android "android" "linux")
                 :arch arch :home home
                 :warnings (if android (termux-warnings probe) nil))))
        (t (error "Unsupported remote system: ~A" system))))))

(defun windows-probe ()
  "powershell -NoProfile -NonInteractive -EncodedCommand ")

(defun last-line (text)
  (let ((trimmed (string-trim '(#\Space #\Newline #\Return #\Tab) text)))
    (if (equal trimmed "")
        "missing"
        (car (last (split-lines trimmed))))))

(defun check-daemon (target remote file sha256)
  (if (equal (getf remote :platform) "windows")
      (error "Windows SSH deployment needs a Windows sshd; this host only runs the POSIX path")
      (last-line
       (run-ssh target
                (format nil "sh -c ~A"
                        (quote-posix
                         (format nil "~A; f=~A; if [ -f \"$f\" ] && [ \"$(hash \"$f\")\" = ~A ]; then echo present; elif [ \"$(hash /dev/null)\" = none ]; then echo nohash; else echo missing; fi"
                                 (posix-hash-program) (quote-posix file) sha256)))))))

(defun posix-upload-script (file sha256)
  (format nil "set -e
~A
f=~A
d=$(dirname \"$f\")
mkdir -p \"$d\"
chmod 700 \"$d\"
t=$(mktemp \"$d/.pi-env.XXXXXX\")
cat > \"$t\"
if [ \"$(hash \"$t\")\" != ~A ]; then rm -f \"$t\"; echo \"pi-env upload is corrupt\" >&2; exit 1; fi
chmod 700 \"$t\"
mv -f \"$t\" \"$f\"
for old in \"$d\"/pi-env-*; do [ \"$old\" = \"$f\" ] || rm -f \"$old\"; done
echo deployed"
          (posix-hash-program) (quote-posix file) sha256))

(defun deploy-daemon (target remote binary)
  (unless (and (stringp binary) (probe-file binary))
    (error "No pi-env daemon for ~A-~A at ~A"
           (getf remote :platform) (getf remote :arch) binary))
  (let* ((sha256 (sha256-hex-file (namestring (probe-file binary))))
         (file (deploy-daemon-path (getf remote :home) sha256
                                   :platform (getf remote :platform)))
         (state (check-daemon target remote file sha256)))
    (cond
      ((equal state "present") file)
      ((equal state "nohash")
       (error "~A has no sha256sum, shasum or openssl to verify pi-env" (getf target :host)))
      (t
       (let ((bytes (read-binary-file binary)))
         (run-ssh target
                  (format nil "sh -c ~A" (quote-posix (posix-upload-script file sha256)))
                  :input bytes
                  :timeout-ms +upload-timeout-ms+))
       file))))

(defun read-binary-file (path)
  (with-open-file (stream path :element-type '(unsigned-byte 8))
    (let ((bytes (make-array (file-length stream) :element-type '(unsigned-byte 8))))
      (read-sequence bytes stream)
      bytes)))

(defun launch-command (remote file login-shell)
  (cond
    ((equal (getf remote :platform) "windows")
     (if (equal (getf remote :shell) "powershell")
         (format nil "& ~A" (quote-powershell file))
         (if (find #\Space file) (format nil "\"~A\"" file) file)))
    (login-shell
     (format nil "exec \"$SHELL\" -lc 'exec \"$0\" \"$@\"' ~A" (quote-posix file)))
    (t (quote-posix file))))

(defun ssh-launch-argv (target state &key binary login-shell on-log)
  (unless (getf state :remote)
    (let ((remote (detect-platform target)))
      (dolist (warning (getf remote :warnings))
        (when on-log (funcall on-log (concatenate 'string warning (string #\Newline)))))
      (setf (getf state :remote) remote)))
  (let ((file (or (getf state :verified)
                  (deploy-daemon target (getf state :remote) binary))))
    (setf (getf state :verified) nil)
    (append (list (ssh-program target))
            (ssh-arguments target)
            (list (launch-command (getf state :remote) file login-shell)))))

(defun connect-ssh (target &key binary login-shell on-log)
  (let* ((remote (detect-platform target))
         (verified (deploy-daemon target remote binary)))
    (dolist (warning (getf remote :warnings))
      (when on-log (funcall on-log (concatenate 'string warning (string #\Newline)))))
    (values (make-spawn-connection
             :on-log on-log
             :command (let ((state (list :remote remote :verified verified)))
                        (lambda ()
                          (ssh-launch-argv target state :binary binary
                                           :login-shell login-shell :on-log on-log))))
            remote)))

(defun ssh-connection (target &key binary login-shell on-log)
  (let ((state (list :remote nil :verified nil)))
    (values (make-spawn-connection
             :on-log on-log
             :command (lambda ()
                        (ssh-launch-argv target state :binary binary
                                         :login-shell login-shell :on-log on-log)))
            (lambda () (getf state :remote)))))

(defun temp-dir (prefix)
  (json-get (op-mkdtemp (json-object "prefix" (concatenate 'string "/tmp/" prefix))) "path"))
