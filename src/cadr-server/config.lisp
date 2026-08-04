(in-package #:cadr-server)

(defun environment-pathname (name)
  (let ((value (uiop:getenv name)))
    (and value
         (plusp (length value))
         (pathname value))))

(defun server-directory ()
  (uiop:ensure-directory-pathname
   (or (environment-pathname
        "CADR_SERVER_DIR")
       (merge-pathnames
        "server/"
        (or (environment-pathname
             "CADR_CONFIG_DIR")
            (merge-pathnames
             ".cadr/"
             (user-homedir-pathname)))))))

(defun server-auth-path
    (&optional (directory (server-directory)))
  (merge-pathnames
   "auth.json"
   (uiop:ensure-directory-pathname
    directory)))

(defun server-machine-path
    (&optional (directory (server-directory)))
  (merge-pathnames
   "machine.json"
   (uiop:ensure-directory-pathname
    directory)))

(defun server-instances-path
    (&optional (directory (server-directory)))
  (merge-pathnames
   "instances.json"
   (uiop:ensure-directory-pathname
    directory)))

(defun server-socket-path
    (&optional (directory (server-directory)))
  (merge-pathnames
   "server.sock"
   (uiop:ensure-directory-pathname
    directory)))
