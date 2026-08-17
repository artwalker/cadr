(in-package #:cadr-cli)

(defparameter +package-manifest-resource-fields+
  '((:extensions . "extensions")
    (:skills . "skills")
    (:prompts . "prompts")
    (:themes . "themes")))

(defun read-package-pi-manifest (root)
  (let ((path
          (merge-pathnames
           "package.json"
           (uiop:ensure-directory-pathname
            root))))
    (unless (probe-file path)
      (return-from read-package-pi-manifest
        (values nil nil)))
    (handler-case
        (let* ((package
                 (cadr-ai::parse-json
                  (uiop:read-file-string
                   path
                   :external-format :utf-8)))
               (manifest
                 (and
                  (hash-table-p package)
                  (cadr-ai::json-get
                   package "pi"))))
          (if (hash-table-p manifest)
              (let ((result nil))
                (dolist
                    (field
                     +package-manifest-resource-fields+)
                  (let ((value
                          (cadr-ai::json-get
                           manifest (cdr field))))
                    (when
                        (and
                         (vectorp value)
                         (every #'stringp value))
                      (setf
                       (getf result (car field))
                       (coerce value 'list)))))
                (values result t))
              (values nil nil)))
      (condition ()
        (values nil nil)))))

(defun package-manifest-path
    (root relative)
  (let ((candidate
          (merge-pathnames
           (pathname relative)
           (uiop:ensure-directory-pathname
            root))))
    (and
     (probe-file candidate)
     (truename candidate))))

(defun package-record-resource-values
    (root manifest manifest-p kind)
  (if manifest-p
      (remove
       nil
       (mapcar
        (lambda (relative)
          (package-manifest-path
           root relative))
        (getf manifest kind)))
      (ecase kind
        (:extensions
         (let ((entry
                 (if
                     (uiop:directory-exists-p root)
                     (merge-pathnames
                      "extension.lisp"
                      (uiop:ensure-directory-pathname
                       root))
                     root)))
           (when (probe-file entry)
             (list root))))
        (:skills
         (let ((path
                 (merge-pathnames
                  "skills/"
                  (uiop:ensure-directory-pathname
                   root))))
           (when
               (uiop:directory-exists-p path)
             (list path))))
        (:prompts
         (let ((path
                 (merge-pathnames
                  "prompts/"
                  (uiop:ensure-directory-pathname
                   root))))
           (when
               (uiop:directory-exists-p path)
             (list path))))
        (:themes
         (let ((path
                 (merge-pathnames
                  "themes/"
                  (uiop:ensure-directory-pathname
                   root))))
           (when
               (uiop:directory-exists-p path)
             (list path)))))))

(defun package-resource-paths (records)
  (let ((global (make-hash-table :test #'eq))
        (project (make-hash-table :test #'eq)))
    (dolist (record records)
      (let* ((root (getf record :path))
             (scope
               (if (eq :project (getf record :scope))
                   :project :global))
             (buckets (if (eq scope :project) project global)))
        (when root
          (multiple-value-bind (manifest manifest-p)
              (read-package-pi-manifest root)
            (dolist (field +package-manifest-resource-fields+)
              (dolist (path
                       (package-record-resource-values
                        root manifest manifest-p (car field)))
                (push path (gethash (car field) buckets))))))))
    (let ((result nil))
      (dolist (field +package-manifest-resource-fields+)
        (let* ((kind (car field))
               (global-paths (nreverse (gethash kind global)))
               (project-paths (nreverse (gethash kind project))))
          (setf (getf result kind)
                (append project-paths global-paths))
          (setf (getf result
                      (intern (format nil "GLOBAL-~A" kind)
                              :keyword))
                global-paths)
          (setf (getf result
                      (intern (format nil "PROJECT-~A" kind)
                              :keyword))
                project-paths)))
      result)))
