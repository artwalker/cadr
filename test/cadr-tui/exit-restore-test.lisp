(in-package #:cadr-tui/tests)
(in-suite cadr-tui-suite)

(sb-alien:define-alien-routine
    ("grantpt" exit-restore-grantpt)
    sb-alien:int
  (fd sb-alien:int))

(sb-alien:define-alien-routine
    ("unlockpt" exit-restore-unlockpt)
    sb-alien:int
  (fd sb-alien:int))

(sb-alien:define-alien-routine
    ("ptsname" exit-restore-ptsname)
    sb-alien:c-string
  (fd sb-alien:int))

(defun exit-restore-csi (body)
  (format nil "~C[~A" #\Escape body))

(defun count-subsequence (haystack needle)
  (loop for start = 0 then (+ found (length needle))
        for found = (search needle haystack :start2 start)
        while found
        count t))

(defun ends-with-text-p (haystack suffix)
  (and (>= (length haystack) (length suffix))
       (string= haystack suffix
                :start1 (- (length haystack)
                           (length suffix)))))

(defun call-with-pty-input (function)
  (let ((master
          (sb-posix:open
           "/dev/ptmx"
           (logior sb-posix:o-rdwr sb-posix:o-noctty)))
        (slave nil)
        (stream nil))
    (unwind-protect
         (progn
           (unless (zerop (exit-restore-grantpt master))
             (error "grantpt failed"))
           (unless (zerop (exit-restore-unlockpt master))
             (error "unlockpt failed"))
           (setf slave
                 (sb-posix:open
                  (exit-restore-ptsname master)
                  (logior sb-posix:o-rdwr sb-posix:o-noctty)))
           (setf stream
                 (sb-sys:make-fd-stream
                  slave
                  :input t
                  :output nil
                  :element-type 'character
                  :buffering :none
                  :auto-close t
                  :external-format :utf-8))
           (setf slave nil)
           (funcall function stream))
      (when stream
        (close stream :abort t))
      (when slave
        (ignore-errors (sb-posix:close slave)))
      (ignore-errors (sb-posix:close master)))))

(defun call-with-started-alt-screen (function &key (mouse-p t))
  (let ((saved-capabilities
          (cadr-tui:get-terminal-capabilities))
        (saved-kitty (cadr-tui:kitty-protocol-active-p))
        (output (make-string-output-stream)))
    (unwind-protect
         (call-with-pty-input
          (lambda (input)
            (let* ((terminal
                     (cadr-tui:make-process-terminal
                      :input input
                      :output output))
                   (renderer
                     (cadr-tui:make-terminal-renderer
                      terminal
                      :alt-p t
                      :mouse-p mouse-p)))
              (unwind-protect
                   (progn
                     (cadr-tui:renderer-start renderer)
                     (cadr-tui:terminal-start terminal)
                     (funcall function terminal renderer))
                (when (cadr-tui::process-terminal-started-p
                       terminal)
                  (ignore-errors
                    (cadr-tui:renderer-before-stop renderer)
                    (cadr-tui:terminal-stop terminal)
                    (cadr-tui:renderer-after-stop renderer)))
                (cadr-tui::disarm-terminal-exit-restore terminal)
                (setf (cadr-tui::terminal-exit-renderer terminal)
                      nil)))))
      (cadr-tui:set-terminal-capabilities saved-capabilities)
      (cadr-tui:set-kitty-protocol-active saved-kitty))))

(defparameter +v140-exit-without-stop-restore+
  (concatenate
   'string
   (exit-restore-csi "?2026l")
   (format nil "~C[?1006l~C[?1004l~C[?1003l~C[?1002l~C[?1000l"
           #\Escape #\Escape #\Escape #\Escape #\Escape)
   (exit-restore-csi "?7h")
   (exit-restore-csi "?25h")
   (exit-restore-csi "?2004l")
   (exit-restore-csi "<u")
   (exit-restore-csi "?1049l")
   (exit-restore-csi "?25h"))
  "v1.4.0 TuiAltScreen exit restore with mouse, Kitty query pushed,
no modifyOtherKeys, no progress, and color-scheme notifications off.
packages/tui/src/tui.ts getExitRestorePrefix, packages/tui/src/terminal.ts
restoreOnExit, packages/tui/src/tui-alt-screen.ts getExitRestorePrefix
and getExitRestoreSuffix.")

(defun assert-exit-without-stop-output (output)
  (dolist (body '("?1006l" "?1004l" "?1003l" "?1000l"
                  "<u" "?2004l"))
    (is (= 1 (count-subsequence output (exit-restore-csi body)))
        body))
  (is (< (search (exit-restore-csi "<u") output)
         (search (exit-restore-csi "?1049l") output)))
  (is (ends-with-text-p
       output
       (concatenate 'string
                    (exit-restore-csi "?1049l")
                    (exit-restore-csi "?25h"))))
  (is (search +v140-exit-without-stop-restore+ output))
  (is (zerop (count-subsequence
              output
              (exit-restore-csi ">4;0m"))))
  (is (zerop (count-subsequence
              output
              (format nil "~C]9;4;0~C"
                      #\Escape (code-char 7))))))

(test exit-without-stop-restores-terminal-modes
  ;; Locked to packages/tui/test/exit-restore.test.ts
  ;; "restores terminal modes when the process exits without stop()"
  ;; at v1.4.0.
  (let ((output
          (call-with-started-alt-screen
           (lambda (terminal renderer)
             (declare (ignore renderer))
             (is (member terminal cadr-tui::*armed-terminal-exits*))
             (is (member 'cadr-tui::run-terminal-exit-restores
                         sb-ext:*exit-hooks*))
             (cadr-tui::run-terminal-exit-restores)
             (get-output-stream-string
              (cadr-tui::process-terminal-output terminal))))))
    (assert-exit-without-stop-output output)))

(test stop-does-not-restore-terminal-modes-twice
  ;; Locked to packages/tui/test/exit-restore.test.ts
  ;; "does not restore twice after a normal stop()" at v1.4.0.
  (let ((output
          (call-with-started-alt-screen
           (lambda (terminal renderer)
             (cadr-tui:renderer-before-stop renderer)
             (cadr-tui:terminal-stop terminal)
             (cadr-tui:renderer-after-stop renderer)
             (is (null (member terminal
                               cadr-tui::*armed-terminal-exits*)))
             (cadr-tui::run-terminal-exit-restores)
             (get-output-stream-string
              (cadr-tui::process-terminal-output terminal))))))
    (let ((text output))
      (dolist (body '("?1006l" "?1004l" "<u" "?2004l" "?1049l"))
        (is (= 1 (count-subsequence text (exit-restore-csi body)))
            body)))))

(defun exit-restore-only (terminal)
  (cadr-tui::arm-terminal-exit-restore terminal)
  (unwind-protect
       (progn
         (cadr-tui::run-terminal-exit-restores)
         (get-output-stream-string
          (cadr-tui::process-terminal-output terminal)))
    (cadr-tui::disarm-terminal-exit-restore terminal)
    (setf (cadr-tui::terminal-exit-renderer terminal) nil)))

(defun make-exit-restore-terminal ()
  (cadr-tui:make-process-terminal
   :input (make-string-input-stream "")
   :output (make-string-output-stream)))

(test exit-restore-omits-keyboard-pop-until-kitty-is-pushed-or-active
  ;; v1.4.0 restoreOnExit writes ESC[<u only when keyboardProtocolPushed
  ;; or the Kitty protocol is active.
  (let ((idle (make-exit-restore-terminal)))
    (is (string=
         (concatenate 'string
                      (exit-restore-csi "?25h")
                      (exit-restore-csi "?2004l"))
         (exit-restore-only idle))))
  (let ((kitty (make-exit-restore-terminal)))
    (setf (cadr-tui::keyboard-protocol-negotiator-mode
           (cadr-tui::process-terminal-keyboard-negotiator kitty))
          :kitty)
    (is (string=
         (concatenate 'string
                      (exit-restore-csi "?25h")
                      (exit-restore-csi "?2004l")
                      (exit-restore-csi "<u"))
         (exit-restore-only kitty)))))

(test exit-restore-adds-progress-clear-and-modify-other-keys-when-active
  ;; v1.4.0 restoreOnExit appends the progress clear when the progress
  ;; interval is running, and ESC[>4;0m only when modifyOtherKeys is active.
  ;; Order is prefix, progress clear, bracketed-paste off, Kitty pop,
  ;; modifyOtherKeys off, suffix.
  (let ((terminal (make-exit-restore-terminal)))
    (setf (cadr-tui::process-terminal-keyboard-protocol-pushed-p
           terminal)
          t
          (cadr-tui::process-terminal-progress-active-p terminal)
          t
          (cadr-tui::keyboard-protocol-negotiator-mode
           (cadr-tui::process-terminal-keyboard-negotiator terminal))
          :modify-other-keys)
    (cadr-tui:terminal-set-color-scheme-notifications terminal t)
    (is (string=
         (concatenate
          'string
          (exit-restore-csi "?2031l")
          (exit-restore-csi "?25h")
          (format nil "~C]9;4;0~C" #\Escape (code-char 7))
          (exit-restore-csi "?2004l")
          (exit-restore-csi "<u")
          (exit-restore-csi ">4;0m"))
         (exit-restore-only terminal)))))

(test exit-restore-skips-mouse-reset-when-the-alt-screen-has-mouse-off
  ;; v1.4.0 TuiAltScreen.getExitRestorePrefix includes DISABLE_MOUSE
  ;; only when mouse tracking was enabled. The alt screen is still left.
  (let* ((saved (cadr-tui:get-terminal-capabilities))
         (terminal (make-exit-restore-terminal))
         (renderer
           (cadr-tui:make-terminal-renderer
            terminal :alt-p t :mouse-p nil)))
    (unwind-protect
         (progn
           (setf (cadr-tui::process-terminal-keyboard-protocol-pushed-p
                  terminal)
                 t)
           (cadr-tui:renderer-start renderer)
           (let ((text (exit-restore-only terminal)))
             (is (zerop (count-subsequence
                         text
                         (exit-restore-csi "?1006l"))))
             (is (= 1 (count-subsequence
                       text
                       (exit-restore-csi "<u"))))
             (is (ends-with-text-p
                  text
                  (concatenate 'string
                               (exit-restore-csi "?1049l")
                               (exit-restore-csi "?25h"))))))
      (cadr-tui:set-terminal-capabilities saved)
      (setf (cadr-tui::terminal-exit-renderer terminal) nil))))

(test exit-restore-writes-bytes-before-the-caller-flushes
  (multiple-value-bind (read-fd write-fd)
      (sb-posix:pipe)
    (let ((write-stream nil)
          (terminal nil))
      (unwind-protect
           (progn
             (setf write-stream
                   (sb-sys:make-fd-stream
                    write-fd
                    :output t
                    :input nil
                    :element-type 'character
                    :buffering :full
                    :auto-close t
                    :external-format :utf-8))
             (setf write-fd nil)
             (setf terminal
                   (cadr-tui:make-process-terminal
                    :input (make-string-input-stream "")
                    :output write-stream))
             (setf (cadr-tui::process-terminal-keyboard-protocol-pushed-p
                    terminal)
                   t)
             (write-string "PAD" write-stream)
             (cadr-tui::arm-terminal-exit-restore terminal)
             (cadr-tui::run-terminal-exit-restores)
             (let* ((flags (sb-posix:fcntl read-fd sb-posix:f-getfl))
                    (buf (make-array 512
                                     :element-type '(unsigned-byte 8)
                                     :initial-element 0))
                    (n nil))
               (sb-posix:fcntl
                read-fd
                sb-posix:f-setfl
                (logior flags sb-posix:o-nonblock))
               (setf n
                     (handler-case
                         (sb-sys:with-pinned-objects (buf)
                           (sb-posix:read
                            read-fd
                            (sb-sys:vector-sap buf)
                            (length buf)))
                       (sb-posix:syscall-error () 0)))
               (let ((text
                       (if (plusp n)
                           (sb-ext:octets-to-string
                            (subseq buf 0 n))
                           "")))
                 (is (search "PAD" text))
                 (is (search
                      (concatenate 'string
                                   (exit-restore-csi "?25h")
                                   (exit-restore-csi "?2004l")
                                   (exit-restore-csi "<u"))
                      text))
                 (is (< (search "PAD" text)
                        (search (exit-restore-csi "?2004l") text))))))
        (when terminal
          (cadr-tui::disarm-terminal-exit-restore terminal))
        (when write-stream
          (close write-stream :abort t))
        (when write-fd
          (ignore-errors (sb-posix:close write-fd)))
        (ignore-errors (sb-posix:close read-fd))))))

(test exit-restore-swallows-a-dead-terminal
  (let* ((output (make-string-output-stream))
         (terminal
           (cadr-tui:make-process-terminal
            :input (make-string-input-stream "")
            :output output)))
    (close output)
    (cadr-tui::arm-terminal-exit-restore terminal)
    (unwind-protect
         (finishes (cadr-tui::run-terminal-exit-restores))
      (cadr-tui::disarm-terminal-exit-restore terminal))))
