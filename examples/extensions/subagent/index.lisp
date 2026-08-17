(load (merge-pathnames "../support.lisp" *load-truename*))
(load (merge-pathnames "agents.lisp" *load-truename*))

(defconstant +subagent-max-parallel-tasks+ 8)
(defconstant +subagent-max-concurrency+ 4)
(defconstant +subagent-per-task-output-cap+ (* 50 1024))

(defun subagent-task-schema ()
  (cadr-ai::json-object
   "type" "object"
   "properties"
   (cadr-ai::json-object
    "agent" (cadr-ai::json-object "type" "string")
    "task" (cadr-ai::json-object "type" "string")
    "cwd" (cadr-ai::json-object "type" "string"))
   "required" #("agent" "task")
   "additionalProperties" nil))

(defun subagent-parameters-schema ()
  (cadr-ai::json-object
   "type" "object"
   "properties"
   (cadr-ai::json-object
    "agent" (cadr-ai::json-object "type" "string")
    "task" (cadr-ai::json-object "type" "string")
    "tasks" (cadr-ai::json-object
             "type" "array" "items" (subagent-task-schema))
    "chain" (cadr-ai::json-object
             "type" "array" "items" (subagent-task-schema))
    "agentScope" (cadr-ai::json-object
                  "type" "string"
                  "enum" #("user" "project" "both")
                  "default" "user")
    "confirmProjectAgents" (cadr-ai::json-object
                            "type" "boolean" "default" t)
    "cwd" (cadr-ai::json-object "type" "string"))
   "additionalProperties" nil))

(defun subagent-array-list (value)
  (cond ((vectorp value) (coerce value 'list))
        ((listp value) value)
        (t nil)))

(defun subagent-replace-previous (template previous)
  (cadr-ai::replace-all template "{previous}" previous))

(defun subagent-message-text (message)
  (let ((content (and message (cadr-ai::json-get message "content"))))
    (with-output-to-string (output)
      (loop for block across (coerce (or content #()) 'vector)
            when (string= "text" (or (cadr-ai::json-get block "type") ""))
              do (write-string
                  (or (cadr-ai::json-get block "text") "") output)))))

(defun subagent-final-json-output (stdout)
  (let ((last-message nil))
    (dolist (line (uiop:split-string stdout :separator '(#\Newline)))
      (unless (zerop (length (example-trim line)))
        (let ((event (ignore-errors (cadr-ai::parse-json line))))
          (when (and event
                     (string= "message_end"
                              (or (cadr-ai::json-get event "type") ""))
                     (string= "assistant"
                              (or (cadr-ai::json-get
                                   (cadr-ai::json-get event "message") "role")
                                  "")))
            (setf last-message (cadr-ai::json-get event "message"))))))
    (subagent-message-text last-message)))

(defun subagent-safe-name (name)
  (map 'string
       (lambda (character)
         (if (or (alphanumericp character)
                 (find character ".-_"))
             character #\_))
       name))

(defun subagent-shell-quote (value)
  (format nil "'~A'"
          (with-output-to-string (output)
            (loop for character across (princ-to-string value)
                  if (char= character #\')
                    do (write-string "'\\''" output)
                  else
                    do (write-char character output)))))

(defun subagent-program ()
  (or
   (uiop:getenv "CADR_EXECUTABLE")
   (let ((candidate
           (merge-pathnames
            "cadr" (asdf:system-source-directory "cadr-cli"))))
     (and (probe-file candidate) (namestring (truename candidate))))
   "cadr"))

(defun subagent-command-string (program arguments)
  (format nil "~{~A~^ ~}"
          (mapcar #'subagent-shell-quote
                  (cons program arguments))))

(defun subagent-run-one
    (definition task default-cwd cwd signal on-update &key step)
  (let* ((name (getf definition :name))
         (prompt (or (getf definition :system-prompt) ""))
         (temporary-directory
           (uiop:ensure-directory-pathname
            (merge-pathnames
             (format nil "cadr-subagent-~A-~A/"
                     (subagent-safe-name name) (cadr-ai:uuid-v7))
             (uiop:temporary-directory))))
         (prompt-path (merge-pathnames "prompt.md" temporary-directory))
         (arguments (list "--mode" "json" "--print" "--no-session"))
         (working-directory (or cwd default-cwd)))
    (ensure-directories-exist prompt-path)
    (unwind-protect
         (progn
           (when (plusp (length (example-trim prompt)))
             (cadr-agent:with-file-mutation-queue (prompt-path)
                (with-open-file
                    (stream prompt-path :direction :output
                                        :if-exists :supersede
                                        :if-does-not-exist :create
                                        :external-format :utf-8)
                  (write-string prompt stream)))
             (setf arguments
                   (append arguments
                           (list "--append-system-prompt"
                                 (namestring prompt-path)))))
           (when (getf definition :model)
             (setf arguments
                   (append arguments
                           (list "--model" (getf definition :model)))))
           (when (getf definition :tools)
             (setf arguments
                   (append arguments
                           (list "--tools"
                                 (format nil "~{~A~^,~}"
                                         (getf definition :tools))))))
           (setf arguments (append arguments (list (format nil "Task: ~A" task))))
           (when (cadr-agent:extension-cancellation-aborted-p signal)
             (return-from subagent-run-one
               (list :agent name :source (getf definition :source)
                     :task task :exit-code 1 :output "Subagent was aborted"
                     :step step :aborted-p t)))
           (funcall on-update (format nil "Running ~A~@[ (step ~D)~]…"
                                      name step))
           (multiple-value-bind (result operation-error)
               (cadr-agent:execution-env-exec
                (cadr-agent:make-node-execution-env
                 :cwd working-directory)
                (subagent-command-string
                 (subagent-program) arguments)
                :cwd (namestring
                      (uiop:ensure-directory-pathname working-directory))
                :timeout 600 :signal signal)
             (when operation-error
               (return-from subagent-run-one
                 (list
                  :agent name :source (getf definition :source)
                  :task task
                  :exit-code
                  (if (eq :aborted
                          (cadr-agent:harness-operation-error-code
                           operation-error))
                      130 1)
                  :output
                  (cadr-agent:harness-operation-error-message
                   operation-error)
                  :step step
                  :aborted-p
                  (eq :aborted
                      (cadr-agent:harness-operation-error-code
                       operation-error)))))
             (let* ((stdout (cadr-agent:execution-result-stdout result))
                  (stderr (cadr-agent:execution-result-stderr result))
                  (output (subagent-final-json-output stdout)))
             (when (zerop (length output))
               (setf output (if (plusp (length stderr)) stderr stdout)))
             (list :agent name :source (getf definition :source)
                   :task task
                   :exit-code (cadr-agent:execution-result-exit-code result)
                   :output (or output "") :stderr stderr :step step))))
      (ignore-errors (delete-file prompt-path))
      (ignore-errors (uiop:delete-directory-tree temporary-directory
                                                  :validate t)))))

(defun subagent-result-failed-p (result)
  (not (zerop (getf result :exit-code 1))))

(defun subagent-find-definition (agents name)
  (find name agents :key (lambda (entry) (getf entry :name)) :test #'string=))

(defun subagent-run-parallel
    (items agents default-cwd signal on-update)
  (let* ((count (length items))
         (results (make-array count :initial-element nil))
         (next 0)
         (done 0)
         (lock (sb-thread:make-mutex :name "subagent parallel queue")))
    (labels ((take-index ()
               (sb-thread:with-mutex (lock)
                 (when (< next count) (prog1 next (incf next)))))
             (worker ()
               (loop for index = (take-index) while index
                     for item = (nth index items)
                     for name = (cadr-ai::json-get item "agent")
                     for definition = (subagent-find-definition agents name)
                     do
                     (setf (aref results index)
                           (if definition
                               (subagent-run-one
                                definition
                                (or (cadr-ai::json-get item "task") "")
                                default-cwd (cadr-ai::json-get item "cwd")
                                signal on-update)
                               (list :agent name :source :unknown
                                     :task (cadr-ai::json-get item "task")
                                     :exit-code 1
                                     :output (format nil "Unknown agent: ~A" name))))
                     (sb-thread:with-mutex (lock)
                       (incf done)
                       (funcall on-update
                                (format nil "Parallel: ~D/~D done, ~D running…"
                                        done count (- count done)))))))
      (let ((threads
              (loop repeat (min +subagent-max-concurrency+ count)
                    collect (sb-thread:make-thread #'worker
                                                   :name "cadr subagent worker"))))
        (dolist (thread threads) (sb-thread:join-thread thread))))
    (coerce results 'list)))

(defun subagent-render-results (mode results)
  (if (eq mode :parallel)
      (format nil "Parallel: ~D/~D succeeded~%~%~{~A~^~%~%---~%~%~}"
              (count-if-not #'subagent-result-failed-p results)
              (length results)
              (mapcar
               (lambda (result)
                 (let* ((output (getf result :output))
                        (truncated
                          (cadr-agent:truncate-head
                           output :max-bytes +subagent-per-task-output-cap+)))
                   (format nil "### [~A] ~A~%~%~A"
                           (getf result :agent)
                           (if (subagent-result-failed-p result)
                               "failed" "completed")
                           (cadr-agent:truncation-result-content truncated))))
               results))
      (or (getf (car (last results)) :output) "(no output)")))

(cadr-agent:define-rich-tool
 "subagent"
 :label "Subagent"
 :description
 "Delegate isolated work in exactly one mode: single, parallel (max 8, concurrency 4), or chain with {previous}."
 :parameters (subagent-parameters-schema)
 :handler
 (lambda (call-id arguments signal on-update context)
   (declare (ignore call-id))
   (block subagent-handler
   (let* ((scope-name (or (example-argument arguments "agentScope") "user"))
          (scope (intern (string-upcase scope-name) :keyword))
          (discovery
            (discover-subagents (cadr-agent:extension-context-cwd context) scope))
          (agents (getf discovery :agents))
          (single-p (and (example-argument arguments "agent")
                         (example-argument arguments "task")))
          (tasks (subagent-array-list (example-argument arguments "tasks")))
          (chain (subagent-array-list (example-argument arguments "chain")))
          (mode-count (+ (if single-p 1 0)
                         (if tasks 1 0) (if chain 1 0))))
     (unless (= mode-count 1)
       (return-from subagent-handler
         (example-result
          (format nil "Invalid parameters. Provide exactly one mode.~%Available agents: ~{~A~^, ~}"
                  (mapcar (lambda (entry) (getf entry :name)) agents)))))
     (let* ((requested
              (remove-duplicates
               (cond
                 (single-p (list (example-argument arguments "agent")))
                 (tasks (mapcar (lambda (item)
                                  (cadr-ai::json-get item "agent")) tasks))
                 (t (mapcar (lambda (item)
                              (cadr-ai::json-get item "agent")) chain)))
               :test #'string=))
            (project-agents
              (remove-if-not
               (lambda (definition)
                 (and definition (eq :project (getf definition :source))))
               (mapcar (lambda (name)
                         (subagent-find-definition agents name))
                       requested))))
       (when (and project-agents
                  (example-boolean
                   (example-argument arguments "confirmProjectAgents" t))
                  (cadr-agent:extension-context-has-ui-p context)
                  (not (cadr-agent:extension-context-confirm
                        context "Run project-local agents?"
                        (format nil "Agents: ~{~A~^, ~}~%Source: ~A~%~%Project agents are repo-controlled. Only continue for trusted repositories."
                                (mapcar (lambda (entry) (getf entry :name))
                                        project-agents)
                                (or (getf discovery :project-agents-directory)
                                    "(unknown)")))))
         (return-from subagent-handler
           (example-result "Canceled: project-local agents not approved."))))
     (cond
       (single-p
        (let* ((name (example-argument arguments "agent"))
               (definition (subagent-find-definition agents name))
               (result
                 (if definition
                     (subagent-run-one
                      definition (example-argument arguments "task")
                      (cadr-agent:extension-context-cwd context)
                      (example-argument arguments "cwd")
                      signal on-update)
                     (list :agent name :source :unknown :exit-code 1
                           :output (format nil "Unknown agent: ~A" name)))))
          (values (list (cadr-ai:make-text-content
                         :text (getf result :output)))
                  (list :mode :single :agent-scope scope
                        :project-agents-directory
                        (getf discovery :project-agents-directory)
                        :results (list result))
                  nil)))
       (tasks
        (when (> (length tasks) +subagent-max-parallel-tasks+)
          (return-from subagent-handler
            (example-result
             (format nil "Too many parallel tasks (~D). Max is ~D."
                     (length tasks) +subagent-max-parallel-tasks+))))
        (let ((results
                (subagent-run-parallel
                 tasks agents (cadr-agent:extension-context-cwd context)
                 signal on-update)))
          (example-text-result
           (subagent-render-results :parallel results)
           (list :mode :parallel :agent-scope scope
                 :project-agents-directory
                 (getf discovery :project-agents-directory)
                 :results results))))
       (t
        (let ((results nil) (previous ""))
          (loop for item in chain for step from 1
                for name = (cadr-ai::json-get item "agent")
                for definition = (subagent-find-definition agents name)
                for result =
                (if definition
                    (subagent-run-one
                     definition
                     (subagent-replace-previous
                      (or (cadr-ai::json-get item "task") "") previous)
                     (cadr-agent:extension-context-cwd context)
                     (cadr-ai::json-get item "cwd") signal on-update :step step)
                    (list :agent name :source :unknown :exit-code 1
                          :output (format nil "Unknown agent: ~A" name)))
                do (push result results)
                   (setf previous (getf result :output))
                when (subagent-result-failed-p result) do (loop-finish))
          (setf results (nreverse results))
          (example-text-result
           (subagent-render-results :chain results)
           (list :mode :chain :agent-scope scope
                 :project-agents-directory
                 (getf discovery :project-agents-directory)
                 :results results)))))))))
