(in-package #:cadr-tui)

(defparameter +keyboard-protocol-query+
  (format nil "~C[>7u~C[?u~C[c"
          #\Escape #\Escape #\Escape))

(defparameter +keyboard-protocol-query-without-da+
  (format nil "~C[>7u~C[?u"
          #\Escape #\Escape))

(defparameter +device-attributes-query+
  (format nil "~C[c" #\Escape))

(defparameter +modify-other-keys-enable+
  (format nil "~C[>4;2m" #\Escape))

(defparameter +modify-other-keys-disable+
  (format nil "~C[>4;0m" #\Escape))

(defparameter +terminal-progress-active-sequence+
  (format nil "~C]9;4;3~C" #\Escape (code-char 7)))

(defparameter +terminal-progress-clear-sequence+
  (format nil "~C]9;4;0~C" #\Escape (code-char 7)))

(defconstant +terminal-progress-keepalive-seconds+ 1.0d0)

(defun terminal-monotonic-seconds ()
  (/ (get-internal-real-time)
     (coerce internal-time-units-per-second
             'double-float)))

(defstruct (keyboard-protocol-negotiator
            (:constructor make-keyboard-protocol-negotiator
                ()))
  (buffer "" :type string)
  (mode :negotiating))

(defun keyboard-protocol-query ()
  +keyboard-protocol-query+)

(defun keyboard-protocol-mode (negotiator)
  (keyboard-protocol-negotiator-mode
   negotiator))

(defparameter +kitty-protocol-reply-scanner+
  (cl-ppcre:create-scanner
   (format nil "^~C\\[\\?(\\d+)u$" #\Escape)))

(defparameter +device-attributes-reply-scanner+
  (cl-ppcre:create-scanner
   (format nil "^~C\\[\\?[\\d;]*c$" #\Escape)))

(defun parse-keyboard-protocol-sequence (sequence)
  (multiple-value-bind
        (start end starts ends)
      (cl-ppcre:scan
       +kitty-protocol-reply-scanner+
       sequence)
    (declare (ignore end))
    (when start
      (return-from parse-keyboard-protocol-sequence
        (list
         :kitty
         (parse-integer
          (subseq
           sequence
           (aref starts 0)
           (aref ends 0)))))))
  (when
      (cl-ppcre:scan
       +device-attributes-reply-scanner+
       sequence)
    (list :device-attributes)))

(defun keyboard-protocol-prefix-p (sequence)
  (or
   (string= sequence
            (format nil "~C[" #\Escape))
   (not
    (null
     (cl-ppcre:scan
      (format nil "^~C\\[\\?[\\d;]*$"
              #\Escape)
      sequence)))))

(defun keyboard-protocol-handle-sequence
    (negotiator parsed)
  (case (first parsed)
    (:kitty
     (if (zerop (second parsed))
         (progn
           (setf
            (keyboard-protocol-negotiator-mode
             negotiator)
            :modify-other-keys)
           (values nil
                   (list
                    +modify-other-keys-enable+)))
         (progn
           (setf
            (keyboard-protocol-negotiator-mode
             negotiator)
            :kitty)
           (set-kitty-protocol-active t)
           (values nil nil))))
    (:device-attributes
     (if (eq :kitty
             (keyboard-protocol-negotiator-mode
              negotiator))
         (values nil nil)
         (progn
           (setf
            (keyboard-protocol-negotiator-mode
             negotiator)
            :modify-other-keys)
           (values nil
                   (list
                    +modify-other-keys-enable+)))))
    (otherwise (values nil nil))))

(defun keyboard-protocol-consume
    (negotiator sequence)
  (let* ((pending
           (keyboard-protocol-negotiator-buffer
            negotiator))
         (combined
           (if (plusp (length pending))
               (concatenate 'string pending sequence)
               sequence))
         (parsed
           (parse-keyboard-protocol-sequence
            combined)))
    (cond
      (parsed
       (setf
        (keyboard-protocol-negotiator-buffer
         negotiator)
        "")
       (keyboard-protocol-handle-sequence
        negotiator parsed))
      ((keyboard-protocol-prefix-p combined)
       (setf
        (keyboard-protocol-negotiator-buffer
         negotiator)
        combined)
       (values nil nil))
      ((plusp (length pending))
       (setf
        (keyboard-protocol-negotiator-buffer
         negotiator)
        "")
       (values
        (remove ""
                (list pending sequence)
                :test #'string=)
        nil))
      (t
       (values (list sequence) nil)))))

(defun keyboard-protocol-flush (negotiator)
  (let ((pending
          (keyboard-protocol-negotiator-buffer
           negotiator)))
    (setf
     (keyboard-protocol-negotiator-buffer
      negotiator)
     "")
    (unless (zerop (length pending))
      (list pending))))

(defun normalize-apple-terminal-input
    (data apple-terminal-p shift-pressed-p)
  (if (and apple-terminal-p
           shift-pressed-p
           (string= data (string #\Return)))
      (format nil "~C[13;2u" #\Escape)
      data))

(defun apple-terminal-session-with-environment-p
    (macos-p environment-function)
  (and macos-p
       (string=
        "Apple_Terminal"
        (or (funcall environment-function "TERM_PROGRAM")
            ""))))

(defun apple-terminal-session-p ()
  (apple-terminal-session-with-environment-p
   (uiop:os-macosx-p)
   #'uiop:getenv))

(defun positive-environment-integer
    (name environment-function)
  (let ((value (funcall environment-function name)))
    (when value
      (let ((parsed
              (parse-integer value
                             :junk-allowed t)))
        (and parsed (> parsed 0) parsed)))))

(defun terminal-dimensions
    (columns rows
     &key (environment-function #'uiop:getenv))
  (values
   (or (and columns (> columns 0) columns)
       (positive-environment-integer
        "COLUMNS" environment-function)
       80)
   (or (and rows (> rows 0) rows)
       (positive-environment-integer
        "LINES" environment-function)
       24)))

#+(and sbcl linux)
(sb-alien:define-alien-type cadr-winsize
  (sb-alien:struct cadr-winsize
    (rows sb-alien:unsigned-short)
    (columns sb-alien:unsigned-short)
    (x-pixels sb-alien:unsigned-short)
    (y-pixels sb-alien:unsigned-short)))

#+(and sbcl linux)
(sb-alien:define-alien-routine
    ("ioctl" %ioctl-winsize)
    sb-alien:int
  (fd sb-alien:int)
  (request sb-alien:unsigned-long)
  (size (* (sb-alien:struct cadr-winsize))))

;; pi@4a080252f packages/tui/native/win32/src/win32-platform.c
;; enable_virtual_terminal_input. STD_INPUT_HANDLE is (DWORD)-10.
(defparameter +std-input-handle+ #xfffffff6)
(defparameter +enable-virtual-terminal-input+ #x0200)

(defun console-mode-with-virtual-terminal-input (mode)
  (logior mode +enable-virtual-terminal-input+))

#+(and sbcl win32)
(sb-alien:define-alien-routine
    ("GetStdHandle" %cadr-get-std-handle :convention :stdcall)
    sb-alien:system-area-pointer
  (std-handle sb-alien:unsigned-int))

#+(and sbcl win32)
(sb-alien:define-alien-routine
    ("GetConsoleMode" %cadr-get-console-mode :convention :stdcall)
    sb-alien:int
  (handle sb-alien:system-area-pointer)
  (mode (* sb-alien:unsigned-int)))

#+(and sbcl win32)
(sb-alien:define-alien-routine
    ("SetConsoleMode" %cadr-set-console-mode :convention :stdcall)
    sb-alien:int
  (handle sb-alien:system-area-pointer)
  (mode sb-alien:unsigned-int))

(defun windows-invalid-handle-p (handle)
  #+(and sbcl win32)
  (= (sb-sys:sap-int (sb-alien:alien-sap handle)) -1)
  #-(and sbcl win32)
  (declare (ignore handle))
  #-(and sbcl win32)
  t)

(defun read-windows-stdin-console-mode ()
  #+(and sbcl win32)
  (let ((handle (%cadr-get-std-handle +std-input-handle+)))
    (if (windows-invalid-handle-p handle)
        (values nil nil)
        (sb-alien:with-alien ((mode sb-alien:unsigned-int 0))
          (if (zerop
               (%cadr-get-console-mode
                handle (sb-alien:addr mode)))
              (values nil nil)
              (values mode t)))))
  #-(and sbcl win32)
  (values nil nil))

(defun write-windows-stdin-console-mode (mode)
  #+(and sbcl win32)
  (let ((handle (%cadr-get-std-handle +std-input-handle+)))
    (unless (windows-invalid-handle-p handle)
      (not (zerop (%cadr-set-console-mode handle mode)))))
  #-(and sbcl win32)
  (declare (ignore mode))
  #-(and sbcl win32)
  nil)

(defun apply-windows-virtual-terminal-input
    (windows-p read-mode write-mode)
  ;; Non-Windows returns without touching the console. A missing
  ;; helper or a failed Get/SetConsoleMode is silent: Shift+Tab then
  ;; arrives as Tab. pi@4a080252f terminal.ts enableWindowsVTInput.
  (when windows-p
    (handler-case
        (multiple-value-bind (mode ok) (funcall read-mode)
          (when (and ok (integerp mode) (not (minusp mode)))
            (funcall
             write-mode
             (console-mode-with-virtual-terminal-input mode))
            t))
      (condition () nil))))

(defun enable-windows-virtual-terminal-input ()
  (apply-windows-virtual-terminal-input
   (uiop:os-windows-p)
   #'read-windows-stdin-console-mode
   #'write-windows-stdin-console-mode))

(defclass process-terminal (terminal)
  ((input
    :initarg :input
    :accessor process-terminal-input)
   (output
    :initarg :output
    :accessor process-terminal-output)
   (input-fd
    :initform nil
    :accessor process-terminal-input-fd)
   (saved-termios
    :initform nil
    :accessor process-terminal-saved-termios)
   (started-p
    :initform nil
    :accessor process-terminal-started-p)
   (keyboard-protocol-pushed-p
    :initform nil
    :accessor process-terminal-keyboard-protocol-pushed-p)
   (keyboard-negotiator
    :initform
    (make-keyboard-protocol-negotiator)
    :accessor
    process-terminal-keyboard-negotiator)
   (keyboard-prefix-time
    :initform nil
    :accessor process-terminal-keyboard-prefix-time)
   (stdin-buffer
    :initform (make-stdin-buffer
               :escape-timeout-milliseconds
               (resolve-escape-timeout-milliseconds))
    :accessor process-terminal-stdin-buffer)
   (stdin-prefix-time
    :initform nil
    :accessor process-terminal-stdin-prefix-time)
   (pending-input
    :initform nil
    :accessor process-terminal-pending-input)
   (response-filter
    :initform
    (make-terminal-response-filter)
    :accessor process-terminal-response-filter)
   (background-response
    :initform nil
    :accessor process-terminal-background-response)
   (color-scheme-response
    :initform nil
    :accessor process-terminal-color-scheme-response)
   (color-scheme-notifications-enabled-p
    :initform nil
    :accessor
    process-terminal-color-scheme-notifications-enabled-p)
   (progress-active-p
    :initform nil
    :accessor process-terminal-progress-active-p)
   (progress-next-keepalive-at
    :initform nil
    :accessor process-terminal-progress-next-keepalive-at)
   (progress-clock-function
    :initarg :progress-clock-function
    :initform #'terminal-monotonic-seconds
    :accessor process-terminal-progress-clock-function)
   (program-status
    :initform nil
    :accessor process-terminal-program-status)
   (program-status-supported-p
    :initform nil
    :accessor process-terminal-program-status-supported-p)
   (program-status-query-pending-p
    :initform nil
    :accessor process-terminal-program-status-query-pending-p)
   (apple-terminal-function
    :initarg :apple-terminal-function
    :initform #'apple-terminal-session-p
    :reader process-terminal-apple-terminal-function)
   (native-modifier-function
    :initarg :native-modifier-function
    :initform #'is-native-modifier-pressed
    :reader process-terminal-native-modifier-function)
   (windows-vt-input-function
    :initarg :windows-vt-input-function
    :initform #'enable-windows-virtual-terminal-input
    :reader process-terminal-windows-vt-input-function)
   (resize-p
    :initform nil
    :accessor process-terminal-resize-p)))

(defun program-status-env-override ()
  ;; PI_PROGRAM_STATUS matches the baseline env contract (enumerate
  ;; environmentVariables). 1 forces reports; 0 disables; unset queries.
  (uiop:getenv "PI_PROGRAM_STATUS"))

(defun configure-program-status-support (terminal)
  (let ((override (program-status-env-override)))
    (setf
     (process-terminal-program-status-supported-p terminal)
     (string= override "1")
     (process-terminal-program-status-query-pending-p terminal)
     (and (not (string= override "1"))
          (not (string= override "0"))))
    (process-terminal-program-status-query-pending-p
     terminal)))

(defun write-stored-program-status (terminal)
  (when
      (and
       (process-terminal-program-status-supported-p
        terminal)
       (process-terminal-program-status terminal))
    (terminal-write
     terminal
     (format-program-status
      (process-terminal-program-status terminal)))))

(defun make-process-terminal
    (&key
       (input *standard-input*)
       (output *standard-output*)
       (progress-clock-function
         #'terminal-monotonic-seconds)
       (apple-terminal-function
         #'apple-terminal-session-p)
       (native-modifier-function
         #'is-native-modifier-pressed)
       (windows-vt-input-function
         #'enable-windows-virtual-terminal-input))
  (multiple-value-bind (columns rows)
      (terminal-dimensions nil nil)
    (make-instance
     'process-terminal
     :input input
     :output output
     :progress-clock-function progress-clock-function
     :apple-terminal-function apple-terminal-function
     :native-modifier-function native-modifier-function
     :windows-vt-input-function windows-vt-input-function
     :columns columns
     :rows rows)))

#+sbcl
(defun underlying-stream (stream direction)
  (loop
    (typecase stream
      (synonym-stream
       (setf stream
             (symbol-value
              (synonym-stream-symbol stream))))
      (two-way-stream
       (setf stream
             (if (eq direction :input)
                 (two-way-stream-input-stream stream)
                 (two-way-stream-output-stream stream))))
      (t (return stream)))))

#+sbcl
(defun stream-file-descriptor (stream direction)
  (let ((resolved (underlying-stream stream direction)))
    (when (typep resolved 'sb-sys:fd-stream)
      (sb-sys:fd-stream-fd resolved))))

(defun terminal-stream-p (stream &optional (direction :input))
  #+sbcl
  (let ((fd
          (stream-file-descriptor stream direction)))
    (and fd
         (handler-case
             (progn
               (sb-posix:tcgetattr fd)
               t)
           (condition () nil))))
  #-sbcl
  (declare (ignore stream direction))
  #-sbcl
  nil)

#+(and sbcl linux)
(defun read-terminal-size (fd)
  (sb-alien:with-alien
      ((size (sb-alien:struct cadr-winsize)))
    (if (minusp
         (%ioctl-winsize fd #x5413
                         (sb-alien:addr size)))
        (values nil nil)
        (values
         (sb-alien:slot size 'columns)
         (sb-alien:slot size 'rows)))))

#-(and sbcl linux)
(defun read-terminal-size (fd)
  (declare (ignore fd))
  (values nil nil))

(defun refresh-terminal-size (terminal)
  (multiple-value-bind (columns rows)
      (read-terminal-size
       (process-terminal-input-fd terminal))
    (when (and columns (> columns 0))
      (setf (terminal-columns terminal) columns))
    (when (and rows (> rows 0))
      (setf (terminal-rows terminal) rows)))
  terminal)

#+sbcl
(defun raw-termios (original)
  (let ((raw
          (make-instance
           'sb-posix:termios
           :iflag
           (sb-posix:termios-iflag original)
           :oflag
           (sb-posix:termios-oflag original)
           :cflag
           (sb-posix:termios-cflag original)
           :lflag
           (sb-posix:termios-lflag original)
           :cc
           (copy-seq
            (sb-posix:termios-cc original)))))
    (setf
     (sb-posix:termios-iflag raw)
     (logandc2
      (sb-posix:termios-iflag raw)
      (logior
       sb-posix:brkint
       sb-posix:icrnl
       sb-posix:inpck
       sb-posix:istrip
       sb-posix:ixon))
     (sb-posix:termios-oflag raw)
     (logandc2
      (sb-posix:termios-oflag raw)
      sb-posix:opost)
     (sb-posix:termios-cflag raw)
     (logior
      (logandc2
       (sb-posix:termios-cflag raw)
       (logior sb-posix:csize
               sb-posix:parenb))
      sb-posix:cs8)
     (sb-posix:termios-lflag raw)
     (logandc2
      (sb-posix:termios-lflag raw)
      (logior
       sb-posix:echo
       sb-posix:echonl
       sb-posix:icanon
       sb-posix:isig
       sb-posix:iexten)))
    (setf
     (aref (sb-posix:termios-cc raw)
           sb-posix:vmin)
     0
     (aref (sb-posix:termios-cc raw)
           sb-posix:vtime)
     1)
    raw))

(defvar *armed-terminal-exits* nil)

(defun ensure-terminal-exit-hook ()
  (unless (member 'run-terminal-exit-restores
                  sb-ext:*exit-hooks*)
    (push 'run-terminal-exit-restores sb-ext:*exit-hooks*)))

(defun disarm-terminal-exit-restore (terminal)
  (setf *armed-terminal-exits*
        (remove terminal *armed-terminal-exits* :test #'eq))
  terminal)

(defun arm-terminal-exit-restore (terminal)
  (disarm-terminal-exit-restore terminal)
  (push terminal *armed-terminal-exits*)
  (ensure-terminal-exit-hook)
  terminal)

(defun terminal-exit-restore-base-prefix (terminal)
  (format nil "~A~C[?25h"
          (if (process-terminal-color-scheme-notifications-enabled-p
               terminal)
              (format nil "~C[?2031l" #\Escape)
              "")
          #\Escape))

(defun terminal-exit-restore-prefix (terminal)
  (let ((renderer (terminal-exit-renderer terminal))
        (base (terminal-exit-restore-base-prefix terminal)))
    (if (and renderer
             (terminal-renderer-alt-screen-p renderer)
             (terminal-renderer-alt-screen-active-p renderer))
        (concatenate
         'string
         +synchronized-update-end+
         (if (terminal-renderer-mouse-p renderer)
             +mouse-disable+
             "")
         +autowrap-enable+
         base)
        base)))

(defun terminal-exit-restore-suffix (terminal)
  ;; Kitty keyboard flags are per screen, so the pop is written
  ;; before the alternate screen is left.
  (let ((renderer (terminal-exit-renderer terminal)))
    (if (and renderer
             (terminal-renderer-alt-screen-p renderer)
             (terminal-renderer-alt-screen-active-p renderer))
        (concatenate 'string
                     +alt-screen-exit+
                     (format nil "~C[?25h" #\Escape))
        "")))

(defun terminal-exit-pop-keyboard-p (terminal)
  (or (process-terminal-keyboard-protocol-pushed-p terminal)
      (eq :kitty
          (keyboard-protocol-negotiator-mode
           (process-terminal-keyboard-negotiator terminal)))))

(defun terminal-exit-disable-modify-other-keys-p (terminal)
  (eq :modify-other-keys
      (keyboard-protocol-negotiator-mode
       (process-terminal-keyboard-negotiator terminal))))

(defun process-terminal-exit-restore-sequence
    (terminal before after)
  (concatenate
   'string
   before
   (if (process-terminal-progress-active-p terminal)
       +terminal-progress-clear-sequence+
       "")
   (format nil "~C[?2004l" #\Escape)
   (if (terminal-exit-pop-keyboard-p terminal)
       (format nil "~C[<u" #\Escape)
       "")
   (if (terminal-exit-disable-modify-other-keys-p terminal)
       +modify-other-keys-disable+
       "")
   after))

(defun write-octets-to-fd (fd octets)
  (let ((total (length octets)))
    (sb-sys:with-pinned-objects (octets)
      (let ((base (sb-sys:vector-sap octets))
            (offset 0))
        (loop
          (unless (< offset total)
            (return))
          (let ((wrote
                  (sb-posix:write
                   fd
                   (sb-sys:sap+ base offset)
                   (- total offset))))
            (when (zerop wrote)
              (return))
            (incf offset wrote)))))))

(defun write-terminal-exit-bytes (terminal sequence)
  ;; A buffered stream write can still be sitting in the Lisp buffer
  ;; when the exit hook runs. Flush that first, then write the reset
  ;; itself with write(2) so it reaches the terminal before the process
  ;; is gone.
  (let ((output (process-terminal-output terminal)))
    (handler-case
        (finish-output output)
      (serious-condition () nil))
    (let ((fd (stream-file-descriptor output :output)))
      (if fd
          (write-octets-to-fd
           fd
           (sb-ext:string-to-octets sequence))
          (progn
            (write-string sequence output)
            (finish-output output))))))

(defun terminal-restore-on-exit (terminal)
  (write-terminal-exit-bytes
   terminal
   (process-terminal-exit-restore-sequence
    terminal
    (terminal-exit-restore-prefix terminal)
    (terminal-exit-restore-suffix terminal))))

(defun run-terminal-exit-restores ()
  (dolist (terminal (copy-list *armed-terminal-exits*))
    (handler-case
        (terminal-restore-on-exit terminal)
      (serious-condition () nil))))

(defmethod terminal-start ((terminal process-terminal))
  #+sbcl
  (let ((fd
          (stream-file-descriptor
           (process-terminal-input terminal)
           :input)))
    (unless fd
      (error "TUI input is not a file-descriptor stream"))
    (let ((original (sb-posix:tcgetattr fd)))
      (setf
       (process-terminal-input-fd terminal) fd
       (process-terminal-saved-termios terminal)
       original)
      (stdin-buffer-clear
       (process-terminal-stdin-buffer terminal))
      (setf
       (process-terminal-pending-input terminal)
       nil)
      (sb-posix:tcsetattr
       fd sb-posix:tcsanow
       (raw-termios original))
      ;; pi@4a080252f terminal.ts start(): ENABLE_VIRTUAL_TERMINAL_INPUT
      ;; is applied after setRawMode, which resets console mode flags.
      (funcall
       (process-terminal-windows-vt-input-function terminal))
      (setf (process-terminal-started-p terminal) t)
      (setf
       (process-terminal-keyboard-protocol-pushed-p
        terminal)
       t)
      (arm-terminal-exit-restore terminal)
      (refresh-terminal-size terminal)
      (let ((program-status-query
              (if (configure-program-status-support
                   terminal)
                  +program-status-query+
                  "")))
        (terminal-write
         terminal
         (format nil
                 "~C[?2004h~C[?25l~A~A~A~A~A"
                 #\Escape #\Escape
                 +keyboard-protocol-query-without-da+
                 program-status-query
                 +device-attributes-query+
                 (if
                     (terminal-capabilities-images
                      (get-terminal-capabilities))
                     (format nil "~C[16t" #\Escape)
                     "")
                 (if
                     (process-terminal-color-scheme-notifications-enabled-p
                      terminal)
                     (format nil "~C[?2031h" #\Escape)
                     "")))
        (when
            (process-terminal-program-status-supported-p
             terminal)
          (write-stored-program-status terminal)))))
  #-sbcl
  (error "process-terminal requires SBCL")
  terminal)

(defmethod terminal-stop ((terminal process-terminal))
  (when (process-terminal-started-p terminal)
    (disarm-terminal-exit-restore terminal)
    (setf (terminal-exit-renderer terminal) nil)
    (unwind-protect
         (ignore-errors
           (when (process-terminal-progress-active-p
                  terminal)
             (terminal-set-progress terminal nil))
           (when
               (and
                (process-terminal-program-status-supported-p
                 terminal)
                (process-terminal-program-status terminal))
             (terminal-write
              terminal
              (format-program-status
               (make-program-status :state :clear))))
           (terminal-write
            terminal
            (format nil
                    "~A~C[0m~C[?25h~C[?2004l~C[<u~A"
                    (if
                        (process-terminal-color-scheme-notifications-enabled-p
                         terminal)
                        (format nil "~C[?2031l" #\Escape)
                        "")
                    #\Escape #\Escape #\Escape #\Escape
                    +modify-other-keys-disable+)))
      #+sbcl
      (when (and
             (process-terminal-input-fd terminal)
             (process-terminal-saved-termios terminal))
        (ignore-errors
          (sb-posix:tcsetattr
           (process-terminal-input-fd terminal)
           sb-posix:tcsanow
           (process-terminal-saved-termios terminal))))
      (setf
       (process-terminal-started-p terminal) nil
       (process-terminal-keyboard-protocol-pushed-p
        terminal)
       nil
       (process-terminal-saved-termios terminal) nil
       (process-terminal-progress-active-p terminal) nil
       (process-terminal-progress-next-keepalive-at terminal)
       nil
       (process-terminal-program-status-supported-p
        terminal)
       nil
       (process-terminal-program-status-query-pending-p
        terminal)
       nil
       (process-terminal-stdin-prefix-time terminal) nil
       (process-terminal-keyboard-prefix-time terminal) nil
       (process-terminal-pending-input terminal) nil)
      (stdin-buffer-destroy
       (process-terminal-stdin-buffer terminal))
      (set-kitty-protocol-active nil)))
  terminal)

(defmethod terminal-write ((terminal process-terminal) text)
  (write-string text
                (process-terminal-output terminal))
  (finish-output
   (process-terminal-output terminal))
  text)

(defun process-terminal-normalize-input
    (terminal sequence)
  (let ((apple-terminal-p
          (and
           (string= sequence (string #\Return))
           (funcall
            (process-terminal-apple-terminal-function
             terminal)))))
    (normalize-apple-terminal-input
     sequence
     apple-terminal-p
     (and
      apple-terminal-p
      (funcall
       (process-terminal-native-modifier-function
        terminal)
       :shift)))))

(defun process-terminal-consume-sequence
    (terminal sequence forward)
  (when (program-status-reply-p sequence)
    (when
        (process-terminal-program-status-query-pending-p
         terminal)
      (setf
       (process-terminal-program-status-query-pending-p
        terminal)
       nil
       (process-terminal-program-status-supported-p
        terminal)
       t)
      (write-stored-program-status terminal))
    (return-from process-terminal-consume-sequence
      forward))
  (multiple-value-bind (sequences writes)
      (keyboard-protocol-consume
       (process-terminal-keyboard-negotiator terminal)
       sequence)
    (dolist (write writes)
      (terminal-write terminal write))
    (dolist (candidate sequences)
      (when (program-status-reply-p candidate)
        (when
            (process-terminal-program-status-query-pending-p
             terminal)
          (setf
           (process-terminal-program-status-query-pending-p
            terminal)
           nil
           (process-terminal-program-status-supported-p
            terminal)
           t)
          (write-stored-program-status terminal))
        (return))
      (multiple-value-bind (consumed-p value)
          (terminal-response-consume
           (process-terminal-response-filter terminal)
           candidate)
        (if consumed-p
            (cond
              ((typep value 'rgb-color)
               (setf
                (process-terminal-background-response
                 terminal)
                value))
              ((member value '(:dark :light))
               (setf
                (process-terminal-color-scheme-response
                 terminal)
                value)))
            (setf forward
                  (nconc forward
                         (list
                          (process-terminal-normalize-input
                           terminal candidate))))))))
  forward)

(defun resolve-escape-timeout-milliseconds ()
  ;; Baseline terminal.ts resolveEscapeTimeoutMs (v0.84.2): an explicit
  ;; CADR_TUI_ESC_TIMEOUT override wins; SSH transports get a longer
  ;; reassembly window for legacy Alt+key input.
  (let ((configured
          (ignore-errors
           (parse-integer
            (or (uiop:getenv "CADR_TUI_ESC_TIMEOUT") "")))))
    (cond
      ((and configured (plusp configured)) configured)
      ((or (uiop:getenv "SSH_CONNECTION")
           (uiop:getenv "SSH_TTY"))
       100)
      (t 10))))

(defun elapsed-seconds (start)
  (/ (- (get-internal-real-time) start)
     internal-time-units-per-second))

(defmethod terminal-read-input ((terminal process-terminal))
  (when
      (process-terminal-pending-input terminal)
    (return-from terminal-read-input
      (pop
       (process-terminal-pending-input
        terminal))))
  (let ((raw
          (with-output-to-string (output)
            (loop for character =
                  (read-char-no-hang
                  (process-terminal-input terminal)
                   nil nil)
                  while character
                  do (write-char character output))))
        (forward nil))
    (when (plusp (length raw))
      (multiple-value-bind (sequences pastes events)
          (stdin-buffer-process
           (process-terminal-stdin-buffer terminal)
           raw)
        (declare (ignore sequences pastes))
        (dolist (event events)
          (case (first event)
            (:data
             (setf forward
                   (process-terminal-consume-sequence
                    terminal (second event) forward)))
            (:paste
             (setf forward
                   (nconc
                    forward
                    (list
                     (concatenate
                      'string
                      +paste-start+
                      (second event)
                      +paste-end+)))))))))
    (if
        (plusp
         (length
          (stdin-buffer-contents
           (process-terminal-stdin-buffer terminal))))
        (unless
            (process-terminal-stdin-prefix-time terminal)
          (setf
           (process-terminal-stdin-prefix-time terminal)
           (get-internal-real-time)))
        (setf
         (process-terminal-stdin-prefix-time terminal)
         nil))
    (let ((started
            (process-terminal-stdin-prefix-time terminal)))
      (when
          (and started
               (>= (elapsed-seconds started)
                   ;; Baseline v0.84.2 stdin-buffer.ts: a lone ESC flushes
                   ;; after the escape timeout; any longer incomplete
                   ;; sequence gets the sequence timeout.
                   (let ((buffer
                           (process-terminal-stdin-buffer terminal)))
                     (/ (if (string= (stdin-buffer-contents buffer)
                                     (string #\Escape))
                            (stdin-buffer-escape-timeout-milliseconds
                             buffer)
                            (stdin-buffer-timeout-milliseconds buffer))
                        1000d0))))
        (dolist
            (sequence
             (stdin-buffer-flush
              (process-terminal-stdin-buffer terminal)))
          (setf forward
                (process-terminal-consume-sequence
                 terminal sequence forward)))
        (setf
         (process-terminal-stdin-prefix-time terminal)
         nil)))
    (if
        (plusp
         (length
          (keyboard-protocol-negotiator-buffer
           (process-terminal-keyboard-negotiator
            terminal))))
        (unless
            (process-terminal-keyboard-prefix-time terminal)
          (setf
           (process-terminal-keyboard-prefix-time terminal)
           (get-internal-real-time)))
        (setf
         (process-terminal-keyboard-prefix-time terminal)
         nil))
    (let ((started
            (process-terminal-keyboard-prefix-time
             terminal)))
      (when
          (and started
               (>= (elapsed-seconds started) 0.15d0))
        (setf
         forward
         (append
          forward
          (keyboard-protocol-flush
           (process-terminal-keyboard-negotiator
            terminal)))
         (process-terminal-keyboard-prefix-time
          terminal)
         nil)))
    (when forward
      (setf
       (process-terminal-pending-input terminal)
       (rest forward)))
    (or (first forward) "")))

(defmethod terminal-resized-p ((terminal process-terminal))
  (when (process-terminal-resize-p terminal)
    (setf (process-terminal-resize-p terminal) nil)
    (refresh-terminal-size terminal)
    t))

(defmethod terminal-query-background-color
    ((terminal process-terminal)
     &key (timeout-seconds 0.1d0))
  (unless (process-terminal-started-p terminal)
    (return-from terminal-query-background-color nil))
  (let ((forward nil)
        (started-at
          (get-internal-real-time))
        (timeout
          (max 0d0
               (coerce timeout-seconds
                       'double-float))))
    (setf
     (process-terminal-background-response terminal)
     nil)
    (terminal-response-expect-color
     (process-terminal-response-filter terminal))
    (terminal-write
     terminal
     (format nil "~C]11;?~C"
             #\Escape (code-char 7)))
    (loop
      (let ((input
              (terminal-read-input terminal)))
        (when (plusp (length input))
          (push input forward)))
      (when
          (or
           (process-terminal-background-response terminal)
           (>= (elapsed-seconds started-at) timeout))
        (return))
      (sleep 0.005d0))
    (when forward
      (setf
       (process-terminal-pending-input terminal)
       (nconc
        (nreverse forward)
        (process-terminal-pending-input terminal))))
    (process-terminal-background-response terminal)))

(defmethod terminal-query-theme-colors
    ((terminal process-terminal)
     &key (timeout-seconds 0.1d0))
  (unless (process-terminal-started-p terminal)
    (return-from terminal-query-theme-colors nil))
  (let* ((filter
           (process-terminal-response-filter terminal))
         (query (make-terminal-color-query))
         (forward nil)
         (started-at (get-internal-real-time))
         (timeout
           (max 0d0
                (coerce timeout-seconds 'double-float))))
    (setf (terminal-response-filter-color-query filter) query)
    (setf (terminal-response-filter-color-result filter) nil)
    (terminal-write terminal (terminal-color-query-sequence))
    (loop
      (let ((input (terminal-read-input terminal)))
        (when (plusp (length input))
          (push input forward)))
      (when (or (null
                 (terminal-response-filter-color-query filter))
                (>= (elapsed-seconds started-at) timeout))
        (return))
      (sleep 0.005d0))
    (when forward
      (setf
       (process-terminal-pending-input terminal)
       (nconc
        (nreverse forward)
        (process-terminal-pending-input terminal))))
    (let ((result
            (or (terminal-response-filter-color-result filter)
                (terminal-color-query-plist query))))
      (when (null
             (terminal-response-filter-color-query filter))
        (setf (terminal-response-filter-color-result filter)
              nil))
      result)))

(defmethod terminal-take-theme-colors
    ((terminal process-terminal))
  (let* ((filter
           (process-terminal-response-filter terminal))
         (result
           (terminal-response-filter-color-result filter)))
    (setf (terminal-response-filter-color-result filter) nil)
    result))

(defmethod terminal-query-color-scheme
    ((terminal process-terminal)
     &key (timeout-seconds 0.1d0))
  (unless (process-terminal-started-p terminal)
    (return-from terminal-query-color-scheme nil))
  (let ((forward nil)
        (started-at
          (get-internal-real-time))
        (timeout
          (max 0d0
               (coerce timeout-seconds
                       'double-float))))
    (setf
     (process-terminal-color-scheme-response terminal)
     nil)
    (terminal-write
     terminal
     (format nil "~C[?996n" #\Escape))
    (loop
      (let ((input
              (terminal-read-input terminal)))
        (when (plusp (length input))
          (push input forward)))
      (when
          (or
           (process-terminal-color-scheme-response terminal)
           (>= (elapsed-seconds started-at) timeout))
        (return))
      (sleep 0.005d0))
    (when forward
      (setf
       (process-terminal-pending-input terminal)
       (nconc
        (nreverse forward)
        (process-terminal-pending-input terminal))))
    (prog1
        (process-terminal-color-scheme-response terminal)
      (setf
       (process-terminal-color-scheme-response terminal)
       nil))))

(defmethod terminal-set-color-scheme-notifications
    ((terminal process-terminal) enabled)
  (let ((enabled-p (not (null enabled))))
    (unless
        (eq enabled-p
            (process-terminal-color-scheme-notifications-enabled-p
             terminal))
      (setf
       (process-terminal-color-scheme-notifications-enabled-p
        terminal)
       enabled-p)
      (when (process-terminal-started-p terminal)
        (terminal-write
         terminal
         (format nil "~C[?2031~C"
                 #\Escape
                 (if enabled-p #\h #\l)))))
    enabled-p))

(defmethod terminal-color-scheme-change
    ((terminal process-terminal))
  (prog1
      (process-terminal-color-scheme-response terminal)
    (setf
     (process-terminal-color-scheme-response terminal)
     nil)))

(defmethod terminal-set-progress
    ((terminal process-terminal) active)
  (let ((active-p (not (null active))))
    (if active-p
        (progn
          (terminal-write
           terminal
           +terminal-progress-active-sequence+)
          (setf
           (process-terminal-progress-active-p terminal)
           t
           (process-terminal-progress-next-keepalive-at
            terminal)
           (+ (funcall
               (process-terminal-progress-clock-function
                terminal))
              +terminal-progress-keepalive-seconds+)))
        (progn
          (setf
           (process-terminal-progress-active-p terminal)
           nil
           (process-terminal-progress-next-keepalive-at
            terminal)
           nil)
          (terminal-write
           terminal
           +terminal-progress-clear-sequence+)))
    active-p))

(defmethod terminal-poll-progress
    ((terminal process-terminal))
  (let ((next
          (process-terminal-progress-next-keepalive-at
           terminal)))
    (when
        (and
         (process-terminal-progress-active-p terminal)
         next
         (>=
          (funcall
           (process-terminal-progress-clock-function
            terminal))
          next))
      (terminal-write
       terminal
       +terminal-progress-active-sequence+)
      (setf
       (process-terminal-progress-next-keepalive-at
        terminal)
       (+ (funcall
           (process-terminal-progress-clock-function
            terminal))
          +terminal-progress-keepalive-seconds+))
      t)))

(defmethod terminal-set-program-status
    ((terminal process-terminal) status)
  (setf
   (process-terminal-program-status terminal)
   (if (and status
            (not (eq :clear
                     (program-status-state status))))
       status
       nil))
  (when
      (process-terminal-program-status-supported-p
       terminal)
    (terminal-write
     terminal
     (format-program-status
      (or status
          (make-program-status :state :clear)))))
  status)
(defun %call-with-terminal
    (terminal function
     before-start before-stop after-stop)
  (unwind-protect
       (progn
         (when before-start
           (funcall before-start))
         (terminal-start terminal)
         (funcall function))
    (unwind-protect
         (progn
           (disarm-terminal-exit-restore terminal)
           (when before-stop
             (funcall before-stop))
           (terminal-stop terminal))
      (when after-stop
        (funcall after-stop)))))

(defun call-with-terminal
    (terminal function
     &key before-start before-stop after-stop)
  #+sbcl
  (if (typep terminal 'process-terminal)
      (sb-sys:with-interrupt-bindings
        (sb-sys:enable-interrupt
         sb-unix:sigwinch
         (lambda (signal code context)
           (declare (ignore signal code context))
           (setf
            (process-terminal-resize-p terminal)
            t)))
        (%call-with-terminal
         terminal function
         before-start before-stop after-stop))
      (%call-with-terminal
       terminal function
       before-start before-stop after-stop))
  #-sbcl
  (%call-with-terminal
   terminal function
   before-start before-stop after-stop))
