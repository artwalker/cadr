(in-package #:cadr-ai/tests)

(in-suite cadr-ai-suite)

(defun v140-deferred-tool (name &optional description)
  (make-tool
   :name name
   :description (or description (format nil "~A tool" name))
   :parameters (cadr-ai::json-object)))

(defun v140-deferred-model (&key (additional-p nil) (tool-search-p nil)
                                 (mid-convo-p t))
  (make-model
   :id "gpt-5.4"
   :name "GPT-5.4"
   :provider :openai
   :api :openai-responses
   :base-url "http://127.0.0.1:9"
   :max-tokens 1000
   :context-window 100000
   :reasoning-p t
   :compat
   (append (when mid-convo-p '(:supports-mid-convo-system-messages t))
           (when additional-p '(:supports-additional-tools t))
           (when tool-search-p '(:supports-tool-search t)))))

(defun v140-deferred-payload (model messages)
  (request-spec-payload
   (build-request
    (make-openai-provider :api-key "test-key")
    model
    (make-context :messages messages)
    :stream-p t)))

(defun v140-input-names (item)
  (let ((tools (cadr-ai::json-get item "tools")))
    (when tools
      (loop for tool across tools
            collect (cadr-ai::json-get tool "name")))))

(defun v140-input-projection (payload)
  (loop for item across (cadr-ai::json-get payload "input")
        collect (list (cadr-ai::json-get item "type")
                      (cadr-ai::json-get item "role")
                      (cadr-ai::json-get item "content")
                      (v140-input-names item))))

(defun v140-tool-names (payload)
  (let ((tools (cadr-ai::json-get payload "tools")))
    (when tools
      (loop for tool across tools
            collect (cadr-ai::json-get tool "name")))))

(defun v140-prefix-p (earlier later)
  (and (<= (length earlier) (length later))
       (every #'equalp earlier (subseq later 0 (length earlier)))))

(defun v140-system (content &key tools-added tools-removed sections timestamp)
  (cadr-ai:make-system-message
   :content content
   :sections sections
   :tools-added tools-added
   :tools-removed
   (mapcar (lambda (name) (cadr-ai:make-tool-reference :name name))
           tools-removed)
   :timestamp (or timestamp 0)))

(test v140-responses-declares-every-tool-in-additional-tools
  ;; pi@4a080252f transcript-tool-changes.test.ts
  ;; "declares every OpenAI tool in additional_tools at its developer message"
  (let* ((base (v140-deferred-tool "base_tool"))
         (late (v140-deferred-tool "late_tool"))
         (model (v140-deferred-model :additional-p t))
         (payload
           (v140-deferred-payload
            model
            (list
             (v140-system "base prompt" :tools-added (list base) :timestamp 0)
             (make-user-message :content "before" :timestamp 1)
             (v140-system "updated guidance"
                          :tools-added (list late)
                          :timestamp 2))))
         (projection (v140-input-projection payload))
         (notices
           (loop for item in projection
                 for content = (third item)
                 when (and (stringp content)
                           (search "incremental tools update" content))
                   collect content)))
    (is (null (v140-tool-names payload)))
    (is (equal '(("base_tool") ("late_tool"))
               (loop for item in projection
                     when (equal "additional_tools" (first item))
                       collect (fourth item))))
    (is (equal '("additional_tools" nil nil nil "additional_tools" nil)
               (mapcar #'first projection)))
    (is (equal '("base prompt" "updated guidance")
               (loop for item in projection
                     for content = (third item)
                     when (and (stringp content)
                               (not (search "incremental tools update" content)))
                       collect content)))
    (is (= 1 (length notices)))
    (is (search "latest definition replaces the earlier one" (first notices)))
    (is (not (search "Still unavailable" (first notices))))))

(test v140-responses-maps-additions-into-synthetic-tool-search
  (let* ((model (v140-deferred-model :tool-search-p t))
         (payload
           (v140-deferred-payload
            model
            (list
             (v140-system "base prompt"
                          :tools-added (list (v140-deferred-tool "base_tool")))
             (make-user-message :content "before" :timestamp 1)
             (v140-system "updated guidance"
                          :tools-added (list (v140-deferred-tool "late_tool"))
                          :timestamp 2))))
         (input (cadr-ai::json-get payload "input"))
         (output
           (find "tool_search_output" input
                 :key (lambda (item) (cadr-ai::json-get item "type"))
                 :test #'string=)))
    (is (equal '("base_tool") (v140-tool-names payload)))
    (is (find "tool_search_call" input
              :key (lambda (item) (cadr-ai::json-get item "type"))
              :test #'string=))
    (is (equal '("late_tool") (v140-input-names output)))
    (is (eq t (cadr-ai::json-get (aref (cadr-ai::json-get output "tools") 0)
                                 "defer_loading")))))

(test v140-responses-folds-updates-without-native-support
  (let* ((model (v140-deferred-model :additional-p t :mid-convo-p nil))
         (payload
           (v140-deferred-payload
            model
            (list
             (v140-system
              "base prompt"
              :sections '(("rules" . "<rules>
old rules
</rules>")
                          ("docs" . "<docs>
read docs
</docs>"))
              :tools-added (list (v140-deferred-tool "base_tool"))
              :timestamp 0)
             (make-user-message :content "before" :timestamp 1)
             (v140-system
              "updated guidance"
              :sections '(("rules" . "<rules>
new rules
</rules>")
                          ("docs" . nil))
              :tools-removed '("base_tool")
              :tools-added (list (v140-deferred-tool "late_tool"))
              :timestamp 2))))
         (input (cadr-ai::json-get payload "input")))
    (is (equal '("late_tool") (v140-tool-names payload)))
    (is (= 2 (length input)))
    (is (string= "developer" (cadr-ai::json-get (aref input 0) "role")))
    (is (string= "user" (cadr-ai::json-get (aref input 1) "role")))
    (is (string=
         "base prompt

updated guidance

<rules>
new rules
</rules>"
         (cadr-ai::json-get (aref input 0) "content")))))

(test v140-responses-announces-removals-as-text
  (let* ((model (v140-deferred-model :additional-p t))
         (payload
           (v140-deferred-payload
            model
            (list
             (v140-system
              "base prompt"
              :sections '(("rules" . "<rules>
old rules
</rules>")
                          ("docs" . "<docs>
read docs
</docs>"))
              :tools-added (list (v140-deferred-tool "base_tool"))
              :timestamp 0)
             (make-user-message :content "before" :timestamp 1)
             (v140-system
              "updated guidance"
              :sections '(("rules" . "<rules>
new rules
</rules>")
                          ("docs" . nil))
              :tools-removed '("base_tool")
              :tools-added (list (v140-deferred-tool "late_tool"))
              :timestamp 2))))
         (projection (v140-input-projection payload))
         (update (third (car (last projection)))))
    (is (null (v140-tool-names payload)))
    (is (equal '(("base_tool") ("late_tool"))
               (loop for item in projection
                     when (equal "additional_tools" (first item))
                       collect (fourth item))))
    (is (search "updated guidance" update))
    (is (search "The following tools are no longer available. Do not call them:
- base_tool"
                update))))

(test v140-responses-redefines-a-tool-without-announcing-removal
  (let* ((model (v140-deferred-model :additional-p t))
         (payload
           (v140-deferred-payload
            model
            (list
             (v140-system "base prompt"
                          :tools-added (list (v140-deferred-tool "base_tool"))
                          :timestamp 0)
             (make-user-message :content "before" :timestamp 1)
             (v140-system ""
                          :tools-removed '("base_tool")
                          :tools-added
                          (list (v140-deferred-tool "base_tool" "changed"))
                          :timestamp 2))))
         (projection (v140-input-projection payload))
         (notice (third (fourth projection))))
    (is (null (v140-tool-names payload)))
    (is (= 5 (length projection)))
    (is (equal "additional_tools" (first (first projection))))
    (is (equal '("base_tool") (fourth (first projection))))
    (is (string= "base prompt" (third (second projection))))
    (is (string= "user" (second (third projection))))
    (is (search "latest definition replaces the earlier one" notice))
    (is (not (search "no longer available" notice)))
    (is (equal "additional_tools" (first (fifth projection))))
    (is (equal '("base_tool") (fourth (fifth projection))))
    (is (string=
         "changed"
         (cadr-ai::json-get
          (aref (cadr-ai::json-get
                 (aref (cadr-ai::json-get payload "input") 4)
                 "tools")
                0)
          "description")))))

(test v140-responses-keeps-the-prefix-across-a-removal-and-later-loads
  ;; #10940: deferred loads after a removal must not rewrite the cached prefix.
  (let* ((model (v140-deferred-model :additional-p t))
         (base (v140-deferred-tool "base_tool"))
         (drop (v140-deferred-tool "drop_tool"))
         (messages
           (list (v140-system "base prompt"
                              :tools-added (list base drop)
                              :timestamp 0)))
         (steps
           (list
            (list (make-user-message :content "first" :timestamp 1))
            (list (v140-system "" :tools-removed '("drop_tool") :timestamp 2)
                  (make-user-message :content "after removal" :timestamp 3))
            (list (v140-system ""
                              :tools-added (list (v140-deferred-tool "late_tool"))
                              :timestamp 4)
                  (make-user-message :content "after first load" :timestamp 5))
            (list (v140-system ""
                              :tools-added (list (v140-deferred-tool "later_tool"))
                              :timestamp 6)
                  (make-user-message :content "after second load" :timestamp 7))))
         (payloads nil))
    (dolist (step steps)
      (setf messages (append messages step))
      (push (v140-deferred-payload model messages) payloads))
    (setf payloads (nreverse payloads))
    (dolist (payload payloads)
      (is (not (cadr-ai::json-present-p payload "tools"))))
    (let ((projections (mapcar #'v140-input-projection payloads)))
      (loop for previous in projections
            for current in (rest projections)
            do (is (v140-prefix-p previous current)))
    (let ((last (car (last projections))))
      (is (equal '(("base_tool" "drop_tool") ("late_tool") ("later_tool"))
                 (loop for item in last
                       when (equal "additional_tools" (first item))
                         collect (fourth item))))
      (is (some (lambda (item)
                  (and (stringp (third item))
                       (search "no longer available. Do not call them:
- drop_tool"
                               (third item))))
                last))
      (is (equal 2
                 (count-if
                  (lambda (item)
                    (and (stringp (third item))
                         (search "Still unavailable: drop_tool." (third item))
                         (search "incremental tools update" (third item))))
                  last)))))))

(test v140-responses-stops-listing-a-tool-once-it-is-declared-again
  (let* ((model (v140-deferred-model :additional-p t))
         (drop (v140-deferred-tool "drop_tool"))
         (payload
           (v140-deferred-payload
            model
            (list
             (v140-system "base prompt"
                          :tools-added (list (v140-deferred-tool "base_tool") drop)
                          :timestamp 0)
             (v140-system "" :tools-removed '("drop_tool") :timestamp 1)
             (v140-system "" :tools-added (list drop) :timestamp 2)
             (make-user-message :content "go" :timestamp 3))))
         (notice
           (find-if (lambda (item)
                      (and (stringp (third item))
                           (search "incremental tools update" (third item))))
                    (v140-input-projection payload))))
    (is (not (null notice)))
    (is (not (search "Still unavailable" (third notice))))
    (let ((items (cadr-ai::json-get payload "input")))
      (is (equal '("drop_tool")
                 (v140-input-names (aref items (- (length items) 2))))))))

(test v140-responses-does-not-list-a-removal-before-it-is-announced
  (let* ((model (v140-deferred-model :additional-p t))
         (payload
           (v140-deferred-payload
            model
            (list
             (v140-system "base prompt"
                          :tools-added
                          (list (v140-deferred-tool "base_tool")
                                (v140-deferred-tool "drop_tool"))
                          :timestamp 0)
             (v140-system ""
                          :tools-added (list (v140-deferred-tool "late_tool"))
                          :tools-removed '("drop_tool")
                          :timestamp 1)
             (make-user-message :content "go" :timestamp 2))))
         (projection (v140-input-projection payload))
         (tail (last projection 4)))
    (is (search "incremental tools update" (third (first tail))))
    (is (not (search "Still unavailable" (third (first tail)))))
    (is (equal "additional_tools" (first (second tail))))
    (is (equal '("late_tool") (fourth (second tail))))
    (is (search "no longer available. Do not call them:
- drop_tool"
                (third (third tail))))
    (is (string= "user" (second (fourth tail))))))

(test v140-responses-tool-search-keeps-the-prefix-after-one-removal
  (let* ((model (v140-deferred-model :tool-search-p t))
         (base (v140-deferred-tool "base_tool"))
         (drop (v140-deferred-tool "drop_tool"))
         (messages
           (list (v140-system "base prompt"
                              :tools-added (list base drop)
                              :timestamp 0)))
         (steps
           (list
            (list (make-user-message :content "first" :timestamp 1))
            (list (v140-system "" :tools-removed '("drop_tool") :timestamp 2)
                  (make-user-message :content "after removal" :timestamp 3))
            (list (v140-system ""
                              :tools-added (list (v140-deferred-tool "late_tool"))
                              :timestamp 4)
                  (make-user-message :content "after first load" :timestamp 5))
            (list (v140-system ""
                              :tools-added (list (v140-deferred-tool "later_tool"))
                              :timestamp 6)
                  (make-user-message :content "after second load" :timestamp 7))))
         (payloads nil))
    (dolist (step steps)
      (setf messages (append messages step))
      (push (v140-deferred-payload model messages) payloads))
    (setf payloads (nreverse payloads))
    (is (equal '("base_tool" "drop_tool")
               (v140-tool-names (first payloads))))
    (dolist (payload (rest payloads))
      (is (equal '("base_tool") (v140-tool-names payload))))
    (loop for previous in (mapcar #'v140-input-projection (rest payloads))
          for current in (mapcar #'v140-input-projection (rest (rest payloads)))
          do (is (v140-prefix-p previous current)))
    (is (equal '("late_tool" "later_tool")
               (loop for item across (cadr-ai::json-get (car (last payloads)) "input")
                     when (string= "tool_search_output"
                                   (or (cadr-ai::json-get item "type") ""))
                       append (v140-input-names item))))))

(defun v140-kimi-k3-model ()
  (cadr-ai::model-from-metadata
   (cadr-ai:find-model-metadata :kimi-coding "k3")))

(defun v140-completions-payload (model messages)
  (request-spec-payload
   (build-request
    (cadr-ai:make-openai-completions-provider :api-key "test-key")
    model
    (make-context :messages messages)
    :stream-p t)))

(defun v140-chat-function-names (tools)
  (when tools
    (loop for tool across tools
          collect (cadr-ai::json-get
                   (cadr-ai::json-get tool "function")
                   "name"))))

(defun v140-chat-tool-names (payload)
  (v140-chat-function-names (cadr-ai::json-get payload "tools")))

(defun v140-chat-message-projection (payload)
  (loop for message across (cadr-ai::json-get payload "messages")
        collect (list (cadr-ai::json-get message "role")
                      (cadr-ai::json-get message "content")
                      (v140-chat-function-names
                       (cadr-ai::json-get message "tools")))))

(test v140-kimi-keeps-the-prefix-across-loads-after-a-removal
  ;; pi@4a080252f transcript-tool-changes.test.ts
  ;; "keeps the Kimi prefix across loads after a removal"
  ;; getModel("kimi-coding", "k3"): removal rewrites the top-level list
  ;; once, and the two loads after that stay a prefix of each other.
  (let* ((model (v140-kimi-k3-model))
         (base (v140-deferred-tool "base_tool"))
         (drop (v140-deferred-tool "drop_tool"))
         (messages
           (list (v140-system "base prompt"
                              :tools-added (list base drop)
                              :timestamp 0)))
         (steps
           (list
            (list (make-user-message :content "first" :timestamp 1))
            (list (v140-system "" :tools-removed '("drop_tool") :timestamp 2)
                  (make-user-message :content "after removal" :timestamp 3))
            (list (v140-system ""
                              :tools-added (list (v140-deferred-tool "late_tool"))
                              :timestamp 4)
                  (make-user-message :content "after first load" :timestamp 5))
            (list (v140-system ""
                              :tools-added (list (v140-deferred-tool "later_tool"))
                              :timestamp 6)
                  (make-user-message :content "after second load" :timestamp 7))))
         (payloads nil))
    (dolist (step steps)
      (setf messages (append messages step))
      (push (v140-completions-payload model messages) payloads))
    (setf payloads (nreverse payloads))
    (is (equal '("base_tool" "drop_tool")
               (v140-chat-tool-names (first payloads))))
    (dolist (payload (rest payloads))
      (is (equal '("base_tool") (v140-chat-tool-names payload))))
    (let ((projections
            (mapcar #'v140-chat-message-projection (rest payloads))))
      (loop for previous in projections
            for current in (rest projections)
            do (is (v140-prefix-p previous current))))
    (is (equal '("late_tool" "later_tool")
               (loop for message
                       in (v140-chat-message-projection
                           (car (last payloads)))
                     when (third message)
                       append (third message))))))

(test v140-resolve-transcript-tools-moves-the-boundary-once
  (let* ((base (v140-deferred-tool "base_tool"))
         (drop (v140-deferred-tool "drop_tool"))
         (late-x (v140-deferred-tool "late_tool" "x"))
         (late-y (v140-deferred-tool "late_tool" "y"))
         (messages
           (list
            (v140-system "base prompt" :tools-added (list base drop) :timestamp 0)
            (v140-system "" :tools-removed '("drop_tool") :timestamp 1)
            (v140-system "" :tools-added (list drop) :timestamp 2)
            (v140-system "" :tools-added (list late-x) :timestamp 3)
            (v140-system "" :tools-added (list late-y) :timestamp 4)))
         (pairs
           (lambda (tools)
             (mapcar (lambda (tool)
                       (list (cadr-ai:tool-name tool)
                             (cadr-ai:tool-description tool)))
                     tools))))
    (let ((early (cadr-ai:resolve-transcript-tools (subseq messages 0 2) :additions)))
      (is (equal '(("base_tool" "base_tool tool"))
                 (funcall pairs (cadr-ai:transcript-tools-request-tools early))))
      (is (= 2 (cadr-ai::transcript-tools-folded-system-messages early))))
    (let ((readded (cadr-ai:resolve-transcript-tools (subseq messages 0 4) :additions)))
      (is (equal '(("base_tool" "base_tool tool")
                   ("drop_tool" "drop_tool tool"))
                 (funcall pairs (cadr-ai:transcript-tools-request-tools readded))))
      (is (= 3 (cadr-ai::transcript-tools-folded-system-messages readded))))
    (let ((redefined (cadr-ai:resolve-transcript-tools messages :additions)))
      (is (equal '(("base_tool" "base_tool tool")
                   ("drop_tool" "drop_tool tool")
                   ("late_tool" "y"))
                 (funcall pairs (cadr-ai:transcript-tools-request-tools redefined))))
      (is (= 5 (cadr-ai::transcript-tools-folded-system-messages redefined))))
    (let ((changes (cadr-ai:resolve-transcript-tools messages :changes)))
      (is (null (cadr-ai:transcript-tools-request-tools changes)))
      (is (= 0 (cadr-ai::transcript-tools-folded-system-messages changes))))
    (let ((none (cadr-ai:resolve-transcript-tools messages :none)))
      (is (equal '(("base_tool" "base_tool tool")
                   ("drop_tool" "drop_tool tool")
                   ("late_tool" "y"))
                 (funcall pairs (cadr-ai:transcript-tools-request-tools none))))
      (is (= 5 (cadr-ai::transcript-tools-folded-system-messages none))))))
