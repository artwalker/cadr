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
  (query-cursor 0 :type (integer 0 *))
  (input-origin nil)
  (input-width 80 :type (integer 1 *))
  (filtered-levels nil :type list)
  (filter-query nil :type (or null string))
  (filtered-count 0 :type (integer 0 *))
  (selected 0 :type (integer 0 *))
  (list-origin nil)
  (list-limit 10 :type (integer 1 *))
  (mouse-pressed nil)
  keybindings)

(defun thinking-selector-apply-filter (state)
  (let* ((query (thinking-selector-state-query state))
         (last-query (thinking-selector-state-filter-query state)))
    (unless (and (stringp last-query)
                 (string= query last-query))
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

(defun thinking-selector-edit-query (state query cursor)
  (let ((query (or query "")))
    (setf
     (thinking-selector-state-query state) query
     (thinking-selector-state-query-cursor state)
     (max 0 (min cursor (length query))))
    (thinking-selector-apply-filter state)
    (if (plusp (length query))
        (setf (thinking-selector-state-selected state) 0)
        (thinking-selector-clamp-selected state)))
  state)

(defun thinking-selector-set-query (state query)
  (let ((query (or query "")))
    (thinking-selector-edit-query state query (length query))))

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
     (let* ((query (thinking-selector-state-query state))
            (cursor
              (min
               (thinking-selector-state-query-cursor state)
               (length query)))
            (start
              (if (zerop cursor)
                  0
                  (cadr-tui::previous-cluster-boundary
                   query cursor))))
       (unless (= start cursor)
         (thinking-selector-edit-query
          state
          (concatenate
           'string
           (subseq query 0 start)
           (subseq query cursor))
          start)))
     (values :changed nil))
    (:text
     (let* ((query (thinking-selector-state-query state))
            (cursor
              (min
               (thinking-selector-state-query-cursor state)
               (length query)))
            (text
              (or (cadr-tui:input-event-text event) "")))
       (thinking-selector-edit-query
        state
        (concatenate
         'string
         (subseq query 0 cursor)
         text
         (subseq query cursor))
        (+ cursor (length text))))
     (values :changed nil))
    (otherwise
     (values nil nil))))

(defun thinking-selector-handle-mouse (state gesture local-y)
  (let ((origin (thinking-selector-state-input-origin state))
        (x (getf gesture :x)))
    (when (and (integerp origin)
               (eql local-y origin)
               (eq (getf gesture :type) :press)
               (eq (getf gesture :button) :left)
               (integerp x))
      (let* ((query (thinking-selector-state-query state))
             (input
               (cadr-tui:make-single-line-input
                :value query :prompt "> ")))
        (setf (cadr-tui::single-line-input-cursor input)
              (min
               (thinking-selector-state-query-cursor state)
               (length query)))
        (cadr-tui:render-single-line-input
         input
         (thinking-selector-state-input-width state))
        (when (cadr-tui:single-line-input-handle-mouse
               input :type :press :button :left :x x :y 0)
          (setf (thinking-selector-state-query-cursor state)
                (cadr-tui::single-line-input-cursor input))
          (return-from thinking-selector-handle-mouse t)))))
  (unless (and (integerp (thinking-selector-state-list-origin state))
               (integerp local-y))
    (return-from thinking-selector-handle-mouse nil))
  (let ((y (- local-y (thinking-selector-state-list-origin state)))
        (levels (thinking-selector-state-filtered-levels state)))
    (when (minusp y)
      (return-from thinking-selector-handle-mouse nil))
    (multiple-value-bind (next action)
        (cadr-tui:centered-list-mouse
         (length levels)
         (thinking-selector-state-selected state)
         (thinking-selector-state-list-limit state)
         y
         (getf gesture :type)
         (getf gesture :button)
         (getf gesture :wheel-delta)
         :pressed (thinking-selector-state-mouse-pressed state))
      (case action
        (:wheel
         (setf (thinking-selector-state-selected state) next)
         (values t nil nil))
        (:press
         (setf (thinking-selector-state-mouse-pressed state) next
               (thinking-selector-state-selected state) next)
         (values t nil nil))
        (:click
         (setf (thinking-selector-state-mouse-pressed state) nil
               (thinking-selector-state-selected state) next)
         (multiple-value-bind (kind value)
             (thinking-selector-handle-event
              state (cadr-tui:make-input-event :kind :enter))
           (values t kind value)))
        (t nil)))))

(defun thinking-level-description-line (level default-level)
  (let* ((base (settings-thinking-description level))
         (suffix
           (when (and default-level (eq level default-level))
             " · default")))
    (if suffix
        (concatenate 'string base suffix)
        base)))

;; Immutable chrome + themed fragments keyed by width / text so
;; th_draw paints reuse ANSI wraps instead of rebuilding title,
;; footer, arrows, and muted descriptions every frame.
(defparameter *thinking-selector-title-by-width*
  (make-hash-table :test #'eql))
(defparameter *thinking-selector-footer-by-width*
  (make-hash-table :test #'eql))
(defparameter *thinking-selector-empty-by-width*
  (make-hash-table :test #'eql))
(defparameter *thinking-selector-cycle-by-key*
  (make-hash-table :test #'equal))
(defparameter *thinking-selector-muted-by-text*
  (make-hash-table :test #'equal))
(defparameter *thinking-selector-accent-by-text*
  (make-hash-table :test #'equal))
(defparameter *thinking-selector-arrow-accent* nil)
(defparameter *thinking-selector-check-success* nil)

(defun thinking-selector-muted (text)
  (or (gethash text *thinking-selector-muted-by-text*)
      (setf (gethash text *thinking-selector-muted-by-text*)
            (cadr-tui:theme-foreground :muted text))))

(defun thinking-selector-accent (text)
  (or (gethash text *thinking-selector-accent-by-text*)
      (setf (gethash text *thinking-selector-accent-by-text*)
            (cadr-tui:theme-foreground :accent text))))

(defun thinking-selector-arrow-accent ()
  (or *thinking-selector-arrow-accent*
      (setf *thinking-selector-arrow-accent*
            (cadr-tui:theme-foreground :accent "→ "))))

(defun thinking-selector-check-success ()
  (or *thinking-selector-check-success*
      (setf *thinking-selector-check-success*
            (cadr-tui:theme-foreground :success " ✓"))))

(defun thinking-selector-title-line (width)
  (or (gethash width *thinking-selector-title-by-width*)
      (setf (gethash width *thinking-selector-title-by-width*)
            (selector-component-text-line
             (cadr-tui:theme-foreground
              :accent
              (cadr-tui:theme-bold "Thinking Level"))
             width :padding-x 0))))

(defun thinking-selector-footer-line (width)
  (or (gethash width *thinking-selector-footer-by-width*)
      (setf (gethash width *thinking-selector-footer-by-width*)
            (selector-component-text-line
             (cadr-tui:theme-foreground
              :dim
              "  Enter to select · Ctrl+S to set as default · Esc to cancel")
             width :padding-x 0))))

(defun thinking-selector-empty-line (width)
  (or (gethash width *thinking-selector-empty-by-width*)
      (setf (gethash width *thinking-selector-empty-by-width*)
            (selector-component-text-line
             (thinking-selector-muted "  No matching levels")
             width :padding-x 0))))

(defun thinking-selector-cycle-line (state width)
  (let* ((key
           (or
            (first
             (cadr-tui:keybinding-keys
              (thinking-selector-keybindings state)
              "app.thinking.cycle"))
            "ctrl+t"))
         (cache-key (cons width key)))
    (or (gethash cache-key *thinking-selector-cycle-by-key*)
        (setf (gethash cache-key *thinking-selector-cycle-by-key*)
              (selector-component-text-line
               (thinking-selector-muted
                (format
                 nil
                 "~A cycles thinking levels in-session"
                 key))
               width :padding-x 0)))))

(defun thinking-selector-level-row
    (level selected-p current-p default width)
  (let ((label (thinking-level-label level))
        (description
          (thinking-level-description-line level default)))
    (selector-component-text-line
     (with-output-to-string (out)
       (write-string
        (if selected-p
            (thinking-selector-arrow-accent)
            "  ")
        out)
       (write-string
        (if selected-p
            (thinking-selector-accent label)
            label)
        out)
       (write-string "  " out)
       (write-string (thinking-selector-muted description) out)
       (when current-p
         (write-string (thinking-selector-check-success) out)))
     width :padding-x 0)))

(defun render-thinking-selector (state width)
  (multiple-value-bind (visible start end total)
      (selector-frame-visible-slice
       (thinking-selector-state-filtered-levels state)
       (thinking-selector-state-selected state)
       10)
    (declare (ignore end))
    (let* ((selected (thinking-selector-state-selected state))
           (current (thinking-selector-state-current-level state))
           (default (thinking-selector-state-default-level state))
           (selected-level
             (and visible
                  (nth selected
                       (thinking-selector-state-filtered-levels
                        state))))
           (body-lines nil))
      (if visible
          (loop
            for level in visible
            for index from start
            do (push
                (thinking-selector-level-row
                 level
                 (= index selected)
                 (eq level current)
                 default
                 width)
                body-lines))
          (push (thinking-selector-empty-line width) body-lines))
      (when (> total (length visible))
        (push
         (selector-component-text-line
          (thinking-selector-muted
           (format nil "  (~D/~D)" (1+ selected) total))
          width :padding-x 0)
         body-lines))
      (when selected-level
        (push "" body-lines)
        (push
         (selector-component-text-line
          (thinking-selector-muted
           (format nil "  ~A"
                   (thinking-level-description-line
                    selected-level default)))
          width :padding-x 0)
         body-lines))
      (setf body-lines (nreverse body-lines))
      (let* ((header
               (list
                (thinking-selector-title-line width)
                ""
                (thinking-selector-cycle-line state width)
                ""))
             (input
               (multiple-value-list
                (selector-input-rendering
                 (thinking-selector-state-query state)
                 width
                 :cursor
                 (thinking-selector-state-query-cursor state)))))
        (setf (thinking-selector-state-list-origin state)
              (+ (length header) (length (first input)) 1)
              (thinking-selector-state-input-origin state)
              (length header)
              (thinking-selector-state-input-width state)
              (max 1 width)
              (thinking-selector-state-list-limit state)
              10)
        (render-selector-frame
         (make-selector-frame
          :sections
          (list
           (list :lines header)
           (list :component
                 (first input)
                 (second input)
                 (third input))
           :blank
           (list :lines body-lines)
           :blank
           (list
            :lines
            (list (thinking-selector-footer-line width)))
           :border))
         width)))))
