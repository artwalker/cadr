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
  (let* ((path-text
           (etypecase path
             (string path)
             (pathname (namestring path))))
         (without-at
           (if (and (> (length path-text) 1)
                    (char= #\@ (char path-text 0)))
               (subseq path-text 1)
               path-text))
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

(defun lexically-normalized-absolute-pathname (path)
  (let ((directory nil))
    (dolist (component (pathname-directory path))
      (cond
        ((eq component :up)
         (when (and directory
                    (stringp (first directory)))
           (pop directory)))
        ((eq component :back)
         (when (and directory
                    (stringp (first directory)))
           (pop directory)))
        (t
         (push component directory))))
    (make-pathname
     :directory (nreverse directory)
     :defaults path)))

(defun normalized-tool-directory (path)
  (uiop:ensure-directory-pathname
   (lexically-normalized-absolute-pathname
    (uiop:ensure-absolute-pathname
     (pathname (normalize-tool-path-text path))))))

(defun resolve-tool-path (cwd path)
  (let* ((path-text (normalize-tool-path-text path)))
    (unless (plusp (length path-text))
      (error "Path must be a non-empty string"))
    (let* ((pathname
             (pathname path-text))
         (absolute
           (uiop:ensure-absolute-pathname
            (if (uiop:absolute-pathname-p pathname)
                 pathname
                 (merge-pathnames
                  pathname
                  (normalized-tool-directory cwd))))))
      (lexically-normalized-absolute-pathname absolute))))

(defun execution-context-value (value operation-error)
  (when operation-error
    (error "~A" (cadr-agent:harness-operation-error-message operation-error)))
  value)

(defun resolve-execution-context-path (context cwd path)
  (multiple-value-bind (resolved operation-error)
    (cadr-agent:execution-tool-resolve-path
       context path (namestring (normalized-tool-directory cwd)))
    (execution-context-value resolved operation-error)))

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
               path (normalized-tool-directory cwd))))

(defun canonicalize-path (path)
  (or (ignore-errors (truename path))
      (pathname path)))

(defun cwd-relative-path (path cwd)
  (let* ((base
           (normalized-tool-directory cwd))
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

(defun format-path-relative-to-cwd-or-absolute (file-path cwd)
  (substitute #\/ #\\
              (or (cwd-relative-path file-path cwd)
                  (namestring
                   (uiop:ensure-absolute-pathname
                    file-path
                    (normalized-tool-directory cwd))))))

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
    (lexically-normalized-absolute-pathname
     (uiop:ensure-absolute-pathname
      pathname
      (normalized-tool-directory base)))))

(defun signal-normalized-file-operation-error
    (operation display-path condition resolved-path)
  (if (and (eq operation :read)
           resolved-path
           (search "Permission denied"
                   (princ-to-string condition)
                   :test #'char-equal))
      (error "EACCES: permission denied, access '~A'"
             (namestring resolved-path))
      (error
       (case operation
         (:read "Could not read file: ~A")
         (:write "Could not write file: ~A")
         (:edit "Could not edit file: ~A")
         ((:find :grep :glob) "Could not search path: ~A")
         (:ls "Could not list directory: ~A")
         (otherwise "Could not access path: ~A"))
       display-path)))

(defun call-with-normalized-file-operation
    (operation display-path function &key resolved-path)
  (handler-case
      (funcall function)
    (file-error (condition)
      (signal-normalized-file-operation-error
       operation display-path condition resolved-path))
    (stream-error (condition)
      (signal-normalized-file-operation-error
       operation display-path condition resolved-path))
    (type-error (condition)
      (signal-normalized-file-operation-error
       operation display-path condition resolved-path))))

(defun required-string (arguments key)
  (let ((value (cadr-ai::json-get arguments key)))
    (unless (stringp value)
      (error "~A must be a string" key))
    value))

(defun optional-string (arguments key &optional default)
  (let ((value (cadr-ai::json-get arguments key default)))
    (unless (or (null value) (stringp value))
      (error "~A must be a string" key))
    (or value default)))

(defun optional-integer (arguments key &optional default)
  (let ((value (cadr-ai::json-get arguments key default)))
    (unless (or (null value) (integerp value))
      (error "~A must be an integer" key))
    value))

(defun object-schema (properties required)
  (let ((schema
          (cadr-ai::json-object
           "type" "object"
           "properties" properties
           "additionalProperties" nil)))
    ;; Baseline TypeBox: Type.Object without a required list omits the
    ;; key entirely (core/tools/ls.ts has no required).
    (when required
      (cadr-ai::json-put
       schema "required" (coerce required 'vector)))
    schema))

(defun string-property (&optional description)
  (let ((property (cadr-ai::json-object "type" "string")))
    (when description
      (cadr-ai::json-put property "description" description))
    property))

(defun number-property (&optional description)
  (let ((property (cadr-ai::json-object "type" "number")))
    (when description
      (cadr-ai::json-put property "description" description))
    property))

(defun boolean-property (&optional description)
  (let ((property (cadr-ai::json-object "type" "boolean")))
    (when description
      (cadr-ai::json-put property "description" description))
    property))

(defun mutation-queue-key (path)
  (cadr-agent::file-mutation-queue-key path))

(defun file-mutation-lock (path)
  (cadr-agent::file-mutation-queue-lock path))

(defun with-file-mutation-queue (path function)
  (cadr-agent::with-file-mutation-queue path function))
