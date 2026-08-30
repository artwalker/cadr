(in-package #:cadr-agent/tests)
(in-suite cadr-agent-suite)

(defun goal12-test-context (host bundle &optional (kind :command))
  (cadr-agent::%make-extension-context
   :host host :bundle bundle :kind kind
   :source-path (cadr-agent::extension-bundle-path bundle)))

(test goal12-extension-context-exposes-approved-host-state-without-changing-defaults
  (let* ((bundle (make-test-extension-bundle "goal12-context" (lambda ())))
         (calls nil)
         (host
           (cadr-agent::make-extension-host
            :cwd #P"/tmp/" :mode :tui
            :action-function
            (lambda (action arguments)
              (push (list action arguments) calls)
              (case action
                (:model :model)
                (:scoped-models '(:scoped))
                (:thinking-level :high)
                (:context-usage '(:tokens 12 :context-window 100 :percent 12d0))
                (:system-prompt "prompt")
                (:system-prompt-options '(:selected-tools ("read")))
                (:has-pending-messages-p t)
                (otherwise :ok)))))
         (context (goal12-test-context host bundle)))
    (is (cadr-agent:extension-context-has-ui-p context))
    (is (eq :model (cadr-agent:extension-context-model context)))
    (is (equal '(:scoped) (cadr-agent:extension-context-scoped-models context)))
    (is (eq :high (cadr-agent:extension-context-thinking-level context)))
    (is (equal '(:tokens 12 :context-window 100 :percent 12d0)
               (cadr-agent:extension-context-context-usage context)))
    (is (string= "prompt" (cadr-agent:extension-context-system-prompt context)))
    (is (equal '(:selected-tools ("read"))
               (cadr-agent:extension-command-context-system-prompt-options context)))
    (is (cadr-agent:extension-context-has-pending-messages-p context))
    (is (eq :ok (cadr-agent:extension-context-abort context)))
    (is (eq :ok (cadr-agent:extension-context-shutdown context)))
    (is (eq :ok (cadr-agent:extension-command-context-new-session
                 context :parent-session "parent")))
    (let* ((print-host (cadr-agent::make-extension-host :mode :print))
           (print-context (goal12-test-context print-host bundle :hook)))
      (is (not (cadr-agent:extension-context-has-ui-p print-context))))
    (is (find :abort calls :key #'first))
    (is (find :shutdown calls :key #'first))
    (is (find :new-session calls :key #'first))))

(test goal12-ui-composition-contract-is-additive-and-forwards-exact-values
  (let* ((bundle (make-test-extension-bundle "goal12-ui" (lambda ())))
         (calls nil)
         (factory (lambda (&rest values) (declare (ignore values)) :component))
         (host
           (cadr-agent::make-extension-host
            :mode :tui
            :ui-function
            (lambda (method arguments)
              (push (list method arguments) calls)
              (case method
                (:get-editor-component factory)
                (:get-editor-text "draft")
                (:theme '(:name "dark"))
                (otherwise :ok)))))
         (context (goal12-test-context host bundle)))
    (is (eq :ok (cadr-agent:extension-context-set-header context factory)))
    (is (eq :ok (cadr-agent:extension-context-set-footer context factory)))
    (is (eq :ok (cadr-agent:extension-context-set-editor-component context factory)))
    (is (eq factory (cadr-agent:extension-context-get-editor-component context)))
    (is (eq :ok (cadr-agent:extension-context-set-working-visible context nil)))
    (is (eq :ok (cadr-agent:extension-context-set-working-message context "Indexing")))
    (is (eq :ok (cadr-agent:extension-context-set-working-indicator
                 context :frames '("a" "b") :interval-ms 80)))
    (is (eq :ok (cadr-agent:extension-context-set-hidden-thinking-label
                 context "Reasoning")))
    (is (eq :ok (cadr-agent:extension-context-paste-to-editor context "paste")))
    (is (string= "draft" (cadr-agent:extension-context-get-editor-text context)))
    (is (eq :ok
            (cadr-agent:extension-context-custom-component
             context factory :overlay-p t
             :overlay-options '(:width 42)
             :on-handle (lambda (handle) (declare (ignore handle))))))
    (dolist (method '(:set-header :set-footer :set-editor-component
                      :set-working-visible :set-working-message
                      :set-working-indicator :set-hidden-thinking-label
                      :paste-to-editor :custom-component))
      (is (find method calls :key #'first)))))

(test goal12-extension-event-bus-is-host-scoped-and-prunes-retired-bundles
  (let ((seen nil))
    (let* ((first (cadr-agent::make-extension-bundle
                   :id "bus-a" :path "/tmp/bus-a.lisp"))
           (second (cadr-agent::make-extension-bundle
                    :id "bus-b" :path "/tmp/bus-b.lisp"))
           (host (cadr-agent::make-extension-host))
           (api
             (cadr-agent::%make-extension-api
              :host host :bundle second :attachment-generation 0)))
      (cadr-agent::call-with-extension-load
       host first
       (lambda ()
         (cadr-agent:extension-api-events-on
          (cadr-agent:current-extension-api)
          "topic"
          (lambda (payload) (push payload seen)))))
      (cadr-agent::replace-extension-bundles host (list first second))
      (cadr-agent:extension-api-events-emit api "topic" '(:one))
      (is (equal '((:one)) seen))
      (cadr-agent::replace-extension-bundles host (list second))
      (cadr-agent:extension-api-events-emit api "topic" '(:two))
      (is (equal '((:one)) seen)))))

(test goal12-extension-tool-names-accept-baseline-case-sensitive-identifiers
  (let ((bundle
          (make-test-extension-bundle
           "case-sensitive-tool"
           (lambda ()
             (cadr-agent:define-rich-tool
              "Calculator"
              :label "Calculator"
              :description "Evaluate a simple expression"
              :parameters (object-schema)
              :handler
              (lambda (call-id arguments signal on-update context)
                (declare (ignore call-id arguments signal on-update context))
                (values "42" nil)))))))
    (is (string=
         "Calculator"
         (cadr-agent::extension-tool-definition-name
          (first
           (cadr-agent::extension-bundle-tools bundle)))))))

(test goal12-rich-tool-metadata-is-additive-and-legacy-macro-lambda-list-is-frozen
  (let* ((schema (object-schema))
         (bundle
           (make-test-extension-bundle
            "rich-tool"
            (lambda ()
              (cadr-agent:define-rich-tool
               "rich" :label "Rich"
               :description "description"
               :prompt-snippet "rich: use it"
               :prompt-guidelines '("Do the rich thing")
               :parameters schema
               :constrained-sampling '(:grammar "json")
               :render-shell :self
               :prepare-arguments #'identity
               :handler (lambda (&rest values)
                          (declare (ignore values))
                          (values nil nil t))))))
         (definition (first (cadr-agent::extension-bundle-tools bundle))))
    (is (string= "Rich" (cadr-agent::extension-tool-definition-label definition)))
    (is (string= "rich: use it"
                 (cadr-agent::extension-tool-definition-prompt-snippet definition)))
    (is (equal '("Do the rich thing")
               (cadr-agent::extension-tool-definition-prompt-guidelines definition)))
    (is (eq :self (cadr-agent::extension-tool-definition-render-shell definition)))
    (is (functionp (cadr-agent::extension-tool-definition-prepare-arguments definition)))
    (labels ((shape (value)
               (cond
                 ((symbolp value) (symbol-name value))
                 ((consp value) (mapcar #'shape value))
                 (t value))))
      (is (equal
           '("NAME" "&KEY" "DESCRIPTION" "PARAMETERS"
             ("EXECUTION-MODE" "PARALLEL") "HANDLER")
           (shape
            (sb-introspect:function-lambda-list
             (macro-function 'cadr-agent:define-tool))))))))

(test goal12-component-renderers-add-theme-without-changing-legacy-callbacks
  (let ((legacy-arguments nil)
        (message-arguments nil)
        (entry-arguments nil))
    (let* ((bundle
             (make-test-extension-bundle
              "component-renderers"
              (lambda ()
                (cadr-agent:define-message-renderer
                 "legacy"
                 :renderer
                 (lambda (&rest arguments)
                   (setf legacy-arguments arguments)
                   '("legacy")))
                (cadr-agent:define-component-message-renderer
                 "status"
                 :renderer
                 (lambda (&rest arguments)
                   (setf message-arguments arguments)
                   :message-component))
                (cadr-agent:define-component-entry-renderer
                 "card"
                 :renderer
                 (lambda (&rest arguments)
                   (setf entry-arguments arguments)
                   :entry-component)))))
           (host (make-test-extension-host (list bundle)))
           (theme '(:fg :function)))
      (multiple-value-bind (value handled-p)
          (cadr-agent::render-extension-message
           host "legacy" '(:content "old") '(:expanded-p nil) theme)
        (is (not (null handled-p)))
        (is (equal '("legacy") value)))
      (multiple-value-bind (value handled-p)
          (cadr-agent::render-extension-message
           host "status" '(:content "new") '(:output-pad 1) theme)
        (is (not (null handled-p)))
        (is (eq :message-component value)))
      (multiple-value-bind (value handled-p)
          (cadr-agent::render-extension-entry
           host "card" '(:data (:ok t)) '(:expanded-p t) theme)
        (is (not (null handled-p)))
        (is (eq :entry-component value)))
      (is (= 2 (length legacy-arguments)))
      (is (= 3 (length message-arguments)))
      (is (= 3 (length entry-arguments)))
      (is (eq theme (third message-arguments)))
      (is (eq theme (third entry-arguments)))
      (labels ((shape (value)
                 (cond
                   ((symbolp value) (symbol-name value))
                   ((consp value) (mapcar #'shape value))
                   (t value))))
        (is (equal
             '("CUSTOM-TYPE" "&KEY" "RENDERER")
             (shape
              (sb-introspect:function-lambda-list
               (macro-function 'cadr-agent:define-message-renderer)))))))))

(test goal12-cancellation-signal-composes-local-and-host-aborts
  (let ((host-aborted-p nil)
        (abort-count 0))
    (let ((signal
            (cadr-agent:make-extension-cancellation-signal
             :aborted-function (lambda () host-aborted-p)
             :abort-function (lambda () (incf abort-count)))))
      (is (not (cadr-agent:extension-cancellation-aborted-p signal)))
      (setf host-aborted-p t)
      (is (cadr-agent:extension-cancellation-aborted-p signal))
      (setf host-aborted-p nil)
      (cadr-agent:abort-extension-cancellation-signal signal)
      (is (cadr-agent:extension-cancellation-aborted-p signal))
      (is (= 1 abort-count)))))

(test goal12-tool-after-hook-can-override-terminate-without-changing-replacement
  (let* ((result
           (cadr-ai:make-tool-result-message
            :tool-call-id "call" :tool-name "tool"
            :content (list (cadr-ai:make-text-content :text "ok"))))
         (bundle
           (make-test-extension-bundle
            "terminate-hook"
            (lambda ()
              (cadr-agent:define-event-hook
               :tool-call-after
               :handler
               (lambda (event context)
                 (declare (ignore event context))
                 (cadr-agent:make-extension-hook-result
                  :terminate-p t))))))
         (host (make-test-extension-host (list bundle))))
    (multiple-value-bind
          (replacement appended blocked reason terminate supplied-p)
        (cadr-agent::run-extension-hooks
         host :tool-call-after :tool-result result)
      (declare (ignore appended blocked reason))
      (is (eq result replacement))
      (is (not (null terminate)))
      (is (not (null supplied-p))))))

(test goal12-tool-before-hook-terminate-applies-only-on-block
  ;; pi@b79e4cc83 extensions/types.ts:1075-1079 + agent-loop.ts:637-640 —
  ;; a before hook may set terminate; it marks the blocked result and is
  ;; ignored without a block.
  (let* ((call
           (cadr-ai:make-tool-call
            :id "call" :name "tool"
            :arguments (make-hash-table :test #'equal)))
         (blocked-bundle
           (make-test-extension-bundle
            "terminate-before-block"
            (lambda ()
              (cadr-agent:define-event-hook
               :tool-call-before
               :handler
               (lambda (event context)
                 (declare (ignore event context))
                 (cadr-agent:make-extension-hook-result
                  :block-p t
                  :reason "policy"
                  :terminate-p t))))))
         (plain-bundle
           (make-test-extension-bundle
            "terminate-before-plain"
            (lambda ()
              (cadr-agent:define-event-hook
               :tool-call-before
               :handler
               (lambda (event context)
                 (declare (ignore event context))
                 (cadr-agent:make-extension-hook-result
                  :terminate-p t)))))))
    (let ((host
            (make-test-extension-host (list blocked-bundle))))
      (multiple-value-bind
            (replacement appended blocked reason terminate supplied-p)
          (cadr-agent::run-extension-hooks
           host :tool-call-before :tool-call call)
        (declare (ignore appended))
        (is (not (null replacement)))
        (is (not (null blocked)))
        (is (string= "policy" reason))
        (is (not (null terminate)))
        (is (not (null supplied-p))))
      (let* ((agent
               (cadr-agent:make-agent
                :provider :mock :model nil
                :extension-host host))
             (outcome
               (cadr-agent::prepare-tool-execution
                agent call :turn-index 0)))
        (is (typep outcome 'cadr-agent::tool-outcome))
        (is (cadr-agent::tool-outcome-terminate-p outcome))))
    ;; terminate without a block is accepted but not applied.
    (let ((host
            (make-test-extension-host (list plain-bundle))))
      (multiple-value-bind
            (replacement appended blocked reason terminate supplied-p)
          (cadr-agent::run-extension-hooks
           host :tool-call-before :tool-call call)
        (declare (ignore appended reason))
        (is (not (null replacement)))
        (is (null blocked))
        (is (not (null terminate)))
        (is (not (null supplied-p)))))))

(test goal12-extension-http-request-is-session-local-copied-and-stale-safe
  (let* ((bundle
           (cadr-agent::make-extension-bundle
            :id "http" :path "/tmp/http.lisp"))
         (seen nil)
         (host
           (cadr-agent::make-extension-host
            :http-request-function
            (lambda (url &key method headers body timeout-ms signal)
              (setf seen
                    (list url method headers body timeout-ms signal))
              (list
               :status 201
               :headers '(("content-type" . "application/json"))
               :body
               (make-array 2 :element-type '(unsigned-byte 8)
                           :initial-contents '(111 107))))))
         (api
           (cadr-agent::%make-extension-api
            :host host :bundle bundle :attachment-generation 0))
         (headers (list (cons "authorization" "Bearer secret")))
         (body
           (make-array 3 :element-type '(unsigned-byte 8)
                       :initial-contents '(1 2 3)))
         (signal
           (cadr-agent:make-extension-cancellation-signal))
         (result
           (progn
             (cadr-agent::replace-extension-bundles host (list bundle))
             (cadr-agent:extension-api-http-request
              api "https://example.invalid/token"
              :method :post :headers headers :body body
              :timeout-ms 250 :signal signal))))
    (setf (cdr (first headers)) "mutated"
          (aref body 0) 9)
    (is (= 201 (getf result :status)))
    (is (equal '(("content-type" . "application/json"))
               (getf result :headers)))
    (is (equalp #(111 107) (getf result :body)))
    (is (string= "Bearer secret"
                 (cdr (first (third seen)))))
    (is (= 1 (aref (fourth seen) 0)))
    (is (eq signal (sixth seen)))
    (setf (cadr-agent::extension-host-attachment-generation host) 1)
    (signals cadr-agent:stale-extension-context
      (cadr-agent:extension-api-http-request
       api "https://example.invalid"))))

(test goal12-extension-http-request-isolated-across-concurrent-sessions
  (let ((entered (sb-thread:make-semaphore :count 0))
        (release (sb-thread:make-semaphore :count 0))
        (results (make-array 2 :initial-element nil)))
    (labels
        ((make-session-api (id status byte)
           (let* ((bundle
                    (cadr-agent::make-extension-bundle
                     :id id :path (format nil "/tmp/~A.lisp" id)))
                  (host
                    (cadr-agent::make-extension-host
                     :http-request-function
                     (lambda (url &key method headers body timeout-ms signal)
                       (declare
                        (ignore method headers body timeout-ms signal))
                       (sb-thread:signal-semaphore entered)
                       (sb-thread:wait-on-semaphore release)
                       (list
                        :status status
                        :headers (list (cons "x-session" id))
                        :body
                        (make-array
                         1 :element-type '(unsigned-byte 8)
                         :initial-element
                         (if (search id url) byte 0))))))
                  (api
                    (cadr-agent::%make-extension-api
                     :host host :bundle bundle
                     :attachment-generation 0)))
             (cadr-agent::replace-extension-bundles host (list bundle))
             api)))
      (let* ((first (make-session-api "first" 201 1))
             (second (make-session-api "second" 202 2))
             (threads
               (list
                (sb-thread:make-thread
                 (lambda ()
                   (setf (aref results 0)
                         (cadr-agent:extension-api-http-request
                          first "https://first.invalid/token")))
                 :name "goal12-http-session-first")
                (sb-thread:make-thread
                 (lambda ()
                   (setf (aref results 1)
                         (cadr-agent:extension-api-http-request
                          second "https://second.invalid/token")))
                 :name "goal12-http-session-second"))))
        (loop repeat 2 do
          (sb-thread:wait-on-semaphore entered))
        (sb-thread:signal-semaphore release 2)
        (dolist (thread threads)
          (sb-thread:join-thread thread))
        (is (= 201 (getf (aref results 0) :status)))
        (is (= 202 (getf (aref results 1) :status)))
        (is (equalp #(1) (getf (aref results 0) :body)))
        (is (equalp #(2) (getf (aref results 1) :body)))
        (is (string= "first"
                     (cdr (first (getf (aref results 0) :headers)))))
        (is (string= "second"
                     (cdr (first (getf (aref results 1) :headers)))))))))
