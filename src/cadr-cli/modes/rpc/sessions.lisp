(in-package #:cadr-cli)

(defun rpc-session-directory (session)
  (make-pathname
   :name nil :type nil
   :defaults
   (cadr-agent:session-path session)))

(defun rpc-switch-agent-session
    (agent session reason previous-file)
  (let ((host
          (cadr-agent::agent-extension-host agent)))
    (when host
      (cadr-agent::invalidate-extension-host-generation
       host)))
  (setf
   (cadr-agent:agent-session agent) session
   (cadr-agent:agent-messages agent)
   (cadr-agent:session-messages session))
  (rpc-run-lifecycle
   agent :session-start
   :reason reason
   :previous-session-file previous-file)
  session)

(defun rpc-before-session-switch
    (agent reason target)
  (let ((result
          (rpc-run-lifecycle
           agent :session-before-switch
           :reason reason
           :target-session-file target)))
    (not (null (getf result :cancel-p)))))

(defun rpc-new-session (state object)
  (let* ((agent (rpc-state-agent state))
         (old (cadr-agent:agent-session agent))
         (parent
           (cadr-ai::json-get
            object "parentSession"))
         (directory
           (rpc-session-directory old)))
    (if
        (rpc-before-session-switch
         agent :new nil)
        (cadr-ai::json-object "cancelled" t)
        (progn
          (rpc-run-lifecycle
           agent :session-shutdown
           :reason :new)
          (let ((session
                  (cadr-agent:create-session
                   :directory directory
                   :cwd (cadr-agent:session-cwd old)
                   :parent-session
                   (and
                    (stringp parent)
                    parent))))
            (rpc-switch-agent-session
             agent session :new
             (namestring
              (cadr-agent:session-path old)))
            (cadr-ai::json-object
             "cancelled" nil))))))

(defun rpc-switch-session-command (state object)
  (let* ((agent (rpc-state-agent state))
         (old (cadr-agent:agent-session agent))
         (path
           (require-rpc-string
            object "sessionPath")))
    (if
        (rpc-before-session-switch
         agent :resume path)
        (cadr-ai::json-object "cancelled" t)
        (let ((session
                (cadr-agent:load-session path)))
          (rpc-run-lifecycle
           agent :session-shutdown
           :reason :resume
           :target-session-file path)
          (rpc-switch-agent-session
           agent session :resume
           (namestring
            (cadr-agent:session-path old)))
          (cadr-ai::json-object
           "cancelled" nil)))))

(defun rpc-entry-user-text (entry)
  (when
      (and
       (eq :message
           (cadr-agent:session-entry-type entry))
       (typep
        (cadr-agent:session-entry-message entry)
        'cadr-ai:user-message))
    (let ((content
            (cadr-ai:user-message-content
             (cadr-agent:session-entry-message
              entry))))
      (if (stringp content)
          content
          (format
           nil "~{~A~^~%~}"
           (loop for block in content
                 when
                 (typep block 'cadr-ai:text-content)
                   collect
                   (cadr-ai:text-content-text
                    block)))))))

(defun rpc-copy-session-branch
    (source target leaf-id)
  (dolist
      (entry
       (cadr-agent::session-path-entries
        source leaf-id))
    (when
        (eq :message
            (cadr-agent:session-entry-type entry))
      (cadr-agent:session-append-message
       target
       (cadr-agent:session-entry-message entry))))
  target)

(defun rpc-fork-session
    (state entry-id position)
  (let* ((agent (rpc-state-agent state))
         (old (cadr-agent:agent-session agent))
         (entry
           (find
            entry-id
            (cadr-agent:session-entries old)
            :key #'cadr-agent:session-entry-id
            :test #'string=)))
    (unless entry
      (error "Entry not found: ~A" entry-id))
    (let ((before
            (rpc-run-lifecycle
             agent :session-before-fork
             :entry-id entry-id
             :position position)))
      (when (getf before :cancel-p)
        (return-from rpc-fork-session
          (values nil t))))
    (let* ((leaf-id
             (if (eq position :before)
                 (cadr-agent:session-entry-parent-id
                  entry)
                 entry-id)))
      (when leaf-id
        (refuse-unflushed-persisted-fork old))
      (cadr-agent:agent-abort-and-idle agent)
      (let ((new
             (cadr-agent:create-session
              :directory
              (rpc-session-directory old)
              :cwd
              (cadr-agent:session-cwd old)
              :parent-session
              (namestring
               (cadr-agent:session-path old)))))
      (when leaf-id
        (rpc-copy-session-branch
         old new leaf-id))
      (rpc-run-lifecycle
       agent :session-shutdown
       :reason :fork
       :target-session-file
       (namestring
        (cadr-agent:session-path new)))
      (rpc-switch-agent-session
       agent new :fork
       (namestring
        (cadr-agent:session-path old)))
      (values
       (or (rpc-entry-user-text entry) "")
       nil)))))

(defun rpc-context-usage (agent session)
  ;; pi@4a080252f agent-session.ts getContextUsage. No model or a
  ;; non-positive window omits the object. After compaction the token
  ;; count stays unknown until a later assistant reports usage.
  (let* ((model (cadr-agent:agent-model agent))
         (window
           (and model
                (cadr-ai:model-context-window model))))
    (unless (and window (plusp window))
      (return-from rpc-context-usage nil))
    (let* ((branch
             (cadr-agent::session-path-entries session))
           (compaction
             (cadr-agent::latest-compaction-entry branch)))
      (when compaction
        (let ((after
                (cdr (member compaction branch :test #'eq))))
          (unless
              (some
               (lambda (entry)
                 (and
                  (eq :message
                      (cadr-agent:session-entry-type entry))
                  (cadr-agent::valid-assistant-usage-p
                   (cadr-agent:session-entry-message
                    entry))))
               after)
            (return-from rpc-context-usage
              (cadr-ai::json-object
               "tokens" 'null
               "contextWindow" window
               "percent" 'null)))))
      (let ((tokens
              (cadr-agent::projected-context-tokens
               (cadr-agent:session-messages session))))
        (cadr-ai::json-object
         "tokens" tokens
         "contextWindow" window
         "percent"
         (* 100d0 (/ (float tokens 1d0) window)))))))

(defun rpc-session-stats (session &optional agent)
  (let ((user 0)
        (assistant 0)
        (tool-results 0)
        (tool-calls 0)
        (total-messages 0)
        (input 0)
        (output 0)
        (cache-read 0)
        (cache-write 0)
        (cost 0d0))
    (flet ((add-usage (usage)
             (when usage
               (incf input (cadr-ai:usage-input usage))
               (incf output (cadr-ai:usage-output usage))
               (incf cache-read
                     (cadr-ai:usage-cache-read usage))
               (incf cache-write
                     (cadr-ai:usage-cache-write usage))
               (incf cost
                     (cadr-ai:cost-total
                      (cadr-ai:usage-cost usage))))))
      (dolist (entry (cadr-agent:session-entries session))
        (let ((type
                (cadr-agent:session-entry-type entry)))
          (cond
            ((eq type :usage)
             (add-usage
              (cadr-agent:session-entry-usage entry)))
            ((member type '(:compaction :branch-summary))
             (add-usage
              (cadr-agent:session-entry-usage entry))))
          (when (eq type :message)
            (incf total-messages)
            (let ((message
                    (cadr-agent:session-entry-message
                     entry)))
              (cond
                ((typep message 'cadr-ai:user-message)
                 (incf user))
                ((typep message
                        'cadr-ai:tool-result-message)
                 (incf tool-results)
                 (add-usage
                  (cadr-ai:tool-result-message-usage
                   message)))
                ((typep message
                        'cadr-ai:assistant-message)
                 (incf assistant)
                 (incf
                  tool-calls
                  (count-if
                   (lambda (block)
                     (typep block 'cadr-ai:tool-call))
                   (cadr-ai:assistant-message-content
                    message)))
                 (add-usage
                  (cadr-ai:assistant-message-usage
                   message)))))))))
    (let ((object
            (cadr-ai::json-object
             "sessionFile"
             (and (cadr-agent:session-path session)
                  (namestring
                   (cadr-agent:session-path session)))
             "sessionId" (cadr-agent:session-id session)
             "userMessages" user
             "assistantMessages" assistant
             "toolCalls" tool-calls
             "toolResults" tool-results
             "totalMessages" total-messages
             "tokens"
             (cadr-ai::json-object
              "input" input
              "output" output
              "cacheRead" cache-read
              "cacheWrite" cache-write
              "total"
              (+ input output cache-read cache-write))
             "cost" cost)))
      (when agent
        (let ((context
                (rpc-context-usage agent session)))
          (when context
            (cadr-ai::json-put
             object "contextUsage" context))))
      object)))

(defun rpc-session-tree (session)
  (let ((nodes (make-hash-table :test #'equal))
        (label-stamps (make-hash-table :test #'equal))
        (roots nil))
    (dolist (entry (cadr-agent:session-entries session))
      (when
          (and
           (eq :label
               (cadr-agent:session-entry-type entry))
           (cadr-agent:session-entry-label entry)
           (plusp
            (length
             (cadr-agent:session-entry-label entry))))
        (setf
         (gethash
          (cadr-agent:session-entry-target-id entry)
          label-stamps)
         (cadr-agent:session-entry-timestamp entry)))
      (setf
       (gethash
        (cadr-agent:session-entry-id entry)
        nodes)
       (cadr-ai::json-object
        "entry"
        (cadr-agent::session-entry-to-json entry)
        "children"
        (make-array
         0 :adjustable t :fill-pointer 0))))
    (dolist (entry (cadr-agent:session-entries session))
      (let* ((node
               (gethash
                (cadr-agent:session-entry-id entry)
                nodes))
             (parent-id
               (cadr-agent:session-entry-parent-id
                entry))
             (parent
               (and parent-id
                    (not
                     (string=
                      parent-id
                      (cadr-agent:session-entry-id
                       entry)))
                    (gethash parent-id nodes)))
             (label
               (cadr-agent:session-label
                session
                (cadr-agent:session-entry-id entry))))
        (when label
          (cadr-ai::json-put node "label" label)
          (let ((stamp
                  (gethash
                   (cadr-agent:session-entry-id entry)
                   label-stamps)))
            (when stamp
              (cadr-ai::json-put
               node "labelTimestamp"
               (cadr-agent::session-timestamp-json
                stamp)))))
        (if parent
            (vector-push-extend
             node
             (cadr-ai::json-get parent "children"))
            (push node roots))))
    (labels ((sort-nodes (nodes)
               (map nil
                    (lambda (node)
                      (let ((children
                              (cadr-ai::json-get
                               node "children")))
                        (stable-sort
                         children #'string<
                         :key
                         (lambda (child)
                           (cadr-ai::json-get
                            (cadr-ai::json-get
                             child "entry")
                            "timestamp")))
                        (sort-nodes children)))
                    nodes)))
      (let ((ordered (nreverse roots)))
        (sort-nodes ordered)
        (coerce ordered 'vector)))))
