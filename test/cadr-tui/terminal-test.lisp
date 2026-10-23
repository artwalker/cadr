(in-package #:cadr-tui/tests)
(in-suite cadr-tui-suite)

(defclass lifecycle-terminal (cadr-tui:terminal)
  ((starts :initform 0 :accessor lifecycle-starts)
   (stops :initform 0 :accessor lifecycle-stops)))

(defmethod cadr-tui:terminal-start ((terminal lifecycle-terminal))
  (incf (lifecycle-starts terminal)))

(defmethod cadr-tui:terminal-stop ((terminal lifecycle-terminal))
  (incf (lifecycle-stops terminal)))

(test terminal-lifecycle-restores-after-condition
  (let ((terminal (make-instance 'lifecycle-terminal)))
    (signals simple-error
      (cadr-tui:call-with-terminal
       terminal
       (lambda ()
         (error "boom"))))
    (is (= 1 (lifecycle-starts terminal)))
    (is (= 1 (lifecycle-stops terminal)))))

(defclass failing-start-terminal (lifecycle-terminal) ())

(defmethod cadr-tui:terminal-start ((terminal failing-start-terminal))
  (incf (lifecycle-starts terminal))
  (error "start failed after partial setup"))

(test terminal-lifecycle-cleans-up-partial-start
  (let ((terminal (make-instance 'failing-start-terminal)))
    (signals simple-error
      (cadr-tui:call-with-terminal
       terminal
       (lambda () nil)))
    (is (= 1 (lifecycle-starts terminal)))
    (is (= 1 (lifecycle-stops terminal)))))

(test escape-timeout-follows-cadr-tui-esc-timeout-and-ssh
  ;; pi@4a080252f packages/tui/test/terminal.test.ts resolveEscapeTimeoutMs.
  ;; SSH_CLIENT does not lengthen the timeout. An empty SSH variable is
  ;; unset for this check (JS truthiness).
  (flet ((timeout (pairs)
           (cadr-tui::resolve-escape-timeout-milliseconds
            :environment pairs)))
    (is (= 80 (timeout '(("CADR_TUI_ESC_TIMEOUT" . "80")))))
    (is (= 80
           (timeout '(("CADR_TUI_ESC_TIMEOUT" . "80")
                      ("SSH_TTY" . "/dev/pts/1")))))
    (is (= 80.5
           (timeout '(("CADR_TUI_ESC_TIMEOUT" . "80.5")))))
    (is (= 100 (timeout '(("CADR_TUI_ESC_TIMEOUT" . "1e2")))))
    (is (= 80 (timeout '(("CADR_TUI_ESC_TIMEOUT" . " 80 ")))))
    (is (= 10 (timeout '(("CADR_TUI_ESC_TIMEOUT" . "abc")))))
    (is (= 10 (timeout '(("CADR_TUI_ESC_TIMEOUT" . "0")))))
    (is (= 10 (timeout '(("CADR_TUI_ESC_TIMEOUT" . "-5")))))
    (is (= 10 (timeout '(("CADR_TUI_ESC_TIMEOUT" . "")))))
    (is (= 10 (timeout '(("CADR_TUI_ESC_TIMEOUT" . "Infinity")))))
    (is (= 100 (timeout '(("SSH_CONNECTION" . "10.0.0.1 22")))))
    (is (= 100 (timeout '(("SSH_TTY" . "/dev/pts/1")))))
    (is (= 100
           (timeout '(("CADR_TUI_ESC_TIMEOUT" . "0")
                      ("SSH_CONNECTION" . "10.0.0.1 22")))))
    (is (= 10 (timeout '(("SSH_CLIENT" . "10.0.0.1 22 24")))))
    (is (= 10 (timeout '(("SSH_CONNECTION" . "")))))
    (is (= 10 (timeout '())))))

(test multiplexer-mouse-tracking-drops-all-motion
  ;; pi@4a080252f tui-alt-screen.test.ts "uses button-motion tracking
  ;; inside terminal multiplexers".
  (let ((button (format nil "~C[?1002h" #\Escape))
        (all (format nil "~C[?1003h" #\Escape))
        (sgr (format nil "~C[?1006h" #\Escape)))
    (flet ((sequence (pairs)
             (cadr-tui::mouse-enable-sequence :environment pairs)))
      (let ((direct
              (sequence '(("TERM" . "xterm-256color")))))
        (is (search all direct))
        (is (search sgr direct)))
      (dolist (pairs '((("TMUX" . "/tmp/tmux/default,1,0"))
                       (("TERM" . "tmux-256color"))
                       (("ZELLIJ" . "0"))
                       (("ZELLIJ" . ""))
                       (("STY" . "123.session"))
                       (("TERM" . "screen-256color"))))
        (let ((writes (sequence pairs)))
          (is (search button writes) pairs)
          (is (not (search all writes)) pairs)
          (is (search sgr writes) pairs))))))

(defun tui-write-log-temp-dir ()
  (let ((dir (merge-pathnames
              (format nil "cadr-tui-write-log-~A-~A/"
                      (get-universal-time)
                      (random 1000000))
              (uiop:temporary-directory))))
    (ensure-directories-exist dir)
    dir))

(test tui-write-log-join-matches-node-path-join
  ;; Node 22 path.posix.join / path.win32.join. The write-log directory
  ;; branch is path.join(env, `tui-${ts}-${pid}.log`).
  (dolist (spec '(("" "tui.log" "tui.log")
                  ("." "tui.log" "tui.log")
                  (".." "tui.log" "../tui.log")
                  ("../.." "a" "../../a")
                  ("/" "tui.log" "/tui.log")
                  ("/tmp/foo" "tui.log" "/tmp/foo/tui.log")
                  ("/tmp/foo/" "tui.log" "/tmp/foo/tui.log")
                  ("/tmp//foo" "tui.log" "/tmp/foo/tui.log")
                  ("/tmp/foo/./bar" "tui.log" "/tmp/foo/bar/tui.log")
                  ("/tmp/foo/../bar" "tui.log" "/tmp/bar/tui.log")
                  ("/../tmp" "a" "/tmp/a")
                  ("rel/../x" "tui.log" "x/tui.log")))
    (destructuring-bind (directory filename expected) spec
      (is (string= expected
                   (cadr-tui::tui-write-log-posix-join
                    directory filename))
          spec)))
  (dolist (spec `(("C:\\logs" "tui.log" "C:\\logs\\tui.log")
                  ("C:/logs/" "tui.log" "C:\\logs\\tui.log")
                  ("C:\\foo\\..\\bar" "a.log" "C:\\bar\\a.log")
                  ("C:/foo/../bar" "a.log" "C:\\bar\\a.log")
                  ("//server/share/dir" "a.log"
                   "\\\\server\\share\\dir\\a.log")
                  ("\\\\server\\share\\dir" "a.log"
                   "\\\\server\\share\\dir\\a.log")
                  ("rel/../x" "a.log" "x\\a.log")
                  ("C:foo" "a.log" "C:foo\\a.log")
                  ("C:foo/../bar" "a.log" "C:bar\\a.log")
                  ("/tmp/foo" "a.log" "\\tmp\\foo\\a.log")
                  ("\\\\?\\C:\\logs" "a.log" "\\\\?\\C:\\logs\\a.log")
                  ("D:\\" "tui.log" "D:\\tui.log")
                  ("." "tui.log" "tui.log")
                  (".." "tui.log" "..\\tui.log")))
    (destructuring-bind (directory filename expected) spec
      (is (string= expected
                   (cadr-tui::tui-write-log-win32-join
                    directory filename))
          spec))))

(test tui-write-log-path-follows-cadr-env-file-or-directory
  ;; pi@4a080252f packages/tui/src/terminal.ts writeLogPath initializer.
  ;; CADR_TUI_WRITE_LOG is the product name. PI_TUI_WRITE_LOG is ignored.
  (let ((probes 0))
    (flet ((resolve (environment &key directory-p pid clock)
             (cadr-tui::resolve-tui-write-log-path
              :environment environment
              :directory-p
              (or directory-p
                  (lambda (path)
                    (incf probes)
                    (cadr-tui::tui-write-log-directory-p path)))
              :pid (or pid 1)
              :clock (or clock (constantly 0)))))
      (is (string= "" (resolve '())))
      (is (string= ""
                   (resolve '(("CADR_TUI_WRITE_LOG" . "")))))
      (is (string= ""
                   (resolve '(("PI_TUI_WRITE_LOG" . "/tmp/pi.log")))))
      (is (zerop probes))
      (is (string= "0"
                   (resolve '(("CADR_TUI_WRITE_LOG" . "0"))
                            :directory-p (constantly nil))))
      (is (string= "/tmp/foo/../bar.log"
                   (resolve '(("CADR_TUI_WRITE_LOG" . "/tmp/foo/../bar.log"))
                            :directory-p (constantly nil))))
      (is (string= "/tmp/kept.log"
                   (resolve '(("CADR_TUI_WRITE_LOG" . "/tmp/kept.log"))
                            :directory-p
                            (lambda (path)
                              (declare (ignore path))
                              (error "stat failed")))))
      (is (string= "/tmp/cadr.log"
                   (resolve '(("PI_TUI_WRITE_LOG" . "/tmp/pi.log")
                              ("CADR_TUI_WRITE_LOG" . "/tmp/cadr.log"))
                            :directory-p (constantly nil))))))
  (let* ((root (tui-write-log-temp-dir))
         (instant (encode-universal-time 9 5 8 23 10 2026))
         (pid 4242))
    (unwind-protect
         (multiple-value-bind (second minute hour day month year)
             (decode-universal-time instant)
           (let* ((filename
                    (format nil
                            "tui-~D-~2,'0D-~2,'0D_~2,'0D-~2,'0D-~2,'0D-~D.log"
                            year month day hour minute second pid))
                  (logs (merge-pathnames "logs/" root))
                  (via (merge-pathnames "other/../logs" root))
                  (link (merge-pathnames "linkdir" root))
                  (nested (merge-pathnames "missing-dir/ansi.log" root))
                  (plain (merge-pathnames "ansi.log" root)))
             (ensure-directories-exist logs)
             (ensure-directories-exist
              (merge-pathnames "other/" root))
             (is (= 32 (length filename)))
             (is (char= #\_ (char filename 14)))
             (is (null (find #\: filename)))
             (let ((resolved
                     (cadr-tui::resolve-tui-write-log-path
                      :environment
                      `(("CADR_TUI_WRITE_LOG" . ,(namestring logs)))
                      :clock (constantly instant)
                      :pid pid)))
               (is (string= filename (file-namestring resolved)))
               (is (string= resolved
                            (cadr-tui::tui-write-log-join
                             (namestring logs)
                             filename)))
               (is (null (probe-file resolved))))
             (let ((resolved
                     (cadr-tui::resolve-tui-write-log-path
                      :environment
                      `(("CADR_TUI_WRITE_LOG"
                         . ,(concatenate 'string
                                         (string-right-trim
                                          "/" (namestring logs))
                                         "/")))
                      :clock (constantly instant)
                      :pid pid)))
               (is (string= filename (file-namestring resolved))))
             (let ((resolved
                     (cadr-tui::resolve-tui-write-log-path
                      :environment
                      `(("CADR_TUI_WRITE_LOG" . ,(namestring via)))
                      :clock (constantly instant)
                      :pid pid)))
               (is (null (search "other" resolved)))
               (is (string= filename (file-namestring resolved))))
             (sb-posix:symlink
              (string-right-trim "/" (namestring logs))
              (namestring link))
             (let ((resolved
                     (cadr-tui::resolve-tui-write-log-path
                      :environment
                      `(("CADR_TUI_WRITE_LOG" . ,(namestring link)))
                      :clock (constantly instant)
                      :pid pid)))
               (is (search "linkdir" resolved))
               (is (null (search "/logs/" resolved)))
               (is (string= filename (file-namestring resolved))))
             (is (string= (namestring plain)
                          (cadr-tui::resolve-tui-write-log-path
                           :environment
                           `(("CADR_TUI_WRITE_LOG" . ,(namestring plain)))
                           :pid pid)))
             (is (string= (namestring nested)
                          (cadr-tui::resolve-tui-write-log-path
                           :environment
                           `(("CADR_TUI_WRITE_LOG" . ,(namestring nested)))
                           :pid pid)))))
      (uiop:delete-directory-tree root :validate t))))

(defclass tui-write-log-observing-stream
    (sb-gray:fundamental-character-output-stream)
  (   (path :initarg :path :reader tui-write-log-observing-path)
   (observed-p :initform nil :accessor tui-write-log-observing-observed-p)
   (saw-file-p :initform nil
               :accessor tui-write-log-observing-saw-file-p)
   (text :initform (make-string-output-stream)
         :reader tui-write-log-observing-text)))

(defmethod sb-gray:stream-write-string
    ((stream tui-write-log-observing-stream) string &optional start end)
  (unless (tui-write-log-observing-observed-p stream)
    (setf (tui-write-log-observing-observed-p stream) t
          (tui-write-log-observing-saw-file-p stream)
          (not (null (probe-file (tui-write-log-observing-path stream))))))
  (write-string (subseq string (or start 0) (or end (length string)))
                (tui-write-log-observing-text stream)))

(defmethod sb-gray:stream-write-char
    ((stream tui-write-log-observing-stream) character)
  (unless (tui-write-log-observing-observed-p stream)
    (setf (tui-write-log-observing-observed-p stream) t
          (tui-write-log-observing-saw-file-p stream)
          (not (null (probe-file (tui-write-log-observing-path stream))))))
  (write-char character (tui-write-log-observing-text stream)))

(defmethod sb-gray:stream-finish-output
    ((stream tui-write-log-observing-stream))
  nil)

(defclass tui-write-log-failing-stream
    (sb-gray:fundamental-character-output-stream)
  ())

(defmethod sb-gray:stream-write-string
    ((stream tui-write-log-failing-stream) string &optional start end)
  (declare (ignore stream string start end))
  (error "stdout failed"))

(defmethod sb-gray:stream-write-char
    ((stream tui-write-log-failing-stream) character)
  (declare (ignore stream character))
  (error "stdout failed"))

(defun tui-write-log-terminal (path &key output environment directory-p)
  (cadr-tui:make-process-terminal
   :input (make-string-input-stream "")
   :output (or output (make-string-output-stream))
   :write-log-environment
   (or environment
       `(("CADR_TUI_WRITE_LOG" . ,path)))
   :write-log-directory-p
   (or directory-p #'cadr-tui::tui-write-log-directory-p)
   :write-log-clock (constantly (encode-universal-time 9 5 8 23 10 2026))
   :write-log-pid 4242))

(test tui-write-log-appends-writes-and-ignores-log-errors
  ;; ProcessTerminal.write appends the same string after stdout.
  ;; fs.appendFileSync errors are ignored. setProgress uses
  ;; process.stdout.write in v1.4.0 and stays out of the log.
  (let ((root (tui-write-log-temp-dir)))
    (unwind-protect
         (let* ((log (namestring (merge-pathnames "ansi.log" root)))
                (missing (namestring
                          (merge-pathnames "missing-dir/ansi.log" root)))
                (output (make-string-output-stream))
                (terminal
                  (tui-write-log-terminal log :output output)))
           (with-open-file (stream log :direction :output
                                       :if-exists :supersede
                                       :external-format :utf-8)
             (write-string "old" stream))
           (is (string= "new"
                        (cadr-tui:terminal-write terminal "new")))
           (is (string= "oldnew"
                        (uiop:read-file-string log :external-format :utf-8)))
           (cadr-tui:terminal-write terminal "héllo中")
           (is (equalp
                (sb-ext:string-to-octets "oldnewhéllo中"
                                         :external-format :utf-8)
                (with-open-file (stream log :element-type '(unsigned-byte 8))
                  (let ((octets (make-array (file-length stream)
                                            :element-type '(unsigned-byte 8))))
                    (read-sequence octets stream)
                    octets))))
           (delete-file log)
           (cadr-tui:terminal-write terminal "two")
           (is (string= "two"
                        (uiop:read-file-string log :external-format :utf-8)))
           (cadr-tui:terminal-set-progress terminal t)
           (is (string= "two"
                        (uiop:read-file-string log :external-format :utf-8)))
           (is (search (format nil "~C]9;4;3" #\Escape)
                       (get-output-stream-string output)))
           (let* ((empty (namestring (merge-pathnames "empty.log" root)))
                  (empty-terminal (tui-write-log-terminal empty)))
             (cadr-tui:terminal-write empty-terminal "")
             (is (probe-file empty))
             (is (zerop (with-open-file (stream empty
                                                :element-type '(unsigned-byte 8))
                           (file-length stream)))))
           (let* ((frame (namestring (merge-pathnames "frame.log" root)))
                  (watch (make-instance 'tui-write-log-observing-stream
                                        :path frame))
                  (watched (tui-write-log-terminal frame :output watch)))
             (cadr-tui:terminal-write watched "AB")
             (cadr-tui:terminal-write watched "CD")
             (is (not (tui-write-log-observing-saw-file-p watch)))
             (is (string= "ABCD"
                          (uiop:read-file-string
                           frame :external-format :utf-8)))
             (is (string= "ABCD"
                          (get-output-stream-string
                           (tui-write-log-observing-text watch)))))
           (let ((quiet (namestring (merge-pathnames "quiet.log" root)))
                 (virtual (cadr-tui:make-virtual-terminal)))
             (cadr-tui:terminal-write virtual "nope")
             (is (null (probe-file quiet)))
             (let ((terminal
                     (tui-write-log-terminal
                      quiet
                      :environment
                      `(("PI_TUI_WRITE_LOG" . ,quiet)))))
               (cadr-tui:terminal-write terminal "nope")
               (is (null (probe-file quiet)))))
           (let* ((output (make-string-output-stream))
                  (terminal
                    (tui-write-log-terminal missing :output output)))
             (is (string= "still"
                          (cadr-tui:terminal-write terminal "still")))
             (is (string= "still" (get-output-stream-string output)))
             (is (null (probe-file missing))))
           (let* ((blocked (namestring (merge-pathnames "blocked.log" root)))
                  (terminal
                    (tui-write-log-terminal
                     blocked
                     :output (make-instance 'tui-write-log-failing-stream))))
             (signals simple-error
               (cadr-tui:terminal-write terminal "x"))
             (is (null (probe-file blocked))))
           (let ((calls 0)
                 (sticky (namestring (merge-pathnames "sticky.log" root))))
             (let ((terminal
                     (tui-write-log-terminal
                      sticky
                      :directory-p
                      (lambda (path)
                        (incf calls)
                        (declare (ignore path))
                        nil))))
               (cadr-tui:terminal-write terminal "a")
               (cadr-tui:terminal-write terminal "b")
               (is (= 1 calls))
               (is (string= "ab"
                            (uiop:read-file-string
                             sticky :external-format :utf-8))))))
      (uiop:delete-directory-tree root :validate t))))

(defun tui-write-log-file (path)
  (when (probe-file path)
    (uiop:read-file-string path :external-format :utf-8)))

(defun tui-write-log-color-query ()
  ;; v1.4.0 packages/tui/src/tui.ts TERMINAL_COLOR_QUERY (OSC 10, OSC 11,
  ;; OSC 4 for palette 0-15, then DA1).
  (with-output-to-string (out)
    (format out "~C]10;?~C~C]11;?~C"
            #\Escape (code-char 7) #\Escape (code-char 7))
    (loop for index below 16
          do (format out "~C]4;~D;?~C"
                     #\Escape index (code-char 7)))
    (format out "~C[c" #\Escape)))

(test tui-write-log-splits-stdout-writes-from-terminal-write
  ;; v1.4.0 terminal.ts setTitle / hideCursor / showCursor and
  ;; setProgress use process.stdout.write. tui.ts queryTerminalColors,
  ;; start's ?2031h, queryCellSize's CSI 16 t, stop's ?2031l, and
  ;; setTerminalColorSchemeNotifications use terminal.write.
  ;; tui-main-screen.ts positionHardwareCursor logs the move only.
  (let ((root (tui-write-log-temp-dir)))
    (unwind-protect
         (let* ((title-log (namestring (merge-pathnames "title.log" root)))
                (title-out (make-string-output-stream))
                (title-terminal
                  (tui-write-log-terminal title-log :output title-out))
                (title
                  (format nil "~C]0;Lane~C" #\Escape (code-char 7))))
           (cadr-tui:terminal-set-title title-terminal "Lane")
           (cadr-tui:terminal-write title-terminal "frame")
           (is (string= "frame" (tui-write-log-file title-log)))
           (is (string= (concatenate 'string title "frame")
                        (get-output-stream-string title-out)))
           (let* ((theme-log (namestring (merge-pathnames "theme.log" root)))
                  (theme-out (make-string-output-stream))
                  (theme
                    (tui-write-log-terminal theme-log :output theme-out)))
             (setf (cadr-tui::process-terminal-started-p theme) t)
             (cadr-tui:terminal-query-theme-colors
              theme :timeout-seconds 0d0)
             (is (string= (tui-write-log-color-query)
                          (tui-write-log-file theme-log)))
             (is (string= (tui-write-log-color-query)
                          (get-output-stream-string theme-out)))
             (setf (cadr-tui::process-terminal-started-p theme) nil))
           (let* ((back-log (namestring (merge-pathnames "back.log" root)))
                  (back-out (make-string-output-stream))
                  (back
                    (tui-write-log-terminal back-log :output back-out))
                  (osc11
                    (format nil "~C]11;?~C" #\Escape (code-char 7))))
             (setf (cadr-tui::process-terminal-started-p back) t)
             (cadr-tui:terminal-query-background-color
              back :timeout-seconds 0d0)
             (is (string= osc11 (tui-write-log-file back-log)))
             (is (string= osc11 (get-output-stream-string back-out)))
             (setf (cadr-tui::process-terminal-started-p back) nil))
           (let* ((note-log (namestring (merge-pathnames "note.log" root)))
                  (note-out (make-string-output-stream))
                  (note
                    (tui-write-log-terminal note-log :output note-out))
                  (enable (format nil "~C[?2031h" #\Escape))
                  (disable (format nil "~C[?2031l" #\Escape)))
             ;; v1.4.0 TuiBase.stopped starts false, so set(true) before
             ;; start writes ESC[?2031h. The same value does not write
             ;; again. set(false) before start writes ESC[?2031l.
             ;; set(false) on the default false writes nothing.
             (cadr-tui:terminal-set-color-scheme-notifications note nil)
             (is (null (tui-write-log-file note-log)))
             (cadr-tui:terminal-set-color-scheme-notifications note t)
             (is (string= enable (tui-write-log-file note-log)))
             (cadr-tui:terminal-set-color-scheme-notifications note t)
             (is (string= enable (tui-write-log-file note-log)))
             (cadr-tui:terminal-set-color-scheme-notifications note nil)
             (is (string= (concatenate 'string enable disable)
                          (tui-write-log-file note-log)))
             ;; After start, a changed value writes again. Stdout is
             ;; read once here: every notification byte also went out,
             ;; and nothing else did.
             (setf (cadr-tui::process-terminal-started-p note) t)
             (cadr-tui:terminal-set-color-scheme-notifications note t)
             (cadr-tui:terminal-set-color-scheme-notifications note t)
             (is (string= (concatenate 'string enable disable enable)
                          (tui-write-log-file note-log)))
             (cadr-tui:terminal-set-color-scheme-notifications note nil)
             (is (string= (concatenate 'string enable disable enable disable)
                          (tui-write-log-file note-log)))
             (is (string= (concatenate 'string enable disable enable disable)
                          (get-output-stream-string note-out)))
             ;; stop() sets stopped. Later sets change the flag and
             ;; do not write. The flag is already false, so stop itself
             ;; does not append ?2031l.
             (cadr-tui:terminal-stop note)
             (cadr-tui:terminal-set-color-scheme-notifications note t)
             (cadr-tui:terminal-set-color-scheme-notifications note nil)
             (is (string= (concatenate 'string enable disable enable disable)
                          (tui-write-log-file note-log))))
           (let* ((cursor-log
                    (namestring (merge-pathnames "cursor.log" root)))
                  (cursor-out (make-string-output-stream))
                  (cursor-terminal
                    (tui-write-log-terminal
                     cursor-log :output cursor-out))
                  (hide (format nil "~C[?25l" #\Escape))
                  (show (format nil "~C[?25h" #\Escape))
                  (column (format nil "~C[4G" #\Escape))
                  (up (format nil "~C[1A" #\Escape)))
             (setf (cadr-tui:terminal-columns cursor-terminal) 20
                   (cadr-tui:terminal-rows cursor-terminal) 4)
             (let ((renderer
                     (cadr-tui:make-terminal-renderer
                      cursor-terminal
                      :show-hardware-cursor-p t)))
               ;; A full frame parks the hardware row on the last line,
               ;; then positionHardwareCursor moves back to row 0.
               (cadr-tui:render-frame
                renderer '("editor" "next")
                :cursor-row 0 :cursor-column 0)
               (cadr-tui:render-frame
                renderer '("editor")
                :cursor-row 0 :cursor-column 3))
             (is (search up (tui-write-log-file cursor-log)))
             (is (search column (tui-write-log-file cursor-log)))
             (is (null (search hide (tui-write-log-file cursor-log))))
             (is (null (search show (tui-write-log-file cursor-log))))
             (is (search show (get-output-stream-string cursor-out))))
           (let* ((hidden-log
                    (namestring (merge-pathnames "hidden.log" root)))
                  (hidden-out (make-string-output-stream))
                  (hidden-terminal
                    (tui-write-log-terminal
                     hidden-log :output hidden-out))
                  (hide (format nil "~C[?25l" #\Escape)))
             (setf (cadr-tui:terminal-columns hidden-terminal) 20
                   (cadr-tui:terminal-rows hidden-terminal) 4)
             (cadr-tui:render-frame
              (cadr-tui:make-terminal-renderer hidden-terminal)
              '("editor")
              :cursor-row 0 :cursor-column 3)
             (cadr-tui:render-frame
              (cadr-tui:make-terminal-renderer hidden-terminal)
              '("editor")
              :cursor-row nil :cursor-column nil)
             (is (null (search hide (tui-write-log-file hidden-log))))
             (is (search hide (get-output-stream-string hidden-out)))))
      (uiop:delete-directory-tree root :validate t))))

(test tui-write-log-records-cell-size-and-color-scheme-startup
  ;; v1.4.0 TuiBase.stopped starts false. set(true) before start writes
  ;; ?2031h through terminal.write. start writes that sequence again,
  ;; then CSI 16 t when images are enabled. stop writes ?2031l.
  ;; Bracketed paste, the cursor hide, and the keyboard DA query stay
  ;; on process.stdout.write. After stop, set does not write; the next
  ;; start writes ?2031h again because the flag was set back to true.
  (let ((root (tui-write-log-temp-dir))
        (saved-capabilities (cadr-tui:get-terminal-capabilities)))
    (unwind-protect
         (progn
           (cadr-tui:set-terminal-capabilities
            (cadr-tui:make-terminal-capabilities :images t))
           (call-with-pty-input
            (lambda (input)
              (let* ((log (namestring (merge-pathnames "start.log" root)))
                     (output (make-string-output-stream))
                     (terminal
                       (cadr-tui:make-process-terminal
                        :input input
                        :output output
                        :dimensions-refresh-function (lambda () nil)
                        :windows-vt-input-function (lambda () nil)
                        :write-log-environment
                        `(("CADR_TUI_WRITE_LOG" . ,log))
                        :write-log-directory-p
                        #'cadr-tui::tui-write-log-directory-p
                        :write-log-clock
                        (constantly
                         (encode-universal-time 9 5 8 23 10 2026))
                        :write-log-pid 4242))
                     (enable (format nil "~C[?2031h" #\Escape))
                     (cell (format nil "~C[16t" #\Escape))
                     (disable (format nil "~C[?2031l" #\Escape))
                     (paste (format nil "~C[?2004h" #\Escape))
                     (hide (format nil "~C[?25l" #\Escape)))
                (cadr-tui:terminal-set-color-scheme-notifications
                 terminal t)
                (is (string= enable (tui-write-log-file log)))
                (is (string= enable (get-output-stream-string output)))
                (cadr-tui:terminal-set-color-scheme-notifications
                 terminal t)
                (is (string= enable (tui-write-log-file log)))
                (unwind-protect
                     (progn
                       (cadr-tui:terminal-start terminal)
                       (is (string= (concatenate 'string enable enable cell)
                                    (tui-write-log-file log)))
                       (let ((stdout (get-output-stream-string output)))
                         (is (search paste stdout))
                         (is (search hide stdout))
                         (is (search (concatenate 'string enable cell)
                                     stdout)))
                       (cadr-tui:terminal-stop terminal)
                       (is (string= (concatenate 'string
                                                 enable enable cell disable)
                                    (tui-write-log-file log)))
                       (is (null (search paste (tui-write-log-file log))))
                       (is (null (search hide (tui-write-log-file log))))
                       (is (null
                            (search (format nil "~C[?2004l" #\Escape)
                                    (tui-write-log-file log))))
                       (is (null
                            (search (format nil "~C[?25h" #\Escape)
                                    (tui-write-log-file log))))
                       (cadr-tui:terminal-set-color-scheme-notifications
                        terminal nil)
                       (cadr-tui:terminal-set-color-scheme-notifications
                        terminal t)
                       (is (string= (concatenate 'string
                                                 enable enable cell disable)
                                    (tui-write-log-file log)))
                       (cadr-tui:terminal-start terminal)
                       (is (string= (concatenate 'string
                                                 enable enable cell disable
                                                 enable cell)
                                    (tui-write-log-file log))))
                  (when (cadr-tui::process-terminal-started-p terminal)
                    (ignore-errors (cadr-tui:terminal-stop terminal)))
                  (cadr-tui::disarm-terminal-exit-restore terminal))))))
      (cadr-tui:set-terminal-capabilities saved-capabilities)
      (uiop:delete-directory-tree root :validate t))))
