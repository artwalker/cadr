(in-package #:cadr-cli)

(defparameter +osc-133-start+
  (format nil "~C]133;A~C" #\Escape (code-char 7)))
(defparameter +osc-133-end+
  (format nil "~C]133;B~C" #\Escape (code-char 7)))
(defparameter +osc-133-final+
  (format nil "~C]133;C~C" #\Escape (code-char 7)))

(defun output-padding-string (output-pad)
  (make-string
   (if (member output-pad '(0 1))
       output-pad 1)
   :initial-element #\Space))

(defun render-user-message-lines
    (text width &key (output-pad 1))
  (let* ((padding
           (output-padding-string output-pad))
         (lines
           (cadr-tui:wrap-text
            (concatenate 'string padding text)
            width)))
    (append
     (list
      (concatenate
       'string +osc-133-start+
       (format nil "~C[49m" #\Escape)))
     lines
     (list
      (concatenate
       'string +osc-133-end+
       +osc-133-final+
       (format nil "~C[49m" #\Escape))))))

(defun render-assistant-message-lines
    (blocks width
     &key (output-pad 1)
       thinking-visible-p stop-reason)
  (let ((contains-tool-p nil)
        (thinking-run-p nil)
        (lines nil)
        (padding
          (output-padding-string output-pad)))
    (dolist (block blocks)
      (case (getf block :type)
        (:tool-call
         (setf contains-tool-p t
               thinking-run-p nil))
        (:thinking
         (unless thinking-run-p
           (setf
            lines
            (nconc
             lines
             (cadr-tui:wrap-text
              (concatenate
               'string padding
               (if thinking-visible-p
                   (or (getf block :thinking)
                       "")
                   "Thinking..."))
              width))))
         (setf thinking-run-p t))
        (:text
         (setf thinking-run-p nil)
         (setf
          lines
          (nconc
           lines
           (cadr-tui:wrap-text
            (concatenate
             'string padding
             (or (getf block :text) ""))
            width))))))
    (when (eq stop-reason :length)
      (setf
       lines
       (nconc
        lines
        (cadr-tui:wrap-text
         "Error: maximum output token limit reached; response may be incomplete."
         width))))
    (if contains-tool-p
        lines
        (if lines
            (let ((copy (copy-list lines)))
              (setf
               (first copy)
               (concatenate
                'string +osc-133-start+
                (first copy))
               (car (last copy))
               (concatenate
                'string +osc-133-end+
                +osc-133-final+
                (car (last copy))))
              copy)
            nil))))

(defun assistant-price-known-p (message)
  (not
   (null
    (ignore-errors
      (cadr-ai:find-model-metadata
       (cadr-ai:assistant-message-provider message)
       (cadr-ai:assistant-message-model message))))))

(defun accumulate-message-usage (state message)
  (let* ((usage
           (cadr-ai:assistant-message-usage message))
         (cost (cadr-ai:usage-cost usage))
         (input (cadr-ai:usage-input usage))
         (cache-read
           (cadr-ai:usage-cache-read usage))
         (cache-write
           (cadr-ai:usage-cache-write usage))
         (prompt-total
           (+ input cache-read cache-write))
         (context-total
           (or
            (and
             (plusp (cadr-ai:usage-total usage))
             (cadr-ai:usage-total usage))
            (+ prompt-total
               (cadr-ai:usage-output usage)))))
    (incf (tui-state-input-tokens state)
          input)
    (incf (tui-state-output-tokens state)
          (cadr-ai:usage-output usage))
    (incf
     (tui-state-cache-read-tokens state)
     cache-read)
    (incf
     (tui-state-cache-write-tokens state)
     cache-write)
    (incf
     (tui-state-cache-tokens state)
     (+ cache-read cache-write))
    (setf
     (tui-state-latest-cache-hit-rate state)
     (and
      (plusp prompt-total)
      (* 100d0
         (/ cache-read prompt-total))))
    (unless
        (member
         (cadr-ai:assistant-message-stop-reason message)
         '(:aborted :error))
      (setf
       (tui-state-context-percent state)
       (and
        (plusp
         (tui-state-context-window state))
        (* 100d0
           (/ context-total
              (tui-state-context-window
               state))))))
    (when (assistant-price-known-p message)
      (setf (tui-state-cost-known-p state) t)
      (incf (tui-state-cost state)
            (cadr-ai:cost-total cost)))))

(defun assistant-message-has-tool-calls-p
    (message)
  (some
   (lambda (block)
     (typep block 'cadr-ai:tool-call))
   (cadr-ai:assistant-message-content message)))

(defun assistant-display-blocks (message)
  (let ((result nil))
    (dolist
        (block
         (cadr-ai:assistant-message-content
          message))
      (cond
        ((typep block 'cadr-ai:text-content)
         (let ((text
                 (string-trim
                  '(#\Space #\Tab #\Newline
                    #\Return)
                  (cadr-ai:text-content-text
                   block))))
           (when (plusp (length text))
             (setf result
                   (nconc
                    result
                    (list
                     (cons :assistant text)))))))
        ((typep block 'cadr-ai:thinking-content)
         (let ((thinking
                 (string-trim
                  '(#\Space #\Tab #\Newline
                    #\Return)
                  (cadr-ai:thinking-content-thinking
                   block))))
           (when (plusp (length thinking))
             (let ((last (car (last result))))
               (if
                   (and last
                        (eq :assistant-thinking
                            (car last)))
                   (setf
                    (cdr last)
                    (format nil "~A~%~%~A"
                            (cdr last) thinking))
                   (setf result
                         (nconc
                          result
                          (list
                           (cons
                            :assistant-thinking
                            thinking)))))))))))
    result))

(defun seed-tui-message (state message)
  (typecase message
    (cadr-ai:user-message
     (append-tui-user-message
      state
      (cadr-ai::content-text
       (cadr-ai:user-message-content message))))
    (cadr-ai:assistant-message
     (append-tui-entry
      state
      (make-tui-entry
       :type :assistant
       :text (response-text message)
       :content-blocks
       (assistant-display-blocks message)
       :stop-reason
       (cadr-ai:assistant-message-stop-reason
        message)
       :error-message
       (cadr-ai:assistant-message-error-message
        message)
       :has-tool-calls-p
       (assistant-message-has-tool-calls-p
        message)))
     (accumulate-message-usage state message))
    (cadr-agent:bash-execution-message
     (append-tui-entry
      state
      (make-tui-entry
       :type :bash-execution
       :label
       (cadr-agent:bash-execution-message-command message)
       :text
       (cadr-agent:bash-execution-message-output message)
       :expanded-p (tui-state-tools-expanded-p state)
       :custom-options
       (list
        :exit-code
        (cadr-agent:bash-execution-message-exit-code message)
        :cancelled-p
        (cadr-agent:bash-execution-message-cancelled-p message)
        :truncated-p
        (cadr-agent:bash-execution-message-truncated-p message)
        :full-output-path
        (cadr-agent:bash-execution-message-full-output-path message)
        :exclude-from-context-p
        (cadr-agent:bash-execution-message-exclude-from-context-p
         message)))))
    (cadr-agent:custom-agent-message
     (when (cadr-agent::custom-agent-message-display-p message)
       (append-tui-entry
        state
        (make-tui-entry
         :type :custom-message
         :custom-type
         (cadr-agent::custom-agent-message-custom-type message)
         :custom-payload
         (list
          :custom-type
          (cadr-agent::custom-agent-message-custom-type message)
          :content
          (cadr-agent::custom-agent-message-content message)
          :details
          (cadr-agent::custom-agent-message-details message)
          :display-p t)
         :custom-options
         '(:expanded-p nil :output-pad 1)))))
    (cadr-agent:branch-summary-message
     (append-tui-entry
      state
      (make-tui-entry
       :type :branch-summary
       :text
       (cadr-agent::branch-summary-message-summary message)
       :expanded-p (tui-state-tools-expanded-p state))))
    (cadr-agent:compaction-summary-agent-message
     (append-tui-entry
      state
      (make-tui-entry
       :type :compaction-summary
       :text
       (cadr-agent::compaction-summary-agent-message-summary message)
       :tokens-before
       (cadr-agent::compaction-summary-agent-message-tokens-before message)
       :expanded-p (tui-state-tools-expanded-p state)))))
  state)

(defun append-tui-user-message (state text)
  (multiple-value-bind
        (name location content user-message skill-p)
      (cadr-agent::parse-session-skill-block text)
    (declare (ignore location))
    (if skill-p
        (progn
          (append-tui-entry
           state
           (make-tui-entry
            :type :skill-invocation
            :label name
            :text content
            :expanded-p
            (tui-state-tools-expanded-p state)))
          (when user-message
            (let ((trimmed
                    (string-trim
                     '(#\Space #\Tab #\Newline #\Return)
                     user-message)))
              (when (plusp (length trimmed))
                (append-tui-entry
                 state
                 (make-tui-entry
                  :type :user :text trimmed))))))
        (append-tui-entry
         state
         (make-tui-entry :type :user :text text))))
  state)

(defun reset-tui-messages
    (state messages &key preserve-usage-p
                         context-unknown-p)
  (let ((saved-usage
          (and
           preserve-usage-p
           (list
            (tui-state-input-tokens state)
            (tui-state-output-tokens state)
            (tui-state-cache-tokens state)
            (tui-state-cache-read-tokens state)
            (tui-state-cache-write-tokens state)
            (tui-state-latest-cache-hit-rate state)
            (tui-state-cost state)
            (tui-state-cost-known-p state)))))
    (replace-tui-entries state nil)
    (setf
     (tui-state-current-assistant state) nil
     (tui-state-input-tokens state) 0
     (tui-state-output-tokens state) 0
     (tui-state-cache-tokens state) 0
     (tui-state-cache-read-tokens state) 0
     (tui-state-cache-write-tokens state) 0
     (tui-state-latest-cache-hit-rate state) nil
     (tui-state-context-percent state) nil
     (tui-state-cost state) 0d0
     (tui-state-cost-known-p state) nil)
    (dolist (message messages)
      (seed-tui-message state message))
    (when saved-usage
      (setf
       (tui-state-input-tokens state)
       (pop saved-usage)
       (tui-state-output-tokens state)
       (pop saved-usage)
       (tui-state-cache-tokens state)
       (pop saved-usage)
       (tui-state-cache-read-tokens state)
       (pop saved-usage)
       (tui-state-cache-write-tokens state)
       (pop saved-usage)
       (tui-state-latest-cache-hit-rate state)
       (pop saved-usage)
       (tui-state-cost state)
       (pop saved-usage)
       (tui-state-cost-known-p state)
       (pop saved-usage)))
    (when context-unknown-p
      (setf
       (tui-state-context-percent state)
       nil)))
  state)

(defun transform-tui-markdown
    (entry source message-type width extension-host
     &optional (cache-key message-type))
  (unless extension-host
    (return-from transform-tui-markdown source))
  (let* ((snapshot
           (cadr-agent::extension-host-current-snapshot
            extension-host))
         (context
           (list
            :message-type message-type
            :streaming-p
            (tui-entry-streaming-p entry)
            :available-width width)))
    (let ((cached
            (find-if
             (lambda (item)
               (and
                (equal cache-key (first item))
                (string= source (second item))
                (eq
                 (tui-entry-streaming-p entry)
                 (third item))
                (= width (fourth item))
                (eq snapshot (fifth item))))
             (tui-entry-markdown-cache entry))))
      (if cached
          (sixth cached)
          (let ((transformed
                  (cadr-agent::transform-extension-markdown
                   extension-host source context)))
            (setf
             (tui-entry-markdown-cache entry)
             (cons
              (list
               cache-key source
               (tui-entry-streaming-p entry)
               width snapshot transformed)
              (remove
               cache-key
               (tui-entry-markdown-cache entry)
               :key #'first
               :test #'equal)))
            transformed)))))

(defun assistant-stop-error-lines
    (entry width)
  (let ((message
          (case (tui-entry-stop-reason entry)
            (:length
             "Error: Model stopped because it reached the maximum output token limit. The response may be incomplete.")
            (:aborted
             (let ((error-message
                     (tui-entry-error-message
                      entry)))
               (if
                   (and error-message
                        (not
                         (string=
                          error-message
                          "Request was aborted")))
                   error-message
                   "Operation aborted")))
            (:error
             (unless
                 (tui-entry-has-tool-calls-p entry)
               (format
                nil "Error: ~A"
                (or
                 (tui-entry-error-message entry)
                 "Unknown error")))))))
    (when message
      (cons
       ""
       (component-text-lines
        (cadr-tui:theme-foreground
         :error message :enabled-p t)
        width :padding-x 1)))))

(defun tui-syntax-highlight (language source)
  (simple-syntax-highlight
   source language
   (list
    (cons
     "keyword"
     (lambda (text)
       (cadr-tui:theme-foreground
        :syntax-keyword text
        :enabled-p t)))
    (cons
     "number"
     (lambda (text)
       (cadr-tui:theme-foreground
        :syntax-number text
        :enabled-p t))))))

(defun render-assistant-blocks
    (entry width extension-host
     &key hide-thinking-block-p hidden-thinking-label)
  (let ((available-width
          (max 1 (- width 2))))
    (let ((blocks
            (or
             (tui-entry-content-blocks entry)
             (and
              (plusp
               (length
                (string-trim
                 '(#\Space #\Tab #\Newline
                   #\Return)
                 (tui-entry-text entry))))
              (list
               (cons
                :assistant
                (string-trim
                 '(#\Space #\Tab #\Newline
                   #\Return)
                 (tui-entry-text entry)))))))
          (rendered nil))
      (loop for (message-type . source)
              in blocks
            for block-index from 0
            for display-source =
              (if (and hide-thinking-block-p
                       (eq message-type :assistant-thinking))
                  (or hidden-thinking-label "Thinking...")
                  source)
            for transformed =
              (transform-tui-markdown
               entry display-source message-type
               available-width extension-host
               (list message-type block-index))
            for lines =
              (cadr-tui:render-markdown
               transformed width
               :padding-x 1
               :ansi-theme-p t
               :default-style-function
               (and
                (eq message-type
                    :assistant-thinking)
                (lambda (text)
                  (cadr-tui:theme-foreground
                   :thinking-text
                   (cadr-tui:theme-italic text)
                   :enabled-p t)))
               :syntax-highlight-function
               #'tui-syntax-highlight)
            do
            (when rendered
              (setf rendered
                    (nconc rendered
                           (list ""))))
            (setf rendered
                  (nconc rendered lines)))
      (let ((errors
              (assistant-stop-error-lines
               entry width)))
        (when rendered
          (setf rendered
                (cons "" rendered)))
        (nconc rendered errors)))))

(defun theme-message-background-lines
    (lines background-token)
  (loop for line in lines
        collect
        (cadr-tui:theme-background
         background-token line
         :enabled-p t)))

(defun transcript-summary-label (name)
  (cadr-tui:theme-foreground
   :custom-message-label
   (cadr-tui:theme-bold
    (format nil "[~A]" name)
    :enabled-p t)
   :enabled-p t))

(defun transcript-summary-text (text)
  (cadr-tui:theme-foreground
   :custom-message-text text :enabled-p t))

(defun render-transcript-summary-entry (entry width)
  (labels
      ((text-component (text)
         (cadr-tui:make-text-component
          text :padding-x 0 :padding-y 0))
       (markdown-component (text)
         (cadr-tui:make-markdown-component
          text
          :ansi-theme-p t
          :syntax-highlight-function #'tui-syntax-highlight
          :default-style-function #'transcript-summary-text)))
    (let* ((expanded-p (tui-entry-expanded-p entry))
           (type (tui-entry-type entry))
           (children
             (case type
               (:skill-invocation
                (if expanded-p
                    (list
                     (text-component
                      (transcript-summary-label "skill"))
                     (markdown-component
                      (format nil "**~A**~%~%~A"
                              (tui-entry-label entry)
                              (tui-entry-text entry))))
                    (list
                     (text-component
                      (concatenate
                       'string
                       (transcript-summary-label "skill")
                       " "
                       (transcript-summary-text
                        (tui-entry-label entry))
                       (cadr-tui:theme-foreground
                        :dim " (ctrl+o to expand)"
                        :enabled-p t))))))
               (:branch-summary
                (list
                 (text-component
                  (transcript-summary-label "branch"))
                 (cadr-tui:make-spacer-component :lines 1)
                 (if expanded-p
                     (markdown-component
                      (format nil "**Branch Summary**~%~%~A"
                              (tui-entry-text entry)))
                     (text-component
                      (concatenate
                       'string
                       (transcript-summary-text
                        "Branch summary (")
                       (cadr-tui:theme-foreground
                        :dim "ctrl+o" :enabled-p t)
                       (transcript-summary-text
                        " to expand)"))))))
               (:compaction-summary
                (let ((tokens
                        (format nil "~:D"
                                (or (tui-entry-tokens-before entry)
                                    0))))
                  (list
                   (text-component
                    (transcript-summary-label "compaction"))
                   (cadr-tui:make-spacer-component :lines 1)
                   (if expanded-p
                       (markdown-component
                        (format nil
                                "**Compacted from ~A tokens**~%~%~A"
                                tokens (tui-entry-text entry)))
                       (text-component
                        (concatenate
                         'string
                         (transcript-summary-text
                          (format nil
                                  "Compacted from ~A tokens ("
                                  tokens))
                         (cadr-tui:theme-foreground
                          :dim "ctrl+o" :enabled-p t)
                         (transcript-summary-text
                          " to expand)")))))))))
           (component
             (cadr-tui:make-box-component
              :padding-x 1 :padding-y 1
              :background-function
              (lambda (text)
                (cadr-tui:theme-background
                 :custom-message-bg text :enabled-p t))
              :children children)))
      (cadr-tui:component-render component width))))

(defun update-notification-border-line (width)
  (cadr-tui:theme-foreground
   :warning
   (make-string width :initial-element #\─)
   :enabled-p t))

(defun update-notification-text-lines (text width)
  (cadr-tui:component-render
   (cadr-tui:make-text-component
    text :padding-x 1 :padding-y 0)
   width))

(defun render-version-update-notification (entry width)
  (let* ((slug (cadr-ai::cadr-product-slug))
         (version (tui-entry-text entry))
         (action
           (cadr-tui:theme-foreground
            :accent
            (format nil "~A update" slug)
            :enabled-p t))
         (instruction
           (concatenate
            'string
            (cadr-tui:theme-foreground
             :muted
             (format nil "New version ~A is available. Run " version)
             :enabled-p t)
            action))
         (changelog-url (cadr-ai::cadr-changelog-url))
         (changelog
           (concatenate
            'string
            (cadr-tui:theme-foreground
             :muted "Changelog: " :enabled-p t)
            (let ((styled-url
                    (cadr-tui:theme-foreground
                     :accent changelog-url :enabled-p t)))
              (if
                  (cadr-tui:terminal-capabilities-hyperlinks-p
                   (cadr-tui:get-terminal-capabilities))
                  (cadr-tui:terminal-hyperlink
                   styled-url changelog-url)
                  styled-url))))
         (note (tui-entry-label entry)))
    (append
     (list "" (update-notification-border-line width))
     (update-notification-text-lines
      (format nil "~A~%~A"
              (cadr-tui:theme-bold
               (cadr-tui:theme-foreground
                :warning "Update Available" :enabled-p t)
               :enabled-p t)
              instruction)
      width)
     (when note
       (append
        (list "")
        (cadr-tui:render-markdown
         note width
         :padding-x 1
         :ansi-theme-p t
         :default-style-function
         (lambda (text)
           (cadr-tui:theme-foreground
            :muted text :enabled-p t))
         :syntax-highlight-function
         #'tui-syntax-highlight)
        (list "")))
     (update-notification-text-lines changelog width)
     (list (update-notification-border-line width)))))

(defun render-package-update-notification (entry width)
  (let* ((slug (cadr-ai::cadr-product-slug))
         (action
           (cadr-tui:theme-foreground
            :accent
            (format nil "~A update --extensions" slug)
            :enabled-p t))
         (instruction
           (concatenate
            'string
            (cadr-tui:theme-foreground
             :muted
             "Package updates are available. Run "
             :enabled-p t)
            action))
         (packages
           (getf (tui-entry-custom-options entry)
                 :packages))
         (package-lines
           (format nil "~{- ~A~^~%~}" packages)))
    (append
     (list "" (update-notification-border-line width))
     (update-notification-text-lines
      (format
       nil "~A~%~A~%~A~%~A"
       (cadr-tui:theme-bold
        (cadr-tui:theme-foreground
         :warning "Package Updates Available" :enabled-p t)
        :enabled-p t)
       instruction
       (cadr-tui:theme-foreground
        :muted "Packages:" :enabled-p t)
       package-lines)
      width)
     (list (update-notification-border-line width)))))

(defun render-tui-entry-uncached
    (entry width &key extension-host now
                      hide-thinking-block-p
                      hidden-thinking-label)
  (case (tui-entry-type entry)
    (:user
     (let ((lines
             (theme-message-background-lines
              (cadr-tui:render-markdown
               (transform-tui-markdown
                entry
                (tui-entry-text entry)
                :user
                (max 1 (- width 2))
                extension-host)
               width
               :padding-x 1
               :padding-y 1
               :ansi-theme-p t
               :default-style-function
               (lambda (text)
                 (cadr-tui:theme-foreground
                  :user-message-text text
                  :enabled-p t))
               :preserve-list-markers-p t
               :syntax-highlight-function
               #'tui-syntax-highlight)
              :user-message-bg)))
       (when lines
         (setf
          (first lines)
          (concatenate
           'string +osc-133-start+ (first lines))
          (car (last lines))
          (concatenate
           'string +osc-133-end+ +osc-133-final+
           (car (last lines)))))
       lines))
    (:assistant
     (let ((lines
             (render-assistant-blocks
              entry width extension-host
              :hide-thinking-block-p hide-thinking-block-p
              :hidden-thinking-label hidden-thinking-label)))
       (when
           (and
            lines
            (not
             (tui-entry-has-tool-calls-p entry)))
         (setf
          (first lines)
          (concatenate
           'string +osc-133-start+ (first lines))
          (car (last lines))
          (concatenate
           'string +osc-133-end+ +osc-133-final+
           (car (last lines)))))
       lines))
    (:tool
     (let ((custom-call
             (and
              (tui-entry-custom-call-rendered-p entry)
              (extension-render-value-lines
               (tui-entry-custom-call-render entry)
               width)))
           (custom-result
             (and
              (tui-entry-custom-result-rendered-p
               entry)
              (extension-render-value-lines
               (tui-entry-custom-result-render entry)
               width))))
       (if
           (or
            (tui-entry-custom-call-rendered-p entry)
            (tui-entry-custom-result-rendered-p entry))
           (nconc
            (or
             custom-call
             (cadr-tui:wrap-text
              (format nil "~A ~A"
                      (cadr-tui:tool-block-name
                       (tui-entry-tool-block entry))
                      (cadr-tui:tool-block-summary
                       (tui-entry-tool-block entry)))
              width))
            (if
                (tui-entry-custom-result-rendered-p
                 entry)
                custom-result
                (let ((output
                        (cadr-tui:tool-block-output
                         (tui-entry-tool-block entry))))
                  (and
                   (plusp (length output))
                   (cadr-tui:wrap-text
                    output width)))))
           (cadr-tui:render-tool-block
            (tui-entry-tool-block entry)
            width
           :ansi-theme-p t
            :now now))))
    (:bash-execution
     (render-user-bash-entry entry width :now now))
    ((:custom-message :custom-entry)
     (render-extension-custom-entry
      entry width extension-host))
    ((:skill-invocation :branch-summary :compaction-summary)
     (render-transcript-summary-entry entry width))
    (:notice
     (cons
      ""
      (component-text-lines
       (let ((text (tui-entry-text entry)))
         (if (find #\Escape text)
             text
             (cadr-tui:theme-foreground
              :dim text :enabled-p t)))
       width :padding-x 1)))
    (:status
     (cons
      ""
      (component-text-lines
       (cadr-tui:theme-foreground
        :dim (tui-entry-text entry) :enabled-p t)
       width :padding-x 1)))
    (:error
     (cons
      ""
      (component-text-lines
       (cadr-tui:theme-foreground
        :error
        (format nil "Error: ~A"
                (tui-entry-text entry))
        :enabled-p t)
       width :padding-x 1)))
    (:warning
     (cons
      ""
      (component-text-lines
       (cadr-tui:theme-foreground
        :warning
        (format nil "Warning: ~A"
                (tui-entry-text entry))
        :enabled-p t)
       width :padding-x 1)))
    (:project-trust-warning
     (cons
      ""
      (component-text-lines
       (cadr-tui:theme-foreground
        :warning (tui-entry-text entry) :enabled-p t)
       width :padding-x 1)))
    (:success
     (append
      (list "" (make-string width :initial-element #\Space))
      (component-text-lines
       (cadr-tui:theme-foreground
        :accent
        (format nil "✓ ~A"
                (tui-entry-text entry))
        :enabled-p t)
       width :padding-x 1)
      (list (make-string width :initial-element #\Space))))
    (:debug-written
     ;; Baseline /debug block: Spacer(1), then accent "✓ Debug log
     ;; written" and the muted path, both with one-cell padding.
     (append
      (list "" (make-string width :initial-element #\Space))
      (component-text-lines
       (cadr-tui:theme-foreground
        :accent "✓ Debug log written" :enabled-p t)
       width :padding-x 1)
      (component-text-lines
       (cadr-tui:theme-foreground
        :muted (tui-entry-text entry) :enabled-p t)
       width :padding-x 1)
      (list (make-string width :initial-element #\Space))))
    (:command-markdown
     (append
      (list
       ""
       (selector-border-line width)
       (selector-component-text-line
        (cadr-tui:theme-foreground
         :accent
         (cadr-tui:theme-bold
          (or (tui-entry-label entry) ""))
         :enabled-p t)
        width)
       "")
      (cadr-tui:render-markdown
       (tui-entry-text entry)
       width
       :padding-x 1
       :padding-y 1
       :ansi-theme-p t
       :syntax-highlight-function
       #'tui-syntax-highlight)
      (list (selector-border-line width))))
    (:version-update
     (render-version-update-notification entry width))
    (:package-update
     (render-package-update-notification entry width))
    (:auth-url
     (render-auth-url-lines
      (tui-entry-text entry)
      width))
    (otherwise nil)))

(defun tui-entry-render-cacheable-p (entry)
  (and
   (not (tui-entry-streaming-p entry))
   (or
    (not (eq (tui-entry-type entry) :tool))
    (let ((block (tui-entry-tool-block entry)))
      (and
       block
       (not
        (eq (cadr-tui:tool-block-status block)
            :running))
       (not (tui-entry-custom-call-rendered-p entry))
       (not
        (tui-entry-custom-result-rendered-p entry)))))))

(defun render-tui-entry
    (entry width &key extension-host now
                      hide-thinking-block-p
                      hidden-thinking-label)
  (let* ((cacheable-p
           (tui-entry-render-cacheable-p entry))
         (theme
           (and cacheable-p
                (cadr-tui:current-theme)))
         (snapshot
           (and
            cacheable-p
            extension-host
            (cadr-agent::extension-host-current-snapshot
             extension-host))))
    (if
        (and
         cacheable-p
         (tui-entry-render-cache-valid-p entry)
         (= width
            (tui-entry-render-cache-width entry))
         (eq theme
             (tui-entry-render-cache-theme entry))
         (eq
          snapshot
          (tui-entry-render-cache-extension-snapshot
           entry)))
        (tui-entry-render-cache-lines entry)
        (let ((lines
                (render-tui-entry-uncached
                 entry width
                 :extension-host extension-host
                 :now now
                 :hide-thinking-block-p hide-thinking-block-p
                 :hidden-thinking-label hidden-thinking-label)))
          (when cacheable-p
            (setf
             (tui-entry-render-cache-valid-p entry) t
             (tui-entry-render-cache-width entry) width
             (tui-entry-render-cache-theme entry) theme
             (tui-entry-render-cache-extension-snapshot
              entry)
             snapshot
             (tui-entry-render-cache-lines entry) lines))
          lines))))

(defun render-tui-entries
    (entries width &key extension-host now
                        hide-thinking-block-p
                        hidden-thinking-label)
  (loop
    for entry in entries
    for index from 0
    for rendered =
      (render-tui-entry
       entry width
       :extension-host extension-host
       :now now
       :hide-thinking-block-p hide-thinking-block-p
       :hidden-thinking-label hidden-thinking-label)
    append
      (if
          (and
           (plusp index)
           (member
            (tui-entry-type entry)
            '(:user :branch-summary :compaction-summary)
            :test #'eq))
          (cons "" rendered)
          rendered)))
