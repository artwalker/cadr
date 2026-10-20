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
