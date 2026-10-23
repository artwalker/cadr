(in-package #:cadr-tui/tests)
(in-suite cadr-tui-suite)

(defun decode-program-status-message (sequence)
  (cl-ppcre:register-groups-bind (payload)
      (":msg=([A-Za-z0-9+/=]*)" sequence)
    (when payload
      (let ((octets (cadr-tui::decode-base64 payload)))
        (when octets
          #+sbcl
          (sb-ext:octets-to-string
           octets :external-format :utf-8)
          #-sbcl
          (map 'string #'code-char octets))))))

;; #10607
(test format-program-status-encodes-state-app-kind-message
  (let ((sequence
          (cadr-tui:format-program-status
           (cadr-tui:make-program-status
            :state :blocked
            :app "pi"
            :kind :permission
            :message "Allow bash?"))))
    (is
     (string=
      sequence
      (format nil
              "~C]7501;state=blocked:app=pi:kind=permission:msg=~A~C\\"
              #\Escape
              (cadr-tui::program-status-utf8-base64
               "Allow bash?")
              #\Escape))))
  (is
   (string=
    (cadr-tui:format-program-status
     (cadr-tui:make-program-status :state :clear))
    (format nil "~C]7501;state=clear~C\\"
            #\Escape #\Escape))))

(test format-program-status-omits-invalid-fields
  (is
   (string=
    (cadr-tui:format-program-status
     (cadr-tui:make-program-status
      :state :working
      :app "my app"
      :kind :auth
      :message (format nil " ~% ")))
    (format nil "~C]7501;state=working~C\\"
            #\Escape #\Escape)))
  (is
   (cl-ppcre:scan
    (format nil ":app=a{32}~C\\\\" #\Escape)
    (cadr-tui:format-program-status
     (cadr-tui:make-program-status
      :state :idle
      :app (make-string 32 :initial-element #\a)))))
  (is
   (not
    (search
     "app="
     (cadr-tui:format-program-status
      (cadr-tui:make-program-status
       :state :idle
       :app (make-string 33 :initial-element #\a)))))))

(test format-program-status-sanitizes-controls-and-utf8
  (let* ((sequence
           (cadr-tui:format-program-status
            (cadr-tui:make-program-status
             :state :error
             :message
             (format nil
                     "first~%second~C[31m~Cthird~C"
                     #\Escape
                     (code-char #x9b)
                     #\Tab))))
         (message
           (decode-program-status-message sequence)))
    (is (string= message "first second [31m third")))
  (let* ((sequence
           (cadr-tui:format-program-status
            (cadr-tui:make-program-status
             :state :working
             :app "pi"
             :message
             (make-string
              2000
              :initial-element (code-char #xe9)))))
         (message
           (decode-program-status-message sequence)))
    (is (= (length message) 1024))
    (is
     (<=
      (length
       (sb-ext:string-to-octets
        message :external-format :utf-8))
      2048))
    (is (<= (length sequence) 4096))))

(test program-status-reply-detection
  (is
   (cadr-tui:program-status-reply-p
    (format nil "~C]7501;?~C\\" #\Escape #\Escape)))
  (is
   (cadr-tui:program-status-reply-p
    (format nil "~C]7501;?~C"
            #\Escape (code-char 7))))
  (is
   (cadr-tui:program-status-reply-p
    (format nil "~C]7501;?version=2~C\\"
            #\Escape #\Escape)))
  (is
   (not
    (cadr-tui:program-status-reply-p
     (format nil "~C]7501;state=idle~C\\"
             #\Escape #\Escape))))
  (is
   (not
    (cadr-tui:program-status-reply-p
     (format nil "~C]11;rgb:0000/0000/0000~C"
             #\Escape (code-char 7))))))

(defparameter +goal36-working+
  (format nil "~C]7501;state=working:app=pi~C\\" #\Escape #\Escape))

(defparameter +goal36-done+
  (format nil "~C]7501;state=done~C\\" #\Escape #\Escape))

(defparameter +goal36-clear+
  (format nil "~C]7501;state=clear~C\\" #\Escape #\Escape))

(defparameter +goal36-query+
  (format nil "~C]7501;?~C\\" #\Escape #\Escape))

(defparameter +goal36-reply-bel+
  (format nil "~C]7501;?~C" #\Escape (code-char 7)))

(defparameter +goal36-da+
  (format nil "~C[?62;4;52c" #\Escape))

(sb-alien:define-alien-routine
    ("grantpt" goal36-grantpt)
    sb-alien:int
  (fd sb-alien:int))

(sb-alien:define-alien-routine
    ("unlockpt" goal36-unlockpt)
    sb-alien:int
  (fd sb-alien:int))

(sb-alien:define-alien-routine
    ("ptsname" goal36-ptsname)
    sb-alien:c-string
  (fd sb-alien:int))

(defun goal36-count (haystack needle)
  (loop for start = 0 then (+ found (length needle))
        for found = (search needle haystack :start2 start)
        while found
        count t))

(defun goal36-captured (stream)
  (let ((text (get-output-stream-string stream)))
    (write-string text stream)
    text))

(defun goal36-call-with-status-env (cadr legacy function)
  (let ((saved-cadr (uiop:getenv "CADR_PROGRAM_STATUS"))
        (saved-legacy (uiop:getenv "PI_PROGRAM_STATUS")))
    (unwind-protect
         (progn
           (if (eq cadr :unset)
               (sb-posix:unsetenv "CADR_PROGRAM_STATUS")
               (setf (uiop:getenv "CADR_PROGRAM_STATUS") cadr))
           (if (eq legacy :unset)
               (sb-posix:unsetenv "PI_PROGRAM_STATUS")
               (setf (uiop:getenv "PI_PROGRAM_STATUS") legacy))
           (funcall function))
      (if saved-cadr
          (setf (uiop:getenv "CADR_PROGRAM_STATUS") saved-cadr)
          (sb-posix:unsetenv "CADR_PROGRAM_STATUS"))
      (if saved-legacy
          (setf (uiop:getenv "PI_PROGRAM_STATUS") saved-legacy)
          (sb-posix:unsetenv "PI_PROGRAM_STATUS")))))

(defun goal36-with-terminal (function)
  (let ((master
          (sb-posix:open
           "/dev/ptmx"
           (logior sb-posix:o-rdwr sb-posix:o-noctty)))
        (slave nil)
        (stream nil)
        (output (make-string-output-stream)))
    (unwind-protect
         (progn
           (unless (zerop (goal36-grantpt master))
             (error "grantpt failed"))
           (unless (zerop (goal36-unlockpt master))
             (error "unlockpt failed"))
           (setf slave
                 (sb-posix:open
                  (goal36-ptsname master)
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
           (let ((terminal
                   (cadr-tui:make-process-terminal
                    :input stream
                    :output output
                    :dimensions-refresh-function (lambda () nil)
                    :windows-vt-input-function (lambda () nil))))
             (unwind-protect
                  (progn
                    (cadr-tui:terminal-start terminal)
                    (funcall
                     function terminal output
                     (lambda (text)
                       (cadr-tui::write-octets-to-fd
                        master
                        (sb-ext:string-to-octets
                         text :external-format :utf-8))
                       (cadr-tui:terminal-read-input terminal))))
               (when (cadr-tui::process-terminal-started-p terminal)
                 (ignore-errors (cadr-tui:terminal-stop terminal)))
               (cadr-tui::disarm-terminal-exit-restore terminal))))
      (when stream (close stream :abort t))
      (when slave (ignore-errors (sb-posix:close slave)))
      (ignore-errors (sb-posix:close master)))))

(defun goal36-run (cadr legacy function)
  (goal36-call-with-status-env
   cadr legacy
   (lambda () (goal36-with-terminal function))))

(defun goal36-report (terminal state &rest args)
  (cadr-tui:terminal-set-program-status
   terminal
   (apply #'cadr-tui:make-program-status :state state args)))

(test program-status-one-reports-without-asking
  ;; v1.4.0 terminal.test.ts: PI_PROGRAM_STATUS=1 skips the query and
  ;; writes the latest status. The runtime name is CADR_PROGRAM_STATUS.
  (goal36-run
   "1" :unset
   (lambda (terminal output send)
     (declare (ignore send))
     (let ((started (goal36-captured output)))
       (is (zerop (goal36-count started +goal36-query+)))
       (is (search (format nil "~C[>7u~C[?u~C[c"
                           #\Escape #\Escape #\Escape)
                   started)))
     (goal36-report terminal :working :app "pi")
     (is (search +goal36-working+ (goal36-captured output))))))

(test program-status-zero-never-reports
  (goal36-run
   "0" :unset
   (lambda (terminal output send)
     (is (zerop (goal36-count (goal36-captured output) +goal36-query+)))
     (goal36-report terminal :working :app "pi")
     (is (zerop (goal36-count (goal36-captured output) +goal36-working+)))
     (is (string= "" (funcall send +goal36-query+)))
     (is (zerop (goal36-count (goal36-captured output) +goal36-working+))))))

(test program-status-reports-after-the-terminal-answers-before-da
  ;; Unset, empty, and any value other than exact "1" or "0" query.
  (dolist (value '(:unset "" "true" "2"))
    (goal36-run
     value :unset
     (lambda (terminal output send)
       (is (= 1 (goal36-count (goal36-captured output) +goal36-query+)))
       (goal36-report terminal :working :app "pi")
       (is (zerop (goal36-count (goal36-captured output) +goal36-working+)))
       (is (string= "" (funcall send +goal36-query+)))
       (is (= 1 (goal36-count (goal36-captured output) +goal36-working+)))
       (is (string= "" (funcall send +goal36-da+)))
       (goal36-report terminal :done)
       (let ((text (goal36-captured output)))
         (is (= 1 (goal36-count text +goal36-working+)))
         (is (search +goal36-done+ text)))))))

(test program-status-da-first-swallows-a-late-reply
  (goal36-run
   :unset :unset
   (lambda (terminal output send)
     (is (string= "" (funcall send +goal36-da+)))
     (is (search (format nil "~C[>4;2m" #\Escape)
                 (goal36-captured output)))
     (is (string= "" (funcall send +goal36-reply-bel+)))
     (goal36-report terminal :working :app "pi")
     (is (zerop (goal36-count (goal36-captured output) +goal36-working+))))))

(test program-status-restart-does-not-let-an-old-da-end-the-query
  (goal36-run
   :unset :unset
   (lambda (terminal output send)
     (goal36-report terminal :working :app "pi")
     (cadr-tui:terminal-stop terminal)
     (cadr-tui:terminal-start terminal)
     (is (string= "" (funcall send +goal36-da+)))
     (is (zerop (goal36-count (goal36-captured output) +goal36-working+)))
     (is (string= "" (funcall send +goal36-query+)))
     (is (= 1 (goal36-count (goal36-captured output) +goal36-working+)))
     (is (string= "" (funcall send +goal36-da+))))))

(test program-status-stop-clears-and-asks-again
  (goal36-run
   :unset :unset
   (lambda (terminal output send)
     (goal36-report terminal :working :app "pi")
     (is (string= "" (funcall send +goal36-query+)))
     (cadr-tui:terminal-stop terminal)
     (is (search +goal36-clear+ (goal36-captured output)))
     (let ((before (goal36-count (goal36-captured output) +goal36-working+)))
       (goal36-report terminal :working :app "pi")
       (is (= before (goal36-count (goal36-captured output) +goal36-working+))))
     (cadr-tui:terminal-start terminal)
     (is (string= "" (funcall send +goal36-query+)))
     (is (= 2 (goal36-count (goal36-captured output) +goal36-working+))))))

(test program-status-ignores-the-legacy-name
  (goal36-run
   :unset "1"
   (lambda (terminal output send)
     (declare (ignore send))
     (is (= 1 (goal36-count (goal36-captured output) +goal36-query+)))
     (goal36-report terminal :working :app "pi")
     (is (zerop (goal36-count (goal36-captured output) +goal36-working+)))))
  (goal36-run
   "1" "0"
   (lambda (terminal output send)
     (declare (ignore send))
     (is (zerop (goal36-count (goal36-captured output) +goal36-query+)))
     (goal36-report terminal :working :app "pi")
     (is (search +goal36-working+ (goal36-captured output))))))
