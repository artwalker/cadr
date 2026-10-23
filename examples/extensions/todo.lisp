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

(defun todo-theme-bold (theme text)
  (let ((bold (and (listp theme) (getf theme :bold))))
    (if (functionp bold)
        (funcall bold (or text ""))
        (or text ""))))

(defun todo-render-call (arguments theme context)
  ;; The host calls this as (arguments theme context).
  (declare (ignore context))
  (let ((text
          (concatenate
           'string
           (example-theme-fg
            theme :tool-title (todo-theme-bold theme "todo "))
           (example-theme-fg
            theme :muted
            (or (example-argument arguments "action" nil) ""))))
        (arg-text (example-argument arguments "text" nil))
        (id (example-argument arguments "id" nil)))
    (when (and (stringp arg-text) (plusp (length arg-text)))
      (setf text
            (concatenate
             'string text " "
             (example-theme-fg
              theme :dim (format nil "\"~A\"" arg-text)))))
    (when id
      (setf text
            (concatenate
             'string text " "
             (example-theme-fg
              theme :accent (format nil "#~A" id)))))
    text))

(defun todo-render-list (todos expanded-p theme)
  (if (null todos)
      (example-theme-fg theme :dim "No todos")
      (let ((display
              (if expanded-p
                  todos
                  (subseq todos 0 (min 5 (length todos)))))
            (text
              (example-theme-fg
               theme :muted
               (format nil "~D todo(s):" (length todos)))))
        (dolist (todo display)
          (let ((done-p (getf todo :done-p)))
            (setf text
                  (concatenate
                   'string text
                   (string #\Newline)
                   (example-theme-fg
                    theme (if done-p :success :dim)
                    (if done-p "✓" "○"))
                   " "
                   (example-theme-fg
                    theme :accent
                    (format nil "#~A" (getf todo :id)))
                   " "
                   (example-theme-fg
                    theme (if done-p :dim :muted)
                    (or (getf todo :text) ""))))))
        (when (and (not expanded-p) (> (length todos) 5))
          (setf text
                (concatenate
                 'string text
                 (string #\Newline)
                 (example-theme-fg
                  theme :dim
                  (format nil "... ~D more" (- (length todos) 5))))))
        text)))

(defun todo-render-result (result options theme context)
  ;; The host calls this as (result options theme context).
  (declare (ignore context))
  (let ((details
          (and (typep result 'cadr-ai:tool-result-message)
               (cadr-ai:tool-result-message-details result))))
    (cond
      ((null details)
       (example-tool-result-text result))
      ((getf details :error)
       (example-theme-fg
        theme :error
        (format nil "Error: ~A" (getf details :error))))
      (t
       (let ((todos (getf details :todos))
             (action (getf details :action)))
         (case action
           (:list
            (todo-render-list
             todos (getf options :expanded-p) theme))
           (:add
            (let ((added (car (last todos))))
              (if (null added)
                  (example-tool-result-text result)
                  (concatenate
                   'string
                   (example-theme-fg theme :success "✓ Added ")
                   (example-theme-fg
                    theme :accent
                    (format nil "#~A" (getf added :id)))
                   " "
                   (example-theme-fg
                    theme :muted (or (getf added :text) ""))))))
           (:toggle
            (concatenate
             'string
             (example-theme-fg theme :success "✓ ")
             (example-theme-fg
              theme :muted (example-tool-result-text result))))
           (:clear
            (concatenate
             'string
             (example-theme-fg theme :success "✓ ")
             (example-theme-fg theme :muted "Cleared all todos")))
           (t (example-tool-result-text result))))))))

(cadr-agent:define-event-hook
 :session-start
 :handler
 (lambda (event context)
   (declare (ignore event))
   (todo-restore context)
   nil))

(cadr-agent:define-event-hook
 :session-tree
 :handler
 (lambda (event context)
   (declare (ignore event))
   (todo-restore context)
   nil))

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
        (example-text-result (todo-format-list) (todo-details :list)))
       ((string= action "add")
        (let ((text (example-argument arguments "text" nil)))
          (if (or (null text) (zerop (length (example-trim text))))
              (example-text-result "Error: text required for add"
                                   (todo-details :add "text required"))
              (let ((todo (list :id *example-todo-next-id*
                                :text text :done-p nil)))
                (incf *example-todo-next-id*)
                (setf *example-todos* (append *example-todos* (list todo)))
                (example-text-result
                 (format nil "Added todo #~D: ~A"
                         (getf todo :id) (getf todo :text))
                 (todo-details :add))))))
       ((string= action "toggle")
        (let* ((id (example-argument arguments "id" nil))
               (todo (and id (find id *example-todos*
                                   :key (lambda (row) (getf row :id))))))
          (cond
            ((null id)
             (example-text-result "Error: id required for toggle"
                                  (todo-details :toggle "id required")))
            ((null todo)
             (example-text-result
              (format nil "Todo #~D not found" id)
              (todo-details :toggle
                            (format nil "#~D not found" id))))
            (t
             (setf (getf todo :done-p) (not (getf todo :done-p)))
             (example-text-result
              (format nil "Todo #~D ~:[uncompleted~;completed~]"
                      id (getf todo :done-p))
              (todo-details :toggle))))))
       ((string= action "clear")
        (let ((count (length *example-todos*)))
          (setf *example-todos* nil *example-todo-next-id* 1)
          (example-text-result (format nil "Cleared ~D todos" count)
                               (todo-details :clear))))
       (t
        (example-text-result (format nil "Unknown action: ~A" action)
                             (todo-details :list
                                           (format nil "unknown action: ~A"
                                                   action)))))))
 :render-call #'todo-render-call
 :render-result #'todo-render-result)

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
