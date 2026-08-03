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
                 entry-id))
           (new
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
       nil))))

(defun rpc-session-stats (session)
  (let ((user 0)
        (assistant 0)
        (tool-results 0)
        (tool-calls 0)
        (input 0)
        (output 0)
        (cache-read 0)
        (cache-write 0))
    (dolist (entry (cadr-agent:session-entries session))
      (when
          (eq :message
              (cadr-agent:session-entry-type entry))
        (let ((message
                (cadr-agent:session-entry-message
                 entry)))
          (cond
            ((typep message 'cadr-ai:user-message)
             (incf user))
            ((typep message
                    'cadr-ai:tool-result-message)
             (incf tool-results))
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
             (let ((usage
                     (cadr-ai:assistant-message-usage
                      message)))
               (incf input
                     (cadr-ai:usage-input usage))
               (incf output
                     (cadr-ai:usage-output usage))
               (incf cache-read
                     (cadr-ai:usage-cache-read usage))
               (incf cache-write
                     (cadr-ai:usage-cache-write
                      usage))))))))
    (cadr-ai::json-object
     "sessionFile"
     (namestring (cadr-agent:session-path session))
     "sessionId" (cadr-agent:session-id session)
     "userMessages" user
     "assistantMessages" assistant
     "toolCalls" tool-calls
     "toolResults" tool-results
     "totalMessages"
     (+ user assistant tool-results)
     "tokens"
     (cadr-ai::json-object
      "input" input
      "output" output
      "cacheRead" cache-read
      "cacheWrite" cache-write
      "total"
      (+ input output cache-read cache-write)))))

(defun rpc-session-tree (session)
  (let ((nodes (make-hash-table :test #'equal))
        (roots nil))
    (dolist (entry (cadr-agent:session-entries session))
      (setf
       (gethash
        (cadr-agent:session-entry-id entry)
        nodes)
       (cadr-ai::json-object
        "entry"
        (cadr-agent::session-entry-to-json
         entry)
        "children" (make-array
                    0 :adjustable t
                    :fill-pointer 0))))
    (dolist (entry (cadr-agent:session-entries session))
      (let* ((node
               (gethash
                (cadr-agent:session-entry-id entry)
                nodes))
             (parent
               (and
                (cadr-agent:session-entry-parent-id
                 entry)
                (gethash
                 (cadr-agent:session-entry-parent-id
                  entry)
                 nodes))))
        (when
            (cadr-agent:session-label
             session
             (cadr-agent:session-entry-id entry))
          (cadr-ai::json-put
           node "label"
           (cadr-agent:session-label
            session
            (cadr-agent:session-entry-id entry))))
        (if parent
            (vector-push-extend
             node
             (cadr-ai::json-get
              parent "children"))
            (push node roots))))
    (coerce (nreverse roots) 'vector)))
