(defparameter +doom-wad-url+
  "https://distro.ibiblio.org/slitaz/sources/packages/d/doom1.wad")

(defparameter +doom-default-wad-paths+
  '("doom1.wad" "DOOM1.WAD" "~/doom1.wad" "~/.doom/doom1.wad"))

(defparameter +doom-bundled-wad-path+
  (merge-pathnames
   "doom1.wad"
   (uiop:pathname-directory-pathname *load-truename*)))

(defun doom-expand-home (path)
  (if (uiop:string-prefix-p "~/" path)
      (merge-pathnames (subseq path 2) (user-homedir-pathname))
      (pathname path)))

(defun doom-bundled-wad-path ()
  +doom-bundled-wad-path+)

(defun find-wad-file (&optional custom-path)
  (if custom-path
      (let ((path (doom-expand-home custom-path)))
        (and (probe-file path) (namestring (truename path))))
      (loop for path in
            (cons (doom-bundled-wad-path)
                  (mapcar #'doom-expand-home +doom-default-wad-paths+))
            when (probe-file path)
              return (namestring (truename path)))))

(defun doom-download-wad-octets ()
  (let* ((request
           (cadr-ai::make-request-spec
            :url +doom-wad-url+
            :method :get
            :headers nil
            :payload (cadr-ai::json-object)))
         (body
           (multiple-value-bind (value status headers)
               (cadr-ai::invoke-http-request
                request :connect-timeout 10 :read-timeout 60
                :want-stream nil :force-string nil)
             (declare (ignore headers))
             (unless (<= 200 status 299)
               (error "HTTP ~D" status))
             (if (typep value '(vector (unsigned-byte 8)))
                 value
                 (cadr-ai::slurp-stream-octets value)))))
    body))

(defun ensure-wad-file ()
  (or
   (find-wad-file)
   (handler-case
       (let* ((wad (doom-download-wad-octets))
              (path (doom-bundled-wad-path)))
         (with-open-file
             (stream path :direction :output
                          :if-exists :supersede
                          :if-does-not-exist :create
                          :element-type '(unsigned-byte 8))
           (write-sequence wad stream))
         (namestring path))
     (condition () nil))))
