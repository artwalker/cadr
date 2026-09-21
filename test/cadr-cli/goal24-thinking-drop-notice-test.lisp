(in-package #:cadr-cli/tests)

(in-suite cadr-cli-suite)

(defun goal24-assistant-with-thinking-drops (count)
  (cadr-ai:make-assistant-message
   :api :anthropic-messages
   :provider :anthropic
   :model "claude-test"
   :stop-reason :stop
   :diagnostics
   (list
    (cadr-ai:make-assistant-message-diagnostic
     :type :anthropic-input-transformations
     :details
     (list
      :transformations
      (loop repeat count
            collect
            (list :type "thinking_dropped"
                  :path "/messages/0"
                  :reason "over limit")))))))

(defun goal24-warning-texts (state)
  (mapcar
   #'cadr-cli::tui-entry-text
   (remove
    :warning
    (cadr-cli::tui-state-entries state)
    :key #'cadr-cli::tui-entry-type
    :test-not #'eq)))

(test goal24-count-dropped-thinking-blocks-counts-thinking-dropped
  (is (= 0
         (cadr-cli::count-dropped-thinking-blocks
          (cadr-ai:make-assistant-message
           :api :anthropic-messages
           :provider :anthropic
           :model "claude-test"
           :stop-reason :stop))))
  (is (= 3
         (cadr-cli::count-dropped-thinking-blocks
          (goal24-assistant-with-thinking-drops 3))))
  (is (= 1
         (cadr-cli::count-dropped-thinking-blocks
          (cadr-ai:make-assistant-message
           :api :anthropic-messages
           :provider :anthropic
           :model "claude-test"
           :stop-reason :stop
           :diagnostics
           (list
            (cadr-ai:make-assistant-message-diagnostic
             :type :anthropic-input-transformations
             :details
             (list
              :transformations
              (list
               (list :type :thinking-dropped
                     :path "/messages/0"
                     :reason "keyword")
               (list :type "other"
                     :path "/messages/1"
                     :reason "ignored"))))))))))

(test goal24-thinking-drop-notice-text-matches-pin-copy
  (is (string=
       "Anthropic dropped 1 thinking block (details in session)"
       (cadr-cli::thinking-drop-notice-text 1)))
  (is (string=
       "Anthropic dropped 3 thinking blocks (details in session)"
       (cadr-cli::thinking-drop-notice-text 3))))

(test goal24-maybe-show-thinking-drop-notice-dedupes-and-gates
  (let ((state
          (cadr-cli::make-tui-state
           :show-cache-miss-notices-p t)))
    (cadr-cli::maybe-show-thinking-drop-notice
     state
     (goal24-assistant-with-thinking-drops 2))
    (is (equal
         '("Anthropic dropped 2 thinking blocks (details in session)")
         (goal24-warning-texts state)))
    (is (= 2 (cadr-cli::tui-state-last-thinking-drop-count state)))
    (cadr-cli::maybe-show-thinking-drop-notice
     state
     (goal24-assistant-with-thinking-drops 2))
    (is (equal
         '("Anthropic dropped 2 thinking blocks (details in session)")
         (goal24-warning-texts state)))
    (cadr-cli::maybe-show-thinking-drop-notice
     state
     (goal24-assistant-with-thinking-drops 3))
    (is (equal
         '("Anthropic dropped 2 thinking blocks (details in session)"
           "Anthropic dropped 3 thinking blocks (details in session)")
         (goal24-warning-texts state)))
    (is (= 3 (cadr-cli::tui-state-last-thinking-drop-count state)))
    (cadr-cli::maybe-show-thinking-drop-notice
     state
     (cadr-ai:make-assistant-message
      :api :anthropic-messages
      :provider :anthropic
      :model "claude-test"
      :stop-reason :stop))
    (is (= 0 (cadr-cli::tui-state-last-thinking-drop-count state)))
    (is (= 2 (length (goal24-warning-texts state)))))
  (let ((state (cadr-cli::make-tui-state)))
    (cadr-cli::maybe-show-thinking-drop-notice
     state
     (goal24-assistant-with-thinking-drops 4))
    (is (null (goal24-warning-texts state)))
    (is (= 4 (cadr-cli::tui-state-last-thinking-drop-count state)))))
