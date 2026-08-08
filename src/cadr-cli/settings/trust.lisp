(in-package #:cadr-cli)

(defstruct (project-trust-store
            (:constructor make-project-trust-store
                (path)))
  path
  (lock
    (sb-thread:make-mutex
     :name "cadr project trust")))

(defun trust-object (store)
  (multiple-value-bind (object error)
      (read-settings-object
       (project-trust-store-path store))
    (if error
        (empty-json-object)
        object)))

(defun canonical-directory-name (path)
  (namestring
   (or
    (ignore-errors
      (truename
       (uiop:ensure-directory-pathname path)))
    (uiop:ensure-absolute-pathname
     (uiop:ensure-directory-pathname path)))))

(defun display-directory-name (path)
  (let* ((text
           (etypecase path
             (string path)
             (pathname (namestring path))))
         (trimmed (string-right-trim '(#\/ #\\) text)))
    (cond
      ((zerop (length trimmed))
       (if (find #\\ text) "\\" "/"))
      ((and (= 3 (length text))
            (alpha-char-p (char text 0))
            (char= #\: (char text 1))
            (member (char text 2) '(#\/ #\\)))
       text)
      (t trimmed))))

(defun parent-directory (directory)
  (let* ((path
           (uiop:ensure-directory-pathname directory))
         (parent
           (uiop:pathname-parent-directory-pathname
            path)))
    (unless (equal (namestring path)
                   (namestring parent))
      parent)))

(defun project-trust-entry
    (store directory)
  (sb-thread:with-mutex
      ((project-trust-store-lock store))
    (let ((object (trust-object store)))
      (loop for current =
            (uiop:ensure-directory-pathname directory)
              then (parent-directory current)
            while current
            for key = (canonical-directory-name current)
            do
            (multiple-value-bind (value found-p)
                (gethash key object)
              (when found-p
                (return
                  (list
                   :path key
                   :decision value))))
            finally (return nil)))))

(defun project-trust-get (store directory)
  (let ((entry
          (project-trust-entry
           store directory)))
    (if entry
        (values (getf entry :decision) t)
        (values nil nil))))

(defun project-trust-set-many
    (store updates)
  (sb-thread:with-mutex
      ((project-trust-store-lock store))
    (let ((object (trust-object store)))
      (dolist (update updates)
        (let ((key
                (canonical-directory-name
                 (getf update :path)))
              (decision
                (getf update :decision)))
          (if (eq decision :remove)
              (remhash key object)
              (setf
               (gethash key object)
               (not (null decision))))))
      (write-settings-object
       (project-trust-store-path store)
       object)))
  updates)

(defun project-trust-set
    (store directory decision
     &key store-negative-p)
  (sb-thread:with-mutex
      ((project-trust-store-lock store))
    (let* ((object (trust-object store))
           (key (canonical-directory-name directory)))
      (if (and (null decision)
               (not store-negative-p))
          (remhash key object)
          (setf (gethash key object)
                (not (null decision))))
      (write-settings-object
       (project-trust-store-path store)
       object)))
  decision)

(defparameter +trust-requiring-project-config-resources+
  '("settings.json" "extensions/" "skills/" "prompts/" "themes/"
    "SYSTEM.md" "APPEND_SYSTEM.md"))

(defun trust-requiring-project-resources-p
    (directory &key (home-directory (user-homedir-pathname)))
  (let* ((root
           (uiop:ensure-directory-pathname
            (pathname (canonical-directory-name directory))))
         (home
           (uiop:ensure-directory-pathname
            (pathname (canonical-directory-name home-directory))))
         (config-root (cadr-core:project-config-directory root)))
    (or
     (some
      (lambda (resource)
        (probe-file (merge-pathnames resource config-root)))
      +trust-requiring-project-config-resources+)
     (loop for current = root then (parent-directory current)
           while current
           when
           (and
            (not
             (equal (canonical-directory-name current)
                    (canonical-directory-name home)))
            (probe-file
             (merge-pathnames ".agents/skills/" current)))
             return t))))

(defun project-trust-warning-text
    (project-trusted-p directory
     &key (home-directory (user-homedir-pathname)))
  (when
      (and
       (not project-trusted-p)
       (trust-requiring-project-resources-p
        directory :home-directory home-directory))
    "This project is not trusted. Project .cadr resources and packages are ignored. Use /trust to save a trust decision, then restart cadr."))

(defun resolve-project-trusted
    (store directory
     &key override override-supplied-p
       extension-host
       (default :ask)
       has-ui-p
       prompt-function)
  (when override-supplied-p
    (return-from resolve-project-trusted
      (not (null override))))
  (unless
      (trust-requiring-project-resources-p
       directory)
    (return-from resolve-project-trusted t))
  (when extension-host
    (let ((result
            (cadr-agent::run-extension-lifecycle-hooks
             extension-host :project-trust
             :payload
             (list
              :cwd
              (canonical-directory-name
               directory)))))
      (when result
        (let ((decision
                (getf result :trusted)))
          (when (member decision '(:yes :no))
            (let ((trusted-p (eq decision :yes)))
              (when (getf result :remember-p)
                (project-trust-set
                 store directory trusted-p
                 :store-negative-p
                 (not trusted-p)))
              (return-from resolve-project-trusted
                trusted-p)))))))
  (multiple-value-bind (stored found-p)
      (project-trust-get store directory)
    (when found-p
      (return-from resolve-project-trusted stored)))
  (case default
    (:always
     (return-from resolve-project-trusted t))
    (:never
     (return-from resolve-project-trusted nil))
    (:ask nil)
    (otherwise
     (error "Invalid default project trust: ~S"
            default)))
  (if (and has-ui-p prompt-function)
      (let ((decision
              (funcall prompt-function directory)))
        (when (member decision '(t nil))
          (project-trust-set
           store directory decision
           :store-negative-p
           (not decision)))
        (not (null decision)))
      nil))
