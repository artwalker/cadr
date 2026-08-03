(in-package #:cadr-ai)

(defstruct model-cost-tier
  (input-tokens-above 0 :type (integer 0 *))
  (input-price 0d0 :type double-float)
  (output-price 0d0 :type double-float)
  (cache-read-price 0d0 :type double-float)
  (cache-write-price 0d0 :type double-float))

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
  (cache-write-price 0d0 :type double-float)
  (cost-tiers nil :type list))

(defmethod print-object ((value model-metadata) stream)
  (print-unreadable-object (value stream :type t)
    (format stream ":provider ~A :id ~S :headers [REDACTED]"
            (model-metadata-provider value)
            (model-metadata-id value))))

(defparameter *model-catalog* (make-hash-table :test #'equal))
(defparameter *image-model-catalog*
  (make-hash-table :test #'equal))

;; Replaced by the generated catalog at load time. Keeping the generation stamp
;; in the image makes catalog provenance available without shipping fixtures.
(defparameter *generated-model-data-generated-at* nil)

(defun model-catalog-key (provider id)
  (cons provider id))

(defun register-image-model (model)
  (setf
   (gethash
    (model-catalog-key
     (image-model-provider model)
     (image-model-id model))
    *image-model-catalog*)
   model)
  model)

(defun find-image-model (provider id)
  (or
   (gethash
    (model-catalog-key provider id)
    *image-model-catalog*)
   (error 'configuration-error
          :message
          (format nil "Unknown image model: ~A/~A" provider id))))

(defun list-image-models (&optional provider)
  (sort
   (loop for model being the hash-values
           of *image-model-catalog*
         when
         (or (null provider)
             (eq provider (image-model-provider model)))
           collect model)
   #'string<
   :key #'image-model-id))

(defun register-generated-image-models (rows)
  (clrhash *image-model-catalog*)
  (dolist (row rows)
    (register-image-model
     (apply #'make-image-model row))))

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
  (let* ((request-input
           (+ (usage-input usage)
              (usage-cache-read usage)
              (usage-cache-write usage)))
         (tier
           (loop with best = nil
                 for candidate in
                 (model-metadata-cost-tiers metadata)
                 when
                 (and
                  (> request-input
                     (model-cost-tier-input-tokens-above candidate))
                  (or
                   (null best)
                   (>
                    (model-cost-tier-input-tokens-above candidate)
                    (model-cost-tier-input-tokens-above best))))
                   do (setf best candidate)
                 finally (return best)))
         (input-price
           (if tier
               (model-cost-tier-input-price tier)
               (model-metadata-input-price metadata)))
         (output-price
           (if tier
               (model-cost-tier-output-price tier)
               (model-metadata-output-price metadata)))
         (cache-read-price
           (if tier
               (model-cost-tier-cache-read-price tier)
               (model-metadata-cache-read-price metadata)))
         (cache-write-price
           (if tier
               (model-cost-tier-cache-write-price tier)
               (model-metadata-cache-write-price metadata))))
    (flet ((charge (tokens price)
           (* (/ (coerce tokens 'double-float) 1000000d0)
              price)))
      (let* ((input
             (charge (usage-input usage)
                     input-price))
           (output
             (charge (usage-output usage)
                     output-price))
           (cache-read
             (charge (usage-cache-read usage)
                     cache-read-price))
           (long-write
             (or (usage-cache-write-1h usage) 0))
           (short-write
             (- (usage-cache-write usage) long-write))
           (cache-write
             (+
              (charge short-write cache-write-price)
              (charge long-write (* 2d0 input-price)))))
        (setf (usage-cost usage)
              (make-cost
               :input input
               :output output
               :cache-read cache-read
               :cache-write cache-write
               :total (+ input output cache-read cache-write))))))
  usage)

(defun model-from-metadata (metadata)
  (make-model
   :id (model-metadata-id metadata)
   :name (model-metadata-name metadata)
   :provider (model-metadata-provider metadata)
   :api (model-metadata-api metadata)
   :base-url (model-metadata-base-url metadata)
   :max-tokens (model-metadata-max-output-tokens metadata)
   :context-window (model-metadata-context-window metadata)
   :supports-images-p (model-metadata-supports-images-p metadata)
   :supports-tools-p (model-metadata-supports-tools-p metadata)
   :reasoning-p (model-metadata-reasoning-p metadata)
   :thinking-level-map (model-metadata-thinking-level-map metadata)
   :headers (model-metadata-headers metadata)
   :compat (model-metadata-compat metadata)))

(defparameter +extended-thinking-levels+
  '(:off :minimal :low :medium :high :xhigh :max))

(defun supported-thinking-levels (model)
  (if (not (model-reasoning-p model))
      '(:off)
      (remove-if-not
       (lambda (level)
         (let ((entry
                 (assoc
                  level (model-thinking-level-map model))))
           (cond
             ((and entry (null (cdr entry))) nil)
             ((member level '(:xhigh :max))
              (and entry (not (null (cdr entry)))))
             (t t))))
       +extended-thinking-levels+)))

(defun clamp-thinking-level (model level)
  (let ((available (supported-thinking-levels model))
        (requested
          (position level +extended-thinking-levels+)))
    (cond
      ((member level available) level)
      ((null requested) (or (first available) :off))
      (t
       (or
        (loop for index from requested
              below (length +extended-thinking-levels+)
              for candidate =
              (nth index +extended-thinking-levels+)
              when (member candidate available)
                return candidate)
        (loop for index downfrom (1- requested) to 0
              for candidate =
              (nth index +extended-thinking-levels+)
              when (member candidate available)
                return candidate)
        (first available)
        :off)))))

(defun models-equal-p (left right)
  (and left right
       (string= (model-id left) (model-id right))
       (eq (model-provider left) (model-provider right))))

(defun round-model-cost (value)
  (/ (round (* value 1000000d0))
     1000000d0))

(defun apply-gpt-5-6-pricing-override (row)
  (when
      (member
       (getf row :provider)
       '(:openai :openai-codex :cloudflare-ai-gateway))
    (let ((prices
            (cond
              ((string= (getf row :id) "gpt-5.6-luna")
               '(0.2d0 1.2d0 0.02d0 0.25d0))
              ((string= (getf row :id) "gpt-5.6-terra")
               '(2d0 12d0 0.2d0 2.5d0)))))
      (when prices
        (destructuring-bind
            (input output cache-read cache-write)
            prices
          (setf
           (getf row :input-price) input
           (getf row :output-price) output
           (getf row :cache-read-price) cache-read
           (getf row :cache-write-price) cache-write
           (getf row :cost-tiers)
           (list
            (list
             :input-tokens-above 272000
             :input-price
             (round-model-cost (* input 2d0))
             :output-price
             (round-model-cost (* output 1.5d0))
             :cache-read-price
             (round-model-cost (* cache-read 2d0))
             :cache-write-price
             (round-model-cost (* cache-write 2d0)))))))))
  row)

(defun register-generated-models (rows)
  (clrhash *model-catalog*)
  (dolist (row rows)
    (let ((copy
            (apply-gpt-5-6-pricing-override
             (copy-list row))))
      (setf
       (getf copy :cost-tiers)
       (mapcar
        (lambda (tier)
          (if (typep tier 'model-cost-tier)
              tier
              (apply #'make-model-cost-tier tier)))
        (getf copy :cost-tiers)))
      (register-model-metadata
       (apply #'make-model-metadata copy)))))
