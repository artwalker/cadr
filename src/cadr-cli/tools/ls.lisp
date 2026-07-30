(in-package #:cadr-cli)

(defun directory-entry-name (path)
  (let ((directory
          (uiop:directory-pathname-p path)))
    (if directory
        (format nil "~A/"
                (car (last (pathname-directory path))))
        (file-namestring path))))

(defun list-directory (cwd arguments)
  (let* ((path
           (resolve-tool-path
            cwd (or (cadr-ai::json-get arguments "path") ".")))
         (limit (or (optional-integer arguments "limit" 500) 500)))
    (unless (probe-file path)
      (error "Path not found: ~A" (namestring path)))
    (unless (uiop:directory-exists-p path)
      (error "Not a directory: ~A" (namestring path)))
    (when (< limit 1)
      (error "limit must be at least 1"))
    (let* ((entries
             (sort
              (append
               (uiop:directory-files path)
               (uiop:subdirectories path))
              #'string-lessp
              :key #'directory-entry-name))
           (truncated (> (length entries) limit))
           (selected
             (subseq entries 0 (min limit (length entries))))
           (text
             (if selected
                 (join-lines
                  (mapcar #'directory-entry-name selected))
                 "(empty directory)")))
      (values
       (list (cadr-ai:make-text-content :text text))
       (and truncated
            (list :entry-limit-reached limit))))))

(defun make-ls-tool (cwd)
  (cadr-ai:make-tool
   :name "ls"
   :description
   "List directory contents sorted alphabetically; directories end in /."
   :parameters
   (object-schema
    (cadr-ai::json-object
     "path" (string-property)
     "limit" (number-property))
    nil)
   :execution-mode :parallel
   :executor
   (lambda (call-id arguments)
     (declare (ignore call-id))
     (list-directory cwd arguments))))
