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
  (let ((input
          (pop
           (goal9-p2-key-terminal-inputs terminal))))
    (or
     (if (functionp input)
         (funcall input)
         input)
     (when
         (funcall
          (goal9-p2-key-terminal-worker-done-p terminal))
       (format nil "~C[100;5u" #\Escape))
     "")))

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

(test goal10-busy-tui-routes-steering-follow-up-and-shows-pending-copy
  (let* ((state (cadr-cli::make-tui-state :model "faux"))
         (editor (cadr-tui:make-multiline-editor))
         (steering-message
           (cadr-ai:make-user-message :content "change direction"))
         (follow-up-message
           (cadr-ai:make-user-message :content "after this"))
         (event
           (cadr-agent::make-agent-event
            :type :queue-update
            :steering (list steering-message)
            :follow-up (list follow-up-message))))
    (cadr-cli::tui-handle-agent-event state event)
    (is
     (equal
      '(""
        " Steering: change direction"
        " Follow-up: after this"
        " ↳ Alt+Up to edit all queued messages")
      (mapcar
       (lambda (line)
         (string-right-trim
          '(#\Space)
          (cadr-tui::strip-ansi line)))
       (cadr-cli::render-tui-pending-message-lines
        state 80))))
    (multiple-value-bind (lines row column)
        (cadr-cli::render-tui-state
         state editor 80 16 :busy-p t)
      (declare (ignore row column))
      (let ((screen (format nil "~{~A~^~%~}" lines)))
        (is (search "Steering: change direction" screen))
        (is (search "Follow-up: after this" screen))
        (is (search "Alt+Up to edit all queued messages" screen))))))

(test goal10-busy-tui-dequeue-restores-both-queues-to-the-editor
  (let ((started (sb-thread:make-semaphore :count 0))
        (release (sb-thread:make-semaphore :count 0))
        (worker-done (sb-thread:make-semaphore :count 0))
        (worker-done-p nil)
        (dequeue-count 0))
    (let (terminal)
      (setf
       terminal
       (make-instance
             'goal9-p2-key-terminal
             :columns 80 :rows 16
             :inputs
             (list
              (format nil "start~C" #\Return)
              (lambda ()
                (sb-thread:wait-on-semaphore started)
                (format nil "steer~C" #\Return))
              "follow"
              (format nil "~C[13;3u" #\Escape)
              (format nil "~C[1;3A" #\Escape)
              (lambda ()
                (sb-thread:wait-on-semaphore worker-done)
                (format nil "~C[99;5u" #\Escape))
              (format nil "~C[99;5u" #\Escape))
             :worker-done-p
             (lambda () worker-done-p)))
      (cadr-cli::run-tui
       (lambda (line)
         (declare (ignore line))
         (sb-thread:signal-semaphore started)
         (sb-thread:wait-on-semaphore release)
         (setf worker-done-p t)
         (sb-thread:signal-semaphore worker-done))
       :busy-input-function
       (lambda (line)
         (declare (ignore line)))
       :follow-up-input-function
       (lambda (line)
         (declare (ignore line)))
       :dequeue-function
       (lambda ()
         (incf dequeue-count)
         (sb-thread:signal-semaphore release)
         '("steer" "follow"))
       :model "faux"
       :terminal terminal)
      (is (= 1 dequeue-count))
      (is
       (search
        "Restored 2 queued messages to editor"
        (goal9-a2-screen-text
         (cadr-tui:virtual-terminal-snapshot terminal))))))
  (let ((editor (cadr-tui:make-multiline-editor)))
    (cadr-tui:editor-set-text editor "draft")
    (is
     (= 2
        (cadr-cli::restore-queued-messages-to-editor
         editor '("steer" "follow"))))
    (is
     (string=
      (format nil "steer~%~%follow~%~%draft")
      (cadr-tui:editor-text editor)))))

(test goal10-pending-hint-uses-the-configured-dequeue-key
  (let ((previous (cadr-tui:get-keybindings)))
    (unwind-protect
         (progn
           (cadr-tui:set-keybindings
            (cadr-tui:make-keybindings-manager
             :user-bindings
             '(("app.message.dequeue" . ("ctrl+g")))))
           (let ((state
                   (cadr-cli::make-tui-state
                    :model "faux")))
             (setf
              (cadr-cli::tui-state-follow-up-messages state)
              (list
               (cadr-ai:make-user-message
                :content "later")))
             (is
              (search
               "Ctrl+G to edit all queued messages"
               (format
                nil "~{~A~^~%~}"
                (cadr-cli::render-tui-pending-message-lines
                 state 80))))))
      (cadr-tui:set-keybindings previous))))

(test goal10-busy-tui-enter-and-alt-enter-use-distinct-queues
  (let ((previous-kitty-p
          (cadr-tui:kitty-protocol-active-p)))
    (unwind-protect
         (progn
           ;; The virtual terminal models xterm/Windows Terminal here.  Do
           ;; not inherit protocol negotiation state from an earlier test.
           (cadr-tui:set-kitty-protocol-active nil)
           (let ((started
                   (sb-thread:make-semaphore :count 0))
                 (release
                   (sb-thread:make-semaphore :count 0))
                 (started-p nil)
                 (worker-done-p nil)
                 (steering nil)
                 (follow-up nil))
             (let ((terminal
                     (make-instance
                      'goal9-p2-key-terminal
                      :columns 80 :rows 16
                      :inputs
                      (list
                       (format nil "start~C" #\Return)
                       (lambda ()
                         (unless
                             (sb-thread:wait-on-semaphore
                              started :timeout 1)
                           (error "Busy worker did not start"))
                         (format nil "steer~C" #\Return))
                       "follow-xterm"
                       (format nil "~C[27;3;13~~" #\Escape)
                       "follow-legacy"
                       (format nil "~C~C" #\Escape #\Return)
                       (lambda ()
                         (sb-thread:signal-semaphore release)
                         (unless (= 2 (length follow-up))
                           (error
                            "Expected two follow-up messages, got ~S"
                            follow-up))
                         ""))
                      :worker-done-p
                      (lambda () worker-done-p))))
               (cadr-cli::run-tui
                (lambda (line)
                  (declare (ignore line))
                  (setf started-p t)
                  (sb-thread:signal-semaphore started)
                  (sb-thread:wait-on-semaphore release)
                  (setf worker-done-p t))
                :busy-input-function
                (lambda (line)
                  (push line steering))
                :follow-up-input-function
                (lambda (line)
                  (push line follow-up)
                  (when (= 2 (length follow-up))
                    (sb-thread:signal-semaphore release)))
                :model "faux"
                :terminal terminal)
               (is-true started-p)
               (is (equal '("steer") (nreverse steering)))
               (is
                (equal '("follow-xterm" "follow-legacy")
                       (nreverse follow-up))))))
      (cadr-tui:set-kitty-protocol-active
       previous-kitty-p))))

(test goal10-busy-tui-steering-is-delivered-after-the-active-turn
  (let ((release (sb-thread:make-semaphore :count 0))
        (worker-done-p nil)
        (stream-calls 0)
        (event-consumer nil)
        (agent nil))
    (labels
        ((assistant-message (text)
           (cadr-ai:make-assistant-message
            :content
            (list
             (cadr-ai:make-text-content :text text))
            :api :openai-responses
            :provider :openai
            :model "faux"
            :stop-reason :stop))
         (stream
             (provider model context on-event
              &key max-tokens temperature abort-p)
           (declare
            (ignore provider model context
                    max-tokens temperature abort-p))
           (incf stream-calls)
           (when (= stream-calls 1)
             (sb-thread:wait-on-semaphore release))
           (let ((message
                   (assistant-message
                    (if (= stream-calls 1)
                        "first done"
                        "steering handled"))))
             (funcall
              on-event
              (cadr-ai:make-stream-event
               :type :start :message message))
             message)))
      (setf
       agent
       (cadr-agent:make-agent
        :provider :openai
        :model
        (cadr-ai:make-model
         :id "faux" :provider :openai
         :api :openai-responses
         :base-url "https://example.invalid"
         :max-tokens 1024)
        :stream-function #'stream
        :on-event
        (lambda (event)
          (when event-consumer
            (funcall event-consumer event)))))
      (let ((terminal
              (make-instance
               'goal9-p2-key-terminal
               :columns 80 :rows 16
               :inputs
               (list
                (format nil "start~C" #\Return)
                (format nil "change direction~C" #\Return))
               :worker-done-p
               (lambda () worker-done-p))))
        (cadr-cli::run-tui
         (lambda (line)
           (unwind-protect
                (cadr-agent:agent-prompt agent line)
             (setf worker-done-p t)))
         :set-event-consumer
         (lambda (consumer)
           (setf event-consumer consumer))
         :busy-input-function
         (lambda (line)
           (cadr-agent:agent-steer agent line)
           (sb-thread:signal-semaphore release))
         :model "faux"
         :terminal terminal))
      (is-false (cadr-agent:agent-busy-p agent))
      (is (= 2 stream-calls))
      (is
       (equal
        '("start" "change direction")
        (loop for message in (cadr-agent:agent-messages agent)
              when (typep message 'cadr-ai:user-message)
                collect
                (cadr-ai::content-text
                 (cadr-ai:user-message-content message))))))))

(test goal10-busy-tui-repeated-escape-does-not-spam-abort-notices
  (let ((release (sb-thread:make-semaphore :count 0))
        (worker-done-p nil)
        (abort-count 0))
    (let ((terminal
            (make-instance
             'goal9-p2-key-terminal
             :columns 80 :rows 16
             :inputs
             (list
              (format nil "start~C" #\Return)
              (string #\Escape)
              ""
              (string #\Escape)
              ""
              (lambda ()
                (sb-thread:signal-semaphore release)
                ""))
             :worker-done-p
             (lambda () worker-done-p))))
      (cadr-cli::run-tui
       (lambda (line)
         (declare (ignore line))
         (sb-thread:wait-on-semaphore release)
         (setf worker-done-p t))
       :abort-function
       (lambda ()
         (incf abort-count))
       :model "faux"
       :terminal terminal)
      (is (= 1 abort-count))
      (is (null
           (search
            "Abort requested"
            (goal9-a2-screen-text
             (cadr-tui:virtual-terminal-snapshot terminal))))))))

(test goal10-busy-tui-escape-aborts-active-tool-and-returns-idle
  (let ((tool-started
          (sb-thread:make-semaphore :count 0))
        (worker-done-p nil)
        (gate-opened-p nil)
        (abort-count 0)
        (stream-calls 0)
        (agent nil))
    (let* ((tool
             (cadr-ai:make-tool
              :name "blocking"
              :description "blocking"
              :parameters
              (cadr-cli::object-schema
               (cadr-ai::json-object) nil)
              :execution-mode :sequential
              :executor
              (lambda (call-id arguments)
                (declare (ignore call-id arguments))
                (sb-thread:signal-semaphore tool-started)
                (loop until
                      (cadr-agent::current-tool-aborted-p)
                      do (sleep 0.001))
                (error "Command aborted"))))
           (stream
             (lambda
                 (provider model context on-event
                  &key max-tokens temperature abort-p)
               (declare
                (ignore provider model context
                        max-tokens temperature))
               (incf stream-calls)
               (let ((message
                       (cadr-ai:make-assistant-message
                        :content
                        (if (= stream-calls 1)
                            (list
                             (cadr-ai:make-tool-call
                              :id "busy-tui-abort-1"
                              :name "blocking"
                              :arguments (cadr-ai::json-object)))
                            nil)
                        :api :openai-responses
                        :provider :openai
                        :model "faux"
                        :stop-reason
                        (if (= stream-calls 1)
                            :tool-use
                            (if (and abort-p (funcall abort-p))
                                :aborted
                                :stop)))))
                 (funcall
                  on-event
                  (cadr-ai:make-stream-event
                   :type :start :message message))
                 message))))
      (setf
       agent
       (cadr-agent:make-agent
        :provider :openai
        :model
        (cadr-ai:make-model
         :id "faux" :provider :openai
         :api :openai-responses
         :base-url "https://example.invalid"
         :max-tokens 1024)
        :tools (list tool)
        :stream-function stream))
      (let ((terminal
              (make-instance
               'goal9-p2-key-terminal
               :columns 80 :rows 16
               :inputs
               (list
                (format nil "run~C" #\Return)
                (lambda ()
                  (setf
                   gate-opened-p
                   (sb-thread:wait-on-semaphore
                    tool-started :timeout 2))
                  (string #\Escape)))
               :worker-done-p
               (lambda () worker-done-p))))
        (cadr-cli::run-tui
         (lambda (line)
           (unwind-protect
                (cadr-agent:agent-prompt agent line)
             (setf worker-done-p t)))
         :abort-function
         (lambda ()
           (incf abort-count)
           (cadr-agent:agent-abort agent))
         :model "faux"
         :terminal terminal))
      (is-true gate-opened-p)
      (is (= 1 abort-count))
      (is-false (cadr-agent:agent-busy-p agent))
      (let ((results
              (remove-if-not
               (lambda (message)
                 (typep message
                        'cadr-ai:tool-result-message))
               (cadr-agent:agent-messages agent))))
        (is (= 1 (length results)))
        (is-true
         (cadr-ai:tool-result-message-is-error
          (first results)))
        (is
         (string=
          "Command aborted"
          (cadr-ai:text-content-text
           (first
            (cadr-ai:tool-result-message-content
             (first results))))))))))

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
    (write-text (merge-pathnames "notes.txt" root) "notes")
    (write-text
     (merge-pathnames "src/main.lisp" root)
     "(in-package #:example)")
    (make-fake-fd-program
     root '("notes.md" "notes.txt" "src/" "src/main.lisp"))
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
        (is (not
             (cadr-tui:editor-autocomplete-visible-p
              editor)))
        (goal9-a2-feed-editor editor decoder (string #\Tab))
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
