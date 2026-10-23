(in-package #:cadr-cli)

(defun render-tui-overlay-lines (overlay width now)
  (cond
    ((session-selector-state-p overlay)
     (render-session-selector overlay width))
    ((tree-selector-state-p overlay)
     (render-tree-selector overlay width))
    ((user-message-selector-state-p overlay)
     (render-user-message-selector overlay width))
    ((model-selector-state-p overlay)
     (render-model-selector overlay width))
    ((thinking-selector-state-p overlay)
     (render-thinking-selector overlay width))
    ((scoped-models-selector-state-p overlay)
     (render-scoped-models-selector overlay width))
    ((trust-selector-state-p overlay)
     (render-trust-selector overlay width))
    ((settings-selector-state-p overlay)
     (render-settings-selector overlay width))
    ((login-method-selector-state-p overlay)
     (render-login-method-selector overlay width))
    ((api-key-input-state-p overlay)
     (render-api-key-input-state overlay width))
    ((runtime-auth-input-state-p overlay)
     (render-runtime-auth-input-state overlay width))
    ((login-dialog-state-p overlay)
     (render-login-dialog-state overlay width))
    ((oauth-selector-state-p overlay)
     (render-oauth-selector overlay width))
    ((extension-custom-ui-state-p overlay)
     (render-extension-custom-ui overlay width))
    ((framed-select-state-p overlay)
     (render-framed-select-state
      overlay width :now now))
    ((typep overlay 'bordered-loader-component)
     (cadr-tui:component-render overlay width))
    (t
     (cadr-tui:render-select-list overlay width))))

(defun render-editor-component
    (editor width rows focused-p
     &key working-message working-spinner-frame)
  (if (typep editor 'cadr-tui:multiline-editor)
      (cadr-tui:render-editor
       editor width :terminal-rows rows :focused-p focused-p
       :working-message working-message
       :working-spinner-frame working-spinner-frame)
      (values
       (cadr-tui:component-render editor width
                                  :focused-p focused-p)
       0 0)))

(defun window-tic-tac-toe-editor-slot
    (transcript pending status widgets-above editor
     widgets-below footer rows)
  ;; pi@4a080252f chat-viewport.ts createChatViewport and
  ;; packages/tui/src/components/stack.ts allocateStackSizes. The
  ;; transcript keeps at least one line and grows. The dock's editor
  ;; keeps at least three lines and shows its top when shrunk, so a
  ;; 20-row board keeps the title and turn and clips the move help.
  ;; The footer shows its top line when it shrinks.
  (labels ((clamp (size min max)
             (let ((floor-min (max 0 (floor (or min 0)))))
               (max floor-min
                    (min (or max most-positive-fixnum)
                         (max 0 (floor size))))))
           (distribute (sizes mins maxs grows shrinks amount grow-p)
             (let ((remaining amount))
               (loop while (plusp remaining)
                     do
                     (let* ((candidates
                              (loop for size in sizes
                                    for min in mins
                                    for max in maxs
                                    for grow in grows
                                    for shrink in shrinks
                                    for index from 0
                                    when (if grow-p
                                             (and (plusp grow)
                                                  (< size max))
                                             (and (plusp shrink)
                                                  (> size min)))
                                      collect index))
                            (total-weight
                              (loop for index in candidates
                                    sum
                                    (if grow-p
                                        (nth index grows)
                                        (* (nth index shrinks)
                                           (max 1 (nth index sizes)))))))
                       (when (or (null candidates)
                                 (zerop total-weight))
                         (return))
                       (let ((distributed 0))
                         (dolist (index candidates)
                           (when (plusp remaining)
                             (let* ((weight
                                      (if grow-p
                                          (nth index grows)
                                          (* (nth index shrinks)
                                             (max 1 (nth index sizes)))))
                                    (proposed
                                      (max 1
                                           (floor
                                            (* remaining weight)
                                            total-weight)))
                                    (capacity
                                      (if grow-p
                                          (- (nth index maxs)
                                             (nth index sizes))
                                          (- (nth index sizes)
                                             (nth index mins))))
                                    (delta
                                      (min remaining proposed
                                           capacity)))
                               (when (plusp delta)
                                 (setf (nth index sizes)
                                       (+ (nth index sizes)
                                          (if grow-p delta (- delta))))
                                 (decf remaining delta)
                                 (incf distributed delta)))))
                         (when (zerop distributed)
                           (return))))))
             sizes)
           (allocate (specs available)
             (let* ((sizes
                      (mapcar
                       (lambda (spec)
                         (destructuring-bind
                             (basis min max grow shrink intrinsic)
                             spec
                           (declare (ignore grow shrink))
                           (clamp
                            (if (eq basis :auto) intrinsic basis)
                            min max)))
                       specs))
                    (mins (mapcar #'second specs))
                    (maxs (mapcar #'third specs))
                    (grows (mapcar #'fourth specs))
                    (shrinks (mapcar #'fifth specs))
                    (total (reduce #'+ sizes :initial-value 0)))
               (cond
                 ((< total available)
                  (distribute sizes mins maxs grows shrinks
                              (- available total) t))
                 ((> total available)
                  (distribute sizes mins maxs grows shrinks
                              (- total available) nil)))
               sizes))
           (take-lines (lines start count)
             (if (or (null lines) (not (plusp count)))
                 nil
                 (subseq lines start
                         (min (length lines)
                              (+ start count)))))
           (take-head (lines count)
             (take-lines lines 0 count))
           (take-tail (lines count)
             (if (or (null lines) (not (plusp count)))
                 nil
                 (take-lines
                  lines
                  (max 0 (- (length lines) count))
                  count))))
    (let* ((dock-specs
             (list
              (list :auto 0 most-positive-fixnum 0 1
                    (length pending))
              (list :auto 0 most-positive-fixnum 0 1
                    (length status))
              (list :auto 0 most-positive-fixnum 0 1
                    (length widgets-above))
              (list :auto 3 most-positive-fixnum 0 1
                    (length editor))
              (list :auto 0 most-positive-fixnum 0 1
                    (length widgets-below))
              (list :auto 0 most-positive-fixnum 0 1
                    (length footer))))
           (dock-natural
             (reduce #'+ dock-specs
                     :key #'sixth :initial-value 0))
           (root-sizes
             (allocate
              (list
               (list 0 1 most-positive-fixnum 1 1 0)
               (list :auto 1 most-positive-fixnum 0 1
                     dock-natural))
              rows))
           (child-sizes
             (allocate dock-specs (second root-sizes))))
      (append
       (take-tail transcript (first root-sizes))
       (take-head pending (first child-sizes))
       (take-head status (second child-sizes))
       (take-head widgets-above (third child-sizes))
       (take-head editor (fourth child-sizes))
       (take-head widgets-below (fifth child-sizes))
       (take-head footer (sixth child-sizes))))))

(defun render-tui-state
    (state editor width rows
     &key overlay busy-p extension-host
       full-document-p
       (now (tui-monotonic-seconds))
       (spinner-frame
         (aref +tui-spinner-frames+ 0))
       floating-overlay)
  (when (and (extension-custom-ui-state-p overlay)
             (extension-custom-ui-state-overlay-p overlay))
    (return-from render-tui-state
      (render-tui-extension-overlay
       state editor width rows overlay
       :busy-p busy-p :extension-host extension-host
       :full-document-p full-document-p :now now
       :spinner-frame spinner-frame)))
  (let* ((embed-working-p
           (and (typep editor 'cadr-tui:multiline-editor)
                (cadr-tui:multiline-editor-embed-working-status-p
                 editor)))
         (status-message
           (tui-state-status-message state))
         ;; Compaction, branch summary, and retry share the editor
         ;; border with Working...
         (embedded-status-message
           (and embed-working-p status-message))
         (embedded-working-message
           (and embed-working-p
                (null status-message)
                busy-p
                (tui-state-working-visible-p state)
                (or (tui-state-working-message state)
                    "Working...")))
         (embedded-border-message
           (or embedded-status-message
               embedded-working-message))
         (embedded-working-spinner-frame
           (when embedded-border-message
             (if embedded-status-message
                 spinner-frame
                 (let ((frames
                         (tui-state-working-indicator-frames state)))
                   (if (consp frames)
                       (nth
                        (mod
                         (floor
                          (* now 1000)
                          (or
                           (tui-state-working-indicator-interval-ms state)
                           80))
                         (length frames))
                        frames)
                       spinner-frame))))))
    (multiple-value-bind
          (editor-lines editor-row editor-column)
        (render-editor-component editor width rows (null overlay)
         :working-message embedded-border-message
         :working-spinner-frame embedded-working-spinner-frame)
      (let* ((pending-message-lines
               (render-tui-pending-message-lines
                state width))
             (status-indicator
               (unless embedded-border-message
                 (or
                  (render-tui-status-indicator
                   (tui-state-status-message state)
                   width :reserve-idle-p nil
                   :spinner-frame spinner-frame)
                  (and
                   busy-p
                   (tui-state-working-visible-p state)
                   (render-tui-status-indicator
                    (or (tui-state-working-message state)
                        "Working...") width
                    :reserve-idle-p nil
                    :spinner-frame
                    (let ((frames
                            (tui-state-working-indicator-frames state)))
                      (if (consp frames)
                          (nth
                           (mod
                            (floor
                             (* now 1000)
                             (or
                              (tui-state-working-indicator-interval-ms state)
                              80))
                            (length frames))
                           frames)
                          spinner-frame))))
                  nil)))
           (header-lines
             (and (tui-state-header-component state)
                  (cadr-tui:component-render
                   (tui-state-header-component state) width)))
           (footer-lines
             (if (tui-state-footer-component state)
                 (cadr-tui:component-render
                  (tui-state-footer-component state) width)
                 (cadr-tui:render-footer
              width
              :cwd (tui-state-cwd state)
              :branch
              (tui-state-branch state)
              :session-name
              (tui-state-session-name state)
              :model
              (tui-state-model state)
              :provider
              (tui-state-provider state)
              :thinking
              (tui-state-thinking state)
              :input
              (tui-state-input-tokens state)
              :output
              (tui-state-output-tokens state)
              :cache-read
              (tui-state-cache-read-tokens state)
              :cache-write
              (tui-state-cache-write-tokens state)
              :latest-cache-hit-rate
              (tui-state-latest-cache-hit-rate
               state)
              :cost
              (and
               (tui-state-cost-known-p state)
               (plusp
                (tui-state-cost state))
               (tui-state-cost state))
              :subscription-p
              (tui-state-subscription-p state)
              :context-percent
              (tui-state-context-percent state)
              :context-window
              (tui-state-context-window state)
              :auto-compact-p
              (tui-state-auto-compact-p state)
              :multiple-providers-p
              (tui-state-multiple-providers-p
               state)
              :statuses
              (tui-state-statuses state)
              :ansi-theme-p t)))
           (widget-above-lines
             (render-tui-widgets
              (tui-state-widgets-above state)
              width
              :spacer-when-empty-p t
              :leading-spacer-p t))
           (widget-below-lines
             (render-tui-widgets
              (tui-state-widgets-below state)
              width
              :spacer-when-empty-p nil
              :leading-spacer-p nil))
           (overlay-rendering
             (and overlay
                  (multiple-value-list
                   (render-tui-overlay-lines
                    overlay width now))))
           (overlay-lines (first overlay-rendering))
           (overlay-row (second overlay-rendering))
           (overlay-column (third overlay-rendering))
           (active-editor-lines
             (if overlay
                 overlay-lines
                 editor-lines))
           (entry-rendering
             (multiple-value-list
              (render-tui-entries
               (tui-state-entries state)
               width
               :extension-host extension-host
               :now now
               :hide-thinking-block-p
               (tui-state-hide-thinking-block-p state)
               :hidden-thinking-label
               (tui-state-hidden-thinking-label state)
               :mermaid-mode
               (tui-state-mermaid-mode state)
               :code-block-indent
               (tui-state-code-block-indent state)
               :output-pad
               (tui-state-output-pad state))))
           (entry-content (first entry-rendering))
           (entry-hits (second entry-rendering))
           (startup-lines
             (if
                 (tui-state-tools-expanded-p state)
                 (or
                  (tui-state-startup-expanded-lines
                   state)
                  (tui-state-startup-compact-lines
                   state))
                 (tui-state-startup-compact-lines
                  state)))
           (startup-lines
             (and startup-lines
                  (render-tui-startup-lines
                   startup-lines width)))
           (all-content
             (append
              header-lines
              (if startup-lines
                  (nconc
                   (list "")
                   (copy-list startup-lines)
                   (list "")
                   entry-content)
                  entry-content)))
           (visible all-content)
           (cursor-row
             (if overlay
                 (and overlay-row
                      (+ (length visible)
                         (length pending-message-lines)
                         (length status-indicator)
                         (length widget-above-lines)
                         overlay-row))
                 (+ (length visible)
                    (length pending-message-lines)
                    (length status-indicator)
                    (length widget-above-lines)
                    editor-row)))
           (editor-origin
             (+ (length visible)
                (length pending-message-lines)
                (length status-indicator)
                (length widget-above-lines))))
      (setf
       (tui-state-summary-click-ranges state)
       (let ((entry-origin
               (+ (length header-lines)
                  (if startup-lines
                      (+ 2 (length startup-lines))
                      0))))
         (mapcar
          (lambda (hit)
            (list (first hit)
                  (+ entry-origin (second hit))
                  (+ entry-origin (third hit))))
          entry-hits)))
      (let* ((dock-line-count
               (+ (length pending-message-lines)
                  (length status-indicator)
                  (length widget-above-lines)
                  (length active-editor-lines)
                  (length widget-below-lines)
                  (length footer-lines)))
             (tic-tac-toe-slot-p
               (and overlay
                    (not floating-overlay)
                    (extension-custom-ui-state-p overlay)
                    (not (extension-custom-ui-state-overlay-p overlay))
                    (let ((component
                            (extension-custom-ui-state-component
                             overlay)))
                      (and component
                           (string=
                            "TIC-TAC-TOE-BOARD-COMPONENT"
                            (symbol-name
                             (class-name
                              (class-of component))))))))
             (frame
               (if tic-tac-toe-slot-p
                   (window-tic-tac-toe-editor-slot
                    all-content
                    pending-message-lines
                    status-indicator
                    widget-above-lines
                    active-editor-lines
                    widget-below-lines
                    footer-lines
                    rows)
                   (nconc visible
                          pending-message-lines
                          status-indicator
                          widget-above-lines
                          active-editor-lines
                          widget-below-lines
                          footer-lines))))
        (values
         frame
         cursor-row
         (if overlay
             overlay-column
             editor-column)
         editor-origin
         dock-line-count
         (when (and floating-overlay
                    (extension-custom-ui-visible-p floating-overlay))
           (list
            (extension-custom-ui-overlay-placement
             floating-overlay width rows)))))))))
