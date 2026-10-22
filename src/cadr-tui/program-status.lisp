(in-package #:cadr-tui)

;;; Program Status Protocol (OSC 7501). Spec:
;;; https://www.superlogical.com/rex/docs/build/program-status
;;; Baseline: packages/tui/src/program-status.ts (pi@71023aec).

(defstruct (program-status
            (:constructor make-program-status
                (&key (state :idle) app kind message))
            (:copier nil))
  (state :idle :type
         (member :idle :working :blocked :done :error :clear))
  (app nil :type (or null string))
  (kind nil :type
        (or null (member :permission :question :auth)))
  (message nil :type (or null string)))

(defparameter +program-status-query+
  (format nil "~C]7501;?~C\\" #\Escape #\Escape))

(defparameter +program-status-app-scanner+
  (cl-ppcre:create-scanner "^[A-Za-z0-9_.+-]{1,32}$"))

(defparameter +program-status-control-scanner+
  (cl-ppcre:create-scanner
   "[\\x00-\\x1f\\x7f-\\x9f]+"))

(defparameter +program-status-reply-scanner+
  (cl-ppcre:create-scanner
   (concatenate
    'string
    "^"
    (string #\Escape)
    "\\]7501;\\?[^"
    (string (code-char 7))
    (string #\Escape)
    "]*(?:"
    (string (code-char 7))
    "|"
    (string #\Escape)
    "\\\\)$")))
(defconstant +program-status-max-message-bytes+ 2048)

(defun program-status-reply-p (sequence)
  (and (stringp sequence)
       (not
        (null
         (cl-ppcre:scan
          +program-status-reply-scanner+
          sequence)))))

(defun truncate-utf8-string (text max-bytes)
  (let* ((octets
           #+sbcl
           (sb-ext:string-to-octets
            text :external-format :utf-8)
           #-sbcl
           (map 'vector #'char-code text)))
    (when (<= (length octets) max-bytes)
      (return-from truncate-utf8-string text))
    (let ((bytes 0)
          (end 0))
      (loop for character across text
            for size =
            #+sbcl
            (length
             (sb-ext:string-to-octets
              (string character)
              :external-format :utf-8))
            #-sbcl
            1
            do
            (when (> (+ bytes size) max-bytes)
              (return))
            (incf bytes size)
            (incf end))
      (subseq text 0 end))))

(defun sanitize-program-status-message (message)
  (truncate-utf8-string
   (string-trim
    '(#\Space #\Tab #\Newline #\Return)
    (cl-ppcre:regex-replace-all
     +program-status-control-scanner+
     (or message "")
     " "))
   +program-status-max-message-bytes+))

(defun program-status-utf8-base64 (text)
  (let ((bytes
          #+sbcl
          (sb-ext:string-to-octets
           text :external-format :utf-8)
          #-sbcl
          (map 'vector #'char-code text)))
    (with-output-to-string (output)
      (loop for position from 0
            below (length bytes) by 3
            for remaining =
            (- (length bytes) position)
            for first = (aref bytes position)
            for second =
            (if (> remaining 1)
                (aref bytes (1+ position))
                0)
            for third =
            (if (> remaining 2)
                (aref bytes (+ position 2))
                0)
            for value =
            (logior
             (ash first 16)
             (ash second 8)
             third)
            do
            (write-char
             (char +base64-alphabet+
                   (ldb (byte 6 18) value))
             output)
            (write-char
             (char +base64-alphabet+
                   (ldb (byte 6 12) value))
             output)
            (write-char
             (if (> remaining 1)
                 (char
                  +base64-alphabet+
                  (ldb (byte 6 6) value))
                 #\=)
             output)
            (write-char
             (if (> remaining 2)
                 (char
                  +base64-alphabet+
                  (ldb (byte 6 0) value))
                 #\=)
             output)))))

(defun format-program-status (status)
  (let* ((state (program-status-state status))
         (pairs
           (list
            (format nil "state=~A"
                    (string-downcase
                     (symbol-name state)))))
         (app (program-status-app status))
         (kind (program-status-kind status))
         (message
           (sanitize-program-status-message
            (program-status-message status))))
    (when (and app
               (cl-ppcre:scan
                +program-status-app-scanner+
                app))
      (setf pairs
            (nconc pairs
                   (list (format nil "app=~A" app)))))
    (when (and (eq state :blocked) kind)
      (setf pairs
            (nconc pairs
                   (list
                    (format nil "kind=~A"
                            (string-downcase
                             (symbol-name kind)))))))
    (when (plusp (length message))
      (setf pairs
            (nconc pairs
                   (list
                    (format nil "msg=~A"
                            (program-status-utf8-base64
                             message))))))
    (format nil "~C]7501;~A~C\\"
            #\Escape
            (format nil "~{~A~^:~}" pairs)
            #\Escape)))