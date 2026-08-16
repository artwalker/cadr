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
(asdf:load-asd (truename (merge-pathnames "cadr-ai.asd" *root*)))
(asdf:load-system "cadr-ai")

(defparameter *source-path*
  (merge-pathnames
   "test/fixtures/catalogs/image-data/openrouter.json"
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

(defun header-alist (object)
  (when (hash-table-p object)
    (loop for key in (sorted-keys object)
          collect (cons key (json-get object key)))))

(defun model-row (model)
  (let ((cost (json-get model "cost")))
    (list
     :id (json-get model "id")
     :name (json-get model "name")
     :api :openrouter-images
     :provider :openrouter
     :base-url (json-get model "baseUrl")
     :input (keyword-list (json-get model "input"))
     :output (keyword-list (json-get model "output"))
     :input-price (number-or-zero (json-get cost "input"))
     :output-price (number-or-zero (json-get cost "output"))
     :cache-read-price
     (number-or-zero (json-get cost "cacheRead"))
     :cache-write-price
     (number-or-zero (json-get cost "cacheWrite"))
     :headers (header-alist (json-get model "headers")))))

(let* ((catalog
         (cadr-ai::parse-json
          (uiop:read-file-string
           *source-path* :external-format :utf-8)))
       (rows
         (loop for id in (sorted-keys catalog)
               collect (model-row (json-get catalog id))))
       (*print-pretty* t)
       (*print-right-margin* 88))
  (with-open-file
      (stream *generated-path*
              :direction :output
              :if-exists :supersede
              :if-does-not-exist :create
              :external-format :utf-8)
    (write-line
     ";; Generated from the fixed @earendil-works/pi-ai 0.83.0 OpenRouter image catalog."
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
