(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(test cached-cli-model-registry-reuses-until-path-changes
  (with-test-directory (root)
    (cadr-cli::clear-cli-model-registry-cache)
    (let* ((agent (merge-pathnames "agent/" root))
           (models-path (merge-pathnames "models.json" agent))
           (other-path (merge-pathnames "other.json" agent))
           (auth-path (merge-pathnames "auth.json" agent)))
      (ensure-directories-exist agent)
      (write-json models-path (args))
      (write-json other-path (args))
      (write-json auth-path (args))
      (unwind-protect
           (let* ((credentials
                    (cadr-cli:make-file-auth-storage auth-path))
                  (first
                    (cadr-cli::cached-cli-model-registry
                     :path models-path
                     :credentials credentials))
                  (second
                    (cadr-cli::cached-cli-model-registry
                     :path models-path
                     :credentials credentials))
                  (third
                    (cadr-cli::cached-cli-model-registry
                     :path other-path
                     :credentials credentials)))
             (is (eq first second))
             (is (not (eq first third))))
        (cadr-cli::clear-cli-model-registry-cache)))))

(test print-cli-models-output-stable-when-registry-is-cached
  (with-test-directory (root)
    (cadr-cli::clear-cli-model-registry-cache)
    (let ((agent (merge-pathnames "agent/" root)))
      (ensure-directories-exist agent)
      (write-json (merge-pathnames "models.json" agent) (args))
      (write-json (merge-pathnames "auth.json" agent) (args))
      (sb-posix:setenv "CADR_CODING_AGENT_DIR" (namestring agent) 1)
      (unwind-protect
           (let ((first
                   (with-output-to-string (stream)
                     (cadr-cli::print-cli-models nil stream)))
                 (second
                   (with-output-to-string (stream)
                     (cadr-cli::print-cli-models nil stream))))
             (is (string= first second))
             (is (plusp (length first))))
        (sb-posix:unsetenv "CADR_CODING_AGENT_DIR")
        (cadr-cli::clear-cli-model-registry-cache)))))

(test model-registry-available-models-reuses-until-mtime-changes
  ;; Cached configured-p walk on the registry.  Same models.json /
  ;; auth.json write-dates reuse the list.  Callers get a copy.
  ;; Not intern.  Not FFI.
  (with-test-directory (root)
    (cadr-cli::clear-cli-model-registry-cache)
    (let* ((agent (merge-pathnames "agent/" root))
           (models-path (merge-pathnames "models.json" agent))
           (auth-path (merge-pathnames "auth.json" agent)))
      (ensure-directories-exist agent)
      (write-json models-path
                  (args "providers"
                        (args "deepseek"
                              (args "apiKey" "sk-test-key"))))
      (write-json auth-path (args))
      (let* ((registry
               (cadr-cli:make-model-registry
                :path models-path
                :credentials
                (cadr-cli:make-file-auth-storage auth-path)))
             (first
               (cadr-cli::model-registry-available-models registry))
             (cached
               (cadr-cli::model-registry-%available-models registry))
             (second
               (cadr-cli::model-registry-available-models registry)))
        (is (not (null first)))
        (is (not (null cached)))
        (is (not (eq first cached)))
        (is (equal first cached))
        (is (equal first second))
        (is (eq cached
                (cadr-cli::model-registry-%available-models registry)))
        (let ((old-key
                (cadr-cli::model-registry-%available-models-key
                 registry)))
          (sleep 1.1)
          (write-json auth-path (args))
          (let ((third
                  (cadr-cli::model-registry-available-models
                   registry)))
            (is (equal
                 (mapcar #'cadr-ai:model-id first)
                 (mapcar #'cadr-ai:model-id third)))
            (is (not
                 (equal
                  old-key
                  (cadr-cli::model-registry-%available-models-key
                   registry))))))))))
