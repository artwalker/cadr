#!/usr/bin/env -S sbcl --script

(require :asdf)

(let ((setup
        (or (uiop:getenv "QUICKLISP_SETUP")
            (namestring
             (merge-pathnames "quicklisp/setup.lisp"
                              (user-homedir-pathname))))))
  (unless (probe-file setup)
    (error "Quicklisp setup not found: ~A" setup))
  (load setup))

(defparameter *root*
  (uiop:pathname-parent-directory-pathname
   (uiop:pathname-directory-pathname
    (truename *load-truename*))))

(asdf:load-asd (truename (merge-pathnames "cadr-core.asd" *root*)))
(asdf:load-asd (truename (merge-pathnames "cadr-telemetry.asd" *root*)))
(asdf:load-asd (truename (merge-pathnames "cadr-ai.asd" *root*)))
(asdf:load-system "cadr-ai")

(defparameter *catalog-directory*
  (merge-pathnames
   "test/fixtures/catalogs/provider-data/"
   *root*))

(defparameter *generated-path*
  (merge-pathnames
   "src/cadr-ai/image-models.generated.lisp"
   *root*))

(defun json-get (object key &optional default)
  (if (hash-table-p object)
      (gethash key object default)
      default))

(defun sorted-keys (object)
  (sort
   (loop for key being the hash-keys of object collect key)
   #'string<))

(defun number-or-zero (value)
  (if (numberp value)
      (coerce value 'double-float)
      0d0))

(defun keyword-list (values)
  (loop for value across values
        collect
        (intern
         (substitute #\- #\_ (string-upcase value))
         :keyword)))

(defun keyword-value (value)
  (intern
   (substitute #\- #\_ (string-upcase value))
   :keyword))

(defun header-alist (object)
  (when (hash-table-p object)
    (loop for key in (sorted-keys object)
          collect (cons key (json-get object key)))))

(defun resize-limits-plist (object)
  (when (hash-table-p object)
    (list :jpeg-quality (json-get object "jpegQuality")
          :max-bytes (json-get object "maxBytes")
          :max-height (json-get object "maxHeight")
          :max-width (json-get object "maxWidth"))))

(defun input-limits-plist (object)
  (when (hash-table-p object)
    (let ((images (json-get object "images"))
          (limits nil))
      (when (numberp (json-get object "maxRequestBytes"))
        (setf limits
              (list :max-request-bytes
                    (json-get object "maxRequestBytes"))))
      (when (hash-table-p images)
        (let ((image-limits nil))
          (when (numberp (json-get images "maxPerMessage"))
            (setf image-limits
                  (list :max-per-message
                        (json-get images "maxPerMessage"))))
          (when (numberp (json-get images "maxPerRequest"))
            (setf image-limits
                  (append image-limits
                          (list :max-per-request
                                (json-get images "maxPerRequest")))))
          (when (hash-table-p (json-get images "resize"))
            (setf image-limits
                  (append image-limits
                          (list :resize
                                (resize-limits-plist
                                 (json-get images "resize"))))))
          (setf limits
                (append limits (list :images image-limits)))))
      limits)))

(defun model-row (model)
  (let ((cost (json-get model "cost")))
    (list
     :id (json-get model "id")
     :name (json-get model "name")
     :api (keyword-value (json-get model "api"))
     :provider (keyword-value (json-get model "provider"))
     :base-url (json-get model "baseUrl")
     :input (keyword-list (json-get model "input"))
     :output (keyword-list (json-get model "output"))
     :input-price (number-or-zero (json-get cost "input"))
     :output-price (number-or-zero (json-get cost "output"))
     :cache-read-price (number-or-zero (json-get cost "cacheRead"))
     :cache-write-price (number-or-zero (json-get cost "cacheWrite"))
     :headers (header-alist (json-get model "headers"))
     :input-limits (input-limits-plist (json-get model "inputLimits")))))

(defun image-catalog-rows ()
  (let ((rows nil)
        (seen (make-hash-table :test #'equal)))
    (dolist (path
             (sort
              (remove-if-not
               (lambda (path)
                 (and (string-equal "json" (pathname-type path))
                      (not (char= #\. (char (pathname-name path) 0)))))
               (uiop:directory-files *catalog-directory*))
              #'string<
              :key #'namestring))
      (let ((catalog
              (cadr-ai::parse-json
               (uiop:read-file-string path :external-format :utf-8))))
        (dolist (api (sorted-keys catalog))
          (let ((models (json-get catalog api)))
            (dolist (key (sorted-keys models))
              (let ((model (json-get models key)))
                (when (string= "image" (or (json-get model "type") ""))
                  (let ((identity
                          (cons (json-get model "provider")
                                (json-get model "id"))))
                    (when (gethash identity seen)
                      (error "Duplicate image model ~A/~A"
                             (car identity) (cdr identity)))
                    (setf (gethash identity seen) t)
                    (push (model-row model) rows)))))))))
    (sort rows #'string<
          :key (lambda (row) (getf row :id)))))

(let* ((rows (image-catalog-rows))
       (*print-pretty* t)
       (*print-right-margin* 88))
  (with-open-file
      (stream *generated-path*
              :direction :output
              :if-exists :supersede
              :if-does-not-exist :create
              :external-format :utf-8)
    (write-line
     ";; Generated by scripts/refresh-image-model-catalog.lisp from the pi-ai 1.4.0 catalog snapshot."
     stream)
    (write-line "(in-package #:cadr-ai)" stream)
    (terpri stream)
    (write-string
     "(defparameter *generated-image-models* '"
     stream)
    (pprint rows stream)
    (write-line ")" stream)
    (terpri stream)
    (write-line
     "(register-generated-image-models *generated-image-models*)"
     stream))
  (format t "Updated ~A with ~D image models.~%"
          (namestring *generated-path*)
          (length rows)))
