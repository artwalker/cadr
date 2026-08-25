(in-package #:cadr-cli)

(defun tool-summary-string (value)
  (cond
    ((stringp value)
     (values
      (cadr-tui:strip-terminal-sequences value)
      t))
    ((null value) (values "" t))
    (t (values "[invalid arg]" nil))))

(defun tool-header-segment
    (text &key token bold-p url)
  (list :text text :token token
        :bold-p bold-p :url url))

(defun tool-path-file-url (path cwd)
  (when (and (stringp path)
             (plusp (length path)))
    (handler-case
        (let ((absolute
                (namestring
                 (resolve-tool-path cwd path))))
          (concatenate
           'string "file://"
           (cadr-ai::sigv4-percent-encode
            absolute :preserve-slash-p t)))
      (condition () nil))))

(defun tool-path-segment
    (value cwd &key (empty-fallback "...")
                    (token :accent) hyperlink-p)
  (multiple-value-bind (text valid-p)
      (tool-summary-string value)
    (cond
      ((not valid-p)
       (tool-header-segment text :token :error))
      ((zerop (length text))
       (tool-header-segment
        empty-fallback :token :tool-output))
      (t
       (tool-header-segment
        (cadr-tui:shortened-home-prefix-path text)
        :token token
        :url (and hyperlink-p
                  (tool-path-file-url text cwd)))))))

(defun tool-read-range-segments (arguments)
  (let ((offset (cadr-ai::json-get arguments "offset"))
        (limit (cadr-ai::json-get arguments "limit")))
    (when (or (numberp offset)
              (numberp limit))
      (let* ((start (if (numberp offset) offset 1))
             (end
               (and (numberp limit)
                    (+ start limit -1))))
        (list
         (tool-header-segment
          (format nil ":~A~@[-~A~]" start end)
          :token :warning))))))

(defun tool-summary-segments (call &optional (cwd (uiop:getcwd)))
  (let* ((name (cadr-ai:tool-call-name call))
         (arguments (cadr-ai:tool-call-arguments call)))
    (labels
        ((value (key)
           (cadr-ai::json-get arguments key))
         (string-segment (value token &key prefix suffix bold-p)
           (multiple-value-bind (text valid-p)
               (tool-summary-string value)
             (list
              (tool-header-segment
               (if valid-p
                   (format nil "~A~A~A"
                           (or prefix "") text (or suffix ""))
                   text)
               :token (if valid-p token :error)
               :bold-p bold-p))))
         (limit-segment (format-control)
           (let ((limit (value "limit")))
             (and (numberp limit)
                  (list
                   (tool-header-segment
                    (format nil format-control limit)
                    :token :tool-output)))))
         (search-path-segments ()
           (multiple-value-bind (text valid-p)
               (tool-summary-string (value "path"))
             (list
              (if valid-p
                  (tool-header-segment
                   (cadr-tui:shortened-home-prefix-path
                    (if (plusp (length text)) text "."))
                   :token :tool-output)
                  (tool-header-segment text :token :error))))))
      (cond
        ((string-equal name "bash")
         (let ((timeout (value "timeout")))
           (append
            (multiple-value-bind (text valid-p)
                (tool-summary-string (value "command"))
              (list
               (tool-header-segment
                (if valid-p
                    (if (plusp (length text)) text "...")
                    text)
                :token
                (cond
                  ((not valid-p) :error)
                  ((zerop (length text)) :tool-output)
                  (t :tool-title))
                :bold-p (and valid-p
                             (plusp (length text))))))
            (and (numberp timeout)
                 (not (zerop timeout))
                 (list
                  (tool-header-segment
                   (format nil " (timeout ~As)" timeout)
                   :token :muted))))))
        ((string-equal name "read")
         (append
          (list
           (tool-path-segment
            (value "path") cwd :hyperlink-p t))
          (tool-read-range-segments arguments)))
        ((or (string-equal name "write")
             (string-equal name "edit"))
         (list
          (tool-path-segment
           (value "path") cwd :hyperlink-p t)))
        ((string-equal name "find")
         (append
          (string-segment (value "pattern") :accent)
          (list
           (tool-header-segment " in " :token :tool-output))
          (search-path-segments)
          (limit-segment " (limit ~A)")))
        ((string-equal name "grep")
         (append
          (string-segment
           (value "pattern") :accent
           :prefix "/" :suffix "/")
          (list
           (tool-header-segment " in " :token :tool-output))
          (search-path-segments)
          (let ((glob (value "glob")))
            (and (stringp glob)
                 (plusp (length glob))
                 (list
                  (tool-header-segment
                   (format nil " (~A)"
                           (cadr-tui:strip-terminal-sequences glob))
                   :token :tool-output))))
          (limit-segment " limit ~A")))
        ((string-equal name "ls")
         (append
          (list
           (tool-path-segment
            (value "path") cwd
            :empty-fallback "." :hyperlink-p t))
          (limit-segment " (limit ~A)")))
        (t
         (list
          (tool-header-segment
           (generic-tool-arguments-summary arguments)
           :token :accent)))))))

(defun generic-tool-arguments-summary (arguments)
  (handler-case
      (cadr-tui:strip-terminal-sequences
       (cadr-ai::stringify-json arguments))
    (condition ()
      (cadr-tui:strip-terminal-sequences
       (princ-to-string arguments)))))

(defun tool-arguments-summary (call &optional (cwd (uiop:getcwd)))
  (format nil "~{~A~}"
          (mapcar
           (lambda (segment) (getf segment :text))
           (tool-summary-segments call cwd))))

(defun tool-read-classification (call cwd)
  (handler-case
      (when (string-equal
             (cadr-ai:tool-call-name call) "read")
        (let ((raw
                (cadr-ai::json-get
                 (cadr-ai:tool-call-arguments call) "path")))
          (when (and (stringp raw)
                     (plusp (length raw)))
            (let* ((absolute
                     (resolve-tool-path cwd raw))
                   (filename (file-namestring absolute)))
              (cond
                ((string= filename "SKILL.md")
                 (list
                  :kind :skill
                  :label
                  (or
                   (car
                    (last
                     (pathname-directory
                      (uiop:pathname-directory-pathname
                       absolute))))
                   filename)))
                ((let* ((root
                          (ignore-errors
                            (asdf:system-source-directory
                             "cadr-cli")))
                        (relative
                          (and root
                               (cwd-relative-path
                                absolute root))))
                   (and
                    relative
                    (or
                     (string= relative "README.md")
                     (uiop:string-prefix-p
                      "docs/" relative)
                     (uiop:string-prefix-p
                      "examples/" relative))
                    (list
                     :kind :docs :label relative))))
                ((member
                  filename
                  '("AGENTS.override.md" "AGENTS.md"
                    "AGENTS.MD" "CLAUDE.md" "CLAUDE.MD")
                  :test #'string=)
                 (list
                  :kind :resource
                  :label
                  (format-path-relative-to-cwd-or-absolute
                   absolute cwd))))))))
    (condition () nil)))

(defun tool-header-segments (call cwd)
  (let* ((name (cadr-ai:tool-call-name call))
         (arguments (cadr-ai:tool-call-arguments call))
         (classification
           (tool-read-classification call cwd)))
    (if classification
        (append
         (if (eq (getf classification :kind) :skill)
             (list
              (tool-header-segment
               "[skill] " :token :custom-message-label
               :bold-p t)
              (tool-header-segment
               (getf classification :label)
               :token :custom-message-text))
             (list
              (tool-header-segment
               (format nil "read ~A"
                       (string-downcase
                        (symbol-name
                         (getf classification :kind))))
               :token :tool-title :bold-p t)
              (tool-header-segment " ")
              (tool-header-segment
               (getf classification :label)
               :token :accent)))
         (tool-read-range-segments arguments)
         (list
          (tool-header-segment
           " (ctrl+o to expand)" :token :dim)))
        (let ((summary-segments
                (tool-summary-segments call cwd)))
          (cond
            ((string-equal name "bash")
             (let ((command-segment (first summary-segments)))
               (cons
                (tool-header-segment
                 (format nil "$ ~A"
                         (or (getf command-segment :text) ""))
                 :token (getf command-segment :token)
                 :bold-p (getf command-segment :bold-p))
                (rest summary-segments))))
            ((string-equal name "powershell")
             (let ((command-segment (first summary-segments)))
               (cons
                (tool-header-segment
                 (format nil "PS> ~A"
                         (or (getf command-segment :text) ""))
                 :token (getf command-segment :token)
                 :bold-p (getf command-segment :bold-p))
                (rest summary-segments))))
            (t
             (append
              (list
               (tool-header-segment
                name :token :tool-title :bold-p t)
               (tool-header-segment " "))
              summary-segments)))))))

(defparameter +tool-source-language-map+
  '(("ts" . "typescript") ("tsx" . "typescript")
    ("js" . "javascript") ("jsx" . "javascript")
    ("mjs" . "javascript") ("cjs" . "javascript")
    ("py" . "python") ("rb" . "ruby") ("rs" . "rust")
    ("go" . "go") ("java" . "java") ("kt" . "kotlin")
    ("swift" . "swift") ("c" . "c") ("h" . "c")
    ("cpp" . "cpp") ("cc" . "cpp") ("cxx" . "cpp")
    ("hpp" . "cpp") ("cs" . "csharp") ("php" . "php")
    ("sh" . "bash") ("bash" . "bash") ("zsh" . "bash")
    ("fish" . "fish") ("ps1" . "powershell")
    ("sql" . "sql") ("html" . "html") ("htm" . "html")
    ("css" . "css") ("scss" . "scss") ("sass" . "sass")
    ("less" . "less") ("json" . "json") ("yaml" . "yaml")
    ("yml" . "yaml") ("toml" . "toml") ("xml" . "xml")
    ("md" . "markdown") ("markdown" . "markdown")
    ("dockerfile" . "dockerfile") ("makefile" . "makefile")
    ("cmake" . "cmake") ("lua" . "lua") ("perl" . "perl")
    ("r" . "r") ("scala" . "scala") ("clj" . "clojure")
    ("ex" . "elixir") ("exs" . "elixir") ("erl" . "erlang")
    ("hs" . "haskell") ("ml" . "ocaml") ("vim" . "vim")
    ("graphql" . "graphql") ("proto" . "protobuf")
    ("tf" . "hcl") ("hcl" . "hcl")))

(defun tool-source-language (call)
  (let ((path
          (cadr-ai::json-get
           (cadr-ai:tool-call-arguments call) "path")))
    (when (stringp path)
      (let* ((filename
               (string-downcase
                (file-namestring (pathname path))))
             (dot (position #\. filename :from-end t))
             (extension
               (if dot (subseq filename (1+ dot)) filename)))
        (cdr
         (assoc extension +tool-source-language-map+
                :test #'string=))))))

(defun tool-result-text (result)
  (format
   nil "~{~A~^~%~}"
   (loop for block in
         (cadr-ai:tool-result-message-content result)
         when (typep block 'cadr-ai:text-content)
           collect (cadr-ai:text-content-text block))))

(defun kebab-keyword-to-camel (key)
  (let ((name (string-downcase (symbol-name key))))
    (with-output-to-string (out)
      (loop with upcase-p = nil
            for char across name
            do
            (cond
              ((char= char #\-)
               (setf upcase-p t))
              (upcase-p
               (write-char (char-upcase char) out)
               (setf upcase-p nil))
              (t (write-char char out)))))))

(defun tool-result-detail (result key &optional json-key)
  (let ((details
          (cadr-ai:tool-result-message-details result))
        (json-key (or json-key (kebab-keyword-to-camel key))))
    (cond
      ((hash-table-p details)
       (cadr-ai::json-get details json-key))
      ((listp details)
       (getf details key))
      (t nil))))

(defun rendered-tool-result-text (call result)
  (let ((text (tool-result-text result)))
    (cond
      ((cadr-ai:tool-result-message-is-error result)
       text)
      ((string-equal
        (cadr-ai:tool-call-name call) "write")
       (let ((content
               (cadr-ai::json-get
                (cadr-ai:tool-call-arguments call)
                "content")))
         (if (stringp content) content text)))
      ((string-equal
        (cadr-ai:tool-call-name call) "edit")
       (let ((diff
               (tool-result-detail
                result :diff)))
         (if (and (stringp diff)
                  (plusp (length diff)))
             diff
             text)))
      ((string-equal
        (cadr-ai:tool-call-name call) "bash")
       (let* ((truncated-p
                (tool-result-detail
                 result :truncated))
              (full-output-path
                (tool-result-detail
                 result :full-output-path))
              (footer-start
                (and
                 truncated-p
                 (stringp full-output-path)
                 (plusp (length full-output-path))
                 (plusp (length text))
                 (char= #\] (char text (1- (length text))))
                 (search (format nil "~%~%[") text
                         :from-end t))))
         (if
             (and footer-start
                  (search full-output-path text
                          :start2 footer-start))
             (string-right-trim
              '(#\Space #\Tab #\Newline #\Return)
              (subseq text 0 footer-start))
             text)))
      (t text))))

(defun tool-call-preview-output (call cwd)
  (cond
    ((string-equal
      (cadr-ai:tool-call-name call) "write")
     (let ((content
             (cadr-ai::json-get
              (cadr-ai:tool-call-arguments call)
              "content")))
       (cond
         ((stringp content) (values content nil))
         ((null content) (values "" nil))
         (t
          (values
           "[invalid content arg - expected string]"
           :error)))))
    ((string-equal
      (cadr-ai:tool-call-name call) "edit")
     (preview-edit-call
      cwd (cadr-ai:tool-call-arguments call)))
    (t (values "" nil))))

(defun summarization-status-message (source reason)
  (let ((cancel-hint
          (format nil "(~A to cancel)"
                  (key-text "app.interrupt"))))
    (if (eq source :branch-summary)
        (format nil "Summarizing branch... ~A" cancel-hint)
        (case reason
          (:threshold
           (format nil "Auto-compacting... ~A" cancel-hint))
          (:overflow
           (format nil
                   "Context overflow detected, Auto-compacting... ~A"
                   cancel-hint))
          (otherwise
           (format nil "Compacting context... ~A" cancel-hint))))))

(defun search-truncation-presentation-warning
    (truncation &key limit-kind limit-count
                       lines-truncated-p)
  (let ((warnings nil))
    (when limit-count
      (push
       (format nil "~D ~A limit" limit-count limit-kind)
       warnings))
    (when (and truncation
               (getf truncation :truncated))
      (push
       (format nil "~A limit"
               (format-byte-size
                (or (getf truncation :max-bytes)
                    +maximum-output-bytes+)))
       warnings))
    (when lines-truncated-p
      (push "some lines truncated" warnings))
    (when warnings
      (format nil "[Truncated: ~{~A~^, ~}]"
              (nreverse warnings)))))

(defun tool-result-presentation-lines (call result)
  (let ((name (cadr-ai:tool-call-name call)))
    (labels
        ((detail (key)
           (tool-result-detail result key))
         (nested-truncation ()
           (detail :truncation)))
      (let ((warning
              (cond
                ((or (string-equal name "bash")
                     (string-equal name "powershell"))
                 (let ((full-output-path
                         (detail :full-output-path)))
                   (when (and (detail :truncated)
                              (stringp full-output-path)
                              (plusp (length full-output-path)))
                     (format
                      nil "[Full output: ~A. ~A]"
                      full-output-path
                      (if
                          (eq (detail :truncated-by)
                              :lines)
                          (format
                           nil "Truncated: showing ~D of ~D lines"
                           (detail :output-lines)
                           (detail :total-lines))
                          (format
                           nil "Truncated: ~D lines shown (~A limit)"
                           (detail :output-lines)
                           (format-byte-size
                            (or (detail :max-bytes)
                                +maximum-output-bytes+))))))))
                ((string-equal name "read")
                 (let ((truncation
                         (cadr-ai:tool-result-message-details result)))
                   (when (and truncation
                              (getf truncation :truncated))
                     (cond
                       ((getf truncation :first-line-exceeds-limit)
                        (format
                         nil "[First line exceeds ~A limit]"
                         (format-byte-size
                          (or (getf truncation :max-bytes)
                              +maximum-output-bytes+))))
                       ((eq (getf truncation :truncated-by) :lines)
                        (format
                         nil
                         "[Truncated: showing ~D of ~D lines (~D line limit)]"
                         (getf truncation :output-lines)
                         (getf truncation :total-lines)
                         (getf truncation :max-lines)))
                       (t
                        (format
                         nil "[Truncated: ~D lines shown (~A limit)]"
                         (getf truncation :output-lines)
                         (format-byte-size
                          (or (getf truncation :max-bytes)
                              +maximum-output-bytes+))))))))
                ((string-equal name "find")
                 (search-truncation-presentation-warning
                  (nested-truncation)
                  :limit-kind "results"
                  :limit-count
                  (detail :result-limit-reached)))
                ((string-equal name "grep")
                 (search-truncation-presentation-warning
                  (nested-truncation)
                  :limit-kind "matches"
                  :limit-count
                  (detail :match-limit-reached)
                  :lines-truncated-p
                  (detail :lines-truncated)))
                ((string-equal name "ls")
                 (search-truncation-presentation-warning
                  (nested-truncation)
                  :limit-kind "entries"
                  :limit-count
                  (detail :entry-limit-reached))))))
        (and warning (list warning))))))

(defun find-tool-entry (state call-id)
  (find
   call-id
   (tui-state-entries state)
   :from-end t
   :key #'tui-entry-tool-call-id
   :test #'string=))

(defun tui-handle-agent-event
    (state event
     &key
       extension-host
       display-messages
       compaction-summary
       compaction-tokens-before
       (clock-function #'tui-monotonic-seconds))
  (let ((type (cadr-agent:agent-event-type event))
        (message (cadr-agent:agent-event-message event))
        (stream-event
          (cadr-agent:agent-event-stream-event event)))
    (case type
      (:agent-start
       (setf
        (tui-state-agent-working-p state)
        t
        (tui-state-status-message state)
        nil
        (tui-state-settle-window-p state)
        nil))
      (:auto-retry-start
       (setf
        (tui-state-status-message state)
        (format
         nil "Retrying (~D/~D) in ~Ds..."
         (or
          (cadr-agent:agent-event-attempt event)
          1)
         (or
          (cadr-agent:agent-event-max-attempts
           event)
          1)
         (ceiling
          (or
           (cadr-agent:agent-event-delay-ms
            event)
           0)
          1000))
        (tui-state-settle-window-p state)
        nil))
      ((:agent-end :agent-settled)
       (setf
        (tui-state-agent-working-p state)
        nil
        (tui-state-status-message state)
        nil
        (tui-state-settle-window-p state)
        nil))
      (:queue-update
       (setf
        (tui-state-steering-messages state)
        (copy-list
         (cadr-agent:agent-event-steering event))
        (tui-state-follow-up-messages state)
        (copy-list
         (cadr-agent:agent-event-follow-up event))))
      (:message-start
       (when (or (typep message 'cadr-ai:user-message)
                 (typep message 'cadr-ai:assistant-message))
         (setf (tui-state-settle-window-p state) nil))
       (typecase message
         (cadr-ai:user-message
          (append-tui-user-message
           state
           (cadr-ai::content-text
            (cadr-ai:user-message-content message))))
         (cadr-ai:assistant-message
          (let ((entry
                  (append-tui-entry
                   state
                   (make-tui-entry
                    :type :assistant
                    :streaming-p t
                    :stop-reason
                    (cadr-ai:assistant-message-stop-reason
                     message)
                    :error-message
                    (cadr-ai:assistant-message-error-message
                     message)
                    :has-tool-calls-p
                    (assistant-message-has-tool-calls-p
                     message)
                    :content-blocks
                    (assistant-display-blocks
                     message)))))
            (setf
             (tui-state-current-assistant state)
             entry)))
         (cadr-agent:branch-summary-message
          (seed-tui-message state message))
         (cadr-agent:compaction-summary-agent-message
          (seed-tui-message state message))))
      (:message-update
       ;; Block-end opens the persist settle window (pi never paints
       ;; loader after the last delta of a finished block).  Any live
       ;; stream start/delta lifts it so Working... shows during
       ;; generation, including the assistant turn after a tool.
       (when stream-event
         (case (cadr-ai:stream-event-type stream-event)
           ((:text-end :thinking-end :tool-call-end)
            (setf (tui-state-settle-window-p state) t))
           ((:text-start :text-delta
             :thinking-start :thinking-delta
             :tool-call-start :tool-call-delta)
            (setf (tui-state-settle-window-p state) nil))))
       (when
           (and
            (tui-state-current-assistant state)
            stream-event)
         (let* ((entry
                  (tui-state-current-assistant state))
                (event-type
                  (cadr-ai:stream-event-type
                   stream-event))
                (message-type
                  (case event-type
                    (:text-delta :assistant)
                    (:thinking-delta
                     :assistant-thinking)))
                (delta
                  (or
                   (cadr-ai:stream-event-delta
                    stream-event)
                   "")))
           (when message-type
             (when (eq message-type :assistant)
               (setf
                (tui-entry-text entry)
                (concatenate
                 'string
                 (tui-entry-text entry)
                 delta)))
             (let ((last
                     (car
                      (last
                       (tui-entry-content-blocks
                        entry)))))
               (if
                   (and last
                        (eq (car last)
                            message-type))
                   (setf
                    (cdr last)
                    (concatenate
                     'string (cdr last) delta))
                   (setf
                    (tui-entry-content-blocks entry)
                    (nconc
                     (tui-entry-content-blocks entry)
                     (list
                      (cons message-type
                            delta))))))))))
      (:message-end
       (when (typep message 'cadr-ai:assistant-message)
         ;; Mark the settle window: the baseline finalizes the
         ;; streaming component at message_end and removes the working
         ;; indicator at agent_end
         ;; (interactive-mode.ts:3001-3042,3088-3102), one synchronous
         ;; event chain its timer-driven renderer can never observe.
         ;; Cadr renders from a wall-clock main loop over
         ;; millisecond-scale persistence work in this window, so a
         ;; flush here would paint "complete final text + loader", a
         ;; frame two rows taller than the settle frame; the terminal
         ;; viewport only ratchets downward, so the overscroll
         ;; survives as trailing blank rows the baseline never shows
         ;; (render-diff tools-significant-states drift).  The window
         ;; opens at the last stream block-end (text-end /
         ;; thinking-end / tool-call-end, handled at :message-update)
         ;; and at message-end, and closes at agent-end /
         ;; agent-settled / auto-retry-start / tool-execution-start /
         ;; user or assistant message-start / compaction-start or any
         ;; live stream start/delta.  While the flag is set, frames
         ;; omit the working indicator.
         (setf (tui-state-settle-window-p state) t)
         (let ((entry
                 (tui-state-current-assistant state)))
           (when entry
             (let ((blocks
                     (assistant-display-blocks
                      message)))
               (when blocks
                 (setf
                  (tui-entry-content-blocks entry)
                  blocks
                  (tui-entry-text entry)
                  (response-text message)))
               (setf
                (tui-entry-stop-reason entry)
                (cadr-ai:assistant-message-stop-reason
                 message)
                (tui-entry-error-message entry)
                (cadr-ai:assistant-message-error-message
                 message)
                (tui-entry-has-tool-calls-p entry)
                (assistant-message-has-tool-calls-p
                 message))
             (setf
              (tui-entry-streaming-p entry)
              nil))))
         (accumulate-message-usage state message)
         (setf
          (tui-state-current-assistant state)
          nil)))
      (:tool-execution-start
       (setf (tui-state-settle-window-p state) nil)
       (let ((call
               (cadr-agent:agent-event-tool-call event)))
         (let ((cwd
                 (if (plusp (length (tui-state-cwd state)))
                     (tui-state-cwd state)
                     (uiop:getcwd))))
           (multiple-value-bind (preview preview-status)
               (tool-call-preview-output call cwd)
             (let* ((render-state
                      (make-hash-table))
                    (entry
                      (make-tui-entry
                       :type :tool
                       :tool-call-id
                       (cadr-ai:tool-call-id call)
                       :tool-render-state render-state
                       :tool-block
                       (cadr-tui:make-tool-block
                        :name (cadr-ai:tool-call-name call)
                        :summary
                        (tool-arguments-summary call cwd)
                        :header-segments
                        (tool-header-segments call cwd)
                        :output preview
                        :output-token
                        (and (eq preview-status :error)
                             :error)
                        :preview-status preview-status
                        :source-language
                        (and
                         (member
                          (string-downcase
                           (cadr-ai:tool-call-name call))
                          '("read" "write") :test #'string=)
                         (tool-source-language call))
                        :syntax-highlight-function
                        #'tui-syntax-highlight
                        :expand-key-text
                        (key-text "app.tools.expand")
                        :started-at
                        (funcall clock-function)
                        :collapsed-p
                        (not
                         (tui-state-tools-expanded-p
                          state))
                        :status :running))))
               (when extension-host
                 (multiple-value-bind
                       (rendered handled-p)
                     (cadr-agent::render-extension-tool-call
                      extension-host
                      (cadr-ai:tool-call-name call)
                      (cadr-ai:tool-call-arguments call)
                      (list
                       :state render-state
                       :theme (tui-extension-theme-runtime)
                       :tool-call-id
                       (cadr-ai:tool-call-id call)
                       :cwd
                       (namestring
                        (cadr-agent::extension-host-cwd
                         extension-host))
                       :execution-started-p t
                       :args-complete-p t
                       :partial-p nil
                       :expanded-p
                       (tui-state-tools-expanded-p state)))
                   (setf
                    (tui-entry-custom-call-render
                     entry)
                    rendered
                    (tui-entry-custom-call-rendered-p
                     entry)
                    (not (null handled-p)))))
               (append-tui-entry state entry))))))
      (:tool-execution-end
       (let* ((call
                (cadr-agent:agent-event-tool-call event))
              (result
                (cadr-agent:agent-event-tool-result event))
              (entry
                (and call
                     (find-tool-entry
                      state
                      (cadr-ai:tool-call-id call)))))
         (when entry
           (invalidate-tui-entry-render-cache entry)
           (let* ((block (tui-entry-tool-block entry))
                  (settled-output
                    (rendered-tool-result-text call result))
                  (preview-output
                    (cadr-tui:tool-block-output block)))
             (setf
              (cadr-tui:tool-block-output block)
              (if (and
                   (string-equal
                    (cadr-ai:tool-call-name call) "edit")
                   (string= preview-output settled-output))
                  preview-output
                  settled-output)
              (cadr-tui::tool-block-supplemental-lines block)
              (tool-result-presentation-lines call result)
              (cadr-tui::tool-block-output-token block)
              nil))
           (setf
            (cadr-tui:tool-block-status
             (tui-entry-tool-block entry))
            (if
                (cadr-ai:tool-result-message-is-error
                 result)
                :error
                :complete)
            (cadr-tui:tool-block-ended-at
             (tui-entry-tool-block entry))
            (funcall clock-function)
            (cadr-tui:tool-block-collapsed-p
             (tui-entry-tool-block entry))
            (not
             (tui-state-tools-expanded-p state)))
           (when extension-host
             (multiple-value-bind
                   (rendered handled-p)
                 (cadr-agent::render-extension-tool-result
                  extension-host
                  (cadr-ai:tool-call-name call)
                  result
                  (list
                   :expanded-p
                   (tui-state-tools-expanded-p state)
                   :partial-p nil)
                  (list
                   :state
                   (tui-entry-tool-render-state entry)
                   :theme (tui-extension-theme-runtime)
                   :tool-call-id
                   (cadr-ai:tool-call-id call)
                   :cwd
                   (namestring
                    (cadr-agent::extension-host-cwd
                     extension-host))
                   :execution-started-p t
                   :args-complete-p t
                   :partial-p nil
                   :expanded-p
                   (tui-state-tools-expanded-p state)
                   :is-error-p
                   (cadr-ai:tool-result-message-is-error
                    result)))
               (setf
                (tui-entry-custom-result-render
                 entry)
                rendered
                (tui-entry-custom-result-rendered-p
                 entry)
                (not (null handled-p)))))
           (unless (loop for other in (tui-state-entries state) for block = (tui-entry-tool-block other)
                         thereis (and block (eq (cadr-tui:tool-block-status block) :running)))
             (setf (tui-state-settle-window-p state) t)))))
      (:compaction-start
       (setf
        (tui-state-status-message state)
        (summarization-status-message
         :compaction
         (cadr-agent:agent-event-reason event))
        (tui-state-settle-window-p state)
        nil))
      (:summarization-retry-scheduled
       (add-tui-error
        state
        (or (cadr-agent:agent-event-error-message event)
            "Unknown error"))
       (setf
        (tui-state-status-message state)
        (format nil "Retrying (~D/~D) in ~Ds..."
                (or (cadr-agent:agent-event-attempt event) 0)
                (or (cadr-agent:agent-event-max-attempts event) 0)
                (ceiling
                 (or (cadr-agent:agent-event-delay-ms event) 0)
                 1000))))
      (:summarization-retry-attempt-start
       (setf
        (tui-state-status-message state)
        (summarization-status-message
         (cadr-agent:agent-event-source event)
         (cadr-agent:agent-event-reason event))))
      (:summarization-retry-finished
       (when (and (tui-state-status-message state)
                  (search "Retrying ("
                          (tui-state-status-message state)))
         (setf (tui-state-status-message state) nil)))
      (:compaction-end
       (setf (tui-state-status-message state) nil)
       (if (cadr-agent:agent-event-error-message event)
           (add-tui-error
            state
            (cadr-agent:agent-event-error-message event))
           (progn
             (setf (tui-state-context-percent state) nil)
             (when display-messages
               (reset-tui-messages
                state display-messages
                :preserve-usage-p t
                :context-unknown-p t))
             (if compaction-summary
                 (append-tui-entry
                  state
                  (make-tui-entry
                   :type :compaction-summary
                   :text compaction-summary
                   :tokens-before
                   (or compaction-tokens-before 0)
                   :expanded-p
                   (tui-state-tools-expanded-p state)))
                 (unless
                     (find-if
                      (lambda (message)
                        (typep
                         message
                         'cadr-agent:compaction-summary-agent-message))
                      display-messages)
                   (add-tui-status state
                                   "Context compacted"))))))
      (:compaction-error
       (setf
        (tui-state-status-message state)
        nil)
       (add-tui-error
        state
        (cadr-agent:agent-event-error-message
         event)))))
  state)

(defun set-tui-tools-expanded
    (state expanded-p)
  (setf
   (tui-state-tools-expanded-p state)
   (not (null expanded-p)))
  (dolist (entry (tui-state-entries state))
    (case (tui-entry-type entry)
      (:tool
       (invalidate-tui-entry-render-cache entry)
       (setf
        (cadr-tui:tool-block-collapsed-p
         (tui-entry-tool-block entry))
        (not expanded-p)))
      ((:custom-message :custom-entry)
       (setf (getf (tui-entry-custom-options entry) :expanded-p)
             (not (null expanded-p)))
       (invalidate-tui-entry-render-cache entry))
      ((:bash-execution
        :skill-invocation :branch-summary :compaction-summary)
       (setf (tui-entry-expanded-p entry)
             (not (null expanded-p)))
       (invalidate-tui-entry-render-cache entry))))
  (tui-state-tools-expanded-p state))

(defun toggle-last-tool-block (state)
  (set-tui-tools-expanded
   state
   (not (tui-state-tools-expanded-p state))))
