(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

;;; Locks packages/coding-agent AgentSession._preparePromptAndToolLoadout
;;; section-only emission against baseline v0.86.0 agent-session.ts.

(defun goal24-loadout-tool (name)
  (cadr-ai:make-tool
   :name name
   :description (format nil "~A tool" name)
   :parameters
   (cadr-ai::json-object
    "type" "object"
    "properties" (cadr-ai::json-object))
   :executor
   (lambda (&rest args)
     (declare (ignore args))
     (list :content nil :details nil))))

(defun goal24-loadout-lookup (&rest tools)
  (let ((by-name (make-hash-table :test #'equal)))
    (dolist (tool tools)
      (setf (gethash (cadr-ai:tool-name tool) by-name) tool))
    (lambda (name) (gethash name by-name))))

(test goal24-prepare-prompt-loadout-nil-when-sections-unchanged
  (let* ((options
           (cadr-cli:normalize-build-system-prompt-options
            :cwd "/tmp"
            :selected-tools '("read")
            :sections '(("plan_mode" . "Plan only."))))
         (sections
           (apply #'cadr-cli:build-system-prompt-sections options))
         (messages
           (list
            (cadr-ai:make-system-message
             :content ""
             :sections sections
             :timestamp 1)))
         (lookup (goal24-loadout-lookup (goal24-loadout-tool "read"))))
    (multiple-value-bind (update selected)
        (cadr-cli:prepare-prompt-and-tool-loadout
         options messages lookup)
      (is (null update))
      (is (= 1 (length selected)))
      (is (string= "read" (cadr-ai:tool-name (first selected)))))))

(test goal24-prepare-prompt-loadout-emits-sections-patch-only
  (let* ((previous-options
           (cadr-cli:normalize-build-system-prompt-options
            :cwd "/tmp"
            :selected-tools '("read")
            :sections '(("plan_mode" . "Plan only."))))
         (current-options
           (cadr-cli:normalize-build-system-prompt-options
            :cwd "/work"
            :selected-tools '("read")
            :sections
            '(("plan_mode" . "Implementation allowed."))))
         (messages
           (list
            (cadr-ai:make-system-message
             :content ""
             :sections
             (apply #'cadr-cli:build-system-prompt-sections
                    previous-options)
             :timestamp 1)))
         (lookup (goal24-loadout-lookup (goal24-loadout-tool "read"))))
    (multiple-value-bind (update selected)
        (cadr-cli:prepare-prompt-and-tool-loadout
         current-options messages lookup)
      (is (typep update 'cadr-ai:system-message))
      (is (string= "" (cadr-ai:system-message-content update)))
      (is (null (cadr-ai:system-message-tools-added update)))
      (is (null (cadr-ai:system-message-tools-removed update)))
      (is (equal
           (cadr-cli:diff-system-prompt-sections
            (apply #'cadr-cli:build-system-prompt-sections
                   previous-options)
            (apply #'cadr-cli:build-system-prompt-sections
                   current-options))
           (cadr-ai:system-message-sections update)))
      (is (assoc "plan_mode"
                 (cadr-ai:system-message-sections update)
                 :test #'string=))
      (is (assoc "cwd"
                 (cadr-ai:system-message-sections update)
                 :test #'string=))
      (is (= 1 (length selected))))))
