(in-package #:cadr-cli)

;;; Session persistence selection

(defclass session-manager ()
  ((mode
    :initarg :mode
    :reader session-manager-mode)
   (cwd
    :initarg :cwd
    :reader session-manager-cwd)
   (directory
    :initarg :directory
    :reader session-manager-directory)
   (path
    :initarg :path
    :initform nil
    :reader session-manager-path)
   (session-id
    :initarg :session-id
    :initform nil
    :reader session-manager-session-id)
   (parent-session
    :initarg :parent-session
    :initform nil
    :reader session-manager-parent-session)
   (entries
    :initarg :entries
    :initform nil
    :reader session-manager-entries)
   (resolved
    :initform :unresolved
    :accessor session-manager-resolved)
   (lock
    :initform
    (sb-thread:make-mutex
     :name "cadr SDK session manager")
    :reader session-manager-lock)))

(defun make-session-manager
    (mode cwd &key directory path id parent-session entries)
  (make-instance
   'session-manager
   :mode mode
   :cwd
   (uiop:ensure-directory-pathname
    (uiop:ensure-absolute-pathname cwd))
   :directory
   (uiop:ensure-directory-pathname
    (uiop:ensure-absolute-pathname
     (or directory
         (cadr-agent:default-session-directory))))
   :path path
   :session-id id
   :parent-session parent-session
   :entries entries))

(defun session-manager-in-memory
    (&optional (cwd (uiop:getcwd))
     &key id parent-session entries)
  (make-session-manager
   :memory cwd
   :id id
   :parent-session parent-session
   :entries entries))

(defun session-manager-create
    (&optional (cwd (uiop:getcwd))
      (directory
        (cadr-agent:default-session-directory)))
  (make-session-manager
   :create cwd :directory directory))

(defun session-manager-continue-recent
    (&optional (cwd (uiop:getcwd))
      (directory
        (cadr-agent:default-session-directory)))
  (make-session-manager
   :continue cwd :directory directory))

(defun session-manager-open (path)
  (let ((resolved
          (uiop:ensure-absolute-pathname path)))
    (make-session-manager
     :open
     (uiop:pathname-directory-pathname resolved)
     :directory
     (uiop:pathname-directory-pathname resolved)
     :path resolved)))

(defun session-manager-list
    (&optional cwd
      (directory
        (cadr-agent:default-session-directory)))
  (cadr-agent:list-session-infos
   :directory directory :cwd cwd))

(defun session-manager-resolve (manager)
  (sb-thread:with-mutex
      ((session-manager-lock manager))
    (when (eq :unresolved
              (session-manager-resolved manager))
      (setf
       (session-manager-resolved manager)
       (ecase (session-manager-mode manager)
         (:memory
          (cadr-agent:create-in-memory-session
           :cwd (session-manager-cwd manager)
           :id (session-manager-session-id manager)
           :parent-session
           (session-manager-parent-session manager)
           :entries (session-manager-entries manager)))
         (:create
          (cadr-agent:create-session
           :directory
           (session-manager-directory manager)
           :cwd (session-manager-cwd manager)))
         (:continue
          (or
           (cadr-agent:continue-session
            :directory
            (session-manager-directory manager)
            :cwd (session-manager-cwd manager))
           (cadr-agent:create-session
            :directory
            (session-manager-directory manager)
            :cwd (session-manager-cwd manager))))
         (:open
          (cadr-agent:load-session
           (session-manager-path manager))))))
    (session-manager-resolved manager)))

;;; AgentSession facade
