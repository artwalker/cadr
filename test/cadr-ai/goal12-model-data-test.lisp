(in-package #:cadr-ai/tests)

(in-suite cadr-ai-suite)

(test goal12-model-data-manifest-validates-the-entire-generated-catalog
  (let* ((directory (fixture-path "test/fixtures/catalogs/provider-data/"))
         (structure (cadr-ai::read-model-data-structure directory))
         (manifest
           (cadr-ai::parse-json
            (uiop:read-file-string
             (merge-pathnames ".manifest.json" directory)
             :external-format :utf-8))))
    (is (= 42 (hash-table-count structure)))
    (is (string=
         (cadr-ai::json-get manifest "structureHash")
         (cadr-ai::model-data-structure-hash structure)))
    (is-true (cadr-ai::validate-model-data-directory structure directory))))

(test goal12-model-data-validator-rejects-a-stale-provider-file
  (let* ((source (fixture-path "test/fixtures/catalogs/provider-data/"))
         (structure (cadr-ai::read-model-data-structure source))
         (temporary
           (merge-pathnames
            (format nil "cadr-model-data-~A/" (cadr-ai:uuid-v7))
            (uiop:temporary-directory))))
    (ensure-directories-exist temporary)
    (unwind-protect
         (progn
           (dolist (path (uiop:directory-files source))
             (uiop:copy-file path
                             (merge-pathnames (file-namestring path) temporary)))
           (with-open-file
               (stream (merge-pathnames "openai.json" temporary)
                       :direction :output :if-exists :append
                       :external-format :utf-8)
             (write-char #\Space stream))
           (signals error
             (cadr-ai::validate-model-data-directory structure temporary)))
      (uiop:delete-directory-tree temporary :validate t :if-does-not-exist :ignore))))

(test goal26-published-catalog-drops-retired-ids-and-prices-glm-4-6v
  ;; Locked to @earendil-works/pi-ai@1.4.0
  ;; sha256 b40e2ba8bb6fc332908f8b96e837dc2d1fdfb45eb9cd382f5aed111462981e3c
  ;; chat rows in dist/providers/data.
  (dolist (entry
           '((:baseten "moonshotai/Kimi-K2.6")
             (:together "MiniMaxAI/MiniMax-M2.7")
             (:github-copilot "claude-opus-4.7")
             (:github-copilot "gpt-5.4")
             (:github-copilot "gpt-5.5")
             (:openrouter "deepseek/deepseek-r1")))
    (signals cadr-ai:configuration-error
      (cadr-ai:find-model-metadata (first entry) (second entry))))
  (is (cadr-ai:find-model-metadata
       :vercel-ai-gateway "deepseek/deepseek-r1"))
  (let ((model
          (cadr-ai:find-model-metadata :zai-coding-cn "glm-4.6v")))
    (is (not (null model)))
    (is (= 0.05d0 (cadr-ai:model-metadata-cache-read-price model)))
    (is (= 0.3d0 (cadr-ai:model-metadata-input-price model)))
    (is (= 0.9d0 (cadr-ai:model-metadata-output-price model)))))

(test goal12-models-dev-effort-options-map-only-supported-thinking-levels
  (is (equal
       '((:off . "none") (:minimal) (:low . "low") (:medium)
         (:high) (:xhigh) (:max . "max"))
       (cadr-ai::models-dev-effort-thinking-level-map
        '((:type :toggle)
          (:type :effort :values ("none" "low" "max" "default" nil))))))
  (is (null
       (cadr-ai::models-dev-effort-thinking-level-map
        '((:type :budget-tokens :min 128 :max 8192)))))
  (is (string= "2026-10-21T22:33:24.994Z"
               (cadr-ai::get-builtin-model-data-generated-at))))

(test g22-openrouter-thinking-level-map-matches-effort-and-mandatory
  (is (null (cadr-ai::openrouter-thinking-level-map nil)))
  (is (equal
       '((:off))
       (cadr-ai::openrouter-thinking-level-map
        '(:mandatory t :supported-efforts nil))))
  (let ((map
          (cadr-ai::openrouter-thinking-level-map
           '(:mandatory nil :supported-efforts ("none" "low" "high")))))
    (is (equal "none" (cdr (assoc :off map))))
    (is (equal "low" (cdr (assoc :low map))))))

(test goal12-test-image-generator-writes-a-self-contained-png
  (let ((path
          (merge-pathnames
           (format nil "cadr-red-circle-~A.png" (cadr-ai:uuid-v7))
           (uiop:temporary-directory))))
    (unwind-protect
         (progn
           (cadr-ai::write-red-circle-test-png path :width 200 :height 200)
           (with-open-file
               (stream path :direction :input
                       :element-type '(unsigned-byte 8))
             (let ((header (make-array 24 :element-type '(unsigned-byte 8))))
               (is (= 24 (read-sequence header stream)))
               (is (equalp #(137 80 78 71 13 10 26 10)
                           (subseq header 0 8)))
               (is (= 200
                      (logior (ash (aref header 16) 24)
                              (ash (aref header 17) 16)
                              (ash (aref header 18) 8)
                              (aref header 19))))
               (is (= 200
                      (logior (ash (aref header 20) 24)
                              (ash (aref header 21) 16)
                              (ash (aref header 22) 8)
                              (aref header 23)))))))
      (when (probe-file path) (delete-file path)))))
