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
  (token-max 5 :type (integer 1 *))
  (tokens-per-second 0 :type (real 0 *)))

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
          (token-max 5)
          (tokens-per-second 0))
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
            (max token-min token-max)
            :tokens-per-second
            (max 0 tokens-per-second))))
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
      :arguments (copy-json-value (tool-call-arguments block))
      :thought-signature
      (tool-call-thought-signature block)))
    (t block)))

(defun faux-copy-usage (usage)
  (let ((snapshot (copy-usage usage)))
    (setf (usage-cost snapshot)
          (copy-cost (usage-cost usage)))
    snapshot))

(defun faux-copy-stream-message (message)
  (make-assistant-message
   :content (copy-list (assistant-message-content message))
   :api (assistant-message-api message)
   :provider (assistant-message-provider message)
   :model (assistant-message-model message)
   :response-model (assistant-message-response-model message)
   :response-id (assistant-message-response-id message)
   :usage (assistant-message-usage message)
   :stop-reason (assistant-message-stop-reason message)
   :error-message (assistant-message-error-message message)
   :raw-stop-reason (assistant-message-raw-stop-reason message)
   :diagnostics (assistant-message-diagnostics message)
   :timestamp (assistant-message-timestamp message)))

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
       (format
        nil "tools:~A"
        (stringify-json
         (list-json-array
          (mapcar #'faux-tool-json-object
                  (context-tools context))))))))))

(defun faux-tool-json-object (tool)
  ;; pi packages/ai/src/types.ts Tool + faux.ts serializeContext:
  ;; JSON.stringify(context.tools) exposes name/description/parameters only.
  (json-object
   "name" (tool-name tool)
   "description" (tool-description tool)
   "parameters" (tool-parameters tool)))

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
        (values
         (faux-with-usage
          handle
          (faux-error-message
           handle model "No more faux responses queued")
          context
          (getf options :session-id)
          (getf options :cache-retention))
         t)))
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
        (values
         (faux-error-message
          handle model (princ-to-string condition))
         t)))))

(defun faux-complete
    (handle model context &rest options
     &key abort-p &allow-other-keys)
  (when (cadr-core:cancellation-predicate-aborted-p abort-p)
    (return-from faux-complete
      (faux-error-message
       handle model "Request was aborted" t)))
  (nth-value 0 (faux-resolve handle model context options)))

(defun faux-emit
    (emit type message
     &key content-index delta content tool-call reason)
  (funcall
   emit
   (make-stream-event
    :type type
    :message
    (if (eq :pending (assistant-message-stop-reason message))
        (faux-copy-stream-message message)
        message)
    :content-index content-index
    :delta delta
    :content content
    :tool-call tool-call
    :reason reason)))

(defun faux-partial-message (message)
  (make-assistant-message
   :content nil
   :api (assistant-message-api message)
   :provider (assistant-message-provider message)
   :model (assistant-message-model message)
   :response-model (assistant-message-response-model message)
   :response-id (assistant-message-response-id message)
   :usage (assistant-message-usage message)
   :stop-reason :pending
   :error-message (assistant-message-error-message message)
   :raw-stop-reason (assistant-message-raw-stop-reason message)
   :timestamp (assistant-message-timestamp message)))

(defun faux-aborted-partial-message (partial)
  (make-assistant-message
   :content (mapcar #'faux-copy-content-block
                    (assistant-message-content partial))
   :api (assistant-message-api partial)
   :provider (assistant-message-provider partial)
   :model (assistant-message-model partial)
   :response-model (assistant-message-response-model partial)
   :response-id (assistant-message-response-id partial)
   :usage (assistant-message-usage partial)
   :stop-reason :aborted
   :error-message "Request was aborted"
   :timestamp (unix-milliseconds)))

(defun faux-split-string (handle text)
  (let ((chunks nil)
        (index 0)
        (minimum (faux-handle-token-min handle))
        (maximum (faux-handle-token-max handle)))
    (loop while (< index (length text))
          for token-size =
            (+ minimum (random (1+ (- maximum minimum))))
          for end =
            (min (length text) (+ index (* 4 token-size)))
          do
          (push (subseq text index end) chunks)
          (setf index end))
    (or (nreverse chunks) (list ""))))

(defun faux-wait-for-chunk (handle chunk)
  (let ((rate (faux-handle-tokens-per-second handle)))
    (when (plusp rate)
      (sleep
       (/ (estimate-text-tokens chunk) rate))))
  nil)

(defun faux-stream-aborted-p (abort-p)
  (cadr-core:cancellation-predicate-aborted-p abort-p))

(defun faux-stream-block
    (handle abort-p emit-fn partial index
     partial-block start-event chunks apply-chunk
     delta-event end-event &rest end-args)
  ;; One emit skeleton for thinking / text / tool-call.
  (let ((before-end (getf end-args :before-end))
        (event-args (copy-list end-args)))
    (remf event-args :before-end)
    (setf (assistant-message-content partial)
          (append (assistant-message-content partial)
                  (list partial-block)))
    (faux-emit emit-fn start-event partial :content-index index)
    (dolist (chunk chunks)
      (faux-wait-for-chunk handle chunk)
      (when (faux-stream-aborted-p abort-p)
        (return-from faux-stream-block :aborted))
      (funcall apply-chunk partial-block chunk)
      (faux-emit emit-fn delta-event partial
                 :content-index index :delta chunk))
    (when before-end
      (funcall before-end))
    (apply #'faux-emit emit-fn end-event partial
           :content-index index event-args)
    nil))

(defun faux-emit-aborted (on-event partial)
  (let ((aborted (faux-aborted-partial-message partial)))
    (faux-emit on-event :error aborted :reason :aborted)
    aborted))

(defun faux-stream
    (handle model context on-event
     &rest options &key abort-p &allow-other-keys)
  (multiple-value-bind (message resolution-error-p)
      (faux-resolve handle model context options)
    (let ((partial (faux-partial-message message))
          (queued-events nil)
          ;; The fixed zero-delay faux baseline queues the whole stream before its
          ;; consumer runs.  Paced streams yield at each chunk instead.
          (paced-p
            (plusp (faux-handle-tokens-per-second handle))))
      (labels ((emit-event (event)
                 (if paced-p
                     (funcall on-event event)
                     (push event queued-events)))
               (finish (result)
                 (dolist (event (nreverse queued-events))
                   (funcall on-event event))
                 result))
        (when resolution-error-p
          (faux-emit #'emit-event :error message :reason :error)
          (return-from faux-stream (finish message)))
        (when (faux-stream-aborted-p abort-p)
          (return-from faux-stream
            (finish (faux-emit-aborted #'emit-event partial))))
        (faux-emit #'emit-event :start partial)
      (loop for block in (assistant-message-content message)
            for index from 0
            do
            (when
                (eq :aborted
                    (cond
                      ((typep block 'thinking-content)
                       (faux-stream-block
                        handle abort-p #'emit-event partial index
                        (make-thinking-content :thinking "")
                        :thinking-start
                        (faux-split-string
                         handle (thinking-content-thinking block))
                        (lambda (partial-block chunk)
                          (setf (thinking-content-thinking
                                 partial-block)
                                (concatenate
                                 'string
                                 (thinking-content-thinking
                                  partial-block)
                                 chunk)))
                        :thinking-delta :thinking-end
                        :content
                        (thinking-content-thinking block)))
                      ((typep block 'text-content)
                       (faux-stream-block
                        handle abort-p #'emit-event partial index
                        (make-text-content :text "")
                        :text-start
                        (faux-split-string
                         handle (text-content-text block))
                        (lambda (partial-block chunk)
                          (setf (text-content-text partial-block)
                                (concatenate
                                 'string
                                 (text-content-text partial-block)
                                 chunk)))
                        :text-delta :text-end
                        :content (text-content-text block)))
                      ((typep block 'tool-call)
                       (let ((partial-block
                               (make-tool-call
                                :id (tool-call-id block)
                                :name (tool-call-name block)
                                :arguments (json-object))))
                         (faux-stream-block
                          handle abort-p #'emit-event
                          partial index
                          partial-block
                          :tool-call-start
                          (faux-split-string
                           handle
                           (stringify-json
                            (tool-call-arguments block)))
                          (lambda (partial-block chunk)
                            (declare (ignore
                                      partial-block chunk)))
                          :tool-call-delta :tool-call-end
                          :before-end
                          (lambda ()
                            (setf (tool-call-arguments
                                   partial-block)
                                  (tool-call-arguments block)))
                          :tool-call block)))
                      (t nil)))
              (return-from faux-stream
                (finish
                 (faux-emit-aborted #'emit-event partial)))))
      (when (eq :pending (assistant-message-stop-reason message))
        (error "Faux response ended without a stop reason"))
      (when (member (assistant-message-stop-reason message)
                    '(:error :aborted))
        (faux-emit
         #'emit-event :error message
         :reason (assistant-message-stop-reason message))
        (return-from faux-stream (finish message)))
      (faux-emit
       #'emit-event :done message
       :reason (assistant-message-stop-reason message))
      (finish message)))))
