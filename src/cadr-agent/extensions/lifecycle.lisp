(in-package #:cadr-agent)

;;; Hook dispatch

(defun extension-message-p (value)
  (or
   (typep value 'cadr-ai:user-message)
   (typep value 'cadr-ai:assistant-message)
   (typep value 'cadr-ai:tool-result-message)))

(defun assistant-tool-call-signature (message)
  (loop
    for block in
    (cadr-ai:assistant-message-content message)
    when (typep block 'cadr-ai:tool-call)
      collect
      (list
       (cadr-ai:tool-call-id block)
       (cadr-ai:tool-call-name block))))

(defun valid-extension-replacement-p
    (event-type replacement original)
  (case event-type
    (:turn-start
     (or
      (null replacement)
      (typep replacement 'cadr-ai:user-message)))
    (:turn-end
     (and
      (typep replacement 'cadr-ai:assistant-message)
      (equal
       (assistant-tool-call-signature replacement)
       (assistant-tool-call-signature original))))
    (:tool-call-before
     (and
      (typep replacement 'cadr-ai:tool-call)
      (string=
       (cadr-ai:tool-call-id replacement)
       (cadr-ai:tool-call-id original))))
    (:tool-call-after
     (and
      (typep replacement 'cadr-ai:tool-result-message)
      (string=
       (cadr-ai:tool-result-message-tool-call-id replacement)
       (cadr-ai:tool-result-message-tool-call-id original))
      (string=
       (cadr-ai:tool-result-message-tool-name replacement)
       (cadr-ai:tool-result-message-tool-name original))))
    (otherwise nil)))

(defun make-hook-event
    (type turn-index primary tool-call
     tool-result tool-results appended)
  (%make-extension-event
   :type type
   :turn-index turn-index
   :message
   (and (member type '(:turn-start :turn-end))
        primary)
   :tool-call
   (if (eq type :tool-call-before)
       primary
       tool-call)
   :tool-result
   (if (eq type :tool-call-after)
       primary
       tool-result)
   :tool-results tool-results
   :appended-messages appended))

(defun run-extension-hooks
    (host event-type
     &key
       turn-index
       message
       tool-call
       tool-result
       tool-results)
  (let* ((snapshot
           (extension-host-current-snapshot host))
         (definitions
           (copy-list
            (gethash event-type
                     (extension-snapshot-hooks
                      snapshot))))
         (primary
           (case event-type
             ((:turn-start :turn-end) message)
             (:tool-call-before tool-call)
             (:tool-call-after tool-result)))
         (appended nil)
         (blocked-p nil)
         (reason nil)
         (terminate-p nil)
         (terminate-supplied-p nil))
    (let ((held
            (acquire-extension-snapshot
             host snapshot)))
      (unwind-protect
           (sb-thread:with-mutex
               ((extension-host-hook-lock host))
             (dolist (definition definitions)
               (handler-case
                   (let ((result
                           (call-with-extension-definition
                            host snapshot definition
                            (lambda (context)
                              (funcall
                               (extension-hook-definition-handler
                                definition)
                               (make-hook-event
                                event-type turn-index primary
                                tool-call tool-result tool-results
                                appended)
                               context)))))
                     (when result
                       (unless
                           (typep
                            result
                            'extension-hook-result)
                         (error
                          "Hook returned ~S instead of EXTENSION-HOOK-RESULT or NIL"
                          result))
                       (let* ((replacement-p
                                (extension-hook-result-replacement-p
                                 result))
                              (replacement
                                (if replacement-p
                                    (extension-hook-result-replacement
                                     result)
                                    primary))
                              (messages
                                (extension-hook-result-append-messages
                                 result))
                              (result-block-p
                                (extension-hook-result-block-p
                                 result))
                              (result-reason
                                (extension-hook-result-reason
                                 result))
                              (result-terminate-supplied-p
                                (extension-hook-result-terminate-supplied-p
                                 result))
                              (result-terminate-p
                                (extension-hook-result-terminate-p
                                 result)))
                         (when
                             (and
                              replacement-p
                              (not
                               (valid-extension-replacement-p
                                event-type replacement
                                primary)))
                           (error
                            "Invalid replacement for ~S"
                            event-type))
                         (unless
                             (and
                              (listp messages)
                              (every
                               #'extension-message-p
                               messages))
                           (error
                            "Hook append-messages must be a list of CADR-AI messages"))
                         (when result-block-p
                           (unless
                               (eq
                                event-type
                                :tool-call-before)
                             (error
                              "Only :tool-call-before hooks may block"))
                           (unless
                               (or
                                (null result-reason)
                                (stringp result-reason))
                             (error
                              "Hook block reason must be a string or NIL")))
                         ;; pi@914cf1472 extensions/types.ts:1075-1079 — the
                         ;; before hook may set terminate on a block;
                         ;; agent-loop.ts:638-639 applies it to the blocked
                         ;; result.  Without a block it is ignored.
                         (when result-terminate-supplied-p
                           (unless
                               (member event-type
                                       '(:tool-call-before
                                         :tool-call-after))
                             (error
                              "Only :tool-call-before and :tool-call-after hooks may override terminate")))
                         ;; Commit only after the entire hook result validates.
                         (setf primary replacement
                                appended
                                (nconc
                                 appended
                                 (copy-list messages)))
                         (when result-terminate-supplied-p
                           (setf terminate-p result-terminate-p
                                 terminate-supplied-p t))
                         (when result-block-p
                           (setf
                            blocked-p t
                            reason
                            (or
                             result-reason
                             "Tool execution was blocked"))
                           (return)))))
                 (condition (condition)
                   (notify-extension-failure
                    host definition "Hook" condition)))))
        (release-acquired-extension-snapshot
         host held)))
    (values primary appended blocked-p reason
            terminate-p terminate-supplied-p)))

;;; Wave 2 lifecycle dispatch. The original four hooks above deliberately keep
;;; their frozen EXTENSION-HOOK-RESULT contract.

(defparameter +extension-lifecycle-no-result-events+
  '(:session-start
    :session-info-changed
    :session-compact
    :session-shutdown
    :session-tree
    :agent-start
    :agent-end
    :agent-settled
    :message-start
    :message-update
    :tool-execution-start
    :tool-execution-update
    :tool-execution-end
    :model-select
    :thinking-level-select
    :after-provider-response))

(defun strict-keyword-plist-p (value)
  (and
   (listp value)
   (evenp (length value))
   (loop for tail on value by #'cddr
         always (keywordp (first tail)))))

(defun validate-lifecycle-result-keys
    (event result allowed)
  (unless (strict-keyword-plist-p result)
    (error
     "~S handler returned ~S instead of a keyword plist or NIL"
     event result))
  (loop for tail on result by #'cddr
        for key = (first tail)
        do
        (unless (member key allowed)
          (error
           "~S handler returned unsupported key ~S"
           event key)))
  result)

(defun extension-boolean-p (value)
  (or (null value) (eq value t)))

(defun extension-message-role (message)
  (cond
    ((typep message 'cadr-ai:user-message) :user)
    ((typep message 'cadr-ai:assistant-message) :assistant)
    ((typep message 'cadr-ai:tool-result-message) :tool-result)
    (t nil)))

(defun validate-session-before-result (event result)
  (let ((allowed
          (case event
            (:session-before-switch
             '(:cancel-p))
            (:session-before-fork
             '(:cancel-p
               :skip-conversation-restore-p))
            (:session-before-compact
             '(:cancel-p :compaction))
            (:session-before-tree
             '(:cancel-p
               :summary
               :details
               :usage
               :custom-instructions
               :replace-instructions-p
               :label)))))
    (validate-lifecycle-result-keys
     event result allowed)
    (dolist (key
             '(:cancel-p
               :skip-conversation-restore-p
               :replace-instructions-p))
      (let ((sentinel (list :missing)))
        (let ((value (getf result key sentinel)))
          (unless
              (or
               (eq value sentinel)
               (extension-boolean-p value))
            (error "~S result key ~S must be boolean"
                   event key)))))
    (dolist (key '(:summary :custom-instructions :label))
      (let ((sentinel (list :missing)))
        (let ((value (getf result key sentinel)))
          (unless
              (or
               (eq value sentinel)
               (null value)
               (stringp value))
            (error "~S result key ~S must be a string or NIL"
                   event key)))))
    result))

(defun validate-lifecycle-result (event result current-payload)
  (cond
    ((member event +extension-lifecycle-no-result-events+)
     (when result
       (error "~S handlers must return NIL" event))
     nil)
    ((member
      event
      '(:session-before-switch
        :session-before-fork
        :session-before-compact
        :session-before-tree))
     (and result
          (validate-session-before-result event result)))
    ((eq event :tool-call-error)
     (when result
       (unless (strict-keyword-plist-p result)
         (error
          ":TOOL-CALL-ERROR handler must return a keyword plist or NIL"))
       (let ((action (getf result :action)))
         (case action
           (:retry
            (validate-lifecycle-result-keys
             event result '(:action :arguments))
            (unless (hash-table-p
                     (getf result :arguments))
              (error
               ":TOOL-CALL-ERROR :RETRY requires hash-table :ARGUMENTS")))
           ((:skip :abort)
            (validate-lifecycle-result-keys
             event result '(:action :reason))
            (let ((reason (getf result :reason)))
              (unless (or (null reason)
                          (stringp reason))
                (error
                 ":TOOL-CALL-ERROR :REASON must be a string or NIL"))))
           (otherwise
            (error
             ":TOOL-CALL-ERROR :ACTION must be :RETRY, :SKIP, or :ABORT")))))
     result)
    ((eq event :context)
     (when result
       (validate-lifecycle-result-keys
        event result '(:messages))
       (let ((messages (getf result :messages)))
         (unless
             (and
              (listp messages)
              (every #'extension-message-p messages))
           (error
            ":CONTEXT :MESSAGES must be a list of CADR-AI messages"))))
     result)
    ((eq event :before-agent-start)
     (when result
       (validate-lifecycle-result-keys
        event result '(:message :system-prompt))
       (let ((sentinel (list :missing)))
         (let ((message (getf result :message sentinel))
               (system-prompt
                 (getf result :system-prompt sentinel)))
           (unless
               (or
                (eq message sentinel)
                (extension-message-p message))
             (error
              ":BEFORE-AGENT-START :MESSAGE must be a CADR-AI message"))
           (unless
               (or
                (eq system-prompt sentinel)
                (stringp system-prompt))
             (error
              ":BEFORE-AGENT-START :SYSTEM-PROMPT must be a string")))))
     result)
    ((eq event :message-end)
     (when result
       (validate-lifecycle-result-keys
        event result '(:message))
       (let ((replacement (getf result :message))
             (original (getf current-payload :message)))
         (unless
             (and
              (extension-message-p replacement)
              (eq
               (extension-message-role replacement)
               (extension-message-role original)))
           (error
            ":MESSAGE-END replacement must preserve the message role"))))
     result)
    ((eq event :input)
     (when result
       (validate-lifecycle-result-keys
        event result '(:action :text :images))
       (let ((action (getf result :action)))
         (unless (member action '(:continue :transform :handled))
           (error
            ":INPUT :ACTION must be :CONTINUE, :TRANSFORM, or :HANDLED"))
         (case action
           ((:continue :handled)
            (unless (= 2 (length result))
              (error
               ":INPUT ~S result accepts only :ACTION"
               action)))
           (:transform
            (unless (stringp (getf result :text))
              (error
               ":INPUT :TRANSFORM requires string :TEXT"))
            (let ((sentinel (list :missing)))
              (let ((images (getf result :images sentinel)))
                (unless
                    (or
                     (eq images sentinel)
                     (null images)
                     (typep images 'sequence))
                  (error
                   ":INPUT :IMAGES must be a sequence or NIL"))))))))
     result)
    ((eq event :project-trust)
     (when result
       (validate-lifecycle-result-keys
        event result '(:trusted :remember-p))
       (unless
           (member
            (getf result :trusted)
            '(:yes :no :undecided))
         (error
          ":PROJECT-TRUST :TRUSTED must be :YES, :NO, or :UNDECIDED"))
       (let ((sentinel (list :missing)))
         (let ((remember
                 (getf result
                       :remember-p sentinel)))
           (unless
               (or
                (eq remember sentinel)
                (extension-boolean-p remember))
             (error
              ":PROJECT-TRUST :REMEMBER-P must be boolean")))))
     result)
    ((eq event :resources-discover)
     (when result
       (validate-lifecycle-result-keys
        event result
        '(:skill-paths
          :prompt-paths
          :theme-paths))
       (dolist
           (key
            '(:skill-paths
              :prompt-paths
              :theme-paths))
         (let ((value (getf result key)))
           (unless
               (or
                (null value)
                (and
                 (listp value)
                 (every #'stringp value)))
             (error
              ":RESOURCES-DISCOVER ~S must be a list of strings"
              key)))))
     result)
    ((eq event :before-provider-request)
     result)
    ((eq event :before-provider-headers)
     (when result
       (error
        ":BEFORE-PROVIDER-HEADERS handlers must return NIL"))
     nil)
    ((eq event :user-bash)
     (when result
       (validate-lifecycle-result-keys
        event result '(:operations :result)))
     result)
    (t
     (error "No lifecycle result contract for ~S" event))))

(defun make-lifecycle-event (event payload)
  (%make-extension-event
   :type event
   :payload
   (if (eq event :tool-call-error)
       (copy-extension-value payload)
       (copy-tree payload))
   :message (getf payload :message)
   :tool-call (getf payload :tool-call)
   :tool-result (getf payload :tool-result)
   :tool-results (getf payload :tool-results)))

(defun lifecycle-event-payload-for-handler
    (event original state)
  (case event
    (:tool-call-error
     (copy-extension-value original))
    (:context
     (list :messages (copy-list (getf state :messages))))
    (:before-agent-start
     (let ((copy (copy-list original)))
       (setf
        (getf copy :system-prompt)
        (getf state :system-prompt))
       copy))
    (:message-end
     (let ((copy (copy-list original)))
       (setf
        (getf copy :message)
        (getf state :message))
       copy))
    (:input
     (let ((copy (copy-list original)))
       (setf
        (getf copy :text) (getf state :text)
       (getf copy :images) (getf state :images))
       copy))
    (:before-provider-request
     (list
      :payload
      (copy-tree (getf state :payload))))
    (:before-provider-headers
     (list :headers (getf state :headers)))
    (otherwise (copy-tree original))))

(defun initial-lifecycle-state (event payload)
  (case event
    (:context
     (list :messages (copy-list (getf payload :messages))))
    (:before-agent-start
     (list
      :messages nil
      :system-prompt (getf payload :system-prompt)
      :modified-p nil))
    (:message-end
     (list :message (getf payload :message)
           :modified-p nil))
    (:input
     (list
      :text (getf payload :text)
      :images (getf payload :images)
      :modified-p nil))
    (:resources-discover
     (list
      :skill-paths nil
      :prompt-paths nil
      :theme-paths nil))
    (:before-provider-request
     (list :payload (getf payload :payload)))
    (:before-provider-headers
     (list :headers (getf payload :headers)))
    (otherwise nil)))

(defun merge-lifecycle-result
    (event state result)
  (case event
    ((:session-before-switch
      :session-before-fork
      :session-before-compact
      :session-before-tree)
     result)
    (:context
     (when result
       (setf
        (getf state :messages)
        (copy-list (getf result :messages))))
     state)
    (:before-agent-start
     (when result
       (let ((sentinel (list :missing)))
         (let ((message (getf result :message sentinel))
               (system-prompt
                 (getf result :system-prompt sentinel)))
           (unless (eq message sentinel)
             (setf
              (getf state :messages)
              (nconc
               (getf state :messages)
               (list message))))
           (unless (eq system-prompt sentinel)
             (setf
              (getf state :system-prompt)
              system-prompt
              (getf state :modified-p)
              t)))))
     state)
    (:message-end
     (when result
       (setf
        (getf state :message)
        (getf result :message)
        (getf state :modified-p)
        t))
     state)
    (:input
     (when result
       (case (getf result :action)
         (:transform
          (setf
           (getf state :text) (getf result :text)
           (getf state :modified-p) t)
          (let ((sentinel (list :missing)))
            (let ((images
                    (getf result :images sentinel)))
              (unless (eq images sentinel)
                (setf
                 (getf state :images) images)))))
         (:handled
          (setf (getf state :handled-p) t))))
     state)
    (:resources-discover
     (when result
       (dolist
           (key
            '(:skill-paths
              :prompt-paths
              :theme-paths))
         (setf
          (getf state key)
          (nconc
           (getf state key)
           (copy-list (getf result key))))))
     state)
    (:before-provider-request
     (cond
       ((typep result
               'provider-request-replacement)
        (setf
         (getf state :payload)
         (provider-request-replacement-payload
          result)))
       (result
        (setf (getf state :payload)
              result)))
     state)
    (otherwise state)))

(defun finalize-lifecycle-state (event state last-result)
  (case event
    ((:session-before-switch
      :session-before-fork
      :session-before-compact
      :session-before-tree)
     last-result)
    (:tool-call-error last-result)
    (:context
     (list :messages (copy-list (getf state :messages))))
    (:before-agent-start
     (let ((result nil))
       (when (getf state :messages)
         (setf
          (getf result :messages)
          (copy-list (getf state :messages))))
       (when (getf state :modified-p)
         (setf
          (getf result :system-prompt)
          (getf state :system-prompt)))
       result))
    (:message-end
     (list :message (getf state :message)))
    (:input
     (cond
       ((getf state :handled-p)
        '(:action :handled))
       ((getf state :modified-p)
        (list
         :action :transform
         :text (getf state :text)
         :images (getf state :images)))
       (t '(:action :continue))))
    (:project-trust
     last-result)
    (:resources-discover
     (list
      :skill-paths
      (copy-list (getf state :skill-paths))
      :prompt-paths
      (copy-list (getf state :prompt-paths))
      :theme-paths
      (copy-list (getf state :theme-paths))))
    (:before-provider-request
     (getf state :payload))
    (:before-provider-headers
     (getf state :headers))
    (:user-bash
     last-result)
    (otherwise nil)))

(defun run-extension-lifecycle-hooks
    (host event &key payload)
  (unless
      (and
       (member event +extension-hook-events+)
       (not
        (member
         event
         '(:turn-start
           :turn-end
           :tool-call-before
           :tool-call-after))))
    (error
     'extension-execution-error
     :message
     (format nil "Unsupported lifecycle event: ~S" event)))
  (let* ((snapshot
           (extension-host-current-snapshot host))
         (definitions
           (copy-list
            (gethash
             event
             (extension-snapshot-hooks snapshot))))
         (state (initial-lifecycle-state event payload))
         (last-result nil)
         (held (acquire-extension-snapshot host snapshot)))
    (unwind-protect
         (sb-thread:with-recursive-lock
             ((extension-host-hook-lock host))
           (dolist (definition definitions)
             (handler-case
                 (let* ((handler-payload
                          (lifecycle-event-payload-for-handler
                           event payload state))
                        (result
                          (call-with-extension-definition
                           host snapshot definition
                           (lambda (context)
                             (funcall
                              (extension-hook-definition-handler
                               definition)
                              (make-lifecycle-event
                               event handler-payload)
                              context)))))
                   (validate-lifecycle-result
                    event result handler-payload)
                   (when result
                     (setf last-result result))
                   (setf
                    state
                    (merge-lifecycle-result
                     event state result))
                   (when
                       (or
                        (and
                         (member
                          event
                          '(:session-before-switch
                            :session-before-fork
                            :session-before-compact
                            :session-before-tree))
                         result
                         (getf result :cancel-p))
                        (and
                         (eq event :input)
                         (getf state :handled-p))
                        (and
                         (eq event :project-trust)
                         result
                         (member
                          (getf result :trusted)
                          '(:yes :no)))
                        (and
                         (eq event :user-bash)
                         result)
                        (and
                         (eq event :tool-call-error)
                         result))
                     (return)))
               (condition (condition)
                 (notify-extension-failure
                  host definition "Lifecycle hook"
                  condition)))))
      (release-acquired-extension-snapshot host held))
    (finalize-lifecycle-state
     event state last-result)))
