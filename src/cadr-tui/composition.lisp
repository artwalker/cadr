(in-package #:cadr-tui)

(defparameter +cursor-marker+
  (format nil "~C_pi:c~C" #\Escape (code-char 7)))

(defclass component () ())

(defclass focusable-component (component)
  ((focused-p
    :initarg :focused-p
    :initform nil
    :accessor component-focused-p)))

(defgeneric component-render
    (component width &key focused-p))

(defgeneric component-handle-event (component event))
(defgeneric component-invalidate (component))
(defgeneric component-dispose (component))
(defgeneric component-wants-key-release-p (component))
(defgeneric component-focusable-p (component))

(defmethod component-render
    ((component component) width &key focused-p)
  (declare (ignore component width focused-p))
  nil)

(defmethod component-handle-event
    ((component component) event)
  (declare (ignore component event))
  (values nil nil))

(defmethod component-invalidate ((component component))
  component)

(defmethod component-dispose ((component component))
  component)

(defmethod component-wants-key-release-p
    ((component component))
  (declare (ignore component))
  nil)

(defmethod component-focusable-p ((component component))
  (typep component 'focusable-component))

(defmethod component-focused-p ((component component))
  (declare (ignore component))
  nil)

(defmethod (setf component-focused-p)
    (value (component component))
  (declare (ignore component))
  (not (null value)))

(defclass component-container (component)
  ((children
    :initarg :children
    :initform nil
    :accessor component-children)))

(defgeneric component-add-child (container child))
(defgeneric component-remove-child (container child))
(defgeneric component-clear (container))

(defun make-component-container (&rest children)
  (make-instance
   'component-container :children (copy-list children)))

(defmethod component-add-child
    ((container component-container) child)
  (setf
   (component-children container)
   (nconc (component-children container)
          (list child)))
  container)

(defmethod component-remove-child
    ((container component-container) child)
  (setf
   (component-children container)
   (remove child (component-children container)
           :test #'eq :count 1))
  container)

(defmethod component-clear
    ((container component-container))
  (setf (component-children container) nil)
  container)

(defmethod component-render
    ((container component-container) width &key focused-p)
  (declare (ignore focused-p))
  (loop for child in (component-children container)
        nconc
        (component-render
         child width
         :focused-p (component-focused-p child))))

(defmethod component-invalidate
    ((container component-container))
  (dolist (child (component-children container))
    (component-invalidate child))
  container)

(defmethod component-dispose
    ((container component-container))
  (dolist (child (component-children container))
    (component-dispose child))
  container)

(defun pad-component-line (line width)
  (multiple-value-bind (clipped used)
      (slice-to-width line width)
    (concatenate
     'string clipped
     (make-string
      (max 0 (- width used))
      :initial-element #\Space))))

(defun apply-component-background
    (line width background-function)
  (let ((padded (pad-component-line line width)))
    (if background-function
        (apply-restoring-style
         padded background-function)
        padded)))

(defclass text-component (component)
  ((text
    :initarg :text
    :initform ""
    :accessor text-component-text)
   (padding-x
    :initarg :padding-x
    :initform 1
    :accessor text-component-padding-x)
   (padding-y
    :initarg :padding-y
    :initform 1
    :accessor text-component-padding-y)
   (background-function
    :initarg :background-function
    :initform nil
    :accessor text-component-background-function)
   (cached-text :initform nil
                :accessor text-component-cached-text)
   (cached-width :initform nil
                 :accessor text-component-cached-width)
   (cached-lines :initform nil
                 :accessor text-component-cached-lines)))

(defun make-text-component
    (text &key (padding-x 1) (padding-y 1)
       background-function)
  (make-instance
   'text-component
   :text text :padding-x padding-x
   :padding-y padding-y
   :background-function background-function))

(defun clear-text-component-cache (component)
  (setf
   (text-component-cached-text component) nil
   (text-component-cached-width component) nil
   (text-component-cached-lines component) nil)
  component)

(defun text-component-set-text (component text)
  (setf (text-component-text component) text)
  (clear-text-component-cache component))

(defun text-component-set-background
    (component background-function)
  (setf
   (text-component-background-function component)
   background-function)
  (clear-text-component-cache component))

(defmethod component-invalidate ((component text-component))
  (clear-text-component-cache component))

(defmethod component-render
    ((component text-component) width &key focused-p)
  (declare (ignore focused-p))
  (let ((text (text-component-text component)))
    (when
        (and (text-component-cached-lines component)
             (equal text
                    (text-component-cached-text component))
             (eql width
                  (text-component-cached-width component)))
      (return-from component-render
        (text-component-cached-lines component)))
    (when
        (zerop
         (length
          (string-trim
           '(#\Space #\Tab #\Newline #\Return)
           text)))
      (setf
       (text-component-cached-text component) text
       (text-component-cached-width component) width
       (text-component-cached-lines component) nil)
      (return-from component-render nil))
    (let* ((padding-x
             (max 0 (text-component-padding-x component)))
           (padding-y
             (max 0 (text-component-padding-y component)))
           (available-width
             (max 1 (- width (* 2 padding-x))))
           (normalized
             (cl-ppcre:regex-replace-all
              (string #\Tab) text "   "))
           (margin
             (make-string padding-x
                          :initial-element #\Space))
           (background
             (text-component-background-function component))
           (content
             (loop for line in (wrap-text normalized available-width)
                   collect
                   (apply-component-background
                    (concatenate 'string margin line margin)
                    width background)))
           (empty
             (apply-component-background "" width background))
           (padding
             (make-list padding-y
                        :initial-element empty))
           (result
             (append padding content padding)))
      (setf
       (text-component-cached-text component) text
       (text-component-cached-width component) width
       (text-component-cached-lines component) result)
      result)))

(defclass spacer-component (component)
  ((lines
    :initarg :lines
    :initform 1
    :accessor spacer-component-lines)))

(defun make-spacer-component (&key (lines 1))
  (make-instance 'spacer-component :lines (max 0 lines)))

(defun spacer-component-set-lines (component lines)
  (setf (spacer-component-lines component)
        (max 0 lines))
  component)

(defmethod component-render
    ((component spacer-component) width &key focused-p)
  (declare (ignore width focused-p))
  (make-list (spacer-component-lines component)
             :initial-element ""))

(defclass box-component (component-container)
  ((padding-x
    :initarg :padding-x
    :initform 1
    :accessor box-component-padding-x)
   (padding-y
    :initarg :padding-y
    :initform 1
    :accessor box-component-padding-y)
   (background-function
    :initarg :background-function
    :initform nil
    :accessor box-component-background-function)
   (cache-key :initform nil
              :accessor box-component-cache-key)
   (cached-lines :initform nil
                 :accessor box-component-cached-lines)))

(defun make-box-component
    (&key (padding-x 1) (padding-y 1)
       background-function children)
  (make-instance
   'box-component
   :padding-x padding-x :padding-y padding-y
   :background-function background-function
   :children (copy-list children)))

(defun clear-box-component-cache (component)
  (setf
   (box-component-cache-key component) nil
   (box-component-cached-lines component) nil)
  component)

(defmethod component-add-child :after
    ((container box-component) child)
  (declare (ignore child))
  (clear-box-component-cache container))

(defmethod component-remove-child :after
    ((container box-component) child)
  (declare (ignore child))
  (clear-box-component-cache container))

(defmethod component-clear :after
    ((container box-component))
  (clear-box-component-cache container))

(defmethod component-invalidate
    ((component box-component))
  (clear-box-component-cache component)
  (call-next-method))

(defun box-component-set-background
    (component background-function)
  (setf
   (box-component-background-function component)
   background-function)
  (clear-box-component-cache component))

(defmethod component-render
    ((component box-component) width &key focused-p)
  (declare (ignore focused-p))
  (when (null (component-children component))
    (return-from component-render nil))
  (let* ((padding-x
           (max 0 (box-component-padding-x component)))
         (padding-y
           (max 0 (box-component-padding-y component)))
         (content-width
           (max 1 (- width (* 2 padding-x))))
         (left
           (make-string padding-x
                        :initial-element #\Space))
         (child-lines
           (loop for child in (component-children component)
                 nconc
                 (loop for line in
                       (component-render
                        child content-width
                        :focused-p
                        (component-focused-p child))
                       collect
                       (concatenate 'string left line))))
         (background
           (box-component-background-function component))
         (sample
           (and background (funcall background "test")))
         (key (list width child-lines sample)))
    (when (null child-lines)
      (return-from component-render nil))
    (when (equal key (box-component-cache-key component))
      (return-from component-render
        (box-component-cached-lines component)))
    (let* ((empty
             (apply-component-background
              "" width background))
           (padding
             (make-list padding-y
                        :initial-element empty))
           (result
             (append
              padding
              (loop for line in child-lines
                    collect
                    (apply-component-background
                     line width background))
              padding)))
      (setf
       (box-component-cache-key component) key
       (box-component-cached-lines component) result)
      result)))

(defclass truncated-text-component (component)
  ((text
    :initarg :text
    :accessor truncated-text-component-text)
   (padding-x
    :initarg :padding-x
    :initform 0
    :accessor truncated-text-component-padding-x)
   (padding-y
    :initarg :padding-y
    :initform 0
    :accessor truncated-text-component-padding-y)))

(defun make-truncated-text-component
    (text &key (padding-x 0) (padding-y 0))
  (make-instance
   'truncated-text-component
   :text text :padding-x padding-x
   :padding-y padding-y))

(defmethod component-render
    ((component truncated-text-component)
     width &key focused-p)
  (declare (ignore focused-p))
  (render-truncated-text
   (truncated-text-component-text component)
   width
   :padding-x
   (truncated-text-component-padding-x component)
   :padding-y
   (truncated-text-component-padding-y component)))

(defclass markdown-component (component)
  ((text
    :initarg :text
    :accessor markdown-component-text)
   (padding-x
    :initarg :padding-x
    :initform 0
    :accessor markdown-component-padding-x)
   (padding-y
    :initarg :padding-y
    :initform 0
    :accessor markdown-component-padding-y)
   (ansi-theme-p
    :initarg :ansi-theme-p
    :initform nil
    :accessor markdown-component-ansi-theme-p)
   (transform-function
    :initarg :transform-function
    :initform nil
    :accessor markdown-component-transform-function)
   (syntax-highlight-function
    :initarg :syntax-highlight-function
    :initform nil
    :accessor markdown-component-syntax-highlight-function)
   (default-style-function
    :initarg :default-style-function
    :initform nil
    :accessor markdown-component-default-style-function)
   (preserve-list-markers-p
    :initarg :preserve-list-markers-p
    :initform nil
    :accessor markdown-component-preserve-list-markers-p)
   (capabilities
    :initarg :capabilities
    :initform nil
    :accessor markdown-component-capabilities)
   (cached-text :initform nil
                :accessor markdown-component-cached-text)
   (cached-width :initform nil
                 :accessor markdown-component-cached-width)
   (cached-lines :initform nil
                 :accessor markdown-component-cached-lines)))

(defun make-markdown-component
    (text &key (padding-x 0) (padding-y 0)
       ansi-theme-p transform-function
       syntax-highlight-function
       default-style-function
       preserve-list-markers-p capabilities)
  (make-instance
   'markdown-component
   :text text :padding-x padding-x
   :padding-y padding-y
   :ansi-theme-p ansi-theme-p
   :transform-function transform-function
   :syntax-highlight-function syntax-highlight-function
   :default-style-function default-style-function
   :preserve-list-markers-p preserve-list-markers-p
   :capabilities capabilities))

(defun clear-markdown-component-cache (component)
  (setf
   (markdown-component-cached-text component) nil
   (markdown-component-cached-width component) nil
   (markdown-component-cached-lines component) nil)
  component)

(defun markdown-component-set-text (component text)
  (setf (markdown-component-text component) text)
  (clear-markdown-component-cache component))

(defmethod component-invalidate
    ((component markdown-component))
  (clear-markdown-component-cache component))

(defmethod component-render
    ((component markdown-component) width &key focused-p)
  (declare (ignore focused-p))
  (when
      (and (markdown-component-cached-lines component)
           (equal (markdown-component-text component)
                  (markdown-component-cached-text component))
           (eql width
                (markdown-component-cached-width component)))
    (return-from component-render
      (markdown-component-cached-lines component)))
  (let ((result
          (render-markdown
           (markdown-component-text component)
           width
           :ansi-theme-p
           (markdown-component-ansi-theme-p component)
           :transform-function
           (markdown-component-transform-function component)
           :syntax-highlight-function
           (markdown-component-syntax-highlight-function
            component)
           :default-style-function
           (markdown-component-default-style-function
            component)
           :preserve-list-markers-p
           (markdown-component-preserve-list-markers-p
            component)
           :padding-x
           (markdown-component-padding-x component)
           :padding-y
           (markdown-component-padding-y component)
           :capabilities
           (or (markdown-component-capabilities component)
               (get-terminal-capabilities)))))
    (setf
     (markdown-component-cached-text component)
     (markdown-component-text component)
     (markdown-component-cached-width component) width
     (markdown-component-cached-lines component) result)
    result))

(defclass image-component (component)
  ((base64-data
    :initarg :base64-data
    :accessor image-component-base64-data)
   (mime-type
    :initarg :mime-type
    :accessor image-component-mime-type)
   (dimensions
    :initarg :dimensions
    :accessor image-component-dimensions)
   (fallback-color-function
    :initarg :fallback-color-function
    :initform #'identity
    :accessor image-component-fallback-color-function)
   (filename
    :initarg :filename
    :initform nil
    :accessor image-component-filename)
   (image-id
    :initarg :image-id
    :initform nil
    :accessor image-component-id)
   (max-width-cells
    :initarg :max-width-cells
    :initform nil
    :accessor image-component-max-width-cells)
   (max-height-cells
    :initarg :max-height-cells
    :initform nil
    :accessor image-component-max-height-cells)
   (capabilities
    :initarg :capabilities
    :initform nil
    :accessor image-component-capabilities)
   (cached-width :initform nil
                 :accessor image-component-cached-width)
   (cached-lines :initform nil
                 :accessor image-component-cached-lines)))

(defun make-image-component
    (base64-data mime-type
     &key dimensions fallback-color-function
       filename image-id max-width-cells
       max-height-cells capabilities)
  (multiple-value-bind (detected-width detected-height)
      (if dimensions
          (values (first dimensions) (second dimensions))
          (image-dimensions base64-data mime-type))
    (make-instance
     'image-component
     :base64-data base64-data
     :mime-type mime-type
     :dimensions
     (list (or detected-width 800)
           (or detected-height 600))
     :fallback-color-function
     (or fallback-color-function #'identity)
     :filename filename :image-id image-id
     :max-width-cells max-width-cells
     :max-height-cells max-height-cells
     :capabilities capabilities)))

(defmethod component-invalidate ((component image-component))
  (setf
   (image-component-cached-width component) nil
   (image-component-cached-lines component) nil)
  component)

(defmethod component-render
    ((component image-component) width &key focused-p)
  (declare (ignore focused-p))
  (when
      (and (image-component-cached-lines component)
           (eql width (image-component-cached-width component)))
    (return-from component-render
      (image-component-cached-lines component)))
  (let* ((capabilities
           (or (image-component-capabilities component)
               (get-terminal-capabilities)))
         (maximum-width
           (max 1
                (min
                 (- width 2)
                 (or
                  (image-component-max-width-cells component)
                  60))))
         (maximum-height
           (or
            (image-component-max-height-cells component)
            (multiple-value-bind (cell-width cell-height)
                (get-cell-dimensions)
              (max 1
                   (ceiling
                    (* maximum-width cell-width)
                    cell-height)))))
         (image-protocol
           (terminal-capabilities-images capabilities))
         (dimensions
           (image-component-dimensions component))
         (lines nil))
    (when
        (and (eq image-protocol :kitty)
             (null (image-component-id component)))
      (setf (image-component-id component)
            (allocate-image-id)))
    (when image-protocol
      (let ((result
              (render-terminal-image
               (image-component-base64-data component)
               (first dimensions) (second dimensions)
               :capabilities capabilities
               :max-width-cells maximum-width
               :max-height-cells maximum-height
               :image-id (image-component-id component)
               :move-cursor-p nil)))
        (when result
          (when (image-render-result-image-id result)
            (setf (image-component-id component)
                  (image-render-result-image-id result)))
          (setf lines
                (if (eq image-protocol :kitty)
                    (cons
                     (image-render-result-sequence result)
                     (make-list
                      (1- (image-render-result-rows result))
                      :initial-element ""))
                    (let* ((row-offset
                             (1- (image-render-result-rows result)))
                           (last-line
                             (concatenate
                              'string
                              (if (plusp row-offset)
                                  (format nil "~C[~DA"
                                          #\Escape row-offset)
                                  "")
                              (image-render-result-sequence result))))
                      (append
                       (make-list row-offset
                                  :initial-element "")
                       (list last-line))))))))
    (unless lines
      (setf lines
            (list
             (truncate-to-width
              (funcall
               (image-component-fallback-color-function component)
               (image-fallback
                (image-component-mime-type component)
                :width (first dimensions)
                :height (second dimensions)
                :filename (image-component-filename component)
                :capabilities capabilities))
              width))))
    (setf
     (image-component-cached-width component) width
     (image-component-cached-lines component) lines)
    lines))

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
       (if (string= (or (input-event-text event) "") " ")
           (settings-list-activate-item component)
           (when
               (and
                (settings-list-component-search-enabled-p component)
                (settings-list-component-search-input component))
             (let ((sanitized
                     (remove #\Space
                             (or (input-event-text event) ""))))
               (when (plusp (length sanitized))
                 (single-line-input-handle-event
                  (settings-list-component-search-input component)
                  (make-input-event
                   :kind :text :text sanitized))
                 (settings-list-apply-filter component))))))
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

(defclass loader-component (text-component)
  ((ui
    :initarg :ui
    :accessor loader-component-ui)
   (frames
    :initarg :frames
    :accessor loader-component-frames)
   (interval-seconds
    :initarg :interval-seconds
    :accessor loader-component-interval-seconds)
   (current-frame
    :initform 0
    :accessor loader-component-current-frame)
   (spinner-color-function
    :initarg :spinner-color-function
    :accessor loader-component-spinner-color-function)
   (message-color-function
    :initarg :message-color-function
    :accessor loader-component-message-color-function)
   (message
    :initarg :message
    :accessor loader-component-message)
   (render-indicator-verbatim-p
    :initarg :render-indicator-verbatim-p
    :initform nil
    :accessor loader-component-render-indicator-verbatim-p)
   (thread
    :initform nil
    :accessor loader-component-thread)
   (stop-p
    :initform nil
    :accessor loader-component-stop-p)
   (lock
    :initform
    (sb-thread:make-mutex :name "cadr TUI loader")
    :reader loader-component-lock)))

(defparameter +loader-default-frames+
  '("⠋" "⠙" "⠹" "⠸" "⠼"
    "⠴" "⠦" "⠧" "⠇" "⠏"))

(defun loader-component-request-render (loader)
  (let ((ui (loader-component-ui loader)))
    (cond
      ((typep ui 'tui-root)
       (tui-request-render ui))
      ((functionp ui)
       (funcall ui)))))

(defun loader-component-update-display (loader)
  (let* ((frames (loader-component-frames loader))
         (frame
           (or (nth (loader-component-current-frame loader)
                    frames)
               ""))
         (rendered-frame
           (if (loader-component-render-indicator-verbatim-p loader)
               frame
               (funcall
                (loader-component-spinner-color-function loader)
                frame)))
         (indicator
           (if (plusp (length frame))
               (concatenate 'string rendered-frame " ")
               "")))
    (text-component-set-text
     loader
     (concatenate
      'string indicator
      (funcall
       (loader-component-message-color-function loader)
       (loader-component-message loader)))))
  loader)

(defun make-loader-component
    (ui spinner-color-function message-color-function
     &key (message "Loading...") indicator-frames
       interval-seconds (start-p t))
  (let ((loader
          (make-instance
           'loader-component
           :ui ui
           :text "" :padding-x 1 :padding-y 0
           :spinner-color-function spinner-color-function
           :message-color-function message-color-function
           :message message
           :frames
           (copy-list
            (or indicator-frames +loader-default-frames+))
           :interval-seconds
           (if (and interval-seconds
                    (plusp interval-seconds))
               interval-seconds
               0.08d0)
           :render-indicator-verbatim-p
           (not (null indicator-frames)))))
    (loader-component-update-display loader)
    (when start-p
      (loader-component-start loader))
    loader))

(defmethod component-render
    ((loader loader-component) width &key focused-p)
  (declare (ignore focused-p))
  (cons "" (call-next-method)))

(defun loader-component-step (loader)
  (sb-thread:with-mutex ((loader-component-lock loader))
    (let ((count (length (loader-component-frames loader))))
      (when (plusp count)
        (setf
         (loader-component-current-frame loader)
         (mod (1+ (loader-component-current-frame loader))
              count)))
      (loader-component-update-display loader)))
  (loader-component-request-render loader)
  loader)

(defun loader-component-run (loader)
  (loop
    (sleep (loader-component-interval-seconds loader))
    (when (loader-component-stop-p loader)
      (return))
    (loader-component-step loader)))

(defun loader-component-start (loader)
  (loader-component-stop loader)
  (setf (loader-component-stop-p loader) nil)
  (when (> (length (loader-component-frames loader)) 1)
    (setf
     (loader-component-thread loader)
     (sb-thread:make-thread
      (lambda () (loader-component-run loader))
      :name "cadr TUI loader")))
  loader)

(defun loader-component-stop (loader)
  (setf (loader-component-stop-p loader) t)
  (let ((thread (loader-component-thread loader)))
    (when (and thread
               (not (eq thread sb-thread:*current-thread*)))
      (when (sb-thread:thread-alive-p thread)
        (sb-thread:join-thread thread)))
    (setf (loader-component-thread loader) nil))
  loader)

(defun loader-component-set-message (loader message)
  (setf (loader-component-message loader) message)
  (loader-component-update-display loader)
  (loader-component-request-render loader)
  loader)

(defun loader-component-set-indicator
    (loader &key frames interval-seconds (start-p t))
  (loader-component-stop loader)
  (setf
   (loader-component-frames loader)
   (copy-list (or frames +loader-default-frames+))
   (loader-component-interval-seconds loader)
   (if (and interval-seconds (plusp interval-seconds))
       interval-seconds
       0.08d0)
   (loader-component-current-frame loader) 0
   (loader-component-render-indicator-verbatim-p loader)
   (not (null frames)))
  (loader-component-update-display loader)
  (when start-p (loader-component-start loader))
  loader)

(defmethod component-dispose ((loader loader-component))
  (loader-component-stop loader))

(defclass cancellation-token ()
  ((aborted-p
    :initform nil
    :accessor cancellation-token-aborted-p)))

(defclass cancellable-loader-component (loader-component)
  ((token
    :initform (make-instance 'cancellation-token)
    :reader cancellable-loader-token)
   (on-abort
    :initform nil
    :accessor cancellable-loader-on-abort)))

(defun make-cancellable-loader-component
    (ui spinner-color-function message-color-function
     &key (message "Loading...") indicator-frames
       interval-seconds (start-p t))
  (let ((loader
          (make-instance
           'cancellable-loader-component
           :ui ui :text "" :padding-x 1 :padding-y 0
           :spinner-color-function spinner-color-function
           :message-color-function message-color-function
           :message message
           :frames
           (copy-list
            (or indicator-frames +loader-default-frames+))
           :interval-seconds
           (if (and interval-seconds
                    (plusp interval-seconds))
               interval-seconds 0.08d0)
           :render-indicator-verbatim-p
           (not (null indicator-frames)))))
    (loader-component-update-display loader)
    (when start-p (loader-component-start loader))
    loader))

(defun cancellable-loader-set-on-abort
    (loader function)
  (setf (cancellable-loader-on-abort loader) function)
  loader)

(defmethod component-handle-event
    ((loader cancellable-loader-component) event)
  (when
      (and (eq :escape (input-event-kind event))
           (not
            (cancellation-token-aborted-p
             (cancellable-loader-token loader))))
    (setf
     (cancellation-token-aborted-p
      (cancellable-loader-token loader))
     t)
    (when (cancellable-loader-on-abort loader)
      (funcall (cancellable-loader-on-abort loader))))
  (values nil nil))

(defstruct tui-overlay-record
  handle component
  width min-width max-height
  (anchor :center)
  (offset-x 0) (offset-y 0)
  row col margin visible-p)

(defclass tui-root (component-container)
  ((terminal
    :initarg :terminal
    :accessor tui-terminal)
   (renderer
    :initarg :renderer
    :initform nil
    :accessor tui-renderer)
   (render-function
    :initarg :render-function
    :initform nil
    :accessor tui-render-function)
   (focused-component
    :initform nil
    :accessor tui-focused-component)
   (overlay-stack
    :initform (make-overlay-stack)
    :accessor tui-overlay-stack)
   (overlays
    :initform nil
    :accessor tui-overlays)
   (input-listeners
    :initform nil
    :accessor tui-input-listeners)
   (decoder
    :initform (make-input-decoder)
    :accessor tui-input-decoder)
   (started-p
    :initform nil
    :accessor tui-started-p)))

(defun make-tui-root
    (&key terminal renderer render-function
       (columns 80) (rows 24))
  (make-instance
   'tui-root
   :terminal
   (or terminal
       (make-virtual-terminal
        :columns columns :rows rows))
   :renderer renderer
   :render-function render-function))

(defun tui-set-focus (tui component)
  (let ((previous (tui-focused-component tui)))
    (when previous
      (setf (component-focused-p previous) nil))
    (setf
     (tui-focused-component tui) component
     (overlay-stack-focused-component
      (tui-overlay-stack tui))
     component)
    (when component
      (setf (component-focused-p component) t)))
  tui)

(defun tui-sync-focus (tui)
  (let ((target
          (overlay-stack-input-target
           (tui-overlay-stack tui))))
    (unless (eq target (tui-focused-component tui))
      (let ((previous (tui-focused-component tui)))
        (when previous
          (setf (component-focused-p previous) nil))
        (setf (tui-focused-component tui) target)
        (when target
          (setf (component-focused-p target) t)))))
  tui)

(defun tui-overlay-visible-records (tui)
  (sort
   (remove-if-not
    (lambda (record)
      (let ((entry
              (overlay-handle-entry
               (tui-overlay-record-handle record))))
        (overlay-entry-visible-p entry)))
    (copy-list (tui-overlays tui)))
   #'<
   :key
   (lambda (record)
     (overlay-stack-entry-focus-order
      (overlay-handle-entry
       (tui-overlay-record-handle record))))))

(defmethod component-render
    ((tui tui-root) width &key focused-p)
  (declare (ignore focused-p))
  (let ((base (call-next-method)))
    (if (not (overlay-stack-visible-p
              (tui-overlay-stack tui)))
        base
        (let ((placements nil)
              (height
                (terminal-rows (tui-terminal tui))))
          (dolist (record (tui-overlay-visible-records tui))
            (multiple-value-bind
                  (overlay-width ignored-row ignored-column
                   ignored-max-height)
                (resolve-overlay-layout
                 width height 0
                 :width (tui-overlay-record-width record)
                 :min-width
                 (tui-overlay-record-min-width record)
                 :max-height
                 (tui-overlay-record-max-height record)
                 :anchor (tui-overlay-record-anchor record)
                 :offset-x
                 (tui-overlay-record-offset-x record)
                 :offset-y
                 (tui-overlay-record-offset-y record)
                 :row (tui-overlay-record-row record)
                 :col (tui-overlay-record-col record)
                 :margin (tui-overlay-record-margin record))
              (declare
               (ignore ignored-row ignored-column
                       ignored-max-height))
              (push
               (make-overlay-placement
                :lines
                (component-render
                 (tui-overlay-record-component record)
                 overlay-width
                 :focused-p
                 (eq
                  (tui-overlay-record-component record)
                  (tui-focused-component tui)))
                :width (tui-overlay-record-width record)
                :min-width
                (tui-overlay-record-min-width record)
                :max-height
                (tui-overlay-record-max-height record)
                :anchor (tui-overlay-record-anchor record)
                :offset-x
                (tui-overlay-record-offset-x record)
                :offset-y
                (tui-overlay-record-offset-y record)
                :row (tui-overlay-record-row record)
                :col (tui-overlay-record-col record)
                :margin (tui-overlay-record-margin record))
               placements)))
          (composite-overlay-frame
           base (nreverse placements) width height)))))

(defun tui-request-render (tui &optional force-p)
  (when (and force-p (tui-renderer tui))
    (invalidate-renderer (tui-renderer tui)))
  (let ((lines
          (component-render
           tui (terminal-columns (tui-terminal tui)))))
    (when (tui-renderer tui)
      (render-frame (tui-renderer tui) lines))
    (when (tui-render-function tui)
      (funcall (tui-render-function tui) lines)))
  tui)

(defun tui-start (tui)
  (unless (tui-started-p tui)
    (terminal-start (tui-terminal tui))
    (setf (tui-started-p tui) t)
    (tui-request-render tui))
  tui)

(defun tui-stop (tui)
  (when (tui-started-p tui)
    (terminal-stop (tui-terminal tui))
    (setf (tui-started-p tui) nil))
  tui)

(defun tui-add-input-listener (tui listener)
  (pushnew listener (tui-input-listeners tui) :test #'eq)
  (lambda ()
    (setf (tui-input-listeners tui)
          (remove listener (tui-input-listeners tui)
                  :test #'eq))))

(defun tui-remove-input-listener (tui listener)
  (setf (tui-input-listeners tui)
        (remove listener (tui-input-listeners tui)
                :test #'eq))
  tui)

(defun tui-dispatch-event (tui event)
  (let ((current event))
    (dolist (listener
             (reverse (tui-input-listeners tui)))
      (multiple-value-bind (consume-p replacement)
          (funcall listener current)
        (when consume-p
          (return-from tui-dispatch-event
            (values nil nil)))
        (when replacement
          (setf current replacement))))
    (tui-sync-focus tui)
    (let ((target (tui-focused-component tui)))
      (when target
        (multiple-value-prog1
            (component-handle-event target current)
          (tui-request-render tui))))))

(defun tui-handle-input (tui input)
  (dolist
      (event
       (etypecase input
         (input-event (list input))
         (string
          (let ((target (tui-focused-component tui)))
            (if (and target
                     (component-wants-key-release-p target)
                     (key-release-p input))
                (list
                 (make-input-event
                  :kind :key-release :text input))
                (feed-input (tui-input-decoder tui) input))))))
    (tui-dispatch-event tui event))
  tui)

(defun tui-show-overlay
    (tui component
     &key width min-width max-height
       (anchor :center) (offset-x 0) (offset-y 0)
       row col margin non-capturing-p (visible-p t))
  (let* ((visibility
           (if (functionp visible-p)
               (lambda ()
                 (funcall
                  visible-p
                  (terminal-columns (tui-terminal tui))
                  (terminal-rows (tui-terminal tui))))
               visible-p))
         (handle
           (overlay-stack-show
            (tui-overlay-stack tui)
            component nil
            :non-capturing-p non-capturing-p
            :visible-p visibility))
         (record
           (make-tui-overlay-record
            :handle handle :component component
            :width width :min-width min-width
            :max-height max-height :anchor anchor
            :offset-x offset-x :offset-y offset-y
            :row row :col col :margin margin
            :visible-p visible-p)))
    (setf
     (tui-overlays tui)
     (nconc (tui-overlays tui) (list record)))
    (tui-sync-focus tui)
    (tui-request-render tui)
    handle))

(defun tui-overlay-hide (tui handle)
  (overlay-handle-hide handle)
  (setf (tui-overlays tui)
        (remove handle (tui-overlays tui)
                :key #'tui-overlay-record-handle
                :test #'eq))
  (tui-sync-focus tui)
  (tui-request-render tui)
  handle)

(defun tui-overlay-set-hidden (tui handle hidden-p)
  (overlay-handle-set-hidden handle hidden-p)
  (tui-sync-focus tui)
  (tui-request-render tui)
  handle)

(defun tui-overlay-focus (tui handle)
  (overlay-handle-focus handle)
  (tui-sync-focus tui)
  (tui-request-render tui)
  handle)

(defun tui-overlay-unfocus
    (tui handle &key (target nil target-supplied-p))
  (if target-supplied-p
      (overlay-handle-unfocus handle :target target)
      (overlay-handle-unfocus handle))
  (tui-sync-focus tui)
  (tui-request-render tui)
  handle)

(defun tui-has-overlay-p (tui)
  (overlay-stack-visible-p (tui-overlay-stack tui)))

(defun overlay-handle-hidden-p (handle)
  (or
   (overlay-stack-entry-removed-p
    (overlay-handle-entry handle))
   (overlay-stack-entry-hidden-p
    (overlay-handle-entry handle))))

(defmethod component-invalidate ((tui tui-root))
  (call-next-method)
  (dolist (record (tui-overlays tui))
    (component-invalidate
     (tui-overlay-record-component record)))
  (when (tui-renderer tui)
    (invalidate-renderer (tui-renderer tui)))
  tui)

(defmethod component-dispose ((tui tui-root))
  (dolist (record (tui-overlays tui))
    (component-dispose
     (tui-overlay-record-component record)))
  (call-next-method)
  (tui-stop tui)
  tui)
