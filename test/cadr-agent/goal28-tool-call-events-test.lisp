(in-package #:cadr-agent/tests)
(in-suite cadr-agent-suite)

(defun goal28-hook-events (bundle)
  (mapcar
   #'cadr-agent::extension-hook-definition-event
   (cadr-agent::extension-bundle-hooks bundle)))

(defun goal28-snapshot-hook-events (host event)
  (mapcar
   #'cadr-agent::extension-hook-definition-event
   (gethash
    event
    (cadr-agent::extension-snapshot-hooks
     (cadr-agent::extension-host-current-snapshot host)))))

(test goal28-tool-call-events-reach-existing-hooks
  (let* ((seen nil)
         (noop
           (lambda (event context)
             (declare (ignore event context))
             nil))
         (bundle
           (make-test-extension-bundle
            "goal28-tool-call-events"
            (lambda ()
              (cadr-agent::register-extension-hook
               'tool_call
               :handler
               (lambda (event context)
                 (declare (ignore event context))
                 (push :tool_call-symbol seen)
                 nil))
              (cadr-agent::register-extension-hook
               "tool_call"
               :handler
               (lambda (event context)
                 (declare (ignore event context))
                 (push :tool_call-string seen)
                 nil))
              (cadr-agent::register-extension-hook
               :tool_call
               :handler
               (lambda (event context)
                 (declare (ignore event context))
                 (push :tool_call-keyword seen)
                 nil))
              (cadr-agent::register-extension-hook
               :tool-call
               :handler
               (lambda (event context)
                 (declare (ignore event context))
                 (push :tool-call-keyword seen)
                 nil))
              (cadr-agent::register-extension-hook
               'tool_result
               :handler
               (lambda (event context)
                 (declare (ignore event context))
                 (push :tool_result-symbol seen)
                 nil))
              (cadr-agent::register-extension-hook
               "tool_result"
               :handler
               (lambda (event context)
                 (declare (ignore event context))
                 (push :tool_result-string seen)
                 nil))
              (cadr-agent::register-extension-hook
               :tool-result
               :handler
               (lambda (event context)
                 (declare (ignore event context))
                 (push :tool-result-keyword seen)
                 nil))
              (cadr-agent::register-extension-hook
               :tool-call-before
               :handler
               (lambda (event context)
                 (declare (ignore event context))
                 (push :existing-before seen)
                 nil))
              (cadr-agent::register-extension-hook
               :tool-call-after
               :handler
               (lambda (event context)
                 (declare (ignore event context))
                 (push :existing-after seen)
                 nil)))))
         (host (make-test-extension-host (list bundle)))
         (call
           (make-tool-call
            :id "goal28-call"
            :name "echo"
            :arguments (cadr-ai::json-object)))
         (result
           (cadr-ai:make-tool-result-message
            :tool-call-id "goal28-call"
            :tool-name "echo"
            :content
            (list (make-text-content :text "ok")))))
    (is
     (equal
      '(:tool-call-before
        :tool-call-before
        :tool-call-before
        :tool-call-before
        :tool-call-after
        :tool-call-after
        :tool-call-after
        :tool-call-before
        :tool-call-after)
      (goal28-hook-events bundle)))
    (is
     (every
      (lambda (stored)
        (eq stored :tool-call-before))
      (goal28-snapshot-hook-events host :tool-call-before)))
    (is
     (= 5
        (length
         (goal28-snapshot-hook-events host :tool-call-before))))
    (is
     (every
      (lambda (stored)
        (eq stored :tool-call-after))
      (goal28-snapshot-hook-events host :tool-call-after)))
    (is
     (= 4
        (length
         (goal28-snapshot-hook-events host :tool-call-after))))
    (cadr-agent::run-extension-hooks
     host :tool-call-before :tool-call call :turn-index 1)
    (cadr-agent::run-extension-hooks
     host :tool-call-after
     :tool-call call :tool-result result :turn-index 1)
    (is
     (equal
      '(:existing-after
        :tool-result-keyword
        :tool_result-string
        :tool_result-symbol
        :existing-before
        :tool-call-keyword
        :tool_call-keyword
        :tool_call-string
        :tool_call-symbol)
      seen))
    (signals cadr-agent:extension-registration-error
      (make-test-extension-bundle
       "goal28-unknown-hook-event"
       (lambda ()
         (cadr-agent::register-extension-hook
          :not-a-hook-event
          :handler noop))))
    (signals cadr-agent:extension-registration-error
      (make-test-extension-bundle
       "goal28-unknown-hook-string"
       (lambda ()
         (cadr-agent::register-extension-hook
          "unknown_event"
          :handler noop))))))
