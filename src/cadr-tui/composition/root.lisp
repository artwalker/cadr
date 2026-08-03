(in-package #:cadr-tui)

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
