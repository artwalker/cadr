(in-package #:cadr-agent/tests)
(in-suite cadr-agent-suite)

;;; Locks packages/agent/test/agent.test.ts
;;; "declares tool loadout changes to the model before the next request"
;;; and "merges tool changes into a pending system message"
;;; against baseline v0.86.0 agent-loop.ts declareToolChanges.

(defun goal24-declare-empty-schema ()
  (cadr-ai::json-object
   "type" "object"
   "properties" (cadr-ai::json-object)))

(defun goal24-declare-tool
    (name &key (description nil) (executor nil))
  (cadr-ai:make-tool
   :name name
   :description
   (or description (format nil "~A tool" name))
   :parameters (goal24-declare-empty-schema)
   :executor executor))

(test goal24-declares-tool-loadout-changes-before-next-request
  (let* ((first (goal24-declare-tool "first"))
         (second (goal24-declare-tool "second"))
         (committed
           (list
            (cadr-ai:make-system-message
             :content "You are helpful."
             :tools-added
             (list (cadr-ai:to-tool-declaration first))
             :timestamp 0)
            (cadr-ai:make-user-message
             :content "one"
             :timestamp 1)
            (cadr-ai:make-assistant-message
             :content
             (list (cadr-ai:make-text-content :text "done"))
             :timestamp 2)))
         (pending
           (list
            (cadr-ai:make-user-message
             :content "two"
             :timestamp 3)))
         (declared
           (cadr-agent:declare-tool-changes
            committed
            (list second)
            pending))
         (update (first declared)))
    (is (= 2 (length declared)))
    (is (typep update 'cadr-ai:system-message))
    (is (string= "" (cadr-ai:system-message-content update)))
    (is (= 1 (length (cadr-ai:system-message-tools-added update))))
    (is (string=
         "second"
         (cadr-ai:tool-name
          (first (cadr-ai:system-message-tools-added update)))))
    (is (string=
         "second tool"
         (cadr-ai:tool-description
          (first (cadr-ai:system-message-tools-added update)))))
    (is (null
         (cadr-ai:tool-executor
          (first (cadr-ai:system-message-tools-added update)))))
    (is (= 1 (length (cadr-ai:system-message-tools-removed update))))
    (is (string=
         "first"
         (cadr-ai:tool-reference-name
          (first
           (cadr-ai:system-message-tools-removed update)))))
    (is (typep (second declared) 'cadr-ai:user-message))
    (let ((again
            (cadr-agent:declare-tool-changes
             (append committed declared)
             (list second)
             (list
              (cadr-ai:make-user-message
               :content "three"
               :timestamp 4)))))
      (is (equal
           '("three")
           (mapcar
            (lambda (message)
              (cadr-ai:content-text
               (cadr-ai:user-message-content message)))
            again))))))

(test goal24-merges-tool-changes-into-pending-system-message
  (let* ((tool
           (goal24-declare-tool
            "echo"
            :description "Echo input"
            :executor
            (lambda (&rest args)
              (declare (ignore args))
              (list :content nil :details nil))))
         (pending
           (list
            (cadr-ai:make-system-message
             :content ""
             :sections
             '(("skills" . "<skills>x</skills>"))
             :timestamp 1)
            (cadr-ai:make-user-message
             :content "hi"
             :timestamp 2)))
         (declared
           (cadr-agent:declare-tool-changes
            nil
            (list tool)
            pending))
         (merged (first declared)))
    (is (= 2 (length declared)))
    (is (typep merged 'cadr-ai:system-message))
    (is (= 1 (cadr-ai:system-message-timestamp merged)))
    (is (equal
         '(("skills" . "<skills>x</skills>"))
         (cadr-ai:system-message-sections merged)))
    (is (= 1 (length (cadr-ai:system-message-tools-added merged))))
    (is (string=
         "echo"
         (cadr-ai:tool-name
          (first (cadr-ai:system-message-tools-added merged)))))
    (is (string=
         "Echo input"
         (cadr-ai:tool-description
          (first (cadr-ai:system-message-tools-added merged)))))
    (is (null
         (cadr-ai:tool-executor
          (first (cadr-ai:system-message-tools-added merged)))))
    (is (null (cadr-ai:system-message-tools-removed merged)))))

(test goal24-rewrites-pending-tool-declarations-to-executable-set
  (let* ((first (goal24-declare-tool "first"))
         (second (goal24-declare-tool "second"))
         (committed
           (list
            (cadr-ai:make-system-message
             :content "You are helpful."
             :tools-added
             (list (cadr-ai:to-tool-declaration first))
             :timestamp 0)))
         (pending
           (list
            (cadr-ai:make-system-message
             :content ""
             :sections '(("note" . "<note>x</note>"))
             :tools-added
             (list (cadr-ai:to-tool-declaration second))
             :tools-removed
             (list (cadr-ai:make-tool-reference :name "first"))
             :timestamp 1)
            (cadr-ai:make-user-message
             :content "hi"
             :timestamp 2)))
         (declared
           (cadr-agent:declare-tool-changes
            committed
            (list first)
            pending))
         (merged (first declared)))
    (is (typep merged 'cadr-ai:system-message))
    (is (equal
         '(("note" . "<note>x</note>"))
         (cadr-ai:system-message-sections merged)))
    (is (null (cadr-ai:system-message-tools-added merged)))
    (is (null (cadr-ai:system-message-tools-removed merged)))
    (is (equal
         '("first")
         (mapcar
          #'cadr-ai:tool-name
          (cadr-ai:system-message-tools-added
           (cadr-ai:get-current-system-message
            (append committed declared))))))))
