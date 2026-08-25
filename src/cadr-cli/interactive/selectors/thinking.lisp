(in-package #:cadr-cli)

(defparameter +thinking-selector-keybinding-definitions+
  (append
   (copy-tree
    cadr-tui::+tui-keybinding-definitions+)
   '(("app.thinking.save" . ("ctrl+s"))
     ("app.thinking.clearSearchOrCancel"
      . ("ctrl+c")))))

(defun make-thinking-selector-keybindings
    (&optional user-bindings)
  (cadr-tui:make-keybindings-manager
   :definitions
   +thinking-selector-keybinding-definitions+
   :user-bindings user-bindings))

(defparameter *default-thinking-selector-keybindings*
  (make-thinking-selector-keybindings))

(defun thinking-selector-keybindings (state)
  (or (thinking-selector-state-keybindings state)
      *default-thinking-selector-keybindings*))

(defun thinking-level-label (level)
  (string-downcase (symbol-name level)))

(defun thinking-level-search-text (level)
  (format nil "~A ~A"
          (thinking-level-label level)
          (or (settings-thinking-description level) "")))

(defstruct (thinking-selector-state
            (:constructor %make-thinking-selector-state))
  (levels nil :type list)
  current-level
  default-level
  (query "" :type string)
  (filtered-levels nil :type list)
  (filter-query nil :type (or null string))
  (filtered-count 0 :type (integer 0 *))
  (selected 0 :type (integer 0 *))
  keybindings)

(defun thinking-selector-apply-filter (state)
  (let* ((query (thinking-selector-state-query state))
         (last-query (thinking-selector-state-filter-query state)))
    (unless (string= query (or last-query ""))
      (let* ((levels (thinking-selector-state-levels state))
             (filtered
               (if (zerop (length query))
                   levels
                   (selector-fuzzy-filter
                    levels query #'thinking-level-search-text))))
        (setf
         (thinking-selector-state-filtered-levels state)
         filtered
         (thinking-selector-state-filter-query state)
         query
         (thinking-selector-state-filtered-count state)
         (length filtered)))))
  state)

(defun thinking-selector-clamp-selected (state)
  (let ((count
          (thinking-selector-state-filtered-count state)))
    (setf
     (thinking-selector-state-selected state)
     (if (zerop count)
         0
         (min
          (thinking-selector-state-selected state)
          (1- count)))))
  state)

(defun thinking-selector-select-current (state)
  (let* ((levels
           (thinking-selector-state-filtered-levels state))
         (index
           (position
            (thinking-selector-state-current-level state)
            levels
            :test #'eq)))
    (setf
     (thinking-selector-state-selected state)
     (or index 0)))
  state)

(defun make-thinking-selector-state
    (&key levels current-level default-level
       keybindings)
  (let ((state
          (%make-thinking-selector-state
           :levels (copy-list levels)
           :current-level current-level
           :default-level default-level
           :keybindings
           (or keybindings
               *default-thinking-selector-keybindings*))))
    (thinking-selector-apply-filter state)
    (thinking-selector-select-current state)
    state))

(defun thinking-selector-selected-level (state)
  (nth
   (thinking-selector-state-selected state)
   (thinking-selector-state-filtered-levels state)))

(defun thinking-selector-set-query (state query)
  (setf
   (thinking-selector-state-query state)
   (or query ""))
  (thinking-selector-apply-filter state)
  (if (plusp (length (thinking-selector-state-query state)))
      (setf (thinking-selector-state-selected state) 0)
      (thinking-selector-clamp-selected state))
  state)

(defun thinking-selector-move (state delta)
  (setf
   (thinking-selector-state-selected state)
   (selector-frame-move-index
    (thinking-selector-state-selected state)
    (thinking-selector-state-filtered-count state)
    delta))
  state)

(defun thinking-selector-key-p (state data name)
  (selector-keybinding-matches-p
   (thinking-selector-keybindings state)
   data name))

(defun thinking-selector-handle-raw-input (state data)
  (cond
    ((thinking-selector-key-p state data "tui.select.up")
     (thinking-selector-move state -1)
     (values :changed nil t))
    ((thinking-selector-key-p state data "tui.select.down")
     (thinking-selector-move state 1)
     (values :changed nil t))
    ((thinking-selector-key-p state data "tui.select.pageUp")
     (thinking-selector-move state -10)
     (values :changed nil t))
    ((thinking-selector-key-p state data "tui.select.pageDown")
     (thinking-selector-move state 10)
     (values :changed nil t))
    ((thinking-selector-key-p state data "tui.select.confirm")
     (let ((level (thinking-selector-selected-level state)))
       (values (and level :select) level t)))
    ((thinking-selector-key-p state data "app.thinking.save")
     (let ((level (thinking-selector-selected-level state)))
       (values (and level :persist) level t)))
    ((thinking-selector-key-p
      state data "app.thinking.clearSearchOrCancel")
     (if (plusp (length (thinking-selector-state-query state)))
         (progn
           (thinking-selector-set-query state "")
           (values :changed nil t))
         (values :cancel nil t)))
    ((thinking-selector-key-p state data "tui.select.cancel")
     (values :cancel nil t))
    (t
     (values nil nil nil))))

(defun thinking-selector-handle-event (state event)
  (case (cadr-tui:input-event-kind event)
    (:up
     (thinking-selector-move state -1)
     (values :changed nil))
    (:down
     (thinking-selector-move state 1)
     (values :changed nil))
    (:page-up
     (thinking-selector-move state -10)
     (values :changed nil))
    (:page-down
     (thinking-selector-move state 10)
     (values :changed nil))
    (:enter
     (let ((level (thinking-selector-selected-level state)))
       (values (and level :select) level)))
    ((:escape :interrupt)
     (values :cancel nil))
    (:backspace
     (thinking-selector-set-query
      state
      (selector-delete-query-character
       (thinking-selector-state-query state)))
     (values :changed nil))
    (:text
     (thinking-selector-set-query
      state
      (concatenate
       'string
       (thinking-selector-state-query state)
       (or (cadr-tui:input-event-text event) "")))
     (values :changed nil))
    (otherwise
     (values nil nil))))

(defun thinking-level-description-line (level default-level)
  (let* ((base (settings-thinking-description level))
         (suffix
           (when (and default-level (eq level default-level))
             " · default")))
    (if suffix
        (concatenate 'string base suffix)
        base)))

(defun render-thinking-selector (state width)
  (multiple-value-bind (visible start end total)
      (selector-frame-visible-slice
       (thinking-selector-state-filtered-levels state)
       (thinking-selector-state-selected state)
       10)
    (let* ((selected (thinking-selector-state-selected state))
           (current (thinking-selector-state-current-level state))
           (default (thinking-selector-state-default-level state))
           (selected-level
             (and visible
                  (nth selected
                       (thinking-selector-state-filtered-levels
                        state))))
           (body-lines
             (append
              (if visible
                  (loop
                    for level in visible
                    for index from start
                    for selected-p = (= index selected)
                    for current-p = (eq level current)
                    for label = (thinking-level-label level)
                    for description =
                      (thinking-level-description-line
                       level default)
                    collect
                    (selector-component-text-line
                     (concatenate
                      'string
                      (if selected-p
                          (cadr-tui:theme-foreground :accent "→ ")
                          "  ")
                      (if selected-p
                          (cadr-tui:theme-foreground
                           :accent label)
                          label)
                      "  "
                      (cadr-tui:theme-foreground
                       :muted description)
                      (if current-p
                          (cadr-tui:theme-foreground :success " ✓")
                          ""))
                     width :padding-x 0))
                  (list
                   (selector-component-text-line
                    (cadr-tui:theme-foreground
                     :muted "  No matching levels")
                    width :padding-x 0)))
              (when (> total (length visible))
                (list
                 (selector-component-text-line
                  (cadr-tui:theme-foreground
                   :muted
                   (format nil "  (~D/~D)" (1+ selected) total))
                  width :padding-x 0)))
              (when selected-level
                (list
                 ""
                 (selector-component-text-line
                  (cadr-tui:theme-foreground
                   :muted
                   (format nil "  ~A"
                           (thinking-level-description-line
                            selected-level default)))
                  width :padding-x 0))))))
      (render-selector-frame
       (make-selector-frame
        :sections
        (list
         (list
          :lines
          (list
           (selector-component-text-line
            (cadr-tui:theme-foreground
             :accent
             (cadr-tui:theme-bold "Thinking Level"))
            width :padding-x 0)
           ""
           (selector-component-text-line
            (cadr-tui:theme-foreground
             :muted
             (format
              nil
              "~A cycles thinking levels in-session"
              (or
               (first
                (cadr-tui:keybinding-keys
                 (thinking-selector-keybindings state)
                 "app.thinking.cycle"))
               "ctrl+t")))
            width :padding-x 0)
           ""))
         (list :input (thinking-selector-state-query state))
         :blank
         (list :lines body-lines)
         :blank
         (list
          :lines
          (list
           (selector-component-text-line
            (cadr-tui:theme-foreground
             :dim
             "  Enter to select · Ctrl+S to set as default · Esc to cancel")
            width :padding-x 0)))
         :border))
       width))))
