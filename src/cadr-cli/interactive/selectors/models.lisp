(in-package #:cadr-cli)

(defparameter +models-selector-keybinding-definitions+
  (append
   (copy-tree
    cadr-tui::+tui-keybinding-definitions+)
   '(("app.models.save" . ("ctrl+s"))
     ("app.models.enableAll" . ("ctrl+a"))
     ("app.models.clearAll" . ("ctrl+x"))
     ("app.models.toggleProvider" . ("ctrl+p"))
     ("app.models.reorderUp" . ("alt+up"))
     ("app.models.reorderDown" . ("alt+down"))
     ("app.models.clearSearchOrCancel"
      . ("ctrl+c")))))

(defun make-models-selector-keybindings
    (&optional user-bindings)
  (cadr-tui:make-keybindings-manager
   :definitions
   +models-selector-keybinding-definitions+
   :user-bindings user-bindings))

(defun qualified-model-id (model)
  (format nil "~(~A~)/~A"
          (cadr-ai:model-provider model)
          (cadr-ai:model-id model)))

(defun model-selector-search-text (model)
  (format nil "~(~A~) ~A ~(~A~) ~A~@[ ~A~]"
          (cadr-ai:model-provider model)
          (qualified-model-id model)
          (cadr-ai:model-provider model)
          (cadr-ai:model-id model)
          (let ((name
                  (cadr-ai::model-name model)))
            (and (stringp name)
                 (plusp (length name))
                 name))))

(defun scoped-model-selector-search-text
    (model)
  (format nil "~A ~(~A~) ~A ~(~A~) ~A~@[ ~A~]"
          (cadr-ai:model-id model)
          (cadr-ai:model-provider model)
          (qualified-model-id model)
          (cadr-ai:model-provider model)
          (cadr-ai:model-id model)
          (let ((name
                  (cadr-ai::model-name model)))
            (and (stringp name)
                 (plusp (length name))
                 name))))

(defun model-equal-p (left right)
  (and left right
       (cadr-ai::models-equal-p left right)))

(defun sort-model-selector-models
    (models current-model)
  (stable-sort
   (copy-list models)
   (lambda (left right)
     (cond
       ((model-equal-p left current-model)
        (not
         (model-equal-p right current-model)))
       ((model-equal-p right current-model)
        nil)
       (t
        (string<
         (provider-key
          (cadr-ai:model-provider left))
         (provider-key
          (cadr-ai:model-provider right))))))))

(defstruct (model-selector-state
            (:constructor
                %make-model-selector-state))
  (all-models nil :type list)
  (scoped-models nil :type list)
  current-model
  (scope :all)
  (query "" :type string)
  (selected 0 :type (integer 0 *))
  refresh-status-message
  keybindings)

(defun model-selector-active-models (state)
  (if (eq :scoped
          (model-selector-state-scope state))
      (model-selector-state-scoped-models state)
      (model-selector-state-all-models state)))

(defun model-selector-visible-models (state)
  (let ((models
          (model-selector-active-models state))
        (query
          (model-selector-state-query state)))
    (if (zerop (length query))
        (copy-list models)
        (selector-fuzzy-filter
         models query
         #'model-selector-search-text))))

(defun model-selector-clamp-selected (state)
  (let ((count
          (length
           (model-selector-visible-models state))))
    (setf
     (model-selector-state-selected state)
     (if (zerop count)
         0
         (min
          (model-selector-state-selected state)
          (1- count)))))
  state)

(defun model-selector-select-current (state)
  (let* ((models
           (model-selector-visible-models state))
         (index
           (position
            (model-selector-state-current-model state)
            models
            :test #'model-equal-p)))
    (setf
     (model-selector-state-selected state)
     (or index 0)))
  state)

(defun make-model-selector-state
    (&key all-models scoped-models
       current-model refresh-status-message
       keybindings)
  (let ((state
          (%make-model-selector-state
           :all-models
           (sort-model-selector-models
            all-models current-model)
           :scoped-models
           (copy-list scoped-models)
           :current-model current-model
           :refresh-status-message
           refresh-status-message
           :scope
           (if scoped-models :scoped :all)
           :keybindings
           (or keybindings
               (make-models-selector-keybindings)))))
    (model-selector-select-current state)))

(defun model-selector-selected-model (state)
  (nth
   (model-selector-state-selected state)
   (model-selector-visible-models state)))

(defun model-selector-set-query (state query)
  (setf
   (model-selector-state-query state)
   (or query ""))
  (if (plusp
       (length
        (model-selector-state-query state)))
      (setf
       (model-selector-state-selected state)
       0)
      (model-selector-clamp-selected state))
  state)

(defun model-selector-toggle-scope (state)
  (when (model-selector-state-scoped-models state)
    (setf
     (model-selector-state-scope state)
     (if
         (eq :all
             (model-selector-state-scope state))
         :scoped :all))
    (model-selector-select-current state)
    (when
        (plusp
         (length
          (model-selector-state-query state)))
      (setf
       (model-selector-state-selected state)
       0)))
  state)

(defun model-selector-move (state delta)
  (let ((count
          (length
           (model-selector-visible-models state))))
    (setf
     (model-selector-state-selected state)
     (selector-frame-move-index
      (model-selector-state-selected state)
      count delta)))
  state)

(defun model-selector-key-p
    (state data name)
  (selector-keybinding-matches-p
   (model-selector-state-keybindings state)
   data name))

(defun model-selector-handle-raw-input
    (state data)
  (cond
    ((model-selector-key-p
      state data "tui.input.tab")
     (model-selector-toggle-scope state)
     (values :changed nil t))
    ((model-selector-key-p
      state data "tui.select.up")
     (model-selector-move state -1)
     (values :changed nil t))
    ((model-selector-key-p
      state data "tui.select.down")
     (model-selector-move state 1)
     (values :changed nil t))
    ((model-selector-key-p
      state data "tui.select.pageUp")
     (model-selector-move state -10)
     (values :changed nil t))
    ((model-selector-key-p
      state data "tui.select.pageDown")
     (model-selector-move state 10)
     (values :changed nil t))
    ((model-selector-key-p
      state data "tui.select.confirm")
     (let ((model
             (model-selector-selected-model state)))
       (values
        (and model :select)
        model t)))
    ((model-selector-key-p
      state data "tui.select.cancel")
     (values :cancel nil t))
    (t
     (values nil nil nil))))

(defun model-selector-handle-event
    (state event)
  (case (cadr-tui:input-event-kind event)
    (:tab
     (model-selector-toggle-scope state)
     (values :changed nil))
    (:up
     (model-selector-move state -1)
     (values :changed nil))
    (:down
     (model-selector-move state 1)
     (values :changed nil))
    (:page-up
     (model-selector-move state -10)
     (values :changed nil))
    (:page-down
     (model-selector-move state 10)
     (values :changed nil))
    (:enter
     (let ((model
             (model-selector-selected-model state)))
       (values
        (and model :select)
        model)))
    ((:escape :interrupt)
     (values :cancel nil))
    (:backspace
     (model-selector-set-query
      state
      (selector-delete-query-character
       (model-selector-state-query state)))
     (values :changed nil))
    (:text
     (model-selector-set-query
      state
      (concatenate
       'string
       (model-selector-state-query state)
       (or
        (cadr-tui:input-event-text event)
        "")))
     (values :changed nil))
    (otherwise
     (values nil nil))))

(defun model-selector-visible-slice
    (state maximum)
  (multiple-value-bind (visible start end total)
      (selector-frame-visible-slice
       (model-selector-visible-models state)
       (model-selector-state-selected state)
       maximum)
    (declare (ignore end))
    (values visible start total)))

(defun render-model-selector (state width)
  (render-selector-frame
   (make-selector-frame
    :sections
    (list
     (list
      :lines
      (multiple-value-bind
            (models start total)
          (model-selector-visible-slice state 10)
        (let ((selected
                (model-selector-state-selected state))
              (current
                (model-selector-state-current-model state)))
          (append
       (append
        (list
         (selector-border-line width)
         ""
         (selector-fit-line
          (if
              (model-selector-state-scoped-models state)
              (let ((scoped-p
                      (eq :scoped
                          (model-selector-state-scope
                           state))))
                (concatenate
                 'string
                 (cadr-tui:theme-foreground
                  :muted "Scope: ")
                 (cadr-tui:theme-foreground
                  (if scoped-p :muted :accent)
                  "all")
                 (cadr-tui:theme-foreground
                  :muted " | ")
                 (cadr-tui:theme-foreground
                  (if scoped-p :accent :muted)
                  "scoped")))
              (cadr-tui:theme-foreground
               :warning
               "Only showing models from configured providers. Use /login to add providers."))
          width))
        (list
         ""
         (selector-fit-line
          (concatenate
           'string
           (cadr-tui:theme-foreground
            :muted "> ")
           (cadr-tui:theme-foreground
            :accent
            (model-selector-state-query state)))
          width)
         ""))
       (if models
           (loop
             for model in models
             for index from start
             for selected-p = (= index selected)
             for current-p =
               (model-equal-p model current)
             collect
             (selector-fit-line
              (concatenate
               'string
               (if selected-p
                   (cadr-tui:theme-foreground
                    :accent "→ ")
                   "  ")
               (if selected-p
                   (cadr-tui:theme-foreground
                    :accent
                    (cadr-ai:model-id model))
                   (cadr-ai:model-id model))
               " "
               (cadr-tui:theme-foreground
                :muted
                (format nil "[~(~A~)]"
                        (cadr-ai:model-provider
                         model)))
               (if current-p
                   (cadr-tui:theme-foreground
                    :success " ✓")
                   ""))
              width))
           (list
            (selector-muted-line
             "  No matching models" width)))
       (when (> total (length models))
         (list
          (selector-muted-line
           (format nil "  (~D/~D)"
                   (1+ selected) total)
           width)))
       (when
           (and models
                (model-selector-selected-model state))
         (list
          ""
          (selector-muted-line
           (format
            nil "  Model Name: ~A"
            (cadr-ai::model-name
             (model-selector-selected-model state)))
           width)))
       (when
           (model-selector-state-refresh-status-message
            state)
         (list
          ""
          (selector-fit-line
           (cadr-tui:theme-foreground
            :success
            (format
             nil "  ~A"
             (model-selector-state-refresh-status-message
              state)))
           width)))
           (list
            ""
            (selector-border-line width))))))))
   width))
(defstruct (scoped-models-selector-state
            (:constructor
                %make-scoped-models-selector-state))
  (all-models nil :type list)
  (all-ids nil :type list)
  (enabled-ids :all)
  (query "" :type string)
  (selected 0 :type (integer 0 *))
  (dirty-p nil :type boolean)
  change-callback
  persist-callback
  cancel-callback
  keybindings)

(defun scoped-models-copy-enabled (enabled)
  (if (eq enabled :all)
      :all
      (copy-list enabled)))

(defun scoped-models-model-by-id
    (state id)
  (find
   id
   (scoped-models-selector-state-all-models state)
   :key #'qualified-model-id
   :test #'string=))

(defun scoped-model-id-enabled-p
    (state id)
  (or
   (eq :all
       (scoped-models-selector-state-enabled-ids
        state))
   (member
    id
    (scoped-models-selector-state-enabled-ids
     state)
    :test #'string=)))

(defun scoped-models-sorted-ids (state)
  (let ((enabled
          (scoped-models-selector-state-enabled-ids
           state))
        (all
          (scoped-models-selector-state-all-ids
           state)))
    (if (eq enabled :all)
        (copy-list all)
        (append
         (copy-list enabled)
         (remove-if
          (lambda (id)
            (member id enabled :test #'string=))
          all)))))

(defun scoped-models-selector-items (state)
  (loop
    for id in (scoped-models-sorted-ids state)
    collect
    (list
     :id id
     :model
     (scoped-models-model-by-id state id)
     :enabled-p
     (not
      (null
       (scoped-model-id-enabled-p state id))))))

(defun scoped-model-item-search-text (item)
  (let ((model (getf item :model)))
    (if model
        (scoped-model-selector-search-text
         model)
        (getf item :id))))

(defun scoped-models-selector-visible-items
    (state)
  (let ((items
          (scoped-models-selector-items state))
        (query
          (scoped-models-selector-state-query
           state)))
    (if (zerop (length query))
        items
        (selector-fuzzy-filter
         items query
         #'scoped-model-item-search-text))))

(defun scoped-models-selector-clamp-selected
    (state)
  (let ((count
          (length
           (scoped-models-selector-visible-items
            state))))
    (setf
     (scoped-models-selector-state-selected state)
     (if (zerop count)
         0
         (min
          (scoped-models-selector-state-selected
           state)
          (1- count)))))
  state)

(defun make-scoped-models-selector-state
    (&key all-models
       (enabled-ids :all)
       change-callback
       persist-callback
       cancel-callback
       keybindings)
  (%make-scoped-models-selector-state
   :all-models (copy-list all-models)
   :all-ids
   (mapcar #'qualified-model-id all-models)
   :enabled-ids
   (scoped-models-copy-enabled enabled-ids)
   :change-callback change-callback
   :persist-callback persist-callback
   :cancel-callback cancel-callback
   :keybindings
   (or keybindings
       (make-models-selector-keybindings))))

(defun scoped-models-selector-selected-item
    (state)
  (nth
   (scoped-models-selector-state-selected state)
   (scoped-models-selector-visible-items state)))

(defun scoped-models-selector-select-id
    (state id)
  (let ((position
          (position
           id
           (scoped-models-selector-visible-items state)
           :key
           (lambda (item)
             (getf item :id))
           :test #'string=)))
    (when position
      (setf
       (scoped-models-selector-state-selected state)
       position)))
  state)

(defun scoped-models-selector-notify-change
    (state)
  (when
      (scoped-models-selector-state-change-callback
       state)
    (funcall
     (scoped-models-selector-state-change-callback
      state)
     (scoped-models-copy-enabled
      (scoped-models-selector-state-enabled-ids
       state))))
  state)

(defun scoped-models-selector-mark-changed
    (state)
  (setf
   (scoped-models-selector-state-dirty-p state)
   t)
  (scoped-models-selector-clamp-selected state)
  (scoped-models-selector-notify-change state))

(defun scoped-models-toggle-id (enabled id)
  (cond
    ((eq enabled :all)
     (list id))
    ((member id enabled :test #'string=)
     (remove id enabled :test #'string=))
    (t
     (append enabled (list id)))))

(defun all-known-model-ids-enabled-p
    (enabled all-ids)
  (and
   (listp enabled)
   (= (length enabled)
      (length all-ids))
   (every
    (lambda (id)
      (member id all-ids :test #'string=))
    enabled)))

(defun scoped-models-enable-ids
    (enabled all-ids targets)
  (when (eq enabled :all)
    (return-from scoped-models-enable-ids
      :all))
  (let ((result (copy-list enabled)))
    (dolist (id targets)
      (unless (member id result :test #'string=)
        (setf result
              (append result (list id)))))
    (if (all-known-model-ids-enabled-p
         result all-ids)
        :all
        result)))

(defun scoped-models-clear-ids
    (enabled all-ids targets)
  (if (eq enabled :all)
      (remove-if
       (lambda (id)
         (member id targets :test #'string=))
       all-ids)
      (remove-if
       (lambda (id)
         (member id targets :test #'string=))
       enabled)))

(defun scoped-models-selector-toggle-selected
    (state)
  (let ((item
          (scoped-models-selector-selected-item
           state)))
    (when item
      (setf
       (scoped-models-selector-state-enabled-ids
        state)
       (scoped-models-toggle-id
        (scoped-models-selector-state-enabled-ids
         state)
        (getf item :id)))
      (scoped-models-selector-mark-changed
       state)))
  state)

(defun scoped-models-selector-target-ids
    (state)
  (if
      (plusp
       (length
        (scoped-models-selector-state-query
         state)))
      (mapcar
       (lambda (item)
         (getf item :id))
       (scoped-models-selector-visible-items
        state))
      (copy-list
       (scoped-models-selector-state-all-ids
        state))))

(defun scoped-models-selector-enable-all
    (state)
  (setf
   (scoped-models-selector-state-enabled-ids state)
   (scoped-models-enable-ids
    (scoped-models-selector-state-enabled-ids
     state)
    (scoped-models-selector-state-all-ids state)
    (scoped-models-selector-target-ids state)))
  (scoped-models-selector-mark-changed state))

(defun scoped-models-selector-clear-all
    (state)
  (setf
   (scoped-models-selector-state-enabled-ids state)
   (scoped-models-clear-ids
    (scoped-models-selector-state-enabled-ids
     state)
    (scoped-models-selector-state-all-ids state)
    (scoped-models-selector-target-ids state)))
  (scoped-models-selector-mark-changed state))

(defun scoped-models-selector-toggle-provider
    (state)
  (let* ((item
           (scoped-models-selector-selected-item
            state))
         (model (and item (getf item :model))))
    (when model
      (let* ((provider
               (cadr-ai:model-provider model))
             (ids
               (loop
                 for candidate in
                 (scoped-models-selector-state-all-models
                  state)
                 when
                   (eq provider
                       (cadr-ai:model-provider
                        candidate))
                   collect
                   (qualified-model-id
                    candidate)))
             (enabled
               (scoped-models-selector-state-enabled-ids
                state))
             (all-enabled-p
               (every
                (lambda (id)
                  (or
                   (eq enabled :all)
                   (member id enabled
                           :test #'string=)))
                ids)))
        (setf
         (scoped-models-selector-state-enabled-ids
          state)
         (if all-enabled-p
             (scoped-models-clear-ids
              enabled
              (scoped-models-selector-state-all-ids
               state)
              ids)
             (scoped-models-enable-ids
              enabled
              (scoped-models-selector-state-all-ids
               state)
              ids)))
        (scoped-models-selector-mark-changed
         state))))
  state)

(defun move-list-item (items index new-index)
  (if
      (or (< new-index 0)
          (>= new-index (length items)))
      (copy-list items)
      (let ((result (copy-list items)))
        (rotatef
         (nth index result)
         (nth new-index result))
        result)))

(defun scoped-models-selector-reorder
    (state delta)
  (let* ((enabled
           (scoped-models-selector-state-enabled-ids
            state))
         (item
           (scoped-models-selector-selected-item
            state))
         (id (and item (getf item :id))))
    (when
        (and
         (listp enabled)
         id
         (member id enabled :test #'string=))
      (let* ((index
               (position id enabled
                         :test #'string=))
             (new-index (+ index delta)))
        (when
            (and (>= new-index 0)
                 (< new-index (length enabled)))
          (setf
           (scoped-models-selector-state-enabled-ids
            state)
           (move-list-item
            enabled index new-index))
          (scoped-models-selector-mark-changed
           state)
          (scoped-models-selector-select-id
           state id)))))
  state)

(defun scoped-models-selector-persist (state)
  (when
      (scoped-models-selector-state-persist-callback
       state)
    (funcall
     (scoped-models-selector-state-persist-callback
      state)
     (scoped-models-copy-enabled
      (scoped-models-selector-state-enabled-ids
       state))))
  (setf
   (scoped-models-selector-state-dirty-p state)
   nil)
  state)

(defun scoped-models-selector-key-p
    (state data name)
  (selector-keybinding-matches-p
   (scoped-models-selector-state-keybindings state)
   data name))

(defun scoped-models-selector-handle-raw-input
    (state data)
  (labels
      ((changed (function)
         (funcall function state)
         (values :changed nil t)))
    (cond
      ((scoped-models-selector-key-p
        state data "app.models.reorderUp")
       (changed
        (lambda (state)
          (scoped-models-selector-reorder
           state -1))))
      ((scoped-models-selector-key-p
        state data "app.models.reorderDown")
       (changed
        (lambda (state)
          (scoped-models-selector-reorder
           state 1))))
      ((scoped-models-selector-key-p
        state data "app.models.enableAll")
       (changed
        #'scoped-models-selector-enable-all))
      ((scoped-models-selector-key-p
        state data "app.models.clearAll")
       (changed
        #'scoped-models-selector-clear-all))
      ((scoped-models-selector-key-p
        state data "app.models.toggleProvider")
       (changed
        #'scoped-models-selector-toggle-provider))
      ((scoped-models-selector-key-p
        state data "app.models.save")
       (changed
        #'scoped-models-selector-persist))
      ((scoped-models-selector-key-p
        state data
        "app.models.clearSearchOrCancel")
       (if
           (plusp
            (length
             (scoped-models-selector-state-query
              state)))
           (progn
             (setf
              (scoped-models-selector-state-query
               state)
              "")
             (scoped-models-selector-clamp-selected
              state)
             (values :changed nil t))
           (values :cancel nil t)))
      ((scoped-models-selector-key-p
        state data "tui.select.up")
       (scoped-models-selector-move state -1)
       (values :changed nil t))
      ((scoped-models-selector-key-p
        state data "tui.select.down")
       (scoped-models-selector-move state 1)
       (values :changed nil t))
      ((scoped-models-selector-key-p
        state data "tui.select.pageUp")
       (scoped-models-selector-move state -8)
       (values :changed nil t))
      ((scoped-models-selector-key-p
        state data "tui.select.pageDown")
       (scoped-models-selector-move state 8)
       (values :changed nil t))
      ((scoped-models-selector-key-p
        state data "tui.select.confirm")
       (changed
        #'scoped-models-selector-toggle-selected))
      ((scoped-models-selector-key-p
        state data "tui.select.cancel")
       (values :cancel nil t))
      (t
       (values nil nil nil)))))

(defun scoped-models-selector-move
    (state delta)
  (let ((count
          (length
           (scoped-models-selector-visible-items
            state))))
    (setf
     (scoped-models-selector-state-selected state)
     (selector-frame-move-index
      (scoped-models-selector-state-selected state)
      count delta)))
  state)

(defun scoped-models-selector-set-query
    (state query)
  (setf
   (scoped-models-selector-state-query state)
   (or query ""))
  (scoped-models-selector-clamp-selected state))

(defun scoped-models-selector-cancel (state)
  (when
      (scoped-models-selector-state-cancel-callback
       state)
    (funcall
     (scoped-models-selector-state-cancel-callback
      state)))
  state)

(defun scoped-models-selector-handle-event
    (state event)
  (case (cadr-tui:input-event-kind event)
    (:up
     (scoped-models-selector-move state -1)
     (values :changed nil))
    (:down
     (scoped-models-selector-move state 1)
     (values :changed nil))
    (:page-up
     (scoped-models-selector-move state -8)
     (values :changed nil))
    (:page-down
     (scoped-models-selector-move state 8)
     (values :changed nil))
    (:enter
     (scoped-models-selector-toggle-selected state)
     (values :changed nil))
    (:escape
     (scoped-models-selector-cancel state)
     (values :cancel nil))
    (:interrupt
     (if
         (plusp
          (length
           (scoped-models-selector-state-query
            state)))
         (progn
           (scoped-models-selector-set-query
            state "")
           (values :changed nil))
         (progn
           (scoped-models-selector-cancel state)
           (values :cancel nil))))
    (:backspace
     (scoped-models-selector-set-query
      state
      (selector-delete-query-character
       (scoped-models-selector-state-query
        state)))
     (values :changed nil))
    (:text
     (scoped-models-selector-set-query
      state
      (concatenate
       'string
       (scoped-models-selector-state-query
        state)
       (or
        (cadr-tui:input-event-text event)
        "")))
     (values :changed nil))
    (otherwise
     (values nil nil))))

(defun session-scoped-models
    (all-models enabled-ids)
  (when (eq enabled-ids :all)
    (return-from session-scoped-models nil))
  (let* ((all-ids
           (mapcar #'qualified-model-id all-models))
         (available
           (loop
             for id in enabled-ids
             for model =
               (find id all-models
                     :key #'qualified-model-id
                     :test #'string=)
             when model
               collect model))
         (all-enabled-p
           (every
            (lambda (id)
              (member id enabled-ids
                      :test #'string=))
            all-ids)))
    (if
        (and available
             (not all-enabled-p))
        available
        nil)))

(defun scoped-models-selector-counts (state)
  (let ((enabled
          (scoped-models-selector-state-enabled-ids
           state)))
    (if (eq enabled :all)
        (values
         (length
          (scoped-models-selector-state-all-ids
           state))
         0 t)
        (values
         (count-if
          (lambda (id)
            (member
             id
             (scoped-models-selector-state-all-ids
              state)
             :test #'string=))
          enabled)
         (count-if
          (lambda (id)
            (not
             (member
              id
              (scoped-models-selector-state-all-ids
               state)
              :test #'string=)))
          enabled)
         nil))))

(defun scoped-models-binding-label
    (state name)
  (or
   (first
    (cadr-tui:keybinding-keys
     (scoped-models-selector-state-keybindings
      state)
     name))
   name))

(defun render-scoped-models-selector
    (state width)
  (render-selector-frame
   (make-selector-frame
    :sections
    (list
     (list
      :lines
      (let* ((items
               (scoped-models-selector-visible-items
                state))
             (selected
               (scoped-models-selector-state-selected
                state)))
        (multiple-value-bind (visible start end total)
            (selector-frame-visible-slice items selected 8)
          (declare (ignore total))
          (multiple-value-bind
                (enabled unavailable all-p)
              (scoped-models-selector-counts state)
            (append
       (list
        (selector-border-line width)
        ""
        (selector-title-line
         "Model Configuration" width)
        (selector-muted-line
         (format
          nil "Session-only. ~A to save to settings."
          (scoped-models-binding-label
           state "app.models.save"))
         width)
        ""
        (selector-fit-line
         (concatenate
          'string
          (cadr-tui:theme-foreground
           :muted "> ")
          (cadr-tui:theme-foreground
           :accent
           (scoped-models-selector-state-query
            state)))
         width)
        "")
       (if visible
           (loop
             for item in visible
             for index from start
             for model = (getf item :model)
             for selected-p = (= index selected)
             for identifier =
               (if model
                   (cadr-ai:model-id model)
                   (getf item :id))
             for provider =
               (if model
                   (provider-key
                    (cadr-ai:model-provider model))
                   "unavailable")
             for status =
               (cond
                 ((null model)
                  (cadr-tui:theme-foreground
                   :dim " ✗"))
                 (all-p "")
                 ((getf item :enabled-p)
                  (cadr-tui:theme-foreground
                   :success " ✓"))
                 (t
                  (cadr-tui:theme-foreground
                   :dim " ✗")))
             for line =
               (concatenate
                'string
                (if selected-p
                    (cadr-tui:theme-foreground
                     :accent "→ ")
                    "  ")
                (if selected-p
                    (cadr-tui:theme-foreground
                     :accent identifier)
                    identifier)
                (cadr-tui:theme-foreground
                 :muted
                 (format nil " [~A]" provider))
                status)
             collect
               (selector-fit-line line width))
           (list
            (selector-muted-line
             "  No matching models" width)))
       (when
           (or (> start 0)
               (< end (length items)))
         (list
          (selector-muted-line
           (format nil "  (~D/~D)"
                   (1+ selected)
                   (length items))
           width)))
       (when visible
         (let* ((item
                  (scoped-models-selector-selected-item
                   state))
                (model
                  (and item
                       (getf item :model))))
           (list
            ""
            (selector-muted-line
             (format
              nil "  ~A"
              (if model
                  (format nil "Model Name: ~A"
                          (cadr-ai::model-name
                           model))
                  "Model unavailable"))
             width))))
       (list
        ""
        (selector-fit-line
         (concatenate
          'string
          (cadr-tui:theme-foreground
           :dim
           (format
            nil
            "~A toggle · ~A all · ~A clear · ~A provider · ~A/~A reorder · ~A save · ~A"
            (scoped-models-binding-label
             state "tui.select.confirm")
            (scoped-models-binding-label
             state "app.models.enableAll")
            (scoped-models-binding-label
             state "app.models.clearAll")
            (scoped-models-binding-label
             state "app.models.toggleProvider")
            (scoped-models-binding-label
             state "app.models.reorderUp")
            (scoped-models-binding-label
             state "app.models.reorderDown")
            (scoped-models-binding-label
             state "app.models.save")
            (if all-p
                "all enabled"
                (format
                 nil "~D/~D enabled~@[ · ~D unavailable~]"
                 enabled
                 (length
                  (scoped-models-selector-state-all-ids
                   state))
                 (and (plusp unavailable)
                      unavailable)))))
          (if
              (scoped-models-selector-state-dirty-p
               state)
              (cadr-tui:theme-foreground
               :warning " (unsaved)")
              ""))
         width)
             (selector-border-line width)))))))))
   width))
