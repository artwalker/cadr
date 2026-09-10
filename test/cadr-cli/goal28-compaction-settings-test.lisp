(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defun goal28-compaction-cut-entries ()
  (flet ((message-entry (characters)
           (cadr-agent::make-session-entry
            :type :message
            :message
            (cadr-ai:make-user-message
             :content
             (make-string characters
                          :initial-element #\u)))))
    (list
     (message-entry 40)
     (message-entry 40)
     (message-entry 40))))

(defun goal28-fresh-agent ()
  (cadr-agent:make-agent :provider nil :model nil))

(test goal28-compaction-token-settings-reach-agent-slots
  (let ((entries (goal28-compaction-cut-entries)))
    (let* ((manager (cadr-cli::make-memory-settings-manager))
           (agent (goal28-fresh-agent)))
      (cadr-cli::sync-agent-settings-from-manager
       agent manager)
      (is (eq t (cadr-agent::agent-auto-compact-p agent)))
      (is (= 20000
             (cadr-agent::agent-compaction-keep-recent-tokens
              agent)))
      (is (= 16384
             (cadr-agent::agent-compaction-reserve-tokens
              agent)))
      (is (null
           (cadr-agent::compaction-cut-point
            entries
            (cadr-agent::agent-compaction-keep-recent-tokens
             agent)))))
    (with-test-directory (root)
      (let* ((global
               (merge-pathnames "settings.json" root))
             (_
               (write-text
                global
                "{\"compaction\":{\"keepRecentTokens\":5,\"reserveTokens\":7,\"enabled\":false}}"))
             (manager
               (cadr-cli::make-settings-manager
                :global-path global))
             (agent (goal28-fresh-agent)))
        (declare (ignore _))
        (cadr-cli::sync-agent-settings-from-manager
         agent manager)
        (is (null (cadr-agent::agent-auto-compact-p agent)))
        (is (= 5
               (cadr-agent::agent-compaction-keep-recent-tokens
                agent)))
        (is (= 7
               (cadr-agent::agent-compaction-reserve-tokens
                agent)))
        (is (= 2
               (cadr-agent::compaction-cut-point
                entries
                (cadr-agent::agent-compaction-keep-recent-tokens
                 agent))))))
    (let* ((settings
             (cadr-cli::make-memory-sdk-settings-manager))
           (agent (goal28-fresh-agent)))
      (cadr-cli::sdk-apply-agent-settings agent settings)
      (is (eq t (cadr-agent::agent-auto-compact-p agent)))
      (is (= 20000
             (cadr-cli:sdk-settings-compaction-keep-recent-tokens
              settings)))
      (is (= 16384
             (cadr-cli:sdk-settings-compaction-reserve-tokens
              settings)))
      (is (= 20000
             (cadr-agent::agent-compaction-keep-recent-tokens
              agent)))
      (is (= 16384
             (cadr-agent::agent-compaction-reserve-tokens
              agent))))
    (let* ((settings
             (cadr-cli::make-memory-sdk-settings-manager
              (args
               "compaction"
               (args "keepRecentTokens" 111
                     "reserveTokens" 222
                     "enabled" t))))
           (agent (goal28-fresh-agent)))
      (cadr-cli::sdk-apply-agent-settings agent settings)
      (is (eq t (cadr-agent::agent-auto-compact-p agent)))
      (is (= 111
             (cadr-agent::agent-compaction-keep-recent-tokens
              agent)))
      (is (= 222
             (cadr-agent::agent-compaction-reserve-tokens
              agent))))))
