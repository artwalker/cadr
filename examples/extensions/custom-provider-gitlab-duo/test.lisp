(load (merge-pathnames "index.lisp" *load-truename*))

(defun run-gitlab-duo-smoke
    (runtime &key
       (model-id "claude-sonnet-4-5-20250929")
       thinking-p on-event)
  (let ((model
          (cadr-ai:models-runtime-model runtime :gitlab-duo model-id)))
    (unless model
      (error "Unknown model: ~A. Available: ~{~A~^, ~}"
             model-id (mapcar #'cadr-ai:model-id *gitlab-duo-models*)))
    (cadr-ai:models-runtime-stream
     runtime model
     (cadr-ai:make-context
      :messages
      (list
       (cadr-ai:make-user-message
        :content "Say hello in exactly 3 words.")))
     (or on-event
         (lambda (event)
           (when (member (cadr-ai:stream-event-type event)
                         '(:thinking-delta :text-delta))
             (write-string (or (cadr-ai:stream-event-delta event) ""))
             (finish-output))))
     :max-tokens 100
     :reasoning (and thinking-p :low))))
