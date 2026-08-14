(load (merge-pathnames "support.lisp" *load-truename*))

(defclass example-mascot-header (cadr-tui:component)
  ((theme
    :initarg :theme
    :reader example-mascot-header-theme)))

(defun example-mascot-lines (theme)
  (let* ((block "█")
         (pupil "▌")
         (eye
           (concatenate
            'string
            (example-theme-fg theme :text block)
            (example-theme-fg theme :dim pupil)))
         (bar (example-theme-fg theme :accent (make-string 14 :initial-element #\█)))
         (leg-pair
           (concatenate
            'string
            (example-theme-fg theme :accent (make-string 2 :initial-element #\█))
            "    "
            (example-theme-fg theme :accent (make-string 2 :initial-element #\█))))
         (release
           (string-left-trim
            '(#\v #\V)
            (nth-value 0 (cadr-ai::read-baseline-anchor))))
         (subtitle
           (concatenate
            'string
            (example-theme-fg theme :muted "   shitty coding agent")
            (example-theme-fg theme :dim (format nil " v~A" release)))))
    (list
     ""
     (format nil "     ~A  ~A" eye eye)
     (format nil "  ~A" bar)
     (format nil "     ~A" leg-pair)
     (format nil "     ~A" leg-pair)
     (format nil "     ~A" leg-pair)
     (format nil "     ~A" leg-pair)
     ""
     subtitle)))

(defmethod cadr-tui:component-render
    ((component example-mascot-header) width &key focused-p)
  (declare (ignore width focused-p))
  (example-mascot-lines (example-mascot-header-theme component)))

(cadr-agent:define-event-hook
 :session-start
 :handler
 (lambda (event context)
   (declare (ignore event))
   (when (eq (cadr-agent:extension-context-mode context) :tui)
     (cadr-agent:extension-context-set-header
      context
      (lambda (tui theme)
        (declare (ignore tui))
        (make-instance 'example-mascot-header :theme theme))))))

(cadr-agent:define-command
 "builtin-header"
 :description "Restore built-in header with keybinding hints"
 :handler
 (lambda (arguments context)
   (declare (ignore arguments))
   (cadr-agent:extension-context-set-header context nil)
   (cadr-agent:extension-context-notify context "Built-in header restored")))
