(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(test goal28-auth-command-error-reaches-existing-print
  (signals cadr-cli::auth-command-error
    (cadr-cli:parse-auth-command
     '("auth" "print-api-key"
       "--min-expiry" "30m")))
  (handler-case
      (cadr-cli:parse-auth-command
       '("auth" "print-api-key"
         "--min-expiry" "30m"))
    (cadr-cli::auth-command-error (condition)
      (is (stringp
           (cadr-cli::auth-command-error-message
            condition)))
      (is (plusp
           (length
            (cadr-cli::auth-command-error-message
             condition)))))))

(test goal28-exit-codes-reach-existing-process-contract
  (is (= 0
         (handler-case
             (error 'cadr-cli::cli-session-abort
                    :status 0)
           (cadr-cli::cli-session-abort (condition)
             (cadr-cli::cli-session-abort-status
              condition)))))
  (is (typep
       (make-condition
        'cadr-ai:configuration-error
        :message "Error: goal28")
       'cadr-ai:cadr-error))
  (let ((agent
          (cadr-agent:make-agent
           :tools nil
           :model nil)))
    (is (= 129
           (cadr-cli::call-with-cli-signal-handlers
            agent
            (lambda ()
              (throw 'cadr-cli::cadr-cli-signal
                     129)))))
    (is (= 0
           (cadr-cli::call-with-cli-signal-handlers
            agent
            (lambda () 0))))
    (is (= 1
           (handler-case
               (progn
                 (error
                  'cadr-ai:configuration-error
                  :message "Error: goal28")
                 0)
             (cadr-ai:cadr-error ()
               1))))))

(test goal27-sighup-and-sigterm-follow-v140
  ;; pi@4a080252 interactive-mode.ts registerSignalHandlers and
  ;; shutdown({fromSignal:true}): a real SIGHUP (except win32) or
  ;; SIGTERM kills detached children, emits session_shutdown before
  ;; terminal cleanup, ignores a second signal, and returns 0.
  ;; print-mode.ts and rpc-mode.ts return 129 and 143 and do not emit
  ;; session_shutdown from this handler.
  (let* ((order nil)
         (host (cadr-agent::make-extension-host))
         (bundle
           (cadr-agent::make-extension-bundle
            :id "gap29-sighup"
            :path "/tmp/gap29-sighup.lisp"))
         (agent
           (cadr-agent:make-agent
            :tools nil
            :model nil
            :extension-host host))
         (detached-pid 2147483646))
    (cadr-agent::call-with-extension-registration
     bundle
     (lambda ()
       (cadr-agent:define-event-hook
        :session-shutdown
        :handler
        (lambda (value context)
          (declare (ignore value context))
          (push :session-shutdown order)
          nil))))
    (cadr-agent::replace-extension-bundles host (list bundle))
    (labels ((raise (signal)
               (sb-posix:kill (sb-posix:getpid) signal)
               (sleep 1))
             (tracked-p ()
               (gethash
                detached-pid
                cadr-cli::*tracked-detached-child-pids*)))
      (unwind-protect
           (progn
             #-win32
             (progn
               (cadr-cli:track-detached-child-pid detached-pid)
               (let ((continued nil))
                 (is (= 0
                        (cadr-cli::call-with-cli-signal-handlers
                         agent
                         (lambda ()
                           (unwind-protect
                                (progn
                                  (raise sb-unix:sighup)
                                  (setf continued t))
                             (push :terminal order)
                             (raise sb-unix:sighup)))
                         :interactive-p t)))
                 (is (null continued))
                 (is (equal order '(:terminal :session-shutdown)))
                 (is (null (tracked-p)))))
             (setf order nil)
             (cadr-cli:track-detached-child-pid detached-pid)
             (is (= 0
                    (cadr-cli::call-with-cli-signal-handlers
                     agent
                     (lambda ()
                       (raise sb-unix:sigterm)
                       :continued)
                     :interactive-p t)))
             (is (equal order '(:session-shutdown)))
             (is (null (tracked-p)))
             (setf order nil)
             #-win32
             (progn
               (cadr-cli:track-detached-child-pid detached-pid)
               (is (= 129
                      (cadr-cli::call-with-cli-signal-handlers
                       agent
                       (lambda ()
                         (raise sb-unix:sighup)
                         0))))
               (is (null order))
               (is (null (tracked-p))))
             (cadr-cli:track-detached-child-pid detached-pid)
             (is (= 143
                    (cadr-cli::call-with-cli-signal-handlers
                     agent
                     (lambda ()
                       (raise sb-unix:sigterm)
                       0))))
             (is (null order))
             (is (null (tracked-p)))
             (is (= 0
                    (cadr-cli::call-with-cli-signal-handlers
                     agent
                     (lambda () 0)
                     :interactive-p t)))
             (is (null order)))
        (cadr-cli:untrack-detached-child-pid detached-pid)))))

(defun goal30-record-show (bucket lock answers)
  (lambda (option)
    (sb-thread:with-mutex (lock)
      (push option (car bucket)))
    (cdr (assoc option answers :test #'string=))))

(test goal30-tmux-keyboard-warning-follows-v140
  ;; v1.4.0 interactive-mode.ts checkTmuxKeyboardSetup. Empty TMUX
  ;; skips the query. Both options are always queried. A missing
  ;; extended-keys answer does not warn. Only "on" and "always" are
  ;; enabled. "xterm" then warns, and the product word is Cadr.
  (let ((bucket (list nil))
        (lock (sb-thread:make-mutex :name "goal30-show")))
    (flet ((warn-for (tmux answers)
             (setf (car bucket) nil)
             (cadr-cli::tmux-keyboard-setup-warning
              :tmux tmux
              :show (goal30-record-show bucket lock answers))))
      (is (null (warn-for nil '(("extended-keys" . "off")))))
      (is (null (car bucket)))
      (is (null (warn-for "" '(("extended-keys" . "off")))))
      (is (null (car bucket)))
      (is (null
           (warn-for "/tmp/tmux,1,0"
                     '(("extended-keys" . "on")
                       ("extended-keys-format" . "csi-u")))))
      (is (null
           (warn-for "/tmp/tmux,1,0"
                     '(("extended-keys" . "always")
                       ("extended-keys-format" . "csi-u")))))
      (is (null
           (warn-for "/tmp/tmux,1,0"
                     '(("extended-keys" . "on")))))
      (is (null
           (warn-for "/tmp/tmux,1,0"
                     '(("extended-keys" . "always")
                       ("extended-keys-format" . "")))))
      (is (string=
           "tmux extended-keys is off. Modified Enter keys may not work. Add `set -g extended-keys on` to ~/.tmux.conf and restart tmux."
           (warn-for "/tmp/tmux,1,0"
                     '(("extended-keys" . "off")
                       ("extended-keys-format" . "xterm")))))
      (is (string=
           "tmux extended-keys is off. Modified Enter keys may not work. Add `set -g extended-keys on` to ~/.tmux.conf and restart tmux."
           (warn-for "/tmp/tmux,1,0"
                     '(("extended-keys" . "")
                       ("extended-keys-format" . "csi-u")))))
      (is (string=
           "tmux extended-keys is off. Modified Enter keys may not work. Add `set -g extended-keys on` to ~/.tmux.conf and restart tmux."
           (warn-for "/tmp/tmux,1,0"
                     '(("extended-keys" . "auto")))))
      (is (string=
           "tmux extended-keys is off. Modified Enter keys may not work. Add `set -g extended-keys on` to ~/.tmux.conf and restart tmux."
           (warn-for "/tmp/tmux,1,0"
                     '(("extended-keys" . "ON")
                       ("extended-keys-format" . "xterm")))))
      (is (null
           (warn-for "/tmp/tmux,1,0"
                     '(("extended-keys-format" . "xterm")))))
      (let ((seen nil))
        (warn-for "/tmp/tmux,1,0" nil)
        (setf seen (copy-list (car bucket)))
        (is (find "extended-keys" seen :test #'string=))
        (is (find "extended-keys-format" seen :test #'string=))
        (is (= 2 (length seen))))
      (is (string=
           "tmux extended-keys-format is xterm. Cadr works best with csi-u. Add `set -g extended-keys-format csi-u` to ~/.tmux.conf and restart tmux."
           (warn-for "/tmp/tmux,1,0"
                     '(("extended-keys" . "on")
                       ("extended-keys-format" . "xterm")))))
      (is (string=
           "tmux extended-keys-format is xterm. Cadr works best with csi-u. Add `set -g extended-keys-format csi-u` to ~/.tmux.conf and restart tmux."
           (warn-for "/tmp/tmux,1,0"
                     '(("extended-keys" . "always")
                       ("extended-keys-format" . "xterm")))))
      (is (null
           (warn-for "/tmp/tmux,1,0"
                     '(("extended-keys" . "on")
                       ("extended-keys-format" . "Xterm"))))))))

(defun goal30-write-executable (directory name body)
  (let ((path (merge-pathnames name directory)))
    (with-open-file (stream path
                            :direction :output
                            :if-exists :supersede
                            :if-does-not-exist :create)
      (write-string body stream))
    (uiop:run-program
     (list "chmod" "755" (namestring path))
     :output nil
     :error-output nil)
    path))

(test goal30-tmux-show-option-matches-v140-process-contract
  ;; v1.4.0 runTmuxShow: argv is tmux show -gv OPTION, stdout is
  ;; trimmed on exit 0, stderr is ignored, and timeout or a failed
  ;; spawn yields nil.
  (let* ((directory
           (merge-pathnames
            (format nil "cadr-gap30-~D/"
                    (random most-positive-fixnum))
            (uiop:temporary-directory)))
         (args-file
           (merge-pathnames "args.txt" directory)))
    (ensure-directories-exist directory)
    (unwind-protect
         (progn
           (goal30-write-executable
            directory "show-ok"
            (format
             nil
             "#!/bin/sh~%printf '%s\\n' \"$@\" > '~A'~%printf 'LEAK\\n' >&2~%printf ' on \\n'~%"
             (namestring args-file)))
           (is (string=
                "on"
                (cadr-cli::tmux-show-option-output
                 "extended-keys"
                 :program
                 (namestring
                  (merge-pathnames "show-ok" directory)))))
           (is (string=
                (format nil "show~%-gv~%extended-keys~%")
                (uiop:read-file-string args-file)))
           (goal30-write-executable
            directory "show-fail"
            "#!/bin/sh
printf 'on\\n'
exit 1
")
           (is (null
                (cadr-cli::tmux-show-option-output
                 "extended-keys"
                 :program
                 (namestring
                  (merge-pathnames "show-fail" directory)))))
           (goal30-write-executable
            directory "show-empty"
            "#!/bin/sh
exit 0
")
           (is (string=
                ""
                (cadr-cli::tmux-show-option-output
                 "extended-keys-format"
                 :program
                 (namestring
                  (merge-pathnames "show-empty" directory)))))
           (goal30-write-executable
            directory "show-multiline"
            "#!/bin/sh
printf 'on\\nextra\\n'
")
           (is (string=
                (format nil "on~%extra")
                (cadr-cli::tmux-show-option-output
                 "extended-keys"
                 :program
                 (namestring
                  (merge-pathnames "show-multiline" directory)))))
           (is (null
                (cadr-cli::tmux-show-option-output
                 "extended-keys"
                 :program
                 (namestring
                  (merge-pathnames
                   "missing-tmux" directory)))))
           (goal30-write-executable
            directory "show-sleep"
            "#!/bin/sh
sleep 30
")
           (let ((now (get-internal-real-time))
                 (sleeps 0))
             (is (null
                  (cadr-cli::tmux-show-option-output
                   "extended-keys"
                   :program
                   (namestring
                    (merge-pathnames "show-sleep" directory))
                   :clock (lambda () now)
                   :sleep
                   (lambda (seconds)
                     (incf sleeps)
                     (incf now
                           (round
                            (* seconds
                               internal-time-units-per-second)))))))
             (is (<= 150 sleeps 250))))
      (uiop:delete-directory-tree
       directory :validate t :if-does-not-exist :ignore))))

(defclass goal30-tmux-warning-terminal
    (cadr-tui::virtual-terminal)
  ((inputs
    :initarg :inputs
    :accessor goal30-tmux-warning-terminal-inputs)))

(defmethod cadr-tui:terminal-read-input
    ((terminal goal30-tmux-warning-terminal))
  (let ((next
          (first
           (goal30-tmux-warning-terminal-inputs
            terminal))))
    (cond
      ((null next) "")
      ((functionp next)
       (let ((value (funcall next terminal)))
         (if value
             (progn
               (pop
                (goal30-tmux-warning-terminal-inputs
                 terminal))
               value)
             "")))
      (t
       (pop
        (goal30-tmux-warning-terminal-inputs
         terminal))))))

(defun goal30-terminal-text (terminal)
  (format
   nil "~{~A~^~%~}"
   (cadr-tui:virtual-terminal-snapshot terminal)))

(test goal30-interactive-startup-shows-the-tmux-warning
  ;; Startup calls the same query as checkTmuxKeyboardSetup and
  ;; showWarning renders Warning: plus the off sentence.
  (let* ((directory
           (merge-pathnames
            (format nil "cadr-gap30-tui-~D/"
                    (random most-positive-fixnum))
            (uiop:temporary-directory)))
         (args-file
           (merge-pathnames "args.txt" directory))
         (old-path (uiop:getenv "PATH"))
         (old-tmux (uiop:getenv "TMUX"))
         (started (get-internal-real-time))
         (terminal
           (make-instance
            'goal30-tmux-warning-terminal
            :columns 120
            :rows 40
            :inputs
            (list
             (lambda (value)
               (cond
                 ((search
                   "Warning: tmux extended-keys is off."
                   (goal30-terminal-text value))
                  (format nil "/quit~C" #\Return))
                 ((> (- (get-internal-real-time) started)
                     (* 5 internal-time-units-per-second))
                  (format nil "/quit~C" #\Return))
                 (t nil)))))))
    (ensure-directories-exist directory)
    (goal30-write-executable
     directory "tmux"
     (format
      nil
      "#!/bin/sh~%printf '%s\\n' \"$@\" >> '~A'~%printf 'LEAK\\n' >&2~%if [ \"$3\" = \"extended-keys\" ]; then printf ' off \\n'; else printf 'csi-u\\n'; fi~%"
      (namestring args-file)))
    (unwind-protect
         (progn
           (setf (uiop:getenv "PATH")
                 (format nil "~A:~A"
                         (namestring directory)
                         (or old-path "")))
           (setf (uiop:getenv "TMUX")
                 "/tmp/tmux-gap30,1,0")
           (cadr-cli::run-tui
            (constantly nil)
            :model "faux"
            :terminal terminal
            :sleep-function (constantly nil))
           (is (search
                "Warning: tmux extended-keys is off. Modified Enter keys may not work."
                (goal30-terminal-text terminal)))
           (is (not
                (search "LEAK"
                        (goal30-terminal-text terminal))))
           (let ((args
                   (format nil "~%~A"
                           (uiop:read-file-string args-file))))
             (is (search (format nil "~%extended-keys~%") args))
             (is (search "extended-keys-format" args))
             (is (search (format nil "~%show~%") args))
             (is (search (format nil "~%-gv~%") args))))
      (if old-path
          (setf (uiop:getenv "PATH") old-path)
          (sb-posix:unsetenv "PATH"))
      (if old-tmux
          (setf (uiop:getenv "TMUX") old-tmux)
          (sb-posix:unsetenv "TMUX"))
      (uiop:delete-directory-tree
       directory :validate t :if-does-not-exist :ignore))))
