(in-package #:cadr-cli)

(defun format-key-part (part capitalize-p)
  (let ((display
          (if (and (uiop:os-macosx-p)
                   (string-equal part "alt"))
              "option"
              part)))
    (if (and capitalize-p (plusp (length display)))
        (concatenate
         'string
         (string-upcase (subseq display 0 1))
         (subseq display 1))
        display)))

(defparameter +ansi-foreground-reset+
  (format nil "~C[39m" #\Escape))

(defun format-key-text* (keys &key capitalize-p)
  ;; Stream join. On non-macOS without capitalize, each alternative
  ;; string is already display-ready (no split/rejoin on +).
  (with-output-to-string (out)
    (loop for alternative in keys
          for index from 0
          do
             (when (plusp index)
               (write-char #\/ out))
             (cond
               ((and (not capitalize-p)
                     (stringp alternative)
                     (not (uiop:os-macosx-p)))
                (write-string alternative out))
               (t
                (let ((parts
                        (if (stringp alternative)
                            (uiop:split-string
                             alternative
                             :separator '(#\+))
                            (list
                             (princ-to-string
                              alternative)))))
                  (loop for part in parts
                        for part-index from 0
                        do
                           (when (plusp part-index)
                             (write-char #\+ out))
                           (write-string
                            (format-key-part
                             part capitalize-p)
                            out))))))))

(defun format-key-text (key &key capitalize-p)
  (format-key-text*
   (uiop:split-string key :separator '(#\/))
   :capitalize-p capitalize-p))

(defun key-text (keybinding)
  (format-key-text*
   (cadr-tui:keybinding-keys
    (cadr-tui:get-keybindings) keybinding)))

(defun key-display-text (keybinding)
  (format-key-text*
   (cadr-tui:keybinding-keys
    (cadr-tui:get-keybindings) keybinding)
   :capitalize-p t))

(defun write-raw-key-hint
    (out keys description)
  (let* ((theme (cadr-tui:current-theme))
         (enabled-p
           (cadr-tui::effective-theme-enabled-p
            theme nil nil)))
    (when enabled-p
      (write-string
       (cadr-tui:theme-foreground-ansi
        :dim :theme theme :enabled-p t)
       out))
    (write-string (format-key-text* keys) out)
    (when enabled-p
      (write-string +ansi-foreground-reset+ out)
      (write-string
       (cadr-tui:theme-foreground-ansi
        :muted :theme theme :enabled-p t)
       out))
    (write-char #\Space out)
    (write-string description out)
    (when enabled-p
      (write-string +ansi-foreground-reset+ out))))

(defun raw-key-hint (key description)
  (with-output-to-string (out)
    (write-raw-key-hint
     out
     (uiop:split-string key :separator '(#\/))
     description)))

(defun key-hint (keybinding description)
  (raw-key-hint (key-text keybinding) description))

(defclass dynamic-border-component (cadr-tui:component)
  ((color-function
    :initarg :color-function
    :accessor dynamic-border-color-function)))

(defun make-dynamic-border-component
    (&key
       (color-function
         (lambda (text)
           (cadr-tui:theme-foreground :border text))))
  (make-instance
   'dynamic-border-component
   :color-function color-function))

(defmethod cadr-tui:component-render
    ((component dynamic-border-component)
     width &key focused-p)
  (declare (ignore focused-p))
  (list
   (funcall
    (dynamic-border-color-function component)
    (make-string (max 1 width) :initial-element #\─))))

(defclass bordered-loader-component
    (cadr-tui:component-container)
  ((loader
    :initarg :loader
    :reader bordered-loader-loader)
   (cancellable-p
    :initarg :cancellable-p
    :reader bordered-loader-cancellable-p)
   (signal
    :initarg :signal
    :reader bordered-loader-signal)))

(defun make-bordered-loader-component
    (ui message &key (cancellable-p t) (start-p t))
  (let* ((accent
           (lambda (text)
             (cadr-tui:theme-foreground :accent text)))
         (muted
           (lambda (text)
             (cadr-tui:theme-foreground :muted text)))
         (loader
           (if cancellable-p
               (cadr-tui:make-cancellable-loader-component
                ui accent muted :message message
                :start-p start-p)
               (cadr-tui:make-loader-component
                ui accent muted :message message
                :start-p start-p)))
         (signal
           (if cancellable-p
               (cadr-tui:cancellable-loader-token loader)
               (make-instance 'cadr-tui:cancellation-token)))
         (component
           (make-instance
            'bordered-loader-component
            :loader loader :cancellable-p cancellable-p
            :signal signal)))
    (cadr-tui:component-add-child
     component
     (make-dynamic-border-component))
    (cadr-tui:component-add-child component loader)
    (when cancellable-p
      (cadr-tui:component-add-child
       component (cadr-tui:make-spacer-component :lines 1))
      (cadr-tui:component-add-child
       component
       (cadr-tui:make-text-component
        (key-hint "tui.select.cancel" "cancel")
        :padding-x 1 :padding-y 0)))
    (cadr-tui:component-add-child
     component (cadr-tui:make-spacer-component :lines 1))
    (cadr-tui:component-add-child
     component
     (make-dynamic-border-component))
    component))

(defun bordered-loader-set-on-abort (component function)
  (when (bordered-loader-cancellable-p component)
    (cadr-tui:cancellable-loader-set-on-abort
     (bordered-loader-loader component) function))
  component)

(defmethod cadr-tui:component-handle-event
    ((component bordered-loader-component) event)
  (if (bordered-loader-cancellable-p component)
      (cadr-tui:component-handle-event
       (bordered-loader-loader component) event)
      (values nil nil)))

(defmethod cadr-tui:component-dispose
    ((component bordered-loader-component))
  (cadr-tui:component-dispose
   (bordered-loader-loader component))
  component)
