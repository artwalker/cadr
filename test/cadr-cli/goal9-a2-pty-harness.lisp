(defpackage #:cadr-goal9-a2-pty-harness
  (:use #:cl)
  (:export #:main))

(in-package #:cadr-goal9-a2-pty-harness)

(defun input-has-code-p (input code)
  (loop for character across input
        thereis (= code (char-code character))))

(defun write-marker (terminal marker)
  (cadr-tui:terminal-write
   terminal
   (format nil "~A~%" marker)))

(defparameter +frame-separator+ (code-char 30))

(defun pad-contract-line (line width)
  (concatenate
   'string line
   (make-string
    (max 0 (- width (cadr-tui:visible-width line)))
    :initial-element #\Space)))

(defun padded-contract-snapshot (width rows lines)
  (append
   (mapcar
    (lambda (line)
      (pad-contract-line line width))
    lines)
   (make-list
    (max 0 (- rows (length lines)))
    :initial-element "")))

(defun assert-contract-equal (label expected actual)
  (unless (equal expected actual)
    (error
     "~A mismatch:~%expected: ~S~%actual:   ~S"
     label expected actual)))

(defun read-contract-frame (terminal)
  (loop with buffer = ""
        do
        (setf
         buffer
         (concatenate
          'string buffer
          (cadr-tui:terminal-read-input terminal)))
        (let ((separator
                (position +frame-separator+ buffer)))
          (when separator
            (unless (= separator (1- (length buffer)))
              (error
               "Goal 9 A2 PTY frame contained trailing input: ~S"
               (subseq buffer (1+ separator))))
            (return (subseq buffer 0 separator))))))

(defun contract-frame-events (decoder frame)
  (append
   (cadr-tui:feed-input decoder frame)
   (cadr-tui:flush-input decoder)))

(defun render-editor-contract-frame
    (terminal renderer editor width rows expected marker)
  (multiple-value-bind (lines row column)
      (cadr-tui:render-editor editor width)
    (cadr-tui:render-frame
     renderer lines
     :cursor-row row :cursor-column column)
    (let* ((virtual
             (cadr-tui:make-virtual-terminal
              :columns width :rows rows))
           (virtual-renderer
             (cadr-tui:make-terminal-renderer virtual)))
      (cadr-tui:render-frame
       virtual-renderer lines
       :cursor-row row :cursor-column column)
      (assert-contract-equal
       marker expected
       (cadr-tui:virtual-terminal-snapshot virtual)))
    (write-marker terminal marker)))

(defparameter +input-editor-snapshots+
  (let ((full
          (padded-contract-snapshot
           24 8
           '("────────────────────────"
             "> alpha beta"
             "  中文👩‍💻 omega"
             "────────────────────────")))
        (without-omega
          (padded-contract-snapshot
           24 8
           '("────────────────────────"
             "> alpha beta"
             "  中文👩‍💻 "
             "────────────────────────"))))
    (list full full full without-omega full without-omega)))

(defparameter +input-editor-texts+
  (list
   (format nil "alpha beta~%中文👩‍💻 omega")
   (format nil "alpha beta~%中文👩‍💻 omega")
   (format nil "alpha beta~%中文👩‍💻 omega")
   (format nil "alpha beta~%中文👩‍💻 ")
   (format nil "alpha beta~%中文👩‍💻 omega")
   (format nil "alpha beta~%中文👩‍💻 ")))

(defparameter +input-editor-cursors+
  '((1 11) (1 6) (1 11) (1 6) (1 11) (1 6)))

(defun run-input-editor-contract (terminal renderer)
  (let ((decoder (cadr-tui:make-input-decoder))
        (editor
          (cadr-tui:make-multiline-editor :prompt "> ")))
    (loop for expected in +input-editor-snapshots+
          for text in +input-editor-texts+
          for cursor in +input-editor-cursors+
          for index from 1
          for marker =
            (format nil
                    "GOAL9_A2_INPUT_EDITOR_SNAPSHOT_~D_OK"
                    index)
          do
          (dolist
              (event
               (contract-frame-events
                decoder (read-contract-frame terminal)))
            (cadr-tui:editor-handle-event editor event))
          (assert-contract-equal
           (format nil "input editor text ~D" index)
           text (cadr-tui:editor-text editor))
          (assert-contract-equal
           (format nil "input editor cursor ~D" index)
           cursor
           (multiple-value-list
            (cadr-tui:editor-cursor editor)))
          (render-editor-contract-frame
           terminal renderer editor 24 8 expected marker))))

(defparameter +completion-snapshots+
  (list
   (padded-contract-snapshot
    40 10
    '("────────────────────────────────────────"
      "./no"
      "────────────────────────────────────────"
      "→ notes.md"))
   (padded-contract-snapshot
    40 10
    '("────────────────────────────────────────"
      "./notes.md"
      "────────────────────────────────────────"))
   (padded-contract-snapshot
    40 10
    '("────────────────────────────────────────"
      "./no"
      "────────────────────────────────────────"))
   (padded-contract-snapshot
    40 10
    '("────────────────────────────────────────"
      "/"
      "────────────────────────────────────────"
      "→ settings"
      "  model"
      "  scoped-models"
      "  export"
      "  import"
      "  (1/22)"))
   (padded-contract-snapshot
    40 10
    '("────────────────────────────────────────"
      "/m"
      "────────────────────────────────────────"))))

(defparameter +completion-texts+
  '("./no" "./notes.md" "./no" "/" "/m"))

(defparameter +completion-visible+
  '(t nil nil t nil))

(defun run-completion-contract (terminal renderer)
  (let* ((root
           (or (uiop:getenv "GOAL9_A2_PTY_FIXTURE_ROOT")
               (error "GOAL9_A2_PTY_FIXTURE_ROOT is required")))
         (decoder (cadr-tui:make-input-decoder))
         (editor (cadr-tui:make-multiline-editor)))
    (cadr-tui:editor-set-autocomplete-provider
     editor
     (cadr-cli::make-tui-autocomplete-provider
      :base-path (uiop:ensure-directory-pathname root)))
    (loop for expected in +completion-snapshots+
          for text in +completion-texts+
          for visible in +completion-visible+
          for index from 1
          for marker =
            (format nil
                    "GOAL9_A2_COMPLETION_SNAPSHOT_~D_OK"
                    index)
          do
          (dolist
              (event
               (contract-frame-events
                decoder (read-contract-frame terminal)))
            (cadr-tui:editor-handle-event editor event))
          (assert-contract-equal
           (format nil "completion text ~D" index)
           text (cadr-tui:editor-text editor))
          (assert-contract-equal
           (format nil "completion visibility ~D" index)
           visible
           (not
            (null
             (cadr-tui:editor-autocomplete-visible-p editor))))
          (render-editor-contract-frame
           terminal renderer editor 40 10 expected marker))))

(defparameter +overlay-snapshots+
  (list
   '("────────────────────────────────────────────────────────────"
     "> " "" "  Alpha  true" "  Beta   false" "→ Gamma  true"
     "" "  Gamma setting" ""
     "  Type to search · Enter/Space to change · Esc to cancel"
     "────────────────────────────────────────────────────────────"
     "" "" "")
   '("────────────────────────────────────────────────────────────"
     "> " "" "→ Alpha  true" "  Beta   false" "  Gamma  true"
     "" "  Alpha setting" ""
     "  Type to search · Enter/Space to change · Esc to cancel"
     "────────────────────────────────────────────────────────────"
     "" "" "")
   '("────────────────────────────────────────────────────────────"
     "> ga" "" "→ Gamma  true" "" "  Gamma setting" ""
     "  Type to search · Enter/Space to change · Esc to cancel"
     "────────────────────────────────────────────────────────────"
     "" "" "" "" "")
   '("────────────────────────────────────────────────────────────"
     "> " "" "→ Alpha  true" "  Beta   false" "  Gamma  true"
     "" "  Alpha setting" ""
     "  Type to search · Enter/Space to change · Esc to cancel"
     "────────────────────────────────────────────────────────────"
     "" "" "")
   '("────────────────────────────────────────────────────────────"
     "> " "" "→ Alpha  true" "  Beta   false" "  Gamma  true"
     "" "  Alpha setting" ""
     "  Type to search · Enter/Space to change · Esc to cancel"
     "────────────────────────────────────────────────────────────"
     "" "" "")))

(defparameter +overlay-selected+ '(2 0 0 0 0))
(defparameter +overlay-queries+ '("" "" "ga" "" ""))
(defparameter +overlay-actions+
  '(:changed :changed :changed :changed :cancel))

(defun make-contract-settings-overlay ()
  (cadr-cli::make-settings-selector-state
   :options
   (list
    (cadr-cli::make-settings-option
     :id "alpha" :label "Alpha"
     :description "Alpha setting"
     :value t :values (list t nil))
    (cadr-cli::make-settings-option
     :id "beta" :label "Beta"
     :description "Beta setting"
     :value nil :values (list t nil))
    (cadr-cli::make-settings-option
     :id "gamma" :label "Gamma"
     :description "Gamma setting"
     :value t :values (list t nil)))))

(defun render-overlay-contract-frame
    (terminal renderer overlay expected marker)
  (let ((lines
          (cadr-cli::render-settings-selector overlay 60)))
    (cadr-tui:render-frame renderer lines)
    (let* ((virtual
             (cadr-tui:make-virtual-terminal
              :columns 60 :rows 14))
           (virtual-renderer
             (cadr-tui:make-terminal-renderer virtual)))
      (cadr-tui:render-frame virtual-renderer lines)
      (assert-contract-equal
       marker expected
       (cadr-tui:virtual-terminal-snapshot virtual)))
    (write-marker terminal marker)))

(defun run-overlay-contract (terminal renderer)
  (let ((decoder (cadr-tui:make-input-decoder))
        (overlay (make-contract-settings-overlay)))
    (loop for expected in +overlay-snapshots+
          for selected in +overlay-selected+
          for query in +overlay-queries+
          for expected-action in +overlay-actions+
          for index from 1
          for marker =
            (format nil
                    "GOAL9_A2_OVERLAY_SNAPSHOT_~D_OK"
                    index)
          do
          (let ((action nil)
                (frame (read-contract-frame terminal)))
            (multiple-value-bind
                  (raw-action raw-value handled-p)
                (cadr-cli::settings-selector-handle-raw-input
                 overlay frame)
              (declare (ignore raw-value))
              (if handled-p
                  (setf action raw-action)
                  (dolist
                      (event
                       (contract-frame-events decoder frame))
                    (multiple-value-bind (next-action value)
                        (cadr-cli::settings-selector-handle-event
                         overlay event)
                      (declare (ignore value))
                      (when next-action
                        (setf action next-action))))))
            (assert-contract-equal
             (format nil "overlay action ~D" index)
             expected-action action))
          (assert-contract-equal
           (format nil "overlay selection ~D" index)
           selected
           (cadr-cli::settings-selector-state-selected overlay))
          (assert-contract-equal
           (format nil "overlay query ~D" index)
           query
           (cadr-cli::settings-selector-state-query overlay))
          (render-overlay-contract-frame
           terminal renderer overlay expected marker))))

(defun run-interaction-contract (scenario)
  (unless
      (and
       (cadr-tui:terminal-stream-p *standard-input* :input)
       (cadr-tui:terminal-stream-p *standard-output* :output))
    (error "Goal 9 A2 PTY harness requires terminal stdin and stdout"))
  (let* ((terminal (cadr-tui:make-process-terminal))
         (renderer (cadr-tui:make-terminal-renderer terminal))
         (prefix
           (string-upcase
            (substitute #\_ #\- scenario))))
    (unwind-protect
         (progn
           (cadr-tui:terminal-start terminal)
           (write-marker
            terminal (format nil "GOAL9_A2_~A_READY" prefix))
           (cond
             ((string= scenario "input-editor")
              (run-input-editor-contract terminal renderer))
             ((string= scenario "completion")
              (run-completion-contract terminal renderer))
             ((string= scenario "overlay")
              (run-overlay-contract terminal renderer))
             (t
              (error "Unknown Goal 9 A2 PTY scenario: ~A"
                     scenario)))
           (cadr-tui:terminal-stop terminal)
           (format t "GOAL9_A2_~A_EXIT:OK~%" prefix)
           (finish-output))
      (cadr-tui:terminal-stop terminal))))

(defun run-lifecycle-harness ()
  (unless
      (and
       (cadr-tui:terminal-stream-p *standard-input* :input)
       (cadr-tui:terminal-stream-p *standard-output* :output))
    (error "Goal 9 A2 PTY harness requires terminal stdin and stdout"))
  (let ((terminal (cadr-tui:make-process-terminal))
        (done-p nil)
        (exit-reason :unknown)
        (suspended-p nil))
    (labels
        ((start-terminal ()
           (cadr-tui:terminal-start terminal))
         (stop-terminal ()
           (cadr-tui:terminal-stop terminal))
         (render-resumed ()
           (write-marker terminal "GOAL9_A2_RESUMED")))
      (unwind-protect
           (progn
             (start-terminal)
             (write-marker terminal "GOAL9_A2_READY")
             (loop until done-p
                   for input = (cadr-tui:terminal-read-input terminal)
                   do
                   (cond
                     ((input-has-code-p input 3)
                      (setf done-p t
                            exit-reason :ctrl-c))
                     ((input-has-code-p input 26)
                      (setf suspended-p t)
                      (cadr-cli::suspend-tui
                       :linux
                       #'stop-terminal
                       #'start-terminal
                       #'render-resumed
                       #'cadr-cli::suspend-current-process
                       #'cadr-cli::call-with-sigcont-handler))
                     ((find #\q input :test #'char-equal)
                      (setf done-p t
                            exit-reason
                            (if suspended-p
                                :suspend-resume
                                :normal)))))
             (stop-terminal)
             (format t "GOAL9_A2_EXIT:~A~%"
                     (string-upcase
                      (symbol-name exit-reason)))
             (finish-output))
        (stop-terminal)))))

(defun main ()
  (let ((scenario (uiop:getenv "GOAL9_A2_PTY_SCENARIO")))
    (if scenario
        (run-interaction-contract scenario)
        (run-lifecycle-harness))))

(main)
