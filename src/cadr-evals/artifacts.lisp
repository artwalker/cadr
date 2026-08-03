(in-package #:cadr-evals)

(eval-when (:compile-toplevel
            :load-toplevel
            :execute)
  (require :sb-posix))

(defstruct eval-attachment
  (name "" :type string)
  (content-type "application/octet-stream"
                :type string)
  (body "" :type string))

(defstruct eval-artifact
  type
  (run-id "" :type string)
  (attachments nil :type list))

(defstruct eval-artifact-reference
  (name "" :type string)
  (path "" :type string))

(defun artifact-type-error (datum expected-type)
  (error 'type-error
         :datum datum
         :expected-type expected-type))

(defun valid-artifact-name-p (name)
  (and
   (stringp name)
   (plusp (length name))
   (not (member name '("." "..")
                :test #'string=))
   (not (find #\/ name))
   (not (find #\\ name))))

(defun validate-eval-attachment (attachment)
  (unless
      (typep attachment 'eval-attachment)
    (artifact-type-error
     attachment 'eval-attachment))
  (unless
      (valid-artifact-name-p
       (eval-attachment-name attachment))
    (artifact-type-error
     (eval-attachment-name attachment)
     '(and string
       (satisfies valid-artifact-name-p))))
  attachment)

(defun record-eval-session-artifact (metadata)
  (let ((snapshot
          (and
           (hash-table-p metadata)
           (cadr-ai::json-get
            metadata
            +cadr-session-snapshot-artifact+))))
    (when snapshot
      (let ((run-id
              (cadr-ai::json-get
               metadata "runId")))
        (unless
            (and (stringp run-id)
                 (stringp snapshot))
          (artifact-type-error
           metadata
           '(and hash-table
             (satisfies
              valid-eval-session-artifact-metadata-p))))
        (make-eval-artifact
         :type :session
         :run-id run-id
         :attachments
         (list
          (make-eval-attachment
           :name "session.jsonl"
           :content-type
           "application/jsonl"
           :body snapshot)))))))

(defun record-eval-source-artifact
    (run-id attachment)
  (unless (stringp run-id)
    (artifact-type-error run-id 'string))
  (unless (typep attachment 'eval-attachment)
    (artifact-type-error
     attachment 'eval-attachment))
  (make-eval-artifact
   :type :source
   :run-id run-id
   :attachments (list attachment)))

(defun sha256-hex (text)
  (with-output-to-string (stream)
    (loop
      for octet across
      (cadr-ai::sha256-bytes
       (sb-ext:string-to-octets
        text :external-format :utf-8))
      do (format stream "~(~2,'0X~)" octet))))

(defun write-eval-artifact-file
    (path body)
  (cadr-core:atomic-write-string
   path body :mode #o600 :durability :flush))

(defun persist-eval-artifact-references
    (artifacts run-id artifact-directory)
  (unless (stringp run-id)
    (artifact-type-error run-id 'string))
  (let ((root
          (uiop:ensure-directory-pathname
           artifact-directory))
        (digest
          (sha256-hex run-id))
        (references nil))
    (dolist (artifact artifacts)
      (when
          (and
           (typep artifact 'eval-artifact)
           (member
            (eval-artifact-type artifact)
            '(:session :source))
           (string=
            run-id
            (eval-artifact-run-id artifact)))
        (let ((category
                (if
                    (eq
                     :session
                     (eval-artifact-type artifact))
                    "sessions"
                    "sources")))
          (let ((directory
                  (merge-pathnames
                   (format nil "~A/~A/"
                           category digest)
                   root)))
            (ensure-directories-exist
             (merge-pathnames "anchor"
                              directory))
            (sb-posix:chmod
             (namestring directory)
             #o700))
          (dolist
              (attachment
               (eval-artifact-attachments
                artifact))
            (validate-eval-attachment attachment)
            (let* ((name
                     (eval-attachment-name
                      attachment))
                   (relative
                     (format nil "~A/~A/~A"
                             category digest name))
                   (path
                     (merge-pathnames
                      relative root)))
              (write-eval-artifact-file
               path
               (eval-attachment-body
                attachment))
              (push
               (make-eval-artifact-reference
                :name name
                :path relative)
               references))))))
    (nreverse references)))
