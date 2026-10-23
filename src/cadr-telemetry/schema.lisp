(in-package #:cadr-telemetry)

(defstruct telemetry-attribute-definition
  type
  description
  (required nil)
  values
  cardinality)

(defstruct telemetry-span-definition
  description
  parents
  start-attributes
  end-attributes
  events
  status)

(defstruct telemetry-metric-definition
  kind
  description
  unit
  boundaries
  attributes)

(defstruct telemetry-schema
  version
  spans
  metrics)

(defun define-telemetry-schema (schema)
  schema)

(defun schema-metric-definition (schemas name)
  (dolist (schema schemas)
    (let ((found (assoc name (telemetry-schema-metrics schema) :test #'string=)))
      (when found
        (return (cdr found))))))

(defun create-typed-metrics (metrics schemas)
  (lambda (kind name)
    (let ((definition (schema-metric-definition schemas name)))
      (ecase kind
        (:counter
         (telemetry-counter
          metrics name
          :description (and definition
                            (telemetry-metric-definition-description definition))
          :unit (and definition
                     (telemetry-metric-definition-unit definition))))
        (:up-down
         (telemetry-up-down-counter
          metrics name
          :description (and definition
                            (telemetry-metric-definition-description definition))
          :unit (and definition
                     (telemetry-metric-definition-unit definition))))
        (:histogram
         (telemetry-histogram
          metrics name
          :description (and definition
                            (telemetry-metric-definition-description definition))
          :unit (and definition
                     (telemetry-metric-definition-unit definition))
          :boundaries (and definition
                           (telemetry-metric-definition-boundaries definition))))))))

(defun typed-metrics-counter (typed name)
  (funcall typed :counter name))

(defun typed-metrics-up-down-counter (typed name)
  (funcall typed :up-down name))

(defun typed-metrics-histogram (typed name)
  (funcall typed :histogram name))

(defun create-typed-span-starter (parent schemas)
  (lambda (name attributes callback)
    (telemetry-start-span
     parent name
     (lambda (span)
       (funcall callback
                span
                (create-typed-span-starter span schemas)))
     :attributes attributes)))
