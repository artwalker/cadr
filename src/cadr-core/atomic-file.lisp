(in-package #:cadr-core)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sb-posix))

(defun validate-durability (durability)
  (unless (member durability '(:none :flush))
    (error "Unsupported durability policy: ~S" durability))
  durability)

(defun atomic-temporary-path (path)
  (make-pathname
   :name
   (format nil ".~A.cadr-~D-~D"
           (or (pathname-name path) "file")
           (sb-posix:getpid)
           (random most-positive-fixnum))
   :type "tmp"
   :defaults path))

(defun apply-file-mode (path mode)
  (when mode
    (sb-posix:chmod (namestring path) mode))
  path)

(defun call-with-atomic-replacement
    (path writer &key mode (durability :flush))
  "Write a sibling temporary path and atomically replace PATH.

WRITER receives the temporary pathname.  MODE is NIL for an intentionally
public/default-mode artifact or an explicit numeric mode such as #o600."
  (unless (functionp writer)
    (error 'type-error :datum writer :expected-type 'function))
  (validate-durability durability)
  (ensure-directories-exist path)
  (let ((temporary (atomic-temporary-path path)))
    (unwind-protect
         (progn
           (funcall writer temporary)
           (unless (probe-file temporary)
             (error "Atomic writer did not create ~A" temporary))
           (apply-file-mode temporary mode)
           (uiop:rename-file-overwriting-target temporary path)
           (apply-file-mode path mode)
           path)
      (when (probe-file temporary)
        (delete-file temporary)))))

(defun call-with-atomic-output-file
    (path writer
     &key mode (durability :flush) (external-format :utf-8))
  (call-with-atomic-replacement
   path
   (lambda (temporary)
     (with-open-file
         (stream temporary
                 :direction :output
                 :if-exists :error
                 :if-does-not-exist :create
                 :external-format external-format)
       (funcall writer stream)
       (when (eq durability :flush)
         (finish-output stream))))
   :mode mode :durability durability))

(defun atomic-write-string
    (path content &key mode (durability :flush)
                        (external-format :utf-8))
  (unless (stringp content)
    (error 'type-error :datum content :expected-type 'string))
  (call-with-atomic-output-file
   path
   (lambda (stream) (write-string content stream))
   :mode mode :durability durability
   :external-format external-format))

(defun atomic-copy-file
    (source target &key mode (durability :flush))
  (call-with-atomic-replacement
   target
   (lambda (temporary)
     (uiop:copy-file source temporary))
   :mode mode :durability durability))

(defun append-string-to-file
    (path content &key mode (durability :flush)
                        (external-format :utf-8))
  "Append to an append-only artifact with explicit mode and durability.

This is deliberately not named atomic: append-only report streams cannot use
rename-based replacement without changing their concurrency semantics."
  (unless (stringp content)
    (error 'type-error :datum content :expected-type 'string))
  (validate-durability durability)
  (ensure-directories-exist path)
  (with-open-file
      (stream path
              :direction :output
              :if-exists :append
              :if-does-not-exist :create
              :external-format external-format)
    (write-string content stream)
    (when (eq durability :flush)
      (finish-output stream)))
  (apply-file-mode path mode)
  path)
