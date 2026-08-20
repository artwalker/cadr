(in-package #:cadr-cli)

(defun sequence-list (value)
  (cond
    ((null value) nil)
    ((vectorp value) (coerce value 'list))
    ((listp value) value)
    (t nil)))

(defun package-entry-source (entry)
  (cond
    ((stringp entry) entry)
    ((cadr-ai::json-object-p entry)
     (cadr-ai::json-get entry "source"))
    (t nil)))

(defun package-source-storage-value
    (source base-directory)
  (let ((parsed
          (parse-package-source source)))
    (if (eq :local
            (package-source-type parsed))
        (let* ((base
                 (uiop:ensure-directory-pathname
                  base-directory))
               (resolved
                 (uiop:ensure-absolute-pathname
                  (merge-pathnames
                   (pathname
                    (package-source-path parsed))
                   base))))
          (enough-namestring resolved base))
        source)))

(defun package-command-source-value
    (source cwd)
  (let ((parsed
          (parse-package-source source)))
    (if (eq :local
            (package-source-type parsed))
        (namestring
         (uiop:ensure-absolute-pathname
          (merge-pathnames
           (pathname
            (package-source-path parsed))
           (uiop:ensure-directory-pathname
            cwd))))
        source)))

(defun settings-package-entries
    (manager scope)
  (sequence-list
   (cadr-ai::json-get
    (ecase scope
      (:global
       (settings-manager-global manager))
      (:project
       (settings-manager-project manager)))
    "packages")))

(defun package-entry-identity
    (entry base-directory)
  (let ((source (package-entry-source entry)))
    (and source
         (package-source-identity
          source base-directory))))

(defun persist-package-source
    (manager source
     &key (scope :global)
       base-directory)
  (let* ((base
           (uiop:ensure-directory-pathname
            base-directory))
         (stored
           (package-source-storage-value
            source base))
         (identity
           (package-source-identity
            stored base))
         (entries
           (copy-list
            (settings-package-entries
             manager scope)))
         (existing
           (position
            identity entries
            :test #'equal
            :key
            (lambda (entry)
              (package-entry-identity
               entry base)))))
    (when existing
      (when
          (string=
           stored
           (package-entry-source
            (nth existing entries)))
        (return-from
            persist-package-source nil))
      (let ((entry (nth existing entries)))
        (if (cadr-ai::json-object-p entry)
            (cadr-ai::json-put
             entry "source" stored)
            (setf (nth existing entries)
                  stored))))
    (unless existing
      (setf entries
            (append entries
                    (list stored))))
    (settings-set
     manager "packages" entries
     :scope scope)
    t))

(defun remove-package-source
    (manager source
     &key (scope :global)
       base-directory)
  (let* ((base
           (uiop:ensure-directory-pathname
            base-directory))
         (identity
           (package-source-identity
            source base))
         (entries
           (copy-list
            (settings-package-entries
             manager scope)))
         (remaining
           (remove
            identity entries
            :test #'equal
            :key
            (lambda (entry)
              (package-entry-identity
               entry base)))))
    (when (= (length entries)
             (length remaining))
      (return-from
          remove-package-source nil))
    (settings-set
     manager "packages" remaining
     :scope scope)
    t))

(defun configured-package-records
    (manager
     &key global-base project-base)
  (let ((global nil)
        (project nil))
    (dolist
        (entry
         (settings-package-entries
          manager :global))
      (let ((source
              (package-entry-source entry)))
        (when source
          (push source global))))
    (when
        (settings-manager-project-trusted-p
         manager)
      (dolist
          (entry
           (settings-package-entries
            manager :project))
        (let ((source
                (package-entry-source entry)))
          (when source
            (push source project)))))
    (mapcar
     (lambda (entry)
       (let* ((scope (car entry))
              (source (cdr entry))
              (base
                (if (eq scope :project)
                    project-base
                    global-base))
              (parsed
                (parse-package-source source)))
         (list
          :scope scope
          :source source
          :base base
          :parsed parsed
          :path
          (and
           (eq :local
               (package-source-type parsed))
           (uiop:ensure-absolute-pathname
            (merge-pathnames
             (pathname
              (package-source-path parsed))
             (uiop:ensure-directory-pathname
              base)))))))
     (dedupe-package-sources
       (nreverse global)
       (nreverse project)
       :user-base global-base
       :project-base project-base))))

(defun materialize-package-records
    (records global-install-root
     project-install-root)
  (mapcar
   (lambda (record)
     (let ((copy (copy-list record)))
       (setf
        (getf copy :path)
        (package-record-install-path
         record global-install-root
         project-install-root))
       copy))
   records))
