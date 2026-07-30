(in-package #:cadr-cli)

(defparameter +narrow-no-break-space+ (code-char #x202f))

(defun unicode-space-p (character)
  (let ((code (char-code character)))
    (or (= code #xa0)
        (<= #x2000 code #x200a)
        (= code #x202f)
        (= code #x205f)
        (= code #x3000))))

(defun normalize-unicode-spaces (text)
  (map 'string
       (lambda (character)
         (if (unicode-space-p character)
             #\Space
             character))
       text))

(defun normalize-tool-path-text (path)
  (let* ((without-at
           (if (and (> (length path) 1)
                    (char= #\@ (char path 0)))
               (subseq path 1)
               path))
         (spaces (normalize-unicode-spaces without-at)))
    (if (and (plusp (length spaces))
             (char= #\~ (char spaces 0))
             (or (= 1 (length spaces))
                 (char= #\/ (char spaces 1))))
        (namestring
         (merge-pathnames
          (if (= 1 (length spaces))
              ""
              (subseq spaces 2))
          (user-homedir-pathname)))
        spaces)))

(defun resolve-tool-path (cwd path)
  (unless (and (stringp path) (plusp (length path)))
    (error "Path must be a non-empty string"))
  (let ((pathname (pathname (normalize-tool-path-text path))))
    (uiop:ensure-absolute-pathname
     (if (uiop:absolute-pathname-p pathname)
         pathname
         (merge-pathnames pathname
                          (uiop:ensure-directory-pathname cwd))))))

(defun path-variant-candidates (path)
  (let* ((text (namestring path))
         (ampm
           (cl-ppcre:regex-replace-all
            "(?i) (am|pm)\\." text
            (format nil "~C\\1." +narrow-no-break-space+)))
         (curly
           (substitute (code-char #x2019) #\' text))
         (nfd
           (with-output-to-string (output)
             (loop for character across text
                   do
                   (case (char-code character)
                     (#xe0 (write-string
                            (format nil "a~C" (code-char #x300))
                            output))
                     (#xe1 (write-string
                            (format nil "a~C" (code-char #x301))
                            output))
                     (#xe8 (write-string
                            (format nil "e~C" (code-char #x300))
                            output))
                     (#xe9 (write-string
                            (format nil "e~C" (code-char #x301))
                            output))
                     (#xed (write-string
                            (format nil "i~C" (code-char #x301))
                            output))
                     (#xf3 (write-string
                            (format nil "o~C" (code-char #x301))
                            output))
                     (#xfa (write-string
                            (format nil "u~C" (code-char #x301))
                            output))
                     (otherwise
                      (write-char character output)))))))
    (remove-duplicates
     (list text ampm nfd curly
           (substitute (code-char #x2019) #\' ampm)
           (substitute (code-char #x2019) #\' nfd))
     :test #'string=)))

(defun resolve-readable-tool-path (cwd path)
  (let ((resolved (resolve-tool-path cwd path)))
    (or
     (loop for candidate in (path-variant-candidates resolved)
           when (probe-file candidate)
             return (pathname candidate))
     resolved)))

(defun relative-posix-path (path cwd)
  (substitute #\/ #\\
              (enough-namestring
               path (uiop:ensure-directory-pathname cwd))))

(defun canonicalize-path (path)
  (or (ignore-errors (truename path))
      (pathname path)))

(defun cwd-relative-path (path cwd)
  (let* ((base
           (uiop:ensure-directory-pathname
            (uiop:ensure-absolute-pathname cwd)))
         (absolute
           (uiop:ensure-absolute-pathname path base)))
    (let ((relative
            (substitute #\/ #\\
                        (enough-namestring absolute base))))
      (unless (or (string= relative "..")
                  (uiop:string-prefix-p "../" relative)
                  (uiop:absolute-pathname-p
                   (pathname relative)))
        relative))))

(defun local-path-p (value)
  (let ((text
          (string-downcase
           (string-trim '(#\Space #\Tab) value))))
    (not
     (some
      (lambda (prefix)
        (uiop:string-prefix-p prefix text))
      '("npm:" "git:" "github:" "http:"
        "https:" "ssh:")))))

(defun hex-octet (text position)
  (let ((high (digit-char-p (char text position) 16))
        (low (digit-char-p (char text (1+ position)) 16)))
    (unless (and high low)
      (error "Invalid percent escape in file URL"))
    (+ (ash high 4) low)))

(defun percent-decode-path (text)
  (let ((octets
          (make-array
           0 :element-type '(unsigned-byte 8)
           :adjustable t :fill-pointer 0)))
    (loop with index = 0
          while (< index (length text))
          do
          (if (char= #\% (char text index))
              (progn
                (when (> (+ index 3) (length text))
                  (error "Invalid percent escape in file URL"))
                (vector-push-extend
                 (hex-octet text (1+ index)) octets)
                (incf index 3))
              (let ((encoded
                      (cadr-ai::utf8-octets
                       (string (char text index)))))
                (loop for octet across encoded
                      do (vector-push-extend octet octets))
                (incf index))))
    #+sbcl
    (sb-ext:octets-to-string octets :external-format :utf-8)
    #-sbcl
    (map 'string #'code-char octets)))

(defun resolve-general-path (path &optional (base (uiop:getcwd)))
  (let* ((normalized (normalize-tool-path-text path))
         (file-url-p
           (uiop:string-prefix-p "file://" normalized))
         (decoded
           (if file-url-p
               (percent-decode-path
                (subseq normalized
                        (length "file://")))
               normalized))
         (pathname (pathname decoded)))
    (uiop:ensure-absolute-pathname
     pathname
     (uiop:ensure-directory-pathname base))))

(defun required-string (arguments key)
  (let ((value (cadr-ai::json-get arguments key)))
    (unless (stringp value)
      (error "~A must be a string" key))
    value))

(defun optional-integer (arguments key &optional default)
  (let ((value (cadr-ai::json-get arguments key default)))
    (unless (or (null value) (integerp value))
      (error "~A must be an integer" key))
    value))

(defun object-schema (properties required)
  (cadr-ai::json-object
   "type" "object"
   "properties" properties
   "required" (coerce required 'vector)
   "additionalProperties" nil))

(defun string-property (&optional description)
  (let ((property (cadr-ai::json-object "type" "string")))
    (when description
      (cadr-ai::json-put property "description" description))
    property))

(defun number-property ()
  (cadr-ai::json-object "type" "number"))

(defun boolean-property ()
  (cadr-ai::json-object "type" "boolean"))

(defparameter *file-mutation-locks*
  (make-hash-table :test #'equal))
(defparameter *file-mutation-locks-guard*
  (sb-thread:make-mutex :name "cadr file mutation lock registry"))

(defun mutation-queue-key (path)
  (namestring
   (or (ignore-errors (truename path))
       (uiop:ensure-absolute-pathname path))))

(defun file-mutation-lock (path)
  (let ((key (mutation-queue-key path)))
    (sb-thread:with-mutex (*file-mutation-locks-guard*)
      (or (gethash key *file-mutation-locks*)
          (setf
           (gethash key *file-mutation-locks*)
           (sb-thread:make-mutex
            :name (format nil "cadr mutation ~A" key)))))))

(defun with-file-mutation-queue (path function)
  (sb-thread:with-mutex ((file-mutation-lock path))
    (funcall function)))
