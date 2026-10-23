(in-package #:cadr-agent)

(defvar *virtual-models* (make-hash-table :test #'equal))
(defvar *virtual-model-generation* 0)

(defstruct virtual-model-registration
  model
  route)

(defstruct virtual-model-route-request
  model
  thinking-level
  reason
  previous
  failed
  state
  messages
  ;; v1.4.0 ModelRouteRequest.signal. The request abort signal,
  ;; checked with extension-cancellation-aborted-p.
  signal)

(defstruct virtual-model-route
  model
  thinking-level
  state)

(defstruct (branch-selection
            (:constructor make-branch-selection))
  provider
  model-id)

(defun virtual-model-provider-symbol (provider)
  (etypecase provider
    (symbol provider)
    (string
     (intern (string-upcase provider) :keyword))))

(defun virtual-model-provider-name (provider)
  (string-downcase
   (symbol-name (virtual-model-provider-symbol provider))))

(defun virtual-model-key (provider id)
  (cons (virtual-model-provider-name provider) id))

(defun virtual-model-p (model)
  ;; pi@4a080252f virtual-models.ts isVirtualModel. Failed routing
  ;; leaves api pi-virtual on the assistant message.
  (typecase model
    (cadr-ai:model
     (eq (cadr-ai:model-api model) :pi-virtual))
    (cadr-ai:assistant-message
     (eq (cadr-ai:assistant-message-api model) :pi-virtual))
    (t nil)))

(defun virtual-model-generation ()
  *virtual-model-generation*)

(defun registered-virtual-model (provider id)
  (let ((entry
          (gethash (virtual-model-key provider id)
                   *virtual-models*)))
    (and entry (virtual-model-registration-model entry))))

(defun registered-virtual-models ()
  (loop for entry being the hash-values of *virtual-models*
        collect (virtual-model-registration-model entry)))

(defun create-virtual-model
    (&key provider id name thinking-levels context-window max-tokens
          input)
  (let* ((provider (virtual-model-provider-symbol provider))
         (levels (or thinking-levels '(:off)))
         (images-p
           (not (null
                 (some (lambda (kind)
                         (member kind '("image" :image) :test #'equal))
                       (or input '("text" "image")))))))
    (cadr-ai:make-model
     :id id
     :name (or name id)
     :provider provider
     :api :pi-virtual
     :base-url ""
     :reasoning-p
     (not (null
           (some (lambda (level)
                   (not (eq level :off)))
                 levels)))
     :thinking-level-map
     (loop for level in '(:off :minimal :low :medium :high :xhigh :max)
           collect (cons level
                         (and (member level levels) level)))
     :supports-images-p images-p
     :context-window (or context-window 0)
     :max-tokens (or max-tokens 0))))

(defun virtual-model-blank-text-p (value)
  ;; v1.4.0 model-runtime.ts registerVirtualModel trims before
  ;; rejecting an empty provider or id. The stored text stays as given.
  (or (not (stringp value))
      (zerop
       (length
        (string-trim
         '(#\Space #\Tab #\Newline #\Return #\Page #\Vt)
         value)))))

(defun register-virtual-model
    (&key provider id name route thinking-levels context-window
          max-tokens input physical-model)
  (unless (and (functionp route)
               (not (virtual-model-blank-text-p
                     (virtual-model-provider-name provider)))
               (not (virtual-model-blank-text-p id)))
    (error "Virtual model provider and id must not be empty."))
  (when (and physical-model (not (virtual-model-p physical-model)))
    (error "Virtual model ~A/~A conflicts with a physical model."
           (virtual-model-provider-name provider)
           id))
  (let ((model
          (create-virtual-model
           :provider provider
           :id id
           :name name
           :thinking-levels thinking-levels
           :context-window context-window
           :max-tokens max-tokens
           :input input)))
    (setf (gethash (virtual-model-key provider id) *virtual-models*)
          (make-virtual-model-registration :model model :route route))
    (incf *virtual-model-generation*)
    model))

(defun unregister-virtual-model (provider id)
  (when (remhash (virtual-model-key provider id) *virtual-models*)
    (incf *virtual-model-generation*)
    t))

(defun find-latest-response (messages)
  (loop for message in (reverse messages)
        when (and (typep message 'cadr-ai:assistant-message)
                  (not (member (cadr-ai:assistant-message-stop-reason
                                message)
                               '(:error :aborted))))
          return message))

(defun synthetic-response-model (message)
  (cadr-ai:make-model
   :id (cadr-ai:assistant-message-model message)
   :name (cadr-ai:assistant-message-model message)
   :provider (cadr-ai:assistant-message-provider message)
   :api (or (cadr-ai:assistant-message-api message) :openai-completions)))

(defun resolve-virtual-model
    (model messages &key reason thinking-level failed state signal
                         get-model has-auth-p)
  (let* ((name
           (format nil "Virtual model ~A/~A"
                   (virtual-model-provider-name
                    (cadr-ai:model-provider model))
                   (cadr-ai:model-id model)))
         (entry
           (gethash (virtual-model-key
                     (cadr-ai:model-provider model)
                     (cadr-ai:model-id model))
                    *virtual-models*)))
    (unless entry
      (error "~A is not registered." name))
    (let* ((latest (find-latest-response messages))
           (previous-model
             (and latest
                  (not (virtual-model-p latest))
                  (or (and get-model
                           (funcall get-model
                                    (cadr-ai:assistant-message-provider
                                     latest)
                                    (cadr-ai:assistant-message-model
                                     latest)))
                      (synthetic-response-model latest))))
           (failed-model
             (and failed
                  (not (virtual-model-p failed))
                  (or (and get-model
                           (funcall get-model
                                    (cadr-ai:assistant-message-provider
                                     failed)
                                    (cadr-ai:assistant-message-model
                                     failed)))
                      (synthetic-response-model failed))))
           (route
             (funcall
              (virtual-model-registration-route entry)
              (make-virtual-model-route-request
               :model model
               :thinking-level (or thinking-level :off)
               :reason (or reason :direct)
               :previous
               (and previous-model
                    (list :model previous-model
                          :thinking-level
                          (cadr-ai:assistant-message-provider-thinking-level
                           latest)))
               :failed
               (and failed-model failed
                    (list :model failed-model
                          :message failed))
               ;; v1.4.0 docs/virtual-models.md. direct requests
               ;; have no router state.
               :state (unless (eq (or reason :direct) :direct) state)
               :messages messages
               :signal signal)))
           (target (virtual-model-route-model route)))
      (unless (and (typep target 'cadr-ai:model)
                   (not (virtual-model-p target)))
        (error "~A routed to ~A/~A, which is not a physical model."
               name
               (if (typep target 'cadr-ai:model)
                   (virtual-model-provider-name
                    (cadr-ai:model-provider target))
                   "?")
               (if (typep target 'cadr-ai:model)
                   (cadr-ai:model-id target)
                   "?")))
      (when (and has-auth-p (not (funcall has-auth-p target)))
        (error "~A routed to ~A/~A, which has no credentials."
               name
               (virtual-model-provider-name
                (cadr-ai:model-provider target))
               (cadr-ai:model-id target)))
      (make-virtual-model-route
       :model target
       :thinking-level
       (cadr-ai:clamp-thinking-level
        target
        (or (virtual-model-route-thinking-level route) :off))
       :state (virtual-model-route-state route)))))

(defun find-last-model-change (branch before)
  (loop for index from (1- before) downto 0
        for entry = (nth index branch)
        when (eq (session-entry-type entry) :model-change)
          return entry))

(defun branch-selection (branch get-model)
  ;; pi@4a080252f getBranchSelection. A virtual model_change holds
  ;; across later physical responses while that virtual model stays
  ;; registered. The last model_change itself always wins.
  (loop for index from (1- (length branch)) downto 0
        for entry = (nth index branch)
        do
        (cond
          ((eq (session-entry-type entry) :model-change)
           (return
             (make-branch-selection
              :provider (session-entry-provider entry)
              :model-id (session-entry-model-id entry))))
          ((and (eq (session-entry-type entry) :message)
                (typep (session-entry-message entry)
                       'cadr-ai:assistant-message)
                (not (virtual-model-p (session-entry-message entry))))
           (let* ((message (session-entry-message entry))
                  (response
                    (make-branch-selection
                     :provider
                     (virtual-model-provider-name
                      (cadr-ai:assistant-message-provider message))
                     :model-id
                     (cadr-ai:assistant-message-model message)))
                  (change (find-last-model-change branch index))
                  (model
                    (and change
                         (funcall get-model
                                  (session-entry-provider change)
                                  (session-entry-model-id change)))))
             (return
               (if (and change model (virtual-model-p model))
                   (make-branch-selection
                    :provider (session-entry-provider change)
                    :model-id (session-entry-model-id change))
                   response)))))))

(defun virtual-state-field (data key)
  (cond
    ((or (hash-table-p data)
         (cadr-ai::json-object-pairs-p data))
     (cadr-ai::json-get data key))
    ((consp data)
     (or (getf data (intern (string-upcase key) :keyword))
         (cdr (assoc key data :test #'string=))))
    (t nil)))

(defun virtual-model-state (branch provider model-id)
  (let ((provider-name (virtual-model-provider-name provider)))
    (loop for entry in (reverse branch)
          when (and (eq (session-entry-type entry) :custom)
                    (string= (session-entry-custom-type entry)
                             "pi.virtual-model-state"))
            do
            (let ((data (session-entry-data entry)))
              (when (and (string-equal
                          (or (virtual-state-field data "provider") "")
                          provider-name)
                         (string=
                          (or (virtual-state-field data "modelId") "")
                          model-id))
                (return (virtual-state-field data "state")))))))

(defun virtual-route-user-turn-p (messages)
  (let ((last-assistant
          (position-if
           (lambda (message)
             (typep message 'cadr-ai:assistant-message))
           messages
           :from-end t)))
    (some (lambda (message)
            (typep message 'cadr-ai:user-message))
          (subseq messages
                  (if last-assistant (1+ last-assistant) 0)))))

(defun agent-provider-matches-model-p (agent model)
  (let ((provider (agent-provider agent))
        (id (cadr-ai:model-provider model)))
    (cond
      ((symbolp provider) (eq provider id))
      ((typep provider 'cadr-ai::provider)
       (eq (cadr-ai::provider-id provider) id))
      (t nil))))

(defun agent-provider-has-auth-p (agent model)
  (let ((provider (agent-provider agent)))
    (cond
      ((symbolp provider)
       (agent-provider-matches-model-p agent model))
      ((and (typep provider 'cadr-ai::provider)
            (agent-provider-matches-model-p agent model))
       (or (cadr-ai::provider-api-key provider)
           (cadr-ai::provider-oauth-access-token provider)
           (not (cadr-ai::provider-authentication-required-p
                 provider))))
      ((functionp (agent-virtual-provider-function agent))
       (not (null (funcall (agent-virtual-provider-function agent)
                           model))))
      (t nil))))

(defun agent-provider-for-model (agent model)
  (cond
    ((agent-provider-matches-model-p agent model)
     (agent-provider agent))
    ((functionp (agent-virtual-provider-function agent))
     (funcall (agent-virtual-provider-function agent) model))
    (t nil)))

(defun record-virtual-selection (agent)
  (let ((model (agent-model agent))
        (session (agent-session agent)))
    (when (and model session)
      (let* ((recorded
               (branch-selection
                (session-path-entries session)
                (lambda (provider id)
                  (registered-virtual-model provider id))))
             (same-p
               (and recorded
                    (string-equal
                     (branch-selection-provider recorded)
                     (virtual-model-provider-name
                      (cadr-ai:model-provider model)))
                    (string=
                     (branch-selection-model-id recorded)
                     (cadr-ai:model-id model))))
             (recorded-model
               (and recorded
                    (registered-virtual-model
                     (branch-selection-provider recorded)
                     (branch-selection-model-id recorded)))))
        (when (and (not same-p)
                   (or (virtual-model-p model)
                       (virtual-model-p recorded-model)))
          (session-append-model-change
           session
           (virtual-model-provider-name
            (cadr-ai:model-provider model))
           (cadr-ai:model-id model)))))))

(defun remember-virtual-route-state (agent model route reason previous)
  (let ((session (agent-session agent))
        (state (virtual-model-route-state route)))
    (when (and session
               state
               (not (eq reason :direct))
               (not (eq state previous)))
      (session-append-custom
       session
       "pi.virtual-model-state"
       (cadr-ai::json-object
        "provider"
        (virtual-model-provider-name
         (cadr-ai:model-provider model))
        "modelId" (cadr-ai:model-id model)
        "state" state)))))

(defun agent-stream-target (agent messages &key (reason nil reason-p)
                                                (model nil model-p))
  ;; v1.4.0 _getSummarizationRequestAuth passes the model captured
  ;; before auth. The live selection is the default for a turn.
  (let ((selected (if model-p model (agent-model agent))))
    (unless (virtual-model-p selected)
      (return-from agent-stream-target
        (values selected
                (agent-provider agent)
                (agent-thinking-level agent)
                nil)))
    (let* ((reason
             (cond
               (reason-p reason)
               ((agent-virtual-route-failure agent) :retry)
               ((virtual-route-user-turn-p messages) :user)
               (t :continuation)))
           (failed
             (shiftf (agent-virtual-route-failure agent) nil)))
      (unless (eq reason :direct)
        (record-virtual-selection agent))
      (handler-case
          (let* ((branch
                   (and (agent-session agent)
                        (session-path-entries (agent-session agent))))
                 (previous-state
                   (and branch
                        (virtual-model-state
                         branch
                         (cadr-ai:model-provider selected)
                         (cadr-ai:model-id selected))))
                 (route
                   (resolve-virtual-model
                    selected messages
                    :reason reason
                    :thinking-level (agent-thinking-level agent)
                    :failed (and (eq reason :retry) failed)
                    :state previous-state
                    :signal
                    (make-extension-cancellation-signal
                     :aborted-function
                     (lambda () (agent-aborted-p agent))
                     :abort-function
                     (lambda () (agent-abort agent)))
                    :has-auth-p
                    (lambda (physical)
                      (agent-provider-has-auth-p agent physical)))))
            (remember-virtual-route-state
             agent selected route reason previous-state)
            (values (virtual-model-route-model route)
                    (agent-provider-for-model
                     agent
                     (virtual-model-route-model route))
                    (virtual-model-route-thinking-level route)
                    nil))
        (error (condition)
          (values nil nil nil (princ-to-string condition)))))))
