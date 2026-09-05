(in-package #:cadr-tui/tests)
(in-suite cadr-tui-suite)

(defun editor-event (editor kind &optional text)
  (cadr-tui:editor-handle-event
   editor
   (cadr-tui:make-input-event :kind kind :text text)))

(defun editor-type (editor text)
  (loop for cluster in (cadr-tui:grapheme-clusters text)
        do (editor-event editor :text cluster))
  editor)

(defun editor-cursor-values (editor)
  (multiple-value-list (cadr-tui:editor-cursor editor)))

(defun editor-render-plain-lines (lines)
  (mapcar #'cadr-tui:strip-terminal-sequences lines))

(test editor-history-state-and-normalization-match-reference
  (let ((editor (cadr-tui:make-multiline-editor)))
    (cadr-tui:editor-add-history editor "first")
    (cadr-tui:editor-add-history editor "second")
    (cadr-tui:editor-add-history editor "second")
    (editor-event editor :up)
    (is (string= "second" (cadr-tui:editor-text editor)))
    (is (equal '(0 0) (editor-cursor-values editor)))
    (editor-event editor :up)
    (is (string= "first" (cadr-tui:editor-text editor)))
    (editor-event editor :down)
    (is (string= "second" (cadr-tui:editor-text editor)))
    (is (equal '(0 6) (editor-cursor-values editor)))
    (editor-event editor :down)
    (is (string= "" (cadr-tui:editor-text editor)))
    (cadr-tui:editor-set-text
     editor
     (format nil "A~CB~CC~CD" #\Return #\Newline #\Tab))
    (is (string= (format nil "A~%B~%C    D")
                 (cadr-tui:editor-text editor)))
    (let ((lines (cadr-tui:editor-lines editor)))
      (is (vectorp lines))
      (setf (aref lines 0) "mutated")
      (is (string= "A"
                   (aref (cadr-tui:editor-lines editor) 0))))))

(test editor-backslash-enter-and-programmatic-insert
  (let ((editor (cadr-tui:make-multiline-editor)))
    (editor-type editor "\\")
    (multiple-value-bind (action value)
        (editor-event editor :enter)
      (is (null action))
      (is (null value)))
    (is (string= (string #\Newline)
                 (cadr-tui:editor-text editor)))
    (cadr-tui:editor-insert-text-at-cursor
     editor
     (format nil "a~Cb~Cc~Cd" #\Return #\Newline #\Tab))
    (is (string= (format nil "~%a~%b~%c    d")
                 (cadr-tui:editor-text editor)))
    (editor-event editor :undo)
    (is (string= (string #\Newline)
                 (cadr-tui:editor-text editor)))))

(test editor-kill-ring-yank-pop-and-undo
  (let ((editor
          (cadr-tui:make-multiline-editor
           :text "one two three")))
    (editor-event editor :delete-word-backward)
    (editor-event editor :delete-word-backward)
    (editor-event editor :delete-word-backward)
    (is (string= "" (cadr-tui:editor-text editor)))
    (editor-event editor :yank)
    (is (string= "one two three"
                 (cadr-tui:editor-text editor)))
    (editor-event editor :undo)
    (is (string= "" (cadr-tui:editor-text editor)))
    (cadr-tui:editor-set-text editor "alpha")
    (editor-event editor :delete-word-backward)
    (cadr-tui:editor-set-text editor "")
    (editor-event editor :yank)
    (is (string= "alpha" (cadr-tui:editor-text editor)))
    (editor-event editor :yank-pop)
    (is (string= "one two three"
                 (cadr-tui:editor-text editor)))))

(test editor-word-navigation-cjk-punctuation-and-multiline-kills
  (let ((editor
          (cadr-tui:make-multiline-editor
           :text (format nil "foo.bar~%你好，世界"))))
    (editor-event editor :word-left)
    (is (equal '(1 3) (editor-cursor-values editor)))
    (editor-event editor :delete-word-backward)
    (is (string= (format nil "foo.bar~%你好世界")
                 (cadr-tui:editor-text editor)))
    (editor-event editor :line-start)
    (editor-event editor :delete-word-backward)
    (is (string= "foo.bar你好世界"
                 (cadr-tui:editor-text editor)))
    (editor-event editor :line-start)
    (editor-event editor :delete-word-forward)
    (is (string= ".bar你好世界"
                 (cadr-tui:editor-text editor)))))

(test editor-paste-is-atomic-and-large-pastes-expand-literally
  (let ((editor
          (cadr-tui:make-multiline-editor :text "before after")))
    (loop repeat 5 do (editor-event editor :left))
    (editor-event editor :paste
                  (format nil "one~C~Ctwo~Cthree"
                          #\Return #\Newline #\Tab))
    (is (string= (format nil "before one~%two    threeafter")
                 (cadr-tui:editor-text editor)))
    (editor-event editor :undo)
    (is (string= "before after"
                 (cadr-tui:editor-text editor))))
  (let* ((editor (cadr-tui:make-multiline-editor))
         (payload (make-string 1001 :initial-element #\x)))
    (editor-event editor :paste payload)
    (is (search "[paste #1 1001 chars]"
                (cadr-tui:editor-text editor)))
    (is (string= payload
                 (cadr-tui:editor-expanded-text editor)))
    (editor-event editor :left)
    (editor-event editor :delete)
    (is (string= "" (cadr-tui:editor-text editor)))
    (editor-event editor :undo)
    (is (string= payload
                 (cadr-tui:editor-expanded-text editor)))))

(test editor-renumbers-multiple-paste-markers-and-undo-restores-registry
  (let* ((editor (cadr-tui:make-multiline-editor))
         (first (make-string 1001 :initial-element #\a))
         (second (make-string 1001 :initial-element #\b)))
    (editor-event editor :paste first)
    (editor-event editor :text " ")
    (editor-event editor :paste second)
    (is (search "[paste #1 1001 chars]"
                (cadr-tui:editor-text editor)))
    (is (search "[paste #2 1001 chars]"
                (cadr-tui:editor-text editor)))
    (editor-event editor :line-start)
    (editor-event editor :delete)
    (is (not (search "[paste #2"
                     (cadr-tui:editor-text editor))))
    (is (search "[paste #1 1001 chars]"
                (cadr-tui:editor-text editor)))
    (is (string=
         (concatenate 'string " " second)
         (cadr-tui:editor-expanded-text editor)))
    (editor-event editor :undo)
    (is (string=
         (concatenate 'string first " " second)
         (cadr-tui:editor-expanded-text editor)))))

(test editor-character-jump-and-sticky-column
  (let ((editor
          (cadr-tui:make-multiline-editor
           :text (format nil "abcdef~%x~%abcdef"))))
    (editor-event editor :up)
    (is (equal '(1 1) (editor-cursor-values editor)))
    (editor-event editor :up)
    (is (equal '(0 6) (editor-cursor-values editor)))
    (editor-event editor :down)
    (editor-event editor :left)
    (editor-event editor :up)
    (is (equal '(0 0) (editor-cursor-values editor)))
    (editor-event editor :jump-forward)
    (editor-event editor :text "f")
    (is (equal '(0 5) (editor-cursor-values editor)))
    (editor-event editor :jump-forward)
    (editor-event editor :text "f")
    (is (equal '(2 5) (editor-cursor-values editor)))
    (editor-event editor :jump-backward)
    (editor-event editor :text "x")
    (is (equal '(1 0) (editor-cursor-values editor)))))

(test editor-sticky-column-navigates-wrapped-visual-lines
  (let ((editor
          (cadr-tui:make-multiline-editor
           :text "abcdefghijk" :prompt "")))
    (cadr-tui:render-editor editor 5)
    (editor-event editor :up)
    (is (equal '(0 7) (editor-cursor-values editor)))
    (editor-event editor :up)
    (is (equal '(0 3) (editor-cursor-values editor)))
    (editor-event editor :down)
    (is (equal '(0 7) (editor-cursor-values editor)))))

(test editor-autocomplete-popup-selection-and-undo
  (let* ((provider
           (cadr-tui:make-autocomplete-provider
            :commands
            (list
             (cadr-tui:make-autocomplete-command
              :name "help" :description "show help")
             (cadr-tui:make-autocomplete-command
              :name "history" :description "show history"))))
         (editor (cadr-tui:make-multiline-editor)))
    (cadr-tui:editor-set-autocomplete-provider editor provider)
    (editor-event editor :text "/")
    (is (cadr-tui:editor-autocomplete-visible-p editor))
    (is (= 2 (length
              (cadr-tui:editor-autocomplete-items editor))))
    (multiple-value-bind (lines row column)
        (cadr-tui:render-editor editor 20)
      (declare (ignore row column))
      (is (some
           (lambda (line)
             (search "history" line))
           lines)))
    (editor-event editor :down)
    (editor-event editor :tab)
    (is (string= "/history "
                 (cadr-tui:editor-text editor)))
    (is (not (cadr-tui:editor-autocomplete-visible-p editor)))
    (editor-event editor :undo)
    (is (string= "/" (cadr-tui:editor-text editor)))
    (multiple-value-bind (lines row column)
        (cadr-tui:render-editor editor 20)
      (declare (ignore row column))
      (is (every (lambda (line)
                   (<= (cadr-tui:visible-width line) 20))
                 lines)))))

(test editor-delete-does-not-invent-file-autocomplete-at-plain-trailing-space
  (with-autocomplete-tree
   (lambda (root)
     (let ((provider
             (cadr-tui:make-autocomplete-provider
              :base-path root
              :commands
              (list
               (cadr-tui:make-autocomplete-command
                :name "help")))))
       (dolist (kind '(:backspace :delete))
         (let ((editor
                 (cadr-tui:make-multiline-editor
                  :text "plain x")))
           (cadr-tui:editor-set-autocomplete-provider
            editor provider)
           (when (eq kind :delete)
             (setf
              (cadr-tui::multiline-editor-cursor editor)
              (length "plain ")))
           (editor-event editor kind)
           (is (string= "plain "
                        (cadr-tui:editor-text editor)))
           (is (not
                (cadr-tui:editor-autocomplete-visible-p
                 editor)))))
       (dolist (text '("/he"))
         (let ((editor
                 (cadr-tui:make-multiline-editor)))
           (cadr-tui:editor-set-autocomplete-provider
            editor provider)
           (editor-type editor text)
           (is
            (cadr-tui:editor-autocomplete-visible-p
             editor))
           (editor-event editor :backspace)
           (is
            (cadr-tui:editor-autocomplete-visible-p
             editor))))
       (let ((editor
               (cadr-tui:make-multiline-editor)))
         (cadr-tui:editor-set-autocomplete-provider
          editor provider)
         (editor-type editor "./")
         (is (not
              (cadr-tui:editor-autocomplete-visible-p
               editor)))
         (editor-event editor :tab)
         (is
          (cadr-tui:editor-autocomplete-visible-p
           editor))
         (editor-event editor :text "R")
         (is
          (cadr-tui:editor-autocomplete-visible-p
           editor))
         (editor-event editor :backspace)
         (is
          (cadr-tui:editor-autocomplete-visible-p
           editor)))))))

(test editor-text-autocomplete-matches-baseline-trigger-gate
  (with-autocomplete-tree
   (lambda (root)
     (let* ((calls nil)
            (provider
              (cadr-tui:make-autocomplete-provider
               :base-path root
               :commands
               (list
                (cadr-tui:make-autocomplete-command
                 :name "help"))))
            (editor (cadr-tui:make-multiline-editor))
            (original
              (symbol-function
               'cadr-tui:autocomplete-get-suggestions)))
       (unwind-protect
            (progn
              (setf
               (symbol-function
                'cadr-tui:autocomplete-get-suggestions)
               (lambda (actual-provider lines line column
                        &key force-p)
                 (push (list (copy-seq lines)
                             line column force-p)
                       calls)
                 (funcall original actual-provider lines
                          line column :force-p force-p)))
              (cadr-tui:editor-set-autocomplete-provider
               editor provider)

              ;; Baseline never asks the provider for an empty natural
              ;; prefix, a space, or repeated spaces.
              (editor-event editor :text "")
              (editor-event editor :text " ")
              (editor-event editor :text " ")
              (is (null calls))
              (is (not
                   (cadr-tui:editor-autocomplete-visible-p
                    editor)))

              ;; Slash commands trigger only at the start of the message.
              (cadr-tui:editor-set-text editor "")
              (editor-event editor :text "/")
              (is (= 1 (length calls)))
              (is (not (fourth (first calls))))
              (is
               (cadr-tui:editor-autocomplete-visible-p
                editor))
              (editor-event editor :text " ")
              (is (= 2 (length calls)))
              (is (not
                   (cadr-tui:editor-autocomplete-visible-p
                    editor)))

              ;; Plain path fragments require explicit Tab completion.
              (setf calls nil)
              (cadr-tui:editor-set-text editor "")
              (editor-type editor "./")
              (is (null calls))
              (is (not
                   (cadr-tui:editor-autocomplete-visible-p
                    editor)))
              (editor-event editor :tab)
              (is (= 1 (length calls)))
              (is (fourth (first calls)))
              (is
               (cadr-tui:editor-autocomplete-visible-p
                editor))

              ;; A force-mode picker keeps force semantics while text is
              ;; edited, including a space.
              (editor-event editor :text " ")
              (is (= 2 (length calls)))
              (is (fourth (first calls)))
              (is
               (cadr-tui:editor-autocomplete-visible-p
                editor)))
         (setf
          (symbol-function
           'cadr-tui:autocomplete-get-suggestions)
          original))))))

(test editor-delete-to-empty-and-symbol-triggers-match-baseline
  (with-autocomplete-tree
   (lambda (root)
     (let* ((now 0)
            (calls nil)
            (provider
              (cadr-tui:make-autocomplete-provider
               :base-path root
               :commands
               (list
                (cadr-tui:make-autocomplete-command
                 :name "help"))))
            (editor (cadr-tui:make-multiline-editor))
            (original
              (symbol-function
               'cadr-tui:autocomplete-get-suggestions)))
       (unwind-protect
            (progn
              (setf
               (symbol-function
                'cadr-tui:autocomplete-get-suggestions)
               (lambda (actual-provider lines line column
                        &key force-p)
                 (push (list (copy-seq lines)
                             line column force-p)
                       calls)
                 (funcall original actual-provider lines
                          line column :force-p force-p)))
              (cadr-tui:editor-set-autocomplete-clock
               editor (lambda () now))
              (cadr-tui:editor-set-autocomplete-provider
               editor provider)

              ;; @ at a token boundary is natural; embedded @ is not.
              (editor-event editor :text "@")
              (incf now 1/50)
              (is (cadr-tui:editor-poll-autocomplete editor))
              (is (= 1 (length calls)))
              (setf calls nil)
              (cadr-tui:editor-set-text editor "x")
              (editor-event editor :text "@")
              (incf now 1/50)
              (is (not
                   (cadr-tui:editor-poll-autocomplete editor)))
              (is (null calls))

              ;; Deleting a visible slash picker back to empty re-queries
              ;; once and closes it; later empty deletes stay quiet.
              (cadr-tui:editor-set-text editor "")
              (editor-event editor :text "/")
              (is
               (cadr-tui:editor-autocomplete-visible-p
                editor))
              (setf calls nil)
              (editor-event editor :backspace)
              (is (= 1 (length calls)))
              (is (not
                   (cadr-tui:editor-autocomplete-visible-p
                    editor)))
              (setf calls nil)
              (editor-event editor :backspace)
              (editor-event editor :delete)
              (is (null calls)))
         (setf
          (symbol-function
           'cadr-tui:autocomplete-get-suggestions)
          original))))))

(test editor-autocomplete-honors-configured-visible-row-limit
  (let* ((provider
           (cadr-tui:make-autocomplete-provider
            :commands
            (loop for index below 25
                  collect
                  (cadr-tui:make-autocomplete-command
                   :name
                   (format nil "command-~D" index)))))
         (editor
           (cadr-tui:make-multiline-editor
            :autocomplete-max-visible 1)))
    (cadr-tui:editor-set-autocomplete-provider
     editor provider)
    (editor-event editor :text "/")
    (let ((lines
            (cadr-tui::render-editor-autocomplete
             editor 40)))
      (is (= 4 (length lines)))
      (is (some
           (lambda (line)
             (search "(1/25)" line))
           lines)))
    (let ((editor
            (cadr-tui:make-multiline-editor
             :autocomplete-max-visible 99)))
      (cadr-tui:editor-set-autocomplete-provider
       editor provider)
      (editor-event editor :text "/")
      (is (= 21
             (length
              (cadr-tui::render-editor-autocomplete
               editor 40)))))))

(test editor-border-colors-use-semantic-mode-tokens
  (let ((editor
          (cadr-tui:make-multiline-editor
           :text "hello" :prompt "")))
    (flet ((top-border ()
             (first
              (multiple-value-list
               (cadr-tui:render-editor editor 12)))))
      (is (search
           (cadr-tui:theme-foreground-ansi :border-muted)
           (first (top-border))))
      (cadr-tui:editor-set-border-mode editor :thinking :high)
      (is (search
           (cadr-tui:theme-foreground-ansi :thinking-high)
           (first (top-border))))
      (cadr-tui:editor-set-border-mode editor :bash)
      (is (search
           (cadr-tui:theme-foreground-ansi :bash-mode)
           (first (top-border))))
      (cadr-tui:editor-set-border-mode editor :idle)
      (is (search
           (cadr-tui:theme-foreground-ansi :border-muted)
           (first (top-border)))))))

(test editor-embeds-working-status-in-default-border
  (let ((editor
          (cadr-tui:make-multiline-editor
           :text "hello" :prompt "")))
    (cadr-tui:editor-set-border-mode editor :thinking :high)
    (flet ((top-border (&rest args)
             (first
              (first
               (multiple-value-list
                (apply #'cadr-tui:render-editor
                       editor 20 args))))))
      (let ((border
              (top-border
               :working-message "Working..."
               :working-spinner-frame "⠋")))
        (is (search "Working..." border))
        (is (search "⠋" border))
        (is (search
             (cadr-tui:theme-foreground-ansi :thinking-high)
             border))
        (is (= 20 (cadr-tui:visible-width border))))
      (let ((border (top-border)))
        (is (not (search "Working..." border)))
        (is (= 20 (cadr-tui:visible-width border))))
      (cadr-tui:editor-set-embed-working-status editor nil)
      (let ((border
              (top-border
               :working-message "Working..."
               :working-spinner-frame "⠋")))
        (is (not (search "Working..." border)))))))

(test editor-autocomplete-debounce-is-pollable-and-latest-request-wins
  (with-autocomplete-tree
   (lambda (root)
     (let* ((now 0)
            (calls nil)
            (provider
              (cadr-tui:make-autocomplete-provider
               :base-path root
               :commands
               (list
                (cadr-tui:make-autocomplete-command
                 :name "help"))))
            (editor (cadr-tui:make-multiline-editor))
            (original
              (symbol-function
               'cadr-tui:autocomplete-get-suggestions)))
       (unwind-protect
            (progn
              (setf
               (symbol-function
                'cadr-tui:autocomplete-get-suggestions)
               (lambda (actual-provider lines line column
                        &key force-p)
                 (push (list (copy-seq lines)
                             line column force-p)
                       calls)
                 (funcall original actual-provider lines
                          line column :force-p force-p)))
              (cadr-tui:editor-set-autocomplete-clock
               editor (lambda () now))
              (cadr-tui:editor-set-autocomplete-provider
               editor provider)

              ;; Slash-command menus are cheap and remain synchronous.
              (editor-event editor :text "/")
              (is (= 1 (length calls)))
              (is (cadr-tui:editor-autocomplete-visible-p editor))

              ;; Attachment completion waits 20 ms, and each edit supersedes
              ;; the older request before the provider is invoked.
              (setf calls nil)
              (cadr-tui:editor-set-text editor "")
              (editor-event editor :text "@")
              (is (null calls))
              (incf now 5/1000)
              (editor-event editor :text "a")
              (is (null calls))
              (incf now 5/1000)
              (editor-event editor :text "b")
              (is (null calls))
              (incf now 19/1000)
              (is (not
                   (cadr-tui:editor-poll-autocomplete editor)))
              (incf now 1/1000)
              (is (cadr-tui:editor-poll-autocomplete editor))
              (is (= 1 (length calls)))
              (is (equalp #("@ab")
                         (first (first calls))))
              (is (not
                   (cadr-tui:editor-poll-autocomplete editor)))
              (is (= 1 (length calls)))

              ;; Ordinary path fragments stay closed until explicit Tab;
              ;; force completion itself remains synchronous.
              (setf calls nil)
              (cadr-tui:editor-set-text editor "")
              (editor-event editor :text ".")
              (is (null calls))
              (editor-event editor :text "/")
              (is (null calls))
              (editor-event editor :tab)
              (is (= 1 (length calls)))
              (is (equalp #("./")
                         (first (first calls))))
              (is (fourth (first calls)))
              (is (not
                   (cadr-tui:editor-poll-autocomplete editor)))
              (is (= 1 (length calls)))

              ;; Explicit Tab/force bypasses the debounce window.
              (setf calls nil)
              (cadr-tui:editor-set-text editor "REA")
              (editor-event editor :tab)
              (is (= 1 (length calls)))
              (is (fourth (first calls))))
         (setf
          (symbol-function
           'cadr-tui:autocomplete-get-suggestions)
          original))))))

(test editor-custom-autocomplete-cancels-stale-requests-and-keeps-latest-result
  (let* ((first-entered
           (sb-thread:make-semaphore :count 0))
         (release-first
           (sb-thread:make-semaphore :count 0))
         (second-entered
           (sb-thread:make-semaphore :count 0))
         (now 0)
         (first-signal nil)
         (provider
           (cadr-tui:make-autocomplete-provider
            :trigger-characters '(#\#)
            :suggestions-function
            (lambda (lines row column options)
              (declare (ignore row column))
              (let ((text (cadr-tui:editor-line-at lines 0)))
                (if (string= text "#a")
                    (progn
                      (setf first-signal (getf options :signal))
                      (sb-thread:signal-semaphore first-entered)
                      (sb-thread:wait-on-semaphore release-first)
                      (cadr-tui:make-autocomplete-suggestions
                       :items
                       (list
                        (cadr-tui:make-autocomplete-item
                         :value "stale" :label "stale"))
                       :prefix "#a"))
                    (progn
                      (sb-thread:signal-semaphore second-entered)
                      (cadr-tui:make-autocomplete-suggestions
                       :items
                       (list
                        (cadr-tui:make-autocomplete-item
                         :value "latest" :label "latest"))
                       :prefix "#ab")))))))
         (editor (cadr-tui:make-multiline-editor)))
    (cadr-tui:editor-set-autocomplete-provider editor provider)
    (cadr-tui:editor-set-autocomplete-clock editor (lambda () now))
    (editor-type editor "#a")
    (incf now 1/50)
    (is (cadr-tui:editor-poll-autocomplete editor))
    (is (sb-thread:wait-on-semaphore first-entered :timeout 1))
    (editor-event editor :text "b")
    (is (cadr-tui:autocomplete-request-aborted-p first-signal))
    (incf now 1/50)
    (is (cadr-tui:editor-poll-autocomplete editor))
    (sb-thread:signal-semaphore release-first)
    (is (sb-thread:wait-on-semaphore second-entered :timeout 1))
    (let ((request
            (cadr-tui::multiline-editor-autocomplete-request
             editor)))
      (sb-thread:join-thread
       (cadr-tui::editor-autocomplete-request-thread request)))
    (is (cadr-tui:editor-poll-autocomplete editor))
    (is (equal '("latest")
               (mapcar
                #'cadr-tui:autocomplete-item-value
                (cadr-tui:editor-autocomplete-items editor))))
    (is (not
         (cadr-tui:editor-poll-autocomplete editor)))
    (is (equal '("latest")
               (mapcar
                #'cadr-tui:autocomplete-item-value
                (cadr-tui:editor-autocomplete-items editor))))))

(test editor-custom-autocomplete-isolates-concurrent-editors
  (let* ((entered-a (sb-thread:make-semaphore :count 0))
         (release-a (sb-thread:make-semaphore :count 0))
         (entered-b (sb-thread:make-semaphore :count 0))
         (provider-a
           (cadr-tui:make-autocomplete-provider
            :trigger-characters '(#\#)
            :suggestions-function
            (lambda (lines row column options)
              (declare (ignore lines row column options))
              (sb-thread:signal-semaphore entered-a)
              (sb-thread:wait-on-semaphore release-a)
              (cadr-tui:make-autocomplete-suggestions
               :items
               (list
                (cadr-tui:make-autocomplete-item
                 :value "alpha" :label "alpha"))
               :prefix "#"))))
         (provider-b
           (cadr-tui:make-autocomplete-provider
            :trigger-characters '(#\#)
            :suggestions-function
            (lambda (lines row column options)
              (declare (ignore lines row column options))
              (sb-thread:signal-semaphore entered-b)
              (cadr-tui:make-autocomplete-suggestions
               :items
               (list
                (cadr-tui:make-autocomplete-item
                 :value "beta" :label "beta"))
               :prefix "#"))))
         (editor-a (cadr-tui:make-multiline-editor))
         (editor-b (cadr-tui:make-multiline-editor)))
    (cadr-tui:editor-set-autocomplete-provider editor-a provider-a)
    (cadr-tui:editor-set-autocomplete-provider editor-b provider-b)
    (cadr-tui:editor-set-text editor-a "#")
    (editor-event editor-a :tab)
    (is (sb-thread:wait-on-semaphore entered-a :timeout 1))
    (cadr-tui:editor-set-text editor-b "#")
    (editor-event editor-b :tab)
    (is (sb-thread:wait-on-semaphore entered-b :timeout 1))
    (let ((request-b
            (cadr-tui::multiline-editor-autocomplete-request editor-b)))
      (sb-thread:join-thread
       (cadr-tui::editor-autocomplete-request-thread request-b)))
    (is (cadr-tui:editor-poll-autocomplete editor-b))
    (is (string= "beta" (cadr-tui:editor-text editor-b)))
    (is (not (cadr-tui:editor-autocomplete-visible-p editor-b)))
    (is (not (cadr-tui:editor-autocomplete-visible-p editor-a)))
    (sb-thread:signal-semaphore release-a)
    (let ((request-a
            (cadr-tui::multiline-editor-autocomplete-request editor-a)))
      (sb-thread:join-thread
       (cadr-tui::editor-autocomplete-request-thread request-a)))
    (is (cadr-tui:editor-poll-autocomplete editor-a))
    (is (string= "alpha" (cadr-tui:editor-text editor-a)))
    (is (not (cadr-tui:editor-autocomplete-visible-p editor-a)))))

(test editor-custom-autocomplete-rejects-results-after-text-or-cursor-change
  (let* ((entered (sb-thread:make-semaphore :count 0))
         (release (sb-thread:make-semaphore :count 0))
         (provider
           (cadr-tui:make-autocomplete-provider
            :trigger-characters '(#\#)
            :suggestions-function
            (lambda (lines row column options)
              (declare (ignore lines row column options))
              (sb-thread:signal-semaphore entered)
              (sb-thread:wait-on-semaphore release)
              (cadr-tui:make-autocomplete-suggestions
               :items
               (list
                (cadr-tui:make-autocomplete-item
                 :value "stale" :label "stale"))
               :prefix "#"))))
         (editor (cadr-tui:make-multiline-editor)))
    (cadr-tui:editor-set-autocomplete-provider editor provider)
    (cadr-tui:editor-set-text editor "#")
    (editor-event editor :tab)
    (is (sb-thread:wait-on-semaphore entered :timeout 1))
    (setf (cadr-tui::multiline-editor-cursor editor) 0)
    (sb-thread:signal-semaphore release)
    (let ((request
            (cadr-tui::multiline-editor-autocomplete-request editor)))
      (sb-thread:join-thread
       (cadr-tui::editor-autocomplete-request-thread request)))
    (is (cadr-tui:editor-poll-autocomplete editor))
    (is (not (cadr-tui:editor-autocomplete-visible-p editor)))))

(test editor-custom-autocomplete-tab-applies-a-single-async-result
  (let* ((provider
           (cadr-tui:make-autocomplete-provider
            :suggestions-function
            (lambda (lines row column options)
              (declare (ignore lines row column options))
              (cadr-tui:make-autocomplete-suggestions
               :items
               (list
                (cadr-tui:make-autocomplete-item
                 :value "README.md" :label "README.md"))
               :prefix "REA"))))
         (editor
           (cadr-tui:make-multiline-editor :text "REA")))
    (cadr-tui:editor-set-autocomplete-provider editor provider)
    (editor-event editor :tab)
    (let ((request
            (cadr-tui::multiline-editor-autocomplete-request editor)))
      (sb-thread:join-thread
       (cadr-tui::editor-autocomplete-request-thread request)))
    (is (cadr-tui:editor-poll-autocomplete editor))
    (is (string= "README.md" (cadr-tui:editor-text editor)))
    (is (not (cadr-tui:editor-autocomplete-visible-p editor)))))

(test editor-enter-applies-and-submits-slash-completion
  (let* ((provider
           (cadr-tui:make-autocomplete-provider
            :commands
            (list
             (cadr-tui:make-autocomplete-command
              :name "help"))))
         (editor (cadr-tui:make-multiline-editor)))
    (cadr-tui:editor-set-autocomplete-provider editor provider)
    (editor-event editor :text "/")
    (multiple-value-bind (action value)
        (editor-event editor :enter)
      (is (eq :submit action))
      (is (string= "/help" value)))
    (is (string= "" (cadr-tui:editor-text editor)))))

(test editor-word-wrap-keeps-boundaries-and-wide-cells
  (let ((editor
          (cadr-tui:make-multiline-editor
           :text "alpha beta中文"
           :prompt "")))
    (multiple-value-bind (lines row column)
        (cadr-tui:render-editor editor 7)
      (declare (ignore row column))
      (let ((plain
              (editor-render-plain-lines lines)))
        (is (string= "───────"
                     (first plain)))
        (is (equal '("alpha" "beta中" "文")
                   (mapcar
                    (lambda (line)
                      (string-right-trim '(#\Space) line))
                    (subseq plain 1 (1- (length plain))))))
        (is (string= "───────"
                     (car (last plain)))))
      (is (every (lambda (line)
                   (<= (cadr-tui:visible-width line) 7))
                 lines)))))

(test editor-renders-horizontal-borders-and-thirty-percent-viewport
  (let ((editor
          (cadr-tui:make-multiline-editor
           :text
           (format nil
                   "zero~%one~%two~%three~%four~%five~%six~%seven"))))
    (multiple-value-bind (lines row column)
        (cadr-tui:render-editor
         editor 16 :terminal-rows 10)
      (let ((plain (editor-render-plain-lines lines)))
        (is (= 7 (length plain)))
        (is (search "↑ 3 more" (first plain)))
        (is (equal '("three" "four" "five" "six" "seven")
                   (mapcar
                    (lambda (line)
                      (string-right-trim '(#\Space) line))
                    (subseq plain 1 6))))
        (is (string=
             (make-string 16 :initial-element #\─)
             (car (last plain))))
        (is (string=
             (cadr-tui:theme-foreground
              :border-muted
              (make-string 16 :initial-element #\─))
             (car (last lines))))
        (is (= 5 row))
        (is (= 5 column))
        (is (every
             (lambda (line)
               (= 16 (cadr-tui:visible-width line)))
             lines))))))

(test editor-fake-cursor-covers-whole-grapheme-and-keeps-ime-position
  (let ((editor
          (cadr-tui:make-multiline-editor
           :text "A你🙂" :prompt "")))
    (editor-event editor :left)
    (multiple-value-bind (lines row column)
        (cadr-tui:render-editor
         editor 12 :terminal-rows 24 :focused-p t)
      (is (= 1 row))
      (is (= 3 column))
      (is (search
           (format nil "~C[7m🙂~C[27m"
                   #\Escape #\Escape)
           (second lines)))
      (is (= 12 (cadr-tui:visible-width (second lines)))))
    (editor-event editor :left)
    (multiple-value-bind (lines row column)
        (cadr-tui:render-editor
         editor 12 :terminal-rows 24 :focused-p t)
      (is (= 1 row))
      (is (= 1 column))
      (is (search
           (format nil "~C[7m你~C[27m"
                   #\Escape #\Escape)
           (second lines))))
    (cadr-tui:editor-set-text editor "行尾")
    (multiple-value-bind (lines row column)
        (cadr-tui:render-editor
         editor 12 :terminal-rows 24 :focused-p t)
      (is (= 1 row))
      (is (= 4 column))
      (is (search
           (format nil "~C[7m ~C[27m"
                   #\Escape #\Escape)
           (second lines))))))

(test editor-unfocused-overlay-state-keeps-logical-cursor-without-fake-cursor
  (let ((editor
          (cadr-tui:make-multiline-editor
           :text "你🙂" :prompt "")))
    (editor-event editor :left)
    (multiple-value-bind (lines row column)
        (cadr-tui:render-editor
         editor 10 :terminal-rows 24 :focused-p nil)
      (is (= 1 row))
      (is (= 2 column))
      (is (null
           (search (format nil "~C[7m" #\Escape)
                   (second lines)))))))

(test editor-incremental-cjk-and-emoji-input-never-renders-empty-grapheme
  (let ((editor
          (cadr-tui:make-multiline-editor :prompt "")))
    (cadr-tui:editor-set-autocomplete-provider
     editor
     (cadr-tui:make-autocomplete-provider
      :base-path (uiop:getcwd)))
    ;; A real terminal may split a ZWJ emoji at any codepoint boundary.  Render
    ;; every intermediate state, including a trailing joiner, just as the TUI
    ;; does after each input chunk.
    (loop for character across "中文ABC🙂👨‍👩‍👧‍👦 é"
          do
          (editor-event editor :text (string character))
          (multiple-value-bind (lines row column)
              (cadr-tui:render-editor
               editor 80 :terminal-rows 24 :focused-p t)
            (declare (ignore row column))
            (is (every
                 (lambda (line)
                   (= 80 (cadr-tui:visible-width line)))
                 lines))))
    (is (string= "中文ABC🙂👨‍👩‍👧‍👦 é"
                 (cadr-tui:editor-text editor)))))

(test editor-autocomplete-centers-selection-after-bottom-border
  (let* ((commands
           (loop for index below 8
                 collect
                 (cadr-tui:make-autocomplete-command
                  :name (format nil "command-~D" index)
                  :description
                  (format nil "description ~D" index))))
         (provider
           (cadr-tui:make-autocomplete-provider
            :commands commands))
         (editor
           (cadr-tui:make-multiline-editor :prompt "")))
    (cadr-tui:editor-set-autocomplete-provider editor provider)
    (editor-event editor :text "/")
    (loop repeat 5 do (editor-event editor :down))
    (multiple-value-bind (lines row column)
        (cadr-tui:render-editor
         editor 60 :terminal-rows 24)
      (declare (ignore column))
      (let* ((plain (editor-render-plain-lines lines))
             (bottom-border-position
               (position
                (make-string 60 :initial-element #\─)
                plain :test #'string=
                :from-end t))
             (popup
               (subseq plain (1+ bottom-border-position)))
             (styled-popup
               (subseq lines (1+ bottom-border-position)))
             (selected-position
               (position-if
                (lambda (line)
                  (search "→ command-5" line))
                popup)))
        (is (= 1 row))
        (is (= 6 (length popup)))
        (is (some
             (lambda (line)
               (and (search "→ command-5" line)
                    (search "description 5" line)))
             popup))
        (is (search
             (cadr-tui:theme-foreground-ansi :accent)
             (nth selected-position styled-popup)))
        (is (some
             (lambda (line)
               (search "(6/8)" line))
             popup))
        (is (every
             (lambda (line)
               (= 60 (cadr-tui:visible-width line)))
             lines))))))
