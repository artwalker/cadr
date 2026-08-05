(in-package #:cadr-cli)

(defstruct (user-message-selector-state
            (:constructor
                %make-user-message-selector-state))
  (items nil :type list)
  (selected 0 :type (integer 0 *))
  (max-visible 10 :type (integer 1 *))
  keybindings)

(defun make-user-message-selector-state
    (&key items initial-selected-value
       (max-visible 10) keybindings)
  (let ((initial
          (and initial-selected-value
               (position
                initial-selected-value items
                :key #'cadr-tui:select-item-value
                :test #'equal))))
    (%make-user-message-selector-state
     :items (copy-list items)
     :selected
     (or initial
         (max 0 (1- (length items))))
     :max-visible (max 1 max-visible)
     :keybindings
     (or keybindings
         (cadr-tui:make-keybindings-manager)))))

(defun user-message-selector-move (state delta)
  (let ((count
          (length
           (user-message-selector-state-items state))))
    (setf
     (user-message-selector-state-selected state)
     (selector-frame-move-index
      (user-message-selector-state-selected state)
      count delta)))
  state)

(defun user-message-selector-selection (state)
  (let ((item
          (nth
           (user-message-selector-state-selected state)
           (user-message-selector-state-items state))))
    (and item
         (cadr-tui:select-item-value item))))

(defun user-message-selector-handle-event
    (state event)
  (case (cadr-tui:input-event-kind event)
    (:up
     (user-message-selector-move state -1)
     (values :changed nil))
    (:down
     (user-message-selector-move state 1)
     (values :changed nil))
    ((:enter :submit)
     (let ((value
             (user-message-selector-selection state)))
       (if value
           (values :select value)
           (values nil nil))))
    ((:escape :cancel :interrupt)
     (values :cancel nil))
    (otherwise
     (values nil nil))))

(defun user-message-selector-handle-raw-input
    (state data)
  (let ((keybindings
          (user-message-selector-state-keybindings state)))
    (cond
      ((selector-keybinding-matches-p
        keybindings data "tui.select.up")
       (user-message-selector-move state -1)
       (values :changed nil t))
      ((selector-keybinding-matches-p
        keybindings data "tui.select.down")
       (user-message-selector-move state 1)
       (values :changed nil t))
      ((selector-keybinding-matches-p
        keybindings data "tui.select.confirm")
       (let ((value
               (user-message-selector-selection state)))
         (values (and value :select) value t)))
      ((selector-keybinding-matches-p
        keybindings data "tui.select.cancel")
       (values :cancel nil t))
      (t
       (values nil nil nil)))))

(defun render-user-message-selector
    (state width)
  (render-selector-frame
   (make-selector-frame
    :items (user-message-selector-state-items state)
    :selected (user-message-selector-state-selected state)
    :maximum (user-message-selector-state-max-visible state)
    :sections
    (list
     :blank
     (list :title "Fork from Message" :plain)
     (list
      :lines
      (component-text-lines
       (cadr-tui:theme-foreground
        :muted
        "Select a user message to copy the active path up to that point into a new session")
       width :padding-x 1))
     :blank :border :blank :viewport :count :blank :border)
    :item-renderer
    (lambda (item index selected-p total item-width)
      (let* ((text
               (string-trim
                '(#\Space #\Tab #\Newline #\Return)
                (cl-ppcre:regex-replace-all
                 "\\n"
                 (cadr-tui:select-item-label item)
                 " ")))
             (message
               (cadr-tui:truncate-to-width
                text (max 0 (- item-width 2)) "")))
        (list
         (selector-fit-line
          (concatenate
           'string
           (if selected-p
               (cadr-tui:theme-foreground
                :accent "› ")
               "  ")
           (if selected-p
               (cadr-tui:theme-bold message)
               message))
          item-width)
         (selector-muted-line
          (format nil "  Message ~D of ~D"
                  (1+ index) total)
          item-width)
         "")))
    :empty-renderer
    (lambda (item-width total)
      (declare (ignore total))
      (list
       (selector-muted-line
        "  No user messages found" item-width))))
   width))
