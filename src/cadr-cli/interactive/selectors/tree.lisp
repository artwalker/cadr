(in-package #:cadr-cli)

(defun tree-entry-visible-p
    (entry filter)
  (case filter
    (:all t)
    (:messages
     (eq (getf entry :type)
         :message))
    (:user
     (and
      (eq (getf entry :type)
          :message)
      (eq (getf entry :role)
          :user)))
    (:labeled
     (not (null (getf entry :label))))
    (otherwise t)))

(defun nearest-visible-tree-entry
    (entries entry-id filter)
  (let ((by-id
          (make-hash-table :test #'equal))
        (current entry-id))
    (dolist (entry entries)
      (setf
       (gethash (getf entry :id)
                by-id)
       entry))
    (loop while current
          for entry = (gethash current by-id)
          while entry
          when (tree-entry-visible-p entry filter)
            return entry
          do (setf current
                   (getf entry :parent-id)))))

(defstruct tree-selection
  (filter :messages :type symbol)
  selected-id
  preserved-id)

(defun switch-tree-selection-filter
    (selection entries filter)
  (let* ((current
           (or
            (tree-selection-selected-id
             selection)
            (tree-selection-preserved-id
             selection)))
         (nearest
           (nearest-visible-tree-entry
            entries current filter)))
    (if nearest
        (setf
         (tree-selection-selected-id selection)
         (getf nearest :id)
         (tree-selection-preserved-id selection)
         nil)
        (setf
         (tree-selection-preserved-id selection)
         current
         (tree-selection-selected-id selection)
         nil))
    (setf (tree-selection-filter selection)
          filter)
    selection))

(defparameter +tree-selector-keybinding-definitions+
  (append
   (copy-tree
    cadr-tui::+tui-keybinding-definitions+)
   (list
    (cons
     "app.tree.foldOrUp"
     #+darwin '("alt+left" "ctrl+left")
     #-darwin '("ctrl+left" "alt+left"))
    (cons
     "app.tree.unfoldOrDown"
     #+darwin '("alt+right" "ctrl+right")
     #-darwin '("ctrl+right" "alt+right"))
    '("app.message.copy" . ("ctrl+x"))
    '("app.tree.editLabel" . ("shift+l"))
    '("app.tree.toggleLabelTimestamp"
      . ("shift+t"))
    '("app.tree.filter.default" . ("ctrl+d"))
    '("app.tree.filter.noTools" . ("ctrl+t"))
    '("app.tree.filter.userOnly" . ("ctrl+u"))
    '("app.tree.filter.labeledOnly" . ("ctrl+l"))
    '("app.tree.filter.all" . ("ctrl+a"))
    '("app.tree.filter.cycleForward" . ("ctrl+o"))
    '("app.tree.filter.cycleBackward"
      . ("shift+ctrl+o")))))

(defun make-tree-selector-keybindings
    (&optional user-bindings)
  (cadr-tui:make-keybindings-manager
   :definitions
   +tree-selector-keybinding-definitions+
   :user-bindings user-bindings))

(defstruct (tree-selector-state
            (:constructor %make-tree-selector-state))
  (entries nil :type list)
  (ordered-entries nil :type list)
  current-leaf-id
  (filter :default :type symbol)
  (query "" :type string)
  selected-id
  preserved-id
  (visible-ids nil :type list)
  (visible-parent
   (make-hash-table :test #'equal)
   :type hash-table)
  (visible-children
   (make-hash-table :test #'equal)
   :type hash-table)
  (folded
   (make-hash-table :test #'equal)
   :type hash-table)
  (show-label-timestamps-p nil :type boolean)
  (max-visible-lines 10 :type (integer 1 *))
  (mode :list :type symbol)
  label-edit-id
  (label-input "" :type string)
  keybindings
  copy-callback
  select-callback
  cancel-callback
  label-callback)

(defun tree-selector-entry-map (entries)
  (let ((result
          (make-hash-table :test #'equal)))
    (dolist (entry entries)
      (setf
       (gethash (getf entry :id)
                result)
       entry))
    result))

(defun tree-selector-active-path
    (entries current-leaf-id)
  (let ((by-id
          (tree-selector-entry-map entries))
        (result
          (make-hash-table :test #'equal))
        (current current-leaf-id))
    (loop while current
          for entry = (gethash current by-id)
          while entry
          do
             (setf (gethash current result) t
                   current
                   (getf entry :parent-id)))
    result))

(defun tree-selector-prioritize-active
    (entries active-path)
  (append
   (remove-if-not
    (lambda (entry)
      (gethash (getf entry :id)
               active-path))
    entries)
   (remove-if
    (lambda (entry)
      (gethash (getf entry :id)
               active-path))
    entries)))

(defun tree-selector-order-entries
    (entries current-leaf-id)
  (let ((children
          (make-hash-table :test #'equal))
        (known
          (tree-selector-entry-map entries))
        (active-path
          (tree-selector-active-path
           entries current-leaf-id))
        (roots nil)
        (result nil))
    (dolist (entry entries)
      (let ((parent-id
              (getf entry :parent-id)))
        (if (and parent-id
                 (gethash parent-id known))
            (setf
             (gethash parent-id children)
             (nconc
              (gethash parent-id children)
              (list entry)))
            (setf roots
                  (nconc roots (list entry))))))
    (let ((stack
            (tree-selector-prioritize-active
             roots active-path)))
      (loop while stack
            for entry = (pop stack)
            do
               (push entry result)
               (dolist
                   (child
                    (reverse
                     (tree-selector-prioritize-active
                      (gethash
                       (getf entry :id)
                       children)
                      active-path)))
                 (push child stack))))
    (nreverse result)))

(defun tree-selector-settings-entry-p (entry)
  (member
   (getf entry :type)
   '(:label :custom :model-change
     :thinking-level-change :session-info)
   :test #'eq))

(defun tree-selector-entry-filtered-p
    (entry filter current-leaf-id)
  (and
   (not
    (and
     (eq (getf entry :type) :message)
     (eq (getf entry :role) :assistant)
     (zerop
      (length
       (tree-selector-normalize-display-text
        (getf entry :text))))
     (not
      (let ((stop-reason
              (getf entry :stop-reason)))
        (and stop-reason
             (not
              (member stop-reason
                      '(:stop :tool-use)
                      :test #'eq)))))
     (not
      (equal (getf entry :id)
             current-leaf-id))))
   (case filter
     (:user-only
      (and
       (eq (getf entry :type) :message)
       (eq (getf entry :role) :user)))
     (:no-tools
      (and
       (not
        (tree-selector-settings-entry-p entry))
       (not
        (and
         (eq (getf entry :type) :message)
         (member
          (getf entry :role)
          '(:tool-result :toolresult)
          :test #'eq)))))
     (:labeled-only
      (not (null (getf entry :label))))
     (:all t)
     (otherwise
      (not
       (tree-selector-settings-entry-p entry))))))

(defun tree-selector-entry-search-text (entry)
  (format
   nil "~{~A~^ ~}"
   (remove
    nil
    (list
     (getf entry :label)
     (getf entry :role)
     (getf entry :text)
     (getf entry :summary)
     (getf entry :name)
     (getf entry :model-id)
     (getf entry :thinking-level)
     (getf entry :custom-type)))))

(defun tree-selector-query-matches-p
    (entry query)
  (let ((haystack
          (string-downcase
           (tree-selector-entry-search-text
            entry))))
    (every
     (lambda (token)
       (search
        (string-downcase token)
        haystack))
     (remove
      ""
      (cl-ppcre:split "\\s+" query)
      :test #'string=))))

(defun tree-selector-nearest-visible-id
    (state target visible-set)
  (let ((by-id
          (tree-selector-entry-map
           (tree-selector-state-entries state)))
        (current target))
    (loop while current
          for entry = (gethash current by-id)
          when (gethash current visible-set)
            return current
          while entry
          do (setf current
                   (getf entry :parent-id))
          finally
             (return
               (car
                (last
                 (tree-selector-state-visible-ids
                  state)))))))

(defun tree-selector-rebuild-visible-maps
    (state entries)
  (let ((visible-set
          (make-hash-table :test #'equal))
        (parent-map
          (make-hash-table :test #'equal))
        (children-map
          (make-hash-table :test #'equal))
        (by-id
          (tree-selector-entry-map
           (tree-selector-state-entries state))))
    (dolist (entry entries)
      (setf
       (gethash (getf entry :id)
                visible-set)
       t))
    (dolist (entry entries)
      (let ((parent
              (getf entry :parent-id)))
        (loop while
              (and parent
                   (not
                    (gethash parent
                             visible-set)))
              for parent-entry =
                (gethash parent by-id)
              do
                 (setf parent
                       (and parent-entry
                            (getf
                             parent-entry
                             :parent-id))))
        (setf
         (gethash (getf entry :id)
                  parent-map)
         parent
         (gethash parent children-map)
         (nconc
          (gethash parent children-map)
          (list (getf entry :id))))))
    (setf
     (tree-selector-state-visible-parent
      state)
     parent-map
     (tree-selector-state-visible-children
      state)
     children-map)
    visible-set))

(defun tree-selector-apply-filter (state)
  (let* ((target
           (or
            (tree-selector-state-selected-id state)
            (tree-selector-state-preserved-id state)))
         (skip
           (make-hash-table :test #'equal))
         (visible
           (loop
             for entry in
               (tree-selector-state-ordered-entries
                state)
             for id = (getf entry :id)
             for parent-id = (getf entry :parent-id)
             when
               (and
                parent-id
                (or
                 (gethash
                  parent-id
                  (tree-selector-state-folded
                   state))
                 (gethash parent-id skip)))
               do (setf (gethash id skip) t)
             when
               (and
                (not (gethash id skip))
                (tree-selector-entry-filtered-p
                 entry
                 (tree-selector-state-filter state)
                 (tree-selector-state-current-leaf-id
                  state))
                (tree-selector-query-matches-p
                 entry
                 (tree-selector-state-query state)))
               collect entry)))
    (setf
     (tree-selector-state-visible-ids state)
     (mapcar
      (lambda (entry)
        (getf entry :id))
      visible))
    (let* ((visible-set
             (tree-selector-rebuild-visible-maps
              state visible))
           (nearest
             (tree-selector-nearest-visible-id
              state target visible-set)))
      (if nearest
          (setf
           (tree-selector-state-selected-id
            state)
           nearest
           (tree-selector-state-preserved-id
            state)
           nil)
          (setf
           (tree-selector-state-preserved-id
            state)
           target
           (tree-selector-state-selected-id
            state)
           nil))))
  state)

(defun make-tree-selector-state
    (&key entries current-leaf-id
       initial-selected-id
       (filter :default)
       (max-visible-lines 10)
       copy-callback select-callback
       cancel-callback label-callback
       keybindings)
  (let ((state
          (%make-tree-selector-state
           :entries entries
           :ordered-entries
           (tree-selector-order-entries
            entries current-leaf-id)
           :current-leaf-id current-leaf-id
           :filter filter
           :max-visible-lines
           (max 1 max-visible-lines)
           :selected-id
           (or initial-selected-id
               current-leaf-id)
           :keybindings
           (or keybindings
               (make-tree-selector-keybindings))
           :copy-callback copy-callback
           :select-callback select-callback
           :cancel-callback cancel-callback
           :label-callback label-callback)))
    (tree-selector-apply-filter state)))

(defun tree-selector-selected-id (state)
  (tree-selector-state-selected-id state))

(defun tree-selector-visible-ids (state)
  (copy-list
   (tree-selector-state-visible-ids state)))

(defun tree-selector-select-id (state id)
  (when
      (member
       id
       (tree-selector-state-visible-ids state)
       :test #'equal)
    (setf
     (tree-selector-state-selected-id state)
     id
     (tree-selector-state-preserved-id state)
     nil))
  state)

(defun tree-selector-set-filter (state filter)
  (clrhash
   (tree-selector-state-folded state))
  (setf
   (tree-selector-state-filter state)
   filter)
  (tree-selector-apply-filter state))

(defparameter +tree-selector-filter-modes+
  '(:default :no-tools :user-only
    :labeled-only :all))

(defun tree-selector-cycle-filter
    (state direction)
  (let* ((modes
           +tree-selector-filter-modes+)
         (index
           (or
            (position
             (tree-selector-state-filter state)
             modes)
            0)))
    (tree-selector-set-filter
     state
     (nth
      (mod (+ index direction)
           (length modes))
      modes))))

(defun tree-selector-set-query (state query)
  (clrhash
   (tree-selector-state-folded state))
  (setf
   (tree-selector-state-query state)
   (or query ""))
  (tree-selector-apply-filter state))

(defun tree-selector-move (state delta)
  (let* ((ids
           (tree-selector-state-visible-ids
            state))
         (length (length ids)))
    (when (plusp length)
      (let* ((current
               (or
                (position
                 (tree-selector-state-selected-id
                  state)
                 ids :test #'equal)
                0))
             (next
               (selector-frame-move-index
                current length delta)))
        (setf
         (tree-selector-state-selected-id
          state)
         (nth next ids)
         (tree-selector-state-preserved-id
          state)
         nil))))
  state)

(defun tree-selector-foldable-p (state id)
  (let* ((children
           (gethash
            id
            (tree-selector-state-visible-children
             state)))
         (parent
           (gethash
            id
            (tree-selector-state-visible-parent
             state)))
         (siblings
           (gethash
            parent
            (tree-selector-state-visible-children
             state))))
    (and children
         (or (null parent)
             (> (length siblings) 1)))))

(defun tree-selector-branch-segment-id
    (state direction)
  (let* ((selected
           (tree-selector-state-selected-id
            state))
         (ids
           (tree-selector-state-visible-ids
            state))
         (index
           (position selected ids :test #'equal))
         (current selected))
    (unless current
      (return-from
          tree-selector-branch-segment-id
        nil))
    (ecase direction
      (:down
       (loop
         for children =
           (gethash
            current
            (tree-selector-state-visible-children
             state))
         do
            (cond
              ((null children)
               (return current))
              ((cdr children)
               (return (car children)))
              (t
               (setf current
                     (car children))))))
      (:up
       (loop
         for parent =
           (gethash
            current
            (tree-selector-state-visible-parent
             state))
         do
            (when (null parent)
              (return current))
            (let ((siblings
                    (gethash
                     parent
                     (tree-selector-state-visible-children
                      state))))
              (when
                  (and
                   (cdr siblings)
                   (<
                    (or
                     (position current
                               ids :test #'equal)
                     index)
                    index))
                (return current)))
            (setf current parent))))))

(defun tree-selector-fold-or-up (state)
  (let ((id
          (tree-selector-state-selected-id
           state)))
    (if
        (and
         id
         (tree-selector-foldable-p state id)
         (not
          (gethash
           id
           (tree-selector-state-folded state))))
        (progn
          (setf
           (gethash
            id
            (tree-selector-state-folded state))
           t)
          (tree-selector-apply-filter state))
        (tree-selector-select-id
         state
         (tree-selector-branch-segment-id
          state :up))))
  state)

(defun tree-selector-unfold-or-down (state)
  (let ((id
          (tree-selector-state-selected-id
           state)))
    (if
        (and
         id
         (gethash
          id
          (tree-selector-state-folded state)))
        (progn
          (remhash
           id
           (tree-selector-state-folded state))
          (tree-selector-apply-filter state))
        (tree-selector-select-id
         state
         (tree-selector-branch-segment-id
          state :down))))
  state)

(defun tree-selector-selected-entry (state)
  (find
   (tree-selector-state-selected-id state)
   (tree-selector-state-entries state)
   :key
   (lambda (entry)
     (getf entry :id))
   :test #'equal))

(defun tree-selector-copy-selected (state)
  (when (tree-selector-state-copy-callback state)
    (funcall
     (tree-selector-state-copy-callback state)
     (let ((entry
             (tree-selector-selected-entry
              state)))
       (and entry
            (getf entry :text)))))
  state)

(defun tree-selector-toggle-label-timestamps
    (state)
  (setf
   (tree-selector-state-show-label-timestamps-p
    state)
   (not
    (tree-selector-state-show-label-timestamps-p
     state)))
  state)

(defun tree-selector-iso-timestamp
    (&optional (universal-time
                 (get-universal-time)))
  (multiple-value-bind
        (second minute hour day month year)
      (decode-universal-time universal-time)
    (format
     nil
     "~4,'0D-~2,'0D-~2,'0DT~2,'0D:~2,'0D:~2,'0D"
     year month day hour minute second)))

(defun tree-selector-start-label-edit (state)
  (let ((entry
          (tree-selector-selected-entry state)))
    (when entry
      (setf
       (tree-selector-state-mode state) :label
       (tree-selector-state-label-edit-id state)
       (getf entry :id)
       (tree-selector-state-label-input state)
       (or (getf entry :label) ""))))
  state)

(defun tree-selector-confirm-label (state)
  (let* ((id
           (tree-selector-state-label-edit-id
            state))
         (input
           (string-trim
            '(#\Space #\Tab #\Newline #\Return)
            (tree-selector-state-label-input
             state)))
         (label
           (and (plusp (length input))
                input)))
    (when
        (and id
             (tree-selector-state-label-callback
              state))
      (funcall
       (tree-selector-state-label-callback state)
       id label))
    (let ((entry
            (find
             id
             (tree-selector-state-entries state)
             :key
             (lambda (candidate)
               (getf candidate :id))
             :test #'equal)))
      (when entry
        (setf
         (getf entry :label)
         label
         (getf entry :label-timestamp)
         (and label
              (tree-selector-iso-timestamp)))))
    (setf
     (tree-selector-state-mode state) :list
     (tree-selector-state-label-edit-id state)
     nil
     (tree-selector-state-label-input state)
     "")
    (tree-selector-apply-filter state)))

(defun tree-selector-cancel-label (state)
  (setf
   (tree-selector-state-mode state) :list
   (tree-selector-state-label-edit-id state)
   nil
   (tree-selector-state-label-input state)
   "")
  state)

(defun tree-selector-app-key-p
    (state data name)
  (selector-keybinding-matches-p
   (tree-selector-state-keybindings state)
   data name))

(defun tree-selector-handle-raw-input
    (state data)
  (when (eq :label
            (tree-selector-state-mode state))
    (return-from tree-selector-handle-raw-input
      (cond
        ((tree-selector-app-key-p
          state data "tui.select.confirm")
         (tree-selector-confirm-label state)
         (values :changed nil t))
        ((tree-selector-app-key-p
          state data "tui.select.cancel")
         (tree-selector-cancel-label state)
         (values :changed nil t))
        (t
         (values nil nil nil)))))
  (labels
      ((changed (thunk)
         (funcall thunk)
         (values :changed nil t))
       (toggle (mode)
         (tree-selector-set-filter
          state
          (if
              (eq mode
                  (tree-selector-state-filter
                   state))
              :default
              mode))))
    (cond
      ((tree-selector-app-key-p
        state data "app.tree.foldOrUp")
       (changed
        (lambda ()
          (tree-selector-fold-or-up state))))
      ((tree-selector-app-key-p
        state data "app.tree.unfoldOrDown")
       (changed
        (lambda ()
          (tree-selector-unfold-or-down state))))
      ((tree-selector-app-key-p
        state data "app.message.copy")
       (changed
        (lambda ()
          (tree-selector-copy-selected state))))
      ((tree-selector-app-key-p
        state data "app.tree.editLabel")
       (changed
        (lambda ()
          (tree-selector-start-label-edit
           state))))
      ((tree-selector-app-key-p
        state data
        "app.tree.toggleLabelTimestamp")
       (changed
        (lambda ()
          (tree-selector-toggle-label-timestamps
           state))))
      ((tree-selector-app-key-p
        state data "app.tree.filter.default")
       (changed
        (lambda ()
          (tree-selector-set-filter
           state :default))))
      ((tree-selector-app-key-p
        state data "app.tree.filter.noTools")
       (changed
        (lambda () (toggle :no-tools))))
      ((tree-selector-app-key-p
        state data "app.tree.filter.userOnly")
       (changed
        (lambda () (toggle :user-only))))
      ((tree-selector-app-key-p
        state data
        "app.tree.filter.labeledOnly")
       (changed
        (lambda () (toggle :labeled-only))))
      ((tree-selector-app-key-p
        state data "app.tree.filter.all")
       (changed
        (lambda () (toggle :all))))
      ((tree-selector-app-key-p
        state data
        "app.tree.filter.cycleForward")
       (changed
        (lambda ()
          (tree-selector-cycle-filter state 1))))
      ((tree-selector-app-key-p
        state data
        "app.tree.filter.cycleBackward")
       (changed
        (lambda ()
          (tree-selector-cycle-filter state -1))))
      (t
       (values nil nil nil)))))

(defun tree-selector-handle-label-event
    (state event)
  (case (cadr-tui:input-event-kind event)
    (:escape
     (tree-selector-cancel-label state)
     (values :changed nil))
    (:enter
     (tree-selector-confirm-label state)
     (values :changed nil))
    (:backspace
     (let ((input
             (tree-selector-state-label-input
              state)))
       (when (plusp (length input))
         (setf
          (tree-selector-state-label-input state)
          (subseq
           input 0
           (cadr-tui::previous-cluster-boundary
            input (length input))))))
     (values :changed nil))
    (:text
     (setf
      (tree-selector-state-label-input state)
      (concatenate
       'string
       (tree-selector-state-label-input state)
       (or
        (cadr-tui:input-event-text event)
        "")))
     (values :changed nil))
    (otherwise
     (values nil nil))))

(defun tree-selector-handle-event
    (state event)
  (when (eq :label
            (tree-selector-state-mode state))
    (return-from tree-selector-handle-event
      (tree-selector-handle-label-event
       state event)))
  (case (cadr-tui:input-event-kind event)
    (:up
     (tree-selector-move state -1)
     (values :changed nil))
    (:down
     (tree-selector-move state 1)
     (values :changed nil))
    (:page-up
     (tree-selector-move state -10)
     (values :changed nil))
    (:page-down
     (tree-selector-move state 10)
     (values :changed nil))
    (:enter
     (let ((id
             (tree-selector-state-selected-id
              state)))
       (if id
           (values :select id)
           (values nil nil))))
    (:escape
     (if (plusp
          (length
           (tree-selector-state-query state)))
         (progn
           (tree-selector-set-query state "")
           (values :changed nil))
         (values :cancel nil)))
    (:backspace
     (let ((query
             (tree-selector-state-query state)))
       (when (plusp (length query))
         (tree-selector-set-query
          state
          (subseq
           query 0
           (cadr-tui::previous-cluster-boundary
            query (length query))))))
     (values :changed nil))
    (:text
     (tree-selector-set-query
      state
      (concatenate
       'string
       (tree-selector-state-query state)
       (or
        (cadr-tui:input-event-text event)
        "")))
     (values :changed nil))
    (otherwise
     (values nil nil))))

(defun tree-selector-format-label-timestamp
    (value &optional (now (get-universal-time))
                     display-timezone)
  (multiple-value-bind
        (match registers)
      (cl-ppcre:scan-to-strings
       "^(\\d{4})-(\\d{2})-(\\d{2})T(\\d{2}):(\\d{2})(?::(\\d{2})(?:\\.\\d+)?)?(Z|[+-]\\d{2}:?\\d{2})?$"
       (or value ""))
    (declare (ignore match))
    (if registers
        (handler-case
            (let* ((year (parse-integer (aref registers 0)))
                   (month (parse-integer (aref registers 1)))
                   (day (parse-integer (aref registers 2)))
                   (hour (parse-integer (aref registers 3)))
                   (minute (parse-integer (aref registers 4)))
                   (second
                     (if (aref registers 5)
                         (parse-integer (aref registers 5))
                         0))
                   (zone (aref registers 6))
                   (source-timezone
                     (cond
                       ((null zone) display-timezone)
                       ((string= zone "Z") 0)
                       (t
                        (let* ((east-p (char= (char zone 0) #\+))
                               (offset-hours
                                 (parse-integer zone :start 1 :end 3))
                               (offset-minutes
                                 (parse-integer
                                  zone :start
                                  (if (char= (char zone 3) #\:)
                                      4 3)))
                               (offset
                                 (+ offset-hours
                                    (/ offset-minutes 60))))
                          (if east-p (- offset) offset)))))
                   (timestamp
                     (if source-timezone
                         (encode-universal-time
                          second minute hour day month year
                          source-timezone)
                         (encode-universal-time
                          second minute hour day month year))))
              (multiple-value-bind
                    (shown-second shown-minute shown-hour shown-day
                     shown-month shown-year)
                  (if display-timezone
                      (decode-universal-time
                       timestamp display-timezone)
                      (decode-universal-time timestamp))
                (declare (ignore shown-second))
                (multiple-value-bind
                      (now-second now-minute now-hour now-day
                       now-month now-year)
                    (if display-timezone
                        (decode-universal-time now display-timezone)
                        (decode-universal-time now))
                  (declare
                   (ignore now-second now-minute now-hour))
                  (let ((time
                          (format nil "~2,'0D:~2,'0D"
                                  shown-hour shown-minute)))
                    (cond
                      ((and (= shown-year now-year)
                            (= shown-month now-month)
                            (= shown-day now-day))
                       time)
                      ((= shown-year now-year)
                       (format nil "~D/~D ~A"
                               shown-month shown-day time))
                      (t
                       (format nil "~2,'0D/~D/~D ~A"
                               (mod shown-year 100)
                               shown-month shown-day time)))))))
          (error () (or value "")))
        (or value ""))))

(defun tree-selector-status-labels (state)
  ;; Baseline getStatusLabels: append fixed filter / timestamp
  ;; suffixes. Precomputed strings avoid format/~@[ each paint.
  (let ((filter (tree-selector-state-filter state))
        (time-p
          (tree-selector-state-show-label-timestamps-p
           state)))
    (if time-p
        (case filter
          (:no-tools " [no-tools] [+label time]")
          (:user-only " [user] [+label time]")
          (:labeled-only " [labeled] [+label time]")
          (:all " [all] [+label time]")
          (otherwise " [+label time]"))
        (case filter
          (:no-tools " [no-tools]")
          (:user-only " [user]")
          (:labeled-only " [labeled]")
          (:all " [all]")
          (otherwise "")))))

(defun tree-selector-visual-nodes (state)
  (let* ((children
           (tree-selector-state-visible-children state))
         (roots (copy-list (gethash nil children)))
         (multiple-roots-p (> (length roots) 1))
         (visuals (make-hash-table :test #'equal))
         (stack nil))
    (loop for id in (reverse roots)
          for index downfrom (1- (length roots))
          do
          (push
           (list id
                 (if multiple-roots-p 1 0)
                 multiple-roots-p
                 multiple-roots-p
                 (= index (1- (length roots)))
                 nil
                 multiple-roots-p)
           stack))
    (loop while stack
          for item = (pop stack)
          for id = (first item)
          for indent = (second item)
          for just-branched-p = (third item)
          for show-connector-p = (fourth item)
          for last-p = (fifth item)
          for gutters = (sixth item)
          for virtual-root-child-p = (seventh item)
          for node-children = (copy-list
                               (gethash id children))
          for multiple-children-p =
            (> (length node-children) 1)
          do
          (setf
           (gethash id visuals)
           (list
            :indent indent
            :show-connector-p show-connector-p
            :last-p last-p
            :gutters gutters
            :virtual-root-child-p
            virtual-root-child-p))
          (let* ((child-indent
                   (cond
                     (multiple-children-p (1+ indent))
                     ((and just-branched-p
                           (plusp indent))
                      (1+ indent))
                     (t indent)))
                 (connector-displayed-p
                   (and show-connector-p
                        (not virtual-root-child-p)))
                 (display-indent
                   (if multiple-roots-p
                       (max 0 (1- indent))
                       indent))
                 (connector-position
                   (max 0 (1- display-indent)))
                 (child-gutters
                   (if connector-displayed-p
                       (append
                        gutters
                        (list
                         (cons connector-position
                               (not last-p))))
                       gutters)))
            (loop for child in (reverse node-children)
                  for index downfrom
                    (1- (length node-children))
                  do
                  (push
                   (list
                    child child-indent
                    multiple-children-p
                    multiple-children-p
                    (= index
                       (1- (length node-children)))
                    child-gutters nil)
                   stack))))
    (values visuals multiple-roots-p)))

(defun tree-selector-prefix
    (state id visual multiple-roots-p)
  (let* ((indent (getf visual :indent))
         (display-indent
           (if multiple-roots-p
               (max 0 (1- indent))
               indent))
         (show-connector-p
           (and (getf visual :show-connector-p)
                (not
                 (getf visual
                       :virtual-root-child-p))))
         (connector-position
           (and show-connector-p
                (1- display-indent)))
         (last-p (getf visual :last-p))
         (folded-p
           (gethash id
                    (tree-selector-state-folded state)))
         (foldable-p
           (tree-selector-foldable-p state id)))
    (with-output-to-string (output)
      (loop for level below display-indent
            for gutter =
              (assoc level (getf visual :gutters))
            do
            (cond
              (gutter
               (write-string
                (if (cdr gutter) "│  " "   ")
                output))
              ((and connector-position
                    (= level connector-position))
               (write-string
                (if last-p "└" "├") output)
               (write-string
                (cond
                  (folded-p "⊞")
                  (foldable-p "⊟")
                  (t "─"))
                output)
               (write-char #\Space output))
              (t
               (write-string "   " output)))))))

(defun tree-selector-normalize-display-text (text)
  (string-trim
   '(#\Space #\Tab #\Newline #\Return)
   (cl-ppcre:regex-replace-all
    "[\\n\\t]" (or text "") " ")))

(defun tree-selector-shorten-path (path)
  (let ((home (or (uiop:getenv "HOME") "")))
    (if
        (and
         (plusp (length home))
         (<= (length home) (length path))
         (string= home path :end2 (length home)))
        (concatenate
         'string "~" (subseq path (length home)))
        path)))

(defun tree-selector-default-path (arguments)
  "Return the tool path argument, defaulting empty/missing to \".\" like pi."
  (tree-selector-shorten-path
   (let ((path (tree-selector-tool-argument arguments "path")))
     (if (plusp (length path)) path "."))))

(defun tree-selector-tool-argument
    (arguments name &optional fallback)
  (labels ((resolved (key)
             (when (and arguments
                        (cadr-ai::json-present-p arguments key))
               (let ((value (cadr-ai::json-get arguments key)))
                 (unless (cadr-ai::json-null-p value)
                   (format nil "~A" value))))))
    (or (resolved name)
        (and fallback (resolved fallback))
        "")))

(defun tree-selector-format-tool-call
    (name arguments)
  (cond
    ((string= name "read")
     (let* ((path
              (tree-selector-shorten-path
               (or
                (tree-selector-tool-argument
                 arguments "path" "file_path")
                "")))
            (offset-present-p
              (cadr-ai::json-present-p
               arguments "offset"))
            (limit-present-p
              (cadr-ai::json-present-p
               arguments "limit"))
            (offset
              (and offset-present-p
                   (cadr-ai::json-get
                    arguments "offset")))
            (limit
              (and limit-present-p
                   (cadr-ai::json-get
                    arguments "limit"))))
       (format
        nil "[read: ~A~A]"
        path
        (if (or offset-present-p limit-present-p)
            (let* ((start (or offset 1))
                   (end
                     (and limit
                          (+ start limit -1))))
              (format nil ":~A~@[-~A~]"
                      start end))
            ""))))
    ((member name '("write" "edit")
             :test #'string=)
     (format
      nil "[~A: ~A]" name
      (tree-selector-shorten-path
       (or
        (tree-selector-tool-argument
         arguments "path" "file_path")
        ""))))
    ((string= name "bash")
     (let* ((raw
              (or
               (tree-selector-tool-argument
                arguments "command")
               ""))
            (normalized
              (tree-selector-normalize-display-text
               raw))
            (command
              (subseq normalized 0
                      (min 50
                           (length normalized)))))
       (format nil "[bash: ~A~A]"
               command
               (if (> (length raw) 50)
                   "..." ""))))
    ((string= name "grep")
     (format
      nil "[grep: /~A/ in ~A]"
      (or
       (tree-selector-tool-argument
        arguments "pattern")
       "")
      (tree-selector-default-path arguments)))
    ((string= name "find")
     (format
      nil "[find: ~A in ~A]"
      (or
       (tree-selector-tool-argument
        arguments "pattern")
       "")
      (tree-selector-default-path arguments)))
    ((string= name "ls")
     (format
      nil "[ls: ~A]"
      (tree-selector-default-path arguments)))
    (t
     (let* ((json
              (cadr-ai::stringify-json
               arguments))
            (short
              (subseq json 0
                      (min 40 (length json)))))
       (format nil "[~A: ~A~A]"
               name short
               (if (> (length json) 40)
                   "..." ""))))))

(defun tree-selector-entry-display-text
    (entry selected-p)
  (let* ((type (getf entry :type))
         (role (getf entry :role))
         (text
           (tree-selector-normalize-display-text
            (getf entry :text)))
         (result
           (case type
             (:message
              (case role
                (:user
                 (concatenate
                  'string
                  (cadr-tui:theme-foreground
                   :accent "user: ")
                  text))
                (:assistant
                 (concatenate
                  'string
                  (cadr-tui:theme-foreground
                   :success "assistant: ")
                  (cond
                    ((plusp (length text))
                     text)
                    ((eq (getf entry :stop-reason)
                         :aborted)
                     (cadr-tui:theme-foreground
                      :muted "(aborted)"))
                    ((getf entry :error-message)
                     (cadr-tui:theme-foreground
                      :error
                      (let ((error-text
                              (tree-selector-normalize-display-text
                               (getf entry :error-message))))
                        (subseq error-text 0
                                (min 80 (length error-text))))))
                    (t
                     (cadr-tui:theme-foreground
                      :muted "(no content)")))))
                ((:tool-result :toolresult)
                 (cadr-tui:theme-foreground
                  :muted
                  (let ((name
                          (getf entry
                                :tool-call-name))
                        (arguments
                          (getf entry
                                :tool-call-arguments)))
                    (if (and name arguments)
                        (tree-selector-format-tool-call
                         name arguments)
                        (format nil "[~A]"
                                (or name "tool"))))))
                (:bash-execution
                 (cadr-tui:theme-foreground
                  :dim
                  (format nil "[bash]: ~A" text)))
                (otherwise
                 (cadr-tui:theme-foreground
                  :dim
                  (format nil "[~(~A~)]" role)))))
             ((:custom-message :custom_message)
              (concatenate
               'string
               (cadr-tui:theme-foreground
                :custom-message-label
                (format nil "[~A]: "
                        (or (getf entry :custom-type)
                            "custom")))
               text))
             (:compaction
              (cadr-tui:theme-foreground
               :border-accent
               (format nil "[compaction: ~Dk tokens]"
                       (round
                        (or (getf entry :tokens-before)
                            0)
                        1000))))
             (:branch-summary
              (concatenate
               'string
               (cadr-tui:theme-foreground
                :warning "[branch summary]: ")
               text))
             (:model-change
              (cadr-tui:theme-foreground
               :dim
               (format nil "[model: ~A]"
                       (or (getf entry :model-id)
                           text))))
             (:thinking-level-change
              (cadr-tui:theme-foreground
               :dim
               (format nil "[thinking: ~A]"
                       (or (getf entry :thinking-level)
                           text))))
             (:custom
              (cadr-tui:theme-foreground
               :dim
               (format nil "[custom: ~A]"
                       (or (getf entry :custom-type)
                           "custom"))))
             (:label
              (cadr-tui:theme-foreground
               :dim
               (format nil "[label: ~A]"
                       (or (getf entry :entry-label)
                           "(cleared)"))))
             (:session-info
              (cadr-tui:theme-foreground
               :dim
               (format nil "[title: ~A]"
                       (or (getf entry :name)
                           "empty"))))
             (otherwise text))))
    (if selected-p
        (cadr-tui:theme-bold result)
        result)))

(defun tree-selector-horizontal-viewport
    (rows width)
  (let* ((gutter-width 2)
         (viewport-width
           (max 0 (- width gutter-width)))
         (maximum-body-width
           (loop for row in rows
                 maximize (getf row :body-width)
                   into maximum
                 finally (return (or maximum 0))))
         (maximum-scroll
           (max 0
                (- maximum-body-width
                   viewport-width)))
         (selected
           (find-if
            (lambda (row)
              (getf row :selected-p))
            rows))
         (scroll 0))
    (when (and selected
               (plusp maximum-scroll))
      (let ((minimum-content
              (min 20
                   (max 4
                        (floor viewport-width 3)))))
        (when
            (> (getf selected :anchor-column)
               (- viewport-width minimum-content))
          (let ((context
                  (min 12
                       (max 2
                            (floor viewport-width 4)))))
            (setf
             scroll
             (min maximum-scroll
                  (- (getf selected :anchor-column)
                     context)))))))
    (loop for row in rows
          collect
          (selector-fit-line
           (if (plusp scroll)
               (concatenate
                'string
                (getf row :gutter)
                (cadr-tui:slice-by-column
                 (getf row :body)
                 scroll viewport-width t)
                (format nil "~C[0m" #\Escape))
               (concatenate
                'string
                (getf row :gutter)
                (getf row :body)))
           width))))

(defun tree-selector-render-lines (state width)
  (let* ((by-id
           (tree-selector-entry-map
            (tree-selector-state-entries state)))
         (ids
           (tree-selector-state-visible-ids state))
         (selected
           (tree-selector-state-selected-id state))
         (selected-index
           (or (position selected ids :test #'equal)
               0))
         (active-path
           (tree-selector-active-path
            (tree-selector-state-entries state)
            (tree-selector-state-current-leaf-id
             state))))
    (multiple-value-bind
          (visible start end total)
        (centered-visible-slice
         ids selected-index
         (tree-selector-state-max-visible-lines
          state))
      (declare (ignore end))
      (multiple-value-bind
            (visuals multiple-roots-p)
          (tree-selector-visual-nodes state)
        (let ((rows
                (loop
                  for id in visible
                  for index from start
                  for entry = (gethash id by-id)
                  for visual = (gethash id visuals)
                  for selected-p = (= index selected-index)
                  for prefix =
                    (tree-selector-prefix
                     state id visual multiple-roots-p)
                  for root-fold-marker =
                    (and
                     (gethash
                      id
                      (tree-selector-state-folded state))
                     (not
                      (and
                       (getf visual :show-connector-p)
                       (not
                        (getf visual
                              :virtual-root-child-p))))
                     (cadr-tui:theme-foreground
                      :accent "⊞ "))
                  for path-marker =
                    (and
                     (gethash id active-path)
                     (cadr-tui:theme-foreground
                      :accent "• "))
                  for prefix-part =
                    (concatenate
                     'string
                     (cadr-tui:theme-foreground
                      :dim prefix)
                     (or root-fold-marker "")
                     (or path-marker ""))
                  for label = (getf entry :label)
                  for label-part =
                    (and label
                         (cadr-tui:theme-foreground
                          :warning
                          (format nil "[~A] " label)))
                  for timestamp-part =
                    (and
                     label
                     (tree-selector-state-show-label-timestamps-p
                      state)
                     (cadr-tui:theme-foreground
                      :muted
                      (format
                       nil "~A "
                       (tree-selector-format-label-timestamp
                        (getf entry :label-timestamp)))))
                  for cursor =
                    (if selected-p
                        (cadr-tui:theme-foreground
                         :accent "› ")
                        "  ")
                  for body =
                    (concatenate
                     'string prefix-part
                     (or label-part "")
                     (or timestamp-part "")
                     (tree-selector-entry-display-text
                      entry selected-p))
                  when selected-p
                    do
                    (setf
                     cursor
                     (cadr-tui:theme-background
                      :selected-bg cursor)
                     body
                     (cadr-tui:theme-background
                      :selected-bg body))
                  collect
                  (list
                   :gutter cursor
                   :body body
                   :anchor-column
                   (cadr-tui:visible-width prefix-part)
                   :body-width
                   (cadr-tui:visible-width body)
                   :selected-p selected-p))))
          (append
           (if rows
               (tree-selector-horizontal-viewport
                rows width)
               (list
                (selector-muted-line
                 "  No entries found" width)))
           (list
            (selector-muted-line
             (format
              nil "  (~D/~D)~A"
              (if selected
                  (1+ selected-index)
                  0)
              total
              (tree-selector-status-labels state))
             width))))))))

(defun tree-selector-help-key
    (state name)
  (or
   (first
    (cadr-tui:keybinding-keys
     (tree-selector-state-keybindings state)
     name))
   (cdr
    (assoc
     name
     '(("tui.select.up" . "up")
       ("tui.select.down" . "down")
       ("tui.editor.cursorLeft" . "left")
       ("tui.editor.cursorRight" . "right"))
     :test #'string=))))

(defun tree-selector-help-keys
    (state names)
  (let ((keys
          (remove
           nil
           (mapcar
            (lambda (name)
              (tree-selector-help-key state name))
            names))))
    (when keys
      (let* ((parts
               (mapcar
                (lambda (key)
                  (let ((separator
                          (position #\+ key
                                    :from-end t)))
                    (if separator
                        (cons
                         (subseq key 0 (1+ separator))
                         (subseq key (1+ separator)))
                        (cons "" key))))
                keys))
             (prefix (caar parts))
             (compact
               (if
                   (and
                    (string= prefix "ctrl+")
                    (every
                     (lambda (part)
                       (string= prefix (car part)))
                     parts))
                   (concatenate
                    'string prefix
                    (format nil "~{~A~^/~}"
                            (mapcar #'cdr parts)))
                   (format nil "~{~A~^/~}" keys))))
        (reduce
         (lambda (text replacement)
           (cl-ppcre:regex-replace-all
            (car replacement) text
            (cdr replacement)))
         '(("\\bup\\b" . "↑")
           ("\\bdown\\b" . "↓")
           ("\\bleft\\b" . "←")
           ("\\bright\\b" . "→"))
         :initial-value compact)))))

(defun tree-selector-help-lines (state width)
  (let* ((items
           (mapcar
            (lambda (entry)
              (let ((keys
                      (tree-selector-help-keys
                       state (first entry))))
                (if (getf (cddr entry) :label-first)
                    (format nil "~A ~A"
                            (second entry) keys)
                    (format nil "~A ~A"
                            keys (second entry)))))
            '((("tui.select.up" "tui.select.down")
               "move")
              (("tui.editor.cursorLeft"
                "tui.editor.cursorRight")
               "page")
              (("app.tree.foldOrUp"
                "app.tree.unfoldOrDown")
               "branch")
              (("app.message.copy") "copy")
              (("app.tree.editLabel") "label")
              (("app.tree.toggleLabelTimestamp")
               "label time")
              (("app.tree.filter.default"
                "app.tree.filter.noTools"
                "app.tree.filter.userOnly"
                "app.tree.filter.labeledOnly"
                "app.tree.filter.all")
               "filters" :label-first t)
              (("app.tree.filter.cycleForward"
                "app.tree.filter.cycleBackward")
               "cycle" :label-first t))))
         (lines nil)
         (current ""))
    (dolist (item items)
      (let* ((indented
               (concatenate 'string "  " item))
             (candidate
               (if (zerop (length current))
                   (if
                       (<= (cadr-tui:visible-width indented)
                           width)
                       indented item)
                   (concatenate
                    'string current " · " item))))
        (if
            (or (zerop (length current))
                (<= (cadr-tui:visible-width candidate)
                    width))
            (setf current candidate)
            (progn
              (setf lines
                    (nconc
                     lines
                     (cadr-tui:wrap-text
                      (string-right-trim " " current)
                      width)))
              (setf current
                    (if
                        (<=
                         (cadr-tui:visible-width indented)
                         width)
                        indented item))))))
    (when (plusp (length current))
      (setf lines
            (nconc
             lines
             (cadr-tui:wrap-text
              (string-right-trim " " current)
              width))))
    (mapcar
     (lambda (line)
       (selector-muted-line line width))
     lines)))

(defun render-tree-selector (state width)
  (let ((label-mode-p
          (eq :label
              (tree-selector-state-mode state))))
    (multiple-value-bind
          (label-lines label-row label-column)
        (if label-mode-p
            (selector-input-rendering
             (tree-selector-state-label-input state)
             width)
            (values nil nil nil))
      (render-selector-frame
       (make-selector-frame
        :sections
        (append
         (list
          :blank :border
          (list :title "  Session Tree" :plain)
          (list :lines (tree-selector-help-lines state width))
          (list :input (tree-selector-state-query state) :tree)
          :border :blank)
         (if label-mode-p
             (list
              (list
               :lines
               (list
                (selector-fit-line
                 (concatenate
                  'string "  "
                  (cadr-tui:theme-foreground
                   :muted "Label (empty to remove):"))
                 width)))
              (list
               :component
               (mapcar
                (lambda (line)
                  (selector-fit-line
                   (concatenate 'string "  " line)
                   width))
                label-lines)
               label-row (+ 2 label-column))
              (list
               :lines
               (list
                (selector-fit-line
                 (format
                  nil "  ~A  ~A"
                  (selector-keybinding-hint
                   (tree-selector-state-keybindings state)
                   "tui.select.confirm" "save")
                  (selector-keybinding-hint
                   (tree-selector-state-keybindings state)
                   "tui.select.cancel" "cancel"))
                 width))))
             (list
              (list :lines
                    (tree-selector-render-lines state width))))
         (list :blank :border)))
       width))))
