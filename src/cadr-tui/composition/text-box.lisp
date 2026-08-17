(in-package #:cadr-tui)

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
        (if (eq (text-component-cached-lines component) :blank)
            nil
            (text-component-cached-lines component))))
    (when
        (zerop
         (length
          (string-trim
           '(#\Space #\Tab #\Newline #\Return)
           text)))
      (setf
       (text-component-cached-text component) text
       (text-component-cached-width component) width
       (text-component-cached-lines component) :blank)
      (return-from component-render nil))
    (let* ((padding-x
             (max 0 (text-component-padding-x component)))
           (padding-y
             (max 0 (text-component-padding-y component)))
           (available-width
             (max 1 (- width (* 2 padding-x))))
           (normalized
             (with-output-to-string (out)
               (loop for character across text
                     do (if (char= character #\Tab)
                            (write-string "   " out)
                            (write-char character out)))))
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
