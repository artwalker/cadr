(in-package #:pi-cli)

(defstruct tui-entry
  type
  (text "" :type string)
  tool-call-id
  tool-block)

(defstruct (tui-state
            (:constructor %make-tui-state))
  (model "—" :type string)
  session
  (entries nil :type list)
  current-assistant
  (input-tokens 0 :type (integer 0 *))
  (output-tokens 0 :type (integer 0 *))
  (cache-tokens 0 :type (integer 0 *))
  (cost 0d0 :type double-float)
  (cost-known-p nil :type boolean))

(defun make-tui-state (&key model session messages)
  (let ((state
          (%make-tui-state
           :model (or model "—")
           :session session)))
    (dolist (message messages)
      (seed-tui-message state message))
    state))

(defun append-tui-entry (state entry)
  (setf
   (tui-state-entries state)
   (nconc (tui-state-entries state)
          (list entry)))
  entry)

(defun add-tui-notice (state text)
  (let ((trimmed
          (string-trim
           '(#\Space #\Tab #\Newline #\Return)
           (or text ""))))
    (when (plusp (length trimmed))
      (append-tui-entry
       state
       (make-tui-entry
        :type :notice
        :text trimmed))))
  state)

(defun assistant-price-known-p (message)
  (not
   (null
    (ignore-errors
      (pi-ai:find-model-metadata
       (pi-ai:assistant-message-provider message)
       (pi-ai:assistant-message-model message))))))

(defun accumulate-message-usage (state message)
  (let* ((usage
           (pi-ai:assistant-message-usage message))
         (cost (pi-ai:usage-cost usage)))
    (incf (tui-state-input-tokens state)
          (pi-ai:usage-input usage))
    (incf (tui-state-output-tokens state)
          (pi-ai:usage-output usage))
    (incf (tui-state-cache-tokens state)
          (+ (pi-ai:usage-cache-read usage)
             (pi-ai:usage-cache-write usage)))
    (when (assistant-price-known-p message)
      (setf (tui-state-cost-known-p state) t)
      (incf (tui-state-cost state)
            (pi-ai:cost-total cost)))))

(defun seed-tui-message (state message)
  (typecase message
    (pi-ai:user-message
     (append-tui-entry
      state
      (make-tui-entry
       :type :user
       :text
       (pi-ai::content-text
        (pi-ai:user-message-content message)))))
    (pi-ai:assistant-message
     (append-tui-entry
      state
      (make-tui-entry
       :type :assistant
       :text (response-text message)))
     (accumulate-message-usage state message)))
  state)

(defun tool-arguments-summary (call)
  (handler-case
      (pi-ai::stringify-json
       (pi-ai:tool-call-arguments call))
    (condition ()
      (princ-to-string
       (pi-ai:tool-call-arguments call)))))

(defun tool-result-text (result)
  (format
   nil "~{~A~^~%~}"
   (loop for block in
         (pi-ai:tool-result-message-content result)
         when (typep block 'pi-ai:text-content)
           collect (pi-ai:text-content-text block))))

(defun find-tool-entry (state call-id)
  (find
   call-id
   (tui-state-entries state)
   :from-end t
   :key #'tui-entry-tool-call-id
   :test #'string=))

(defun tui-handle-agent-event (state event)
  (let ((type (pi-agent:agent-event-type event))
        (message (pi-agent:agent-event-message event))
        (stream-event
          (pi-agent:agent-event-stream-event event)))
    (case type
      (:message-start
       (typecase message
         (pi-ai:user-message
          (append-tui-entry
           state
           (make-tui-entry
            :type :user
            :text
            (pi-ai::content-text
             (pi-ai:user-message-content message)))))
         (pi-ai:assistant-message
          (let ((entry
                  (append-tui-entry
                   state
                   (make-tui-entry
                    :type :assistant))))
            (setf
             (tui-state-current-assistant state)
             entry)))))
      (:message-update
       (when
           (and
            (tui-state-current-assistant state)
            stream-event
            (eq :text-delta
                (pi-ai:stream-event-type
                 stream-event)))
         (setf
          (tui-entry-text
           (tui-state-current-assistant state))
          (concatenate
           'string
           (tui-entry-text
            (tui-state-current-assistant state))
           (or
            (pi-ai:stream-event-delta
             stream-event)
            "")))))
      (:message-end
       (when (typep message 'pi-ai:assistant-message)
         (let ((entry
                 (tui-state-current-assistant state)))
           (when (and entry
                      (zerop
                       (length
                        (tui-entry-text entry))))
             (setf
              (tui-entry-text entry)
              (response-text message))))
         (accumulate-message-usage state message)
         (setf
          (tui-state-current-assistant state)
          nil)))
      (:tool-execution-start
       (let ((call
               (pi-agent:agent-event-tool-call event)))
         (append-tui-entry
          state
          (make-tui-entry
           :type :tool
           :tool-call-id
           (pi-ai:tool-call-id call)
           :tool-block
           (pi-tui:make-tool-block
            :name (pi-ai:tool-call-name call)
            :summary
            (tool-arguments-summary call)
            :status :running)))))
      (:tool-execution-end
       (let* ((call
                (pi-agent:agent-event-tool-call event))
              (result
                (pi-agent:agent-event-tool-result event))
              (entry
                (and call
                     (find-tool-entry
                      state
                      (pi-ai:tool-call-id call)))))
         (when entry
           (setf
            (pi-tui:tool-block-output
             (tui-entry-tool-block entry))
            (tool-result-text result)
            (pi-tui:tool-block-status
             (tui-entry-tool-block entry))
            (if
                (pi-ai:tool-result-message-is-error
                 result)
                :error
                :complete)
            (pi-tui:tool-block-collapsed-p
             (tui-entry-tool-block entry))
            t))))
      (:compaction-start
       (add-tui-notice state
                       "Compacting context…"))
      (:compaction-end
       (add-tui-notice state
                       "Context compacted"))
      (:compaction-error
       (add-tui-notice
        state
        (format nil
                "Context compaction failed: ~A"
                (pi-agent:agent-event-error-message
                 event))))))
  state)

(defun render-tui-entry (entry width)
  (case (tui-entry-type entry)
    (:user
     (pi-tui:wrap-text
      (format nil "you> ~A"
              (tui-entry-text entry))
      width))
    (:assistant
     (pi-tui:render-markdown
      (tui-entry-text entry)
      width))
    (:tool
     (pi-tui:render-tool-block
      (tui-entry-tool-block entry)
      width))
    (:notice
     (pi-tui:wrap-text
      (format nil "session> ~A"
              (tui-entry-text entry))
      width))
    (otherwise nil)))

(defun trailing-lines (lines count)
  (if (<= (length lines) count)
      lines
      (nthcdr (- (length lines) count)
              lines)))

(defun render-tui-state
    (state editor width rows
     &key overlay busy-p)
  (multiple-value-bind
        (editor-lines editor-row editor-column)
      (pi-tui:render-editor editor width)
    (let* ((status-lines 1)
           (content-height
             (max 0
                  (- rows
                     status-lines
                     (length editor-lines))))
           (all-content
             (if overlay
                 (pi-tui:render-select-list
                  overlay width)
                 (loop for entry in
                       (tui-state-entries state)
                       append
                       (render-tui-entry
                        entry width))))
           (visible
             (trailing-lines
              all-content content-height))
           (padding
             (make-list
              (max 0
                   (- content-height
                      (length visible)))
              :initial-element ""))
           (status
             (pi-tui:render-status-bar
              width
              :model
              (if busy-p
                  (format nil "~A • working"
                          (tui-state-model state))
                  (tui-state-model state))
              :input
              (tui-state-input-tokens state)
              :output
              (tui-state-output-tokens state)
              :cache
              (tui-state-cache-tokens state)
              :cost
              (and
               (tui-state-cost-known-p state)
               (tui-state-cost state))
              :session
              (tui-state-session state))))
      (values
       (nconc padding visible
              (list status)
              editor-lines)
       (+ content-height
          status-lines
          editor-row)
       editor-column))))

(defun toggle-last-tool-block (state)
  (let ((entry
          (find
           :tool
           (tui-state-entries state)
           :from-end t
           :key #'tui-entry-type)))
    (when entry
      (pi-tui:toggle-tool-block
       (tui-entry-tool-block entry)))))

(defun should-use-tui-p
    (no-tui-p
     &key
       (input *standard-input*)
       (output *standard-output*)
       (terminal-p-function
         #'pi-tui:terminal-stream-p))
  (and
   (not no-tui-p)
   (funcall terminal-p-function input :input)
   (funcall terminal-p-function output :output)))

#+sbcl
(defclass notification-output-stream
    (sb-gray:fundamental-character-output-stream)
  ((callback
    :initarg :callback
    :reader notification-stream-callback)
   (buffer
    :initform (make-string-output-stream)
    :accessor notification-stream-buffer)
   (lock
    :initform
    (sb-thread:make-mutex
     :name "pi-tui-notifications")
    :reader notification-stream-lock)))

#+sbcl
(defun notification-stream-flush (stream)
  (let ((text
          (get-output-stream-string
           (notification-stream-buffer stream))))
    (when (plusp (length text))
      (funcall
       (notification-stream-callback stream)
       text))))

#+sbcl
(defmethod sb-gray:stream-write-char
    ((stream notification-output-stream) character)
  (sb-thread:with-mutex
      ((notification-stream-lock stream))
    (if (char= character #\Newline)
        (notification-stream-flush stream)
        (write-char
         character
         (notification-stream-buffer stream))))
  character)

#+sbcl
(defmethod sb-gray:stream-finish-output
    ((stream notification-output-stream))
  (sb-thread:with-mutex
      ((notification-stream-lock stream))
    (notification-stream-flush stream))
  nil)

(defun make-notification-output-stream (callback)
  #+sbcl
  (make-instance
   'notification-output-stream
   :callback callback)
  #-sbcl
  (declare (ignore callback))
  #-sbcl
  *standard-output*)

(defun run-tui
    (prompt-function
     &key
       command-function
       template-function
       set-event-consumer
       set-notice-consumer
       model-items-function
       session-items-function
       on-model-selected
       on-session-selected
       abort-function
       reset-abort-function
       model
       session
       messages
       (terminal
         (pi-tui:make-process-terminal)))
  (let* ((state
           (make-tui-state
            :model model
            :session session
            :messages messages))
         (editor
           (pi-tui:make-multiline-editor))
         (decoder
           (pi-tui:make-input-decoder))
         (renderer
           (pi-tui:make-terminal-renderer
            terminal))
         (lock
           (sb-thread:make-mutex
            :name "pi-tui-state"))
         (overlay nil)
         (overlay-kind nil)
         (busy-p nil)
         (done-p nil)
         (worker nil))
    (labels
        ((render ()
           (sb-thread:with-mutex (lock)
             (multiple-value-bind
                   (lines cursor-row cursor-column)
                 (render-tui-state
                  state editor
                  (pi-tui:terminal-columns terminal)
                  (pi-tui:terminal-rows terminal)
                  :overlay overlay
                  :busy-p busy-p)
               (pi-tui:render-frame
                renderer lines
                :cursor-row cursor-row
                :cursor-column cursor-column))))
         (notice (text)
           (sb-thread:with-mutex (lock)
             (add-tui-notice state text))
           (render))
         (consume-event (event)
           (sb-thread:with-mutex (lock)
             (tui-handle-agent-event
              state event))
           (render))
         (start-work (line)
           (unless busy-p
             (when reset-abort-function
               (funcall reset-abort-function))
             (setf busy-p t)
             (render)
             (setf
              worker
              (sb-thread:make-thread
               (lambda ()
                 (unwind-protect
                      (handler-case
                          (multiple-value-bind
                                (kind result)
                              (dispatch-user-input
                               line prompt-function
                               :command-function
                               command-function
                               :template-function
                               template-function)
                            (when
                                (eq kind
                                    :unknown-command)
                              (notice
                               "Unknown command"))
                            (when
                                (and
                                 (eq kind :command)
                                 (stringp result)
                                 (plusp
                                  (length result)))
                              (notice result)))
                        (condition (condition)
                          (notice
                           (format nil "~A"
                                   condition))))
                   (setf busy-p nil)
                   (render)))
               :name "pi-tui-dispatch"))))
         (open-selector (kind items)
           (setf overlay-kind kind
                 overlay
                 (pi-tui:make-select-list
                  :items items
                  :height
                  (max 3
                       (- (pi-tui:terminal-rows
                           terminal)
                          5))))
           (render))
         (submit (line)
           (let ((trimmed
                   (string-trim
                    '(#\Space #\Tab #\Newline
                      #\Return)
                    line)))
             (cond
               ((string= trimmed "/model")
                (open-selector
                 :model
                 (if model-items-function
                     (funcall
                      model-items-function)
                     nil)))
               ((string= trimmed "/sessions")
                (open-selector
                 :session
                 (if session-items-function
                     (funcall
                      session-items-function)
                     nil)))
               (t
                (start-work line)))))
         (accept-selection (value)
           (let ((kind overlay-kind))
             (setf overlay nil
                   overlay-kind nil)
             (handler-case
                 (case kind
                   (:model
                    (when on-model-selected
                      (setf
                       (tui-state-model state)
                       (or
                        (funcall
                         on-model-selected
                         value)
                        (tui-state-model
                         state)))))
                   (:session
                    (when on-session-selected
                      (multiple-value-bind
                            (selected-session
                             selected-messages)
                          (funcall
                           on-session-selected
                           value)
                        (setf
                         (tui-state-session state)
                         (or
                          selected-session
                          (tui-state-session state)))
                        (when selected-messages
                          (setf
                           (tui-state-entries state) nil
                           (tui-state-current-assistant
                            state)
                           nil
                           (tui-state-input-tokens state)
                           0
                           (tui-state-output-tokens state)
                           0
                           (tui-state-cache-tokens state)
                           0
                           (tui-state-cost state)
                           0d0
                           (tui-state-cost-known-p
                            state)
                           nil)
                          (dolist
                              (message selected-messages)
                            (seed-tui-message
                             state message)))))))
               (condition (condition)
                 (add-tui-notice
                  state
                  (format nil "~A" condition)))))
           (render))
         (handle-event (event)
           (if overlay
               (multiple-value-bind
                     (action value)
                   (pi-tui:select-list-handle-event
                    overlay event)
                 (case action
                   (:select
                    (accept-selection value))
                   (:cancel
                    (setf overlay nil
                          overlay-kind nil)
                    (render))
                   (otherwise (render))))
               (case (pi-tui:input-event-kind event)
                 (:interrupt
                  (cond
                    (busy-p
                     (when abort-function
                       (funcall abort-function))
                     (notice "Abort requested"))
                    ((plusp
                      (length
                       (pi-tui:editor-text
                        editor)))
                     (pi-tui:editor-handle-event
                      editor
                      (pi-tui:make-input-event
                       :kind :clear))
                     (render))
                    (t (setf done-p t))))
                 (:eof
                  (unless busy-p
                    (setf done-p t)))
                 (:toggle-tools
                  (toggle-last-tool-block state)
                  (render))
                 (otherwise
                  (multiple-value-bind
                        (action value)
                      (pi-tui:editor-handle-event
                       editor event)
                    (if (eq action :submit)
                        (submit value)
                        (render))))))))
      (when set-event-consumer
        (funcall set-event-consumer
                 #'consume-event))
      (when set-notice-consumer
        (funcall set-notice-consumer
                 #'notice))
      (unwind-protect
           (pi-tui:call-with-terminal
            terminal
            (lambda ()
              (render)
              (loop until done-p
                    do
                    (when
                        (pi-tui:terminal-resized-p
                         terminal)
                      (pi-tui:invalidate-renderer
                       renderer)
                      (render))
                    (let ((input
                            (pi-tui:terminal-read-input
                             terminal)))
                      (dolist
                          (event
                           (if (plusp (length input))
                               (pi-tui:feed-input
                                decoder input)
                               (pi-tui:flush-input
                                decoder)))
                        (handle-event event)))
                    (sleep 0.02))))
        (when (and worker
                   (sb-thread:thread-alive-p
                    worker))
          (when abort-function
            (funcall abort-function))
          (sb-thread:join-thread worker))
        (when set-event-consumer
          (funcall set-event-consumer nil))
        (when set-notice-consumer
          (funcall set-notice-consumer nil))))
    state))
