(in-package #:cadr-ai)

(defstruct model-metadata
  (provider nil :type symbol)
  (id "" :type string)
  (name "" :type string)
  (api nil :type symbol)
  (base-url "" :type string)
  (context-window 0 :type (integer 0 *))
  (max-output-tokens 4096 :type (integer 1 *))
  (supports-images-p nil :type boolean)
  (supports-tools-p t :type boolean)
  (reasoning-p nil :type boolean)
  (thinking-level-map nil :type list)
  (headers nil :type list)
  (compat nil :type list)
  (input-price 0d0 :type double-float)
  (output-price 0d0 :type double-float)
  (cache-read-price 0d0 :type double-float)
  (cache-write-price 0d0 :type double-float))

(defparameter *model-catalog* (make-hash-table :test #'equal))

(defun model-catalog-key (provider id)
  (cons provider id))

(defun register-model-metadata (metadata)
  (setf (gethash
         (model-catalog-key
          (model-metadata-provider metadata)
          (model-metadata-id metadata))
         *model-catalog*)
        metadata)
  metadata)

(defun find-model-metadata (provider id)
  (or (gethash (model-catalog-key provider id) *model-catalog*)
      (error 'configuration-error
             :message
             (format nil "Unknown model: ~A/~A" provider id))))

(defun list-model-metadata (&optional provider)
  (sort
   (loop for metadata being the hash-values of *model-catalog*
         when (or (null provider)
                  (eq provider (model-metadata-provider metadata)))
           collect metadata)
   #'string<
   :key #'model-metadata-id))

(defun calculate-usage-cost (usage metadata)
  (flet ((charge (tokens price)
           (* (/ (coerce tokens 'double-float) 1000000d0)
              price)))
    (let* ((input
             (charge (usage-input usage)
                     (model-metadata-input-price metadata)))
           (output
             (charge (usage-output usage)
                     (model-metadata-output-price metadata)))
           (cache-read
             (charge (usage-cache-read usage)
                     (model-metadata-cache-read-price metadata)))
           (cache-write
             (charge (usage-cache-write usage)
                     (model-metadata-cache-write-price metadata))))
      (setf (usage-cost usage)
            (make-cost
             :input input
             :output output
             :cache-read cache-read
             :cache-write cache-write
             :total (+ input output cache-read cache-write)))))
  usage)

(defun register-generated-models (rows)
  (clrhash *model-catalog*)
  (dolist (row rows)
    (register-model-metadata
     (apply #'make-model-metadata row))))
