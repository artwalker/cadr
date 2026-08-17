(in-package #:cadr-tui)

(defstruct setting-item
  (id "" :type string)
  (label "" :type string)
  description
  (current-value "" :type string)
  values
  submenu)

(defclass settings-list-component (component)
  ((items
    :initarg :items
    :accessor settings-list-component-items)
   (filtered-items
    :initarg :filtered-items
    :accessor settings-list-component-filtered-items)
   (selected-index
    :initform 0
    :accessor settings-list-component-selected-index)
   (max-visible
    :initarg :max-visible
    :accessor settings-list-component-max-visible)
   (on-change
    :initarg :on-change
    :accessor settings-list-component-on-change)
   (on-cancel
    :initarg :on-cancel
    :accessor settings-list-component-on-cancel)
   (search-enabled-p
    :initarg :search-enabled-p
    :accessor settings-list-component-search-enabled-p)
   (search-input
    :initarg :search-input
    :accessor settings-list-component-search-input)
   (label-function
    :initarg :label-function
    :accessor settings-list-component-label-function)
   (value-function
    :initarg :value-function
    :accessor settings-list-component-value-function)
   (description-function
    :initarg :description-function
    :accessor settings-list-component-description-function)
   (cursor
    :initarg :cursor
    :accessor settings-list-component-cursor)
   (hint-function
    :initarg :hint-function
    :accessor settings-list-component-hint-function)
   (submenu-component
    :initform nil
    :accessor settings-list-component-submenu-component)
   (submenu-item-index
    :initform nil
    :accessor settings-list-component-submenu-item-index)))

(defun default-settings-label (text selected-p)
  (if selected-p
      (theme-foreground :accent text)
      text))

(defun default-settings-value (text selected-p)
  (theme-foreground
   (if selected-p :accent :muted) text))

(defun make-settings-list-component
    (items max-visible
     &key on-change on-cancel search-enabled-p
       (label-function #'default-settings-label)
       (value-function #'default-settings-value)
       (description-function
         (lambda (text)
           (theme-foreground :muted text)))
       (cursor "→ ")
       (hint-function
         (lambda (text)
           (theme-foreground :dim text))))
  (make-instance
   'settings-list-component
   :items (copy-list items)
   :filtered-items (copy-list items)
   :max-visible (max 1 max-visible)
   :on-change (or on-change
                  (lambda (id value)
                    (declare (ignore id value))))
   :on-cancel (or on-cancel (lambda ()))
   :search-enabled-p (not (null search-enabled-p))
   :search-input
   (and search-enabled-p
        (make-single-line-input :prompt "> "))
   :label-function label-function
   :value-function value-function
   :description-function description-function
   :cursor cursor
   :hint-function hint-function))

(defun settings-list-component-update-value
    (component id new-value)
  (let ((item
          (find id
                (settings-list-component-items component)
                :test #'string=
                :key #'setting-item-id)))
    (when item
      (setf (setting-item-current-value item)
            new-value)))
  component)

(defun settings-list-display-items (component)
  (if (settings-list-component-search-enabled-p component)
      (settings-list-component-filtered-items component)
      (settings-list-component-items component)))

(defun settings-list-apply-filter (component)
  (let ((query
          (single-line-input-value
           (settings-list-component-search-input component))))
    (setf
     (settings-list-component-filtered-items component)
     (fuzzy-filter
      (settings-list-component-items component)
      query #'setting-item-label)
     (settings-list-component-selected-index component) 0))
  component)

(defun settings-list-add-hint-line
    (component lines width)
  (append
   lines
   (list
    ""
    (truncate-to-width
     (funcall
      (settings-list-component-hint-function component)
      (if (settings-list-component-search-enabled-p component)
          "  Type to search · Enter/Space to change · Esc to cancel"
          "  Enter/Space to change · Esc to cancel"))
     width))))

(defmethod component-render
    ((component settings-list-component)
     width &key focused-p)
  (declare (ignore focused-p))
  (when (settings-list-component-submenu-component component)
    (return-from component-render
      (component-render
       (settings-list-component-submenu-component component)
       width)))
  (let ((lines nil))
    (when
        (and (settings-list-component-search-enabled-p component)
             (settings-list-component-search-input component))
      (setf lines
            (append
             lines
             (nth-value
              0
              (render-single-line-input
               (settings-list-component-search-input component)
               width))
             (list ""))))
    (let* ((all-items
             (settings-list-component-items component))
           (items (settings-list-display-items component))
           (count (length items)))
      (when (null all-items)
        (return-from component-render
          (settings-list-add-hint-line
           component
           (list
            (funcall
             (settings-list-component-hint-function component)
             "  No settings available"))
           width)))
      (when (zerop count)
        (return-from component-render
          (settings-list-add-hint-line
           component
           (append
            lines
            (list
             (truncate-to-width
              (funcall
               (settings-list-component-hint-function component)
               "  No matching settings")
              width)))
           width)))
      (let* ((selected
               (min
                (settings-list-component-selected-index component)
                (1- count)))
             (maximum-visible
               (settings-list-component-max-visible component))
             (start
               (max
                0
                (min
                 (- selected (floor maximum-visible 2))
                 (- count maximum-visible))))
             (end (min count (+ start maximum-visible)))
             (maximum-label-width
               (min
                30
                (loop for item in all-items
                      maximize
                      (visible-width
                       (setting-item-label item)))))
             (rendered
               (loop for index from start below end
                     for item = (nth index items)
                     for selected-p = (= index selected)
                     for prefix =
                       (if selected-p
                           (settings-list-component-cursor component)
                           "  ")
                     for label = (setting-item-label item)
                     for label-padding =
                       (make-string
                        (max
                         0
                         (- maximum-label-width
                            (visible-width label)))
                        :initial-element #\Space)
                     for label-text =
                       (funcall
                        (settings-list-component-label-function
                         component)
                        (concatenate 'string label label-padding)
                        selected-p)
                     for used =
                       (+ (visible-width prefix)
                          maximum-label-width 2)
                     for value-width =
                       (max 1 (- width used 2))
                     for value-text =
                       (funcall
                        (settings-list-component-value-function
                         component)
                        (truncate-to-width
                         (setting-item-current-value item)
                         value-width "")
                        selected-p)
                     collect
                     (truncate-to-width
                      (concatenate
                       'string prefix label-text "  " value-text)
                      width))))
        (setf lines (append lines rendered))
        (when (or (plusp start) (< end count))
          (setf lines
                (append
                 lines
                 (list
                  (funcall
                   (settings-list-component-hint-function component)
                   (truncate-to-width
                    (format nil "  (~D/~D)" (1+ selected) count)
                    (max 1 (- width 2)) ""))))))
        (let ((selected-item (nth selected items)))
          (when (and selected-item
                     (setting-item-description selected-item))
            (setf lines (append lines (list "")))
            (dolist
                (line
                 (wrap-text
                  (setting-item-description selected-item)
                  (max 1 (- width 4))))
              (setf lines
                    (append
                     lines
                     (list
                      (funcall
                       (settings-list-component-description-function
                        component)
                       (concatenate 'string "  " line))))))))
        (settings-list-add-hint-line
         component lines width)))))

(defun settings-list-close-submenu (component)
  (setf
   (settings-list-component-submenu-component component) nil)
  (when (settings-list-component-submenu-item-index component)
    (setf
     (settings-list-component-selected-index component)
     (settings-list-component-submenu-item-index component)
     (settings-list-component-submenu-item-index component)
     nil))
  component)

(defun settings-list-activate-item (component)
  (let* ((items (settings-list-display-items component))
         (index
           (settings-list-component-selected-index component))
         (item (nth index items)))
    (when item
      (cond
        ((setting-item-submenu item)
         (setf
          (settings-list-component-submenu-item-index component)
          index
          (settings-list-component-submenu-component component)
          (funcall
           (setting-item-submenu item)
           (setting-item-current-value item)
           (lambda (&optional (selected-value nil supplied-p))
             (when supplied-p
               (setf
                (setting-item-current-value item)
                selected-value)
               (funcall
                (settings-list-component-on-change component)
                (setting-item-id item) selected-value))
             (settings-list-close-submenu component)))))
        ((setting-item-values item)
         (let* ((values (setting-item-values item))
                (current
                  (or
                   (position
                    (setting-item-current-value item)
                    values :test #'string=)
                   -1))
                (new-value
                  (nth (mod (1+ current) (length values))
                       values)))
           (setf (setting-item-current-value item)
                 new-value)
           (funcall
            (settings-list-component-on-change component)
            (setting-item-id item) new-value))))))
  component)

(defmethod component-handle-event
    ((component settings-list-component) event)
  (when (settings-list-component-submenu-component component)
    (return-from component-handle-event
      (component-handle-event
       (settings-list-component-submenu-component component)
       event)))
  (let* ((kind (input-event-kind event))
         (items (settings-list-display-items component))
         (count (length items)))
    (case kind
      (:up
       (when (plusp count)
         (setf
          (settings-list-component-selected-index component)
          (mod
           (1-
            (settings-list-component-selected-index component))
           count))))
      (:down
       (when (plusp count)
         (setf
          (settings-list-component-selected-index component)
          (mod
           (1+
            (settings-list-component-selected-index component))
           count))))
      (:enter (settings-list-activate-item component))
      (:escape
       (funcall
        (settings-list-component-on-cancel component)))
      (:text
       ;; Baseline settings-list.ts:187: space confirms only when
       ;; search is off or the query is empty. A nonempty query
       ;; treats space as a search character; paste keeps spaces.
       ;; The old path stripped #\Space, so "Apple Terminal"
       ;; became "AppleTerminal".
       (let ((text (or (input-event-text event) "")))
         (if (and (string= text " ")
                  (or (not (settings-list-component-search-enabled-p
                            component))
                      (let ((input
                              (settings-list-component-search-input
                               component)))
                        (and input
                             (zerop
                              (length
                               (single-line-input-value input)))))))
             (settings-list-activate-item component)
             (when
                 (and
                  (settings-list-component-search-enabled-p component)
                  (settings-list-component-search-input component)
                  (plusp (length text)))
               (single-line-input-handle-event
                (settings-list-component-search-input component)
                event)
               (settings-list-apply-filter component)))))
      ((:backspace :delete)
       (when
           (and
            (settings-list-component-search-enabled-p component)
            (settings-list-component-search-input component))
         (single-line-input-handle-event
          (settings-list-component-search-input component)
          event)
         (settings-list-apply-filter component))))
    (values nil nil)))

(defmethod component-invalidate
    ((component settings-list-component))
  (when (settings-list-component-submenu-component component)
    (component-invalidate
     (settings-list-component-submenu-component component)))
  component)

(defgeneric editor-component-text (editor))
(defgeneric editor-component-set-text (editor text))

(defmethod editor-component-text ((editor multiline-editor))
  (editor-text editor))

(defmethod editor-component-set-text
    ((editor multiline-editor) text)
  (editor-set-text editor text))

(defmethod component-render
    ((editor multiline-editor) width &key (focused-p t))
  (nth-value 0
             (render-editor
              editor width :focused-p focused-p)))

(defmethod component-handle-event
    ((editor multiline-editor) event)
  (editor-handle-event editor event))

(defmethod component-focusable-p
    ((editor multiline-editor))
  (declare (ignore editor))
  t)

(defmethod component-invalidate
    ((editor multiline-editor))
  editor)

(defmethod component-dispose
    ((editor multiline-editor))
  editor)

(defmethod editor-component-text ((input single-line-input))
  (single-line-input-value input))

(defmethod editor-component-set-text
    ((input single-line-input) text)
  (single-line-input-set-value input text))

(defmethod component-render
    ((input single-line-input) width &key focused-p)
  (declare (ignore focused-p))
  (nth-value 0 (render-single-line-input input width)))

(defmethod component-handle-event
    ((input single-line-input) event)
  (single-line-input-handle-event input event))

(defmethod component-focusable-p
    ((input single-line-input))
  (declare (ignore input))
  t)

(defmethod component-invalidate
    ((input single-line-input))
  input)


(defmethod component-dispose
    ((input single-line-input))
  input)
