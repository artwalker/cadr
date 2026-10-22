(in-package #:cadr-ai/tests)
(in-suite cadr-ai-suite)

(defun empty-tool-schema ()
  (cadr-ai::json-object
   "type" "object"
   "properties" (cadr-ai::json-object)))

(defun replay-tool (name &optional (description (format nil "~A tool" name)))
  (make-tool
   :name name
   :description description
   :parameters (empty-tool-schema)))

(defun system-message-matches-p (message &key content sections tools-added timestamp)
  (and (typep message 'cadr-ai:system-message)
       (equal content (cadr-ai:system-message-content message))
       (equal sections (cadr-ai:system-message-sections message))
       (= timestamp (cadr-ai:system-message-timestamp message))
       (= (length tools-added)
          (length (cadr-ai:system-message-tools-added message)))
       (every #'cadr-ai:declarations-equal
              tools-added
              (cadr-ai:system-message-tools-added message))))

(defun replay-fixture-transcript ()
  (cadr-ai:normalize-context
   (make-context
    :messages
    (list
     (cadr-ai:make-system-message
      :content "base"
      :sections '(("a" . "<a>1</a>") ("b" . "<b>1</b>"))
      :tools-added (list (replay-tool "first"))
      :timestamp 10)
     (make-user-message :content "hello" :timestamp 11)
     (cadr-ai:make-system-message :content "also do this" :timestamp 12)
     (cadr-ai:make-assistant-message
      :content (list (make-text-content :text "ok"))
      :timestamp 13)
     (cadr-ai:make-system-message
      :content ""
      :sections '(("a" . "<a>2</a>") ("b" . nil) ("c" . "<c>1</c>"))
      :tools-removed (list (cadr-ai:make-tool-reference :name "first"))
      :tools-added (list (replay-tool "second"))
      :timestamp 14)))))

(test goal24-replays-content-sections-and-tools
  (let* ((transcript (replay-fixture-transcript))
         (current
           (cadr-ai:get-current-system-message
            (cadr-ai:transcript-context-messages transcript))))
    (is (system-message-matches-p
         current
         :content (format nil "base~%~%also do this")
         :sections '(("a" . "<a>2</a>") ("c" . "<c>1</c>"))
         :tools-added (list (replay-tool "second"))
         :timestamp 10))
    (is (string=
         (format nil "base~%~%also do this~%~%<a>2</a>~%~%<c>1</c>")
         (cadr-ai:get-current-system-prompt
          (cadr-ai:transcript-context-messages transcript))))))

(test goal24-collapse-keeps-non-system-after-head
  (let* ((transcript (replay-fixture-transcript))
         (collapsed (cadr-ai:collapse-system-messages transcript)))
    (is (equal
         '("system" "user" "assistant")
         (mapcar
          (lambda (message)
            (cond
              ((typep message 'cadr-ai:system-message) "system")
              ((typep message 'cadr-ai:user-message) "user")
              ((typep message 'cadr-ai:assistant-message) "assistant")
              (t "other")))
          (cadr-ai:transcript-context-messages collapsed))))
    (let* ((again (cadr-ai:collapse-system-messages collapsed))
           (head (first (cadr-ai:transcript-context-messages collapsed)))
           (head-again (first (cadr-ai:transcript-context-messages again))))
      (is (= (length (cadr-ai:transcript-context-messages collapsed))
             (length (cadr-ai:transcript-context-messages again))))
      (is (system-message-matches-p
           head-again
           :content (cadr-ai:system-message-content head)
           :sections (cadr-ai:system-message-sections head)
           :tools-added (cadr-ai:system-message-tools-added head)
           :timestamp (cadr-ai:system-message-timestamp head))))))

(test goal24-replay-without-system-messages-is-empty
  (let ((context
          (cadr-ai:normalize-context
           (make-context
            :messages
            (list (make-user-message :content "hi" :timestamp 1))))))
    (is (null (cadr-ai:get-current-system-message
               (cadr-ai:transcript-context-messages context))))
    (is (string= ""
                 (cadr-ai:get-current-system-prompt
                  (cadr-ai:transcript-context-messages context))))
    (is (equal
         (cadr-ai:transcript-context-messages context)
         (cadr-ai:transcript-context-messages
          (cadr-ai:collapse-system-messages context))))))

(test goal24-late-full-patch-replays-as-prompt
  (let ((context
          (cadr-ai:normalize-context
           (make-context
            :messages
            (list
             (make-user-message :content "old session" :timestamp 1)
             (cadr-ai:make-system-message
              :content ""
              :sections '(("preamble" . "You are pi."))
              :tools-added (list (replay-tool "x"))
              :timestamp 2))))))
    (is (string= "You are pi."
                 (cadr-ai:get-current-system-prompt
                  (cadr-ai:transcript-context-messages context))))
    (let ((head
            (first
             (cadr-ai:transcript-context-messages
              (cadr-ai:collapse-system-messages context)))))
      (is (typep head 'cadr-ai:system-message))
      (is (cadr-ai:declarations-equal
           (replay-tool "x")
           (first (cadr-ai:system-message-tools-added head)))))))

(test goal24-renders-complete-prompts-and-framed-updates
  (let* ((transcript (replay-fixture-transcript))
         (messages (cadr-ai:transcript-context-messages transcript))
         (leading (first messages))
         (update (fifth messages)))
    (is (typep leading 'cadr-ai:system-message))
    (is (typep update 'cadr-ai:system-message))
    (is (string=
         (format nil "base~%~%<a>1</a>~%~%<b>1</b>")
         (cadr-ai:get-system-message-text leading)))
    (is (string=
         (format nil "~{~A~^~%~%~}"
                 (list
                  (format nil "Updated system prompt section \"a\":~%~%<a>2</a>")
                  "Removed system prompt section \"b\"."
                  (format nil "Updated system prompt section \"c\":~%~%<c>1</c>")))
         (cadr-ai:render-system-message-update update)))))

(test goal24-normalizes-legacy-prompt-and-tools
  (let ((messages (list (make-user-message :content "hi" :timestamp 1))))
    (is (equal
         messages
         (cadr-ai:transcript-context-messages
          (cadr-ai:normalize-context (make-context :messages messages)))))
    (is (equal
         messages
         (cadr-ai:transcript-context-messages
          (cadr-ai:normalize-context
           (make-context
            :system-prompt ""
            :tools '()
            :messages messages)))))
    (let ((normalized
            (cadr-ai:normalize-context
             (make-context
              :system-prompt "be brief"
              :tools (list (replay-tool "a"))
              :messages messages))))
      (is (= 2 (length (cadr-ai:transcript-context-messages normalized))))
      (is (system-message-matches-p
           (first (cadr-ai:transcript-context-messages normalized))
           :content "be brief"
           :sections nil
           :tools-added (list (replay-tool "a"))
           :timestamp 0))
      (is (eq (second (cadr-ai:transcript-context-messages normalized))
              (first messages))))))

(test goal24-compares-tool-declarations-without-executable-fields
  (let ((executable
          (make-tool
           :name "a"
           :description "a tool"
           :parameters (empty-tool-schema)
           :constrained-sampling nil
           :executor (lambda (&rest args) (declare (ignore args)) nil))))
    (is (cadr-ai:declarations-equal executable (replay-tool "a")))
    (is (not (cadr-ai:declarations-equal
              (replay-tool "a")
              (replay-tool "a" "changed"))))
    (is (not (cadr-ai:declarations-equal
              (replay-tool "a")
              (make-tool
               :name "a"
               :description "a tool"
               :parameters (empty-tool-schema)
               :constrained-sampling :false))))))

(test goal24-tool-state-changes-treat-redefinition-as-remove-plus-add
  (let ((changes
          (cadr-ai:get-tool-state-changes
           (list (replay-tool "a") (replay-tool "b"))
           (list (replay-tool "b" "changed") (replay-tool "c")))))
    (is (= 2 (length (cadr-ai:tool-state-changes-tools-added changes))))
    (is (cadr-ai:declarations-equal
         (replay-tool "b" "changed")
         (first (cadr-ai:tool-state-changes-tools-added changes))))
    (is (cadr-ai:declarations-equal
         (replay-tool "c")
         (second (cadr-ai:tool-state-changes-tools-added changes))))
    (is (equal
         '("a" "b")
         (mapcar #'cadr-ai:tool-reference-name
                 (cadr-ai:tool-state-changes-tools-removed changes))))
    (let ((noop
            (cadr-ai:get-tool-state-changes
             (list (replay-tool "a"))
             (list (replay-tool "a")))))
      (is (null (cadr-ai:tool-state-changes-tools-added noop)))
      (is (null (cadr-ai:tool-state-changes-tools-removed noop))))))

(test goal24-detects-non-additive-tool-history-and-redefinitions
  (let ((transcript (replay-fixture-transcript)))
    (is (cadr-ai:has-non-additive-tool-changes
         (cadr-ai:transcript-context-messages transcript)))
    (is (not (cadr-ai:has-tool-redefinitions
              (cadr-ai:transcript-context-messages transcript)))))
  (let ((additive
          (cadr-ai:normalize-context
           (make-context
            :messages
            (list
             (cadr-ai:make-system-message
              :content ""
              :tools-added (list (replay-tool "a"))
              :timestamp 1)
             (cadr-ai:make-system-message
              :content ""
              :tools-added (list (replay-tool "b"))
              :timestamp 2))))))
    (is (not (cadr-ai:has-non-additive-tool-changes
              (cadr-ai:transcript-context-messages additive)))))
  (let ((redeclared
          (cadr-ai:normalize-context
           (make-context
            :messages
            (list
             (cadr-ai:make-system-message
              :content ""
              :tools-added (list (replay-tool "a"))
              :timestamp 1)
             (cadr-ai:make-system-message
              :content ""
              :tools-added (list (replay-tool "a" "changed"))
              :timestamp 2))))))
    (is (cadr-ai:has-non-additive-tool-changes
         (cadr-ai:transcript-context-messages redeclared)))
    (is (cadr-ai:has-tool-redefinitions
         (cadr-ai:transcript-context-messages redeclared)))))
