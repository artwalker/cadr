;;; pi@71023aec1 utils/output-files.ts. Truncated tool output can contain
;;; private data, so the file is created mode #o600 and O_EXCL. O_EXCL fails
;;; when the name already exists, including when that name is a symlink.
(in-package #:cadr-cli)

(defun output-file-name (prefix extension)
  (format nil "~A-~A~A"
          prefix
          (cadr-ai:octets-hex (cadr-ai::secure-random-bytes 8))
          extension))

(defun exclusive-output-stream
    (path &key (element-type 'character) (external-format :utf-8))
  (let ((descriptor
          (sb-posix:open
           (namestring path)
           (logior sb-posix:o-wronly
                   sb-posix:o-creat
                   sb-posix:o-excl)
           #o600)))
    (apply #'sb-sys:make-fd-stream
           descriptor
           :output t
           :element-type element-type
           :buffering :full
           :auto-close t
           :name (pathname path)
           (if (subtypep element-type 'character)
               (list :external-format external-format)
               nil))))

(defun open-output-file-stream
    (prefix extension &key (element-type 'character)
                           (external-format :utf-8))
  (loop repeat 8
        for path = (merge-pathnames
                    (output-file-name prefix extension)
                    (uiop:temporary-directory))
        do (handler-case
               (return
                 (values path
                         (exclusive-output-stream
                          path
                          :element-type element-type
                          :external-format external-format)))
             (sb-posix:syscall-error (condition)
               (unless (= (sb-posix:syscall-errno condition)
                          sb-posix:eexist)
                 (error condition))))
        finally (error "Unable to allocate an output file")))

(defun write-output-file (prefix extension data)
  (let ((binary-p (not (stringp data))))
    (multiple-value-bind (path stream)
        (open-output-file-stream
         prefix extension
         :element-type (if binary-p '(unsigned-byte 8) 'character))
      (unwind-protect
           (progn
             (if binary-p
                 (write-sequence data stream)
                 (write-string data stream))
             (finish-output stream))
        (when (open-stream-p stream)
          (close stream)))
      (namestring path))))
