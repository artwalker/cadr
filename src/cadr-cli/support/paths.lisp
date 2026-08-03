(in-package #:cadr-cli)

(defun strip-json-comments (input)
  (with-output-to-string (output)
    (let ((index 0)
          (in-string-p nil)
          (escaped-p nil))
      (loop while (< index (length input))
            for character = (char input index)
            do
            (cond
              (in-string-p
               (write-char character output)
               (cond
                 (escaped-p (setf escaped-p nil))
                 ((char= character #\\) (setf escaped-p t))
                 ((char= character #\") (setf in-string-p nil)))
               (incf index))
              ((char= character #\")
               (setf in-string-p t)
               (write-char character output)
               (incf index))
              ((and (char= character #\/)
                    (< (1+ index) (length input))
                    (char= #\/ (char input (1+ index))))
               (setf index (or (position #\Newline input :start (+ index 2))
                               (length input))))
              ((char= character #\,)
               (let ((next (position-if-not
                            (lambda (item)
                              (find item '(#\Space #\Tab #\Newline #\Return)))
                            input :start (1+ index))))
                 (if (and next (find (char input next) "}]") )
                     (incf index)
                     (progn (write-char character output) (incf index)))))
              (t (write-char character output) (incf index)))))))

(defparameter +unicode-path-spaces+
  (mapcar #'code-char
          '(#x00a0 #x2000 #x2001 #x2002 #x2003 #x2004 #x2005 #x2006
            #x2007 #x2008 #x2009 #x200a #x202f #x205f #x3000)))

(defun decode-file-url-path (text)
  (let ((octets
          (make-array 0 :element-type '(unsigned-byte 8)
                        :adjustable t :fill-pointer 0)))
    (loop with index = 0
          while (< index (length text))
          do (if (char= #\% (char text index))
                 (progn
                   (when (> (+ index 3) (length text))
                     (error "Invalid percent escape in file URL"))
                   (let ((high (digit-char-p (char text (1+ index)) 16))
                         (low (digit-char-p (char text (+ index 2)) 16)))
                     (unless (and high low)
                       (error "Invalid percent escape in file URL"))
                     (vector-push-extend (+ (ash high 4) low) octets))
                   (incf index 3))
                 (progn
                   (loop for octet across
                         (cadr-ai::utf8-octets (string (char text index)))
                         do (vector-push-extend octet octets))
                   (incf index))))
    (cadr-ai::utf8-string octets)))

(defun normalize-path-input
    (input &key trim-p (expand-tilde-p t) home-directory
                strip-at-prefix-p normalize-unicode-spaces-p)
  (let ((value (if trim-p
                   (string-trim '(#\Space #\Tab #\Newline #\Return) input)
                   input)))
    (when normalize-unicode-spaces-p
      (setf value
            (map 'string
                 (lambda (character)
                   (if (member character +unicode-path-spaces+)
                       #\Space character))
                 value)))
    (when (and strip-at-prefix-p (uiop:string-prefix-p "@" value))
      (setf value (subseq value 1)))
    (when expand-tilde-p
      (let ((home (or home-directory (namestring (user-homedir-pathname)))))
        (cond
          ((string= value "~") (setf value home))
          ((or (uiop:string-prefix-p "~/" value)
               (uiop:string-prefix-p "~\\" value))
           (setf value (namestring
                        (merge-pathnames (subseq value 2)
                                         (uiop:ensure-directory-pathname home))))))))
    (when (uiop:string-prefix-p "file://" value)
      (setf value (decode-file-url-path (subseq value 7))))
    value))

(defun resolve-path-input
    (input &optional (base-directory (uiop:getcwd)) &rest options)
  (let* ((normalized (apply #'normalize-path-input input options))
         (pathname (pathname normalized)))
    (namestring
     (if (uiop:absolute-pathname-p pathname)
         pathname
         (merge-pathnames pathname
                          (uiop:ensure-directory-pathname base-directory))))))

(defun mark-path-ignored-by-cloud-sync (path &key runner)
  (let ((commands
          (cond
            ((uiop:os-macosx-p)
             (list (list "xattr" "-w" "com.dropbox.ignored" "1" path)
                   (list "xattr" "-w" "com.apple.fileprovider.ignore#P" "1" path)))
            ((uiop:os-unix-p)
             (list (list "setfattr" "-n" "user.com.dropbox.ignored"
                         "-v" "1" path))))))
    (dolist (command commands)
      (ignore-errors
        (if runner
            (funcall runner command)
            (uiop:run-program command :output nil :error-output nil
                                      :ignore-error-status t)))))
  nil)
