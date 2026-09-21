(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(test message-projections-preserve-zones-thinking-errors-and-padding
  (let ((assistant
          (cadr-cli:render-assistant-message-lines
           (list
            (list :type :thinking
                  :thinking "first")
            (list :type :thinking
                  :thinking "second")
            (list :type :text
                  :text "answer"))
           80
           :output-pad 1
           :thinking-visible-p nil
           :stop-reason :length)))
    (is (search
         cadr-cli::+osc-133-start+
         (first assistant)))
    (is (search
         cadr-cli::+osc-133-end+
         (car (last assistant))))
    (is (= 1
           (count-if
            (lambda (line)
              (search "Thinking..." line))
            assistant)))
    (is (some
         (lambda (line)
           (search " answer" line))
         assistant))
    (is (some
         (lambda (line)
           (search
            "Response was truncated before completion."
            line))
         assistant)))
  (let ((with-tool
          (cadr-cli:render-assistant-message-lines
           (list
            (list :type :text :text "call")
            (list :type :tool-call))
           80)))
    (is (not
         (search
          cadr-cli::+osc-133-start+
          (format nil "~{~A~^~%~}"
                  with-tool)))))
  (let ((user
          (cadr-cli:render-user-message-lines
           "hello" 20 :output-pad 0)))
    (is (= 3 (length user)))
    (is (string= "hello" (second user)))
    (is (search
         cadr-cli::+osc-133-final+
         (third user)))))

(test startup-input-and-status-lines-are-ordered-and-coalesced
  (let ((queue
          (cadr-cli:make-startup-input-queue)))
    (cadr-cli:queue-startup-input
     queue " early prompt ")
    (cadr-cli:queue-startup-input
     queue "second")
    (is (string=
         "early prompt"
         (cadr-cli:pop-startup-input queue)))
    (is (string=
         "second"
         (cadr-cli:pop-startup-input queue)))
    (is (null
         (cadr-cli:pop-startup-input queue))))
  (let ((log (cadr-cli:make-status-log)))
    (cadr-cli:status-log-show log "one")
    (cadr-cli:status-log-show log "two")
    (is (equal
         '((:status . "two"))
         (cadr-cli:status-log-entries log)))
    (cadr-cli:status-log-add-content log "other")
    (cadr-cli:status-log-show log "three")
    (is (equal
         '((:status . "two")
           (:content . "other")
           (:status . "three"))
         (cadr-cli:status-log-entries log))))
  (is
   (equal
    (list
     (make-string 20 :initial-element #\Space)
     (make-string 20 :initial-element #\Space))
    (cadr-cli::render-tui-status-indicator
     nil 20)))
  (is
   (equal
     (list
     ""
     (concatenate
      'string
      " ⠋ Retrying (1/3) in 1s..."
      (make-string 14 :initial-element #\Space)))
    (mapcar
     #'cadr-tui:strip-terminal-sequences
     (cadr-cli::render-tui-status-indicator
      "Retrying (1/3) in 1s..." 40)))))

(test anthropic-subscription-warning-is-provider-gated-disableable-and-once-only
  (let ((state
          (cadr-cli::make-anthropic-warning-state))
        (lookups 0))
    (is (search
         "billed per token"
         (cadr-cli::maybe-anthropic-subscription-warning
          state :anthropic
          (args)
          (lambda ()
            (incf lookups)
            "sk-ant-oat01-test"))))
    (is (null
         (cadr-cli::maybe-anthropic-subscription-warning
          state :anthropic
          (args)
          (lambda ()
            (incf lookups)
            "sk-ant-oat01-test"))))
    (is (= 1 lookups)))
  (let ((state
          (cadr-cli::make-anthropic-warning-state)))
    (is (search
         "billed per token"
         (cadr-cli::maybe-anthropic-subscription-warning
          state "anthropic"
          (args)
          (lambda () :oauth)))))
  (let ((state
          (cadr-cli::make-anthropic-warning-state))
        (lookups 0))
    (is (null
         (cadr-cli::maybe-anthropic-subscription-warning
          state :openai
          (args)
          (lambda ()
            (incf lookups)
            :oauth))))
    (is (= 0 lookups))
    (is (null
         (cadr-cli::maybe-anthropic-subscription-warning
          state :anthropic
          (args
           "warnings"
           (args "anthropicExtraUsage" nil))
          (lambda ()
            (incf lookups)
            :oauth))))
    (is (= 0 lookups))))

(defun session-record
    (id modified text
     &key name path parent-path cwd first-message
       (message-count 0))
  (cadr-cli:make-session-search-record
   :id id
   :path (or path
             (format nil "/tmp/~A.jsonl" id))
   :parent-path parent-path
   :name name
   :cwd cwd
   :first-message (or first-message text)
   :message-count message-count
   :modified modified
   :all-messages-text text))

(test session-search-supports-phrases-regex-relevance-names-and-invalid-input
  (let* ((late
           (session-record
            "late" 3 "xxxx Brave"
            :name "Named"))
         (early
           (session-record
            "early" 1
            (format nil "node~%~% CVE brave")))
         (other
           (session-record
            "other" 4 "bravery"
            :name "   "))
         (sessions
           (list late early other)))
    (is (equal
         '("early")
         (mapcar
          #'cadr-cli:session-search-record-id
          (cadr-cli:filter-and-sort-sessions
           sessions "\"node cve\""))))
    (is (equal
         '("late" "early")
         (mapcar
          #'cadr-cli:session-search-record-id
          (cadr-cli:filter-and-sort-sessions
           sessions "re:\\bbrave\\b"))))
    (is (equal
         '("other" "early" "late")
         (mapcar
          #'cadr-cli:session-search-record-id
          (cadr-cli:filter-and-sort-sessions
           sessions "\"brave\""
           :sort-mode :relevance))))
    (is (equal
         '("late")
         (mapcar
          #'cadr-cli:session-search-record-id
          (cadr-cli:filter-and-sort-sessions
           sessions ""
           :name-filter :named))))
    (is (null
         (cadr-cli:filter-and-sort-sessions
          sessions "re:(")))))

(test session-threading-canonicalizes-symlink-aliases-and-sorts-by-subtree
  (with-test-directory (root)
    (let* ((real
             (merge-pathnames "real/" root))
           (alias-a-name
             (merge-pathnames "a" root))
           (alias-b-name
             (merge-pathnames "b" root))
           (alias-a
             (uiop:ensure-directory-pathname
              alias-a-name))
           (alias-b
             (uiop:ensure-directory-pathname
              alias-b-name))
           (parent
             (merge-pathnames "parent.jsonl" real))
           (child
             (merge-pathnames "child.jsonl" real)))
      (write-text parent "parent")
      (write-text child "child")
      (sb-posix:symlink
       (namestring real)
       (namestring alias-a-name))
      (sb-posix:symlink
       (namestring real)
       (namestring alias-b-name))
      (let* ((parent-record
               (session-record
                "parent" 1 "parent"
                :path
                (merge-pathnames
                 "parent.jsonl" alias-b)))
             (child-record
               (session-record
                "child" 3 "child"
                :path
                (merge-pathnames
                 "child.jsonl" alias-b)
                :parent-path
                (merge-pathnames
                 "parent.jsonl" alias-a)))
             (threaded
               (cadr-cli:thread-session-records
                (list child-record
                      parent-record))))
        (is (= 0 (caar threaded)))
        (is (string=
             "parent"
             (cadr-cli:session-search-record-id
              (cdar threaded))))
        (is (= 1 (caadr threaded)))
        (is (string=
             "child"
             (cadr-cli:session-search-record-id
              (cdadr threaded))))))))

(test session-file-mutations-canonicalize-active-paths-and-persist-names
  (with-test-directory (root)
    (let* ((cwd root)
           (directory
             (merge-pathnames "sessions/" root))
           (session
             (cadr-agent:create-session
              :directory directory
              :cwd cwd))
           (path
             (cadr-agent:session-path session))
           (alias
             (merge-pathnames "active-alias.jsonl"
                              root)))
      (cadr-agent:session-append-message
       session
       (cadr-ai:make-assistant-message
        :content
        (list
         (cadr-ai:make-text-content
          :text "persist"))
        :api :openai-responses
        :provider :openai
        :model "mock"
        :stop-reason :stop))
      (cadr-agent:session-set-name
       session "Initial")
      #-win32
      (sb-posix:symlink
       (namestring path)
       (namestring alias))
      #-win32
      (signals cadr-cli::active-session-deletion-error
        (cadr-cli::delete-session-file
         path :active-path alias))
      (is (string=
           "Renamed"
           (cadr-cli::rename-session-at-path
            path "  Renamed  ")))
      (is (string=
           "Renamed"
           (cadr-agent:session-name
            (cadr-agent:load-session path))))
      (multiple-value-bind (ok method error)
          (cadr-cli::delete-session-file path)
        (is (eq t ok))
        (is (eq :unlink method))
        (is (null error)))
      (is (not (probe-file path))))))

(test session-selector-controller-preserves-delete-rename-load-and-hint-semantics
  (with-test-directory (root)
    (let* ((active
             (merge-pathnames "active.jsonl" root))
           (other
             (merge-pathnames "other.jsonl" root))
           (active-alias
             (merge-pathnames "active-alias.jsonl" root))
           (renames nil)
           (deletes nil)
           (selector
             (cadr-cli::make-session-selector-state
              :current-sessions
              (list
               (session-record
                "active" 2 "active"
                :name "Active"
                :path active)
               (session-record
                "other" 1 "other"
                :name "Old"
                :path other))
              :current-session-path active-alias
              :show-rename-hint-p t
              :rename-function
              (lambda (path name)
                (push (list path name) renames)
                name)
              :delete-function
              (lambda (path)
                (push path deletes)
                (values t :unlink nil)))))
      (write-text active "active")
      (write-text other "other")
      #-win32
      (sb-posix:symlink
       (namestring active)
       (namestring active-alias))
      (is (search
           "ctrl+r"
           (format nil "~{~A~^~%~}"
                   (cadr-cli::render-session-selector
                    selector 100))))
      (multiple-value-bind (action value handled-p)
          (cadr-cli::session-selector-handle-raw-input
           selector (string (code-char 4)))
        (is (eq :error action))
        (is (search "currently active" value))
        (is (eq t handled-p)))
      (setf (cadr-cli::session-selector-state-selected
             selector)
            1)
      (cadr-cli::session-selector-handle-event
       selector
       (cadr-tui:make-input-event
        :kind :text :text "query"))
      (multiple-value-bind (action value handled-p)
          (cadr-cli::session-selector-handle-raw-input
           selector
           (format nil "~C[127;5u" #\Escape))
        (declare (ignore value))
        (is (eq :changed action))
        (is (eq t handled-p))
        (is (null
             (cadr-cli::session-selector-state-confirming-delete-path
              selector))))
      (setf
       (cadr-cli::session-selector-state-query selector)
       ""
       (cadr-cli::session-selector-state-selected selector)
       1)
      (multiple-value-bind (action value handled-p)
          (cadr-cli::session-selector-handle-raw-input
           selector
           (format nil "~C[127;5u" #\Escape))
        (declare (ignore value))
        (is (eq :changed action))
        (is (eq t handled-p))
        (is (equal
             other
             (cadr-cli::session-selector-state-confirming-delete-path
              selector))))
      (multiple-value-bind (action value)
          (cadr-cli::session-selector-handle-event
           selector
           (cadr-tui:make-input-event :kind :enter))
        (is (eq :deleted action))
        (is (equal other value))
        (is (equal (list other) deletes)))
      (let ((renamable
              (cadr-cli::make-session-selector-state
               :current-sessions
               (list
                (session-record
                 "other" 1 "other"
                 :name "Old"
                 :path other))
               :show-rename-hint-p t
               :rename-function
               (lambda (path name)
                 (push (list path name) renames)
                 name))))
        (multiple-value-bind (action value handled-p)
            (cadr-cli::session-selector-handle-raw-input
             renamable
             (format nil "~C[114;5u" #\Escape))
          (declare (ignore value))
          (is (eq :changed action))
          (is (eq t handled-p)))
        (is (eq :rename
                (cadr-cli::session-selector-state-mode
                 renamable)))
        (cadr-cli::session-selector-handle-event
         renamable
         (cadr-tui:make-input-event
          :kind :text :text "X"))
        (multiple-value-bind (action value)
            (cadr-cli::session-selector-handle-event
             renamable
             (cadr-tui:make-input-event :kind :enter))
          (is (eq :renamed action))
          (is (string= "XOld" value))
          (is (equal
               (list other "XOld")
               (first renames))))))
    (let* ((selector
             (cadr-cli::make-session-selector-state
              :current-sessions
              (list (session-record
                     "current" 1 "current"))))
           (token
             (cadr-cli::session-selector-toggle-scope
              selector)))
      (is (integerp token))
      (is (eq :all
              (cadr-cli::session-selector-state-scope
               selector)))
      (is (null
           (cadr-cli::session-selector-toggle-scope
            selector)))
      (is (eq :current
              (cadr-cli::session-selector-state-scope
               selector)))
      (is (null
           (cadr-cli::session-selector-toggle-scope
            selector)))
      (is (= token
             (cadr-cli::session-selector-state-all-load-sequence
              selector)))
      (cadr-cli::session-selector-toggle-scope selector)
      (cadr-cli::session-selector-complete-all-load
       selector token
       (list (session-record "all" 2 "all")))
      (is (eq :current
              (cadr-cli::session-selector-state-scope
               selector)))
      (is (eq t
              (cadr-cli::session-selector-state-all-loaded-p
               selector))))))

(test session-selector-rename-hint-can-be-hidden
  (let ((selector
          (cadr-cli::make-session-selector-state
           :current-sessions
           (list (session-record "one" 1 "one"))
           :show-rename-hint-p nil
           :rename-function
           (lambda (path name)
             (declare (ignore path))
             name))))
    (is (not
         (search
          "ctrl+r"
          (format nil "~{~A~^~%~}"
                  (cadr-cli::render-session-selector
                   selector 100)))))))

(test goal9-session-selector-layout-matches-baseline-panel-and-list
  (let* ((parent-path #P"/tmp/thread-parent.jsonl")
         (state
           (cadr-cli::make-session-selector-state
            :current-sessions
            (append
             (list
              (session-record
               "parent" 0 "parent search text"
               :name "Named parent"
               :path parent-path
               :cwd "/tmp/project"
               :message-count 4)
              (session-record
               "child-a" 0 "child A"
               :parent-path parent-path
               :message-count 2)
              (session-record
               "child-b" 0 "child B"
               :parent-path parent-path
               :message-count 3))
             (loop for index below 9
                   collect
                   (session-record
                    (format nil "other-~D" index)
                    0
                    (format nil "other ~D" index)
                    :message-count index)))
            :show-rename-hint-p t))
         (width 120))
    (setf
     (cadr-cli::session-selector-state-query state)
     "child")
    (let* ((lines
             (cadr-cli::render-session-selector
              state width))
           (plain
             (mapcar
              #'cadr-tui:strip-terminal-sequences
              lines)))
      (is (string= "" (first plain)))
      (is (= width
             (cadr-tui:visible-width
              (second lines))))
      (is (string= "" (third plain)))
      (is (uiop:string-prefix-p
           "Resume Session (Current Folder)"
           (fourth plain)))
      (is (search "Sort: Threaded"
                  (fourth plain)))
      (is (search "re:<pattern> regex"
                  (fifth plain)))
      (is (search "path (off)"
                  (sixth plain)))
      (is (string= "" (seventh plain)))
      (is
       (string=
        (concatenate
         'string "> child"
         (make-string (- width 7) :initial-element #\Space))
        (eighth plain)))
      (is (string= "" (ninth plain)))
      (is (some
           (lambda (line)
             (and (search "child A" line)
                  (search "2 " line)))
           plain))
      (is (string= ""
                   (nth (- (length plain) 2)
                        plain)))
      (is (= width
             (cadr-tui:visible-width
              (car (last lines))))))
    (setf
     (cadr-cli::session-selector-state-query state)
     ""
     (cadr-cli::session-selector-state-selected state)
     11)
    (let* ((plain
             (mapcar
              #'cadr-tui:strip-terminal-sequences
              (cadr-cli::render-session-selector
               state width)))
           (rows
             (remove-if-not
              (lambda (line)
                (or (uiop:string-prefix-p "› " line)
                    (uiop:string-prefix-p "  " line)))
              (subseq plain 9
                      (- (length plain) 2)))))
      (is (= 11 (length rows)))
      (is (some
           (lambda (line)
             (search "├─ " line))
           rows))
      (is (some
           (lambda (line)
             (search "└─ " line))
           rows))
      (is (search "(12/12)"
                  (car (last rows)))))))

(test goal9-session-selector-rename-layout-matches-baseline-spacers
  (let ((state
          (cadr-cli::make-session-selector-state
           :current-sessions
           (list (session-record "one" 0 "one")))))
    (setf
     (cadr-cli::session-selector-state-mode state) :rename
     (cadr-cli::session-selector-state-rename-input state)
     "Renamed")
    (multiple-value-bind (lines row column)
        (cadr-cli::render-session-selector state 60)
      (let ((plain
              (mapcar
               #'cadr-tui:strip-terminal-sequences
               lines)))
        (is (= 5 row))
        (is (= 2 column))
        (is (string= "> Renamed"
                     (string-right-trim
                      '(#\Space) (nth row plain))))
        (is (equal
             (list "" "" (format nil "~60A" " Rename Session") "" ""
                   (format nil "~60A"
                           " enter to save · escape/ctrl+c to cancel")
                   "")
             (list
              (first plain)
              (third plain)
              (fourth plain)
              (fifth plain)
              (seventh plain)
              (eighth plain)
              (ninth plain))))))))

(test footer-path-width-cost-cache-and-subscription-semantics
  (is (string=
       "/home/user2"
       (cadr-cli:format-cwd-for-footer
        "/home/user2" "/home/user")))
  (is (string=
       "~"
       (cadr-cli:format-cwd-for-footer
        "/home/user" "/home/user")))
  (is (string=
       "~/project"
       (cadr-cli:format-cwd-for-footer
        "/home/user/project"
        "/home/user")))
  (let ((fitted
          (cadr-cli:fit-footer-text
           (with-output-to-string (output)
             (dotimes (index 30)
               (write-char #\界 output)))
           20)))
    (is (<=
         (cadr-tui:visible-width fitted)
         20)))
  (let ((summary
          (cadr-cli:footer-usage-summary
           (list
            (list :input 100
                  :output 10
                  :cache-read 50
                  :cache-write 50
                  :cost 0.5d0)
            (list :input 20
                  :output 5
                  :cost 0.75d0))
           :provider "kimi-coding")))
    (is (search "$1.250" summary))
    (is (search "CH" summary))
    (is (search "(sub)" summary))))

(test footer-data-provider-resolves-and-refreshes-git-branches
  (with-test-directory (root)
    (let* ((repo
             (merge-pathnames "repo/" root))
           (nested
             (merge-pathnames
              "src/nested/" repo))
           (git-directory
             (merge-pathnames ".git/" repo))
           (head
             (merge-pathnames
              "HEAD" git-directory))
           (now 0))
      (ensure-directories-exist
       (merge-pathnames "placeholder"
                        nested))
      (ensure-directories-exist
       (merge-pathnames "placeholder"
                        git-directory))
      (write-text
       head "ref: refs/heads/main")
      (let* ((provider
               (cadr-cli:make-footer-data-provider
                nested
                :poll-seconds 3600
                :debounce-seconds 0.02
                :clock-function (lambda () now)))
             (changes 0)
             (unsubscribe
               (cadr-cli:footer-data-provider-on-branch-change
                provider
                (lambda ()
                  (incf changes)))))
        (unwind-protect
             (progn
               (is (string=
                    "main"
                    (cadr-cli:footer-data-provider-git-branch
                     provider)))
               (write-text
                head
                "ref: refs/heads/feature")
               (cadr-cli::poll-footer-data-provider provider)
               (setf now
                     (round
                      (* 0.02
                         internal-time-units-per-second)))
               (cadr-cli::poll-footer-data-provider provider)
               (is (string=
                    "feature"
                    (cadr-cli:footer-data-provider-git-branch
                     provider)))
               (is (= 1 changes))
               (write-text
                head
                "ref: refs/heads/feature")
               (cadr-cli::poll-footer-data-provider provider)
               (is (= 1 changes))
               (cadr-cli:footer-data-provider-set-status
                provider "one" "ready")
               (is (string=
                    "ready"
                    (cdr
                     (assoc
                      "one"
                      (cadr-cli:footer-data-provider-statuses
                       provider)
                      :test #'string=))))
               (cadr-cli:footer-data-provider-set-status
                provider "one" nil)
               (is (null
                    (cadr-cli:footer-data-provider-statuses
                     provider))))
          (funcall unsubscribe)
          (cadr-cli:footer-data-provider-dispose
           provider))))))

(test footer-data-provider-handles-reftable-worktrees-and-transient-read-errors
  (with-test-directory (root)
    (let* ((repo
             (merge-pathnames "repo/" root))
           (common-git
             (merge-pathnames ".git/" repo))
           (worktree-git
             (merge-pathnames
              "worktrees/src/" common-git))
           (worktree
             (merge-pathnames "worktree/" root))
           (git-file
             (merge-pathnames ".git" worktree))
           (head
             (merge-pathnames "HEAD" worktree-git))
           (commondir
             (merge-pathnames "commondir"
                              worktree-git))
           (symbolic-calls 0)
           (now 0)
           (provider nil))
      (ensure-directories-exist
       (merge-pathnames "placeholder"
                        worktree-git))
      (ensure-directories-exist
       (merge-pathnames "placeholder"
                        common-git))
      (ensure-directories-exist
       (merge-pathnames "placeholder"
                        worktree))
      (write-text
       git-file
       (format nil "gitdir: ~A"
               (namestring worktree-git)))
      (write-text commondir "../..")
      (write-text head
                  "ref: refs/heads/.invalid")
      (let ((cadr-cli::*git-symbolic-branch-function*
              (lambda (directory)
                (is (equal
                     (truename worktree)
                     (truename directory)))
                (incf symbolic-calls)
                "main")))
        (setf provider
              (cadr-cli:make-footer-data-provider
               worktree
               :poll-seconds 3600
               :debounce-seconds 0.02
               :clock-function (lambda () now)))
        (unwind-protect
             (progn
               (is (string=
                    "main"
                    (cadr-cli:footer-data-provider-git-branch
                     provider)))
               (is (plusp symbolic-calls))
               (delete-file head)
               (cadr-cli::poll-footer-data-provider provider)
               (is (string=
                    "main"
                    (cadr-cli:footer-data-provider-git-branch
                     provider)))
               (write-text
                head "ref: refs/heads/recovered")
               (cadr-cli::poll-footer-data-provider provider)
               (setf now
                     (round
                      (* 0.02
                         internal-time-units-per-second)))
               (cadr-cli::poll-footer-data-provider provider)
               (is (string=
                    "recovered"
                    (cadr-cli:footer-data-provider-git-branch
                     provider))))
          (cadr-cli:footer-data-provider-dispose
           provider))))))

(test footer-data-provider-debounces-reftable-refreshes
  (with-test-directory (root)
    (let* ((repo
             (merge-pathnames "repo/" root))
           (git-directory
             (merge-pathnames ".git/" repo))
           (reftable-directory
             (merge-pathnames
              "reftable/" git-directory))
           (head
             (merge-pathnames
              "HEAD" git-directory))
           (tables
             (merge-pathnames
              "tables.list"
              reftable-directory))
           (calls 0)
           (branch "main")
           (now 0)
           (provider nil))
      (ensure-directories-exist tables)
      (write-text head
                  "ref: refs/heads/.invalid")
      (write-text tables "0")
      (let ((cadr-cli::*git-symbolic-branch-function*
              (lambda (directory)
                (declare (ignore directory))
                (incf calls)
                branch)))
        (setf provider
              (cadr-cli:make-footer-data-provider
               repo
               :poll-seconds 3600
               :debounce-seconds 0.05
               :clock-function (lambda () now)))
        (unwind-protect
             (progn
               (is (= 1 calls))
               (cadr-cli::poll-footer-data-provider provider)
               (is (= 1 calls))
               (setf branch "feature")
               (write-text tables "1")
               (cadr-cli::poll-footer-data-provider provider)
               (setf now 10)
               (write-text tables "2")
               (cadr-cli::poll-footer-data-provider provider)
               (setf now 20)
               (write-text tables "3")
               (cadr-cli::poll-footer-data-provider provider)
               (setf now
                     (1-
                      (+ 20
                         (round
                          (* 0.05
                             internal-time-units-per-second)))))
               (cadr-cli::poll-footer-data-provider provider)
               (is (= 1 calls))
               (setf now
                     (+ 20
                        (round
                         (* 0.05
                            internal-time-units-per-second))))
               (cadr-cli::poll-footer-data-provider provider)
               (is (string=
                    "feature"
                    (cadr-cli:footer-data-provider-git-branch
                     provider)))
               (is (= 2 calls)))
          (cadr-cli:footer-data-provider-dispose
           provider))))))

(test themes-detect-resolve-export-and-use-content-names
  (let ((light
          (cadr-cli:detect-background-from-environment
           '(("COLORFGBG" . "0;7;15"))))
        (dark
          (cadr-cli:detect-background-from-environment
           '(("COLORFGBG" . "15;0"))))
        (bright-red
          (cadr-cli:detect-background-from-environment
           '(("COLORFGBG" . "0;9"))))
        (light-cube
          (cadr-cli:detect-background-from-environment
           '(("COLORFGBG" . "1;231;999"))))
        (out-of-range
          (cadr-cli:detect-background-from-environment
           '(("COLORFGBG" . "256"))))
        (fallback
          (cadr-cli:detect-background-from-environment
           '(("OTHER" . "x")))))
    (is (eq :light
            (cadr-cli:theme-detection-theme
             light)))
    (is (eq :dark
            (cadr-cli:theme-detection-theme
             dark)))
    (is (eq :dark
            (cadr-cli:theme-detection-theme
             bright-red)))
    (is (eq :light
            (cadr-cli:theme-detection-theme
             light-cube)))
    (is (eq :low
            (cadr-cli:theme-detection-confidence
             out-of-range)))
    (is (eq :low
            (cadr-cli:theme-detection-confidence
             fallback))))
  (is (eq :dark
          (cadr-cli:rgb-background-theme
           8 8 8)))
  (is (eq :light
          (cadr-cli:rgb-background-theme
           250 250 250)))
  (is (eq :dark
          (cadr-cli:rgb-background-theme
           128 128 128)))
  (is (eq :dark
          (cadr-cli:rgb-background-theme
           187 187 187)))
  (is (eq :light
          (cadr-cli:rgb-background-theme
           188 188 188)))
  (signals type-error
    (cadr-cli:rgb-background-theme
     -1 0 0))
  (signals type-error
    (cadr-cli:rgb-background-theme
     0 0 256))
  (is (null
       (cadr-cli::xterm-color-to-rgb -1)))
  (is (null
       (cadr-cli::xterm-color-to-rgb 256)))
  (is (equal
       '(:light-theme "light"
         :dark-theme "dark")
       (cadr-cli:parse-auto-theme-setting
        "  light / dark  ")))
  (is (null
       (cadr-cli:parse-auto-theme-setting
        " /dark")))
  (is (null
       (cadr-cli:parse-auto-theme-setting
        "light/  ")))
  (is (null
       (cadr-cli:parse-auto-theme-setting nil)))
  (is (string=
       "light"
       (cadr-cli:resolve-theme-setting
        " light / dark " :light)))
  (is (null
       (cadr-cli:resolve-theme-setting
        "light/dark/extra" :dark)))
  (let ((theme
          (args
           "vars"
           (args
            "deep" "#abcdef"
            "page" "deep"
            "card" 24)
           "export"
           (args
            "pageBg" "page"
            "cardBg" "card"
            "infoBg" ""))))
    (is (equal
         '(:page-bg "#abcdef"
           :card-bg "#005F87"
           :info-bg nil)
         (cadr-cli:theme-export-colors
          theme))))
  (with-test-directory (root)
    (write-json
     (merge-pathnames "odd-file.json" root)
     (args "name" "content-name"))
    (is (string=
         "content-name"
         (getf
          (first
           (cadr-cli:load-theme-summaries
            root))
          :name)))))

(test clipboard-selection-and-osc52-are-platform-aware-and-bounded
  (is (equal
       '(("wl-copy")
         ("xclip" "-selection" "clipboard")
         ("xsel" "--clipboard" "--input"))
       (cadr-cli:clipboard-command-candidates
        :platform :linux
        :wayland-p t
        :wayland-display-p t
        :x11-display-p t)))
  (is (equal
       '(("termux-clipboard-set")
         ("wl-copy")
         ("xclip" "-selection" "clipboard")
         ("xsel" "--clipboard" "--input"))
       (cadr-cli:clipboard-command-candidates
        :platform :linux
        :termux-p t
        :wayland-p t
        :wayland-display-p t
        :x11-display-p t)))
  (is (equal
       '(("clip"))
       (cadr-cli:clipboard-command-candidates
        :platform :windows)))
  (is (null
       (cadr-cli:clipboard-command-candidates
        :platform :linux
        :wayland-p t
        :wayland-display-p nil
        :x11-display-p nil)))
  (is (string=
       (format nil "~C]52;c;aGVsbG8=~C"
               #\Escape (code-char 7))
       (cadr-cli:osc52-copy-sequence
        "hello")))
  (is (null
       (cadr-cli:osc52-copy-sequence
        "oversized" :maximum-bytes 1))))

(test clipboard-text-and-image-fallbacks-preserve-platform-order
  (is (string=
       "native"
       (cadr-cli::read-clipboard-text
        :native-getter
        (lambda () "native"))))
  (is (null
       (cadr-cli::read-clipboard-text
        :native-getter
        (lambda ()
          (error "unavailable")))))
  (let ((events nil)
        (output
          (make-string-output-stream)))
    (is (eq
         :native+osc52
         (cadr-cli::copy-to-clipboard
          "hello"
          :platform :darwin
          :remote-p t
          :output output
          :native-setter
          (lambda (text)
            (push (list :native text) events)))))
    (is (equal
         '((:native "hello"))
         events))
    (is (search
         "]52;c;aGVsbG8="
         (get-output-stream-string output))))
  (let ((commands nil)
        (output
          (make-string-output-stream)))
    (is (eq
         :shell
         (cadr-cli::copy-to-clipboard
          "hello"
          :platform :darwin
          :output output
          :native-setter
          (lambda (text)
            (declare (ignore text))
            (error "native failed"))
          :command-runner
          (lambda (argv input)
            (push (list argv input) commands)
            t))))
    (is (equal
         '((("pbcopy") "hello"))
         commands))
    (is (string=
         ""
         (get-output-stream-string output))))
  (signals cadr-ai:configuration-error
    (cadr-cli::copy-to-clipboard
     (make-string 80000 :initial-element #\x)
     :platform :darwin
     :native-setter
     (lambda (text)
       (declare (ignore text))
       (error "native failed"))
     :command-runner
     (lambda (argv input)
       (declare (ignore argv input))
       nil)
     :output
     (make-string-output-stream)))
  (let ((calls nil))
    (let ((image
            (cadr-cli::read-clipboard-image
             :platform :linux
             :environment
             '(("WAYLAND_DISPLAY" . "1"))
             :command-runner
             (lambda (argv)
               (push argv calls)
               (cond
                 ((equal argv
                         '("wl-paste"
                           "--list-types"))
                  (values
                   (cadr-ai::utf8-octets
                    (format nil
                            "text/plain~%image/png~%"))
                   t))
                 ((equal argv
                         '("wl-paste" "--type"
                           "image/png"
                           "--no-newline"))
                  (values
                   (make-array
                    3
                    :element-type
                    '(unsigned-byte 8)
                    :initial-contents '(1 2 3))
                   t))
                 (t
                  (values #() nil)))))))
      (is (string=
           "image/png"
           (cadr-cli::clipboard-image-mime-type
            image)))
      (is (equalp
           #(1 2 3)
           (cadr-cli::clipboard-image-bytes image)))
      (is (null
           (find
            :native calls
            :key #'first)))))
  (with-test-directory (root)
    (let* ((temporary
             (merge-pathnames
              "pi-wsl-clip-test.png" root))
           (calls nil)
           (image
             (cadr-cli::read-clipboard-image
              :platform :linux
              :environment
              '(("WSL_DISTRO_NAME" . "Ubuntu"))
              :temporary-path-provider
              (lambda () temporary)
              :command-runner
              (lambda (argv)
                (push argv calls)
                (cond
                  ((or
                    (equal
                     argv
                     '("wl-paste" "--list-types"))
                    (and
                     (equal (first argv) "xclip")
                     (member "TARGETS" argv
                             :test #'string=)))
                   (values #() nil))
                  ((equal
                    argv
                    (list
                     "wslpath" "-w"
                     (namestring temporary)))
                   (values
                    (cadr-ai::utf8-octets
                     (format nil
                             "C:\\Users\\O'Hare\\clip.png~%"))
                    t))
                  ((equal
                    (subseq argv 0 3)
                    '("powershell.exe"
                      "-NoProfile" "-Command"))
                   (is (search
                        "$path = 'C:\\Users\\O''Hare\\clip.png'"
                        (fourth argv)))
                   (with-open-file
                       (stream temporary
                               :direction :output
                               :if-exists :supersede
                               :if-does-not-exist :create
                               :element-type
                               '(unsigned-byte 8))
                     (write-sequence #(4 5 6) stream))
                   (values
                    (cadr-ai::utf8-octets
                     (format nil "ok~%"))
                    t))
                  (t
                   (values #() nil)))))))
      (is (string=
           "image/png"
           (cadr-cli::clipboard-image-mime-type
            image)))
      (is (equalp
           #(4 5 6)
           (cadr-cli::clipboard-image-bytes image)))
      (is (null (probe-file temporary)))
      (is (find
           "powershell.exe" calls
           :key #'first
           :test #'string=)))))

(defun clipboard-test-hello-osc52 ()
  (format nil "~C]52;c;aGVsbG8=~C"
          #\Escape (code-char 7)))

(defun clipboard-test-error-message
    (text &rest args)
  (let ((output (make-string-output-stream)))
    (handler-case
        (progn
          (apply #'cadr-cli::copy-to-clipboard text
                 :output output args)
          nil)
      (cadr-ai:configuration-error (condition)
        (values
         (cadr-ai:cadr-error-message condition)
         (get-output-stream-string output))))))

(test clipboard-without-a-display-uses-osc52
  (let ((commands nil)
        (output (make-string-output-stream)))
    (is (eq :osc52
            (cadr-cli::copy-to-clipboard
             "hello"
             :platform :linux
             :wsl-p nil
             :windows-terminal-p nil
             :output output
             :command-runner
             (lambda (argv input)
               (declare (ignore input))
               (push argv commands)
               nil))))
    (is (null commands))
    (is (string=
         (clipboard-test-hello-osc52)
         (get-output-stream-string output)))))

(test clipboard-with-a-working-display-skips-osc52
  (let ((commands nil)
        (output (make-string-output-stream)))
    (is (eq :shell
            (cadr-cli::copy-to-clipboard
             "hello"
             :platform :linux
             :x11-display-p t
             :wsl-p nil
             :output output
             :command-runner
             (lambda (argv input)
               (push (list argv input) commands)
               t))))
    (is (equal
         '((("xclip" "-selection" "clipboard") "hello"))
         commands))
    (is (string=
         ""
         (get-output-stream-string output)))))

(test clipboard-display-failure-does-not-report-osc52-success
  (let ((commands nil))
    (multiple-value-bind (message output)
        (clipboard-test-error-message
         "hello"
         :platform :linux
         :x11-display-p t
         :wsl-p nil
         :command-runner
         (lambda (argv input)
           (declare (ignore input))
           (push (first argv) commands)
           nil))
      (is (string=
           "Clipboard unavailable: install `xclip` or `xsel`, or check X11 access"
           message))
      (is (equal '("xsel" "xclip") commands))
      (is (string= "" output))))
  (let ((commands nil))
    (multiple-value-bind (message output)
        (clipboard-test-error-message
         "hello"
         :platform :linux
         :wayland-p t
         :wayland-display-p t
         :x11-display-p t
         :wsl-p nil
         :command-runner
         (lambda (argv input)
           (declare (ignore input))
           (push (first argv) commands)
           nil))
      (is (string=
           "Clipboard unavailable: install `wl-clipboard` (`wl-copy`) or check Wayland access"
           message))
      (is (equal '("xsel" "xclip" "wl-copy") commands))
      (is (string= "" output))))
  (multiple-value-bind (message output)
      (clipboard-test-error-message
       (make-string 80000 :initial-element #\x)
       :platform :linux
       :wsl-p nil
       :command-runner
       (lambda (argv input)
         (declare (ignore argv input))
         nil))
    (is (string=
         "Clipboard unavailable: text exceeds the OSC 52 size limit"
         message))
    (is (string= "" output))))

(test clipboard-wsl-without-display-uses-windows-clipboard
  (with-test-directory (root)
    (let* ((temporary
             (merge-pathnames "cadr-wsl-clip-test.txt" root))
           (commands nil)
           (written nil)
           (output (make-string-output-stream)))
      (is (eq :shell
              (cadr-cli::copy-to-clipboard
               "héllo"
               :platform :linux
               :wsl-p t
               :windows-terminal-p nil
               :output output
               :temporary-path-provider (lambda () temporary)
               :command-runner
               (lambda (argv input)
                 (declare (ignore input))
                 (push argv commands)
                 (cond
                   ((equal (first argv) "wslpath")
                    (setf written
                          (uiop:read-file-string
                           (third argv)
                           :external-format :utf-8))
                    (is (= #o600
                           (logand
                            #o777
                            (sb-posix:stat-mode
                             (sb-posix:stat
                              (namestring (third argv)))))))
                    (values
                     t
                     (format nil "\\\\wsl.localhost\\Ubuntu\\tmp\\clip.txt~%")))
                   ((equal (first argv) "powershell.exe")
                    t)
                   (t nil))))))
      (is (string= "héllo" written))
      (is (null (probe-file temporary)))
      (is (string= "" (get-output-stream-string output)))
      (is (equal "wslpath" (first (first (last commands)))))
      (is (equal
           "powershell.exe"
           (first (first commands))))
      (is (search
           "Set-Clipboard"
           (fourth (first commands))))
      (is (search
           "'\\\\wsl.localhost\\Ubuntu\\tmp\\clip.txt'"
           (fourth (first commands)))))))

(test clipboard-wsl-without-windows-interop-uses-osc52
  (with-test-directory (root)
    (let ((temporary
            (merge-pathnames "cadr-wsl-clip-test.txt" root))
          (commands nil)
          (output (make-string-output-stream)))
      (is (eq :osc52
              (cadr-cli::copy-to-clipboard
               "hello"
               :platform :linux
               :wsl-p t
               :windows-terminal-p nil
               :output output
               :temporary-path-provider (lambda () temporary)
               :command-runner
               (lambda (argv input)
                 (declare (ignore input))
                 (push (first argv) commands)
                 nil))))
      (is (equal '("wslpath") commands))
      (is (null (probe-file temporary)))
      (is (string=
           (clipboard-test-hello-osc52)
           (get-output-stream-string output))))))

(test clipboard-wsl-windows-terminal-prefers-osc52
  (let ((commands nil)
        (output (make-string-output-stream)))
    (is (eq :osc52
            (cadr-cli::copy-to-clipboard
             "hello"
             :platform :linux
             :wsl-p t
             :windows-terminal-p t
             :output output
             :command-runner
             (lambda (argv input)
               (declare (ignore input))
               (push argv commands)
               t))))
    (is (null commands))
    (is (string=
         (clipboard-test-hello-osc52)
         (get-output-stream-string output))))
  (let ((commands nil)
        (output (make-string-output-stream)))
    (is (eq :osc52
            (cadr-cli::copy-to-clipboard
             "hello"
             :platform :linux
             :wsl-p t
             :windows-terminal-p t
             :remote-p t
             :output output
             :command-runner
             (lambda (argv input)
               (declare (ignore input))
               (push argv commands)
               t))))
    (is (null commands))
    (is (string=
         (clipboard-test-hello-osc52)
         (get-output-stream-string output))))
  (with-test-directory (root)
    (let ((temporary
            (merge-pathnames "cadr-wsl-clip-test.txt" root))
          (commands nil)
          (output (make-string-output-stream)))
      (is (eq :shell
              (cadr-cli::copy-to-clipboard
               (make-string 80000 :initial-element #\x)
               :platform :linux
               :wsl-p t
               :windows-terminal-p t
               :output output
               :temporary-path-provider (lambda () temporary)
               :command-runner
               (lambda (argv input)
                 (declare (ignore input))
                 (push (first argv) commands)
                 (if (equal (first argv) "wslpath")
                     (values t "C:\\clip.txt")
                     t)))))
      (is (equal '("powershell.exe" "wslpath") commands))
      (is (string= "" (get-output-stream-string output)))
      (is (null (probe-file temporary))))))

(test clipboard-wsl-with-a-display-prefers-linux-tools
  (let ((commands nil)
        (output (make-string-output-stream)))
    (is (eq :shell
            (cadr-cli::copy-to-clipboard
             "hello"
             :platform :linux
             :wsl-p t
             :windows-terminal-p nil
             :wayland-p t
             :wayland-display-p t
             :output output
             :command-runner
             (lambda (argv input)
               (push (list argv input) commands)
               (equal (first argv) "wl-copy")))))
    (is (equal
         '((("wl-copy") "hello"))
         commands))
    (is (string=
         ""
         (get-output-stream-string output)))))

(test goal16-default-wsl-clipboard-path-uses-cadr-identity
  (let ((name
          (file-namestring
           (cadr-cli::default-clipboard-temporary-path))))
    (is (uiop:string-prefix-p "cadr-wsl-clip-" name))
    (is (uiop:string-suffix-p name ".png"))))

(defun image-test-base64-value (character)
  (position
   character
   "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"))

(defun decode-image-test-base64 (text)
  (let ((output
          (make-array
           0 :element-type '(unsigned-byte 8)
           :adjustable t :fill-pointer 0))
        (accumulator 0)
        (bits 0))
    (loop for character across text
          unless (member character
                         '(#\Space #\Tab #\Newline #\Return #\=))
            do
            (let ((value
                    (image-test-base64-value character)))
              (unless value
                (error "Invalid test base64"))
              (setf accumulator
                    (logior (ash accumulator 6) value)
                    bits (+ bits 6))
              (when (>= bits 8)
                (decf bits 8)
                (vector-push-extend
                 (ldb (byte 8 bits) accumulator)
                 output)
                (setf accumulator
                      (ldb (byte bits 0) accumulator)))))
    output))

(defun image-test-exif-orientation (jpeg orientation)
  (let* ((payload
           (vector
            #x45 #x78 #x69 #x66 0 0
            #x49 #x49 #x2a 0 8 0 0 0
            1 0
            #x12 1 3 0 1 0 0 0
            orientation 0 0 0
            0 0 0 0))
         (segment-length (+ 2 (length payload)))
         (output
           (make-array
            (+ (length jpeg) 4 (length payload))
            :element-type '(unsigned-byte 8))))
    (replace output jpeg :end2 2)
    (setf (aref output 2) #xff
          (aref output 3) #xe1
          (aref output 4)
          (ldb (byte 8 8) segment-length)
          (aref output 5)
          (ldb (byte 8 0) segment-length))
    (replace output payload :start1 6)
    (replace output jpeg
             :start1 (+ 6 (length payload))
             :start2 2)
    output))

(test image-processing-decodes-converts-resamples-orients-and-enforces-limits
  (let ((bmp
          (make-array
           58 :element-type '(unsigned-byte 8)
           :initial-element 0)))
    (setf
     (aref bmp 0) (char-code #\B)
     (aref bmp 1) (char-code #\M)
     (aref bmp 2) 58
     (aref bmp 10) 54
     (aref bmp 14) 40
     (aref bmp 18) 1
     (aref bmp 22) 1
     (aref bmp 26) 1
     (aref bmp 28) 24
     (aref bmp 56) 255)
    (let ((result
            (cadr-cli:process-image-bytes
             bmp "image/bmp"
             :auto-resize-p nil)))
      (is (string=
           "image/png"
           (cadr-cli:image-process-result-mime-type
            result)))
      (is (equalp
           #(137 80 78 71)
           (subseq
            (cadr-cli:image-process-result-bytes
             result)
            0 4)))
      (is (search
           "converted"
           (string-downcase
            (first
             (cadr-cli:image-process-result-hints
              result)))))))
  (let* ((rgba
           #(255 0 0 255
             0 255 0 255
             0 0 255 255
             255 255 255 255))
         (png
           (cadr-cli::encode-rgba-png
            rgba 2 2)))
    (multiple-value-bind (width height valid-p)
        (cadr-cli:image-dimensions-from-bytes
         png "image/png")
      (is (not (null valid-p)))
      (is (= 2 width))
      (is (= 2 height)))
    (let ((result
            (cadr-cli:process-image-bytes
             png "image/png"
             :max-width 100
             :max-height 100)))
      (is (not
           (cadr-cli:image-process-result-resized-p
            result)))
      (is (not
           (eq png
               (cadr-cli:image-process-result-bytes
                result)))))
    (is (null
         (cadr-cli:process-image-bytes
          png "image/png"
          :max-width 1
          :max-height 1
          :resize-function
          (lambda (&rest ignored)
            (declare (ignore ignored))
            nil)))))
  (let* ((tiny-png
           (decode-image-test-base64
            "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACAQMAAABIeJ9nAAAAIGNIUk0AAHomAACAhAAA+gAAAIDoAAB1MAAA6mAAADqYAAAXcJy6UTwAAAAGUExURf8AAP///0EdNBEAAAABYktHRAH/Ai3eAAAAB3RJTUUH6gEOADM5Ddoh/wAAAAxJREFUCNdjYGBgAAAABAABJzQnCgAAACV0RVh0ZGF0ZTpjcmVhdGUAMjAyNi0wMS0xNFQwMDo1MTo1NyswMDowMOnKzHgAAAAldEVYdGRhdGU6bW9kaWZ5ADIwMjYtMDEtMTRUMDA6NTE6NTcrMDA6MDCYl3TEAAAAKHRFWHRkYXRlOnRpbWVzdGFtcAAyMDI2LTAxLTE0VDAwOjUxOjU3KzAwOjAwz4JVGwAAAABJRU5ErkJggg=="))
         (result
           (cadr-cli:process-image-bytes
            tiny-png "image/png"
            :max-width 100
            :max-height 100
            :max-bytes (* 1024 1024))))
    (is (not (null result)))
    (is (equalp
         tiny-png
         (cadr-cli:image-process-result-bytes
          result)))
    (is (not
         (cadr-cli:image-process-result-resized-p
          result))))
  (let* ((jpeg
           (decode-image-test-base64
            "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAMCAgMCAgMDAwMEAwMEBQgFBQQEBQoHBwYIDAoMDAsKCwsNDhIQDQ4RDgsLEBYQERMUFRUVDA8XGBYUGBIUFRT/2wBDAQMEBAUEBQkFBQkUDQsNFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBT/wAARCAACAAIDAREAAhEBAxEB/8QAFAABAAAAAAAAAAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/xAAVAQEBAAAAAAAAAAAAAAAAAAAGCf/EABQRAQAAAAAAAAAAAAAAAAAAAAD/2gAMAwEAAhEDEQA/AD3VTB3/2Q=="))
         (png
           (cadr-cli::convert-image-bytes-to-png
            jpeg "image/jpeg")))
    (is (equalp #(137 80 78 71)
                (subseq png 0 4)))
    (multiple-value-bind (rgba width height)
        (cadr-cli::decode-image-rgba
         png "image/png")
      (is (= 2 width))
      (is (= 2 height))
      (is (= 16 (length rgba)))))
  (let* ((width 8)
         (height 4)
         (rgba
           (make-array
            (* width height 4)
            :element-type '(unsigned-byte 8))))
    (dotimes (y height)
      (dotimes (x width)
        (let ((position (* (+ (* y width) x) 4)))
          (setf (aref rgba position) (* x 30)
                (aref rgba (+ position 1)) (* y 60)
                (aref rgba (+ position 2)) 127
                (aref rgba (+ position 3)) 255))))
    (let* ((png (cadr-cli::encode-rgba-png
                 rgba width height))
           (result
             (cadr-cli:process-image-bytes
              png "image/png"
              :max-width 4
              :max-height 2
              :max-bytes (* 1024 1024))))
      (is (not (null result)))
      (is
       (cadr-cli:image-process-result-resized-p
        result))
      (is (= 4
             (cadr-cli:image-process-result-width
              result)))
      (is (= 2
             (cadr-cli:image-process-result-height
              result)))
      (multiple-value-bind (decoded resized-width resized-height)
          (cadr-cli::decode-image-rgba
           (cadr-cli:image-process-result-bytes result)
           (cadr-cli:image-process-result-mime-type result))
        (is (= 4 resized-width))
        (is (= 2 resized-height))
        (is (= (* 4 2 4) (length decoded)))))
    (let* ((jpeg
             (cadr-cli::encode-rgba-jpeg
              rgba width height 85))
           (oriented
             (image-test-exif-orientation jpeg 6))
           (result
             (cadr-cli:process-image-bytes
              oriented "image/jpeg"
              :max-width 2
              :max-height 8
              :max-bytes (* 1024 1024))))
      (is (not (null result)))
      (is (= 2
             (cadr-cli:image-process-result-width
              result)))
      (is (= 4
             (cadr-cli:image-process-result-height
              result)))))
  (let* ((width 64)
         (height 64)
         (rgba
           (make-array
            (* width height 4)
            :element-type '(unsigned-byte 8))))
    (dotimes (index (* width height))
      (let ((position (* index 4)))
        (setf (aref rgba position) (mod (* index 37) 256)
              (aref rgba (+ position 1)) (mod (* index 61) 256)
              (aref rgba (+ position 2)) (mod (* index 97) 256)
              (aref rgba (+ position 3)) 255)))
    (let* ((png
             (cadr-cli::encode-rgba-png
              rgba width height))
           (input-size
             (* 4 (ceiling (length png) 3)))
           (result
             (cadr-cli:process-image-bytes
              png "image/png"
              :max-width 2000
              :max-height 2000
              :max-bytes
              (floor (* input-size 0.9)))))
      (is (not (null result)))
      (is (<
           (* 4
              (ceiling
               (length
                (cadr-cli:image-process-result-bytes
                 result))
               3))
           (floor (* input-size 0.9)))))
    (is (null
         (cadr-cli:process-image-bytes
          (cadr-cli::encode-rgba-png
           rgba width height)
          "image/png"
          :max-bytes 1)))))

(test truncate-to-width-remains-unicode-and-emoji-safe
  (dolist
      (message
       '("✔ script to run › dev $ concurrently"
         "🎉 Celebration! 🚀 Launch"
         "Hello 世界 Test 你好 More text"))
    (let ((result
            (cadr-tui:truncate-to-width
             message 18)))
      (is (<=
           (cadr-tui:visible-width result)
           18))
      (is (search "..." result)))))

(test syntax-highlighting-decodes-entities-inherits-scopes-and-styles-code
  (let ((theme
          (list
           (cons "keyword"
                 (lambda (text)
                   (format nil "[k:~A]" text)))
           (cons "number"
                 (lambda (text)
                   (format nil "[n:~A]" text)))
           (cons "string"
                 (lambda (text)
                   (format nil "[s:~A]" text)))
           (cons "variable" #'identity)
           (cons "operator" #'identity))))
    (is (string=
         "[k:const] value"
         (cadr-cli:render-highlighted-html
          "<span class=\"hljs-keyword\">const</span> value"
          theme)))
    (is (string=
         "<tag attr=\"value\">&#x41;A</tag>"
         (cadr-cli:render-highlighted-html
          "&lt;tag attr=&quot;value&quot;&gt;&amp;#x41;&#65;&lt;/tag&gt;")))
    (is (string=
         "[s:a][s:${x}][s:b]"
         (cadr-cli:render-highlighted-html
          "<span class=\"hljs-string\">a<span class=\"hljs-subst\">${x}</span>b</span>"
          theme)))
    (is (string=
         "[s:a][s:b][s:c]"
         (cadr-cli:render-highlighted-html
          "<span class=\"hljs-string\">a<span class=\"language-xml\">b</span>c</span>"
          theme)))
    (is (cadr-cli:supports-syntax-language-p
         "typescript"))
    (is (string=
         "[k:const] value = [n:1]"
         (cadr-cli:simple-syntax-highlight
          "const value = 1" "typescript"
          theme))))
  (let* ((source
           (format
            nil
            "// note~%class Widget {~%  run(value: string) {~%    const result = value + ~S;~%    return result + 42;~%  }~%}"
            "x"))
         (theme
           (loop
             for scope in
             '("comment" "keyword" "function"
               "variable" "string" "number"
               "type" "operator" "punctuation")
             collect
             (cons
              scope
              (let ((scope scope))
                (lambda (text)
                  (format nil "[~A:~A]"
                          scope text))))))
         (rendered
           (cadr-cli:simple-syntax-highlight
            source "typescript" theme)))
    (is (string=
         (format
          nil
          "[comment:// note]~%[keyword:class] [function:Widget] {~%  [function:run][function:(][variable:value][variable::][variable: ][type:string][function:)] {~%    [keyword:const] result = value + [string:~S];~%    [keyword:return] result + [number:42];~%  }~%}"
          "x")
         rendered))
    (dolist (language '("python" "bash"))
      (is (string=
           "https://example.com"
           (cadr-cli:simple-syntax-highlight
            "https://example.com"
            language theme))))))

(test goal9-syntax-highlighting-matches-cli-highlight-visible-scopes
  (let ((theme
          (loop
            for scope in
            '("keyword" "function" "variable"
              "string" "number" "type"
              "operator" "punctuation"
              "addition" "deletion")
            collect
            (cons
             scope
             (let ((scope scope))
               (lambda (text)
                 (format nil "[~A:~A]"
                         scope text)))))))
    (is (string=
         "[punctuation:<][keyword:div][punctuation: ][variable:class][punctuation:=][string:\"x\"][punctuation:>]hello[punctuation:</][keyword:div][punctuation:>]"
         (cadr-cli:simple-syntax-highlight
          "<div class=\"x\">hello</div>"
          "html" theme)))
    (is (string=
         (format nil
                 "[deletion:-old]~%[addition:+new]~% same")
         (cadr-cli:simple-syntax-highlight
          (format nil "-old~%+new~% same")
          "diff" theme)))
    (is (string=
         "{[variable:\"ok\"]: [number:true]}"
         (cadr-cli:simple-syntax-highlight
          "{\"ok\": true}" "json" theme)))
    (is (string=
         "[function:f]() { [type:echo] [string:\"][variable:$x][string:\"]; }"
         (cadr-cli:simple-syntax-highlight
          "f() { echo \"$x\"; }" "bash" theme)))
    (is (string=
         "[keyword:SELECT] name [keyword:FROM] users [keyword:WHERE] id [operator:=] [number:42]"
         (cadr-cli:simple-syntax-highlight
          "SELECT name FROM users WHERE id = 42"
          "sql" theme)))))

(test goal9-syntax-previous-word-context-does-not-cross-boundaries
  (let ((theme
          (list
           (cons "keyword"
                 (lambda (text)
                   (format nil "[keyword:~A]" text)))
           (cons "type"
                 (lambda (text)
                   (format nil "[type:~A]" text)))
           (cons "string"
                 (lambda (text)
                   (format nil "[string:~A]" text))))))
    (is (string=
         (format nil
                 "[keyword:new] [string:\"x\"] Widget~%[keyword:new]; Other~%[keyword:new]~%Third")
         (cadr-cli:simple-syntax-highlight
          (format nil
                  "new \"x\" Widget~%new; Other~%new~%Third")
          "typescript" theme)))))

(test tree-selection-follows-visible-ancestors-and-preserves-empty-filters
  (let* ((entries
           '((:id "user-1"
              :parent-id nil
              :type :message
              :role :user)
             (:id "assistant-1"
              :parent-id "user-1"
              :type :message
              :role :assistant)
             (:id "user-2"
              :parent-id "assistant-1"
              :type :message
              :role :user)
             (:id "model-1"
              :parent-id "user-2"
              :type :model-change)))
         (selection
           (cadr-cli:make-tree-selection
            :selected-id "model-1")))
    (cadr-cli:switch-tree-selection-filter
     selection entries :messages)
    (is (string=
         "user-2"
         (cadr-cli:tree-selection-selected-id
          selection)))
    (cadr-cli:switch-tree-selection-filter
     selection entries :labeled)
    (is (null
         (cadr-cli:tree-selection-selected-id
          selection)))
    (cadr-cli:switch-tree-selection-filter
     selection entries :messages)
    (is (string=
         "user-2"
         (cadr-cli:tree-selection-selected-id
          selection)))
    (cadr-cli:switch-tree-selection-filter
     selection entries :user)
    (is (string=
         "user-2"
         (cadr-cli:tree-selection-selected-id
          selection)))))

(defun branching-tree-selector-entries ()
  '((:id "user-1" :parent-id nil
     :type :message :role :user
     :text "first message")
    (:id "asst-1" :parent-id "user-1"
     :type :message :role :assistant
     :text "response 1")
    (:id "user-2" :parent-id "asst-1"
     :type :message :role :user
     :text "second message")
    (:id "asst-2" :parent-id "user-2"
     :type :message :role :assistant
     :text "response 2")
    (:id "user-3a" :parent-id "asst-2"
     :type :message :role :user
     :text "branch A start")
    (:id "asst-3a" :parent-id "user-3a"
     :type :message :role :assistant
     :text "branch A response")
    (:id "user-4a" :parent-id "asst-3a"
     :type :message :role :user
     :text "branch A deep")
    (:id "asst-4a" :parent-id "user-4a"
     :type :message :role :assistant
     :text "branch A leaf")
    (:id "user-3b" :parent-id "asst-2"
     :type :message :role :user
     :text "branch B start")
    (:id "asst-3b" :parent-id "user-3b"
     :type :message :role :assistant
     :text "branch B response")
    (:id "user-4b" :parent-id "asst-3b"
     :type :message :role :user
     :text "branch B deep")))

(test tree-selector-matches-filter-copy-label-and-narrow-help-semantics
  (let* ((long-text
           (format nil "~{~A~}~%second line"
                   (make-list 30
                              :initial-element
                              "long message ")))
         (timestamp-parts
           (multiple-value-list
            (decode-universal-time
             (encode-universal-time
              0 32 14 28 3 2026 0))))
         (now-parts
           (multiple-value-list
            (decode-universal-time
             (get-universal-time))))
         (timestamp-time
           (format nil "~2,'0D:~2,'0D"
                   (nth 2 timestamp-parts)
                   (nth 1 timestamp-parts)))
         (expected-label-timestamp
           (cond
             ((and (= (nth 5 timestamp-parts) (nth 5 now-parts))
                   (= (nth 4 timestamp-parts) (nth 4 now-parts))
                   (= (nth 3 timestamp-parts) (nth 3 now-parts)))
              timestamp-time)
             ((= (nth 5 timestamp-parts) (nth 5 now-parts))
              (format nil "~D/~D ~A"
                      (nth 4 timestamp-parts)
                      (nth 3 timestamp-parts)
                      timestamp-time))
             (t
              (format nil "~2,'0D/~D/~D ~A"
                      (mod (nth 5 timestamp-parts) 100)
                      (nth 4 timestamp-parts)
                      (nth 3 timestamp-parts)
                      timestamp-time))))
         (entries
           `((:id "user-1" :parent-id nil
              :type :message :role :user
              :text "hello"
              :label "checkpoint"
              :label-timestamp
              "2026-03-28T14:32:00.000Z")
             (:id "asst-1" :parent-id "user-1"
              :type :message :role :assistant
              :text ,long-text)
             (:id "user-2" :parent-id "asst-1"
              :type :message :role :user
              :text "active branch")
             (:id "model-1" :parent-id "user-2"
              :type :model-change)
             (:id "user-3" :parent-id "asst-1"
              :type :message :role :user
              :text "sibling branch")))
         (copied nil)
         (state
           (cadr-cli::make-tree-selector-state
            :entries entries
            :current-leaf-id "model-1"
            :copy-callback
            (lambda (text)
              (setf copied text)))))
    (is (string=
         "user-2"
         (cadr-cli::tree-selector-selected-id
          state)))
    (cadr-cli::tree-selector-set-filter
     state :user-only)
    (is (string=
         "user-2"
         (cadr-cli::tree-selector-selected-id
          state)))
    (cadr-cli::tree-selector-set-filter
     state :labeled-only)
    (is (string=
         "user-1"
         (cadr-cli::tree-selector-selected-id
          state)))
    (cadr-cli::tree-selector-set-filter
     state :default)
    (is (string=
         "user-1"
         (cadr-cli::tree-selector-selected-id
          state)))
    (cadr-cli::tree-selector-select-id
     state "asst-1")
    (cadr-cli::tree-selector-copy-selected state)
    (is (string= long-text copied))
    (let ((help
            (cadr-cli::tree-selector-help-lines
             state 30)))
      (dolist (word
               '("branch" "copy" "filters"
                 "cycle" "label time"))
        (is (search word
                    (format nil "~{~A~^~%~}" help)
                    :test #'char-equal)))
      (is (not
           (search "..."
                   (format nil "~{~A~^~%~}" help))))
      (is (every
           (lambda (line)
             (<= (cadr-tui:visible-width line)
                 30))
           help)))
    (let* ((custom
             (cadr-cli::make-tree-selector-state
              :entries entries
              :current-leaf-id "model-1"
              :keybindings
              (cadr-cli::make-tree-selector-keybindings
               '(("app.tree.filter.cycleForward"
                  . ("alt+k"))
                 ("app.tree.filter.cycleBackward"
                  . ("alt+j"))))))
           (help
             (format
              nil "~{~A~^~%~}"
              (cadr-cli::tree-selector-help-lines
               custom 80))))
      (is (search "alt+k" help
                  :test #'char-equal))
      (is (search "alt+j" help
                  :test #'char-equal))
      (is (not
           (search "Ctrl+P/N" help
                   :test #'char-equal))))
    (cadr-cli::tree-selector-select-id
     state "user-1")
    (is (search "[checkpoint]"
                (format nil "~{~A~^~%~}"
                        (cadr-cli::tree-selector-render-lines
                         state 200))))
    (is (not
         (search expected-label-timestamp
                 (format nil "~{~A~^~%~}"
                         (cadr-cli::tree-selector-render-lines
                          state 200)))))
    (cadr-cli::tree-selector-toggle-label-timestamps
     state)
    (let ((rendered
            (format
             nil "~{~A~^~%~}"
             (cadr-cli::tree-selector-render-lines
              state 200))))
      (is (search expected-label-timestamp rendered))
      (is (search "[+label time]" rendered)))))

(test tree-selector-folds-and-jumps-across-branch-segments
  (let ((state
          (cadr-cli::make-tree-selector-state
           :entries
           (branching-tree-selector-entries)
           :current-leaf-id "asst-4a")))
    (is (string=
         "asst-4a"
         (cadr-cli::tree-selector-selected-id
          state)))
    (cadr-cli::tree-selector-fold-or-up state)
    (is (string=
         "user-3a"
         (cadr-cli::tree-selector-selected-id
          state)))
    (cadr-cli::tree-selector-fold-or-up state)
    (is (equal
         '("user-1" "asst-1" "user-2" "asst-2"
           "user-3a" "user-3b" "asst-3b" "user-4b")
         (cadr-cli::tree-selector-visible-ids
          state)))
    (cadr-cli::tree-selector-move state 1)
    (is (string=
         "user-3b"
         (cadr-cli::tree-selector-selected-id
          state)))
    (cadr-cli::tree-selector-move state -1)
    (cadr-cli::tree-selector-unfold-or-down state)
    (cadr-cli::tree-selector-move state 1)
    (is (string=
         "asst-3a"
         (cadr-cli::tree-selector-selected-id
          state)))
    (cadr-cli::tree-selector-fold-or-up state)
    (cadr-cli::tree-selector-unfold-or-down state)
    (is (string=
         "asst-4a"
         (cadr-cli::tree-selector-selected-id
          state)))
    (cadr-cli::tree-selector-fold-or-up state)
    (cadr-cli::tree-selector-fold-or-up state)
    (cadr-cli::tree-selector-fold-or-up state)
    (is (string=
         "user-1"
         (cadr-cli::tree-selector-selected-id
          state)))
    (cadr-cli::tree-selector-fold-or-up state)
    (is (equal
         '("user-1")
         (cadr-cli::tree-selector-visible-ids
          state)))
    (cadr-cli::tree-selector-unfold-or-down
     state)
    (cadr-cli::tree-selector-unfold-or-down
     state)
    (is (string=
         "user-3a"
         (cadr-cli::tree-selector-selected-id
          state)))
    (cadr-cli::tree-selector-move state 1)
    (is (string=
         "user-3b"
         (cadr-cli::tree-selector-selected-id
          state)))))

(test tree-selector-folding-handles-roots-filtered-intermediates-and-reset
  (let* ((entries
           '((:id "user-1" :parent-id nil
              :type :message :role :user
              :text "hello")
             (:id "tool-asst-1" :parent-id "user-1"
              :type :message :role :assistant
              :text ""
              :tool-call-only-p t)
             (:id "user-2" :parent-id "tool-asst-1"
              :type :message :role :user
              :text "follow up")
             (:id "asst-2" :parent-id "user-2"
              :type :message :role :assistant
              :text "response")
             (:id "other-root" :parent-id nil
              :type :message :role :user
              :text "other")))
         (state
           (cadr-cli::make-tree-selector-state
            :entries entries
            :current-leaf-id "asst-2")))
    (cadr-cli::tree-selector-fold-or-up state)
    (is (string=
         "user-1"
         (cadr-cli::tree-selector-selected-id
          state)))
    (cadr-cli::tree-selector-fold-or-up state)
    (is (equal
         '("user-1" "other-root")
         (cadr-cli::tree-selector-visible-ids
          state)))
    (cadr-cli::tree-selector-set-query state "other")
    (is (zerop
         (hash-table-count
          (cadr-cli::tree-selector-state-folded
           state))))
    (cadr-cli::tree-selector-set-query state "")
    (cadr-cli::tree-selector-select-id
     state "asst-2")
    (cadr-cli::tree-selector-fold-or-up state)
    (cadr-cli::tree-selector-fold-or-up state)
    (is (plusp
         (hash-table-count
          (cadr-cli::tree-selector-state-folded
           state))))
    (cadr-cli::tree-selector-set-filter
     state :user-only)
    (is (zerop
         (hash-table-count
          (cadr-cli::tree-selector-state-folded
           state))))))

(test goal9-tree-selector-layout-matches-baseline-tree-viewport-and-label-shell
  (let* ((entries
           (append
            '((:id "root" :parent-id nil
               :type :message :role :user
               :text "root prompt")
              (:id "branch-a" :parent-id "root"
               :type :message :role :assistant
               :text "branch A")
              (:id "branch-b" :parent-id "root"
               :type :message :role :user
               :text "branch B" :label "keep"))
            (loop for index below 5
                  for parent = "branch-b" then id
                  for id = (format nil "tail-~D" index)
                  collect
                  (list
                   :id id :parent-id parent
                   :type :message
                   :role (if (evenp index)
                             :assistant :user)
                   :text (format nil "tail ~D" index)))))
         (state
           (cadr-cli::make-tree-selector-state
            :entries entries
            :current-leaf-id "tail-4"
            :initial-selected-id "root"
            :max-visible-lines 5))
         (width 100)
         (panel
           (cadr-cli::render-tree-selector state width))
         (plain
           (mapcar
            #'cadr-tui:strip-terminal-sequences
            panel))
         (tree-lines
           (mapcar
            #'cadr-tui:strip-terminal-sequences
            (cadr-cli::tree-selector-render-lines
             state width))))
    (is (string= "" (first plain)))
    (is (= width
           (cadr-tui:visible-width
            (second panel))))
    (is (string= (format nil "~VA" width "   Session Tree")
                 (third plain)))
    (is (< 1
           (count-if
            (lambda (word)
              (search word (fourth plain)
                      :test #'char-equal))
            '("move" "page" "branch" "copy"
              "label"))))
    (is (search "  Type to search:"
                (format nil "~{~A~^~%~}" plain)))
    (is (search "• user: root prompt"
                (first tree-lines)))
    (is (search "├⊟ • [keep] user: branch B"
                (second tree-lines)))
    (is (search "│     • assistant: tail 0"
                (third tree-lines)))
    (is (= 6 (length tree-lines)))
    (is (search "(1/8)"
                (car (last tree-lines))))
    (cadr-cli::tree-selector-select-id state "tail-4")
    (let ((scrolled
            (mapcar
             #'cadr-tui:strip-terminal-sequences
             (cadr-cli::tree-selector-render-lines
              state width))))
      (is (= 6 (length scrolled)))
      (is (search "tail 4"
                  (nth 3 scrolled)))
      (is (search "└─ assistant: branch A"
                  (nth 4 scrolled)))
      (is (search "(7/8)"
                  (car (last scrolled)))))
    (cadr-cli::tree-selector-select-id state "branch-b")
    (cadr-cli::tree-selector-start-label-edit state)
    (setf
     (cadr-cli::tree-selector-state-label-input state)
     "renamed")
    (multiple-value-bind
          (label-panel label-row label-column)
        (cadr-cli::render-tree-selector state width)
      (let* (
           (label-plain
             (mapcar
              #'cadr-tui:strip-terminal-sequences
              label-panel))
           (joined
             (format nil "~{~A~^~%~}" label-plain)))
      (is (string= (format nil "~VA" width "   Session Tree")
                   (third label-plain)))
      (is (search "Type to search:" joined))
      (is (search "  Label (empty to remove):"
                  joined))
      (is (search "> renamed" joined))
      (is (= 9 label-row))
      (is (= 11 label-column))
      (is (not (search "Edit Label" joined)))))))

(test goal9-fork-history-overlay-matches-baseline-message-layout
  (let* ((items
           (loop for index from 1 to 12
                 collect
                 (cadr-tui:make-select-item
                  :label
                  (format nil "message ~D~%second line" index)
                  :value (format nil "entry-~D" index))))
         (state
           (cadr-cli::make-user-message-selector-state
            :items items))
         (lines
           (cadr-cli::render-user-message-selector
            state 80))
         (plain
           (mapcar
            #'cadr-tui:strip-terminal-sequences
            lines)))
    (is (string= "" (first plain)))
    (is (string= (format nil "~80A" " Fork from Message")
                 (second plain)))
    (is (search
         "Select a user message to copy the active path"
         (third plain)))
    (is (search "new"
                (third plain)))
    (is (search "session"
                (fourth plain)))
    (is (string= "" (fifth plain)))
    (is (= 80
           (cadr-tui:visible-width
            (sixth lines))))
    (is (string= "" (seventh plain)))
    (is (some
         (lambda (line)
           (search "› message 12 second line" line))
         plain))
    (is (some
         (lambda (line)
           (string= "  Message 12 of 12" line))
         plain))
    (is (some
         (lambda (line)
           (string= "  (12/12)" line))
         plain))
    (multiple-value-bind (action value)
        (cadr-cli::user-message-selector-handle-event
         state
         (cadr-tui:make-input-event :kind :enter))
      (is (eq :select action))
      (is (string= "entry-12" value)))))

(defun selector-test-model (provider id &optional name)
  (cadr-ai:make-model
   :id id
   :name (or name id)
   :provider provider
   :api :openai-responses
   :base-url "https://example.invalid"
   :max-tokens 1024))

(defmacro with-selector-truecolor-theme (&body body)
  `(progn
     (cadr-tui:set-current-theme
      :dark
      :capabilities
      (cadr-tui:make-terminal-capabilities
       :true-color-p t))
     (unwind-protect
          (progn ,@body)
       (cadr-tui:reset-current-theme))))

(test goal9-fenced-code-path-matches-baseline-token-boundaries
  (with-selector-truecolor-theme
    (let ((rendered
            (cadr-cli::tui-syntax-highlight
             "typescript"
             (format
              nil
              "// note~%class Widget { run(value: string) { const result = 1 + ~S; return value + result1; } }"
              "x"))))
      (dolist
          (rgb
           '("106;153;85"
             "86;156;214"
             "220;220;170"
             "156;220;254"
             "206;145;120"
             "181;206;168"
             "78;201;176"))
        (is (search
             (format nil "~C[38;2;~Am"
                     #\Escape rgb)
             rendered)))
      (dolist
          (rgb '("212;212;212"))
        (is (null
             (search
              (format nil "~C[38;2;~Am"
                      #\Escape rgb)
              rendered))))
      (dolist (language '("python" "bash"))
        (is (string=
             "https://example.com"
             (cadr-cli::tui-syntax-highlight
              language
              "https://example.com"))))
      (is (string=
           (format nil
                   "~C[38;2;204;102;102m-old~C[39m~%~C[38;2;181;189;104m+new~C[39m~%"
                   #\Escape #\Escape
                   #\Escape #\Escape)
           (cadr-cli::tui-syntax-highlight
            "diff" (format nil "-old~%+new~%"))))
      (is (search
           (format nil
                   "~C[38;2;206;145;120m/foo+/gi~C[39m"
                   #\Escape #\Escape)
           (cadr-cli::tui-syntax-highlight
            "javascript" "const re = /foo+/gi;")))
      (is (string=
           (format nil
                   "~C[38;2;128;128;128m@decorator~C[39m"
                   #\Escape #\Escape)
           (cadr-cli::tui-syntax-highlight
            "python" "@decorator")))
      (is (search
           (format nil
                   "~C[38;2;86;156;214mdiv~C[39m"
                   #\Escape #\Escape)
           (cadr-cli::tui-syntax-highlight
            "html" "<div></div>")))
      (is (search
           (format nil
                   "~C[38;2;86;156;214m+~C[39m"
                   #\Escape #\Escape)
           (cadr-cli::tui-syntax-highlight
            "lisp" "(+ 1 2)"))))))

(test goal9-session-and-tree-selectors-match-baseline-selected-backgrounds
  (with-selector-truecolor-theme
    (let* ((width 30)
           (session
             (cadr-cli::make-session-selector-state
              :current-sessions
              (list
               (session-record
                "selected" 2 "界界 selected")
               (session-record
                "other" 1 "other"))))
           (session-lines
             (cadr-cli::render-session-selector
              session width))
           (selected-session
             (find-if
              (lambda (line)
                (search "界界 selected"
                        (cadr-tui:strip-terminal-sequences
                         line)))
              session-lines))
           (tree
             (cadr-cli::make-tree-selector-state
              :entries
              '((:id "root" :parent-id nil
                 :type :message :role :user
                 :text "界界 root")
                (:id "child" :parent-id "root"
                 :type :message :role :assistant
                 :text "child"))
              :current-leaf-id "child"
              :initial-selected-id "root"))
           (tree-lines
             (cadr-cli::tree-selector-render-lines
              tree width))
           (tree-panel
             (cadr-cli::render-tree-selector
              tree width))
           (selected-tree (first tree-lines)))
      (dolist (line
               (append session-lines tree-lines
                       tree-panel))
        (is (<= (cadr-tui:visible-width line)
                width)))
      (is (string= ""
                   (cadr-tui:strip-terminal-sequences
                    (first session-lines))))
      (is (= width
             (cadr-tui:visible-width
              (second session-lines))))
      (is (= width
             (cadr-tui:visible-width
              (car (last session-lines)))))
      (is (string= ""
                   (cadr-tui:strip-terminal-sequences
                    (first tree-panel))))
      (is (= width
             (cadr-tui:visible-width
              (second tree-panel))))
      (is (= width
             (cadr-tui:visible-width
              (car (last tree-panel)))))
      (is (not (null selected-session)))
      (is (= width
             (cadr-tui:visible-width
              selected-session)))
      (is (not (null selected-tree)))
      (is (< (cadr-tui:visible-width selected-tree)
             width))
      (dolist (line (list selected-session selected-tree))
        (is (uiop:string-prefix-p
             (format nil "~C[48;2;58;58;74m"
                     #\Escape)
             line))
        (is (search
             (format nil "~C[49m" #\Escape)
             line)))
      (is (search
           (format nil "~C[38;2;102;102;102m"
                   #\Escape)
           (format nil "~{~A~^~%~}" session-lines)))
      (is (search
           (format nil "~C[38;2;128;128;128m"
                   #\Escape)
           (format nil "~{~A~^~%~}" tree-lines))))))

(test goal9-session-selector-labels-neutralize-terminal-controls
  (let* ((escape (string #\Escape))
         (record
           (session-record
            "unsafe" 1
            (format nil
                    "first~%second~Ctab~A[2Jclear~Cend"
                    #\Tab escape (code-char 127))))
         (label
           (cadr-cli::session-selector-record-label
            record)))
    (is (string=
         "first second tab [2Jclear end"
         label))
    (is (null (find-if
               (lambda (character)
                 (let ((code
                         (char-code character)))
                   (or (<= code 31)
                       (= code 127))))
               label)))))

(test goal18-session-selector-falls-back-to-no-messages
  ;; Baseline session-manager.ts:759 + session-selector.ts:461 — the
  ;; row label is name ?? firstMessage, and firstMessage falls back to
  ;; "(no messages)", never to the session id.
  (let ((record (session-record "render-session" 1 "")))
    (is (string= "(no messages)"
                 (cadr-cli::session-selector-record-label record))))
  (let ((record (session-record "named" 1 "" :name "My Session")))
    (is (string= "My Session"
                 (cadr-cli::session-selector-record-label record)))))

(test goal18-session-search-record-matches-the-baseline-corpus
  ;; Baseline session-manager.ts:717-734 — the search corpus holds
  ;; user and assistant texts only; firstMessage is the first user
  ;; message with text.
  (with-test-directory (root)
    (let ((session
            (cadr-agent:create-session
             :directory (merge-pathnames "sessions/" root)
             :cwd root
             :id "corpus-check")))
      (cadr-agent:session-append-message
       session
       (cadr-ai:make-assistant-message
        :content (list (cadr-ai::make-text-content
                        :text "assistant words"))))
      (cadr-agent:session-append-message
       session
       (cadr-ai:make-tool-result-message
        :tool-call-id "t1" :tool-name "bash"
        :content (list (cadr-ai::make-text-content
                        :text "tool secret"))))
      (cadr-agent:session-append-message
       session
       (cadr-ai:make-user-message :content "user question"))
      (let ((record
              (cadr-cli::session-to-search-record session)))
        (is (string= "user question"
                     (cadr-cli::session-search-record-first-message
                      record)))
        (is (string= "assistant words
user question"
                     (cadr-cli::session-search-record-all-messages-text
                      record)))
        (is (not (search "tool secret"
                         (cadr-cli::session-search-record-all-messages-text
                          record))))))))

(test goal18-session-search-haystack-includes-id-and-cwd
  ;; Baseline session-selector-search.ts:27 — the haystack is
  ;; `${id} ${name ?? ""} ${allMessagesText} ${cwd}`.
  (let* ((record
           (session-record "abc123session" 1 "some text"
                           :cwd "/tmp/worktree"))
         (haystack (cadr-cli::search-record-haystack record)))
    (is (search "abc123session" haystack))
    (is (search "some text" haystack))
    (is (search "/tmp/worktree" haystack))))

(test goal9-model-selector-uses-borders-spacers-and-semantic-row-colors
  (with-selector-truecolor-theme
    (let* ((current
             (selector-test-model :faux "model-00"))
           (models
             (loop for index below 12
                   collect
                   (selector-test-model
                    (if (evenp index) :faux :other)
                    (format nil "model-~2,'0D" index))))
           (state
             (cadr-cli::make-model-selector-state
              :all-models models
              :current-model current))
           (width 30)
           (lines
             (cadr-cli::render-model-selector
              state width))
           (plain
             (mapcar
              #'cadr-tui:strip-terminal-sequences
              lines))
           (model-lines
             (remove-if-not
              (lambda (line)
                (cl-ppcre:scan
                 "^(?:→ |  )model-[0-9][0-9] \\["
                 line))
              plain))
           (selected-line
             (let ((position
                     (position-if
                      (lambda (line)
                        (search "→ model-00" line))
                      plain)))
               (and position
                    (nth position lines)))))
      (is (= 10 (length model-lines)))
      (is (= width
             (cadr-tui:visible-width
              (first lines))))
      (is (= width
             (cadr-tui:visible-width
              (car (last lines)))))
      (is (every
           (lambda (character)
             (char= character #\─))
           (cadr-tui:strip-terminal-sequences
            (first lines))))
      (is (string= "" (second plain)))
      (is (string= ""
                   (nth (- (length plain) 2)
                        plain)))
      (is (search
           (format nil "~C[38;2;138;190;183m"
                   #\Escape)
           selected-line))
      (is (search
           (format nil "~C[38;2;128;128;128m"
                   #\Escape)
           selected-line))
      (is (search
           (format nil "~C[38;2;181;189;104m ✓"
                   #\Escape)
           selected-line))
      (is (every
           (lambda (line)
             (<= (cadr-tui:visible-width line)
                 width))
           lines)))))

(test goal9-settings-trust-and-scoped-selectors-are-semantic-and-narrow-safe
  (with-selector-truecolor-theme
    (let* ((settings
             (cadr-cli::make-settings-selector-state
              :options
              (list
               (cadr-cli::make-settings-option
                :id "one" :label "界界 setting"
                :description "A long muted description"
                :value t :values (list t nil))
               (cadr-cli::make-settings-option
                :id "two" :label "Other"
                :value nil :values (list t nil)))))
           (trust
             (cadr-cli::make-trust-selector-state
              :cwd "/tmp/界界-project/"
              :saved-entry
              '(:path "/tmp/界界-project/"
                :decision t)
              :project-trusted-p t))
           (model
             (selector-test-model
              :faux "界界-model" "Wide Model"))
           (scoped
             (cadr-cli::make-scoped-models-selector-state
              :all-models (list model)
              :enabled-ids (list "faux/界界-model")))
           (width 16)
           (groups
             (list
              (cons nil
                    (cadr-cli::render-settings-selector
                     settings width))
              (cons nil
                    (cadr-cli::render-trust-selector
                     trust width))
              (cons nil
                    (cadr-cli::render-scoped-models-selector
                     scoped width)))))
      (dolist (group groups)
        (let ((selected-background-p (car group))
              (lines (cdr group)))
        (is (every
             (lambda (line)
               (<= (cadr-tui:visible-width line)
                   width))
             lines))
        (let ((rendered
                (format nil "~{~A~^~%~}" lines)))
          (is (search
               (format nil "~C[38;2;138;190;183m"
                       #\Escape)
               rendered))
          ;; Input owns plain text/cursor styling in the baseline; muted text
          ;; is optional per selector content and is not a shell invariant.
          (is (search
               (format nil "~C[38;2;102;102;102m"
                       #\Escape)
               rendered))
          (if selected-background-p
              (is (search
                   (format nil "~C[48;2;58;58;74m"
                           #\Escape)
                   rendered))
              (is (null
                   (search
                    (format nil "~C[48;2;58;58;74m"
                            #\Escape)
                    rendered))))))))))

(test model-selector-preserves-scope-order-and-resets-query-selection
  (let* ((alpha-1
           (selector-test-model
            :faux "alpha-1" "Alpha One"))
         (alpha-2
           (selector-test-model
            :faux "alpha-2" "Alpha Two"))
         (alpha-3
           (selector-test-model
            :faux "alpha-3" "Alpha Three"))
         (beta
           (selector-test-model
            :faux "beta-1" "Beta One"))
         (state
           (cadr-cli::make-model-selector-state
            :all-models
            (list alpha-1 alpha-2 alpha-3 beta)
            :scoped-models
            (list alpha-2 alpha-3 alpha-1)
            :current-model alpha-1)))
    (is (eq :scoped
            (cadr-cli::model-selector-state-scope
             state)))
    (is (equal
         '("alpha-2" "alpha-3" "alpha-1")
         (mapcar
          #'cadr-ai:model-id
          (cadr-cli::model-selector-visible-models
           state))))
    (is (string=
         "alpha-1"
         (cadr-ai:model-id
          (cadr-cli::model-selector-selected-model
           state))))
    (cadr-cli::model-selector-set-query
     state "alpha")
    (is (string=
         "alpha-2"
         (cadr-ai:model-id
          (cadr-cli::model-selector-selected-model
           state))))
    (cadr-cli::model-selector-handle-event
     state
     (cadr-tui:make-input-event :kind :tab))
    (is (eq :all
            (cadr-cli::model-selector-state-scope
             state)))
    (cadr-cli::model-selector-handle-event
     state
     (cadr-tui:make-input-event :kind :down))
    (cadr-cli::model-selector-handle-event
     state
     (cadr-tui:make-input-event :kind :down))
    (is (string=
         "alpha-3"
         (cadr-ai:model-id
          (cadr-cli::model-selector-selected-model
           state))))
    (cadr-cli::model-selector-set-query
     state "alpha")
    (is (string=
         "alpha-1"
         (cadr-ai:model-id
          (cadr-cli::model-selector-selected-model
           state))))
    (is (not
         (search
          "beta-1"
          (format
           nil "~{~A~^~%~}"
           (cadr-cli::render-model-selector
            state 100)))))))

(test scoped-models-selector-keeps-unavailable-ids-and-session-order
  (let* ((one
           (selector-test-model :faux "one" "One"))
         (two
           (selector-test-model :faux "two" "Two"))
         (three
           (selector-test-model :faux "three" "Three"))
         (other
           (selector-test-model :other "four" "Four"))
         (unavailable "faux/unavailable")
         (changes nil)
         (persisted nil)
         (state
           (cadr-cli::make-scoped-models-selector-state
            :all-models (list one two three other)
            :enabled-ids
            (list unavailable "faux/one" "faux/two")
            :change-callback
            (lambda (ids)
              (push ids changes))
            :persist-callback
            (lambda (ids)
              (push ids persisted)))))
    (is (search
         "faux/unavailable [unavailable] ✗"
         (cadr-tui:strip-terminal-sequences
          (format
           nil "~{~A~^~%~}"
           (cadr-cli::render-scoped-models-selector
            state 120)))))
    (cadr-cli::scoped-models-selector-handle-event
     state
     (cadr-tui:make-input-event :kind :enter))
    (is (equal
         '("faux/one" "faux/two")
         (first changes)))
    (cadr-cli::scoped-models-selector-select-id
     state "faux/one")
    (multiple-value-bind (action value handled-p)
        (cadr-cli::scoped-models-selector-handle-raw-input
         state
         (format nil "~C[1;3B" #\Escape))
      (declare (ignore value))
      (is (eq :changed action))
      (is (eq t handled-p)))
    (is (equal
         '("faux/two" "faux/one")
         (first changes)))
    (multiple-value-bind (action value handled-p)
        (cadr-cli::scoped-models-selector-handle-raw-input
         state
         (string (code-char 19)))
      (declare (ignore value))
      (is (eq :changed action))
      (is (eq t handled-p)))
    (is (equal
         '("faux/two" "faux/one")
         (first persisted)))
    (is (equal
         '("two" "one")
         (mapcar
          #'cadr-ai:model-id
          (cadr-cli::session-scoped-models
           (list one two three other)
           (first changes)))))
    (is (null
         (cadr-cli::session-scoped-models
          (list one two three other)
          :all)))
    (is (null
         (cadr-cli::session-scoped-models
          (list one two three other)
          nil)))))

(test scoped-models-selector-honors-configurable-actions
  (let* ((one
           (selector-test-model :faux "one"))
         (two
           (selector-test-model :faux "two"))
         (changes nil)
         (state
           (cadr-cli::make-scoped-models-selector-state
            :all-models (list one two)
            :enabled-ids (list "faux/one")
            :change-callback
            (lambda (ids)
              (push ids changes))
            :keybindings
            (cadr-cli::make-models-selector-keybindings
             '(("app.models.enableAll"
                . ("ctrl+y")))))))
    (multiple-value-bind (action value handled-p)
        (cadr-cli::scoped-models-selector-handle-raw-input
         state
         (string (code-char 1)))
      (declare (ignore action value))
      (is (null handled-p)))
    (multiple-value-bind (action value handled-p)
        (cadr-cli::scoped-models-selector-handle-raw-input
         state
         (string (code-char 25)))
      (declare (ignore value))
      (is (eq :changed action))
      (is (eq t handled-p)))
    (is (eq :all (first changes)))))

(test trust-selector-marks-inherited-decisions-and-returns-atomic-updates
  (with-test-directory (root)
    (let* ((parent
             (merge-pathnames "parent/" root))
           (cwd
             (merge-pathnames "project/" parent))
           (store
             (cadr-cli::make-project-trust-store
              (merge-pathnames "trust.json" root))))
      (ensure-directories-exist
       (merge-pathnames "anchor" cwd))
      (cadr-cli::project-trust-set
       store parent t)
      (let* ((state
               (cadr-cli::make-trust-selector-state
                :cwd cwd
                :saved-entry
                (cadr-cli::project-trust-entry
                 store cwd)
                :project-trusted-p t))
             (rendered
               (format
                nil "~{~A~^~%~}"
                (cadr-cli::render-trust-selector
                 state 160))))
        (is (search
             "Saved decision: trusted (inherited from"
             rendered))
        (is (search
             "Current session: trusted"
             rendered))
        (is (search
             "Trust parent folder"
             rendered))
        (multiple-value-bind (action selection)
            (cadr-cli::trust-selector-handle-event
             state
             (cadr-tui:make-input-event
              :kind :submit))
          (is (eq :select action))
          (is (eq t
                  (getf selection :trusted-p)))
          (is (equal
               (list
                (list
                 :path
                 (cadr-cli::canonical-directory-name
                  parent)
                 :decision t)
                (list
                 :path
                 (cadr-cli::canonical-directory-name
                  cwd)
                 :decision :remove))
               (getf selection :updates))))))))

(test settings-selector-cycles-values-in-place-and-keeps-cli-glue-ownership
  (let* ((changes nil)
         (selector
          (cadr-cli::make-settings-selector-state
           :options
           (list
            (cadr-cli::make-settings-option
             :id "autocompact"
             :label "Auto-compact"
             :description
             "Automatically compact context"
             :value t
             :values (list t nil))
            (cadr-cli::make-settings-option
             :id "transport"
             :label "Transport"
             :description "Provider transport"
             :value "sse"
             :values
             '("sse" "websocket" "auto")))
           :change-callback
           (lambda (id value)
             (push (cons id value)
                   changes)))))
    (let ((rendered
            (format
             nil "~{~A~^~%~}"
             (cadr-cli::render-settings-selector
              selector 80))))
      (is (null (search "Settings" rendered)))
      (is (search "Auto-compact" rendered))
      (is (search "true" rendered)))
    (multiple-value-bind (action value)
        (cadr-cli::settings-selector-handle-event
         selector
         (cadr-tui:make-input-event
          :kind :enter))
      (is (eq :changed action))
      (is (string= "autocompact"
                   (getf value :id)))
      (is (null (getf value :value))))
    (is (equal '(("autocompact"))
               changes))
    (cadr-cli::settings-selector-handle-event
     selector
     (cadr-tui:make-input-event
      :kind :down))
    (cadr-cli::settings-selector-handle-event
     selector
     (cadr-tui:make-input-event
      :kind :enter))
    (is (equal
         '(("transport" . "websocket")
           ("autocompact"))
         changes))
    (multiple-value-bind (action value)
        (cadr-cli::settings-selector-handle-event
         selector
         (cadr-tui:make-input-event
          :kind :escape))
      (is (eq :cancel action))
      (is (null value)))))

(test goal17-settings-selector-does-not-position-an-unfocused-search-cursor
  ;; pi@13cbf77df settings-selector.ts:860 returns SettingsList as the focus
  ;; target, but SettingsList is not Focusable and its private Input therefore
  ;; emits no CURSOR_MARKER.  Moving the hardware cursor to a clipped search
  ;; row corrupts the next differential frame on narrow terminals.
  (let ((state
          (cadr-cli::make-settings-selector-state
           :options
           (list
            (cadr-cli::make-settings-option
             :id "one" :label "One" :description "First"
             :value t :values (list t nil))))))
    (multiple-value-bind (lines cursor-row cursor-column)
        (cadr-cli::render-settings-selector state 48)
      (is (consp lines))
      (is (null cursor-row))
      (is (null cursor-column)))))

(defclass goal17-update-test-terminal
    (cadr-tui::virtual-terminal)
  ((inputs
    :initarg :inputs
    :accessor goal17-update-test-terminal-inputs)))

(defmethod cadr-tui:terminal-read-input
    ((terminal goal17-update-test-terminal))
  (let ((next
          (first
           (goal17-update-test-terminal-inputs
            terminal))))
    (cond
      ((null next) "")
      ((functionp next)
       (let ((value (funcall next terminal)))
         (if value
             (progn
               (pop
                (goal17-update-test-terminal-inputs
                 terminal))
               value)
             "")))
      (t
       (pop
        (goal17-update-test-terminal-inputs
         terminal))))))

(defun goal17-update-screen-contains-p (terminal text)
  (search
   text
   (format
    nil "~{~A~^~%~}"
    (cadr-tui:virtual-terminal-snapshot
     terminal))))

(test goal17-tui-startup-runs-both-real-update-notification-check-surfaces
  (let* ((release (make-hash-table :test #'equal))
         (terminal
           (make-instance
            'goal17-update-test-terminal
            :columns 80 :rows 40
            :inputs
            (list
             (lambda (value)
               (and
                (goal17-update-screen-contains-p
                 value "Update Available")
                (goal17-update-screen-contains-p
                 value "Package Updates Available")
                (format nil "/quit~C" #\Return)))))))
    (cadr-ai::json-put release "version" "9.9.9")
    (cadr-ai::json-put release "note" "Release note")
    (cadr-cli::run-tui
     (constantly nil)
     :model "faux"
     :terminal terminal
     :sleep-function (constantly nil)
     :version-update-check-function
     (lambda () release)
     :package-update-check-function
     (lambda () '("alpha" "beta")))
    (is
     (goal17-update-screen-contains-p
      terminal "New version 9.9.9 is available."))
    (is
     (goal17-update-screen-contains-p
      terminal "Package updates are available."))))

(test goal17-update-notifications-use-the-baseline-controller-surface
  ;; pi@13cbf77df interactive-mode.ts:3928-3973 exposes both notification
  ;; methods publicly after INIT.  These assertions come from that component
  ;; composition, not from Cadr's current rendering.
  (cadr-tui:set-current-theme :dark)
  (flet ((pad (text)
           (concatenate
            'string text
            (make-string (- 80 (length text))
                         :initial-element #\Space))))
    (let ((state (cadr-cli::make-tui-state)))
    (cadr-cli::add-tui-version-update-notification
     state "9.9.9" "Release note")
    (cadr-cli::add-tui-package-update-notification
     state '("alpha" "beta"))
    (let* ((entries (cadr-cli::tui-state-entries state))
           (version-lines
             (mapcar #'cadr-tui::strip-ansi
                     (cadr-cli::render-tui-entry (first entries) 80)))
           (package-lines
             (mapcar #'cadr-tui::strip-ansi
                     (cadr-cli::render-tui-entry (second entries) 80))))
      (is (equal
           (list
            ""
            (make-string 80 :initial-element #\─)
            (pad " Update Available")
            (pad " New version 9.9.9 is available. Run cadr update")
            ""
            (pad " Release note")
            ""
            (pad " Changelog: https://github.com/artwalker/cadr/blob/main/CHANGELOG.md")
            (make-string 80 :initial-element #\─))
           version-lines))
      (is (equal
           (list
            ""
            (make-string 80 :initial-element #\─)
            (pad " Package Updates Available")
            (pad " Package updates are available. Run cadr update --extensions")
            (pad " Packages:")
            (pad " - alpha")
            (pad " - beta")
            (make-string 80 :initial-element #\─))
           package-lines))))))

(test goal17-version-update-changelog-link-honors-terminal-capabilities
  ;; pi@13cbf77df terminal-image.ts:526-528 and interactive-mode.ts:3932-3935
  ;; style the visible URL inside an OSC 8 link terminated with ST.  Compare
  ;; the complete rendered line so BEL termination or reversed ANSI nesting
  ;; cannot hide behind SEARCH or STRIP-ANSI.
  (let ((original (cadr-tui:get-terminal-capabilities))
        (width 100)
        (url (cadr-ai::cadr-changelog-url)))
    (unwind-protect
         (labels
             ((render-changelog-line (hyperlinks-p)
                (cadr-tui:set-terminal-capabilities
                 (cadr-tui:make-terminal-capabilities
                  :hyperlinks-p hyperlinks-p))
                (let ((state (cadr-cli::make-tui-state)))
                  (cadr-cli::add-tui-version-update-notification
                   state "9.9.9")
                  (nth
                   4
                   (cadr-cli::render-tui-entry
                    (first
                     (cadr-cli::tui-state-entries state))
                    width))))
              (expected-line (hyperlinks-p)
                (let* ((styled-url
                         (cadr-tui:theme-foreground
                          :accent url :enabled-p t))
                       (visible-url
                         (if hyperlinks-p
                             (cadr-tui:terminal-hyperlink
                              styled-url url)
                             styled-url))
                       (content
                         (concatenate
                          'string
                          (cadr-tui:theme-foreground
                           :muted "Changelog: " :enabled-p t)
                          visible-url))
                       (padded
                         (concatenate
                          'string " " content
                          (make-string
                           (- width 1
                              (cadr-tui:visible-width content))
                           :initial-element #\Space))))
                  padded)))
           (is
            (string=
             (expected-line nil)
             (render-changelog-line nil)))
           (let ((linked (render-changelog-line t)))
             (is (string= (expected-line t) linked))
             (is (null (position (code-char 7) linked)))))
      (cadr-tui:set-terminal-capabilities original))))

(test goal17-update-title-and-border-ansi-nesting-matches-pi
  ;; pi@13cbf77df interactive-mode.ts:3941-3944 composes
  ;; bold(fg(warning, title)); DynamicBorder applies only fg(warning, border).
  ;; Lock the complete raw lines so reversed reset ordering cannot pass.
  (let* ((width 80)
         (state (cadr-cli::make-tui-state)))
    (cadr-cli::add-tui-version-update-notification
     state "9.9.9")
    (cadr-cli::add-tui-package-update-notification
     state '("alpha"))
    (flet ((padded-line (content)
             (concatenate
              'string " " content
              (make-string
               (- width 1
                  (cadr-tui:visible-width content))
               :initial-element #\Space)))
           (expected-title (text)
             (cadr-tui:theme-bold
              (cadr-tui:theme-foreground
               :warning text :enabled-p t)
              :enabled-p t)))
      (let* ((entries (cadr-cli::tui-state-entries state))
             (version-lines
               (cadr-cli::render-tui-entry
                (first entries) width))
             (package-lines
               (cadr-cli::render-tui-entry
                (second entries) width))
             (border
               (cadr-tui:theme-foreground
                :warning
                (make-string width :initial-element #\─)
                :enabled-p t)))
        (is (string= border (second version-lines)))
        (is (string= border (car (last version-lines))))
        (is
         (string=
          (padded-line
           (expected-title "Update Available"))
          (third version-lines)))
        (is (string= border (second package-lines)))
        (is (string= border (car (last package-lines))))
        (is
         (string=
          (padded-line
           (expected-title "Package Updates Available"))
          (third package-lines)))))))

(test cli-settings-selector-persists-and-applies-live-agent-settings
  (let* ((manager
           (cadr-cli::make-memory-settings-manager))
         (model
           (cadr-ai:make-model
            :id "reasoning"
            :name "Reasoning"
            :provider :faux
            :api :openai-responses
            :base-url "https://example.invalid"
            :max-tokens 1024
            :reasoning-p t))
         (agent
           (cadr-agent:make-agent
            :provider nil
            :model model))
         (selector
           (cadr-cli::make-cli-settings-selector-state
            manager agent
            (cadr-cli::make-resource-snapshot))))
    (labels
        ((select-option (id)
           (setf
            (cadr-cli::settings-selector-state-selected
             selector)
            (position
             id
             (cadr-cli::settings-selector-state-options
              selector)
             :key #'cadr-cli::settings-option-id
             :test #'string=))
           (cadr-cli::settings-selector-handle-event
            selector
            (cadr-tui:make-input-event
             :kind :enter))))
      (select-option "autocompact")
      (is (null
           (cadr-agent::agent-auto-compact-p
            agent)))
      (is (null
           (cadr-cli::settings-nested-value
            manager "compaction" "enabled" t)))
      (select-option "steering-mode")
      (is (eq :all
              (cadr-agent:agent-steering-mode
               agent)))
      (is (string=
           "all"
           (cadr-cli::settings-value
            manager "steeringMode")))
      (cadr-cli::set-cli-thinking-level
       agent manager :minimal :persist t)
      (is (eq :minimal
              (cadr-agent::agent-thinking-level
               agent)))
      (is (string=
           "minimal"
           (cadr-cli::settings-value
            manager "defaultThinkingLevel"))))))

(test oauth-selector-projects-provider-auth-and-renders-status-sources
  (let* ((anthropic
           (cadr-ai::make-provider-definition
            :id :anthropic
            :name "Anthropic"
            :protocol :anthropic-messages
            :base-url "https://example.invalid"
            :auth-types '(:oauth :api-key)
            :default-model "claude"))
         (vertex
           (cadr-ai::make-provider-definition
            :id :google-vertex
            :name "Google Vertex AI"
            :protocol :google-vertex
            :base-url "https://example.invalid"
            :auth-types '(:api-key)
            :default-model "gemini"))
         (api-options
           (cadr-cli::login-provider-options
            (list anthropic vertex)
            :auth-type :api-key))
         (oauth-options
           (cadr-cli::login-provider-options
            (list anthropic vertex)
            :auth-type :oauth)))
    (is (equal
         '(:anthropic :google-vertex)
         (mapcar
          #'cadr-cli::oauth-selector-option-id
          api-options)))
    (is (equal
         '(:anthropic)
         (mapcar
          #'cadr-cli::oauth-selector-option-id
          oauth-options)))
    (dolist
        (case
         (list
          (list
           (cadr-cli::make-oauth-selector-option
            :id :google
            :name "Google"
            :auth-type :api-key)
           "unconfigured")
          (list
           (cadr-cli::make-oauth-selector-option
            :id :anthropic
            :name "Anthropic"
            :auth-type :api-key
            :status
            '(:type :oauth :source "OAuth"))
           "subscription configured")
          (list
           (cadr-cli::make-oauth-selector-option
            :id :openai
            :name "OpenAI"
            :auth-type :api-key
            :status
            '(:type :api-key
              :source "OPENAI_API_KEY"))
           "✓ env: OPENAI_API_KEY")
          (list
           (cadr-cli::make-oauth-selector-option
            :id :local-proxy
            :name "local-proxy"
            :auth-type :api-key
            :status
            '(:type :api-key
              :source "key in models.json"))
           "✓ key in models.json")
          (list
           (cadr-cli::make-oauth-selector-option
            :id :op-proxy
            :name "op-proxy"
            :auth-type :api-key
            :status
            '(:type :api-key
              :source "command in models.json"))
           "✓ command in models.json")))
      (destructuring-bind (option expected) case
        (let ((rendered
                (format
                 nil "~{~A~^~%~}"
                 (cadr-cli::render-oauth-selector
                  (cadr-cli::make-oauth-selector-state
                   :mode :login
                   :options (list option))
                  120))))
          (is (search expected rendered)))))))

(test tool-result-images-normalize-once-entering-history
  ;; pi@13cbf77df utils/tool-result-images.ts — a BMP tool-result
  ;; block becomes PNG with a hints text block; a clean PNG passes
  ;; through with the content array identity preserved.
  (let* ((bmp
           (make-array
            58 :element-type '(unsigned-byte 8)
            :initial-element 0)))
    (setf
     (aref bmp 0) (char-code #\B)
     (aref bmp 1) (char-code #\M)
     (aref bmp 2) 58
     (aref bmp 10) 54
     (aref bmp 14) 40
     (aref bmp 18) 1
     (aref bmp 22) 1
     (aref bmp 26) 1
     (aref bmp 28) 24
     (aref bmp 56) 255)
    (let* ((image-block
             (cadr-ai:make-image-content
              :data (cadr-cli::encode-base64-bytes bmp)
              :mime-type "image/bmp"))
           (text-block
             (cadr-ai:make-text-content :text "done"))
           (content (list image-block text-block))
           (normalized
             (cadr-cli::normalize-tool-result-images content)))
      (is (= 3 (length normalized)))
      (is (typep (first normalized) 'cadr-ai:image-content))
      (is (string=
           "image/png"
           (cadr-ai:image-content-mime-type
            (first normalized))))
      (is (typep (second normalized) 'cadr-ai:text-content))
      (is (search
           "converted"
           (string-downcase
            (cadr-ai:text-content-text
             (second normalized)))))
      (is (eq text-block (third normalized))))
    ;; no image blocks: the same array returns unchanged
    (let ((content
            (list (cadr-ai:make-text-content :text "plain"))))
      (is (eq content
              (cadr-cli::normalize-tool-result-images content))))
    ;; an already-fine PNG keeps its block (no hints, same bytes)
    (let* ((png
             (cadr-cli::encode-rgba-png
              (make-array 4 :element-type '(unsigned-byte 8)
                          :initial-element 255)
              1 1))
           (block
             (cadr-ai:make-image-content
              :data (cadr-cli::encode-base64-bytes png)
              :mime-type "image/png"))
           (content (list block))
           (normalized
             (cadr-cli::normalize-tool-result-images content)))
      (is (= 1 (length normalized)))
      (is (eq block (first normalized))))))

(test tool-render-session-shares-state-and-keeps-pending-result-hidden
  (let ((session
          (cadr-cli:make-tool-render-session
           :name "custom"
           :arguments '(:foo "bar")
           :call-renderer
           (lambda (arguments state)
             (setf (gethash "token" state)
                   "shared")
             (format nil "call ~A"
                     (getf arguments :foo)))
           :result-renderer
           (lambda (result arguments state)
             (format nil "result ~A ~A ~A"
                     result
                     (getf arguments :foo)
                     (gethash "token" state))))))
    (is (equal
         '("call bar")
         (cadr-cli:render-tool-session
          session)))
    (cadr-cli:update-tool-render-session
     session "done" :pending-p nil)
    (is (equal
         '("call bar"
           "result done bar shared")
         (cadr-cli:render-tool-session
          session)))))

(test interactive-export-forwards-the-active-theme-without-changing-the-command-surface
  (with-test-directory (root)
    (let* ((sessions
             (merge-pathnames "sessions/" root))
           (session
             (cadr-agent:create-session
              :directory sessions :cwd root
              :id "interactive-theme-export"))
           (agent
             (cadr-agent:make-agent
              :provider :faux
              :model
              (cadr-ai:make-model
               :id "mock"
               :provider :faux
               :api :openai-responses
               :base-url "https://example.invalid"
               :max-tokens 128)
              :session session))
           (path
             (merge-pathnames "interactive.html" root))
           (theme
             (args
              "vars" (args "page" "#102030"
                           "card" "#203040"
                           "info" "#304050")
              "colors"
              (args "accent" "#123456"
                    "userMessageBg" "#405060")
              "export"
              (args "pageBg" "page"
                    "cardBg" "card"
                    "infoBg" "info"))))
      (cadr-agent:session-append-message
       session
       (cadr-ai:make-user-message
        :content "export me"))
      (is
       (cadr-cli::handle-session-command
        (format nil "/export ~A" (namestring path))
        agent
        :directory sessions
        :cwd root
        :output (make-broadcast-stream)
        :export-options-function
        (lambda ()
          (list :theme-name "project-theme"
                :theme-object theme))))
      (let ((html
              (uiop:read-file-string
               path :external-format :utf-8)))
        (is (search "--accent: #123456;" html))
        (is (search "--exportPageBg: #102030;" html))
        (is (search "--exportCardBg: #203040;" html))
        (is (search "--exportInfoBg: #304050;" html))
        (is (search "--body-bg: #102030;" html))
        (is (search "--container-bg: #203040;" html))
        (is (search "--info-bg: #304050;" html))))))
