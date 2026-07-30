(in-package #:cadr-tui)

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
   (resize-p
    :initform nil
    :accessor process-terminal-resize-p)))

(defun make-process-terminal
    (&key
       (input *standard-input*)
       (output *standard-output*))
  (make-instance
   'process-terminal
   :input input
   :output output))

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
      (sb-posix:tcsetattr
       fd sb-posix:tcsanow
       (raw-termios original))
      (setf (process-terminal-started-p terminal) t)
      (refresh-terminal-size terminal)
      (terminal-write
       terminal
       (format nil
               "~C[?1049h~C[?2004h~C[?25l~C[2J~C[H"
               #\Escape #\Escape #\Escape #\Escape #\Escape))))
  #-sbcl
  (error "process-terminal requires SBCL")
  terminal)

(defmethod terminal-stop ((terminal process-terminal))
  (when (process-terminal-started-p terminal)
    (unwind-protect
         (ignore-errors
           (terminal-write
            terminal
            (format nil
                    "~C[0m~C[?25h~C[?2004l~C[?1049l"
                    #\Escape #\Escape #\Escape #\Escape)))
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
       (process-terminal-saved-termios terminal) nil)))
  terminal)

(defmethod terminal-write ((terminal process-terminal) text)
  (write-string text
                (process-terminal-output terminal))
  (finish-output
   (process-terminal-output terminal))
  text)

(defmethod terminal-read-input ((terminal process-terminal))
  (with-output-to-string (output)
    (loop for character =
          (read-char-no-hang
           (process-terminal-input terminal)
           nil nil)
          while character
          do (write-char character output))))

(defmethod terminal-resized-p ((terminal process-terminal))
  (when (process-terminal-resize-p terminal)
    (setf (process-terminal-resize-p terminal) nil)
    (refresh-terminal-size terminal)
    t))

(defun %call-with-terminal (terminal function)
  (unwind-protect
       (progn
         (terminal-start terminal)
         (funcall function))
    (terminal-stop terminal)))

(defun call-with-terminal (terminal function)
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
        (%call-with-terminal terminal function))
      (%call-with-terminal terminal function))
  #-sbcl
  (%call-with-terminal terminal function))
