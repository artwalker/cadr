(in-package #:cadr-agent/tests)

(in-suite cadr-agent-suite)

(defvar *goal26-extension-notifications* nil)

(test goal26-extension-hook-table-includes-provider-and-mcp-events
  ;; pi@71023aec1 ExtensionAPI on(provider_stream_event / mcp_servers_change)
  (dolist (event '(:provider-stream-event :mcp-servers-change))
    (is (member event cadr-agent::+extension-hook-events+))
    (is (member
         event
         cadr-agent::+extension-lifecycle-no-result-events+))))

(test goal26-provider-stream-event-reaches-extension-hooks
  (let* ((seen nil)
         (bundle
           (make-test-extension-bundle
            "provider-stream"
            (lambda ()
              (cadr-agent:define-event-hook
               :provider-stream-event
               :handler
               (lambda (event context)
                 (declare (ignore context))
                 (push (cadr-agent:extension-event-payload event)
                       seen)
                 nil)))))
         (host (make-test-extension-host (list bundle)))
         (data
           (cadr-ai::json-object
            "openrouter_metadata"
            (cadr-ai::json-object "strategy" "direct"))))
    (is-true
     (cadr-agent::extension-host-has-hook-p
      host :provider-stream-event))
    (cadr-agent::run-extension-lifecycle-hooks
     host :provider-stream-event
     :payload
     (list
      :data data
      :provider :openai
      :api :openai-completions
      :model "capture-model"))
    (is (= 1 (length seen)))
    (let ((payload (first seen)))
      (is (eq :openai (getf payload :provider)))
      (is (eq :openai-completions (getf payload :api)))
      (is (string= "capture-model" (getf payload :model)))
      (is (hash-table-p (getf payload :data)))
      (is (string=
           "direct"
           (cadr-ai::json-get
            (cadr-ai::json-get
             (getf payload :data)
             "openrouter_metadata")
            "strategy"))))))

(test goal26-stream-chat-forwards-on-provider-stream-event
  (let* ((seen nil)
         (model
           (cadr-ai:make-model
            :id "capture-model"
            :provider :openai
            :api :openai-completions
            :base-url "https://example.invalid/v1"
            :max-tokens 16))
         (raw
           (cadr-ai::make-sse-event
            :data
            (cadr-ai::stringify-json
             (cadr-ai::json-object "id" "chunk-1")))))
    (cadr-ai::notify-provider-stream-event
     (lambda (data callback-model)
       (push (list data (cadr-ai:model-id callback-model))
             seen))
     (cadr-ai::provider-stream-event-data raw)
     model)
    (is (= 1 (length seen)))
    (is (string= "chunk-1"
                 (cadr-ai::json-get (first (first seen)) "id")))
    (is (string= "capture-model" (second (first seen))))))
(test goal26-mcp-servers-change-emits-on-register
  (let* ((seen nil)
         (*goal26-extension-notifications* nil)
         (bundle
           (make-test-extension-bundle
            "mcp-handler"
            (lambda ()
              (cadr-agent:define-event-hook
               :mcp-servers-change
               :handler
               (lambda (event context)
                 (declare (ignore context))
                 (push (cadr-agent:extension-event-payload event)
                       seen)
                 nil)))
            :path "/tmp/mcp-handler.lisp"))
         (host
           (make-test-extension-host
            (list bundle)
            :notifications '*goal26-extension-notifications*)))
    (cadr-agent::call-with-extension-load
     host bundle
     (lambda ()
       (cadr-agent:extension-api-register-mcp-server
        (cadr-agent:current-extension-api)
        "jira"
        '(:url "https://mcp.example.com/jira"))))
    (is (= 1 (length seen)))
    (let* ((payload (first seen))
           (servers (getf payload :servers)))
      (is (= 1 (length servers)))
      (is (string=
           "jira"
           (cadr-agent:registered-mcp-server-name
            (first servers))))
      (is (string=
           "/tmp/mcp-handler.lisp"
           (cadr-agent:registered-mcp-server-extension-path
            (first servers)))))
    (is (null *goal26-extension-notifications*))
    (is (= 1
           (length
            (cadr-agent::extension-host-list-mcp-servers
             host))))))

(test goal26-unhandled-mcp-servers-are-reported
  (let* ((*goal26-extension-notifications* nil)
         (bundle
           (make-test-extension-bundle
            "mcp-orphan"
            (lambda ())
            :path "/tmp/mcp-orphan.lisp"))
         (host
           (make-test-extension-host
            (list bundle)
            :notifications '*goal26-extension-notifications*)))
    (cadr-agent::call-with-extension-load
     host bundle
     (lambda ()
       (cadr-agent:extension-api-register-mcp-server
        (cadr-agent:current-extension-api)
        "orphan"
        '(:command "npx"))))
    (is (= 1 (length *goal26-extension-notifications*)))
    (is (eq :error
            (first (first *goal26-extension-notifications*))))
    (is (search
         "no loaded extension connects MCP servers"
         (second (first *goal26-extension-notifications*))))))
