(in-package #:cadr-agent)

(defstruct prompt-template
  (name "" :type string)
  description
  (content "" :type string))

(defstruct skill
  (name "" :type string)
  (description "" :type string)
  (content "" :type string)
  (file-path "" :type string)
  (disable-model-invocation-p nil :type boolean))

(defstruct resource-diagnostic
  (type :warning :type symbol)
  code
  (message "" :type string)
  (path "" :type string)
  source)

(defun resource-absolute-path (path &optional cwd)
  (let ((pathname (pathname path)))
    (namestring
     (if (uiop:absolute-pathname-p pathname)
         pathname
         (merge-pathnames
          pathname
          (uiop:ensure-directory-pathname
           (or cwd (uiop:getcwd))))))))

(defun normalize-resource-content (content)
  (cadr-ai::replace-all
   (cadr-ai::replace-all
    content (format nil "~C~C"
                    #\Return #\Newline)
    (string #\Newline))
   (string #\Return)
   (string #\Newline)))

(defun unquote-frontmatter-value (value)
  (let ((trimmed
          (string-trim
           '(#\Space #\Tab) value)))
    (if
        (and
         (> (length trimmed) 1)
         (member (char trimmed 0)
                 '(#\' #\"))
         (char=
          (char trimmed 0)
          (char trimmed
                (1- (length trimmed)))))
        (subseq trimmed 1
                (1- (length trimmed)))
        trimmed)))

(defun parse-resource-frontmatter (content)
  (let ((normalized
          (normalize-resource-content content)))
    (unless
        (uiop:string-prefix-p "---" normalized)
      (return-from parse-resource-frontmatter
        (values nil normalized nil)))
    (let ((end
            (search
             (format nil "~%---")
             normalized
             :start2 3)))
      (unless end
        (return-from parse-resource-frontmatter
          (values nil normalized nil)))
      (let ((metadata nil)
            (raw
              (subseq normalized 4 end)))
        (dolist
            (line
             (uiop:split-string
              raw :separator '(#\Newline)))
          (let ((colon (position #\: line)))
            (when colon
              (let* ((key
                       (string-downcase
                        (string-trim
                         '(#\Space #\Tab)
                         (subseq line 0 colon))))
                     (value
                       (unquote-frontmatter-value
                        (subseq line (1+ colon)))))
                (when
                    (and
                     (uiop:string-prefix-p
                      "[" value)
                     (not
                      (uiop:string-suffix-p
                       value "]")))
                  (return-from
                      parse-resource-frontmatter
                    (values
                     nil nil
                     "Invalid frontmatter")))
                (setf
                 (getf metadata
                       (intern
                        (string-upcase key)
                        :keyword))
                 value)))))
        (values
         metadata
         (string-trim
          '(#\Space #\Tab #\Newline)
          (subseq normalized (+ end 4)))
         nil)))))

(defun resource-first-description (body)
  (let ((line
          (find-if
           (lambda (candidate)
             (plusp
              (length
               (string-trim
                '(#\Space #\Tab)
                candidate))))
           (uiop:split-string
            body :separator '(#\Newline)))))
    (when line
      (if (> (length line) 60)
          (format nil "~A..."
                  (subseq line 0 60))
          line))))

(defun markdown-resource-p (path)
  (string-equal
   "md"
   (or (pathname-type (pathname path)) "")))

(defun make-resource-warning
    (code message path &optional source)
  (make-resource-diagnostic
   :code code
   :message message
   :path (resource-absolute-path path)
   :source source))

(defun load-prompt-template-file (path)
  (handler-case
      (multiple-value-bind
            (metadata body parse-error)
          (parse-resource-frontmatter
           (uiop:read-file-string
            path :external-format :utf-8))
        (if parse-error
            (values
             nil
             (list
              (make-resource-warning
               :parse-failed parse-error path)))
            (values
             (make-prompt-template
              :name
              (or
               (pathname-name (pathname path))
               "")
              :description
              (or
               (getf metadata :description)
               (resource-first-description body)
               "")
              :content body)
             nil)))
    (error (cause)
      (values
       nil
       (list
        (make-resource-warning
         :read-failed
         (princ-to-string cause)
         path))))))

(defun prompt-template-input-files (path)
  (let ((absolute
          (resource-absolute-path path)))
    (cond
      ((uiop:directory-exists-p absolute)
       (sort
        (remove-if-not
         #'markdown-resource-p
         (uiop:directory-files absolute))
        #'string<
        :key #'namestring))
      ((and
        (probe-file absolute)
        (markdown-resource-p absolute))
       (list (pathname absolute)))
      (t nil))))

(defun load-prompt-templates (paths)
  (let ((templates nil)
        (diagnostics nil))
    (dolist
        (path
         (if (listp paths)
             paths
             (list paths)))
      (dolist (file
               (prompt-template-input-files
                path))
        (multiple-value-bind
              (template warnings)
            (load-prompt-template-file file)
          (when template
            (push template templates))
          (setf diagnostics
                (nconc diagnostics warnings)))))
    (values
     (nreverse templates)
     diagnostics)))

(defun copy-resource-diagnostic-with-source
    (diagnostic source)
  (make-resource-diagnostic
   :type (resource-diagnostic-type diagnostic)
   :code (resource-diagnostic-code diagnostic)
   :message
   (resource-diagnostic-message diagnostic)
   :path (resource-diagnostic-path diagnostic)
   :source source))

(defun load-sourced-prompt-templates (inputs)
  (let ((templates nil)
        (diagnostics nil))
    (dolist (input inputs)
      (multiple-value-bind (loaded warnings)
          (load-prompt-templates
           (getf input :path))
        (dolist (template loaded)
          (push
           (list
            :prompt-template template
            :source (getf input :source))
           templates))
        (dolist (warning warnings)
          (push
           (copy-resource-diagnostic-with-source
            warning (getf input :source))
           diagnostics))))
    (values
     (nreverse templates)
     (nreverse diagnostics))))

(defun regex-replacement-register
    (target register-starts register-ends index)
  (let ((start (aref register-starts index))
        (end (aref register-ends index)))
    (and start end
         (subseq target start end))))

(defun substitute-prompt-arguments (content arguments)
  (let ((result
          (cl-ppcre:regex-replace-all
           "\\$(\\d+)" content
           (lambda
               (target start end
                match-start match-end
                register-starts register-ends)
             (declare
              (ignore
               start end match-start match-end))
             (let* ((number
                      (parse-integer
                       (regex-replacement-register
                        target
                        register-starts
                        register-ends 0)))
                    (value
                      (nth (1- number)
                           arguments)))
               (or value ""))))))
    (setf
     result
     (cl-ppcre:regex-replace-all
      "\\$\\{@:(\\d+)(?::(\\d+))?\\}"
      result
      (lambda
          (target start end
           match-start match-end
           register-starts register-ends)
        (declare
         (ignore
          start end match-start match-end))
        (let* ((start-index
                 (max
                  0
                  (1-
                   (parse-integer
                    (regex-replacement-register
                     target register-starts
                     register-ends 0)))))
               (length-text
                 (regex-replacement-register
                  target register-starts
                  register-ends 1))
               (selected
                 (if length-text
                     (subseq
                      arguments
                      (min start-index
                           (length arguments))
                      (min
                       (length arguments)
                       (+ start-index
                          (parse-integer
                           length-text))))
                     (nthcdr start-index
                             arguments))))
          (format nil "~{~A~^ ~}" selected)))))
    (let ((all
            (format nil "~{~A~^ ~}" arguments)))
      (cadr-ai::replace-all
       (cadr-ai::replace-all
        result "$ARGUMENTS" all)
       "$@" all))))

(defun format-prompt-template-invocation
    (template &optional arguments)
  (substitute-prompt-arguments
   (prompt-template-content template)
   arguments))

(defun valid-skill-name-p (name)
  (and
   (<= (length name) 64)
   (plusp (length name))
   (not (char= #\-
               (char name 0)))
   (not
    (char=
     #\-
     (char name
           (1- (length name)))))
   (not (search "--" name))
   (every
    (lambda (character)
      (or
       (and (char>= character #\a)
            (char<= character #\z))
       (digit-char-p character)
       (char= character #\-)))
    name)))

(defun skill-parent-name (path)
  (let* ((directory
           (uiop:pathname-directory-pathname
            (pathname path)))
         (parts (pathname-directory directory)))
    (princ-to-string (car (last parts)))))

(defun load-skill-file (path)
  (handler-case
      (multiple-value-bind
            (metadata body parse-error)
          (parse-resource-frontmatter
           (uiop:read-file-string
            path :external-format :utf-8))
        (when parse-error
          (return-from load-skill-file
            (values
             nil
             (list
              (make-resource-warning
               :parse-failed parse-error path)))))
        (let* ((parent-name
                 (skill-parent-name path))
               (name
                 (or (getf metadata :name)
                     parent-name))
               (description
                 (getf metadata :description))
               (warnings nil))
          (unless
              (and description
                   (plusp
                    (length
                     (string-trim
                      '(#\Space #\Tab)
                      description))))
            (push
             (make-resource-warning
              :invalid-metadata
              "description is required"
              path)
             warnings))
          (when
              (and description
                   (> (length description) 1024))
            (push
             (make-resource-warning
              :invalid-metadata
              (format nil
                      "description exceeds 1024 characters (~D)"
                      (length description))
              path)
             warnings))
          (unless (string= name parent-name)
            (push
             (make-resource-warning
              :invalid-metadata
              (format nil
                      "name ~S does not match parent directory ~S"
                      name parent-name)
              path)
             warnings))
          (unless (valid-skill-name-p name)
            (push
             (make-resource-warning
              :invalid-metadata
              "name contains invalid characters"
              path)
             warnings))
          (if (or warnings (null description))
              (values nil (nreverse warnings))
              (values
               (make-skill
                :name name
                :description description
                :content body
                :file-path
                (resource-absolute-path path)
                :disable-model-invocation-p
                (string-equal
                 "true"
                 (or
                  (getf
                   metadata
                   :disable-model-invocation)
                  "")))
               nil))))
    (error (cause)
      (values
       nil
       (list
        (make-resource-warning
         :read-failed
         (princ-to-string cause)
         path))))))

(defun visible-resource-directory-p (path)
  (let ((name
          (car
           (last
            (pathname-directory
             (uiop:ensure-directory-pathname
              path))))))
    (and
     (stringp name)
     (not
      (uiop:string-prefix-p "." name))
     (not
      (string= "node_modules" name)))))

(defun load-skills-directory (directory include-root-files-p)
  (let* ((absolute
           (resource-absolute-path directory))
         (skill-path
           (merge-pathnames
            "SKILL.md"
            (uiop:ensure-directory-pathname
             absolute))))
    (when (probe-file skill-path)
      (multiple-value-bind (skill warnings)
          (load-skill-file
           (namestring skill-path))
        (return-from load-skills-directory
          (values
           (and skill (list skill))
           warnings))))
    (let ((skills nil)
          (diagnostics nil))
      (when include-root-files-p
        (dolist
            (file
             (sort
              (remove-if-not
               #'markdown-resource-p
               (uiop:directory-files absolute))
              #'string<
              :key #'namestring))
          (multiple-value-bind (skill warnings)
              (load-skill-file file)
            (when skill (push skill skills))
            (setf diagnostics
                  (nconc diagnostics warnings)))))
      (dolist
          (child
           (sort
            (remove-if-not
             #'visible-resource-directory-p
             (uiop:subdirectories absolute))
            #'string<
            :key #'namestring))
        (multiple-value-bind
              (loaded warnings)
            (load-skills-directory child nil)
          (setf
           skills (nconc
                   (nreverse loaded)
                   skills)
           diagnostics
           (nconc diagnostics warnings))))
      (values
       (nreverse skills)
       diagnostics))))

(defun load-skills (directories)
  (let ((skills nil)
        (diagnostics nil))
    (dolist
        (directory
         (if (listp directories)
             directories
             (list directories)))
      (let ((absolute
              (resource-absolute-path directory)))
        (when
            (uiop:directory-exists-p
             absolute)
          (multiple-value-bind
                (loaded warnings)
              (load-skills-directory
               absolute t)
            (setf
             skills (nconc skills loaded)
             diagnostics
             (nconc diagnostics warnings))))))
    (values skills diagnostics)))

(defun load-sourced-skills (inputs)
  (let ((skills nil)
        (diagnostics nil))
    (dolist (input inputs)
      (multiple-value-bind (loaded warnings)
          (load-skills (getf input :path))
        (dolist (skill loaded)
          (push
           (list :skill skill
                 :source (getf input :source))
           skills))
        (dolist (warning warnings)
          (push
           (copy-resource-diagnostic-with-source
            warning (getf input :source))
           diagnostics))))
    (values
     (nreverse skills)
     (nreverse diagnostics))))

(defun format-skill-invocation
    (skill &optional additional-instructions)
  (let ((block
          (format nil
                  "<skill name=\"~A\" location=\"~A\">~%References are relative to ~A.~%~%~A~%</skill>"
                  (skill-name skill)
                  (skill-file-path skill)
                  (string-right-trim
                   "/"
                   (namestring
                    (uiop:pathname-directory-pathname
                     (pathname
                      (skill-file-path skill)))))
                  (skill-content skill))))
    (if additional-instructions
        (format nil "~A~%~%~A"
                block additional-instructions)
        block)))

(defun xml-escape (value)
  (reduce
   (lambda (text pair)
     (cadr-ai::replace-all
      text (car pair) (cdr pair)))
   '(("&" . "&amp;")
     ("<" . "&lt;")
     (">" . "&gt;")
     ("\"" . "&quot;")
     ("'" . "&apos;"))
   :initial-value value))

(defun format-skills-for-system-prompt (skills)
  (let ((visible
          (remove-if
           #'skill-disable-model-invocation-p
           skills)))
    (if (null visible)
        ""
        (with-output-to-string (stream)
          (format
           stream
           "The following skills provide specialized instructions for specific tasks.~%Read the full skill file when the task matches its description.~%When a skill file references a relative path, resolve it against the skill directory (parent of SKILL.md / dirname of the path) and use that absolute path in tool commands.~%~%<available_skills>~%")
          (dolist (skill visible)
            (format
             stream
             "  <skill>~%    <name>~A</name>~%    <description>~A</description>~%    <location>~A</location>~%  </skill>~%"
             (xml-escape (skill-name skill))
             (xml-escape
              (skill-description skill))
             (xml-escape
              (skill-file-path skill))))
          (write-string
           "</available_skills>" stream)))))
