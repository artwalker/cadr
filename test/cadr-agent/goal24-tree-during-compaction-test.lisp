(in-package #:cadr-agent/tests)
(in-suite cadr-agent-suite)

(defparameter +goal24-tree-busy-message+
  "Wait for the current response to finish before navigating the session tree.")

(defparameter +goal24-tree-compacting-message+
  "Wait for the current compaction or tree navigation to finish before navigating the session tree.")

(defun goal24-navigate-error-message (thunk)
  (handler-case
      (progn
        (funcall thunk)
        nil)
    (cadr-agent::agent-busy-error (condition)
      (cadr-ai:cadr-error-message condition))))

(test goal24-navigate-rejects-during-compaction
  ;; Baseline #9178 / #9179: navigateTree during manual compaction must
  ;; throw before the leaf can change; compaction still parents the
  ;; original leaf.
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let* ((started (sb-thread:make-semaphore :count 0))
           (release (sb-thread:make-semaphore :count 0))
           (bundle
             (make-test-extension-bundle
              "goal24-block-compact"
              (lambda ()
                (cadr-agent:define-event-hook
                 :session-before-compact
                 :handler
                 (lambda (event context)
                   (declare (ignore context))
                   (let ((prep
                           (getf
                            (cadr-agent:extension-event-payload event)
                            :preparation)))
                     (sb-thread:signal-semaphore started)
                     (sb-thread:wait-on-semaphore release :timeout 10)
                     (list
                      :compaction
                      (list
                       :summary "summary"
                       :first-kept-entry-id
                       (getf prep :first-kept-entry-id)
                       :tokens-before
                       (getf prep :tokens-before)
                       :details nil))))))))
           (host (make-test-extension-host (list bundle)))
           (session
             (cadr-agent:create-session
              :directory sessions :cwd cwd
              :id "goal24-nav-during-compact"))
           (navigation-target
             (progn
               (cadr-agent:session-append-message
                session
                (cadr-ai:make-user-message :content "first user"))
               (cadr-agent:session-append-message
                session
                (assistant
                 (list (make-text-content :text "first assistant"))))))
           (_second-user
             (cadr-agent:session-append-message
              session
              (cadr-ai:make-user-message :content "second user")))
           (original-leaf
             (cadr-agent:session-append-message
              session
              (assistant
               (list
                (make-text-content :text "second assistant")))))
           (agent
             (cadr-agent:make-agent
              :provider :mock
              :model (compaction-test-model)
              :session session
              :extension-host host
              :compaction-keep-recent-tokens 1
              :auto-compact-p nil
              :stream-function
              (lambda (&rest arguments)
                (declare (ignore arguments))
                (error "compaction must use extension summary")))))
      (declare (ignore _second-user))
      (let ((compact-thread
              (sb-thread:make-thread
               (lambda ()
                 (cadr-agent:compact-agent agent :force-p t))
               :name "goal24-compact")))
        (sb-thread:wait-on-semaphore started :timeout 5)
        (is-true (cadr-agent:agent-compacting-p agent))
        (is
         (string=
          +goal24-tree-compacting-message+
          (goal24-navigate-error-message
           (lambda ()
             (cadr-agent:agent-navigate-tree
              agent navigation-target
              :summarize-p nil)))))
        (is
         (string=
          original-leaf
          (cadr-agent:session-leaf-id session)))
        (sb-thread:signal-semaphore release)
        (sb-thread:join-thread compact-thread :timeout 10))
      (is-false (cadr-agent:agent-compacting-p agent))
      (let ((entry
              (car (last (cadr-agent:session-entries session)))))
        (is (eq :compaction (cadr-agent:session-entry-type entry)))
        (is
         (string=
          original-leaf
          (cadr-agent:session-entry-parent-id entry)))))))

(test goal24-navigate-rejects-concurrent-tree-navigation
  ;; Baseline #9178: a second navigateTree while session_before_tree is
  ;; blocked must throw; the first navigation still moves the leaf.
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let* ((started (sb-thread:make-semaphore :count 0))
           (release (sb-thread:make-semaphore :count 0))
           (bundle
             (make-test-extension-bundle
              "goal24-block-tree"
              (lambda ()
                (cadr-agent:define-event-hook
                 :session-before-tree
                 :handler
                 (lambda (event context)
                   (declare (ignore event context))
                   (sb-thread:signal-semaphore started)
                   (sb-thread:wait-on-semaphore release :timeout 10)
                   nil)))))
           (host (make-test-extension-host (list bundle)))
           (session
             (cadr-agent:create-session
              :directory sessions :cwd cwd
              :id "goal24-nav-concurrent"))
           (second-target
             (cadr-agent:session-append-message
              session
              (cadr-ai:make-user-message :content "first user")))
           (first-target
             (cadr-agent:session-append-message
              session
              (assistant
               (list
                (make-text-content :text "first assistant")))))
           (_second-user
             (cadr-agent:session-append-message
              session
              (cadr-ai:make-user-message :content "second user")))
           (original-leaf
             (cadr-agent:session-append-message
              session
              (assistant
               (list
                (make-text-content :text "second assistant")))))
           (agent
             (cadr-agent:make-agent
              :provider :mock
              :model (mock-model)
              :session session
              :extension-host host
              :auto-compact-p nil))
           (first-error nil))
      (declare (ignore _second-user))
      (let ((nav-thread
              (sb-thread:make-thread
               (lambda ()
                 (handler-case
                     (cadr-agent:agent-navigate-tree
                      agent first-target
                      :summarize-p nil)
                   (error (condition)
                     (setf first-error condition))))
               :name "goal24-first-nav")))
        (sb-thread:wait-on-semaphore started :timeout 5)
        (is-true (cadr-agent:agent-compacting-p agent))
        (is
         (string=
          +goal24-tree-compacting-message+
          (goal24-navigate-error-message
           (lambda ()
             (cadr-agent:agent-navigate-tree
              agent second-target
              :summarize-p nil)))))
        (is
         (string=
          original-leaf
          (cadr-agent:session-leaf-id session)))
        (sb-thread:signal-semaphore release)
        (sb-thread:join-thread nav-thread :timeout 10))
      (is (null first-error))
      (is-false (cadr-agent:agent-compacting-p agent))
      (is
       (string=
        first-target
        (cadr-agent:session-leaf-id session))))))

(test goal24-agent-compacting-p-false-when-idle
  (let ((agent
          (cadr-agent:make-agent
           :provider :mock
           :model (mock-model)
           :auto-compact-p nil)))
    (is-false (cadr-agent:agent-compacting-p agent))
    (setf (cadr-agent::agent-busy-p agent) t)
    (is-false (cadr-agent:agent-compacting-p agent))
    (is
     (string=
      +goal24-tree-busy-message+
      (goal24-navigate-error-message
       (lambda ()
         (cadr-agent:agent-navigate-tree agent "missing")))))))
