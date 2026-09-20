(in-package #:cadr-agent/tests)
(in-suite cadr-agent-suite)

(defparameter +wave3-extension-events+
  '(:project-trust
    :resources-discover
    :before-provider-request
    :before-provider-headers
    :after-provider-response
    :user-bash))

(test goal10-extension-event-set-is-refrozen-at-thirty-five
  (is (= 37
         (length
          cadr-agent::+extension-hook-events+)))
  (is (= 37
         (length
          (remove-duplicates
           cadr-agent::+extension-hook-events+))))
  (is (member
       :session-compact-failed
       cadr-agent::+extension-hook-events+))
  (is (member
       :ui-prompt-start
       cadr-agent::+extension-hook-events+))
  (is (member
       :ui-prompt-end
       cadr-agent::+extension-hook-events+))
  (is (member
       :tool-call-error
       cadr-agent::+extension-hook-events+))
  (dolist (event +wave3-extension-events+)
    (is (member
         event
         cadr-agent::+extension-hook-events+))))

(test wave3-additive-extension-registries-preserve-baseline-resolution
  (let* ((first
           (make-test-extension-bundle
            "first-additive"
            (lambda ()
              (cadr-agent::define-shortcut
               "ctrl+shift+x"
               :description "first shortcut"
               :handler (lambda (context)
                          (declare (ignore context))
                          :first))
              (cadr-agent::define-flag
               "plan" :description "first flag"
               :type :boolean :default t)
              (cadr-agent::define-message-renderer
               "status"
               :renderer (lambda (&rest values)
                           (declare (ignore values))
                           :first-message))
              (cadr-agent::define-entry-renderer
               "state"
               :renderer (lambda (&rest values)
                           (declare (ignore values))
                           :first-entry))
              (cadr-agent::define-tool-renderer
               "read"
               :call (lambda (&rest values)
                       (declare (ignore values))
                       :first-call)))))
         (second
           (make-test-extension-bundle
            "second-additive"
            (lambda ()
              (cadr-agent::define-shortcut
               "ctrl+shift+x"
               :description "second shortcut"
               :handler (lambda (context)
                          (declare (ignore context))
                          :second))
              (cadr-agent::define-flag
               "plan" :description "second flag"
               :type :boolean :default nil)
              (cadr-agent::define-message-renderer
               "status"
               :renderer (lambda (&rest values)
                           (declare (ignore values))
                           :second-message))
              (cadr-agent::define-tool-renderer
               "read"
               :result (lambda (&rest values)
                         (declare (ignore values))
                         :second-result)))))
         (host
           (make-test-extension-host
            (list first second)))
         (shortcuts
           (cadr-agent::extension-host-shortcuts host))
         (flags
           (cadr-agent::extension-host-flags host))
         (tool-renderer
           (cadr-agent::find-extension-tool-renderer
            host "read")))
    ;; Shortcuts follow the baseline last-registration-wins rule. Flags and
    ;; renderers follow first-extension precedence.
    (is (= 1 (length shortcuts)))
    (is (string=
         "second shortcut"
         (cadr-agent::extension-shortcut-definition-description
          (first shortcuts))))
    (is (= 1 (length flags)))
    (is (string=
         "first flag"
         (cadr-agent::extension-flag-definition-description
          (first flags))))
    (is (eq
         :first-message
         (funcall
          (cadr-agent::extension-renderer-definition-renderer
           (cadr-agent::find-extension-message-renderer
            host "status")))))
    (is (eq
         :first-entry
         (funcall
          (cadr-agent::extension-renderer-definition-renderer
           (cadr-agent::find-extension-entry-renderer
            host "state")))))
    (is (functionp
         (cadr-agent::extension-tool-renderer-definition-call
          tool-renderer)))
    (is (null
         (cadr-agent::extension-tool-renderer-definition-result
          tool-renderer)))
    (is (some
         (lambda (message)
           (search "Shortcut" message))
         (cadr-agent::extension-host-conflicts host)))))

(test goal9-markdown-transformers-chain-in-load-order-and-contain-errors
  (let ((contexts nil)
        (failures nil))
    (let* ((first
             (make-test-extension-bundle
              "markdown-a"
              (lambda ()
                (cadr-agent:define-markdown-transformer
                 (lambda (markdown context)
                   (push (copy-list context) contexts)
                   (substitute
                    #\² #\x markdown))))))
           (broken
             (make-test-extension-bundle
              "markdown-b"
              (lambda ()
                (cadr-agent:define-markdown-transformer
                 (lambda (markdown context)
                   (declare (ignore markdown context))
                   (error "broken transformer"))))))
           (last
             (make-test-extension-bundle
              "markdown-c"
              (lambda ()
                (cadr-agent:define-markdown-transformer
                 (lambda (markdown context)
                   (declare (ignore context))
                   (concatenate
                    'string markdown " done"))))))
           (host
             (make-test-extension-host
              (list first broken last)
              :notifications '*goal9-markdown-failures*)))
      (declare (special *goal9-markdown-failures*))
      (setf *goal9-markdown-failures* nil)
      (let* ((source "x")
             (context
               '(:message-type :assistant
                 :streaming-p t
                 :available-width 78))
             (result
               (cadr-agent::transform-extension-markdown
                host source context)))
        (is (string= "² done" result))
        (is (string= "x" source))
        (is (equal context
                   '(:message-type :assistant
                     :streaming-p t
                     :available-width 78)))
        (is (= 3
               (length
                (cadr-agent::extension-host-markdown-transformers
                 host))))
        (is (equal context (first contexts)))
        (setf failures *goal9-markdown-failures*)
        (is (= 1 (length failures)))
        (is (search "broken transformer"
                    (second (first failures))))))))

(test wave3-load-scope-api-survives-handlers-but-stales-on-reload
  (let ((captured nil)
        (sent nil)
        (executed nil)
        (active-tools '("read" "bash")))
    (let* ((host
             (cadr-agent::make-extension-host
              :cwd #P"/tmp/"
              :send-message-function
              (lambda (message &key trigger-turn-p deliver-as)
                (push
                 (list message trigger-turn-p deliver-as)
                 sent))
              :send-user-message-function
              (lambda (content &key deliver-as)
                (push (list content deliver-as) sent))
              :exec-function
              (lambda (command arguments
                       &key cwd environment timeout-ms)
                (push
                 (list command arguments cwd environment
                       timeout-ms)
                 executed)
                '(:stdout "ok" :stderr "" :exit-code 0))
              :get-active-tools-function
              (lambda () (copy-list active-tools))
              :set-active-tools-function
              (lambda (names)
                (setf active-tools (copy-list names)))))
           (bundle
             (cadr-agent::make-extension-bundle
              :id "api"
              :path "/tmp/api.lisp"
              :scope :project
              :rank 1
              :order 0)))
      (cadr-agent::call-with-extension-load
       host bundle
       (lambda ()
         (cadr-agent::define-flag
          "enabled" :type :boolean :default t)
         (setf captured
               (cadr-agent::current-extension-api))))
      (cadr-agent::replace-extension-bundles
       host (list bundle))
      (cadr-agent::extension-api-send-message
       captured "later"
       :trigger-turn-p t :deliver-as :follow-up)
      (cadr-agent::extension-api-send-user-message
       captured "user" :deliver-as :steer)
      (is (equal
           '(:stdout "ok" :stderr "" :exit-code 0)
           (cadr-agent::extension-api-exec
            captured "printf" '("ok")
            :cwd "/tmp" :environment '(("A" . "B"))
            :timeout-ms 250)))
      (is (eq t
              (cadr-agent::extension-api-get-flag
               captured "enabled")))
      (is (equal
           '("read" "bash")
           (cadr-agent::extension-api-get-active-tools
            captured)))
      (cadr-agent::extension-api-set-active-tools
       captured '("bash"))
      (is (equal '("bash") active-tools))
      (is (= 2 (length sent)))
      (is (= 1 (length executed)))
      (let ((replacement
              (make-test-extension-bundle
               "api"
               (lambda ())
               :path "/tmp/api.lisp")))
        (cadr-agent::replace-extension-bundles
         host (list replacement)))
      (signals cadr-agent:stale-extension-context
        (cadr-agent::extension-api-get-active-tools
         captured)))))

(test wave3-handler-context-idle-and-command-only-wait-remain-scoped
  (let ((command-context nil)
        (hook-context nil))
    (let* ((bundle
             (make-test-extension-bundle
              "idle"
              (lambda ()
                (cadr-agent:define-command
                 "wait"
                 :handler
                 (lambda (arguments context)
                   (declare (ignore arguments))
                   (setf command-context context)
                   (is
                    (cadr-agent::extension-context-idle-p
                     context))
                   (is
                    (typep
                     (cadr-agent::extension-command-context-wait-for-idle
                      context)
                     'cadr-agent:agent))))
                (cadr-agent:define-event-hook
                 :agent-start
                 :handler
                 (lambda (event context)
                   (declare (ignore event))
                   (setf hook-context context)
                   (signals cadr-agent:extension-execution-error
                     (cadr-agent::extension-command-context-wait-for-idle
                      context)))))))
           (host
             (make-test-extension-host
              (list bundle)))
           (agent
             (make-agent
              :provider :mock
              :model (mock-model)
              :extension-host host
              :auto-compact-p nil)))
      (declare (ignore agent))
      (is
       (cadr-agent::invoke-extension-command
        host "wait" ""))
      (cadr-agent::run-extension-lifecycle-hooks
       host :agent-start)
      (signals cadr-agent:stale-extension-context
        (cadr-agent::extension-context-idle-p
         command-context))
      (signals cadr-agent:stale-extension-context
        (cadr-agent::extension-context-idle-p
         hook-context)))))

(test wave3-additive-ui-surface-delegates-without-tui-core-changes
  (let ((calls nil))
    (let* ((bundle
             (make-test-extension-bundle
              "ui-additive"
              (lambda ()
                (cadr-agent:define-command
                 "ui"
                 :handler
                 (lambda (arguments context)
                   (declare (ignore arguments))
                   (cadr-agent::extension-context-custom
                    context (lambda () '("custom"))
                    :overlay-p t
                    :overlay-options '(:width 40))
                   (cadr-agent::extension-context-add-autocomplete-provider
                    context (lambda (&rest values)
                              (declare (ignore values))
                              nil))
                   (is (equal
                        '(:name "dark")
                        (cadr-agent::extension-context-theme
                         context)))
                   (is (= 2
                          (length
                           (cadr-agent::extension-context-all-themes
                            context))))
                   (is (equal
                        '(:name "light")
                        (cadr-agent::extension-context-get-theme
                         context "light")))
                   (is (equal
                        '(:success t)
                        (cadr-agent::extension-context-set-theme
                         context "light")))
                   (is
                    (cadr-agent::extension-context-tools-expanded-p
                     context))
                   (cadr-agent::extension-context-set-tools-expanded
                    context nil))))))
           (host
             (cadr-agent::make-extension-host
              :cwd #P"/tmp/"
              :ui-function
              (lambda (method arguments)
                (push (list method arguments) calls)
                (case method
                  (:theme '(:name "dark"))
                  (:all-themes
                   '((:name "dark") (:name "light")))
                  (:get-theme '(:name "light"))
                  (:set-theme '(:success t))
                  (:tools-expanded-p t)
                  (otherwise nil))))))
      (cadr-agent::replace-extension-bundles
       host (list bundle))
      (is
       (cadr-agent::invoke-extension-command
        host "ui" ""))
      (is (member :custom calls :key #'first))
      (is (member :add-autocomplete-provider
                  calls :key #'first))
      (is (member :set-tools-expanded
                  calls :key #'first)))))

(test wave3-tool-renderers-share-state-and-expose-fallback-slots
  (let* ((bundle
           (make-test-extension-bundle
            "render-state"
            (lambda ()
              (cadr-agent::define-tool-renderer
               "read"
               :call
               (lambda (arguments context)
                 (setf
                  (gethash
                   :token
                   (getf context :state))
                  (getf arguments :path))
                 (list
                  (format nil "call ~A"
                          (getf arguments :path))))
               :result
               (lambda (result options context)
                 (declare (ignore result options))
                 (list
                  (format
                   nil "result ~A"
                   (gethash
                    :token
                    (getf context :state))))))
              (cadr-agent::define-tool-renderer
               "write"
               :call
               (lambda (arguments context)
                 (declare (ignore arguments context))
                 '("write call"))))))
         (host
           (make-test-extension-host
            (list bundle)))
         (state (make-hash-table))
         (call-context
           (list :state state
                 :tool-call-id "tool-1"
                 :cwd "/tmp"))
         (result-context
           (list :state state
                 :tool-call-id "tool-1"
                 :cwd "/tmp")))
    (multiple-value-bind (rendered handled-p)
        (cadr-agent::render-extension-tool-call
         host "read" '(:path "notes.txt")
         call-context)
      (is (not (null handled-p)))
      (is (equal '("call notes.txt") rendered)))
    (multiple-value-bind (rendered handled-p)
        (cadr-agent::render-extension-tool-result
         host "read" '(:content "ok")
         '(:expanded-p t :partial-p nil)
         result-context)
      (is (not (null handled-p)))
      (is (equal '("result notes.txt") rendered)))
    (multiple-value-bind (rendered handled-p)
        (cadr-agent::render-extension-tool-result
         host "write" '(:content "ok") nil
         (list :state (make-hash-table)))
      (is (null rendered))
      (is (null handled-p)))
    (multiple-value-bind (rendered handled-p)
        (cadr-agent::render-extension-tool-call
         host "missing" nil
         (list :state (make-hash-table)))
      (is (null rendered))
      (is (null handled-p)))))

(test wave3-native-provider-registration-is-additive-and-reload-aware
  (let* ((provider
           (cadr-ai:make-runtime-provider
            :id :native
            :name "Native"
            :api-key-auth-p t))
         (bundle
           (make-test-extension-bundle
            "native"
            (lambda ()
              (cadr-agent:define-native-provider
               provider))))
         (host
           (make-test-extension-host
            (list bundle))))
    (is (equal
         '(:native)
         (mapcar
          #'cadr-ai:runtime-provider-id
          (cadr-agent::extension-host-native-providers
           host))))
    (cadr-agent::replace-extension-bundles host nil)
    (is (null
         (cadr-agent::extension-host-native-providers
          host)))))

(test project-trust-uses-first-decision
  (let ((calls nil))
    (let* ((bundle
             (make-test-extension-bundle
              "trust"
              (lambda ()
                (cadr-agent:define-event-hook
                 :project-trust
                 :handler
                 (lambda (event context)
                   (declare (ignore event context))
                   (push :undecided calls)
                   '(:trusted :undecided)))
                (cadr-agent:define-event-hook
                 :project-trust
                 :handler
                 (lambda (event context)
                   (declare (ignore event context))
                   (push :yes calls)
                   '(:trusted :yes
                     :remember-p t)))
                (cadr-agent:define-event-hook
                 :project-trust
                 :handler
                 (lambda (event context)
                   (declare (ignore event context))
                   (push :late calls)
                   '(:trusted :no))))))
           (host
             (make-test-extension-host
              (list bundle))))
      (is
       (equal
        '(:trusted :yes :remember-p t)
        (cadr-agent::run-extension-lifecycle-hooks
         host :project-trust
         :payload
         '(:cwd "/project"))))
      (is (equal
           '(:yes :undecided)
           calls)))))

(test resources-discover-aggregates-valid-paths
  (let* ((bundle
           (make-test-extension-bundle
            "resources"
            (lambda ()
              (cadr-agent:define-event-hook
               :resources-discover
               :handler
               (lambda (event context)
                 (declare (ignore event context))
                 '(:skill-paths
                   ("/one/skills")
                   :prompt-paths
                   ("/one/prompts"))))
              (cadr-agent:define-event-hook
               :resources-discover
               :handler
               (lambda (event context)
                 (declare (ignore event context))
                 '(:skill-paths
                   ("/two/skills")
                   :theme-paths
                   ("/two/themes")))))))
         (host
           (make-test-extension-host
            (list bundle)))
         (result
           (cadr-agent::run-extension-lifecycle-hooks
            host :resources-discover
            :payload
            '(:cwd "/project"
              :reason :reload))))
    (is (equal
         '("/one/skills" "/two/skills")
         (getf result :skill-paths)))
    (is (equal
         '("/one/prompts")
         (getf result :prompt-paths)))
    (is (equal
         '("/two/themes")
         (getf result :theme-paths)))
    (is (equal
         "extension:resources.lisp"
         (getf
          (first (getf result :extension-resource-sources))
          :source)))
    (is (equal
         "temporary"
         (getf
          (first (getf result :extension-resource-sources))
          :scope)))
    (is (string=
         "extension:foo"
         (cadr-agent::extension-resource-source-label
          "/tmp/foo.ts")))
    (is (string=
         "extension:inline"
         (cadr-agent::extension-resource-source-label
          "<inline>")))))

(test provider-hooks-chain-mutate-and-observe
  (let ((response-seen nil))
    (let* ((bundle
             (make-test-extension-bundle
              "provider"
              (lambda ()
                (cadr-agent:define-event-hook
                 :before-provider-request
                 :handler
                 (lambda (event context)
                   (declare (ignore context))
                   (append
                    (getf
                     (cadr-agent:extension-event-payload
                      event)
                     :payload)
                    '(:trace "one"))))
                (cadr-agent:define-event-hook
                 :before-provider-request
                 :handler
                 (lambda (event context)
                   (declare (ignore context))
                   (is
                    (string=
                     "one"
                     (getf
                      (getf
                       (cadr-agent:extension-event-payload
                        event)
                       :payload)
                      :trace)))
                   (cadr-agent:make-provider-request-replacement
                    nil)))
                (cadr-agent:define-event-hook
                 :before-provider-headers
                 :handler
                 (lambda (event context)
                   (declare (ignore context))
                   (setf
                    (gethash
                     "x-trace"
                     (getf
                      (cadr-agent:extension-event-payload
                       event)
                      :headers))
                    "value")
                   nil))
                (cadr-agent:define-event-hook
                 :after-provider-response
                 :handler
                 (lambda (event context)
                   (declare (ignore context))
                   (setf
                    response-seen
                    (cadr-agent:extension-event-payload
                     event))
                   nil)))))
           (host
             (make-test-extension-host
              (list bundle)))
           (headers
             (make-hash-table
              :test #'equal)))
      (is (null
           (cadr-agent::run-extension-lifecycle-hooks
            host :before-provider-request
            :payload
            '(:payload (:original t)))))
      (is (eq
           headers
           (cadr-agent::run-extension-lifecycle-hooks
            host :before-provider-headers
            :payload
            (list :headers headers))))
      (is (string=
           "value"
           (gethash "x-trace" headers)))
      (cadr-agent::run-extension-lifecycle-hooks
       host :after-provider-response
       :payload
       '(:status 200
         :headers
         (("content-type"
           . "application/json"))))
      (is (= 200
             (getf response-seen
                   :status))))))

(test user-bash-returns-first-interception
  (let ((late-called-p nil))
    (let* ((bundle
             (make-test-extension-bundle
              "bash"
              (lambda ()
                (cadr-agent:define-event-hook
                 :user-bash
                 :handler
                 (lambda (event context)
                   (declare (ignore event context))
                   nil))
                (cadr-agent:define-event-hook
                 :user-bash
                 :handler
                 (lambda (event context)
                   (declare (ignore event context))
                   '(:result
                     (:output "handled"
                      :exit-code 0))))
                (cadr-agent:define-event-hook
                 :user-bash
                 :handler
                 (lambda (event context)
                   (declare (ignore event context))
                   (setf late-called-p t)
                   nil)))))
           (host
             (make-test-extension-host
              (list bundle))))
      (is (equal
           '(:result
             (:output "handled"
              :exit-code 0))
           (cadr-agent::run-extension-lifecycle-hooks
            host :user-bash
            :payload
            '(:command "pwd"
              :exclude-from-context-p nil
              :cwd "/project"))))
      (is (not late-called-p)))))

(test g22-ui-prompt-events-wrap-the-outermost-extension-prompt
  (let* ((seen nil)
         (bundle
           (make-test-extension-bundle
            "ui-prompt-events"
            (lambda ()
              (cadr-agent:define-event-hook
               :ui-prompt-start
               :handler
               (lambda (event context)
                 (declare (ignore context))
                 (push
                  (list :start
                        (getf
                         (cadr-agent:extension-event-payload event)
                         :kind))
                  seen)
                 nil))
              (cadr-agent:define-event-hook
               :ui-prompt-end
               :handler
               (lambda (event context)
                 (declare (ignore context))
                 (push
                  (list :end
                        (getf
                         (cadr-agent:extension-event-payload event)
                         :kind))
                  seen)
                 nil)))))
         (host (make-test-extension-host (list bundle))))
    (is
     (eq 'ok
         (cadr-agent::call-with-extension-ui-prompt
          host :select "Outer"
          (lambda ()
            (cadr-agent::call-with-extension-ui-prompt
             host :confirm "Inner"
             (lambda () 'ok))))))
    (is (equal '((:end :select) (:start :select)) seen))))

;;; Goal 24 — pi@ecac0a9c4 packages/coding-agent/test/extensions-runner.test.ts
;;; describe("event subscriptions"): pi.on returns unsubscribe; dispatch
;;; snapshots the handler list so add/remove applies on the next emit.

(test goal24-hook-unsubscribe-self-removal-keeps-neighbors
  (let ((calls nil)
        (stop-a nil))
    (let* ((bundle
             (make-test-extension-bundle
              "goal24-unsub-self"
              (lambda ()
                (setf stop-a
                      (cadr-agent:define-event-hook
                       :agent-end
                       :handler
                       (lambda (event context)
                         (declare (ignore event context))
                         (push :a calls)
                         (funcall stop-a)
                         nil)))
                (cadr-agent:define-event-hook
                 :agent-end
                 :handler
                 (lambda (event context)
                   (declare (ignore event context))
                   (push :b calls)
                   nil)))))
           (host (make-test-extension-host (list bundle))))
      (is (functionp stop-a))
      (cadr-agent::run-extension-lifecycle-hooks
       host :agent-end :payload '(:messages ()))
      (is (equal '(:b :a) calls))
      (cadr-agent::run-extension-lifecycle-hooks
       host :agent-end :payload '(:messages ()))
      (is (equal '(:b :b :a) calls))
      (funcall stop-a)
      (funcall stop-a)
      (cadr-agent::run-extension-lifecycle-hooks
       host :agent-end :payload '(:messages ()))
      (is (equal '(:b :b :b :a) calls)))))

(test goal24-hook-unsubscribe-defers-removal-until-next-dispatch
  (let ((calls nil)
        (stop-b nil))
    (let* ((bundle
             (make-test-extension-bundle
              "goal24-unsub-defer"
              (lambda ()
                (cadr-agent:define-event-hook
                 :agent-end
                 :handler
                 (lambda (event context)
                   (declare (ignore event context))
                   (push :a calls)
                   (funcall stop-b)
                   nil))
                (setf stop-b
                      (cadr-agent:define-event-hook
                       :agent-end
                       :handler
                       (lambda (event context)
                         (declare (ignore event context))
                         (push :b calls)
                         nil)))
                (cadr-agent:define-event-hook
                 :agent-end
                 :handler
                 (lambda (event context)
                   (declare (ignore event context))
                   (push :c calls)
                   nil)))))
           (host (make-test-extension-host (list bundle))))
      (cadr-agent::run-extension-lifecycle-hooks
       host :agent-end :payload '(:messages ()))
      (is (equal '(:c :b :a) calls))
      (cadr-agent::run-extension-lifecycle-hooks
       host :agent-end :payload '(:messages ()))
      (is (equal '(:c :a :c :b :a) calls)))))

(test goal24-hook-register-during-dispatch-runs-next-time
  (let ((calls nil))
    (let* ((bundle
             (make-test-extension-bundle
              "goal24-register-during"
              (lambda ()
                (cadr-agent:define-event-hook
                 :agent-end
                 :handler
                 (lambda (event context)
                   (declare (ignore event context))
                   (push :a calls)
                   (cadr-agent:define-event-hook
                    :agent-end
                    :handler
                    (lambda (event context)
                      (declare (ignore event context))
                      (push :c calls)
                      nil))
                   nil))
                (cadr-agent:define-event-hook
                 :agent-end
                 :handler
                 (lambda (event context)
                   (declare (ignore event context))
                   (push :b calls)
                   nil)))))
           (host (make-test-extension-host (list bundle))))
      (cadr-agent::run-extension-lifecycle-hooks
       host :agent-end :payload '(:messages ()))
      (is (equal '(:b :a) calls))
      (cadr-agent::run-extension-lifecycle-hooks
       host :agent-end :payload '(:messages ()))
      (is (equal '(:c :b :a :b :a) calls)))))

(test goal24-hook-unsubscribe-duplicate-registrations-independently
  (let ((calls nil)
        (stop-first nil)
        (stop-b nil)
        (stop-second nil))
    (let* ((shared
             (lambda (event context)
               (declare (ignore event context))
               (push :shared calls)
               nil))
           (bundle
             (make-test-extension-bundle
              "goal24-unsub-dup"
              (lambda ()
                (setf stop-first
                      (cadr-agent:define-event-hook
                       :agent-end :handler shared))
                (setf stop-b
                      (cadr-agent:define-event-hook
                       :agent-end
                       :handler
                       (lambda (event context)
                         (declare (ignore event context))
                         (push :b calls)
                         nil)))
                (setf stop-second
                      (cadr-agent:define-event-hook
                       :agent-end :handler shared)))))
           (host (make-test-extension-host (list bundle))))
      (funcall stop-second)
      (funcall stop-second)
      (cadr-agent::run-extension-lifecycle-hooks
       host :agent-end :payload '(:messages ()))
      (is (equal '(:b :shared) calls))
      (funcall stop-first)
      (cadr-agent::run-extension-lifecycle-hooks
       host :agent-end :payload '(:messages ()))
      (is (equal '(:b :b :shared) calls))
      (funcall stop-b)
      (is
       (null
        (gethash
         :agent-end
         (cadr-agent::extension-snapshot-hooks
          (cadr-agent::extension-host-current-snapshot
           host))))))))