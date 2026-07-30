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
            "maximum output token limit"
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
     "… Retrying (1/3) in 1s..."
     (make-string 40 :initial-element #\Space))
    (cadr-cli::render-tui-status-indicator
     "Retrying (1/3) in 1s..." 40))))

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
     &key name path parent-path)
  (cadr-cli:make-session-search-record
   :id id
   :path (or path
             (format nil "/tmp/~A.jsonl" id))
   :parent-path parent-path
   :name name
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
              "HEAD" git-directory)))
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
                :poll-seconds 0.01
                :debounce-seconds 0.02))
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
               (loop repeat 200
                     until
                     (string=
                      "feature"
                      (or
                       (cadr-cli:footer-data-provider-git-branch
                        provider)
                       ""))
                     do (sleep 0.01))
               (is (string=
                    "feature"
                    (cadr-cli:footer-data-provider-git-branch
                     provider)))
               (is (= 1 changes))
               (write-text
                head
                "ref: refs/heads/feature")
               (sleep 0.05)
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
               :poll-seconds 0.01
               :debounce-seconds 0.02))
        (unwind-protect
             (progn
               (is (string=
                    "main"
                    (cadr-cli:footer-data-provider-git-branch
                     provider)))
               (is (plusp symbolic-calls))
               (delete-file head)
               (sleep 0.05)
               (is (string=
                    "main"
                    (cadr-cli:footer-data-provider-git-branch
                     provider)))
               (write-text
                head "ref: refs/heads/recovered")
               (loop repeat 200
                     until
                     (string=
                      "recovered"
                      (or
                       (cadr-cli:footer-data-provider-git-branch
                        provider)
                       ""))
                     do (sleep 0.01))
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
               :poll-seconds 0.01
               :debounce-seconds 0.05))
        (unwind-protect
             (progn
               (is (= 1 calls))
               (sleep 0.08)
               (is (= 1 calls))
               (setf branch "feature")
               (write-text tables "1")
               (sleep 0.01)
               (write-text tables "2")
               (sleep 0.01)
               (write-text tables "3")
               (loop repeat 200
                     until
                     (string=
                      "feature"
                      (or
                       (cadr-cli:footer-data-provider-git-branch
                        provider)
                       ""))
                     do (sleep 0.01))
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
        (fallback
          (cadr-cli:detect-background-from-environment
           '(("OTHER" . "x")))))
    (is (eq :light
            (cadr-cli:theme-detection-theme
             light)))
    (is (eq :dark
            (cadr-cli:theme-detection-theme
             dark)))
    (is (eq :low
            (cadr-cli:theme-detection-confidence
             fallback))))
  (is (eq :dark
          (cadr-cli:rgb-background-theme
           8 8 8)))
  (is (eq :light
          (cadr-cli:rgb-background-theme
           250 250 250)))
  (is (string=
       "light"
       (cadr-cli:resolve-theme-setting
        "light/dark" :light)))
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

(test image-processing-detects-dimensions-converts-bmp-and-omits-unsafe-output
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
          :max-height 1)))))

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
                   (format nil "[s:~A]" text))))))
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
    (is (cadr-cli:supports-syntax-language-p
         "typescript"))
    (is (string=
         "[k:const] value = [n:1]"
         (cadr-cli:simple-syntax-highlight
          "const value = 1" "typescript"
          theme)))))

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
             (<= (length line) 30))
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
         (search "3/28 14:32"
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
      (is (search "3/28 14:32" rendered))
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

(defun selector-test-model (provider id &optional name)
  (cadr-ai:make-model
   :id id
   :name (or name id)
   :provider provider
   :api :openai-responses
   :base-url "https://example.invalid"
   :max-tokens 1024))

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
         (format
          nil "~{~A~^~%~}"
          (cadr-cli::render-scoped-models-selector
           state 120))))
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
      (is (search "Settings" rendered))
      (is (search "Auto-compact" rendered))
      (is (search "on" rendered)))
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
      (select-option "thinking")
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
