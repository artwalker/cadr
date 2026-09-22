(in-package #:cadr-cli)

(defparameter +credential-environment-names+
  '("ANTHROPIC_AUTH_TOKEN"
    "ANTHROPIC_OAUTH_TOKEN"
    "AWS_ACCESS_KEY_ID"
    "AWS_BEARER_TOKEN_BEDROCK"
    "AWS_SECRET_ACCESS_KEY"
    "AWS_SESSION_TOKEN"
    "GOOGLE_CLOUD_API_KEY"))

(defun crash-known-secrets
    (&optional (arguments (uiop:command-line-arguments)))
  (remove-duplicates
   (remove-if-not
    #'cadr-ai::non-empty-string-p
    (append
     (cadr-ai::command-line-api-key-secrets arguments)
     (stored-auth-secrets)
     (loop for definition in (cadr-ai:list-provider-definitions)
           for name =
             (cadr-ai:provider-definition-key-environment definition)
           when name collect (uiop:getenv name))
     (loop for name in +credential-environment-names+
           collect (uiop:getenv name))))
   :test #'string=))

(defun redact-crash-diagnostic (text secrets)
  (let ((redacted (cadr-ai:redact-secrets text secrets)))
    (dolist
        (rule
         '(("(?i)authorization[[:space:]]*[:=][^\r\n]*"
            . "Authorization: [REDACTED]")
           ("(?i)(bearer|basic)[[:space:]]+[A-Za-z0-9._~+/=-]+"
            . "Authorization [REDACTED]")
           ("(?i)[\"']?(access|refresh|api[-_]?key|token|client[-_]?secret)[\"']?[[:space:]]*[:=][[:space:]]*[\"']?[^\"'[:space:](),]+"
            . "[REDACTED-CREDENTIAL]")))
      (setf redacted
            (cl-ppcre:regex-replace-all
             (car rule) redacted (cdr rule))))
    redacted))

(defun call-with-fatal-condition-boundary
    (function &key
                (program-name "cadr")
                (crash-directory
                  (cadr-ai::default-crash-directory))
                secrets
                (exit-function #'uiop:quit))
  (cadr-ai::call-with-fatal-condition-boundary
   function
   :program-name program-name
   :crash-directory crash-directory
   :secrets
   (remove-duplicates
    (append secrets (crash-known-secrets))
    :test #'string=)
   :redactor #'redact-crash-diagnostic
   :diagnostic-annotation #'crash-extension-diagnostic-annotation
   :exit-function exit-function))

(defparameter *crash-extensions* nil
  "Loaded extensions whose paths may appear in a fatal backtrace.")

(defstruct crash-extension
  (path "" :type string)
  (resolved-path "" :type string)
  (origin "" :type string)
  (source "" :type string)
  (base-dir "" :type string))

(defun crash-extension-label (extension)
  (if (and (string= (crash-extension-origin extension) "package")
           (plusp (length (crash-extension-source extension))))
      (crash-extension-source extension)
      (crash-extension-path extension)))

(defun normalize-stack-path (value)
  (string-right-trim "/" (substitute #\/ #\\ (or value ""))))

(defun decode-stack-percent (text)
  (with-output-to-string (output)
    (loop with index = 0
          while (< index (length text))
          do (let ((character (char text index)))
               (if (and (char= character #\%)
                        (<= (+ index 3) (length text))
                        (digit-char-p (char text (+ index 1)) 16)
                        (digit-char-p (char text (+ index 2)) 16))
                   (progn
                     (write-char
                      (code-char
                       (parse-integer text :start (1+ index) :end (+ index 3) :radix 16))
                      output)
                     (incf index 3))
                   (progn
                     (write-char character output)
                     (incf index)))))))

(defun stack-path-boundary-p (next)
  (or (null next)
      (char= next #\:)
      (char= next #\))
      (member next '(#\Space #\Tab #\Newline #\Return))))

(defun stack-contains-path (stack target include-descendants-p)
  (let* ((normalized (normalize-stack-path target))
         (case-insensitive-p
           (and (>= (length normalized) 2)
                (alpha-char-p (char normalized 0))
                (char= (char normalized 1) #\:)))
         (haystack
           (if case-insensitive-p (string-downcase stack) stack))
         (needle
           (if case-insensitive-p
               (string-downcase normalized)
               normalized)))
    (when (or (zerop (length needle)) (char= (char needle 0) #\<))
      (return-from stack-contains-path nil))
    (if include-descendants-p
        (search (concatenate 'string needle "/") haystack)
        (loop with start = 0
              for index = (search needle haystack :start2 start)
              while index
              do (let ((next
                         (when (< (+ index (length needle)) (length haystack))
                           (char haystack (+ index (length needle))))))
                   (when (stack-path-boundary-p next)
                     (return-from stack-contains-path t))
                   (setf start (+ index (length needle)))))
    )))

(defun crash-extension-single-file-p (extension)
  (let ((source (crash-extension-source extension)))
    (and (string= (crash-extension-origin extension) "package")
         (plusp (length source))
         (not (or (uiop:string-prefix-p "npm:" source)
                  (uiop:string-prefix-p "git:" source)
                  (uiop:string-prefix-p "http://" source)
                  (uiop:string-prefix-p "https://" source)
                  (uiop:string-prefix-p "ssh://" source)))
         (cl-ppcre:scan "\\.[cm]?[jt]s$" source))))

(defun crash-extension-matches-stack-p (extension stack)
  (let* ((resolved (normalize-stack-path (crash-extension-resolved-path extension)))
         (package-root
           (and (string= (crash-extension-origin extension) "package")
                (not (crash-extension-single-file-p extension))
                (plusp (length (crash-extension-base-dir extension)))
                (normalize-stack-path (crash-extension-base-dir extension))))
         (slash (position #\/ resolved :from-end t))
         (directory-entry-p
           (cl-ppcre:scan "/index\\.[cm]?[jt]s$" resolved)))
    (cond
      (package-root
       (stack-contains-path stack package-root t))
      ((and directory-entry-p slash)
       (stack-contains-path stack (subseq resolved 0 slash) t))
      (t
       (stack-contains-path stack resolved nil)))))

(defun find-extension-stack-matches (stack extensions)
  (when (and (stringp stack) (plusp (length stack)))
    (let* ((lines (uiop:split-string stack :separator '(#\Newline)))
           (frames
             (decode-stack-percent
              (substitute
               #\/ #\\
               (format nil "~{~A~%~}" (rest lines)))))
           (seen (make-hash-table :test #'equal))
           (matches nil))
      (dolist (extension extensions)
        (when (crash-extension-matches-stack-p extension frames)
          (let ((label (crash-extension-label extension)))
            (unless (gethash label seen)
              (setf (gethash label seen) t)
              (push label matches)))))
      (nreverse matches))))

(defun format-crash-extension-hint (matches)
  (let ((labels
          (remove-if
           (lambda (label)
             (or (not (stringp label)) (zerop (length label))))
           matches)))
    (when labels
      (let ((quoted (mapcar (lambda (label) (format nil "`~A`" label)) labels)))
        (format nil
                "A stack frame came from loaded ~A ~A, which may be involved. Try disabling ~A with `cadr config`, or run `cadr -ne` to confirm."
                (if (= (length labels) 1) "extension" "extensions")
                (cond
                  ((= (length quoted) 1) (first quoted))
                  ((= (length quoted) 2)
                   (format nil "~A and ~A" (first quoted) (second quoted)))
                  (t
                   (format nil "~{~A~^, ~}, and ~A"
                           (butlast quoted) (first (last quoted)))))
                (if (= (length labels) 1) "it" "them"))))))

(defun crash-extensions-from-bundles (bundles)
  (loop for bundle in bundles
        for path = (cadr-agent::extension-bundle-path bundle)
        when (and (stringp path) (plusp (length path)))
          collect
          (make-crash-extension
           :path path
           :resolved-path path
           :origin "top-level")))

(defun note-loaded-crash-extensions (bundles)
  (setf *crash-extensions* (crash-extensions-from-bundles bundles)))

(defun crash-extension-diagnostic-annotation (diagnostic)
  (format-crash-extension-hint
   (find-extension-stack-matches diagnostic *crash-extensions*)))

