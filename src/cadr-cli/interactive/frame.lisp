(in-package #:cadr-cli)

(defun trailing-lines (lines count)
  (if (<= (length lines) count)
      lines
      (nthcdr (- (length lines) count)
              lines)))

(defun blank-render-line-p (line)
  (zerop
   (length
    (string-trim
     '(#\Space #\Tab #\Newline #\Return)
     (cadr-tui:strip-terminal-sequences
      line)))))

(defun selected-overlay-line-p (line)
  (let ((plain
          (cadr-tui:strip-terminal-sequences
           line)))
    (or
     (search
      (cadr-tui:theme-background-ansi
       :selected-bg :enabled-p t)
      line)
     (uiop:string-prefix-p "→ " plain)
     (uiop:string-prefix-p "› " plain)
     (uiop:string-prefix-p "> " plain))))

(defun fit-overlay-lines (lines height)
  (let ((available (max 0 height)))
    (when (zerop available)
      (return-from fit-overlay-lines nil))
    (when (<= (length lines) available)
      (return-from fit-overlay-lines lines))
    (let* ((compact
             (remove-if #'blank-render-line-p
                        lines))
           (selected
             (position-if
              #'selected-overlay-line-p compact)))
      (when (<= (length compact) available)
        (return-from fit-overlay-lines compact))
      (unless selected
        (let* ((head-count
                 (min 4
                      (max 1
                           (ceiling available 2))))
               (tail-count
                 (- available head-count)))
          (return-from fit-overlay-lines
            (nconc
             (subseq compact 0 head-count)
             (when (plusp tail-count)
               (copy-list
                (nthcdr
                 (- (length compact)
                    tail-count)
                 compact)))))))
      (let* ((last-index
               (1- (length compact)))
             (head-count
               (min 3
                    (max 0 (- available 2))))
             (reserved
               (remove-duplicates
                (append
                 (loop for index below head-count
                       collect index)
                 (when (> available head-count)
                   (list last-index)))
                :test #'=))
             (body-budget
               (- available (length reserved)))
             (body-start
               (max
                head-count
                (min
                 (- selected
                    (floor body-budget 2))
                 (max
                  head-count
                  (- last-index body-budget)))))
             (body
               (loop for index from body-start
                     below
                     (min last-index
                          (+ body-start
                             body-budget))
                     collect index))
             (indices
               (sort
                (remove-duplicates
                 (append reserved
                         body
                         (list selected))
                 :test #'=)
                #'<)))
        (when (> (length indices) available)
          (setf
           indices
           (subseq indices
                   (- (length indices)
                      available))))
        (mapcar
         (lambda (index)
           (nth index compact))
         indices)))))

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
    ((oauth-selector-state-p overlay)
     (render-oauth-selector overlay width))
    ((extension-custom-ui-state-p overlay)
     (render-extension-custom-ui overlay width))
    ((framed-select-state-p overlay)
     (render-framed-select-state
      overlay width :now now))
    (t
     (cadr-tui:render-select-list overlay width))))

(defun render-editor-component (editor width rows focused-p)
  (if (typep editor 'cadr-tui:multiline-editor)
      (cadr-tui:render-editor
       editor width :terminal-rows rows :focused-p focused-p)
      (values
       (cadr-tui:component-render editor width
                                  :focused-p focused-p)
       0 0)))

(defun render-tui-state
    (state editor width rows
     &key overlay busy-p extension-host
       full-document-p
       (now (tui-monotonic-seconds))
       (spinner-frame
         (aref +tui-spinner-frames+ 0)))
  (when (and (extension-custom-ui-state-p overlay)
             (extension-custom-ui-state-overlay-p overlay))
    (return-from render-tui-state
      (render-tui-extension-overlay
       state editor width rows overlay
       :busy-p busy-p :extension-host extension-host
       :full-document-p full-document-p :now now
       :spinner-frame spinner-frame)))
  (multiple-value-bind
        (editor-lines editor-row editor-column)
      (render-editor-component editor width rows (null overlay))
    (let* ((pending-message-lines
             (render-tui-pending-message-lines
              state width))
           (status-indicator
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
              (and
               (not full-document-p)
               (render-tui-status-indicator
                nil width :reserve-idle-p t
                :spinner-frame spinner-frame))))
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
           (overlay-lines
             (and overlay
                  (render-tui-overlay-lines
                   overlay width now)))
           (fixed-lines-without-editor
             (+ (length pending-message-lines)
                (length status-indicator)
                (length widget-above-lines)
                (length widget-below-lines)
                (length footer-lines)))
           (active-editor-lines
             (if overlay
                 (fit-overlay-lines
                  overlay-lines
                  (max 0
                       (- rows
                          fixed-lines-without-editor)))
                 editor-lines))
           (non-content-lines
             (+ (length pending-message-lines)
                (length status-indicator)
                (length widget-above-lines)
                (length active-editor-lines)
                (length widget-below-lines)
                (length footer-lines)))
           (content-height
             (max 0
                  (- rows
                     non-content-lines)))
           (entry-content
             (render-tui-entries
              (tui-state-entries state)
              width
              :extension-host extension-host
              :now now
              :hide-thinking-block-p
              (tui-state-hide-thinking-block-p state)
              :hidden-thinking-label
              (tui-state-hidden-thinking-label state)))
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
           (visible
             (cond
               ((and full-document-p
                     (null overlay))
                all-content)
               (t
                (trailing-lines
                 all-content content-height))))
           (overlay-padding
             ;; Editor-slot overlays keep their fixed viewport geometry;
             ;; ordinary transcript composition keeps its natural height.
             (and overlay
                  (make-list
                   (max 0
                        (- content-height
                           (length visible)))
                   :initial-element "")))
           (cursor-row
             (+ (if overlay
                    (max content-height
                         (length visible))
                    (length visible))
                (length pending-message-lines)
                (length status-indicator)
                (length widget-above-lines)
                (if overlay 0 editor-row))))
      (values
       (nconc overlay-padding
              visible
              pending-message-lines
              status-indicator
              widget-above-lines
              active-editor-lines
              widget-below-lines
              footer-lines)
       cursor-row
       (if overlay 0 editor-column)))))
