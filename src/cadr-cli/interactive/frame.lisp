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
  (let* ((embed-working-p
           (and (typep editor 'cadr-tui:multiline-editor)
                (cadr-tui:multiline-editor-embed-working-status-p
                 editor)))
         (embedded-working-message
           (and embed-working-p
                (null (tui-state-status-message state))
                busy-p
                (tui-state-working-visible-p state)
                (or (tui-state-working-message state)
                    "Working...")))
         (embedded-working-spinner-frame
           (when embedded-working-message
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
                   spinner-frame)))))
    (multiple-value-bind
          (editor-lines editor-row editor-column)
        (render-editor-component editor width rows (null overlay)
         :working-message embedded-working-message
         :working-spinner-frame embedded-working-spinner-frame)
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
                 (not embedded-working-message)
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
                nil))
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
               (tui-state-code-block-indent state))))
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
      (values
       (nconc visible
              pending-message-lines
              status-indicator
              widget-above-lines
              active-editor-lines
              widget-below-lines
       footer-lines)
       cursor-row
       (if overlay
           overlay-column
           editor-column)
       editor-origin)))))
