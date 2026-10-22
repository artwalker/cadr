(in-package #:cadr-ai/tests)

(in-suite cadr-ai-suite)

(defparameter *minimax-m31-flash-prices*
  '((:minimax 0.15d0 0.6d0 0.015d0 0d0
     "https://api.minimax.io/anthropic")
    (:minimax-cn 0.1494d0 0.5976d0 0.0149d0 0d0
     "https://api.minimaxi.com/anthropic")))

(defparameter *minimax-m31-flash-thinking-map*
  '((:high . "high")
    (:low . "low")
    (:max . "max")
    (:medium . "medium")
    (:minimal)
    (:off)
    (:xhigh . "xhigh")))

(defparameter *minimax-m31-flash-efforts*
  '((:low . "low")
    (:medium . "medium")
    (:high . "high")
    (:xhigh . "xhigh")
    (:max . "max")))

(defun minimax-m31-flash-metadata (provider)
  (cadr-ai:find-model-metadata provider "MiniMax-M3.1-Flash"))

(defun minimax-m31-flash-model (provider)
  (nth-value 1
             (cadr-ai:instantiate-provider
              provider
              :model-id "MiniMax-M3.1-Flash"
              :api-key "fixture-key")))

(defun minimax-m31-flash-payload (provider reasoning)
  (multiple-value-bind (adapter model)
      (cadr-ai:instantiate-provider
       provider
       :model-id "MiniMax-M3.1-Flash"
       :api-key "fixture-key")
    (request-spec-payload
     (build-request
      adapter model (sample-context)
      :stream-p t
      :reasoning reasoning
      :cache-retention :none))))

(test minimax-m31-flash-catalog-matches-published-v140
  (dolist (row *minimax-m31-flash-prices*)
    (destructuring-bind
        (provider input output cache-read cache-write base-url)
        row
      (let ((metadata (minimax-m31-flash-metadata provider)))
        (is (eq :anthropic-messages
                (cadr-ai:model-metadata-api metadata)))
        (is (string= "MiniMax-M3.1-Flash"
                     (cadr-ai:model-metadata-name metadata)))
        (is (string= base-url
                     (cadr-ai:model-metadata-base-url metadata)))
        (is (= 1000000
               (cadr-ai:model-metadata-context-window metadata)))
        (is (= 524288
               (cadr-ai:model-metadata-max-output-tokens metadata)))
        (is (eq t (cadr-ai:model-metadata-supports-images-p metadata)))
        (is (eq t (cadr-ai:model-metadata-supports-tools-p metadata)))
        (is (eq t (cadr-ai:model-metadata-reasoning-p metadata)))
        (is (equal *minimax-m31-flash-thinking-map*
                   (cadr-ai:model-metadata-thinking-level-map metadata)))
        (is (equal '(:force-adaptive-thinking t)
                   (cadr-ai:model-metadata-compat metadata)))
        (is (= input (cadr-ai:model-metadata-input-price metadata)))
        (is (= output (cadr-ai:model-metadata-output-price metadata)))
        (is (= cache-read
               (cadr-ai:model-metadata-cache-read-price metadata)))
        (is (= cache-write
               (cadr-ai:model-metadata-cache-write-price metadata)))
        (is (null (cadr-ai:model-metadata-cost-tiers metadata))))))
  (dolist (provider '(:minimax :minimax-cn))
    (dolist (id '("MiniMax-M2.7" "MiniMax-M2.7-highspeed" "MiniMax-M3"))
      (is (cadr-ai:find-model-metadata provider id)))
    (dolist (id '("MiniMax-M2" "MiniMax-M2.1" "MiniMax-M2.5"
                  "MiniMax-M2.5-highspeed"))
      (signals cadr-ai:configuration-error
        (cadr-ai:find-model-metadata provider id)))))

(test minimax-m31-flash-thinking-cannot-be-turned-off
  (dolist (provider '(:minimax :minimax-cn))
    (let ((model (minimax-m31-flash-model provider)))
      (is (equal '(:low :medium :high :xhigh :max)
                 (cadr-ai:supported-thinking-levels model)))
      (is (eq :low (cadr-ai:clamp-thinking-level model :off)))
      (is (eq :low (cadr-ai:clamp-thinking-level model :minimal)))
      (let ((payload (minimax-m31-flash-payload provider nil)))
        (is (not (cadr-ai::json-present-p payload "thinking")))
        (is (not (cadr-ai::json-present-p payload "output_config"))))
      (dolist (requested-and-effort '((:off . "high") (:minimal . "low")))
        (let* ((requested (car requested-and-effort))
               (payload (minimax-m31-flash-payload provider requested))
               (thinking (cadr-ai::json-get payload "thinking"))
               (output (cadr-ai::json-get payload "output_config")))
          (is (string= "adaptive"
                       (cadr-ai::json-get thinking "type")))
          (is (string= (cdr requested-and-effort)
                       (cadr-ai::json-get output "effort"))))))))

(test minimax-m31-flash-sends-effort-on-adaptive-thinking
  (dolist (provider '(:minimax :minimax-cn))
    (dolist (entry *minimax-m31-flash-efforts*)
      (let* ((payload (minimax-m31-flash-payload provider (car entry)))
             (thinking (cadr-ai::json-get payload "thinking")))
        (is (json-equal-p
             (cadr-ai::json-object
              "type" "adaptive"
              "display" "summarized")
             thinking))
        (is (json-equal-p
             (cadr-ai::json-object "effort" (cdr entry))
             (cadr-ai::json-get payload "output_config")))))))
