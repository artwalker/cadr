(in-package #:cadr-cli)

(defun escape-html (text)
  (with-output-to-string (output)
    (loop for character across text
          do
          (case character
            (#\& (write-string "&amp;" output))
            (#\< (write-string "&lt;" output))
            (#\> (write-string "&gt;" output))
            (#\" (write-string "&quot;" output))
            (#\' (write-string "&#39;" output))
            (otherwise
             (write-char character output))))))

(defun strip-c0-controls (text)
  (remove-if
   (lambda (character)
     (let ((code (char-code character)))
       (or (< code #x20)
           (= code #x7f))))
   text))

(defun safe-html-url (url &key image-p)
  (let* ((clean (strip-c0-controls url))
         (lower (string-downcase clean))
         (colon (position #\: lower)))
    (when
        (or
         (null colon)
         (uiop:string-prefix-p "#" lower)
         (uiop:string-prefix-p "/" lower)
         (some
          (lambda (prefix)
            (uiop:string-prefix-p prefix lower))
          '("http:" "https:" "mailto:"))
         (and image-p
              (some
               (lambda (prefix)
                 (uiop:string-prefix-p prefix lower))
               '("data:image/png;base64,"
                 "data:image/jpeg;base64,"
                 "data:image/gif;base64,"
                 "data:image/webp;base64,"))))
      (escape-html clean))))

(defun experimental-features-enabled-p
    (&optional
       (value (or (uiop:getenv "CADR_EXPERIMENTAL")
                  (uiop:getenv "PI_EXPERIMENTAL"))))
  (string= (or value "") "1"))

(defun shell-quote (text)
  (if (and
       (plusp (length text))
       (every
        (lambda (character)
          (or (alphanumericp character)
              (find character "_./:-")))
        text))
      text
      (format nil "'~A'"
              (cadr-ai::replace-all
               text "'" "'\\''"))))
