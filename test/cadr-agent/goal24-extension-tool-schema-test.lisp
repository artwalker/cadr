(in-package #:cadr-agent/tests)
(in-suite cadr-agent-suite)

(defun goal24-noop-handler (call-id arguments context)
  (declare (ignore call-id arguments context))
  (values "ok" nil))

(defun goal24-register-tool-without-object-schema (parameters)
  (make-test-extension-bundle
   "goal24-missing-parameters"
   (lambda ()
     (cadr-agent:define-tool
      "noop"
      :description "Do nothing"
      :parameters parameters
      :handler #'goal24-noop-handler))
   :path "/tmp/goal24-missing-parameters.lisp"))

(test goal24-rejects-extension-tools-without-a-parameter-schema
  "pi #9300 / acaa253cc: missing or non-object parameters fail at
registration with the object-schema message; the tool is not kept."
  (dolist (parameters (list nil "string" #() '(not-a-schema)))
    (let ((condition
            (handler-case
                (goal24-register-tool-without-object-schema parameters)
              (cadr-agent:extension-registration-error (signaled)
                signaled))))
      (is (typep condition 'cadr-agent:extension-registration-error))
      (is (search
           "must define an object parameter schema"
           (cadr-ai:cadr-error-message condition)))
      (is (search
           "Tool \"noop\""
           (cadr-ai:cadr-error-message condition)))
      (is (search
           "/tmp/goal24-missing-parameters.lisp"
           (cadr-ai:cadr-error-message condition)))))
  (let ((bundle
          (handler-case
              (goal24-register-tool-without-object-schema nil)
            (cadr-agent:extension-registration-error ()
              nil))))
    (is (null bundle)))
  (let* ((host (make-test-extension-host nil))
         (path "/tmp/goal24-missing-parameters-load.lisp")
         (kept
           (handler-case
               (let ((bundle
                       (cadr-agent::make-extension-bundle
                        :id "goal24-missing-parameters-load"
                        :path path
                        :scope :project
                        :rank 1
                        :order 0)))
                 (cadr-agent::call-with-extension-load
                  host bundle
                  (lambda ()
                    (cadr-agent:define-tool
                     "noop"
                     :description "Do nothing"
                     :handler #'goal24-noop-handler)))
                 (cadr-agent::replace-extension-bundles host (list bundle))
                 bundle)
             (cadr-agent:extension-registration-error ()
               nil))))
    (is (null kept))
    (is (null
         (cadr-agent::extension-snapshot-bundles
          (cadr-agent::extension-host-current-snapshot host))))))
