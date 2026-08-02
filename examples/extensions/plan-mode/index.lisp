(load (merge-pathnames "../support.lisp" *load-truename*))
(load (merge-pathnames "utils.lisp" *load-truename*))

(defparameter *plan-mode-plan-tools*
  '("read" "bash" "grep" "find" "ls" "questionnaire"))
(defparameter *plan-mode-normal-tools* '("read" "bash" "edit" "write"))
(defvar *plan-mode-active-p* nil)
(defvar *plan-mode-executing-p* nil)
(defvar *plan-mode-items* nil)
(defvar *plan-mode-prior-tools* nil)

(defun plan-mode-persist ()
  (cadr-agent:extension-api-append-entry
   *example-api* "plan-mode"
   (list :enabled *plan-mode-active-p*
         :executing *plan-mode-executing-p*
         :todos
         (mapcar
          (lambda (item)
            (list :step (plan-mode-todo-item-step item)
                  :text (plan-mode-todo-item-text item)
                  :completed-p (plan-mode-todo-item-completed-p item)))
          *plan-mode-items*)
         :prior-tools *plan-mode-prior-tools*)))

(defun plan-mode-update-ui (context)
  (cond
    (*plan-mode-executing-p*
     (let ((completed
             (count-if #'plan-mode-todo-item-completed-p
                       *plan-mode-items*)))
       (cadr-agent:extension-context-set-status
        context "plan-mode"
        (format nil "plan ~D/~D" completed (length *plan-mode-items*)))
       (cadr-agent:extension-context-set-widget
        context "plan-todos"
        (mapcar
         (lambda (item)
           (format nil "~:[☐~;☑~] ~A"
                   (plan-mode-todo-item-completed-p item)
                   (plan-mode-todo-item-text item)))
         *plan-mode-items*))))
    (*plan-mode-active-p*
     (cadr-agent:extension-context-set-status context "plan-mode" "plan")
     (cadr-agent:extension-context-set-widget context "plan-todos" nil))
    (t
     (cadr-agent:extension-context-set-status context "plan-mode" nil)
     (cadr-agent:extension-context-set-widget context "plan-todos" nil))))

(defun plan-mode-enable-tools ()
  (unless *plan-mode-prior-tools*
    (setf *plan-mode-prior-tools*
          (cadr-agent:extension-api-get-active-tools *example-api*)))
  (cadr-agent:extension-api-set-active-tools
   *example-api*
   (remove-duplicates
    (append
     (remove-if (lambda (name) (member name '("edit" "write") :test #'string=))
                *plan-mode-prior-tools*)
     *plan-mode-plan-tools*)
    :test #'string=)))

(defun plan-mode-restore-tools ()
  (cadr-agent:extension-api-set-active-tools
   *example-api*
   (or *plan-mode-prior-tools* *plan-mode-normal-tools*))
  (setf *plan-mode-prior-tools* nil))

(defun plan-mode-toggle (context)
  (setf *plan-mode-active-p* (not *plan-mode-active-p*)
        *plan-mode-executing-p* nil
        *plan-mode-items* nil)
  (if *plan-mode-active-p*
      (progn
        (plan-mode-enable-tools)
        (cadr-agent:extension-context-notify
         context "Plan mode enabled. Built-in write tools disabled."))
      (progn
        (plan-mode-restore-tools)
        (cadr-agent:extension-context-notify
         context "Plan mode disabled. Full access restored.")))
  (plan-mode-update-ui context)
  (plan-mode-persist))

(cadr-agent:define-flag
 "plan" :description "Start in plan mode (read-only exploration)"
 :type :boolean :default nil)

(cadr-agent:define-command
 "plan" :description "Toggle plan mode (read-only exploration)"
 :handler
 (lambda (arguments context)
   (declare (ignore arguments))
   (plan-mode-toggle context)))

(cadr-agent:define-command
 "todos" :description "Show current plan todo list"
 :handler
 (lambda (arguments context)
   (declare (ignore arguments))
   (cadr-agent:extension-context-notify
    context
    (if *plan-mode-items*
        (format nil "Plan Progress:~%~{~A~^~%~}"
                (mapcar
                 (lambda (item)
                   (format nil "~D. ~:[○~;✓~] ~A"
                           (plan-mode-todo-item-step item)
                           (plan-mode-todo-item-completed-p item)
                           (plan-mode-todo-item-text item)))
                 *plan-mode-items*))
        "No todos. Create a plan first with /plan"))))

(cadr-agent:define-shortcut
 "ctrl+alt+p" :description "Toggle plan mode"
 :handler (lambda (context) (plan-mode-toggle context)))

(cadr-agent:define-event-hook
 :tool-call-before :priority 100
 :handler
 (lambda (event context)
   (declare (ignore context))
   (when *plan-mode-active-p*
     (let ((call (cadr-agent:extension-event-tool-call event)))
       (when (and (string= (cadr-ai:tool-call-name call) "bash")
                  (not (plan-mode-safe-command-p
                        (or (cadr-ai::json-get
                             (cadr-ai:tool-call-arguments call) "command") ""))))
         (cadr-agent:make-extension-hook-result
          :block-p t
          :reason "Plan mode: command blocked (not allowlisted). Use /plan to disable plan mode first."))))))

(cadr-agent:define-event-hook
 :context
 :handler
 (lambda (event context)
   (declare (ignore context))
   (unless *plan-mode-active-p*
     (let ((messages (example-event-value event :messages)))
       (list :messages
             (remove-if
              (lambda (message)
                (and (typep message 'cadr-ai:user-message)
                     (search "[PLAN MODE ACTIVE]"
                             (cadr-ai:user-message-content message))))
              messages))))))

(cadr-agent:define-event-hook
 :before-agent-start
 :handler
 (lambda (event context)
   (declare (ignore context))
   (cond
     (*plan-mode-active-p*
      (list
       :system-prompt
       (format nil
               "~A~%~%[PLAN MODE ACTIVE]~%Explore read-only. Built-in edit and write tools are disabled. Bash is restricted to allowlisted read-only commands. Produce a numbered plan under a Plan: heading."
               (example-event-value event :system-prompt))))
     ((and *plan-mode-executing-p* *plan-mode-items*)
      (list
       :system-prompt
       (format nil
               "~A~%~%[EXECUTING PLAN]~%Remaining steps:~%~{~D. ~A~%~}Include [DONE:n] after completing each step."
               (example-event-value event :system-prompt)
               (loop for item in *plan-mode-items*
                     unless (plan-mode-todo-item-completed-p item)
                       append (list (plan-mode-todo-item-step item)
                                    (plan-mode-todo-item-text item)))))))))

(cadr-agent:define-event-hook
 :turn-end
 :handler
 (lambda (event context)
   (when (and *plan-mode-executing-p* *plan-mode-items*)
     (let ((message (cadr-agent:extension-event-message event)))
       (when (typep message 'cadr-ai:assistant-message)
         (let ((text
                 (with-output-to-string (output)
                   (dolist (block (cadr-ai:assistant-message-content message))
                     (when (typep block 'cadr-ai:text-content)
                       (write-string (cadr-ai:text-content-text block) output))))))
           (when (plusp (plan-mode-mark-completed-steps text *plan-mode-items*))
             (plan-mode-update-ui context)))))
     (plan-mode-persist))))

(cadr-agent:define-event-hook
 :agent-end
 :handler
 (lambda (event context)
   (when (and *plan-mode-executing-p* *plan-mode-items*
              (every #'plan-mode-todo-item-completed-p *plan-mode-items*))
     (cadr-agent:extension-api-send-message
      *example-api*
      (list :custom-type "plan-complete"
            :content "**Plan Complete!** ✓" :display t)
      :trigger-turn-p nil)
     (setf *plan-mode-executing-p* nil *plan-mode-items* nil)
     (plan-mode-update-ui context)
     (plan-mode-persist))
   (when (and *plan-mode-active-p* (not *plan-mode-executing-p*))
     (let* ((messages (example-event-value event :messages))
            (last (find-if (lambda (message)
                             (typep message 'cadr-ai:assistant-message))
                           (reverse messages))))
       (when last
         (let ((text
                 (with-output-to-string (output)
                   (dolist (block (cadr-ai:assistant-message-content last))
                     (when (typep block 'cadr-ai:text-content)
                       (write-string (cadr-ai:text-content-text block) output))))))
           (setf *plan-mode-items* (plan-mode-extract-todo-items text))))
       (when *plan-mode-items*
         (plan-mode-persist)
         (let ((choice
                 (cadr-agent:extension-context-select
                  context "Plan mode - what next?"
                  '("Execute the plan (track progress)"
                    "Stay in plan mode" "Refine the plan"))))
           (cond
             ((and choice (uiop:string-prefix-p "Execute" choice))
              (setf *plan-mode-active-p* nil *plan-mode-executing-p* t)
              (plan-mode-restore-tools)
              (plan-mode-update-ui context)
              (plan-mode-persist)
              (cadr-agent:extension-api-send-user-message
               *example-api* "Execute the plan. Include [DONE:n] after each completed step."
               :deliver-as :follow-up))
             ((string= (or choice "") "Refine the plan")
              (let ((refinement
                      (cadr-agent:extension-context-editor
                       context "Refine the plan:" :prefill "")))
                (when (and refinement (plusp (length (example-trim refinement))))
                  (cadr-agent:extension-api-send-user-message
                   *example-api* (example-trim refinement)
                   :deliver-as :follow-up)))))))))))

(cadr-agent:define-event-hook
 :session-start
 :handler
 (lambda (event context)
   (declare (ignore event))
   (when (eq t (cadr-agent:extension-api-get-flag *example-api* "plan"))
     (setf *plan-mode-active-p* t))
   (dolist (entry (example-session-entries context))
     (when (and (eq (cadr-agent:session-entry-type entry) :custom)
                (string= (or (cadr-agent:session-entry-custom-type entry) "")
                         "plan-mode"))
       (let ((data (cadr-agent:session-entry-data entry)))
         (setf *plan-mode-active-p* (getf data :enabled *plan-mode-active-p*)
               *plan-mode-executing-p* (getf data :executing nil)
               *plan-mode-prior-tools* (getf data :prior-tools nil)
               *plan-mode-items*
               (mapcar
                (lambda (row)
                  (make-plan-mode-todo-item
                   :step (getf row :step)
                   :text (getf row :text)
                   :completed-p (not (null (getf row :completed-p)))))
                (getf data :todos nil))))))
   (when *plan-mode-active-p* (plan-mode-enable-tools))
   (plan-mode-update-ui context)))
