(in-package #:cadr-cli)

(defstruct extension-source-record
  id
  path
  scope
  rank
  order)

(defvar *extension-generation-counter* 0)
(defvar *extension-generation-lock*
  (sb-thread:make-mutex
   :name "cadr-cli extension generations"))

(defun next-extension-generation ()
  (sb-thread:with-mutex
      (*extension-generation-lock*)
    (incf *extension-generation-counter*)))

(defstruct (cli-extension-manager
            (:constructor %make-cli-extension-manager))
  cwd
  global-directory
  explicit-paths
  (extension-factories nil :type list)
  configured-package-paths
  (no-discovery-p nil :type boolean)
  output
  (secret-function (constantly nil) :type function)
  host
  (last-good (make-hash-table :test #'equal)
             :type hash-table)
  (generation 0 :type (integer 0 *))
  (package-names nil :type list))

(defun default-extension-directory ()
  (cadr-core:agent-extensions-directory))

(defun extension-directory-id (directory)
  (let ((parts
          (pathname-directory
           (uiop:ensure-directory-pathname directory))))
    (princ-to-string (car (last parts)))))

(defun make-extension-source-record-for-path
    (path scope rank order &optional id)
  (let* ((resolved (truename path))
         (entry
           (if (uiop:directory-pathname-p resolved)
               (merge-pathnames "extension.lisp" resolved)
               resolved)))
    (unless (probe-file entry)
      (error
       'cadr-ai:configuration-error
       :message
       (format nil
               "Extension directory has no extension.lisp: ~A"
               (namestring resolved))))
    (unless
        (and
         (not (uiop:directory-pathname-p entry))
         (string-equal
          "lisp"
          (or (pathname-type entry) "")))
      (error
       'cadr-ai:configuration-error
       :message
       (format nil "Extension entry is not a .lisp file: ~A"
               (namestring entry))))
    (make-extension-source-record
     :id
     (string-downcase
      (or
       id
       (if (uiop:directory-pathname-p resolved)
           (extension-directory-id resolved)
           (pathname-name resolved))))
     :path (namestring (truename entry))
     :scope scope
     :rank rank
     :order order)))

(defun discover-extensions-in-directory
    (directory scope rank)
  (let ((root
          (uiop:ensure-directory-pathname
           (pathname directory)))
        (candidates nil))
    (unless (probe-file root)
      (return-from discover-extensions-in-directory nil))
    (dolist
        (path
         (directory (merge-pathnames "*.lisp" root)))
      (when
          (and
           (not (uiop:directory-pathname-p path))
           (string-equal
            "lisp"
            (or (pathname-type path) "")))
        (push path candidates)))
    (dolist (path (uiop:subdirectories root))
      (when
          (probe-file
           (merge-pathnames "extension.lisp" path))
        (push path candidates)))
    (setf candidates
          (sort candidates
                #'string<
                :key #'namestring))
    (loop for path in candidates
          for order from 0
          collect
          (make-extension-source-record-for-path
           path scope rank order))))

(defun dedupe-extension-sources (sources)
  (let ((seen (make-hash-table :test #'equal))
        (selected nil)
        (errors nil))
    (dolist (source sources)
      (let ((existing
              (gethash
               (extension-source-record-id source)
               seen)))
        (if existing
            (push
             (format nil
                     "Extension id ~S from ~A is shadowed by ~A"
                     (extension-source-record-id source)
                     (extension-source-record-path source)
                     (extension-source-record-path existing))
             errors)
            (progn
              (setf
               (gethash
                (extension-source-record-id source)
                seen)
               source)
              (push source selected)))))
    (values
     (nreverse selected)
     (nreverse errors))))

(defun discover-extension-sources (manager)
  (let ((errors nil)
        (explicit nil)
        (package-project nil)
        (package-global nil))
    (loop
      for path in
      (reverse
       (cli-extension-manager-explicit-paths
        manager))
      for order from 0
      do
      (handler-case
          (push
           (make-extension-source-record-for-path
            (merge-pathnames
             (pathname path)
             (cli-extension-manager-cwd manager))
            :cli 2 order)
           explicit)
        (condition (condition)
          (push (princ-to-string condition) errors))))
    (loop
      for entry in
      (cli-extension-manager-configured-package-paths
       manager)
      for order from 0
      for scope = (car entry)
      for path = (cdr entry)
      do
      (handler-case
          (let ((record
                  (make-extension-source-record-for-path
                   path scope
                   (if (eq scope :project) 1 0)
                   order)))
            (if (eq scope :project)
                (push record package-project)
                (push record package-global)))
        (condition (condition)
          (push (princ-to-string condition) errors))))
    (multiple-value-bind (selected collisions)
        (dedupe-extension-sources
         (nconc
          (nreverse explicit)
          (unless
              (cli-extension-manager-no-discovery-p
               manager)
            (nconc
             (nreverse package-project)
             (discover-extensions-in-directory
              (merge-pathnames
               "extensions/"
               (cadr-core:project-config-directory
                (cli-extension-manager-cwd manager)))
              :project 1)))
          (unless
              (cli-extension-manager-no-discovery-p
               manager)
            (nconc
             (nreverse package-global)
             (discover-extensions-in-directory
              (cli-extension-manager-global-directory
               manager)
              :global 0)))))
      (values selected
              (nreverse errors)
              collisions))))
