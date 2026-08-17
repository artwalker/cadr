(in-package #:cadr-ai/live-tests)
(in-suite cadr-ai-live-suite)

(defparameter *opencode-go-sweep-representatives*
  '("mimo-v2.5" "qwen3.7-plus" "grok-4.5"))

(defparameter *opencode-go-sweep-remainder*
  '("minimax-m3" "qwen3.7-max" "qwen3.8-max"
    "deepseek-v4-flash" "deepseek-v4-pro"
    "glm-5.1" "glm-5.2" "hy3"
    "kimi-k2.6" "kimi-k2.7-code" "kimi-k3"
    "mimo-v2.5-pro" "minimax-m2.7" "qwen3.6-plus"
    "gpt-5.6-luna"))

(defun collect-thinking-field-names (value acc)
  (cond
    ((hash-table-p value)
     (maphash
      (lambda (key child)
        (when (and (stringp key)
                   (or (search "reason" key :test #'char-equal)
                       (search "think" key :test #'char-equal)))
          (pushnew key acc :test #'string=))
        (setf acc (collect-thinking-field-names child acc)))
      value)
     acc)
    ((vectorp value)
     (loop for child across value
           do (setf acc
                    (collect-thinking-field-names child acc)))
     acc)
    ((consp value)
     (dolist (child value acc)
       (setf acc (collect-thinking-field-names child acc))))
    (t acc)))

(defun sweep-row-kind (row)
  (cond
    ((cadr-live-test-support:provider-quota-exhausted-p
      (getf row :error))
     :skip-quota)
    ((cadr-live-test-support:provider-endpoint-unavailable-p
      (getf row :error))
     :skip-endpoint)
    ((getf row :thinking-p)
     :ok)
    ((getf row :content-fields)
     :parse-miss)
    (t
     :provider-hidden)))

(defun sweep-one-opencode-go-model (api-key model-id)
  (multiple-value-bind (provider model)
      (cadr-ai:instantiate-provider
       :opencode-go
       :api-key api-key
       :model-id model-id)
    (let* ((message (cadr-ai::empty-assistant-message model))
           (state (cadr-ai::make-provider-stream-state
                   :message message))
           (events nil)
           (raw-fields nil)
           (content-fields nil)
           (context
             (cadr-ai:make-context
              :system-prompt
              "Follow the requested output format exactly and do not call tools."
              :messages
              (list
               (cadr-ai:make-user-message
                :content
                "Think through why 17 is prime, then reply with one short sentence.")))))
      (handler-case
          (let ((request
                  (cadr-ai::build-request
                   provider model context
                   :stream-p t
                   :reasoning :medium)))
            (cadr-ai::request-provider-events
             (cadr-ai::prepare-provider-sse-request provider request)
             (lambda (event)
               (let ((payload
                       (handler-case
                           (cadr-ai::parse-json
                            (cadr-ai:sse-event-data event))
                         (error () (cadr-ai::json-object)))))
                 (setf raw-fields
                       (collect-thinking-field-names
                        payload raw-fields))
                 (setf content-fields
                       (cadr-live-test-support:live-sse-thinking-content-fields
                        payload content-fields)))
               (cadr-ai::reduce-provider-sse-event
                provider state event
                (lambda (stream-event)
                  (push stream-event events))))
             :environment
             (getf (cadr-ai::provider-options provider)
                   :environment))
            (cadr-ai::finalize-provider-stream
             provider model state
             (lambda (stream-event)
               (push stream-event events)))
            (setf events (nreverse events))
            (list
             :id model-id
             :api (cadr-ai:model-api model)
             :thinking-p
             (and
              (find :thinking-start events
                    :key #'cadr-ai:stream-event-type)
              (let ((text (live-thinking-text message)))
                (and (stringp text) (plusp (length text)))))
             :raw-fields (nreverse raw-fields)
             :content-fields (nreverse content-fields)
             :error nil))
        (error (condition)
          (list
           :id model-id
           :api (cadr-ai:model-api model)
           :thinking-p nil
           :raw-fields (nreverse raw-fields)
           :content-fields (nreverse content-fields)
           :error (princ-to-string condition)))))))

(test live-opencode-go-catalog-sweep
  (unless
      (live-environment-value "CADR_LIVE_OPENCODE_GO_SWEEP")
    (skip "CADR_LIVE_OPENCODE_GO_SWEEP is not set"))
  (let ((credential
          (cadr-live-test-support:prepare-opencode-go-credential)))
    (if
        (not
         (typep credential
                'cadr-ai:api-key-credential))
        (skip "OpenCode Go API key is not configured")
        (let* ((api-key
                 (cadr-ai:api-key-credential-key credential))
               (ids
                 (append *opencode-go-sweep-representatives*
                         *opencode-go-sweep-remainder*))
               (rows
                 (mapcar
                  (lambda (id)
                    (sweep-one-opencode-go-model api-key id))
                  ids))
               (defects
                 (remove-if-not
                  (lambda (row)
                    (eq :parse-miss (sweep-row-kind row)))
                  rows)))
          (format
           t
           "~%OpenCode Go catalog sweep~%id~20Tapi~40Tkind raw-fields content error~%")
          (dolist (row rows)
            (format
             t
             "~A~20T~A~40T~A ~S ~S ~A~%"
             (getf row :id)
             (getf row :api)
             (sweep-row-kind row)
             (getf row :raw-fields)
             (getf row :content-fields)
             (or (getf row :error) "")))
          (is (null defects)
              "opencode-go SSE had thinking text that cadr did not parse: ~S"
              defects)))))
