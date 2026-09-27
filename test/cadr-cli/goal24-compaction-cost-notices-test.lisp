(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defun compaction-cost-notice-usage
    (&key (input 10)
       (output 20)
       (cache-read 30)
       (cache-write 40)
       (total-cost 0.125d0))
  (cadr-ai:make-usage
   :input input
   :output output
   :cache-read cache-read
   :cache-write cache-write
   :cost
   (cadr-ai:make-cost
    :input 0.01d0
    :output 0.02d0
    :cache-read 0.03d0
    :cache-write 0.065d0
    :total total-cost)))

(defun compaction-cost-notice-texts (state)
  (loop for entry in (cadr-cli::tui-state-entries state)
        when (eq (cadr-cli::tui-entry-type entry) :notice)
          collect (cadr-cli::tui-entry-text entry)))

(defun compaction-cost-notice-plain-text (text)
  (remove-if
   (lambda (char)
     (or (eql char #\Escape)
         (< (char-code char) 32)))
   text))

(test compaction-cost-notices-setting-off-skips
  (let ((state (cadr-cli::make-tui-state))
        (usage (compaction-cost-notice-usage)))
    (cadr-cli::add-compaction-cost-notice
     state :compaction usage :show-p nil)
    (is (null (compaction-cost-notice-texts state)))))

(test compaction-cost-notices-setting-on-shows-compaction
  (let ((state (cadr-cli::make-tui-state))
        (usage (compaction-cost-notice-usage)))
    (cadr-cli::add-compaction-cost-notice
     state :compaction usage :show-p t)
    (let ((texts (compaction-cost-notice-texts state)))
      (is (= 1 (length texts)))
      (let ((plain
              (compaction-cost-notice-plain-text
               (first texts))))
        (is (search "Compaction: 100 tokens billed" plain))
        (is (search "~$0.13" plain))))))

(test compaction-cost-notices-setting-on-shows-branch-summary
  (let ((state (cadr-cli::make-tui-state))
        (usage (compaction-cost-notice-usage)))
    (cadr-cli::add-compaction-cost-notice
     state :branch-summary usage :show-p t)
    (let ((texts (compaction-cost-notice-texts state)))
      (is (= 1 (length texts)))
      (let ((plain
              (compaction-cost-notice-plain-text
               (first texts))))
        (is (search
             "Branch summary: 100 tokens billed"
             plain))
        (is (search "~$0.13" plain))))))

(test compaction-cost-notices-tiny-cost-omits-dollar
  (let ((state (cadr-cli::make-tui-state))
        (usage
          (compaction-cost-notice-usage
           :total-cost 0.009d0)))
    (cadr-cli::add-compaction-cost-notice
     state :compaction usage :show-p t)
    (let ((texts (compaction-cost-notice-texts state)))
      (is (= 1 (length texts)))
      (let ((plain
              (compaction-cost-notice-plain-text
               (first texts))))
        (is (search "Compaction: 100 tokens billed" plain))
        (is (null (search "~$" plain)))))))

(test compaction-cost-notices-session-display-injects-markers
  (with-test-directory (root)
    (let* ((session
             (cadr-agent:create-session
              :directory root
              :cwd root
              :id "goal24-compaction-cost"))
           (root-id
             (cadr-agent:session-append-message
              session
              (cadr-ai:make-user-message
               :content "keep")))
           (usage (compaction-cost-notice-usage)))
      (cadr-agent:session-append-compaction
       session "compacted" (list root-id) root-id 1000
       :usage usage)
      (let ((items
              (cadr-cli::session-display-messages
               session)))
        (is (>= (length items) 2))
        (is
         (typep
          (first items)
          'cadr-agent:compaction-summary-agent-message))
        (is
         (typep
          (second items)
          'cadr-cli::compaction-cost-notice))
        (is
         (eq
          :compaction
          (cadr-cli::compaction-cost-notice-kind
           (second items)))))
      (let ((state (cadr-cli::make-tui-state)))
        (cadr-cli::reset-tui-messages
         state
         (cadr-cli::session-display-messages session)
         :show-cache-miss-notices-p t)
        (let ((texts (compaction-cost-notice-texts state)))
          (is (= 1 (length texts)))
          (is
           (search
            "Compaction: 100 tokens billed"
            (compaction-cost-notice-plain-text
             (first texts)))))))))
