(in-package #:cadr-agent/tests)
(in-suite cadr-agent-suite)

(defun make-test-extension-bundle (id thunk
                                   &key
                                     (path (format nil "/tmp/~A.lisp" id))
                                     (scope :project)
                                     (rank 1)
                                     (order 0))
  (let ((bundle
          (cadr-agent::make-extension-bundle
           :id id
           :path path
           :scope scope
           :rank rank
           :order order)))
    (cadr-agent::call-with-extension-registration bundle thunk)
    bundle))

(defun make-test-extension-host (bundles &key notifications)
  (let ((host
          (cadr-agent::make-extension-host
           :cwd #P"/tmp/"
           :mode :repl
           :notify-function
           (lambda (message level)
             (when notifications
               (push (list level message)
                     (symbol-value notifications)))))))
    (cadr-agent::replace-extension-bundles host bundles)
    host))

(test extension-registration-requires-a-load-context
  (signals cadr-agent:extension-registration-error
    (cadr-agent:define-tool
     "outside"
     :description "Must fail"
     :parameters (object-schema)
     :handler
     (lambda (call-id arguments context)
       (declare (ignore call-id arguments context))
       (values nil nil))))
  (signals cadr-agent:extension-registration-error
    (cadr-agent:define-command
     "outside"
     :handler
     (lambda (arguments context)
       (declare (ignore arguments context)))))
  (signals cadr-agent:extension-registration-error
    (cadr-agent:define-event-hook
     :turn-start
     :handler
     (lambda (event context)
       (declare (ignore event context)))))
  (signals cadr-agent:extension-registration-error
    (cadr-agent:define-prompt-template
     "outside"
     :template "no")))

(test extension-registration-validates-the-frozen-contract
  (flet ((attempt (thunk)
           (signals cadr-agent:extension-registration-error
             (make-test-extension-bundle
              "invalid" thunk))))
    (attempt
     (lambda ()
       (cadr-agent:define-tool
        "Uppercase"
        :description "bad"
        :parameters (object-schema)
        :handler (lambda (id args context)
                   (declare (ignore id args context))))))
    (attempt
     (lambda ()
       (cadr-agent:define-tool
        "bad-mode"
        :description "bad"
        :parameters (object-schema)
        :execution-mode :sometimes
        :handler (lambda (id args context)
                   (declare (ignore id args context))))))
    (attempt
     (lambda ()
       (cadr-agent:define-tool
        "bad-schema"
        :description "bad"
        :parameters nil
        :handler (lambda (id args context)
                   (declare (ignore id args context))))))
    (attempt
     (lambda ()
       (cadr-agent:define-command
        "/bad"
        :handler (lambda (arguments context)
                   (declare (ignore arguments context))))))
    (attempt
     (lambda ()
       (cadr-agent:define-event-hook
        :unknown
        :handler (lambda (event context)
                   (declare (ignore event context))))))
    (attempt
     (lambda ()
       (cadr-agent:define-prompt-template
        "bad-template"
        :template 42)))))

(test extension-tool-runs-with-context-and-becomes-stale-after-return
  (let ((saved-context nil)
        (*responses*
          (list
           (assistant
            (list
             (make-tool-call
              :id "ext-1"
              :name "extension-echo"
              :arguments
              (cadr-ai::json-object "value" "hello")))
            :tool-use)
           (assistant
            (list (make-text-content :text "done")))))
        (*contexts* nil))
    (declare (special *responses* *contexts*))
    (let* ((bundle
             (make-test-extension-bundle
              "echo"
              (lambda ()
                (cadr-agent:define-tool
                 "extension-echo"
                 :description "Echo from an extension"
                 :parameters (object-schema "value")
                 :execution-mode :parallel
                 :handler
                 (lambda (call-id arguments context)
                   (declare (ignore call-id))
                   (setf saved-context context)
                   (values
                    (list
                     (make-text-content
                      :text
                      (format nil "~A:~A"
                              (namestring
                               (cadr-agent:extension-context-cwd
                                context))
                              (cadr-ai::json-get arguments "value"))))
                    nil))))))
           (host (make-test-extension-host (list bundle)))
           (agent
             (make-agent
              :provider :mock
              :model (mock-model)
              :extension-host host
              :stream-function
              (faux-stream '*responses* '*contexts*))))
      (agent-prompt agent "run")
      (let ((result
              (find-if
               (lambda (message)
                 (typep message 'tool-result-message))
               (agent-messages agent))))
        (is (string= "/tmp/:hello" (text-result result))))
      (signals cadr-agent:stale-extension-context
        (cadr-agent:extension-context-cwd saved-context)))))

(test extension-hooks-chain-rewrite-append-block-and-contain-errors
  (let ((*notifications* nil)
        (seen nil))
    (declare (special *notifications*))
    (let* ((bundle
             (make-test-extension-bundle
              "hooks"
              (lambda ()
                (cadr-agent:define-event-hook
                 :tool-call-before
                 :priority -10
                 :handler
                 (lambda (event context)
                   (declare (ignore context))
                   (let ((call
                           (cadr-agent:extension-event-tool-call
                            event)))
                     (cadr-agent:make-extension-hook-result
                      :replacement
                      (make-tool-call
                       :id (cadr-ai:tool-call-id call)
                       :name (cadr-ai:tool-call-name call)
                       :arguments
                       (cadr-ai::json-object "value" "rewritten"))
                      :append-messages
                      (list
                       (cadr-ai:make-user-message
                        :content "hook-note"))))))
                (cadr-agent:define-event-hook
                 :tool-call-before
                 :priority 0
                 :handler
                 (lambda (event context)
                   (declare (ignore context))
                   (push
                    (cadr-ai::json-get
                     (cadr-ai:tool-call-arguments
                      (cadr-agent:extension-event-tool-call event))
                     "value")
                    seen)
                   (error "broken hook")))
                (cadr-agent:define-event-hook
                 :tool-call-before
                 :priority 10
                 :handler
                 (lambda (event context)
                   (declare (ignore context))
                   (when
                       (string=
                        "block"
                        (cadr-ai:tool-call-name
                         (cadr-agent:extension-event-tool-call
                          event)))
                     (cadr-agent:make-extension-hook-result
                      :block-p t
                      :reason "blocked by extension")))))))
           (host
             (make-test-extension-host
              (list bundle)
              :notifications '*notifications*))
           (call
             (make-tool-call
              :id "call-1"
              :name "echo"
              :arguments
              (cadr-ai::json-object "value" "original"))))
      (multiple-value-bind
            (replacement appended blocked-p reason)
          (cadr-agent::run-extension-hooks
           host :tool-call-before
           :tool-call call :turn-index 1)
        (is (string=
             "rewritten"
             (cadr-ai::json-get
              (cadr-ai:tool-call-arguments replacement)
              "value")))
        (is (= 1 (length appended)))
        (is (not blocked-p))
        (is (null reason)))
      (is (equal '("rewritten") seen))
      (is (search "broken hook"
                  (second (first *notifications*))))
      (multiple-value-bind
            (replacement appended blocked-p reason)
          (cadr-agent::run-extension-hooks
           host :tool-call-before
           :tool-call
           (make-tool-call
            :id "call-2"
            :name "block"
            :arguments (cadr-ai::json-object))
           :turn-index 1)
        (declare (ignore replacement appended))
        (is (not (null blocked-p)))
        (is (string= "blocked by extension" reason))))))

(test extension-tool-result-hook-can-rewrite-result
  (let* ((bundle
           (make-test-extension-bundle
            "result"
            (lambda ()
              (cadr-agent:define-event-hook
               :tool-call-after
               :handler
               (lambda (event context)
                 (declare (ignore context))
                 (let ((result
                         (cadr-agent:extension-event-tool-result
                          event)))
                   (cadr-agent:make-extension-hook-result
                    :replacement
                    (cadr-ai:make-tool-result-message
                     :tool-call-id
                     (cadr-ai:tool-result-message-tool-call-id
                      result)
                     :tool-name
                     (cadr-ai:tool-result-message-tool-name result)
                     :content
                     (list
                      (make-text-content :text "after-hook"))
                     :is-error nil))))))))
         (host (make-test-extension-host (list bundle)))
         (call
           (make-tool-call
            :id "result-1"
            :name "echo"
            :arguments (cadr-ai::json-object)))
         (result
           (cadr-ai:make-tool-result-message
            :tool-call-id "result-1"
            :tool-name "echo"
            :content (list (make-text-content :text "before")))))
    (multiple-value-bind (replacement appended blocked-p reason)
        (cadr-agent::run-extension-hooks
         host :tool-call-after
         :tool-call call
         :tool-result result
         :turn-index 1)
      (declare (ignore appended blocked-p reason))
      (is (string=
           "after-hook"
           (text-result replacement))))))

(test extension-prompt-template-supports-the-fixed-placeholder-contract
  (let* ((bundle
           (make-test-extension-bundle
            "prompts"
            (lambda ()
              (cadr-agent:define-prompt-template
               "substitute"
               :template
               "one=$1 two=${2:-d} all=$@ missing=${3:-x} tail=${@:2} slice=${@:2:1}")
              (cadr-agent:define-prompt-template
               "nonrecursive"
               :template "value=$1"))))
         (host (make-test-extension-host (list bundle))))
    (multiple-value-bind (text found-p)
        (cadr-agent::expand-extension-prompt
         host "/substitute a 'b c'")
      (is (not (null found-p)))
      (is (string=
           "one=a two=b c all=a b c missing=x tail=b c slice=b c"
           text)))
    (multiple-value-bind (text found-p)
        (cadr-agent::expand-extension-prompt
         host "/nonrecursive '$1'")
      (is (not (null found-p)))
      (is (string= "value=$1" text)))
    (multiple-value-bind (text found-p)
        (cadr-agent::expand-extension-prompt
         host "/missing arg")
      (is (not found-p))
      (is (string= "/missing arg" text)))))

(test extension-resource-precedence-is-first-wins-with-diagnostics
  (let* ((global
           (make-test-extension-bundle
            "global"
            (lambda ()
              (cadr-agent:define-tool
               "same"
               :description "global"
               :parameters (object-schema)
               :handler
               (lambda (call-id arguments context)
                 (declare (ignore call-id arguments context))
                 (values nil nil))))
            :scope :global :rank 0))
         (project
           (make-test-extension-bundle
            "project"
            (lambda ()
              (cadr-agent:define-tool
               "same"
               :description "project"
               :parameters (object-schema)
               :handler
               (lambda (call-id arguments context)
                 (declare (ignore call-id arguments context))
                 (values nil nil))))
            :scope :project :rank 1))
         (host (make-test-extension-host (list project global))))
    (is (string=
         "project"
         (cadr-ai:tool-description
          (find
           "same"
           (cadr-agent::extension-host-tools host)
           :key #'cadr-ai:tool-name
           :test #'string=))))
    (is (= 1
           (length
            (cadr-agent::extension-host-conflicts host))))))

(test tool-hooks-affect-real-execution-and-revalidate-rewritten-arguments
  (let ((executed nil)
        (*responses*
          (list
           (assistant
            (list
             (make-tool-call
              :id "hooked-1"
              :name "hooked"
              :arguments (cadr-ai::json-object)))
            :tool-use)
           (assistant
            (list (make-text-content :text "done")))))
        (*contexts* nil))
    (declare (special *responses* *contexts*))
    (let* ((tool
             (make-tool
              :name "hooked"
              :description "Hook target"
              :parameters (object-schema "value")
              :executor
              (lambda (call-id arguments)
                (declare (ignore call-id))
                (push
                 (cadr-ai::json-get arguments "value")
                 executed)
                (values
                 (list
                  (make-text-content :text "before-after"))
                 nil))))
           (bundle
             (make-test-extension-bundle
              "real-hooks"
              (lambda ()
                (cadr-agent:define-event-hook
                 :tool-call-before
                 :handler
                 (lambda (event context)
                   (declare (ignore context))
                   (let ((call
                           (cadr-agent:extension-event-tool-call
                            event)))
                     (cadr-agent:make-extension-hook-result
                      :replacement
                      (make-tool-call
                       :id (cadr-ai:tool-call-id call)
                       :name (cadr-ai:tool-call-name call)
                       :arguments
                       (cadr-ai::json-object
                        "value" "rewritten"))
                      :append-messages
                      (list
                       (cadr-ai:make-user-message
                        :content "before-extra"))))))
                (cadr-agent:define-event-hook
                 :tool-call-after
                 :handler
                 (lambda (event context)
                   (declare (ignore context))
                   (let ((result
                           (cadr-agent:extension-event-tool-result
                            event)))
                     (cadr-agent:make-extension-hook-result
                      :replacement
                      (cadr-ai:make-tool-result-message
                       :tool-call-id
                       (cadr-ai:tool-result-message-tool-call-id
                        result)
                       :tool-name
                       (cadr-ai:tool-result-message-tool-name
                        result)
                       :content
                       (list
                        (make-text-content
                         :text "after-hook"))
                       :is-error nil)
                      :append-messages
                      (list
                       (cadr-ai:make-user-message
                        :content "after-extra")))))))))
           (host (make-test-extension-host (list bundle)))
           (agent
             (make-agent
              :provider :mock
              :model (mock-model)
              :tools (list tool)
              :extension-host host
              :stream-function
              (faux-stream '*responses* '*contexts*))))
      (agent-prompt agent "run")
      (is (equal '("rewritten") executed))
      (let ((result
              (find-if
               (lambda (message)
                 (typep message 'tool-result-message))
               (agent-messages agent))))
        (is (string= "after-hook" (text-result result))))
      (is
       (equal
        '("before-extra" "after-extra")
        (loop
          for message in (agent-messages agent)
          when
          (and
           (typep message 'cadr-ai:user-message)
           (member
            (cadr-ai:user-message-content message)
            '("before-extra" "after-extra")
            :test #'string=))
            collect
            (cadr-ai:user-message-content message)))))))

(test invalid-tool-hook-rewrite-is-rejected-before-execution
  (let ((executions 0)
        (*responses*
          (list
           (assistant
            (list
             (make-tool-call
              :id "invalid-rewrite"
              :name "validated"
              :arguments
              (cadr-ai::json-object "value" "valid")))
            :tool-use)
           (assistant
            (list (make-text-content :text "recovered")))))
        (*contexts* nil))
    (declare (special *responses* *contexts*))
    (let* ((tool
             (make-tool
              :name "validated"
              :description "Validated"
              :parameters (object-schema "value")
              :executor
              (lambda (call-id arguments)
                (declare (ignore call-id arguments))
                (incf executions)
                (values nil nil))))
           (bundle
             (make-test-extension-bundle
              "invalid-rewrite"
              (lambda ()
                (cadr-agent:define-event-hook
                 :tool-call-before
                 :handler
                 (lambda (event context)
                   (declare (ignore context))
                   (let ((call
                           (cadr-agent:extension-event-tool-call
                            event)))
                     (cadr-agent:make-extension-hook-result
                      :replacement
                      (make-tool-call
                       :id (cadr-ai:tool-call-id call)
                       :name (cadr-ai:tool-call-name call)
                       :arguments
                       (cadr-ai::json-object)))))))))
           (host (make-test-extension-host (list bundle)))
           (agent
             (make-agent
              :provider :mock
              :model (mock-model)
              :tools (list tool)
              :extension-host host
              :stream-function
              (faux-stream '*responses* '*contexts*))))
      (agent-prompt agent "run")
      (is (= 0 executions))
      (let ((result
              (find-if
               (lambda (message)
                 (typep message 'tool-result-message))
               (agent-messages agent))))
        (is (cadr-ai:tool-result-message-is-error result))
        (is (search "Invalid arguments"
                    (text-result result)))))))

(test extension-tool-errors-become-results-and-the-agent-continues
  (let ((*notifications* nil)
        (*responses*
          (list
           (assistant
            (list
             (make-tool-call
              :id "explode-1"
              :name "explode"
              :arguments (cadr-ai::json-object)))
            :tool-use)
           (assistant
            (list (make-text-content :text "still-alive")))))
        (*contexts* nil))
    (declare
     (special *notifications* *responses* *contexts*))
    (let* ((bundle
             (make-test-extension-bundle
              "explode"
              (lambda ()
                (cadr-agent:define-tool
                 "explode"
                 :description "Signal an error"
                 :parameters (object-schema)
                 :handler
                 (lambda (call-id arguments context)
                   (declare
                    (ignore call-id arguments context))
                   (error "extension tool boom"))))))
           (host
             (make-test-extension-host
              (list bundle)
              :notifications '*notifications*))
           (agent
             (make-agent
              :provider :mock
              :model (mock-model)
              :extension-host host
              :stream-function
              (faux-stream '*responses* '*contexts*))))
      (let ((final
              (agent-prompt agent "run")))
        (is (string=
             "still-alive"
             (text-content-text
              (first
               (assistant-message-content final))))))
      (let ((result
              (find-if
               (lambda (message)
                 (typep message
                        'tool-result-message))
               (agent-messages agent))))
        (is (cadr-ai:tool-result-message-is-error result))
        (is (search "extension tool boom"
                    (text-result result)))))))

(test invalid-hook-results-are-transactional
  (let* ((*notifications* nil)
         (bundle
           (make-test-extension-bundle
            "transactional"
            (lambda ()
              (cadr-agent:define-event-hook
               :turn-start
               :handler
               (lambda (event context)
                 (declare (ignore event context))
                 (cadr-agent:make-extension-hook-result
                  :replacement
                  (cadr-ai:make-user-message
                   :content "must-not-commit")
                  :append-messages (list 42)))))))
         (host
           (make-test-extension-host
            (list bundle)
            :notifications '*notifications*))
         (original
           (cadr-ai:make-user-message
            :content "original")))
    (declare (special *notifications*))
    (multiple-value-bind
          (replacement appended blocked-p reason)
        (cadr-agent::run-extension-hooks
         host :turn-start :message original
         :turn-index 1)
      (declare (ignore blocked-p reason))
      (is (eq original replacement))
      (is (null appended)))
    (is (search "append-messages"
                (second
                 (first *notifications*))))))

(test turn-hooks-rewrite-and-append-before-session-persistence
  (let ((*responses*
          (list
           (assistant
            (list
             (make-text-content :text "original-assistant")))))
        (*contexts* nil))
    (declare (special *responses* *contexts*))
    (let* ((bundle
             (make-test-extension-bundle
              "turn-hooks"
              (lambda ()
                (cadr-agent:define-event-hook
                 :turn-start
                 :handler
                 (lambda (event context)
                   (declare (ignore context))
                   (when
                       (cadr-agent:extension-event-message event)
                     (cadr-agent:make-extension-hook-result
                      :replacement
                      (cadr-ai:make-user-message
                       :content "rewritten-user")
                      :append-messages
                      (list
                       (cadr-ai:make-user-message
                        :content "start-extra"))))))
                (cadr-agent:define-event-hook
                 :turn-end
                 :handler
                 (lambda (event context)
                   (declare (ignore event context))
                   (cadr-agent:make-extension-hook-result
                    :replacement
                    (assistant
                     (list
                      (make-text-content
                       :text "rewritten-assistant")))
                    :append-messages
                    (list
                     (cadr-ai:make-user-message
                      :content "end-extra"))))))))
           (host (make-test-extension-host (list bundle)))
           (agent
             (make-agent
              :provider :mock
              :model (mock-model)
              :extension-host host
              :stream-function
              (faux-stream '*responses* '*contexts*))))
      (agent-prompt agent "original-user")
      (is
       (equal
        '("rewritten-user" "start-extra"
          "rewritten-assistant" "end-extra")
        (loop
          for message in (agent-messages agent)
          collect
          (etypecase message
            (cadr-ai:user-message
             (cadr-ai:user-message-content message))
            (cadr-ai:assistant-message
             (text-content-text
              (first
               (assistant-message-content message))))))))
      (is
       (equal
        '("rewritten-user" "start-extra")
        (mapcar
         #'cadr-ai:user-message-content
         (cadr-ai:context-messages
          (first *contexts*))))))))

(test old-tool-closure-remains-valid-across-atomic-reload
  (flet ((bundle (id value)
           (make-test-extension-bundle
            id
            (lambda ()
              (cadr-agent:define-tool
               "versioned"
               :description value
               :parameters (object-schema)
               :handler
               (lambda (call-id arguments context)
                 (declare
                  (ignore call-id arguments context))
                 (values
                  (list
                   (make-text-content :text value))
                  nil)))))))
    (let* ((old-bundle (bundle "old-version" "old"))
           (host
             (make-test-extension-host
              (list old-bundle)))
           (old-tool
             (first
              (cadr-agent::extension-host-tools host)))
           (new-bundle (bundle "new-version" "new")))
      (cadr-agent::replace-extension-bundles
       host (list new-bundle))
      (multiple-value-bind (old-content old-details)
          (funcall
           (cadr-ai:tool-executor old-tool)
           "old-call"
           (cadr-ai::json-object))
        (declare (ignore old-details))
        (is (string= "old"
                     (text-content-text
                      (first old-content)))))
      (multiple-value-bind (new-content new-details)
          (funcall
           (cadr-ai:tool-executor
            (first
             (cadr-agent::extension-host-tools host)))
           "new-call"
           (cadr-ai::json-object))
        (declare (ignore new-details))
        (is (string= "new"
                     (text-content-text
                      (first new-content))))))))
