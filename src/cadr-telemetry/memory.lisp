(in-package #:cadr-telemetry)

(defstruct memory-event
  name
  time-ms
  attributes)

(defstruct memory-link
  context
  attributes)

(defstruct memory-span
  started-ms
  clock
  ended-ms
  id
  parent-id
  context
  parent-context
  (links nil)
  name
  (attributes nil)
  (events nil)
  (status (make-telemetry-status))
  (explicit-p nil)
  (settled-p nil)
  end-sequence)

(defstruct memory-parent
  context
  local-id
  span)

(defstruct memory-measurement
  interval-ms
  kind
  name
  description
  unit
  boundaries
  value
  attributes
  context)

(defstruct memory-state
  (lock (sb-thread:make-mutex :name "telemetry"))
  (carriers (make-hash-table :test 'eq :weakness :key))
  scope
  (spans nil)
  (measurements nil)
  (next-span-id 1)
  (next-end-sequence 1)
  metrics
  propagation)

(defstruct (in-memory-telemetry
            (:include telemetry-span)
            (:constructor %make-in-memory-telemetry))
  state)

(defstruct recorded-telemetry-event
  name
  attributes)

(defstruct recorded-telemetry-link
  context
  attributes)

(defstruct recorded-telemetry-span
  id
  parent-id
  context
  parent-context
  links
  name
  attributes
  events
  status
  settled
  end-sequence)

(defstruct recorded-measurement
  kind
  name
  description
  unit
  boundaries
  value
  attributes
  context)

(defstruct stored-event
  name
  time-ms
  attributes)

(defstruct stored-link
  trace-id
  span-id
  attributes)

(defstruct stored-span
  id
  trace-id
  parent-id
  name
  started-ms
  ended-ms
  attributes
  events
  links
  status)

(defstruct stored-trace
  id
  spans)

(defstruct stored-metric
  interval-ms
  name
  kind
  unit
  attributes
  count
  sum
  min
  max)

(defun condition-error-name (condition)
  (if (typep condition 'simple-condition)
      "Error"
      (symbol-name (type-of condition))))

(defun condition-error-message (condition)
  (princ-to-string condition))

(defun call-span-callback (record callback span)
  (handler-bind
      ((error
        (lambda (condition)
          (unless (memory-span-explicit-p record)
            (setf (memory-span-status record)
                  (if (typep condition 'telemetry-rejection)
                      (make-telemetry-status :kind :error)
                      (make-telemetry-status
                       :kind :error
                       :error-p t
                       :error-name (condition-error-name condition)
                       :error-message (condition-error-message condition))))))))
    (funcall callback span)))

(defun with-memory-lock (state function)
  (sb-thread:with-recursive-lock ((memory-state-lock state))
    (funcall function)))

(defun lookup-carrier (state context)
  (with-memory-lock
      state
    (lambda ()
      (let ((carrier (gethash context (memory-state-carriers state))))
        (when carrier
          (copy-carrier carrier))))))

(defun remember-carrier (state span carrier)
  (with-memory-lock
      state
    (lambda ()
      (setf (gethash span (memory-state-carriers state)) carrier))))

(defun copy-link-record (state context attributes)
  (let ((carrier (lookup-carrier state context)))
    (when carrier
      (make-memory-link
       :context carrier
       :attributes (copy-attributes attributes)))))

(defun local-span-id (scope state-scope span-text)
  (when (and (stringp scope) (string= scope state-scope) (stringp span-text))
    (multiple-value-bind (number position)
        (parse-integer span-text :junk-allowed t)
      (when (and number (= position (length span-text)))
        number))))

(defun make-span-carrier (state id parent)
  (list (cons "pi-memory-scope" (memory-state-scope state))
        (cons "pi-memory-span" (princ-to-string id))
        (cons "pi-memory-trace"
              (or (and parent
                       (carrier-value (memory-parent-context parent)
                                      "pi-memory-trace"))
                  (format nil "~A:~A" (memory-state-scope state) id)))))

(defun create-span (state parent name attributes links)
  (with-memory-lock
      state
    (lambda ()
      (let* ((id (memory-state-next-span-id state))
             (copied-links nil))
        (incf (memory-state-next-span-id state))
        (dolist (link links)
          (let ((copied (copy-link-record
                         state
                         (getf link :context)
                         (getf link :attributes))))
            (when copied
              (setf copied-links (append copied-links (list copied))))))
        (let ((record
                (make-memory-span
                 :started-ms (telemetry-wall-milliseconds)
                 :clock (telemetry-monotonic-milliseconds)
                 :id id
                 :parent-id (and parent (memory-parent-local-id parent))
                 :context (make-span-carrier state id parent)
                 :parent-context (and parent
                                      (copy-carrier
                                       (memory-parent-context parent)))
                 :links copied-links
                 :name name
                 :attributes (copy-attributes attributes))))
          (setf (memory-state-spans state)
                (append (memory-state-spans state) (list record)))
          record)))))

(defun settle-span (state record)
  (with-memory-lock
      state
    (lambda ()
      (unless (memory-span-settled-p record)
        (setf (memory-span-settled-p record) t
              (memory-span-ended-ms record)
              (+ (memory-span-started-ms record)
                 (- (telemetry-monotonic-milliseconds)
                    (memory-span-clock record)))
              (memory-span-end-sequence record)
              (memory-state-next-end-sequence state))
        (incf (memory-state-next-end-sequence state))))))

(defun inert-span (state)
  (let ((span (make-telemetry-span
               :metrics (memory-state-metrics state)
               :propagation (memory-state-propagation state))))
    (setf (telemetry-span-start-fn span)
          (lambda (name attributes links callback)
            (declare (ignore name attributes links))
            (funcall callback (inert-span state)))
          (telemetry-span-add-link-fn span)
          (lambda (context attributes)
            (declare (ignore context attributes))
            nil)
          (telemetry-span-add-event-fn span)
          (lambda (name attributes)
            (declare (ignore name attributes))
            nil)
          (telemetry-span-set-attributes-fn span)
          (lambda (attributes) (declare (ignore attributes)) nil)
          (telemetry-span-set-status-fn span)
          (lambda (status) (declare (ignore status)) nil))
    span))

(defun live-span (state record)
  (let ((span (make-telemetry-span
               :metrics (memory-state-metrics state)
               :propagation (memory-state-propagation state))))
    (remember-carrier state span (memory-span-context record))
    (setf (telemetry-span-start-fn span)
          (lambda (name attributes links callback)
            (start-recorded
             state
             (make-memory-parent
              :context (memory-span-context record)
              :local-id (memory-span-id record)
              :span record)
             name attributes links callback))
          (telemetry-span-add-link-fn span)
          (lambda (context attributes)
            (with-memory-lock
                state
              (lambda ()
                (unless (memory-span-settled-p record)
                  (let ((copied (copy-link-record state context attributes)))
                    (when copied
                      (setf (memory-span-links record)
                            (append (memory-span-links record)
                                    (list copied)))))))))
          (telemetry-span-add-event-fn span)
          (lambda (name attributes)
            (let ((time (- (telemetry-monotonic-milliseconds)
                           (memory-span-clock record))))
              (with-memory-lock
                  state
                (lambda ()
                  (unless (memory-span-settled-p record)
                    (setf (memory-span-events record)
                          (append (memory-span-events record)
                                  (list (make-memory-event
                                         :name name
                                         :time-ms time
                                         :attributes (copy-attributes attributes))))))))))
          (telemetry-span-set-attributes-fn span)
          (lambda (attributes)
            (with-memory-lock
                state
              (lambda ()
                (unless (memory-span-settled-p record)
                  (setf (memory-span-attributes record)
                        (merge-attributes (memory-span-attributes record)
                                          attributes))))))
          (telemetry-span-set-status-fn span)
          (lambda (status)
            (with-memory-lock
                state
              (lambda ()
                (unless (memory-span-settled-p record)
                  (setf (memory-span-status record)
                        (copy-telemetry-status status)
                        (memory-span-explicit-p record)
                        t))))))
    span))

(defun start-recorded (state parent name attributes links callback)
  (when (and parent
             (memory-parent-span parent)
             (memory-span-settled-p (memory-parent-span parent)))
    (return-from start-recorded
      (funcall callback (inert-span state))))
  (let* ((record (create-span state parent name attributes links))
         (span (live-span state record)))
    (unwind-protect
         (call-span-callback record callback span)
      (settle-span state record))))

(defun start-from-parent (state parent name attributes links callback)
  (start-recorded state parent name attributes links callback))

(defun make-recorder (state kind name description unit boundaries)
  (let ((description (and (stringp description) (copy-seq description)))
        (unit (and (stringp unit) (copy-seq unit)))
        (copied-boundaries
          (when (and (string= kind "histogram") boundaries)
            (copy-list boundaries))))
    (lambda (value attributes &optional context)
      (let ((carrier (when context (lookup-carrier state context)))
            (interval (* 10000 (floor (telemetry-wall-milliseconds) 10000))))
        (with-memory-lock
            state
          (lambda ()
            (setf (memory-state-measurements state)
                  (append (memory-state-measurements state)
                          (list (make-memory-measurement
                                 :interval-ms interval
                                 :kind kind
                                 :name name
                                 :description description
                                 :unit unit
                                 :boundaries copied-boundaries
                                 :value value
                                 :attributes (copy-attributes attributes)
                                 :context (and carrier
                                               (copy-carrier carrier))))))))))))

(defun install-instruments (state root)
  (setf (telemetry-span-counter-fn root)
        (lambda (name description unit)
          (make-telemetry-counter
           :add-fn (make-recorder state "counter" name description unit nil)))
        (telemetry-span-up-down-fn root)
        (lambda (name description unit)
          (make-telemetry-counter
           :add-fn (make-recorder state "upDownCounter" name description unit nil)))
        (telemetry-span-histogram-fn root)
        (lambda (name description unit boundaries)
          (make-telemetry-histogram
           :record-fn (make-recorder state "histogram" name description unit boundaries)))))

(defun extract-parent (state root carrier)
  (let ((scope (and (listp carrier) (carrier-value carrier "pi-memory-scope")))
        (span-text (and (listp carrier) (carrier-value carrier "pi-memory-span")))
        (trace (and (listp carrier) (carrier-value carrier "pi-memory-trace"))))
    (unless (and (stringp scope) (stringp span-text) (stringp trace))
      (return-from extract-parent root))
    (let* ((context (list (cons "pi-memory-scope" (copy-seq scope))
                          (cons "pi-memory-span" (copy-seq span-text))
                          (cons "pi-memory-trace" (copy-seq trace))))
           (parent (make-memory-parent
                    :context context
                    :local-id (local-span-id scope
                                             (memory-state-scope state)
                                             span-text)))
           (extracted
             (make-telemetry-span
              :metrics root
              :propagation root
              :start-fn
              (lambda (name attributes links callback)
                (start-from-parent state parent name attributes links callback))
              :inject-fn (telemetry-span-inject-fn root)
              :extract-fn (telemetry-span-extract-fn root))))
      (remember-carrier state extracted context)
      extracted)))

(defun make-in-memory-telemetry ()
  (let* ((state (make-memory-state :scope (uuid-v4)))
         (root (%make-in-memory-telemetry :state state)))
    (setf (memory-state-metrics state) root
          (memory-state-propagation state) root
          (telemetry-span-metrics root) root
          (telemetry-span-propagation root) root
          (telemetry-span-start-fn root)
          (lambda (name attributes links callback)
            (start-from-parent state nil name attributes links callback))
          (telemetry-span-inject-fn root)
          (lambda (context)
            (lookup-carrier state context))
          (telemetry-span-extract-fn root)
          (lambda (carrier)
            (extract-parent state root carrier)))
    (install-instruments state root)
    root))

(defun snapshot-status (status)
  (copy-telemetry-status status))

(defun snapshot-recorded-span (record)
  (make-recorded-telemetry-span
   :id (memory-span-id record)
   :parent-id (memory-span-parent-id record)
   :context (copy-carrier (memory-span-context record))
   :parent-context (and (memory-span-parent-context record)
                        (copy-carrier (memory-span-parent-context record)))
   :links (mapcar (lambda (link)
                    (make-recorded-telemetry-link
                     :context (copy-carrier (memory-link-context link))
                     :attributes (copy-attributes (memory-link-attributes link))))
                  (memory-span-links record))
   :name (memory-span-name record)
   :attributes (copy-attributes (memory-span-attributes record))
   :events (mapcar (lambda (event)
                     (make-recorded-telemetry-event
                      :name (memory-event-name event)
                      :attributes (copy-attributes (memory-event-attributes event))))
                   (memory-span-events record))
   :status (snapshot-status (memory-span-status record))
   :settled (memory-span-settled-p record)
   :end-sequence (memory-span-end-sequence record)))

(defun in-memory-telemetry-spans (context)
  (let ((state (in-memory-telemetry-state context)))
    (with-memory-lock
        state
      (lambda ()
        (mapcar #'snapshot-recorded-span
                (copy-list (memory-state-spans state)))))))

(defun snapshot-measurement (measurement)
  (make-recorded-measurement
   :kind (memory-measurement-kind measurement)
   :name (memory-measurement-name measurement)
   :description (memory-measurement-description measurement)
   :unit (memory-measurement-unit measurement)
   :boundaries (and (memory-measurement-boundaries measurement)
                    (copy-list (memory-measurement-boundaries measurement)))
   :value (memory-measurement-value measurement)
   :attributes (copy-attributes (memory-measurement-attributes measurement))
   :context (and (memory-measurement-context measurement)
                 (copy-carrier (memory-measurement-context measurement)))))

(defun in-memory-measurements (context)
  (let ((state (in-memory-telemetry-state context)))
    (with-memory-lock
        state
      (lambda ()
        (mapcar #'snapshot-measurement
                (copy-list (memory-state-measurements state)))))))

(defun stored-span-from (record)
  (make-stored-span
   :id (carrier-id (memory-span-context record))
   :trace-id (carrier-value (memory-span-context record) "pi-memory-trace")
   :parent-id (and (memory-span-parent-context record)
                   (carrier-id (memory-span-parent-context record)))
   :name (memory-span-name record)
   :started-ms (memory-span-started-ms record)
   :ended-ms (memory-span-ended-ms record)
   :attributes (copy-attributes (memory-span-attributes record))
   :events (mapcar (lambda (event)
                     (make-stored-event
                      :name (memory-event-name event)
                      :time-ms (memory-event-time-ms event)
                      :attributes (copy-attributes
                                   (memory-event-attributes event))))
                   (memory-span-events record))
   :links (mapcar (lambda (link)
                    (make-stored-link
                     :trace-id (carrier-value (memory-link-context link)
                                              "pi-memory-trace")
                     :span-id (carrier-id (memory-link-context link))
                     :attributes (copy-attributes
                                  (memory-link-attributes link))))
                  (memory-span-links record))
   :status (snapshot-status (memory-span-status record))))

(defun stored-spans (state)
  (let ((spans
          (with-memory-lock
              state
            (lambda ()
              (mapcar #'stored-span-from
                      (remove-if-not #'memory-span-settled-p
                                     (copy-list (memory-state-spans state))))))))
    (stable-sort
     spans
     (lambda (left right)
       (or (< (stored-span-started-ms left) (stored-span-started-ms right))
           (and (= (stored-span-started-ms left) (stored-span-started-ms right))
                (string< (stored-span-id left) (stored-span-id right))))))))

(defun in-memory-telemetry-trace (context trace-id)
  (let ((spans (remove-if-not
                (lambda (span)
                  (string= (stored-span-trace-id span) trace-id))
                (stored-spans (in-memory-telemetry-state context)))))
    (when spans
      (make-stored-trace :id trace-id :spans spans))))

(defun trace-earliest (trace)
  (first (stored-trace-spans trace)))

(defun trace-matches-p (trace name attributes errors start-min start-max after)
  (let ((first (trace-earliest trace)))
    (and (or (null name) (string= (stored-span-name first) name))
         (or (null start-min) (>= (stored-span-started-ms first) start-min))
         (or (null start-max) (<= (stored-span-started-ms first) start-max))
         (or (null after)
             (< (stored-span-started-ms first) (first after))
             (and (= (stored-span-started-ms first) (first after))
                  (string> (stored-trace-id trace) (second after))))
         (or (not errors)
             (some (lambda (span)
                     (eq :error (telemetry-status-kind (stored-span-status span))))
                   (stored-trace-spans trace)))
         (or (null attributes)
             (some (lambda (span)
                     (attributes-match-p (stored-span-attributes span) attributes))
                   (stored-trace-spans trace))))))

(defun group-traces (spans)
  (let ((order nil)
        (groups (make-hash-table :test #'equal)))
    (dolist (span spans)
      (let ((trace (gethash (stored-span-trace-id span) groups)))
        (unless trace
          (setf trace (make-stored-trace
                       :id (stored-span-trace-id span)
                       :spans nil))
          (setf (gethash (stored-span-trace-id span) groups) trace)
          (setf order (append order (list trace))))
        (setf (stored-trace-spans trace)
              (append (stored-trace-spans trace) (list span)))))
    order))

(defun in-memory-telemetry-find-traces
    (context &key name attributes errors start-min start-max limit cursor)
  (let* ((after (and cursor (parse-cursor cursor)))
         (matches
           (stable-sort
            (remove-if-not
             (lambda (trace)
               (trace-matches-p trace name attributes errors
                                start-min start-max after))
             (group-traces
              (stored-spans (in-memory-telemetry-state context))))
            (lambda (left right)
              (let ((left-start (stored-span-started-ms (trace-earliest left)))
                    (right-start (stored-span-started-ms (trace-earliest right))))
                (or (> left-start right-start)
                    (and (= left-start right-start)
                         (string< (stored-trace-id left)
                                  (stored-trace-id right))))))))
         (page-size (or limit 20))
         (page (subseq matches 0 (min page-size (length matches)))))
    (values page
            (when (and page (> (length matches) page-size))
              (let ((last (car (last page))))
                (json-cursor (stored-span-started-ms (trace-earliest last))
                             (stored-trace-id last)))))))

(defun in-memory-telemetry-find-metrics
    (context &key name start-min start-max attributes)
  (unless name
    (error "find-metrics requires a metric name"))
  (let ((state (in-memory-telemetry-state context)))
    (mapcar
     (lambda (measurement)
       (make-stored-metric
        :interval-ms (memory-measurement-interval-ms measurement)
        :name (memory-measurement-name measurement)
        :kind (memory-measurement-kind measurement)
        :unit (memory-measurement-unit measurement)
        :attributes (copy-attributes (memory-measurement-attributes measurement))
        :count 1
        :sum (memory-measurement-value measurement)
        :min (memory-measurement-value measurement)
        :max (memory-measurement-value measurement)))
     (with-memory-lock
         state
       (lambda ()
         (remove-if-not
          (lambda (measurement)
            (and (string= (memory-measurement-name measurement) name)
                 (or (null start-min)
                     (>= (memory-measurement-interval-ms measurement) start-min))
                 (or (null start-max)
                     (<= (memory-measurement-interval-ms measurement) start-max))
                 (attributes-match-p
                  (memory-measurement-attributes measurement)
                  attributes)))
          (copy-list (memory-state-measurements state))))))))
