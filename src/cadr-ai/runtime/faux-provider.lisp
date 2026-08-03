(in-package #:cadr-ai)

(defstruct faux-state
  (call-count 0 :type (integer 0 *)))

(defstruct (faux-handle
            (:constructor %make-faux-handle))
  provider
  (api :faux :type symbol)
  (provider-id :faux :type symbol)
  (models nil :type list)
  (responses nil :type list)
  (state (make-faux-state) :type faux-state)
  (prompt-cache (make-hash-table :test #'equal)
                :type hash-table)
  (token-min 3 :type (integer 1 *))
  (token-max 5 :type (integer 1 *)))

(defun faux-text (text)
  (make-text-content :text text))

(defun faux-thinking (thinking)
  (make-thinking-content :thinking thinking))

(defun faux-tool-call (name arguments &key id)
  (make-tool-call
   :id (or id (format nil "tool:~A" (uuid-v7)))
   :name name
   :arguments arguments))

(defun faux-assistant-message
    (content &key (stop-reason :stop)
                     error-message response-id timestamp)
  (make-assistant-message
   :content
   (cond
     ((stringp content) (list (faux-text content)))
     ((or (typep content 'text-content)
          (typep content 'thinking-content)
          (typep content 'tool-call))
      (list content))
     (t (copy-list content)))
   :api :faux
   :provider :faux
   :model "faux-1"
   :usage (make-usage)
   :stop-reason stop-reason
   :error-message error-message
   :response-id response-id
   :timestamp (or timestamp (unix-milliseconds))))

(defun faux-make-model (api provider-id definition)
  (make-model
   :id (or (getf definition :id) "faux-1")
   :name (or (getf definition :name)
             (getf definition :id)
             "Faux Model")
   :api api
   :provider provider-id
   :base-url "http://localhost:0"
   :reasoning-p (not (null (getf definition :reasoning-p)))
   :supports-images-p
   (if (member :supports-images-p definition)
       (not (null (getf definition :supports-images-p)))
       t)
   :context-window
   (or (getf definition :context-window) 128000)
   :max-tokens (or (getf definition :max-tokens) 16384)))

(defun make-faux-provider
    (&key (api :faux)
          (provider-id :faux)
          model-definitions
          (token-min 3)
          (token-max 5))
  (let* ((definitions
           (or model-definitions
               '((:id "faux-1"
                  :name "Faux Model"
                  :reasoning-p nil))))
         (models
           (mapcar
            (lambda (definition)
              (faux-make-model
               api provider-id definition))
            definitions))
         (handle
           (%make-faux-handle
            :api api
            :provider-id provider-id
            :models models
            :token-min
            (max 1 (min token-min token-max))
            :token-max
            (max token-min token-max))))
    (setf
     (faux-handle-provider handle)
     (make-runtime-provider
      :id provider-id
      :name (symbol-name provider-id)
      :models models
      :api-key-auth-p t
      :auth-resolver
      (lambda (&rest ignored)
        (declare (ignore ignored))
        (make-runtime-auth-result
         :source "Faux" :type :api-key))
      :complete-function
      (lambda (model context options)
        (apply #'faux-complete
               handle model context options))
      :stream-function
      (lambda (model context on-event &rest options)
        (apply #'faux-stream
               handle model context on-event options))))
    handle))

(defun faux-set-responses (handle responses)
  (setf (faux-handle-responses handle)
        (copy-list responses))
  handle)

(defun faux-append-responses (handle responses)
  (setf (faux-handle-responses handle)
        (append (faux-handle-responses handle)
                (copy-list responses)))
  handle)

(defun faux-pending-response-count (handle)
  (length (faux-handle-responses handle)))

(defun faux-get-model (handle &optional model-id)
  (if model-id
      (find model-id
            (faux-handle-models handle)
            :key #'model-id
            :test #'string=)
      (first (faux-handle-models handle))))

(defun faux-copy-content-block (block)
  (cond
    ((typep block 'text-content)
     (make-text-content
      :text (text-content-text block)
      :signature (text-content-signature block)))
    ((typep block 'thinking-content)
     (make-thinking-content
      :thinking (thinking-content-thinking block)
      :signature (thinking-content-signature block)
      :redacted-p (thinking-content-redacted-p block)))
    ((typep block 'tool-call)
     (make-tool-call
      :id (tool-call-id block)
      :name (tool-call-name block)
      :arguments (tool-call-arguments block)
      :thought-signature
      (tool-call-thought-signature block)))
    (t block)))

(defun faux-copy-message (message handle model)
  (make-assistant-message
   :content
   (mapcar #'faux-copy-content-block
           (assistant-message-content message))
   :api (faux-handle-api handle)
   :provider (faux-handle-provider-id handle)
   :model (model-id model)
   :response-model
   (assistant-message-response-model message)
   :response-id (assistant-message-response-id message)
   :usage (assistant-message-usage message)
   :stop-reason (assistant-message-stop-reason message)
   :error-message (assistant-message-error-message message)
   :raw-stop-reason
   (assistant-message-raw-stop-reason message)
   :timestamp (assistant-message-timestamp message)))

(defun faux-content-text (content)
  (cond
    ((stringp content) content)
    ((or (listp content) (vectorp content))
     (format
      nil "~{~A~^~%~}"
      (loop for block across (coerce content 'vector)
            collect
            (cond
              ((typep block 'text-content)
               (text-content-text block))
              ((typep block 'image-content)
               (format nil "[image:~A:~D]"
                       (image-content-mime-type block)
                       (length (image-content-data block))))
              (t "")))))
    (t "")))

(defun faux-assistant-content-text (content)
  (format
   nil "~{~A~^~%~}"
   (mapcar
    (lambda (block)
      (cond
        ((typep block 'text-content)
         (text-content-text block))
        ((typep block 'thinking-content)
         (thinking-content-thinking block))
        ((typep block 'tool-call)
         (format nil "~A:~A"
                 (tool-call-name block)
                 (stringify-json
                  (tool-call-arguments block))))
        (t "")))
    content)))

(defun faux-message-text (message)
  (cond
    ((typep message 'user-message)
     (faux-content-text (user-message-content message)))
    ((typep message 'assistant-message)
     (faux-assistant-content-text
      (assistant-message-content message)))
    ((typep message 'tool-result-message)
     (format nil "~A~%~A"
             (tool-result-message-tool-name message)
             (faux-content-text
              (tool-result-message-content message))))
    (t "")))

(defun faux-serialize-context (context)
  (format
   nil "~{~A~^~%~%~}"
   (append
    (when (context-system-prompt context)
      (list
       (format nil "system:~A"
               (context-system-prompt context))))
    (mapcar
     (lambda (message)
       (format nil "~A:~A"
               (cond
                 ((typep message 'user-message) "user")
                 ((typep message 'assistant-message)
                  "assistant")
                 (t "toolResult"))
               (faux-message-text message)))
     (context-messages context))
    (when (context-tools context)
      (list
       (format nil "tools:~{~A~^,~}"
               (mapcar #'tool-name
                       (context-tools context))))))))

(defun common-prefix-length (left right)
  (loop for index from 0
        below (min (length left) (length right))
        while (char= (char left index)
                     (char right index))
        finally (return index)))

(defun faux-with-usage
    (handle message context session-id cache-retention)
  (let* ((prompt (faux-serialize-context context))
         (prompt-tokens (estimate-text-tokens prompt))
         (output-tokens
           (estimate-text-tokens
            (faux-assistant-content-text
             (assistant-message-content message))))
         (input prompt-tokens)
         (cache-read 0)
         (cache-write 0))
    (when (and session-id
               (not (eq cache-retention :none)))
      (let ((previous
              (gethash session-id
                       (faux-handle-prompt-cache handle))))
        (if previous
            (let ((prefix
                    (common-prefix-length previous prompt)))
              (setf cache-read
                    (estimate-text-tokens
                     (subseq previous 0 prefix))
                    cache-write
                    (estimate-text-tokens
                     (subseq prompt prefix))
                    input (max 0
                               (- prompt-tokens cache-read))))
            (setf cache-write prompt-tokens))
        (setf
         (gethash session-id
                  (faux-handle-prompt-cache handle))
         prompt)))
    (setf
     (assistant-message-usage message)
     (make-usage
      :input input
      :output output-tokens
      :cache-read cache-read
      :cache-write cache-write))
    message))

(defun faux-error-message (handle model text &optional aborted-p)
  (make-assistant-message
   :api (faux-handle-api handle)
   :provider (faux-handle-provider-id handle)
   :model (model-id model)
   :content nil
   :stop-reason (if aborted-p :aborted :error)
   :error-message text))

(defun faux-resolve
    (handle model context options)
  (incf (faux-state-call-count
         (faux-handle-state handle)))
  (let ((step (pop (faux-handle-responses handle))))
    (unless step
      (return-from faux-resolve
        (faux-error-message
         handle model "No more faux responses queued")))
    (handler-case
        (let* ((resolved
                 (if (functionp step)
                     (funcall step context options
                              (faux-handle-state handle)
                              model)
                     step))
               (message
                 (faux-copy-message resolved handle model)))
          (when (eq :pending
                    (assistant-message-stop-reason message))
            (return-from faux-resolve
              (faux-error-message
               handle model
               "Faux response ended without a stop reason")))
          (faux-with-usage
           handle message context
           (getf options :session-id)
           (getf options :cache-retention)))
      (error (condition)
        (faux-error-message
         handle model (princ-to-string condition))))))

(defun faux-complete
    (handle model context &rest options
     &key abort-p &allow-other-keys)
  (when (cadr-core:cancellation-predicate-aborted-p abort-p)
    (return-from faux-complete
      (faux-error-message
       handle model "Request was aborted" t)))
  (faux-resolve handle model context options))

(defun faux-emit
    (emit type message
     &key content-index delta content tool-call reason)
  (funcall
   emit
   (make-stream-event
    :type type
    :message message
    :content-index content-index
    :delta delta
    :content content
    :tool-call tool-call
    :reason reason)))

(defun faux-stream
    (handle model context on-event
     &rest options &key abort-p &allow-other-keys)
  (let ((message
          (if (cadr-core:cancellation-predicate-aborted-p abort-p)
              (faux-error-message
               handle model "Request was aborted" t)
              (faux-resolve handle model context options))))
    (when (member (assistant-message-stop-reason message)
                  '(:error :aborted))
      (faux-emit
       on-event :error message
       :reason (assistant-message-stop-reason message))
      (return-from faux-stream message))
    (faux-emit on-event :start message)
    (loop for block in (assistant-message-content message)
          for index from 0
          do
          (cond
            ((typep block 'thinking-content)
             (faux-emit
              on-event :thinking-start message
              :content-index index)
             (faux-emit
              on-event :thinking-delta message
              :content-index index
              :delta
              (thinking-content-thinking block))
             (faux-emit
              on-event :thinking-end message
              :content-index index
              :content
              (thinking-content-thinking block)))
            ((typep block 'text-content)
             (faux-emit
              on-event :text-start message
              :content-index index)
             (faux-emit
              on-event :text-delta message
              :content-index index
              :delta (text-content-text block))
             (faux-emit
              on-event :text-end message
              :content-index index
              :content (text-content-text block)))
            ((typep block 'tool-call)
             (faux-emit
              on-event :tool-call-start message
              :content-index index)
             (faux-emit
              on-event :tool-call-delta message
              :content-index index
              :delta
              (stringify-json
               (tool-call-arguments block)))
             (faux-emit
              on-event :tool-call-end message
              :content-index index
              :tool-call block))))
    (faux-emit
     on-event :done message
     :reason (assistant-message-stop-reason message))
    message))
