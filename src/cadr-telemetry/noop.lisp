(in-package #:cadr-telemetry)

(define-condition telemetry-rejection (error)
  ((value :initarg :value :reader telemetry-rejection-value))
  (:report
   (lambda (condition stream)
     (format stream "Telemetry rejection: ~S"
             (telemetry-rejection-value condition)))))

(defstruct telemetry-counter
  (add-fn (constantly nil) :type function))

(defstruct telemetry-histogram
  (record-fn (constantly nil) :type function))

(defun telemetry-counter-add (counter value &optional attributes)
  (funcall (telemetry-counter-add-fn counter) value attributes))

(defun telemetry-histogram-record (histogram value &optional attributes context)
  (funcall (telemetry-histogram-record-fn histogram) value attributes context))

(defstruct (telemetry-status (:copier nil))
  (kind :ok)
  (error-p nil)
  (error-name "")
  (error-message ""))

(defun copy-telemetry-status (status)
  (make-telemetry-status
   :kind (telemetry-status-kind status)
   :error-p (telemetry-status-error-p status)
   :error-name (copy-seq (telemetry-status-error-name status))
   :error-message (copy-seq (telemetry-status-error-message status))))

(defstruct (telemetry-span (:copier nil))
  metrics
  propagation
  (start-fn (constantly nil) :type function)
  (add-link-fn (constantly nil) :type function)
  (add-event-fn (constantly nil) :type function)
  (set-attributes-fn (constantly nil) :type function)
  (set-status-fn (constantly nil) :type function)
  (counter-fn (constantly nil) :type function)
  (up-down-fn (constantly nil) :type function)
  (histogram-fn (constantly nil) :type function)
  (inject-fn (constantly nil) :type function)
  (extract-fn (constantly nil) :type function))

(defun copy-telemetry-span (span &key (metrics nil metrics-p))
  (make-telemetry-span
   :metrics (if metrics-p metrics (telemetry-span-metrics span))
   :propagation (telemetry-span-propagation span)
   :start-fn (telemetry-span-start-fn span)
   :add-link-fn (telemetry-span-add-link-fn span)
   :add-event-fn (telemetry-span-add-event-fn span)
   :set-attributes-fn (telemetry-span-set-attributes-fn span)
   :set-status-fn (telemetry-span-set-status-fn span)
   :counter-fn (telemetry-span-counter-fn span)
   :up-down-fn (telemetry-span-up-down-fn span)
   :histogram-fn (telemetry-span-histogram-fn span)
   :inject-fn (telemetry-span-inject-fn span)
   :extract-fn (telemetry-span-extract-fn span)))

(defun telemetry-start-span (span name callback &key attributes links)
  (funcall (telemetry-span-start-fn span)
           name attributes links callback))

(defun telemetry-add-link (span context &key attributes)
  (funcall (telemetry-span-add-link-fn span) context attributes))

(defun telemetry-add-event (span name &optional attributes)
  (funcall (telemetry-span-add-event-fn span) name attributes))

(defun telemetry-set-attributes (span attributes)
  (funcall (telemetry-span-set-attributes-fn span) attributes))

(defun telemetry-set-status (span &key (kind :ok) error-name error-message)
  (funcall (telemetry-span-set-status-fn span)
           (make-telemetry-status
            :kind kind
            :error-p (and (or error-name error-message) t)
            :error-name (or error-name "")
            :error-message (or error-message ""))))

(defun telemetry-counter (metrics name &key description unit)
  (funcall (telemetry-span-counter-fn metrics) name description unit))

(defun telemetry-up-down-counter (metrics name &key description unit)
  (funcall (telemetry-span-up-down-fn metrics) name description unit))

(defun telemetry-histogram (metrics name &key description unit boundaries)
  (funcall (telemetry-span-histogram-fn metrics)
           name description unit boundaries))

(defun telemetry-inject (propagation context)
  (funcall (telemetry-span-inject-fn propagation) context))

(defun telemetry-extract (propagation carrier)
  (funcall (telemetry-span-extract-fn propagation) carrier))

(defvar *noop-counter*
  (make-telemetry-counter
   :add-fn (lambda (value attributes)
             (declare (ignore value attributes))
             nil)))

(defvar *noop-up-down-counter*
  (make-telemetry-counter
   :add-fn (lambda (value attributes)
             (declare (ignore value attributes))
             nil)))

(defvar *noop-histogram*
  (make-telemetry-histogram
   :record-fn (lambda (value attributes context)
                (declare (ignore value attributes context))
                nil)))

(defvar *noop-telemetry-metrics*
  (make-telemetry-span
   :counter-fn (lambda (name description unit)
                 (declare (ignore name description unit))
                 *noop-counter*)
   :up-down-fn (lambda (name description unit)
                 (declare (ignore name description unit))
                 *noop-up-down-counter*)
   :histogram-fn (lambda (name description unit boundaries)
                   (declare (ignore name description unit boundaries))
                   *noop-histogram*)))

(defvar *noop-telemetry-context* nil)

(defvar *noop-telemetry-propagation*
  (make-telemetry-span
   :inject-fn (lambda (context) (declare (ignore context)) nil)
   :extract-fn (lambda (carrier)
                 (declare (ignore carrier))
                 *noop-telemetry-context*)))

(setf *noop-telemetry-context*
      (let ((span (make-telemetry-span
                   :metrics *noop-telemetry-metrics*
                   :propagation *noop-telemetry-propagation*)))
        (setf (telemetry-span-start-fn span)
              (lambda (name attributes links callback)
                (declare (ignore name attributes links))
                (funcall callback span))
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

(setf (telemetry-span-extract-fn *noop-telemetry-propagation*)
      (lambda (carrier)
        (declare (ignore carrier))
        *noop-telemetry-context*))
