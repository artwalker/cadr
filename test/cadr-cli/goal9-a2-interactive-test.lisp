(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defun goal9-a2-event (kind &optional text)
  (cadr-tui:make-input-event :kind kind :text text))

(defun goal9-a2-feed-editor (editor decoder input)
  (dolist (event (cadr-tui:feed-input decoder input))
    (cadr-tui:editor-handle-event editor event))
  editor)

(defun goal9-a2-flush-editor (editor decoder)
  (dolist (event (cadr-tui:flush-input decoder))
    (cadr-tui:editor-handle-event editor event))
  editor)

(defun goal9-a2-snapshot-lines
    (lines width rows &key (cursor-row 0) (cursor-column 0))
  (let* ((terminal
           (cadr-tui:make-virtual-terminal
            :columns width :rows rows))
         (renderer
           (cadr-tui:make-terminal-renderer terminal)))
    (cadr-tui:render-frame
     renderer lines
     :cursor-row cursor-row
     :cursor-column cursor-column)
    (cadr-tui:virtual-terminal-snapshot terminal)))

(defun goal9-a2-editor-snapshot (editor width rows)
  (multiple-value-bind (lines row column)
      (cadr-tui:render-editor editor width)
    (values
     (goal9-a2-snapshot-lines
      lines width rows
      :cursor-row row :cursor-column column)
     lines row column)))

(defun goal9-a2-state-snapshot
    (state editor width rows &key overlay full-document-p)
  (multiple-value-bind (lines row column)
      (cadr-cli::render-tui-state
       state editor width rows
       :overlay overlay
       :full-document-p full-document-p)
    (values
     (goal9-a2-snapshot-lines
      lines width rows
      :cursor-row row :cursor-column column)
     lines row column)))

(defun goal9-a2-screen-text (snapshot)
  (format nil "~{~A~^~%~}" snapshot))

(defun goal9-a2-model (id name)
  (cadr-ai:make-model
   :id id :name name :provider :faux
   :api :faux :base-url "http://localhost:0"
   :max-tokens 1024))

(defclass goal9-p2-key-terminal
    (cadr-tui::virtual-terminal)
  ((inputs
    :initarg :inputs
    :accessor goal9-p2-key-terminal-inputs)
   (worker-done-p
    :initarg :worker-done-p
    :reader goal9-p2-key-terminal-worker-done-p)))

(defmethod cadr-tui:terminal-read-input
    ((terminal goal9-p2-key-terminal))
  (or
   (pop (goal9-p2-key-terminal-inputs terminal))
   (when
       (funcall
        (goal9-p2-key-terminal-worker-done-p terminal))
     (format nil "~C[100;5u" #\Escape))
   ""))

(test goal9-p2-baseline-key-hints-and-decoder-actions-agree
  (multiple-value-bind (compact expanded)
      (cadr-cli::make-tui-startup-lines
       (cadr-cli::make-resource-snapshot))
    (is (string=
         (format nil "cadr v~A" (cadr-ai::cadr-version))
         (first compact)))
    (is (find
         "escape interrupt · ctrl+c/ctrl+d clear/exit · / commands · ! bash · ctrl+o more"
         compact :test #'string=))
    (is (find "escape to interrupt" expanded :test #'string=))
    (is (find "ctrl+c to clear" expanded :test #'string=))
    (is (find "ctrl+c twice to exit" expanded :test #'string=))
    (is (find "ctrl+d to exit (empty)" expanded :test #'string=)))
  (let ((decoder (cadr-tui:make-input-decoder)))
    (is (eq :clear
            (cadr-tui:input-event-kind
             (first
              (cadr-tui:feed-input
               decoder (string (code-char 3)))))))
    (is (eq :clear
            (cadr-tui:input-event-kind
             (first
              (cadr-tui:feed-input
               decoder
               (format nil "~C[99;5u" #\Escape))))))
    (is (eq :eof
            (cadr-tui:input-event-kind
             (first
              (cadr-tui:feed-input
               decoder
               (format nil "~C[100;5u" #\Escape))))))
    (is (null
         (cadr-tui:feed-input decoder (string #\Escape))))
    (is (eq :escape
            (cadr-tui:input-event-kind
             (first (cadr-tui:flush-input decoder)))))))

(test goal9-p2-ctrl-c-clears-busy-draft-and-escape-interrupts
  (let ((abort-requested
          (sb-thread:make-semaphore :count 0))
        (worker-done-p nil)
        (abort-count 0))
    (let ((terminal
            (make-instance
             'goal9-p2-key-terminal
             :columns 80 :rows 16
             :inputs
             (list
              (format nil "go~C" #\Return)
              "draft"
              (format nil "~C[99;5u" #\Escape)
              (string #\Escape))
             :worker-done-p
             (lambda () worker-done-p))))
      (cadr-cli::run-tui
       (lambda (line)
         (declare (ignore line))
         (sb-thread:wait-on-semaphore abort-requested)
         (setf worker-done-p t))
       :abort-function
       (lambda ()
         (incf abort-count)
         (sb-thread:signal-semaphore abort-requested))
       :model "faux"
       :terminal terminal)
      (is (= 1 abort-count))
      (is (null
           (search
            "draft"
            (goal9-a2-screen-text
             (cadr-tui:virtual-terminal-snapshot terminal)))))))
  (let ((terminal
          (make-instance
           'goal9-p2-key-terminal
           :columns 80 :rows 16
           :inputs
           (list
            "draft"
            (format nil "~C[99;5u" #\Escape)
            (format nil "~C[99;5u" #\Escape))
           :worker-done-p (constantly nil))))
    (cadr-cli::run-tui
     (lambda (line)
       (error "Unexpected submission: ~A" line))
     :model "faux"
     :terminal terminal)
    (is (null
         (search
          "draft"
          (goal9-a2-screen-text
           (cadr-tui:virtual-terminal-snapshot terminal)))))))

(test goal9-a2-input-editor-pty-events-and-virtual-screen-cover-full-contract
  (let* ((decoder (cadr-tui:make-input-decoder))
         (editor
           (cadr-tui:make-multiline-editor
            :prompt "> ")))
    (goal9-a2-feed-editor
     editor decoder
     (format nil "alpha beta~C[13;2u中文👩‍💻 omega"
             #\Escape))
    (is (string=
         (format nil "alpha beta~%中文👩‍💻 omega")
         (cadr-tui:editor-text editor)))
    (multiple-value-bind (snapshot lines row column)
        (goal9-a2-editor-snapshot editor 12 8)
      (declare (ignore row column))
      (let ((screen (goal9-a2-screen-text snapshot)))
        (is (search "alpha" screen))
        (is (search "beta" screen))
        (is (search "中文👩‍💻" screen))
        (is (search "omega" screen)))
      (is (> (length lines) 2))
      (is (every
           (lambda (line)
             (<= (cadr-tui:visible-width line) 12))
           lines)))
    (let ((end-cursor
            (multiple-value-list
             (cadr-tui:editor-cursor editor))))
      (goal9-a2-feed-editor
       editor decoder
       (format nil "~C[1;5D" #\Escape))
      (let ((word-cursor
              (multiple-value-list
               (cadr-tui:editor-cursor editor))))
        (is (= 1 (first word-cursor)))
        (is (< (second word-cursor)
               (second end-cursor))))
      (goal9-a2-feed-editor
       editor decoder
       (format nil "~C[1;5C" #\Escape))
      (is (equal
           end-cursor
           (multiple-value-list
            (cadr-tui:editor-cursor editor))))))
  (let* ((decoder (cadr-tui:make-input-decoder))
         (editor (cadr-tui:make-multiline-editor)))
    (cadr-tui:editor-add-history editor "历史一")
    (cadr-tui:editor-add-history editor "历史二")
    (goal9-a2-feed-editor
     editor decoder (format nil "~C[A" #\Escape))
    (is (string= "历史二" (cadr-tui:editor-text editor)))
    (goal9-a2-feed-editor
     editor decoder (format nil "~C[A" #\Escape))
    (is (string= "历史一" (cadr-tui:editor-text editor)))
    (goal9-a2-feed-editor
     editor decoder (format nil "~C[B" #\Escape))
    (is (string= "历史二" (cadr-tui:editor-text editor))))
  (let* ((decoder (cadr-tui:make-input-decoder))
         (editor
           (cadr-tui:make-multiline-editor
            :text "one two three")))
    (goal9-a2-feed-editor
     editor decoder
     (coerce
      (list (code-char 23)
            (code-char 23)
            (code-char 23))
      'string))
    (is (string= "" (cadr-tui:editor-text editor)))
    (goal9-a2-feed-editor
     editor decoder (string (code-char 25)))
    (is (string=
         "one two three"
         (cadr-tui:editor-text editor)))
    (goal9-a2-feed-editor
     editor decoder (string (code-char 31)))
    (is (string= "" (cadr-tui:editor-text editor)))
    (cadr-tui:editor-set-text editor "alpha")
    (goal9-a2-feed-editor
     editor decoder (string (code-char 23)))
    (cadr-tui:editor-set-text editor "")
    (goal9-a2-feed-editor
     editor decoder (string (code-char 25)))
    (is (string= "alpha" (cadr-tui:editor-text editor)))
    (goal9-a2-feed-editor
     editor decoder
     (format nil "~Cy" #\Escape))
    (is (string=
         "one two three"
         (cadr-tui:editor-text editor)))))

(test goal9-a2-completion-pty-events-snapshot-selection-cancel-and-undo
  (with-test-directory (root)
    (write-text (merge-pathnames "notes.md" root) "notes")
    (write-text
     (merge-pathnames "src/main.lisp" root)
     "(in-package #:example)")
    (make-fake-fd-program
     root '("notes.md" "src/" "src/main.lisp"))
    (with-test-path-prefix (root)
     (let ((provider
             (cadr-cli::make-tui-autocomplete-provider
              :base-path root)))
      (let* ((decoder (cadr-tui:make-input-decoder))
             (editor (cadr-tui:make-multiline-editor)))
        (cadr-tui:editor-set-autocomplete-provider
         editor provider)
        (goal9-a2-feed-editor editor decoder "/")
        (is (cadr-tui:editor-autocomplete-visible-p editor))
        (multiple-value-bind (snapshot lines row column)
            (goal9-a2-editor-snapshot editor 40 10)
          (declare (ignore lines row column))
          (is (search
               "model"
               (goal9-a2-screen-text snapshot))))
        (goal9-a2-feed-editor
         editor decoder (format nil "~C[B~C" #\Escape #\Tab))
        (is (uiop:string-prefix-p
             "/" (cadr-tui:editor-text editor)))
        (let ((text (cadr-tui:editor-text editor)))
          (is (char= #\Space
                     (char text (1- (length text))))))
        (goal9-a2-feed-editor
         editor decoder (string (code-char 31)))
        (is (string= "/" (cadr-tui:editor-text editor)))
        (goal9-a2-feed-editor editor decoder "m")
        (is (cadr-tui:editor-autocomplete-visible-p editor))
        (goal9-a2-feed-editor editor decoder (string #\Escape))
        (goal9-a2-flush-editor editor decoder)
        (is (not
             (cadr-tui:editor-autocomplete-visible-p editor)))
        (is (string= "/m" (cadr-tui:editor-text editor))))
      (let* ((decoder (cadr-tui:make-input-decoder))
             (editor (cadr-tui:make-multiline-editor)))
        (cadr-tui:editor-set-autocomplete-provider
         editor provider)
        (goal9-a2-feed-editor editor decoder "./no")
        (is
         (find
          "./notes.md"
          (cadr-tui:editor-autocomplete-items editor)
          :key #'cadr-tui:autocomplete-item-value
          :test #'string=))
        (multiple-value-bind (snapshot lines row column)
            (goal9-a2-editor-snapshot editor 40 8)
          (declare (ignore lines row column))
          (is (search
               "notes.md"
               (goal9-a2-screen-text snapshot))))
        (goal9-a2-feed-editor editor decoder (string #\Tab))
        (is (string=
             "./notes.md"
             (cadr-tui:editor-text editor)))
        (goal9-a2-feed-editor
         editor decoder (string (code-char 31)))
        (is (string= "./no" (cadr-tui:editor-text editor))))
      (let* ((now 0d0)
             (decoder (cadr-tui:make-input-decoder))
             (editor (cadr-tui:make-multiline-editor)))
        (cadr-tui:editor-set-autocomplete-provider
         editor provider)
        (cadr-tui:editor-set-autocomplete-clock
         editor (lambda () now))
        (goal9-a2-feed-editor editor decoder "@main")
        (incf now 0.02d0)
        (is (cadr-tui:editor-poll-autocomplete editor))
        (is
         (find
          "@src/main.lisp"
          (cadr-tui:editor-autocomplete-items editor)
          :key #'cadr-tui:autocomplete-item-value
          :test #'string=))
        (multiple-value-bind (snapshot lines row column)
            (goal9-a2-editor-snapshot editor 40 8)
          (declare (ignore lines row column))
          (let ((screen (goal9-a2-screen-text snapshot)))
            (is (search "main.lisp" screen))
            (is (null (search "src" screen)))))
        (goal9-a2-feed-editor editor decoder (string #\Tab))
        (is (search
             "@src/main.lisp"
             (cadr-tui:editor-text editor)))
        (goal9-a2-feed-editor
         editor decoder (string (code-char 31)))
        (is (string= "@main" (cadr-tui:editor-text editor))))))))

(test goal9-a2-overlay-selectors-focus-cjk-and-resize-snapshots
  (with-test-directory (root)
    (let* ((one (goal9-a2-model "one" "One"))
           (two (goal9-a2-model "two" "Two"))
           (session
             (cadr-cli::make-session-selector-state
              :current-sessions
              (list
               (cadr-cli:make-session-search-record
                :id "session-one"
                :path "/tmp/session-one.jsonl"
                :name "会话一"
                :modified 1
                :all-messages-text "hello"))))
           (tree
             (cadr-cli::make-tree-selector-state
              :entries
              '((:id "u1" :parent-id nil
                 :type :message :role :user
                 :text "树节点")
                (:id "a1" :parent-id "u1"
                 :type :message :role :assistant
                 :text "answer"))
              :current-leaf-id "a1"))
           (model
             (cadr-cli::make-model-selector-state
              :all-models (list one two)
              :scoped-models (list two one)
              :current-model one
              :refresh-status-message
              "Model catalogs refreshed."))
           (scoped
             (cadr-cli::make-scoped-models-selector-state
              :all-models (list one two)
              :enabled-ids '("faux/one")))
           (settings
             (cadr-cli::make-settings-selector-state
              :options
              (list
               (cadr-cli::make-settings-option
                :id "autocompact"
                :label "Auto-compact"
                :description "Automatically compact context"
                :value t :values (list t nil)))))
           (trust
             (cadr-cli::make-trust-selector-state
              :cwd root :project-trusted-p nil))
           (state
             (cadr-cli::make-tui-state
              :model "faux-1" :session "s1"))
           (editor (cadr-tui:make-multiline-editor)))
      (dolist
          (case
           `((,session "Resume Session" "会话一")
             (,tree "Session Tree" "树节点")
             (,model "Scope: all | scoped"
              "Model catalogs refreshed.")
             (,scoped "Model Configuration" "one")
             (,settings "> " "Auto-compact  true")
             (,trust "Project trust" "Do not trust")))
        (destructuring-bind (overlay &rest expected) case
          (multiple-value-bind (snapshot lines row column)
              (goal9-a2-state-snapshot
               state editor 72 20 :overlay overlay)
            (declare (ignore row column))
            (let ((screen (goal9-a2-screen-text snapshot)))
              (dolist (needle expected)
                (is (search needle screen)))
              (when (eq overlay model)
                (is (null (search "Select Model" screen)))))
            (is (every
                 (lambda (line)
                   (<= (cadr-tui:visible-width line) 72))
                 lines)))))
      (let* ((stack
               (cadr-tui:make-overlay-stack
                :focused-component :editor))
             (first
               (cadr-tui:overlay-stack-show
                stack :session '("会话 overlay")))
             (second
               (cadr-tui:overlay-stack-show
                stack :model '("model overlay"))))
        (is (cadr-tui:overlay-handle-focused-p second))
        (is (not
             (cadr-tui:overlay-handle-focused-p first)))
        (is (eq :model
                (cadr-tui:overlay-stack-input-target stack)))
        (cadr-tui:overlay-handle-set-hidden second t)
        (is (eq :session
                (cadr-tui:overlay-stack-input-target stack)))
        (cadr-tui:overlay-handle-set-hidden second nil)
        (is (eq :model
                (cadr-tui:overlay-stack-input-target stack))))
      (let* ((placement
               (cadr-tui:make-overlay-placement
                :lines '("┌─中文─┐" "│ 选择 │" "└──────┘")
                :width 10 :anchor :center))
             (wide
               (cadr-tui:composite-overlay-frame
                '("stale-wide-content" "base")
                (list placement) 28 8))
             (terminal
               (cadr-tui:make-virtual-terminal
                :columns 28 :rows 8))
             (renderer
               (cadr-tui:make-terminal-renderer terminal)))
        (cadr-tui:render-frame renderer wide)
        (is (search
             "┌─中文─┐"
             (goal9-a2-screen-text
              (cadr-tui:virtual-terminal-snapshot terminal))))
        (setf
         (cadr-tui:terminal-columns terminal) 14
         (cadr-tui:terminal-rows terminal) 6)
        (cadr-tui:invalidate-renderer renderer)
        (let ((narrow
                (cadr-tui:composite-overlay-frame
                 '("base") (list placement) 14 6)))
          (cadr-tui:render-frame renderer narrow)
          (let ((snapshot
                  (cadr-tui:virtual-terminal-snapshot terminal)))
            (is (= 6 (length snapshot)))
            (is (search "中文"
                        (goal9-a2-screen-text snapshot)))
            (is (every
                 (lambda (line)
                   (<= (cadr-tui:visible-width line) 14))
                 snapshot))))))))

(test goal9-a2-faux-stream-rendering-structure-and-status-snapshots
  (let* ((handle
           (cadr-ai:make-faux-provider
            :token-min 1 :token-max 1))
         (model (cadr-ai:faux-get-model handle))
         (state
           (cadr-cli::make-tui-state
            :model "faux-1"
            :session "render-session"
            :session-name "render-session"))
         (editor (cadr-tui:make-multiline-editor))
         (event-types nil)
         (stream-types nil)
         (snapshots nil)
         (tool
           (cadr-ai:make-tool
            :name "echo"
            :description "Echo text"
            :parameters
            (args "type" "object")
            :executor
            (lambda (call-id arguments)
              (declare (ignore call-id arguments))
              (list
               (cadr-ai:make-text-content
                :text
                (format nil
                        "echoed line one~%echoed line two")))))))
    (cadr-ai:faux-set-responses
     handle
     (list
      (cadr-ai:faux-assistant-message
       (list
        (cadr-ai:faux-thinking "plan-stream")
        (cadr-ai:faux-text
         (format nil
                 "## Heading~%- first~%- second~%~%| A | B |~%|---|---|~%| 1 | 2 |~%~%```lisp~%(+ 1 2)~%```~%[docs](https://example.test)"))
        (cadr-ai:faux-tool-call
         "echo" (args "text" "hello")
         :id "tool-render-1"))
       :stop-reason :tool-use)
      (cadr-ai:faux-assistant-message "final-stream")))
    (let ((agent
            (cadr-agent:make-agent
             :provider :faux
             :model model
             :tools (list tool)
             :stream-function
             (lambda (provider selected-model context on-event
                      &rest options)
               (declare (ignore provider))
               (apply
                #'cadr-ai:faux-stream
                handle selected-model context on-event options))
             :on-event
             (lambda (event)
               (push
                (cadr-agent:agent-event-type event)
                event-types)
               (let ((stream-event
                       (cadr-agent:agent-event-stream-event
                        event)))
                 (when stream-event
                   (push
                    (cadr-ai:stream-event-type stream-event)
                    stream-types)))
               (cadr-cli::tui-handle-agent-event state event)
               (when
                   (member
                    (cadr-agent:agent-event-type event)
                    '(:message-update
                      :tool-execution-start
                      :tool-execution-end))
                 (multiple-value-bind
                       (snapshot lines row column)
                     (goal9-a2-state-snapshot
                      state editor 100 40
                      :full-document-p t)
                   (declare (ignore lines row column))
                   (push snapshot snapshots)))))))
      (unwind-protect
           (cadr-agent:agent-prompt agent "render this")
        (cadr-agent:agent-shutdown agent)))
    (setf
     event-types (nreverse event-types)
     stream-types (nreverse stream-types))
    (is (member :thinking-delta stream-types))
    (is (member :text-delta stream-types))
    (is (member :tool-execution-start event-types))
    (is (member :tool-execution-end event-types))
    (let ((streamed
            (format
             nil "~{~A~^~%---~%~}"
             (mapcar #'goal9-a2-screen-text
                     (nreverse snapshots)))))
      (is (search "plan-stream" streamed))
      (is (search "Heading" streamed))
      (is (search "echo" streamed)))
    (setf
     (cadr-cli::tui-state-input-tokens state) 11
     (cadr-cli::tui-state-output-tokens state) 7
     (cadr-cli::tui-state-cache-read-tokens state) 3
     (cadr-cli::tui-state-cost-known-p state) t
     (cadr-cli::tui-state-cost state) 0.0042d0)
    (cadr-cli::set-tui-tools-expanded state t)
    (multiple-value-bind (expanded expanded-lines row column)
        (goal9-a2-state-snapshot
         state editor 100 40 :full-document-p t)
      (declare (ignore row column))
      (let ((screen (goal9-a2-screen-text expanded)))
        (dolist
            (needle
             '("Heading" "first" "A" "B" "(+ 1 2)"
               "docs" "https://example.test" "plan-stream"
               "echoed line one" "final-stream"
               "↑11" "↓7" "R3" "$0.004"
               "render-session"))
          (is (search needle screen))))
      (is (every
           (lambda (line)
             (<= (cadr-tui:visible-width line) 100))
           expanded-lines)))
    (cadr-cli::set-tui-tools-expanded state nil)
    (multiple-value-bind (collapsed lines row column)
        (goal9-a2-state-snapshot
         state editor 100 40 :full-document-p t)
      (declare (ignore lines row column))
      (let ((screen (goal9-a2-screen-text collapsed)))
        (is (search "echo" screen))
        (is (search "echoed line one" screen))))))
