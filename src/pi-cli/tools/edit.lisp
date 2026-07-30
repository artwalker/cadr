(in-package #:pi-cli)

(defstruct replacement
  start
  end
  old
  new)

(defun all-occurrences (needle haystack)
  (when (zerop (length needle))
    (error "oldText must not be empty"))
  (loop with start = 0
        for position = (search needle haystack :start2 start)
        while position
        collect position
        do (setf start (1+ position))))

(defun parse-replacements (arguments original)
  (let ((edits (pi-ai::json-get arguments "edits")))
    (unless (and (vectorp edits) (plusp (length edits)))
      (error "edits must contain at least one replacement"))
    (let ((replacements nil))
      (loop for edit across edits
            for old = (required-string edit "oldText")
            for new = (required-string edit "newText")
            for positions = (all-occurrences old original)
            do
            (cond
              ((null positions)
               (error "oldText was not found: ~S" old))
              ((cdr positions)
               (error "oldText is not unique: ~S" old))
              (t
               (push
                (make-replacement
                 :start (first positions)
                 :end (+ (first positions) (length old))
                 :old old
                 :new new)
                replacements))))
      (setf replacements
            (sort replacements #'< :key #'replacement-start))
      (loop for previous = nil then replacement
            for replacement in replacements
            when (and previous
                      (< (replacement-start replacement)
                         (replacement-end previous)))
              do (error "Edits overlap in the original file"))
      replacements)))

(defun apply-replacements (original replacements)
  (with-output-to-string (output)
    (loop with cursor = 0
          for replacement in replacements
          do (write-string
              original output
              :start cursor
              :end (replacement-start replacement))
             (write-string (replacement-new replacement) output)
             (setf cursor (replacement-end replacement))
          finally (write-string original output :start cursor))))

(defun atomic-write-utf8 (path content)
  (let* ((name (or (pathname-name path) "file"))
         (temporary
           (make-pathname
            :name (format nil ".~A.pi-cl-~D"
                          name (random most-positive-fixnum))
            :type "tmp"
            :defaults path)))
    (unwind-protect
         (progn
           (write-utf8-file temporary content)
           (uiop:rename-file-overwriting-target temporary path))
      (when (probe-file temporary)
        (delete-file temporary)))))

(defun make-edit-tool (cwd)
  (pi-ai:make-tool
   :name "edit"
   :description
   "Apply one or more unique, non-overlapping exact replacements."
   :parameters
   (object-schema
    (pi-ai::json-object
     "path" (string-property)
     "edits"
     (pi-ai::json-object
      "type" "array"
      "minItems" 1
      "items"
      (object-schema
       (pi-ai::json-object
        "oldText" (string-property)
        "newText" (string-property))
       '("oldText" "newText"))))
    '("path" "edits"))
   :execution-mode :sequential
   :executor
   (lambda (call-id arguments)
     (declare (ignore call-id))
     (let* ((path
              (resolve-tool-path
               cwd (required-string arguments "path")))
            (original
              (uiop:read-file-string
               path :external-format :utf-8))
            (replacements
              (parse-replacements arguments original))
            (updated
              (apply-replacements original replacements)))
       (atomic-write-utf8 path updated)
       (values
        (list
         (pi-ai:make-text-content
          :text
          (format nil "Applied ~D replacement~:P to ~A"
                  (length replacements)
                  (namestring path))))
        (list :path (namestring path)
              :replacements (length replacements)))))))
