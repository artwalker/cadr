(in-package #:cadr-cli/tests)

(in-suite cadr-cli-suite)

(defun goal20-selector-test-model (id)
  (cadr-ai:make-model
   :id id
   :name id
   :provider :faux
   :api :openai-responses
   :base-url "https://example.invalid"
   :max-tokens 1024))

(test goal20-session-haystack-is-computed-once
  (let* ((record
           (cadr-cli:make-session-search-record
            :id "abc123session"
            :path "/tmp/abc123session.jsonl"
            :cwd "/tmp/worktree"
            :all-messages-text "some text"
            :modified 1))
         (first (cadr-cli::search-record-haystack record))
         (second (cadr-cli::search-record-haystack record)))
    (is (eq first second))
    (is (search "abc123session" first))
    (is (search "some text" first))
    (is (search "/tmp/worktree" first))))

(test goal20-session-regex-filter-reuses-one-scanner
  (let* ((late
           (cadr-cli:make-session-search-record
            :id "late"
            :path "/tmp/late.jsonl"
            :name "Named"
            :all-messages-text "xxxx Brave"
            :modified 3))
         (early
           (cadr-cli:make-session-search-record
            :id "early"
            :path "/tmp/early.jsonl"
            :all-messages-text
            (format nil "node~%~% CVE brave")
            :modified 1)))
    (is (equal
         '("late" "early")
         (mapcar
          #'cadr-cli:session-search-record-id
          (cadr-cli:filter-and-sort-sessions
           (list late early)
           "re:\\bbrave\\b"))))))

(test goal20-model-selector-filters-only-when-query-changes
  (let* ((alpha
           (goal20-selector-test-model "alpha-1"))
         (beta
           (goal20-selector-test-model "beta-1"))
         (state
           (cadr-cli::make-model-selector-state
            :all-models (list alpha beta)
            :current-model alpha))
         (first
           (cadr-cli::model-selector-visible-models
            state))
         (second
           (cadr-cli::model-selector-visible-models
            state)))
    (is (eq first second))
    (is (= 2 (length first)))
    (cadr-cli::model-selector-set-query state "beta")
    (let ((filtered
            (cadr-cli::model-selector-visible-models
             state)))
      (is (= 1 (length filtered)))
      (is (string=
           "beta-1"
           (cadr-ai:model-id (first filtered))))
      (is
       (eq
        filtered
        (cadr-cli::model-selector-visible-models
         state))))))
