(in-package #:cadr-cli/tests)

(in-suite cadr-cli-suite)

(defun goal27-todo-arguments (&rest pairs)
  (let ((arguments (make-hash-table :test #'equal)))
    (loop for (key value) on pairs by #'cddr
          do (setf (gethash key arguments) value))
    arguments))

(defun goal27-todo-tool (host)
  (find "todo"
        (cadr-agent::extension-snapshot-tools
         (cadr-agent::extension-host-current-snapshot host))
        :key #'cadr-agent::extension-tool-definition-name
        :test #'string=))

(defun goal27-todo-content-text (content)
  (cadr-ai:text-content-text (first content)))

(defun goal27-todo-execute (tool arguments)
  (multiple-value-bind (content details)
      (funcall (cadr-agent::extension-tool-definition-handler tool)
               "todo-call" arguments nil nil nil)
    (values
     (cadr-ai:make-tool-result-message
      :tool-call-id "todo-call"
      :tool-name "todo"
      :content content
      :details details)
     (goal27-todo-content-text content))))

(defun goal27-todo-theme ()
  (cadr-cli::tui-extension-theme-runtime))

(defun goal27-todo-fg (theme token text)
  (funcall (getf theme :fg) token text))

(defun goal27-todo-paint (host message theme &key expanded-p)
  (multiple-value-bind (rendered handled-p)
      (cadr-agent::render-extension-tool-result
       host "todo" message
       (list :expanded-p expanded-p :partial-p nil)
       (list :theme theme :expanded-p expanded-p))
    (values rendered handled-p)))

(defun goal27-todo-visible (rendered width)
  (mapcar #'cadr-tui::strip-ansi
          (cadr-cli::extension-render-value-lines rendered width)))

(defmacro with-goal27-todo ((host tool theme) &body body)
  `(let ((root (asdf:system-source-directory "cadr-cli")))
     (with-test-directory (temporary)
       (let* ((output (make-string-output-stream))
              (manager
                (make-test-extension-manager
                 temporary (merge-pathnames "global/" temporary)
                 output
                 (list
                  (merge-pathnames
                   "examples/extensions/todo.lisp" root))))
              (report (cadr-cli::reload-cli-extensions manager))
              (,host (cadr-cli::cli-extension-manager-host manager))
              (,tool (goal27-todo-tool ,host))
              (,theme (goal27-todo-theme)))
         (is (null (getf report :errors)))
         (is (not (null ,tool)))
         ,@body))))

(test goal27-todo-add-confirmation-is-a-success-check
  ;; v1.4.0 todo.ts renderResult add: success "✓ Added ", accent "#id",
  ;; muted text. execute() content stays "Added todo #id: text".
  (with-goal27-todo (host tool theme)
    (multiple-value-bind (message content)
        (goal27-todo-execute
         tool (goal27-todo-arguments "action" "add" "text" "first"))
      (is (string= "Added todo #1: first" content))
      (multiple-value-bind (rendered handled-p)
          (goal27-todo-paint host message theme)
        (is-true handled-p)
        (is (string=
             rendered
             (concatenate
              'string
              (goal27-todo-fg theme :success "✓ Added ")
              (goal27-todo-fg theme :accent "#1")
              " "
              (goal27-todo-fg theme :muted "first"))))
        (is (equal '("✓ Added #1 first")
                   (goal27-todo-visible rendered 80)))
        (is (equal '("✓ Added #1 first")
                   (goal27-todo-visible rendered 40)))))
    (multiple-value-bind (call handled-p)
        (cadr-agent::render-extension-tool-call
         host "todo"
         (goal27-todo-arguments "action" "add" "text" "first")
         (list :theme theme))
      (is-true handled-p)
      (is (string=
           call
           (concatenate
            'string
            (goal27-todo-fg
             theme :tool-title
             (funcall (getf theme :bold) "todo "))
            (goal27-todo-fg theme :muted "add")
            " "
            (goal27-todo-fg theme :dim "\"first\""))))
      (is (equal '("todo add \"first\"")
                 (goal27-todo-visible call 80))))))

(test goal27-todo-result-renderer-matches-upstream-branches
  (with-goal27-todo (host tool theme)
    (multiple-value-bind (empty content)
        (goal27-todo-execute
         tool (goal27-todo-arguments "action" "list"))
      (is (string= "No todos" content))
      (multiple-value-bind (rendered handled-p)
          (goal27-todo-paint host empty theme)
        (is-true handled-p)
        (is (string= rendered (goal27-todo-fg theme :dim "No todos")))
        (is (equal '("No todos") (goal27-todo-visible rendered 80)))))
    (let ((texts '("one" "two" "three" "four" "five" "six")))
      (dolist (text texts)
        (goal27-todo-execute
         tool (goal27-todo-arguments "action" "add" "text" text))))
    (multiple-value-bind (toggled content)
        (goal27-todo-execute
         tool (goal27-todo-arguments "action" "toggle" "id" 1))
      (is (string= "Todo #1 completed" content))
      (multiple-value-bind (rendered handled-p)
          (goal27-todo-paint host toggled theme)
        (is-true handled-p)
        (is (string=
             rendered
             (concatenate
              'string
              (goal27-todo-fg theme :success "✓ ")
              (goal27-todo-fg theme :muted "Todo #1 completed"))))
        (is (equal '("✓ Todo #1 completed")
                   (goal27-todo-visible rendered 80)))))
    (multiple-value-bind (listed content)
        (goal27-todo-execute
         tool (goal27-todo-arguments "action" "list"))
      (is (string= "[x] #1: one" (subseq content 0 11)))
      (multiple-value-bind (folded handled-p)
          (goal27-todo-paint host listed theme)
        (is-true handled-p)
        (is (equal
             '("6 todo(s):"
               "✓ #1 one"
               "○ #2 two"
               "○ #3 three"
               "○ #4 four"
               "○ #5 five"
               "... 1 more")
             (goal27-todo-visible folded 80)))
        (is (search (goal27-todo-fg theme :success "✓") folded))
        (is (search (goal27-todo-fg theme :dim "one") folded))
        (is (search (goal27-todo-fg theme :dim "○") folded))
        (is (search (goal27-todo-fg theme :muted "two") folded))
        (is (search (goal27-todo-fg theme :dim "... 1 more") folded)))
      (multiple-value-bind (opened handled-p)
          (goal27-todo-paint host listed theme :expanded-p t)
        (declare (ignore handled-p))
        (is (equal
             '("6 todo(s):"
               "✓ #1 one"
               "○ #2 two"
               "○ #3 three"
               "○ #4 four"
               "○ #5 five"
               "○ #6 six")
             (goal27-todo-visible opened 80)))))
    (multiple-value-bind (cleared content)
        (goal27-todo-execute
         tool (goal27-todo-arguments "action" "clear"))
      (is (string= "Cleared 6 todos" content))
      (multiple-value-bind (rendered handled-p)
          (goal27-todo-paint host cleared theme)
        (is-true handled-p)
        (is (string=
             rendered
             (concatenate
              'string
              (goal27-todo-fg theme :success "✓ ")
              (goal27-todo-fg theme :muted "Cleared all todos"))))
        (is (equal '("✓ Cleared all todos")
                   (goal27-todo-visible rendered 80)))))
    (multiple-value-bind (missing content)
        (goal27-todo-execute
         tool (goal27-todo-arguments "action" "add" "text" ""))
      (is (string= "Error: text required for add" content))
      (multiple-value-bind (rendered handled-p)
          (goal27-todo-paint host missing theme)
        (is-true handled-p)
        (is (string=
             rendered
             (goal27-todo-fg theme :error "Error: text required")))
        (is (equal '("Error: text required")
                   (goal27-todo-visible rendered 80)))))
    (multiple-value-bind (missing-id content)
        (goal27-todo-execute
         tool (goal27-todo-arguments "action" "toggle"))
      (is (string= "Error: id required for toggle" content))
      (is (equal '("Error: id required")
                 (goal27-todo-visible
                  (goal27-todo-paint host missing-id theme) 80))))
    (multiple-value-bind (absent content)
        (goal27-todo-execute
         tool (goal27-todo-arguments "action" "toggle" "id" 99))
      (is (string= "Todo #99 not found" content))
      (is (equal '("Error: #99 not found")
                 (goal27-todo-visible
                  (goal27-todo-paint host absent theme) 80))))
    (multiple-value-bind (unknown content)
        (goal27-todo-execute
         tool (goal27-todo-arguments "action" "nope"))
      (is (string= "Unknown action: nope" content))
      (is (equal '("Error: unknown action: nope")
                 (goal27-todo-visible
                  (goal27-todo-paint host unknown theme) 80))))
    (multiple-value-bind (call handled-p)
        (cadr-agent::render-extension-tool-call
         host "todo"
         (goal27-todo-arguments "action" "toggle" "text" "" "id" 0)
         (list :theme theme))
      (is-true handled-p)
      (is (equal '("todo toggle #0")
                 (goal27-todo-visible call 80)))
      (is (search (goal27-todo-fg theme :accent "#0") call)))))
