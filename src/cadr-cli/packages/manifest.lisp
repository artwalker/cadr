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
  (let ((global-extensions nil)
        (project-extensions nil)
        (global-skills nil)
        (project-skills nil)
        (global-prompts nil)
        (project-prompts nil)
        (global-themes nil)
        (project-themes nil))
    (dolist (record records)
      (let* ((root (getf record :path))
             (scope
               (if (eq :project
                       (getf record :scope))
                   :project :global)))
        (when root
          (multiple-value-bind
                (manifest manifest-p)
              (read-package-pi-manifest root)
            (dolist
                (path
                 (package-record-resource-values
                  root manifest manifest-p
                  :extensions))
              (if (eq scope :project)
                  (push path project-extensions)
                  (push path global-extensions)))
            (dolist
                (path
                 (package-record-resource-values
                  root manifest manifest-p
                  :skills))
              (if (eq scope :project)
                  (push path project-skills)
                  (push path global-skills)))
            (dolist
                (path
                 (package-record-resource-values
                  root manifest manifest-p
                  :prompts))
              (if (eq scope :project)
                  (push path project-prompts)
                  (push path global-prompts)))
            (dolist
                (path
                 (package-record-resource-values
                  root manifest manifest-p
                  :themes))
              (if (eq scope :project)
                  (push path project-themes)
                  (push path global-themes)))))))
    (setf
     global-extensions (nreverse global-extensions)
     project-extensions (nreverse project-extensions)
     global-skills (nreverse global-skills)
     project-skills (nreverse project-skills)
     global-prompts (nreverse global-prompts)
     project-prompts (nreverse project-prompts)
     global-themes (nreverse global-themes)
     project-themes (nreverse project-themes))
    (list
     :extensions
     (append project-extensions global-extensions)
     :skills
     (append project-skills global-skills)
     :prompts
     (append project-prompts global-prompts)
     :themes
     (append project-themes global-themes)
     :global-extensions global-extensions
     :project-extensions project-extensions
     :global-skills global-skills
     :project-skills project-skills
     :global-prompts global-prompts
     :project-prompts project-prompts
     :global-themes global-themes
     :project-themes project-themes)))
