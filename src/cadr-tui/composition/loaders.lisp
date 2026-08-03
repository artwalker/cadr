(in-package #:cadr-tui)

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
        (stop-thread-for-cleanup thread)))
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
  ((state
    :initform (cadr-core:make-cancellation-state)
    :reader cancellation-token-state)))

(defun cancellation-token-aborted-p (token)
  (cadr-core:cancellation-aborted-p
   (cancellation-token-state token)))

(defun (setf cancellation-token-aborted-p) (value token)
  (cadr-core:set-cancellation-aborted-p
   (cancellation-token-state token) value))

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
