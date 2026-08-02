(load (merge-pathnames "support.lisp" *load-truename*))

(defvar *example-todos* nil)
(defvar *example-todo-next-id* 1)

(defun todo-copy-state ()
  (mapcar #'copy-list *example-todos*))

(defun todo-details (action &optional error)
  (list :action action :todos (todo-copy-state)
        :next-id *example-todo-next-id* :error error))

(defun todo-restore (context)
  (setf *example-todos* nil *example-todo-next-id* 1)
  (dolist (entry (example-session-branch context))
    (let ((message (cadr-agent:session-entry-message entry)))
      (when (and (typep message 'cadr-ai:tool-result-message)
                 (string= (cadr-ai:tool-result-message-tool-name message) "todo"))
        (let ((details (cadr-ai:tool-result-message-details message)))
          (when details
            (setf *example-todos*
                  (mapcar #'copy-list (getf details :todos))
                  *example-todo-next-id*
                  (or (getf details :next-id) 1))))))))

(defun todo-format-list ()
  (if *example-todos*
      (format nil "~{~A~^~%~}"
              (mapcar
               (lambda (todo)
                 (format nil "[~:[ ~;x~]] #~D: ~A"
                         (getf todo :done-p)
                         (getf todo :id) (getf todo :text)))
               *example-todos*))
      "No todos"))

(cadr-agent:define-event-hook
 :session-start
 :handler (lambda (event context) (declare (ignore event)) (todo-restore context)))

(cadr-agent:define-event-hook
 :session-tree
 :handler (lambda (event context) (declare (ignore event)) (todo-restore context)))

(cadr-agent:define-rich-tool
 "todo"
 :label "Todo"
 :description "Manage a todo list. Actions: list, add (text), toggle (id), clear"
 :parameters
 (cadr-ai::json-object
  "type" "object"
  "properties"
  (cadr-ai::json-object
   "action" (cadr-ai::json-object
             "type" "string"
             "enum" #("list" "add" "toggle" "clear"))
   "text" (cadr-ai::json-object "type" "string")
   "id" (cadr-ai::json-object "type" "number"))
  "required" #("action") "additionalProperties" nil)
 :execution-mode :sequential
 :handler
 (lambda (call-id arguments signal on-update context)
   (declare (ignore call-id signal on-update context))
   (let ((action (example-argument arguments "action" "list")))
     (cond
       ((string= action "list")
        (example-result (todo-format-list) :details (todo-details :list)))
       ((string= action "add")
        (let ((text (example-argument arguments "text" nil)))
          (if (or (null text) (zerop (length (example-trim text))))
              (example-result "Error: text required for add"
                              :details (todo-details :add "text required"))
              (let ((todo (list :id *example-todo-next-id*
                                :text text :done-p nil)))
                (incf *example-todo-next-id*)
                (setf *example-todos* (append *example-todos* (list todo)))
                (example-result
                 (format nil "Added todo #~D: ~A"
                         (getf todo :id) (getf todo :text))
                 :details (todo-details :add))))))
       ((string= action "toggle")
        (let* ((id (example-argument arguments "id" nil))
               (todo (and id (find id *example-todos*
                                   :key (lambda (row) (getf row :id))))))
          (cond
            ((null id)
             (example-result "Error: id required for toggle"
                             :details (todo-details :toggle "id required")))
            ((null todo)
             (example-result
              (format nil "Todo #~D not found" id)
              :details (todo-details :toggle
                                     (format nil "#~D not found" id))))
            (t
             (setf (getf todo :done-p) (not (getf todo :done-p)))
             (example-result
              (format nil "Todo #~D ~:[uncompleted~;completed~]"
                      id (getf todo :done-p))
              :details (todo-details :toggle))))))
       ((string= action "clear")
        (let ((count (length *example-todos*)))
          (setf *example-todos* nil *example-todo-next-id* 1)
          (example-result (format nil "Cleared ~D todos" count)
                          :details (todo-details :clear))))
       (t
        (example-result (format nil "Unknown action: ~A" action)
                        :details (todo-details :list
                                               (format nil "unknown action: ~A"
                                                       action)))))))
 :render-call
 (lambda (arguments render-context theme)
   (declare (ignore render-context theme))
   (format nil "todo ~A~@[ ~S~]~@[ #~D~]"
           (example-argument arguments "action" "list")
           (example-argument arguments "text" nil)
           (example-argument arguments "id" nil)))
 :render-result
 (lambda (result options render-context theme)
   (declare (ignore options render-context theme))
   (example-tool-result-text result)))

(cadr-agent:define-command
 "todos"
 :description "Show all todos on the current branch"
 :handler
 (lambda (arguments context)
   (declare (ignore arguments))
   (if (not (cadr-agent:extension-context-has-ui-p context))
       (cadr-agent:extension-context-notify
        context "/todos requires interactive mode" :level :error)
       (example-show-dialog
        context "Todos"
        (if *example-todos*
            (append
             (list
              (format nil "~D/~D completed"
                      (count-if (lambda (todo) (getf todo :done-p))
                                *example-todos*)
                      (length *example-todos*))
              "")
             (mapcar
              (lambda (todo)
                (format nil "~:[○~;✓~] #~D ~A"
                        (getf todo :done-p)
                        (getf todo :id) (getf todo :text)))
              *example-todos*))
            '("No todos yet. Ask the agent to add some!"))))))
