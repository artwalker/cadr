(in-package #:cadr-ai)

;;; models.dev rows the pi generator at b73412a37 would emit for meta.
;;; That commit does not commit meta.json, so the rows are the tool-call
;;; models from the models.dev meta provider.

(defparameter *meta-model-specs*
  '(("muse-spark-1.1" "Muse Spark 1.1"
     1.25d0 4.25d0 0.15d0
     ("minimal" "low" "medium" "high" "xhigh"))
    ("muse-spark-1.2" "Muse Spark 1.2"
     1.25d0 4.25d0 0.15d0
     ("minimal" "low" "medium" "high" "xhigh"))
    ("muse-spark-1.2-contributor" "Muse Spark 1.2 Contributor"
     0.1d0 0.2d0 0.002d0
     ("minimal" "low" "medium" "high" "xhigh"))
    ("muse-spark-1.3" "Muse Spark 1.3"
     1.25d0 4.25d0 0.15d0
     ("minimal" "low" "medium" "high" "xhigh" "max"))
    ("muse-spark-1.3-contributor" "Muse Spark 1.3 Contributor"
     0.1d0 0.2d0 0.002d0
     ("minimal" "low" "medium" "high" "xhigh"))))

(defun register-meta-models ()
  (dolist (spec *meta-model-specs*)
    (destructuring-bind
        (id name input-price output-price cache-read-price efforts)
        spec
      (register-model-metadata
       (make-model-metadata
        :provider :meta
        :id id
        :name name
        :api :openai-responses
        :base-url "https://api.meta.ai/v1"
        :context-window 1048576
        :max-output-tokens 131072
        :supports-images-p t
        :supports-tools-p t
        :reasoning-p t
        :thinking-level-map
        (models-dev-effort-thinking-level-map
         (list (list :type :effort :values efforts)))
        :input-price input-price
        :output-price output-price
        :cache-read-price cache-read-price
        :cache-write-price 0d0)))))

(register-meta-models)
