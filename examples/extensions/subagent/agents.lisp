(defun subagent-trim (text)
  (string-trim '(#\Space #\Tab #\Newline #\Return) text))

(defun subagent-unquote (text)
  (let ((trimmed (subagent-trim text)))
    (if
        (and (> (length trimmed) 1)
             (member (char trimmed 0) '(#\' #\"))
             (char= (char trimmed 0)
                    (char trimmed (1- (length trimmed)))))
        (subseq trimmed 1 (1- (length trimmed)))
        trimmed)))

(defun subagent-frontmatter (content)
  (let ((normalized
          (cl-ppcre:regex-replace-all "\\r\\n?" content (string #\Newline))))
    (if (not (uiop:string-prefix-p "---" normalized))
        (values nil normalized)
        (let ((end (search (format nil "~%---") normalized :start2 3)))
          (if (null end)
              (values nil normalized)
              (let ((metadata nil))
                (dolist
                    (line
                     (uiop:split-string
                      (subseq normalized 4 end) :separator '(#\Newline)))
                  (let ((colon (position #\: line)))
                    (when colon
                      (setf
                       (getf metadata
                             (intern
                              (string-upcase (subagent-trim (subseq line 0 colon)))
                              :keyword))
                       (subagent-unquote (subseq line (1+ colon)))))))
                (values metadata
                        (string-left-trim
                         '(#\Space #\Tab #\Newline #\Return)
                         (subseq normalized (+ end 4))))))))))

(defun subagent-load-directory (directory source)
  (let ((agents nil))
    (when (uiop:directory-exists-p directory)
      (dolist (path (directory (merge-pathnames "*.md" directory)))
        (handler-case
            (multiple-value-bind (metadata body)
                (subagent-frontmatter
                 (uiop:read-file-string path :external-format :utf-8))
              (let ((name (getf metadata :name))
                    (description (getf metadata :description)))
                (when (and name description)
                  (let ((tools
                          (remove
                           ""
                           (mapcar #'subagent-trim
                                   (uiop:split-string
                                    (or (getf metadata :tools) "")
                                    :separator '(#\,)))
                           :test #'string=)))
                    (push
                     (list :name name
                           :description description
                           :tools (and tools (plusp (length tools)) tools)
                           :model (getf metadata :model)
                           :system-prompt body
                           :source source
                           :file-path (namestring path))
                     agents)))))
          (condition () nil))))
    (nreverse agents)))

(defun subagent-nearest-project-directory (cwd)
  (labels ((visit (current)
             (let ((candidate
                     (merge-pathnames ".cadr/agents/" current)))
               (if (uiop:directory-exists-p candidate)
                   candidate
                   (let ((parent
                           (uiop:pathname-parent-directory-pathname current)))
                     (unless (or (null parent) (equal parent current))
                       (visit parent)))))))
    (visit (uiop:ensure-directory-pathname cwd))))

(defun discover-subagents (cwd scope)
  (let* ((user-directory
           (merge-pathnames ".cadr/agents/" (user-homedir-pathname)))
         (project-directory (subagent-nearest-project-directory cwd))
         (user-agents
           (unless (eq scope :project)
             (subagent-load-directory user-directory :user)))
         (project-agents
           (unless (or (eq scope :user) (null project-directory))
             (subagent-load-directory project-directory :project)))
         (agents nil))
    (dolist (agent
             (if (eq scope :both)
                 (append user-agents project-agents)
                 (or user-agents project-agents)))
      (let ((existing
              (position (getf agent :name) agents
                        :key (lambda (item) (getf item :name))
                        :test #'string=)))
        (if existing
            (setf (nth existing agents) agent)
            (setf agents (nconc agents (list agent))))))
    (list :agents agents
          :project-agents-directory
          (and project-directory (namestring project-directory)))))

(defun format-subagent-list (agents max-items)
  (if (null agents)
      (list :text "none" :remaining 0)
      (let ((listed (subseq agents 0 (min max-items (length agents)))))
        (list
         :text
         (format nil "~{~A~^; ~}"
                 (mapcar
                  (lambda (agent)
                    (format nil "~A (~(~A~)): ~A"
                            (getf agent :name)
                            (getf agent :source)
                            (getf agent :description)))
                  listed))
         :remaining (- (length agents) (length listed))))))
