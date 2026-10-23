(in-package #:cadr-chord)

(defvar *chord-queue* nil)
(defvar *activating* nil)
(defvar *recording* nil)
(defvar *factory-holds* nil)
(defvar *call-serial* 0)
(defvar *live-hosts* nil)

(defstruct chord-host
  (name "host")
  (kind "host")
  (self nil)
  (code-version 0)
  previous-code-version
  (services (make-hash-table :test #'equal))
  (objects (make-hash-table :test #'equal))
  (order nil)
  (roots nil)
  (sessions (make-hash-table :test #'equal))
  (errors nil)
  on-error)

(defstruct chord-service contract factory linger)
(defstruct chord-cell object name schema version value listeners migrate)
(defstruct chord-resource name open close (opened nil))
(defstruct chord-object
  host address key contract input principal service
  (status "loading")
  methods cells resources
  (holders 0)
  linger-until
  waiters
  shape-listeners
  gated)
(defstruct chord-ref object host remote-id session)
(defstruct chord-root version (methods (make-hash-table :test #'eq)) holds (finished nil))
(defstruct chord-request value error (done nil))
(defstruct chord-ctx host root)
(defstruct chord-session
  host link principal mismatch name kind
  (negotiated nil)
  (reported nil)
  (calls (make-hash-table))
  (holds (make-hash-table)))
(defstruct reload-report code-version previous changed removed prepared gated)
(defstruct facet name setup)

(define-condition chord-aggregate-error (error)
  ((errors :initarg :errors :reader chord-aggregate-errors))
  (:report (lambda (condition stream)
             (format stream "aggregate: ~A" (chord-aggregate-errors condition)))))

(defun make-self (&key (kind "host"))
  (json-object "kind" kind))

(defun create-host (&key (self (make-self)) (name "host") (kind "host") on-error)
  (let ((host (make-chord-host :self self :name name :kind kind :on-error on-error)))
    (remember-host host)
    host))

(defun host-name (host) (chord-host-name host))
(defun host-code-version (host) (chord-host-code-version host))
(defun host-previous-code-version (host) (chord-host-previous-code-version host))

(defun chord-schedule (thunk)
  (setf *chord-queue* (append *chord-queue* (list thunk))))

(defun object-address (contract input)
  (format nil "~A~A" (contract-name contract) (canonical-identity (contract-input contract) input)))

(defun object-key (contract input principal)
  (format nil "~A|~A" (object-address contract input) (canonical-json principal)))

(defun host-serve (host contract factory &key linger)
  (setf (gethash (contract-name contract) (chord-host-services host))
        (make-chord-service :contract contract :factory factory :linger linger))
  contract)

(defun host-install (host facet)
  (funcall (facet-setup facet) host)
  host)

(defun find-cell (object name)
  (find name (chord-object-cells object) :key #'chord-cell-name :test #'string=))

(defun emit-event (cell event)
  (dolist (listener (chord-cell-listeners cell))
    (funcall listener event)))

(defun self-state (object name schema initial &key (version 1) migrate)
  (let ((existing (find-cell object name)))
    (cond
      ((and existing *recording*)
       (cond
         ((and (= version (chord-cell-version existing))
               (string= (canonical-json schema) (canonical-json (chord-cell-schema existing))))
          existing)
         ((<= version (chord-cell-version existing))
          (invalid "state"
                   (format nil "~A changed without a version bump" name)))
         ((null migrate)
          (invalid "state" "missing migrate"))
         (t
          (let ((migrated (funcall migrate (copy-json (chord-cell-value existing))
                                    (chord-cell-version existing))))
            (setf (chord-cell-schema existing) schema
                  (chord-cell-version existing) version
                  (chord-cell-value existing) migrated
                  (chord-cell-migrate existing) migrate
                  (chord-object-gated object) t)
            (emit-event existing (json-object "type" "reset" "value" migrated))
            existing))))
      (existing
       (error "duplicate state name ~A" name))
      (t
       (let ((cell (make-chord-cell :object object :name name :schema schema
                                    :version version :value (copy-json initial)
                                    :migrate migrate)))
         (push cell (chord-object-cells object))
         cell)))))

(defun self-resource (object name &key version open close)
  (declare (ignore version))
  (let ((resource (make-chord-resource :name name :open open :close close)))
    (push resource (chord-object-resources object))
    resource))

(defun open-resources (object)
  (dolist (resource (reverse (chord-object-resources object)))
    (when (chord-resource-open resource)
      (funcall (chord-resource-open resource))
      (setf (chord-resource-opened resource) t))))

(defun close-resources (host object)
  (let ((errors nil))
    (dolist (resource (chord-object-resources object))
      (when (and (chord-resource-opened resource) (chord-resource-close resource))
        (handler-case (funcall (chord-resource-close resource))
          (error (condition) (push condition errors)))))
    (setf (chord-object-resources object) nil)
    (when (and errors (chord-host-on-error host))
      (funcall (chord-host-on-error host)
               (make-condition 'chord-aggregate-error :errors errors)))))

(defun dispose-object (host object)
  (setf (chord-object-status object) "released"
        (chord-object-linger-until object) nil)
  (close-resources host object))

(defun fail-waiters (object condition)
  (dolist (waiter (nreverse (chord-object-waiters object)))
    (destructuring-bind (request name args root) waiter
      (declare (ignore name args root))
      (setf (chord-request-error request) condition
            (chord-request-done request) t)))
  (setf (chord-object-waiters object) nil))

(defun invoke-method (object name args root)
  (when (and root (chord-object-gated object)
             (< (chord-root-version root)
                (chord-host-code-version (chord-object-host object))))
    (signal-chord "upgrade_conflict" "the object was upgraded"))
  (when (and root (not (gethash object (chord-root-methods root))))
    (setf (gethash object (chord-root-methods root))
          (copy-alist (chord-object-methods object))))
  (let* ((table (if root
                    (gethash object (chord-root-methods root))
                    (chord-object-methods object)))
         (function (cdr (assoc name table :test #'string=))))
    (unless function
      (invalid "member" (format nil "missing method ~A" name)))
    (apply function args)))

(defun drain-waiters (object)
  (dolist (waiter (nreverse (chord-object-waiters object)))
    (destructuring-bind (request name args root) waiter
      (handler-case
          (setf (chord-request-value request) (invoke-method object name args root))
        (error (condition)
          (setf (chord-request-error request) condition)))
      (setf (chord-request-done request) t)))
  (setf (chord-object-waiters object) nil))

(defun activate-object (host object)
  (let* ((key (chord-object-key object))
         (*activating* (cons key *activating*))
         (*factory-holds* nil)
         (service (chord-object-service object)))
    (handler-case
        (let ((methods (funcall (chord-service-factory service)
                                (chord-object-input object)
                                (chord-object-principal object)
                                object)))
          (unless (listp methods)
            (error "factory must be synchronous"))
          (open-resources object)
          (setf (chord-object-methods object) methods
                (chord-object-status object) "live")
          (drain-waiters object))
      (error (condition)
        (dolist (hold *factory-holds*)
          (ref-release hold))
        (setf (chord-object-status object) "gone")
        (close-resources host object)
        (let ((wrapped (if (typep condition 'chord-error)
                           condition
                           (make-condition 'chord-error
                                           :code "unavailable"
                                           :text (princ-to-string condition)))))
          (fail-waiters object wrapped))))))

(defun usable-object (object)
  (and object (member (chord-object-status object)
                      '("loading" "live" "lingering")
                      :test #'string=)))

(defun host-hold (host contract input &key (principal (json-object "kind" "host")))
  (let* ((normalized (schema-normalize (contract-input contract) input "input"))
         (key (object-key contract normalized principal))
         (existing (gethash key (chord-host-objects host)))
         (session (session-for host contract)))
    (when (member key *activating* :test #'string=)
      (error "cycle"))
    (cond
      (session (remote-hold session contract normalized))
      ((usable-object existing)
       (incf (chord-object-holders existing))
       (when (string= (chord-object-status existing) "lingering")
         (setf (chord-object-status existing) "live"
               (chord-object-linger-until existing) nil))
       (make-chord-ref :object existing :host host))
      (t
       (let ((object (make-chord-object
                      :host host
                      :address (object-address contract normalized)
                      :key key
                      :contract contract
                      :input normalized
                      :principal principal
                      :service (or (gethash (contract-name contract) (chord-host-services host))
                                   (error "no factory for ~A" (contract-name contract)))
                      :holders 1)))
         (setf (gethash key (chord-host-objects host)) object)
         (setf (chord-host-order host) (append (chord-host-order host) (list object)))
         (if *activating*
             (activate-object host object)
             (chord-schedule (lambda () (activate-object host object))))
         (make-chord-ref :object object :host host))))))

(defun session-for (host contract)
  (when (eq (contract-scope contract) :remote)
    (let ((name (resolve-host (contract-name contract)
                              (json-get (contract-def contract) "host")
                              nil)))
      (gethash name (chord-host-sessions host)))))

(defun remote-hold (session contract input)
  (let* ((id (incf *call-serial*))
         (ref (make-chord-ref :host (chord-session-host session)
                              :session session
                              :remote-id id
                              :object (make-chord-object :status "live" :host (chord-session-host session)))))
    (setf (gethash id (chord-session-holds session)) (list contract input))
    (link-send (chord-session-link session)
               (json-object "t" "hold"
                            "id" id
                            "name" (contract-name contract)
                            "input" input))
    ref))

(defun self-get (object contract input)
  (let ((ref (host-hold (chord-object-host object) contract input)))
    (push ref *factory-holds*)
    ref))

(defun ref-status (ref)
  (chord-object-status (chord-ref-object ref)))

(defun ref-release (ref)
  (when (chord-ref-remote-id ref)
    (return-from ref-release nil))
  (let* ((object (chord-ref-object ref))
         (host (chord-ref-host ref)))
    (when (plusp (chord-object-holders object))
      (decf (chord-object-holders object)))
    (when (and (zerop (chord-object-holders object))
               (not (string= (chord-object-status object) "gone")))
      (let ((linger (chord-service-linger (chord-object-service object))))
        (if (and linger (plusp linger))
            (setf (chord-object-status object) "lingering"
                  (chord-object-linger-until object)
                  (+ (get-internal-real-time)
                     (ceiling (* linger internal-time-units-per-second))))
            (dispose-object host object))))))

(defun ref-member (ref name)
  (or (find-cell (chord-ref-object ref) name)
      (signal-chord "not_ready" "state is not ready")))

(defun ref-on-shape (ref listener)
  (push listener (chord-object-shape-listeners (chord-ref-object ref))))

(defun cell-value (cell)
  (let ((status (chord-object-status (chord-cell-object cell))))
    (unless (or (string= status "live") (string= status "lingering"))
      (signal-chord "not_ready" "state is not ready")))
  (chord-cell-value cell))

(defun cell-change (cell function)
  (when *recording*
    (invalid "read_only" "state is read_only during prepare"))
  (let ((draft (copy-json (chord-cell-value cell))))
    (funcall function draft)
    (setf (chord-cell-value cell) draft)
    (emit-event cell (json-object "type" "ops" "value" draft))
    draft))

(defun cell-replace (cell value)
  (when *recording*
    (invalid "read_only" "state is read_only during prepare"))
  (setf (chord-cell-value cell) (copy-json value)))

(defun cell-on-event (cell listener)
  (push listener (chord-cell-listeners cell)))

(defun call-root (args)
  (let ((last (car (last args))))
    (cond
      ((chord-ctx-p last) (values (chord-ctx-root last) (butlast args)))
      ((chord-root-p last) (values last (butlast args)))
      (t (values nil args)))))

(defun ref-call (ref name &rest args)
  (multiple-value-bind (root args) (call-root args)
    (cond
      ((chord-ref-remote-id ref)
       (remote-call ref name args))
      (t
       (let ((object (chord-ref-object ref)))
         (cond
           ((or (string= (chord-object-status object) "released")
                (string= (chord-object-status object) "gone"))
            (let ((request (make-chord-request :done t
                                                :error (make-condition 'chord-error
                                                                       :code "released"
                                                                       :text "released"))))
              (if (string= (chord-object-status object) "gone")
                  (setf (chord-request-error request)
                        (make-condition 'chord-error :code "unavailable" :text "gone")))
              request))
           ((member (chord-object-status object) '("live" "lingering") :test #'string=)
            (handler-case
                (make-chord-request :done t :value (invoke-method object name args root))
              (error (condition)
                (make-chord-request :done t :error condition))))
           (t
            (let ((request (make-chord-request)))
              (setf (chord-object-waiters object)
                    (append (chord-object-waiters object)
                            (list (list request name args root))))
              request))))))))

(defun remote-call (ref name args)
  (let* ((session (chord-ref-session ref))
         (id (incf *call-serial*))
         (request (make-chord-request)))
    (setf (gethash id (chord-session-calls session)) request)
    (link-send (chord-session-link session)
               (json-object "t" "call"
                            "id" id
                            "hold" (chord-ref-remote-id ref)
                            "member" name
                            "args" (apply #'json-array args)))
    request))

(defun chord-await (request)
  (let ((deadline (+ (get-internal-real-time) (* 30 internal-time-units-per-second))))
    (loop until (chord-request-done request)
          do (chord-flush)
             (when (> (get-internal-real-time) deadline)
               (error "condition not reached"))
             (sleep 0.01)))
  (when (chord-request-error request)
    (error (chord-request-error request)))
  (chord-request-value request))

(defun expire-lingers ()
  (let ((now (get-internal-real-time)))
    (dolist (host *live-hosts*)
      (dolist (object (chord-host-order host))
        (when (and (string= (chord-object-status object) "lingering")
                   (chord-object-linger-until object)
                   (>= now (chord-object-linger-until object)))
          (dispose-object host object))))))

(defun chord-flush ()
  (loop while *chord-queue*
        for thunk = (pop *chord-queue*)
        do (funcall thunk))
  (expire-lingers))

(defun remember-host (host)
  (pushnew host *live-hosts*))

(defun host-open-root (host)
  (let ((root (make-chord-root :version (chord-host-code-version host))))
    (push root (chord-host-roots host))
    root))

(defun host-finish-root (host root)
  (setf (chord-root-finished root) t)
  (dolist (hold (chord-root-holds root))
    (ref-release hold))
  (setf (chord-host-roots host) (remove root (chord-host-roots host)))
  (refresh-previous host)
  root)

(defun host-root (host function)
  (let ((root (host-open-root host)))
    (unwind-protect
         (funcall function (make-chord-ctx :host host :root root))
      (host-finish-root host root))))

(defun ctx-get (ctx contract input)
  (let ((ref (host-hold (chord-ctx-host ctx) contract input)))
    (push ref (chord-root-holds (chord-ctx-root ctx)))
    (chord-flush)
    ref))

(defun refresh-previous (host)
  (setf (chord-host-previous-code-version host)
        (when (some (lambda (root)
                      (< (chord-root-version root) (chord-host-code-version host)))
                    (chord-host-roots host))
          (max 0 (1- (chord-host-code-version host))))))

(defun rollback-snapshot (host snapshot)
  (destructuring-bind (object old-methods old-resources new-resources) snapshot
    (declare (ignore new-resources))
    (close-resources host object)
    (setf (chord-object-methods object) old-methods
          (chord-object-resources object) old-resources
          (chord-object-gated object) nil)))

(defun prepare-object (host object snapshots prepared gated)
  (let ((old-methods (copy-alist (chord-object-methods object)))
        (old-resources (chord-object-resources object))
        (old-service (chord-object-service object)))
    (setf (chord-object-resources object) nil
          (chord-object-gated object) nil
          (chord-object-service object)
          (or (gethash (contract-name (chord-object-contract object))
                       (chord-host-services host))
              old-service))
    (handler-case
        (let ((*recording* t))
          (setf (chord-object-methods object)
                (funcall (chord-service-factory (chord-object-service object))
                         (chord-object-input object)
                         (chord-object-principal object)
                         object))
          (open-resources object)
          (vector-push-extend
           (list object old-methods old-resources (chord-object-resources object))
           snapshots)
          (vector-push-extend (chord-object-address object) prepared)
          (when (chord-object-gated object)
            (vector-push-extend (chord-object-address object) gated)))
      (error (condition)
        (close-resources host object)
        (setf (chord-object-methods object) old-methods
              (chord-object-resources object) old-resources
              (chord-object-service object) old-service
              (chord-object-gated object) nil)
        (error condition)))))

(defun host-reload (host facets)
  (let ((previous (chord-host-code-version host))
        (snapshots (make-array 0 :adjustable t :fill-pointer 0))
        (prepared (make-array 0 :adjustable t :fill-pointer 0))
        (gated (make-array 0 :adjustable t :fill-pointer 0)))
    (handler-case
        (progn
          (dolist (facet facets)
            (funcall (facet-setup facet) host))
          (dolist (object (chord-host-order host))
            (when (member (chord-object-status object) '("live" "lingering" "loading") :test #'string=)
              (prepare-object host object snapshots prepared gated)))
          (incf (chord-host-code-version host))
          (loop for snapshot across snapshots
                do (dolist (listener (chord-object-shape-listeners (first snapshot)))
                     (funcall listener
                              (json-object "contract"
                                           (contract-fingerprint
                                            (chord-object-contract (first snapshot)))))))
          (refresh-previous host)
          (make-reload-report :code-version (chord-host-code-version host)
                              :previous previous
                              :changed nil
                              :removed nil
                              :prepared (coerce prepared 'list)
                              :gated (coerce gated 'list)))
      (error (condition)
        (loop for snapshot across snapshots
              do (rollback-snapshot host snapshot))
        (if (typep condition 'chord-error)
            (error condition)
            (signal-chord "unavailable"
                          (format nil "reload aborted: ~A" condition)))))))

(defun frame-type (frame)
  (json-get frame "t"))

(defun frame-protocol (frame)
  (let ((value (json-get frame "protocol")))
    (if (integerp value) value 1)))

(defun protocol-peer (reason)
  (let ((marker "protocol-version "))
    (when (and (stringp reason) (string= reason marker :end1 (min (length reason) (length marker))))
      (parse-integer reason :start (length marker) :junk-allowed t))))

(defun report-mismatch (session peer)
  (unless (chord-session-reported session)
    (setf (chord-session-reported session) t)
    (when (chord-session-mismatch session)
      (funcall (chord-session-mismatch session)
               (json-object "local" +protocol-version+ "peer" peer)))))

(defun hello-frame (host)
  (json-object "t" "hello"
               "protocol" +protocol-version+
               "name" (chord-host-name host)
               "kind" (chord-host-kind host)
               "codeVersion" (chord-host-code-version host)))

(defun ingest-hello (session frame)
  (let ((peer (frame-protocol frame)))
    (cond
      ((= peer +protocol-version+)
       (setf (chord-session-negotiated session) t))
      (t
       (report-mismatch session peer)
       (link-send (chord-session-link session)
                  (json-object "t" "bye" "reason" (format nil "protocol-version ~A" +protocol-version+)))
       (link-close (chord-session-link session)
                   (format nil "protocol-version ~A" +protocol-version+))))))

(defun ingest-hold (session frame)
  (let* ((host (chord-session-host session))
         (name (json-get frame "name"))
         (service (gethash name (chord-host-services host)))
         (ref (host-hold host (chord-service-contract service) (json-get frame "input"))))
    (chord-flush)
    (setf (gethash (json-get frame "id") (chord-session-holds session)) ref)
    (link-send (chord-session-link session)
               (json-object "t" "shape"
                            "id" (json-get frame "id")
                            "contract" (contract-fingerprint (chord-service-contract service))))))

(defun json-args (value)
  (cond
    ((null value) nil)
    ((vectorp value) (coerce value 'list))
    ((listp value) value)
    (t (list value))))

(defun ingest-call (session frame)
  (let* ((ref (gethash (json-get frame "hold") (chord-session-holds session)))
         (value (chord-await (apply #'ref-call ref (json-get frame "member") (json-args (json-get frame "args"))))))
    (link-send (chord-session-link session)
               (json-object "t" "result" "id" (json-get frame "id") "value" value))))

(defun ingest-result (session frame)
  (let ((request (gethash (json-get frame "id") (chord-session-calls session))))
    (when request
      (if (json-get frame "error")
          (setf (chord-request-error request)
                (make-condition 'chord-error :code "unavailable" :text (json-get frame "error")))
          (setf (chord-request-value request) (json-get frame "value")))
      (setf (chord-request-done request) t))))

(defun ingest-frame (session frame)
  (let ((type (or (frame-type frame) "")))
    (cond
      ((string= type "hello") (ingest-hello session frame))
      ((string= type "bye")
       (link-close (chord-session-link session) (json-get frame "reason")))
      ((not (chord-session-negotiated session)) nil)
      ((string= type "hold") (ingest-hold session frame))
      ((string= type "call") (ingest-call session frame))
      ((string= type "result") (ingest-result session frame)))))

(defun note-link-close (session reason)
  (let ((peer (protocol-peer reason)))
    (when peer
      (report-mismatch session peer))))

(defun attach-session (host link &key principal on-protocol-mismatch name kind)
  (let ((session (make-chord-session :host host
                                     :link link
                                     :principal (or principal (json-object))
                                     :mismatch on-protocol-mismatch
                                     :name name
                                     :kind kind)))
    (when name
      (setf (gethash name (chord-host-sessions host)) session))
    (link-on-close link (lambda (reason) (note-link-close session reason)))
    (link-receive link (lambda (frame) (ingest-frame session frame)))
    (link-send link (hello-frame host))
    session))

(defun host-accept (host link &key principal on-protocol-mismatch name (kind "host"))
  (attach-session host link :principal principal :on-protocol-mismatch on-protocol-mismatch
                  :name name :kind kind))

(defun host-connect (host link &key principal on-protocol-mismatch name)
  (attach-session host link :principal principal :on-protocol-mismatch on-protocol-mismatch
                  :name name :kind "client"))

(defun host-close (host)
  (setf *live-hosts* (remove host *live-hosts*))
  (dolist (object (chord-host-order host))
    (unless (string= (chord-object-status object) "released")
      (dispose-object host object)))
  host)
