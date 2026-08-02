(load (merge-pathnames "support.lisp" *load-truename*))

(defclass example-game-component (cadr-tui:component)
  ((title :initarg :title :reader example-game-title)
   (width :initarg :width :initform 24 :reader example-game-width)
   (height :initarg :height :initform 10 :reader example-game-height)
   (x :initform 2 :accessor example-game-x)
   (y :initform 2 :accessor example-game-y)
   (glyph :initarg :glyph :initform "@" :reader example-game-glyph)
   (ticks :initform 0 :accessor example-game-ticks)
   (done :initarg :done :reader example-game-done)))

(defmethod cadr-tui:component-render
    ((component example-game-component) width &key focused-p)
  (declare (ignore width focused-p))
  (let ((board-width (example-game-width component))
        (board-height (example-game-height component)))
    (append
     (list (format nil "~A · tick ~D"
                   (example-game-title component)
                   (example-game-ticks component)))
     (loop for row below board-height
           collect
           (with-output-to-string (output)
             (loop for column below board-width
                   do (write-string
                       (if (and (= row (example-game-y component))
                                (= column (example-game-x component)))
                           (example-game-glyph component)
                           (if (or (zerop row) (= row (1- board-height))
                                   (zerop column) (= column (1- board-width)))
                               "#" " "))
                      output))))
     (list "arrows move · q/escape close"))))

(defmethod cadr-tui:component-handle-event
    ((component example-game-component) event)
  (case (cadr-tui:input-event-kind event)
    (:up (setf (example-game-y component)
               (max 1 (1- (example-game-y component)))))
    (:down (setf (example-game-y component)
                 (min (- (example-game-height component) 2)
                      (1+ (example-game-y component)))))
    (:left (setf (example-game-x component)
                 (max 1 (1- (example-game-x component)))))
    (:right (setf (example-game-x component)
                  (min (- (example-game-width component) 2)
                       (1+ (example-game-x component)))))
    ((:escape :cancel :interrupt)
     (funcall (example-game-done component) nil))
    (:text
     (when (string-equal (or (cadr-tui:input-event-text event) "") "q")
       (funcall (example-game-done component) nil))))
  (incf (example-game-ticks component))
  (values nil nil))

(defun example-open-game (context title &key (glyph "@") (width 24) (height 10))
  (cadr-agent:extension-context-custom-component
   context
   (lambda (tui theme keybindings done)
     (declare (ignore tui theme keybindings))
     (make-instance 'example-game-component
                    :title title :glyph glyph :width width :height height
                    :done done))
   :overlay-p t
   :overlay-options '(:anchor :center :margin 1 :width 32 :max-height 16)))
