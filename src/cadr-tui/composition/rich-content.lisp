(in-package #:cadr-tui)

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
