(in-package #:pi-cli)

(defun resolve-tool-path (cwd path)
  (unless (and (stringp path) (plusp (length path)))
    (error "Path must be a non-empty string"))
  (let ((pathname (pathname path)))
    (uiop:ensure-absolute-pathname
     (if (uiop:absolute-pathname-p pathname)
         pathname
         (merge-pathnames pathname
                          (uiop:ensure-directory-pathname cwd))))))

(defun relative-posix-path (path cwd)
  (substitute #\/ #\\
              (enough-namestring
               path (uiop:ensure-directory-pathname cwd))))

(defun required-string (arguments key)
  (let ((value (pi-ai::json-get arguments key)))
    (unless (stringp value)
      (error "~A must be a string" key))
    value))

(defun optional-integer (arguments key &optional default)
  (let ((value (pi-ai::json-get arguments key default)))
    (unless (or (null value) (integerp value))
      (error "~A must be an integer" key))
    value))

(defun object-schema (properties required)
  (pi-ai::json-object
   "type" "object"
   "properties" properties
   "required" (coerce required 'vector)
   "additionalProperties" nil))

(defun string-property (&optional description)
  (let ((property (pi-ai::json-object "type" "string")))
    (when description
      (pi-ai::json-put property "description" description))
    property))

(defun number-property ()
  (pi-ai::json-object "type" "number"))

(defun boolean-property ()
  (pi-ai::json-object "type" "boolean"))
