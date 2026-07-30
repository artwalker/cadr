(in-package #:cadr-agent/tests)
(in-suite cadr-agent-suite)

(defun storage-user-entry (id parent-id text timestamp)
  (cadr-agent::make-session-entry
   :type :message
   :id id
   :parent-id parent-id
   :timestamp timestamp
   :message
   (cadr-ai:make-user-message
    :content text
    :timestamp timestamp)))

(defun storage-assistant-entry
    (id parent-id text timestamp
     &optional (usage (cadr-ai:make-usage)))
  (cadr-agent::make-session-entry
   :type :message
   :id id
   :parent-id parent-id
   :timestamp timestamp
   :message
   (cadr-ai:make-assistant-message
    :content
    (list
     (cadr-ai:make-text-content :text text))
    :api :openai-responses
    :provider :openai
    :model "mock"
    :usage usage
    :stop-reason :stop
    :timestamp timestamp)))

(test memory-session-storage-covers-leaf-label-stats-and-compaction-path
  (let* ((root
           (storage-user-entry
            "root" nil "one" 100))
         (assistant
           (storage-assistant-entry
            "assistant" "root" "two" 101
            (cadr-ai:make-usage
             :input 10
             :output 20
             :cache-read 30
             :cache-write 40
             :cost
             (cadr-ai:make-cost :total 1d0))))
         (initial (list root assistant))
         (storage
           (cadr-agent:make-memory-session-storage
            :metadata
            (cadr-agent:make-session-metadata
             :id "session-1"
             :created-at
             "2026-01-01T00:00:00.000Z")
            :entries initial)))
    (setf initial
          (nconc
           initial
           (list
            (storage-user-entry
             "outside" "assistant" "ignored" 102))))
    (is
     (equal
      '("root" "assistant")
      (mapcar
       #'cadr-agent:session-entry-id
       (cadr-agent:session-storage-entries
        storage))))
    (is
     (string=
      "assistant"
      (cadr-agent:session-storage-leaf-id
       storage)))
    (cadr-agent:session-storage-set-leaf-id
     storage nil)
    (is (null
         (cadr-agent:session-storage-leaf-id
          storage)))
    (is
     (eq
      :leaf
      (cadr-agent:session-entry-type
       (car
        (last
         (cadr-agent:session-storage-entries
          storage))))))
    (signals cadr-agent:session-error
      (cadr-agent:session-storage-set-leaf-id
       storage "missing"))
    (let ((label
            (cadr-agent::make-session-entry
             :type :label
             :id "label"
             :parent-id nil
             :timestamp 103
             :target-id "root"
             :label "checkpoint")))
      (cadr-agent:session-storage-append-entry
       storage label)
      (is
       (string=
        "checkpoint"
        (cadr-agent:session-storage-label
         storage "root"))))
    (let ((stats
            (cadr-agent:session-storage-stats
             storage)))
      (is (= 2 (getf stats :message-count)))
      (is (= 30 (getf stats :cached-tokens)))
      (is (= 50 (getf stats :uncached-tokens)))
      (is (= 100 (getf stats :total-tokens)))
      (is (= 1d0 (getf stats :cost-total))))
    (let ((branched
            (cadr-agent:make-memory-session-storage
             :entries
             (list
              root
              assistant
              (cadr-agent::make-session-entry
               :type :compaction
               :id "compaction"
               :parent-id "assistant"
               :timestamp 102
               :summary "summary"
               :first-kept-id "assistant"
               :tokens-before 100
               :retained-tail
               (list
                (cadr-agent::session-entry-message
                 assistant)))
              (storage-user-entry
               "after" "compaction" "after" 103)))))
      (is
       (equal
        '("compaction" "after")
        (mapcar
         #'cadr-agent:session-entry-id
         (cadr-agent:session-storage-path
          branched "after")))))))

(test jsonl-session-repository-creates-lists-forks-opens-and-deletes
  (with-session-directories (sessions cwd other-cwd)
    (let* ((environment
             (cadr-agent:make-node-execution-env
              :cwd cwd))
           (repository
             (cadr-agent:make-jsonl-session-repository
              :environment environment
              :sessions-root sessions))
           (source
             (cadr-agent:session-repository-create
              repository
              :id "source"
              :cwd cwd
              :metadata '(:profile "reviewer")))
           (source-metadata
             (cadr-agent:harness-session-metadata
              source)))
      (is
       (probe-file
        (cadr-agent:session-metadata-path
         source-metadata)))
      (is
       (search
        "--"
        (namestring
         (cadr-agent:session-metadata-path
          source-metadata))))
      (cadr-agent:harness-session-append-message
       source
       (cadr-ai:make-user-message
        :content "one"
        :timestamp 100))
        (cadr-agent:harness-session-append-message
         source
         (cadr-ai:make-assistant-message
          :content
          (list
           (cadr-ai:make-text-content :text "two"))
          :api :openai-responses
          :provider :openai
          :model "mock"
          :stop-reason :stop
          :timestamp 101))
        (let ((user-2
                (cadr-agent:harness-session-append-message
                 source
                 (cadr-ai:make-user-message
                  :content "three"
                  :timestamp 102))))
          (let ((fork
                  (cadr-agent:session-repository-fork
                   repository source-metadata
                   :id "fork"
                   :cwd other-cwd
                   :entry-id user-2)))
            (is
             (= 2
                (length
                 (cadr-agent:harness-session-entries
                  fork))))
            (is
             (string=
              (namestring
               (cadr-agent:session-metadata-path
                source-metadata))
              (cadr-agent:session-metadata-parent-session-path
               (cadr-agent:harness-session-metadata
                fork))))))
      (is
       (equal
        '("source")
        (mapcar
         #'cadr-agent:session-metadata-id
         (cadr-agent:session-repository-list
          repository :cwd cwd))))
      (is
       (= 3
          (length
           (cadr-agent:harness-session-entries
            (cadr-agent:session-repository-open
             repository source-metadata)))))
      (cadr-agent:session-repository-delete
       repository source-metadata)
      (is
       (not
        (probe-file
         (cadr-agent:session-metadata-path
          source-metadata))))
      (signals cadr-agent:session-error
        (cadr-agent:session-repository-open
         repository source-metadata)))))

(test in-memory-session-repository-preserves-metadata-and-fork-boundary
  (let* ((repository
           (cadr-agent:make-memory-session-repository))
         (source
           (cadr-agent:session-repository-create
            repository
            :id "source"
            :cwd "/tmp/source"
            :metadata '(:profile "reviewer")))
         (root
           (cadr-agent:harness-session-append-message
            source
            (cadr-ai:make-user-message
             :content "one"
             :timestamp 100))))
    (cadr-agent:harness-session-append-message
     source
     (cadr-ai:make-user-message
      :content "two"
      :timestamp 101))
    (let ((fork
            (cadr-agent:session-repository-fork
             repository
             (cadr-agent:harness-session-metadata source)
             :id "fork"
             :entry-id root
             :position :at)))
      (is
       (= 1
          (length
           (cadr-agent:harness-session-entries
            fork))))
      (is
       (equal
        '(:profile "reviewer")
        (cadr-agent:session-metadata-data
         (cadr-agent:harness-session-metadata
          fork)))))
    (cadr-agent:session-repository-delete
     repository
     (cadr-agent:harness-session-metadata source))
    (signals cadr-agent:session-error
      (cadr-agent:session-repository-open
       repository
       (cadr-agent:harness-session-metadata
        source)))))

(test harness-session-builds-branch-compaction-and-custom-context
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let ((environment
            (cadr-agent:make-node-execution-env
             :cwd cwd)))
      (dolist
          (storage
           (list
            (cadr-agent:make-memory-session-storage)
            (cadr-agent:create-jsonl-session-storage
             environment
             (merge-pathnames
              "harness.jsonl" sessions)
             :id "harness"
             :cwd cwd)))
        (let* ((session
             (cadr-agent:make-harness-session
              :storage storage))
           (root
             (cadr-agent:harness-session-append-message
              session
              (cadr-ai:make-user-message
               :content "one"
               :timestamp 100))))
      (cadr-agent:harness-session-append-model
       session "openai" "gpt-4.1")
      (cadr-agent:harness-session-append-thinking-level
       session "high")
      (cadr-agent:harness-session-append-active-tools
       session '("read" "bash"))
      (cadr-agent:harness-session-append-custom
       session "metadata" '(:text "hidden"))
      (cadr-agent:harness-session-append-custom-message
       session "notice" "visible" t)
      (let ((context
              (cadr-agent:harness-session-build-context
               session)))
        (is
         (string=
          "high"
          (getf context :thinking-level)))
        (is
         (equal
          '(:provider "openai"
            :model-id "gpt-4.1")
          (getf context :model)))
        (is
         (equal
          '("read" "bash")
          (getf context :active-tool-names)))
        (is
         (= 2
            (length
             (getf context :messages)))))
      (cadr-agent:harness-session-move-to
       session root
       :summary "branch summary")
      (let ((context
              (cadr-agent:harness-session-build-context
               session)))
        (is
         (= 2
            (length
             (getf context :messages)))))
      (let ((kept
              (cadr-agent:harness-session-append-message
               session
               (cadr-ai:make-user-message
                :content "kept"
                :timestamp 101))))
        (cadr-agent:harness-session-append-compaction
         session "summary" kept 1234
         :retained-tail
         (list
          (cadr-ai:make-user-message
           :content "kept"
           :timestamp 101)))
        (cadr-agent:harness-session-append-message
         session
         (cadr-ai:make-user-message
          :content "after"
          :timestamp 102))
        (is
         (= 3
            (length
             (getf
              (cadr-agent:harness-session-build-context
               session)
              :messages)))))
         (cadr-agent:harness-session-cleanup
           session))))))

(test jsonl-session-supports-root-branch-summary-reload
  (with-session-directories (sessions cwd other-cwd)
    (values other-cwd)
    (let* ((environment
             (cadr-agent:make-node-execution-env
              :cwd cwd))
           (repository
             (cadr-agent:make-jsonl-session-repository
              :environment environment
              :sessions-root sessions))
           (session
             (cadr-agent:session-repository-create
              repository
              :id "root-branch"
              :cwd cwd))
           (metadata
             (cadr-agent:harness-session-metadata
              session)))
      (cadr-agent:harness-session-move-to
       session nil
       :summary "root summary")
      (cadr-agent:harness-session-cleanup session)
      (let ((reopened
              (cadr-agent:session-repository-open
               repository metadata)))
        (is
         (string=
          "root"
          (cadr-agent:session-entry-from-id
           (find
            :branch-summary
            (cadr-agent:harness-session-entries
             reopened)
            :key #'cadr-agent:session-entry-type))))
        (cadr-agent:harness-session-cleanup
         reopened)))))
