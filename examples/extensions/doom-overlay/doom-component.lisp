(load (merge-pathnames "doom-keys.lisp" *load-truename*))
(load (merge-pathnames "doom-engine.lisp" *load-truename*))

(defclass doom-component (cadr-tui:component)
  ((engine :initarg :engine :reader doom-component-engine)
   (done :initarg :done :reader doom-component-done)))

(defmethod cadr-tui:component-render
    ((component doom-component) width &key focused-p)
  (declare (ignore focused-p))
  (append
   (mapcar (lambda (line)
             (if (> (length line) width) (subseq line 0 width) line))
           (doom-engine-current-frame (doom-component-engine component)))
   '("WASD/arrows move · F fire · Space use · Escape close")))

(defmethod cadr-tui:component-handle-event
    ((component doom-component) event)
  (let ((kind (cadr-tui:input-event-kind event)))
    (if (member kind '(:escape :cancel :interrupt))
        (funcall (doom-component-done component) nil)
        (dolist (key
                 (map-key-to-doom
                  (or (cadr-tui:input-event-text event)
                      (string-downcase (symbol-name kind)))))
          (doom-engine-key (doom-component-engine component) key t)
          (doom-engine-key (doom-component-engine component) key nil))))
  (values nil nil))

(defmethod cadr-tui:component-dispose ((component doom-component))
  (stop-doom-engine (doom-component-engine component))
  component)
