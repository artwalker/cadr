(in-package #:cadr-tui/tests)
(in-suite cadr-tui-suite)

(test apple-terminal-return-normalization
  (is (string=
       (csi "13;2u")
       (cadr-tui:normalize-apple-terminal-input
        (string #\Return) t t)))
  (is (string=
       (string #\Return)
       (cadr-tui:normalize-apple-terminal-input
        (string #\Return) t nil)))
  (is (string=
       (string #\Return)
       (cadr-tui:normalize-apple-terminal-input
        (string #\Return) nil t)))
  (is (string=
       "x"
       (cadr-tui:normalize-apple-terminal-input
        "x" t t))))

(test apple-terminal-native-modifier-fixtures-match-coregraphics-masks
  (dolist (spec '((:shift #x00020000)
                  (:control #x00040000)
                  (:option #x00080000)
                  (:command #x00100000)))
    (destructuring-bind (key mask) spec
      (is
       (cadr-tui::native-modifier-pressed-p
        key t "arm64" (lambda () mask)))
      (is
       (cadr-tui::native-modifier-pressed-p
        (string-downcase (symbol-name key))
        t "x86-64" (lambda () mask)))
      (is
       (not
        (cadr-tui::native-modifier-pressed-p
         key t "arm64" (constantly 0))))))
  (is
   (not
    (cadr-tui::native-modifier-pressed-p
     :unknown t "arm64" (constantly #xffffffffffffffff)))))

(test apple-terminal-native-modifier-query-is-fail-closed
  (let ((queries 0))
    (flet ((flags ()
             (incf queries)
             #x00020000))
      (is
       (not
        (cadr-tui::native-modifier-pressed-p
         :shift nil "arm64" #'flags)))
      (is (= 0 queries))
      (is
       (not
        (cadr-tui::native-modifier-pressed-p
         :shift t "powerpc" #'flags)))
      (is (= 0 queries))))
  (is
   (not
    (cadr-tui::native-modifier-pressed-p
     :shift t "arm64"
     (lambda () (error "fixture failure")))))
  #-darwin
  (is (not (cadr-tui::is-native-modifier-pressed :shift))))

(test apple-terminal-session-detection-matches-baseline
  (flet ((apple-environment (name)
           (and (string= name "TERM_PROGRAM")
                "Apple_Terminal"))
         (iterm-environment (name)
           (and (string= name "TERM_PROGRAM")
                "iTerm.app")))
    (is
     (cadr-tui::apple-terminal-session-with-environment-p
      t #'apple-environment))
    (is
     (not
      (cadr-tui::apple-terminal-session-with-environment-p
       nil #'apple-environment)))
    (is
     (not
      (cadr-tui::apple-terminal-session-with-environment-p
       t #'iterm-environment)))))

(test process-terminal-queries-shift-only-for-apple-terminal-return
  (let* ((queries nil)
        (terminal
          (cadr-tui:make-process-terminal
           :input (make-string-input-stream (string #\Return))
           :output (make-string-output-stream)
           :apple-terminal-function (constantly t)
           :native-modifier-function
           (lambda (key)
             (push key queries)
             t))))
    (is (string= (csi "13;2u")
                 (cadr-tui:terminal-read-input terminal)))
    (is (equal '(:shift) queries)))
  (dolist (spec
           (list
            (list (string #\Return) nil t (string #\Return))
            (list (string #\Return) t nil (string #\Return))
            (list "x" t t "x")))
    (destructuring-bind
        (input apple-terminal-p shift-pressed-p expected) spec
      (let* ((queries 0)
            (terminal
              (cadr-tui:make-process-terminal
               :input (make-string-input-stream input)
               :output (make-string-output-stream)
               :apple-terminal-function
               (constantly apple-terminal-p)
               :native-modifier-function
               (lambda (key)
                 (declare (ignore key))
                 (incf queries)
                 shift-pressed-p))))
        (is (string= expected
                     (cadr-tui:terminal-read-input terminal)))
        (is (= (if (and apple-terminal-p
                        (string= input (string #\Return)))
                   1
                   0)
               queries))))))

(test keyboard-protocol-negotiation-matches-kitty-fallback-order
  (let ((negotiator
          (cadr-tui:make-keyboard-protocol-negotiator)))
    (is (string=
         (format nil "~C[>7u~C[?u~C[c"
                 #\Escape #\Escape #\Escape)
         (cadr-tui:keyboard-protocol-query)))
    (multiple-value-bind (forward writes)
        (cadr-tui:keyboard-protocol-consume
         negotiator "a")
      (is (equal '("a") forward))
      (is (null writes)))
    (multiple-value-bind (forward writes)
        (cadr-tui:keyboard-protocol-consume
         negotiator (csi "?7"))
      (is (null forward))
      (is (null writes)))
    (multiple-value-bind (forward writes)
        (cadr-tui:keyboard-protocol-consume
         negotiator "u")
      (is (null forward))
      (is (null writes)))
    (is (eq :kitty
            (cadr-tui:keyboard-protocol-mode
             negotiator))))
  (let ((negotiator
          (cadr-tui:make-keyboard-protocol-negotiator)))
    (multiple-value-bind (forward writes)
        (cadr-tui:keyboard-protocol-consume
         negotiator (csi "?0u"))
      (is (null forward))
      (is (equal (list (csi ">4;2m")) writes)))
    (is (eq :modify-other-keys
            (cadr-tui:keyboard-protocol-mode
             negotiator))))
  (let ((negotiator
          (cadr-tui:make-keyboard-protocol-negotiator)))
    (multiple-value-bind (forward writes)
        (cadr-tui:keyboard-protocol-consume
         negotiator (csi "?1;2c"))
      (is (null forward))
      (is (equal (list (csi ">4;2m")) writes)))))

(test keyboard-protocol-replays-incomplete-non-response
  (let ((negotiator
          (cadr-tui:make-keyboard-protocol-negotiator)))
    (multiple-value-bind (forward writes)
        (cadr-tui:keyboard-protocol-consume
         negotiator (csi ""))
      (is (null forward))
      (is (null writes)))
    (is (equal (list (csi ""))
               (cadr-tui:keyboard-protocol-flush
                negotiator)))))

(test process-terminal-splits-batched-capability-replies-from-user-input
  (let* ((escape (string #\Escape))
         (output (make-string-output-stream))
         (terminal
           (cadr-tui:make-process-terminal
            :input
            (make-string-input-stream
             (format nil "/~A[?1;2;4c" escape))
            :output output)))
    (is (string= "/"
                 (cadr-tui:terminal-read-input terminal)))
    (is (string=
         (format nil "~A[>4;2m" escape)
         (get-output-stream-string output))))
  (let ((terminal
          (cadr-tui:make-process-terminal
           :input
           (make-string-input-stream
            (format nil "~C[6;24;12tq" #\Escape))
           :output
           (make-string-output-stream))))
    (is (string= "q"
                 (cadr-tui:terminal-read-input terminal)))
    (is (equal
         '(12 24)
         (multiple-value-list
          (cadr-tui:get-cell-dimensions))))))

(test process-terminal-preserves-batched-input-event-boundaries
  (let* ((press
           (format nil "~C[<0;2;1M" #\Escape))
         (drag
           (format nil "~C[<32;4;1M" #\Escape))
         (release
           (format nil "~C[<0;4;1m" #\Escape))
         (terminal
           (cadr-tui:make-process-terminal
            :input
            (make-string-input-stream
             (concatenate
              'string press drag release))
            :output
            (make-string-output-stream))))
    (is (string=
         press
         (cadr-tui:terminal-read-input terminal)))
    (is (string=
         drag
         (cadr-tui:terminal-read-input terminal)))
    (is (string=
         release
         (cadr-tui:terminal-read-input terminal)))
    (is (string=
         ""
         (cadr-tui:terminal-read-input terminal)))))

(test windows-virtual-terminal-input-ors-the-console-flag
  ;; pi@4a080252f win32-platform.c enable_virtual_terminal_input ORs
  ;; ENABLE_VIRTUAL_TERMINAL_INPUT (0x0200) into the stdin console
  ;; mode. Non-Windows and a failed read do not call SetConsoleMode.
  ;; A thrown helper is swallowed.
  (is (= #x0200 cadr-tui::+enable-virtual-terminal-input+))
  (is (= #xfffffff6 cadr-tui::+std-input-handle+))
  (dolist (mode '(0 1 #x1f7 #x0200 #x80000000))
    (is (= (logior mode #x0200)
           (cadr-tui::console-mode-with-virtual-terminal-input
            mode))))
  (let ((reads 0)
        (writes nil))
    (is (null
         (cadr-tui::apply-windows-virtual-terminal-input
          nil
          (lambda ()
            (incf reads)
            (values 1 t))
          (lambda (mode)
            (push mode writes)))))
    (is (zerop reads))
    (is (null writes)))
  (let ((writes nil))
    (is (eql t
             (cadr-tui::apply-windows-virtual-terminal-input
              t
              (lambda () (values #x1f7 t))
              (lambda (mode) (push mode writes)))))
    (is (equal '(#x03f7) writes)))
  (let ((writes nil))
    (is (null
         (cadr-tui::apply-windows-virtual-terminal-input
          t
          (lambda () (values nil nil))
          (lambda (mode) (push mode writes)))))
    (is (null writes)))
  (is (null
       (cadr-tui::apply-windows-virtual-terminal-input
        t
        (lambda () (error "console helper missing"))
        (lambda (mode) (declare (ignore mode))))))
  (is (null
       (cadr-tui::apply-windows-virtual-terminal-input
        t
        (lambda () (values 7 t))
        (lambda (mode)
          (declare (ignore mode))
          (error "SetConsoleMode failed")))))
  (unless (uiop:os-windows-p)
    (is (null (cadr-tui::enable-windows-virtual-terminal-input)))))

(test windows-vt-input-runs-after-raw-mode
  ;; pi@4a080252f terminal.ts start() calls enableWindowsVTInput after
  ;; setRawMode(true). ICANON and ECHO are already off when it runs.
  (call-with-pty-input
   (lambda (input)
     (let ((output (make-string-output-stream))
           (seen nil)
           (terminal nil))
       (setf terminal
             (cadr-tui:make-process-terminal
              :input input
              :output output
              :windows-vt-input-function
              (lambda ()
                (let* ((fd
                         (cadr-tui::process-terminal-input-fd
                          terminal))
                       (termios (sb-posix:tcgetattr fd))
                       (lflag
                         (sb-posix:termios-lflag termios)))
                  (setf seen
                        (list
                         (not (null fd))
                         (zerop (logand lflag sb-posix:icanon))
                         (zerop (logand lflag sb-posix:echo))))))))
       (unwind-protect
            (progn
              (cadr-tui:terminal-start terminal)
              (is (equal '(t t t) seen))
              (is (cadr-tui::process-terminal-started-p terminal)))
         (when (cadr-tui::process-terminal-started-p terminal)
           (ignore-errors (cadr-tui:terminal-stop terminal)))
         (cadr-tui::disarm-terminal-exit-restore terminal))))))

(test refresh-terminal-dimensions-matches-v140
  ;; pi@4a080252f packages/tui/src/terminal.ts refreshTerminalDimensions
  ;; and packages/tui/test/regression-sigwinch-kill-eacces.test.ts.
  ;; POSIX and a positive pid: kill(pid, SIGWINCH). win32 and pid <= 0
  ;; do not call kill. EACCES, EPERM, and any other kill error are ignored.
  (let ((calls nil))
    (cadr-tui::refresh-terminal-dimensions
     :windows-p nil
     :pid 4242
     :kill-function
     (lambda (pid signal)
       (push (list pid signal) calls)))
    (is (equal (list (list 4242 sb-posix:sigwinch)) calls)))
  (dolist (pid '(0 -1))
    (let ((calls 0))
      (cadr-tui::refresh-terminal-dimensions
       :windows-p nil
       :pid pid
       :kill-function
       (lambda (pid signal)
         (declare (ignore pid signal))
         (incf calls)))
      (is (zerop calls) "pid ~A must not be signaled" pid)))
  (let ((calls 0))
    (cadr-tui::refresh-terminal-dimensions
     :windows-p t
     :pid 4242
     :kill-function
     (lambda (pid signal)
       (declare (ignore pid signal))
       (incf calls)))
    (is (zerop calls)))
  (dolist (reason '("kill EACCES" "kill EPERM"))
    (let ((calls 0))
      (finishes
        (cadr-tui::refresh-terminal-dimensions
         :windows-p nil
         :pid 7
         :kill-function
         (lambda (pid signal)
           (declare (ignore pid signal))
           (incf calls)
           (error reason))))
      (is (= 1 calls) "~A must reach kill and then be ignored" reason)))
  (unless (uiop:os-windows-p)
    (finishes
      (cadr-tui::refresh-terminal-dimensions
       :windows-p nil
       :pid (sb-posix:getpid)))))

(test process-terminal-start-self-sigwinch-after-raw-mode
  ;; pi@4a080252f terminal.ts start() calls refreshTerminalDimensions
  ;; after setRawMode and before enableWindowsVTInput.
  (call-with-pty-input
   (lambda (input)
     (let ((output (make-string-output-stream))
           (order nil)
           (raw-at-refresh nil)
           (terminal nil))
       (setf terminal
             (cadr-tui:make-process-terminal
              :input input
              :output output
              :dimensions-refresh-function
              (lambda ()
                (let* ((fd
                         (cadr-tui::process-terminal-input-fd
                          terminal))
                       (lflag
                         (sb-posix:termios-lflag
                          (sb-posix:tcgetattr fd))))
                  (setf raw-at-refresh
                        (and fd
                             (zerop (logand lflag sb-posix:icanon))
                             (zerop (logand lflag sb-posix:echo)))))
                (push :sigwinch order)
                (cadr-tui::refresh-terminal-dimensions
                 :windows-p nil
                 :pid 5150
                 :kill-function
                 (lambda (pid signal)
                   (push (list :kill pid signal) order))))
              :windows-vt-input-function
              (lambda ()
                (push :vt order))))
       (unwind-protect
            (progn
              (cadr-tui:terminal-start terminal)
              (is (equal t raw-at-refresh))
              (is (equal
                   (list :sigwinch
                         (list :kill 5150 sb-posix:sigwinch)
                         :vt)
                   (nreverse order)))
              (is (cadr-tui::process-terminal-started-p terminal)))
         (when (cadr-tui::process-terminal-started-p terminal)
           (ignore-errors (cadr-tui:terminal-stop terminal)))
         (cadr-tui::disarm-terminal-exit-restore terminal)))))
  (call-with-pty-input
   (lambda (input)
     (let* ((output (make-string-output-stream))
            (terminal
              (cadr-tui:make-process-terminal
               :input input
               :output output
               :dimensions-refresh-function
               (lambda ()
                 (cadr-tui::refresh-terminal-dimensions
                  :windows-p nil
                  :pid 9
                  :kill-function
                  (lambda (pid signal)
                    (declare (ignore pid signal))
                    (error "kill EACCES")))))))
       (unwind-protect
            (progn
              (finishes (cadr-tui:terminal-start terminal))
              (is (cadr-tui::process-terminal-started-p terminal)))
         (when (cadr-tui::process-terminal-started-p terminal)
           (ignore-errors (cadr-tui:terminal-stop terminal)))
         (cadr-tui::disarm-terminal-exit-restore terminal))))))

(test terminal-dimensions-use-environment-before-defaults
  (flet ((lookup (name)
           (cdr (assoc name
                       '(("COLUMNS" . "123")
                         ("LINES" . "45"))
                       :test #'string=))))
    (multiple-value-bind (columns rows)
        (cadr-tui:terminal-dimensions
         nil nil :environment-function #'lookup)
      (is (= 123 columns))
      (is (= 45 rows))))
  (flet ((lookup (name)
           (declare (ignore name))
           "not-a-number"))
    (multiple-value-bind (columns rows)
        (cadr-tui:terminal-dimensions
         nil nil :environment-function #'lookup)
      (is (= 80 columns))
      (is (= 24 rows)))))
