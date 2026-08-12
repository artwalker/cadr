(in-package #:cadr-tui)

(defparameter +keyboard-protocol-query+
  (format nil "~C[>7u~C[?u~C[c"
          #\Escape #\Escape #\Escape))

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

(defun parse-keyboard-protocol-sequence (sequence)
  (multiple-value-bind
        (start end starts ends)
      (cl-ppcre:scan
       (format nil "^~C\\[\\?(\\d+)u$"
               #\Escape)
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
       (format nil "^~C\\[\\?[\\d;]*c$"
               #\Escape)
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
   (keyboard-negotiator
    :initform
    (make-keyboard-protocol-negotiator)
    :accessor
    process-terminal-keyboard-negotiator)
   (keyboard-prefix-time
    :initform nil
    :accessor process-terminal-keyboard-prefix-time)
   (stdin-buffer
    :initform (make-stdin-buffer)
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
   (apple-terminal-function
    :initarg :apple-terminal-function
    :initform #'apple-terminal-session-p
    :reader process-terminal-apple-terminal-function)
   (native-modifier-function
    :initarg :native-modifier-function
    :initform #'is-native-modifier-pressed
    :reader process-terminal-native-modifier-function)
   (resize-p
    :initform nil
    :accessor process-terminal-resize-p)))

(defun make-process-terminal
    (&key
       (input *standard-input*)
       (output *standard-output*)
       (progress-clock-function
         #'terminal-monotonic-seconds)
       (apple-terminal-function
         #'apple-terminal-session-p)
       (native-modifier-function
         #'is-native-modifier-pressed))
  (multiple-value-bind (columns rows)
      (terminal-dimensions nil nil)
    (make-instance
     'process-terminal
     :input input
     :output output
     :progress-clock-function progress-clock-function
     :apple-terminal-function apple-terminal-function
     :native-modifier-function native-modifier-function
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
      (setf (process-terminal-started-p terminal) t)
      (refresh-terminal-size terminal)
      (terminal-write
       terminal
       (format nil
               "~C[?2004h~C[?25l~A~A~A"
               #\Escape #\Escape
               (keyboard-protocol-query)
               (if
                   (terminal-capabilities-images
                    (get-terminal-capabilities))
                   (format nil "~C[16t" #\Escape)
                   "")
               (if
                   (process-terminal-color-scheme-notifications-enabled-p
                    terminal)
                   (format nil "~C[?2031h" #\Escape)
                   "")))))
  #-sbcl
  (error "process-terminal requires SBCL")
  terminal)

(defmethod terminal-stop ((terminal process-terminal))
  (when (process-terminal-started-p terminal)
    (unwind-protect
         (ignore-errors
           (when (process-terminal-progress-active-p
                  terminal)
             (terminal-set-progress terminal nil))
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
       (process-terminal-saved-termios terminal) nil
       (process-terminal-progress-active-p terminal) nil
       (process-terminal-progress-next-keepalive-at terminal)
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
  (multiple-value-bind (sequences writes)
      (keyboard-protocol-consume
       (process-terminal-keyboard-negotiator terminal)
       sequence)
    (dolist (write writes)
      (terminal-write terminal write))
    (dolist (candidate sequences)
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
               (>= (elapsed-seconds started) 0.01d0))
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
