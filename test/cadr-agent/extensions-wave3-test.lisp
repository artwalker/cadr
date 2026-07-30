(in-package #:cadr-agent/tests)
(in-suite cadr-agent-suite)

(defparameter +wave3-extension-events+
  '(:project-trust
    :resources-discover
    :before-provider-request
    :before-provider-headers
    :after-provider-response
    :user-bash))

(test wave3-extension-event-set-is-exactly-the-baseline-thirty-three
  (is (= 33
         (length
          cadr-agent::+extension-hook-events+)))
  (is (= 33
         (length
          (remove-duplicates
           cadr-agent::+extension-hook-events+))))
  (dolist (event +wave3-extension-events+)
    (is (member
         event
         cadr-agent::+extension-hook-events+))))

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
         (getf result :theme-paths)))))

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
