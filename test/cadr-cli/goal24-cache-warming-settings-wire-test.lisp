(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

;;; Settings UI cacheWarming drives live warmer get-mode (Goal 24 wire).
;;; Locks pi@13cbf77df settings-manager getCacheWarmingMode → CacheWarmer.

(test goal24-settings-mode-drives-live-warmer-get-mode
  (let* ((settings (cadr-cli::make-memory-settings-manager))
         (warmer
           (cadr-cli:make-live-cache-warmer
            settings
            (lambda () nil)
            (lambda () nil)
            (lambda (&rest args)
              (declare (ignore args))
              nil))))
    (is (string= "streaming" (cadr-cli::cache-warmer-mode warmer)))
    (cadr-cli::settings-set-cache-warming-mode settings "off")
    (is (string= "off" (cadr-cli::cache-warmer-mode warmer)))
    (is
     (equal
      (cadr-cli:cache-warming-status-reason
       (cadr-cli:cache-warmer-status warmer))
      "cache warming disabled"))
    (cadr-cli::settings-set-cache-warming-mode settings "idle")
    (is (string= "idle" (cadr-cli::cache-warmer-mode warmer)))
    (is (string= "idle"
                 (cadr-cli::%read-cache-warming-mode settings)))
    (is (string= "streaming"
                 (cadr-cli::%read-cache-warming-mode nil)))))

(test goal24-settings-ui-still-exposes-cache-warming
  (let* ((manager (cadr-cli::make-memory-settings-manager))
         (model
           (cadr-ai:make-model
            :id "m"
            :name "m"
            :provider :anthropic
            :api :anthropic-messages))
         (agent
           (cadr-agent:make-agent
            :provider nil :model model))
         (state
           (cadr-cli::make-cli-settings-selector-state
            manager agent
            (cadr-cli::make-resource-snapshot)
            :supports-images-p nil))
         (options
           (cadr-cli::settings-selector-state-options state))
         (row
           (find "cache-warming-mode" options
                 :key #'cadr-cli::settings-option-id
                 :test #'string=)))
    (is (not (null row)))
    (is (string= "Cache warming"
                 (cadr-cli::settings-option-label row)))
    (is (equal '("off" "streaming" "idle")
               (cadr-cli::settings-option-values row)))
    (funcall
     (cadr-cli::settings-selector-state-change-callback state)
     "cache-warming-mode" "off")
    (is (string= "off"
                 (cadr-cli::settings-cache-warming-mode
                  manager)))
    (is (string= "off"
                 (cadr-cli::%read-cache-warming-mode
                  manager)))))
