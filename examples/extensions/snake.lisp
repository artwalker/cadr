(load (merge-pathnames "support.lisp" *load-truename*))

(defconstant +snake-width+ 40)
(defconstant +snake-height+ 15)
(defconstant +snake-tick-seconds+ 0.1)
(defconstant +snake-save-type+ "snake-save")

(defstruct snake-state
  snake food
  (direction :right)
  (next-direction :right)
  (score 0)
  (game-over-p nil)
  (high-score 0))

(defun snake-point (x y)
  (cons x y))

(defun snake-point= (left right)
  (and (= (car left) (car right))
       (= (cdr left) (cdr right))))

(defun snake-spawn-food (snake &optional (random-state *random-state*))
  (loop for point = (snake-point (random +snake-width+ random-state)
                                 (random +snake-height+ random-state))
        unless (find point snake :test #'snake-point=)
          return point))

(defun make-initial-snake-state (&key (high-score 0) random-state)
  (let* ((x (floor +snake-width+ 2))
         (y (floor +snake-height+ 2))
         (snake (list (snake-point x y)
                      (snake-point (1- x) y)
                      (snake-point (- x 2) y))))
    (make-snake-state
     :snake snake
     :food (snake-spawn-food snake (or random-state *random-state*))
     :high-score high-score)))

(defun snake-state-to-data (state)
  (list :snake (mapcar (lambda (point) (list (car point) (cdr point)))
                       (snake-state-snake state))
        :food (list (car (snake-state-food state))
                    (cdr (snake-state-food state)))
        :direction (snake-state-direction state)
        :next-direction (snake-state-next-direction state)
        :score (snake-state-score state)
        :game-over-p (snake-state-game-over-p state)
        :high-score (snake-state-high-score state)))

(defun snake-state-from-data (data)
  (when (and (listp data) (getf data :snake))
    (make-snake-state
     :snake (mapcar (lambda (point) (snake-point (first point) (second point)))
                    (getf data :snake))
     :food (let ((point (getf data :food)))
             (snake-point (first point) (second point)))
     :direction (or (getf data :direction) :right)
     :next-direction (or (getf data :next-direction) :right)
     :score (or (getf data :score) 0)
     :game-over-p (not (null (getf data :game-over-p)))
     :high-score (or (getf data :high-score) 0))))

(defun snake-next-head (state)
  (let* ((head (first (snake-state-snake state)))
         (x (car head))
         (y (cdr head)))
    (ecase (snake-state-direction state)
      (:up (snake-point x (1- y)))
      (:down (snake-point x (1+ y)))
      (:left (snake-point (1- x) y))
      (:right (snake-point (1+ x) y)))))

(defun snake-tick (state &optional (random-state *random-state*))
  (unless (snake-state-game-over-p state)
    (setf (snake-state-direction state)
          (snake-state-next-direction state))
    (let ((head (snake-next-head state)))
      (if (or (< (car head) 0) (>= (car head) +snake-width+)
              (< (cdr head) 0) (>= (cdr head) +snake-height+)
              (find head (snake-state-snake state) :test #'snake-point=))
          (setf (snake-state-game-over-p state) t)
          (progn
            (push head (snake-state-snake state))
            (if (snake-point= head (snake-state-food state))
                (progn
                  (incf (snake-state-score state) 10)
                  (setf (snake-state-high-score state)
                        (max (snake-state-high-score state)
                             (snake-state-score state))
                        (snake-state-food state)
                        (snake-spawn-food (snake-state-snake state)
                                          random-state)))
                (setf (snake-state-snake state)
                      (butlast (snake-state-snake state))))))))
  state)

(defun snake-direction-opposite-p (left right)
  (member (cons left right)
          '((:up . :down) (:down . :up)
            (:left . :right) (:right . :left))
          :test #'equal))

(defclass snake-component (cadr-tui:component)
  ((state :initarg :state :accessor snake-component-state)
   (tui :initarg :tui :reader snake-component-tui)
   (done :initarg :done :reader snake-component-done)
   (save :initarg :save :reader snake-component-save)
   (paused-p :initarg :paused-p :accessor snake-component-paused-p)
   (running-p :initform nil :accessor snake-component-running-p)
   (thread :initform nil :accessor snake-component-thread)
   (lock :initform (sb-thread:make-mutex :name "snake example state")
         :reader snake-component-lock)))

(defun snake-component-start (component)
  (unless (snake-component-running-p component)
    (setf (snake-component-running-p component) t
          (snake-component-thread component)
          (sb-thread:make-thread
           (lambda ()
             (loop while (snake-component-running-p component)
                   do (sleep +snake-tick-seconds+)
                      (when (and (snake-component-running-p component)
                                 (not (snake-component-paused-p component)))
                        (sb-thread:with-mutex ((snake-component-lock component))
                          (snake-tick (snake-component-state component)))
                        (cadr-tui:tui-request-render
                         (snake-component-tui component)))))
           :name "cadr snake example timer")))
  component)

(defun snake-component-stop (component)
  (setf (snake-component-running-p component) nil)
  (let ((thread (snake-component-thread component)))
    (when (and thread (sb-thread:thread-alive-p thread)
               (not (eq thread sb-thread:*current-thread*)))
      (ignore-errors (sb-thread:join-thread thread))))
  (setf (snake-component-thread component) nil)
  component)

(defun snake-board-line (state y effective-width)
  (with-output-to-string (output)
    (write-string " │" output)
    (loop for x below effective-width
          for point = (snake-point x y)
          do (write-string
              (cond
                ((snake-point= point (first (snake-state-snake state))) "██")
                ((find point (rest (snake-state-snake state)) :test #'snake-point=) "▓▓")
                ((snake-point= point (snake-state-food state)) "◆ ")
                (t "  "))
              output))
    (write-string "│" output)))

(defmethod cadr-tui:component-render
    ((component snake-component) width &key focused-p)
  (declare (ignore focused-p))
  (sb-thread:with-mutex ((snake-component-lock component))
    (let* ((state (snake-component-state component))
           (effective-width (max 1 (min +snake-width+ (floor (- width 4) 2))))
           (box-width (* 2 effective-width))
           (footer
             (cond
               ((snake-component-paused-p component)
                "PAUSED · any key resumes · Q quits")
               ((snake-state-game-over-p state)
                "GAME OVER · R restarts · Q quits")
               (t "arrows/WASD move · ESC saves · Q quits"))))
      (append
       (list (format nil " ╭~A╮" (make-string box-width :initial-element #\─))
             (format nil " │SNAKE · Score: ~D · High: ~D~V@T│"
                     (snake-state-score state)
                     (snake-state-high-score state)
                     box-width "")
             (format nil " ├~A┤" (make-string box-width :initial-element #\─)))
       (loop for y below +snake-height+
             collect (snake-board-line state y effective-width))
       (list (format nil " ├~A┤" (make-string box-width :initial-element #\─))
             (format nil " │~VA│" box-width footer)
             (format nil " ╰~A╯" (make-string box-width :initial-element #\─)))))))

(defun snake-event-direction (event)
  (let ((text (or (cadr-tui:input-event-text event) "")))
    (case (cadr-tui:input-event-kind event)
      (:up :up) (:down :down) (:left :left) (:right :right)
      (:text
       (cond ((member text '("w" "W") :test #'string=) :up)
             ((member text '("s" "S") :test #'string=) :down)
             ((member text '("a" "A") :test #'string=) :left)
             ((member text '("d" "D") :test #'string=) :right))))))

(defmethod cadr-tui:component-handle-event
    ((component snake-component) event)
  (let ((text (or (cadr-tui:input-event-text event) "")))
    (cond
      ((and (snake-component-paused-p component)
            (not (member (cadr-tui:input-event-kind event)
                         '(:escape :cancel :interrupt))))
       (setf (snake-component-paused-p component) nil)
       (snake-component-start component))
      ((member (cadr-tui:input-event-kind event)
               '(:escape :cancel :interrupt))
       (funcall (snake-component-save component)
                (snake-state-to-data (snake-component-state component)))
       (snake-component-stop component)
       (funcall (snake-component-done component) nil))
      ((member text '("q" "Q") :test #'string=)
       (funcall (snake-component-save component) nil)
       (snake-component-stop component)
       (funcall (snake-component-done component) nil))
      ((and (snake-state-game-over-p (snake-component-state component))
            (or (member text '("r" "R" " ") :test #'string=)
                (eq (cadr-tui:input-event-kind event) :enter)))
       (let ((high-score
               (snake-state-high-score (snake-component-state component))))
         (setf (snake-component-state component)
               (make-initial-snake-state :high-score high-score))
         (funcall (snake-component-save component) nil)))
      (t
       (let* ((state (snake-component-state component))
              (direction (snake-event-direction event)))
         (when (and direction
                    (not (snake-direction-opposite-p
                          (snake-state-direction state) direction)))
           (setf (snake-state-next-direction state) direction))))))
  (values nil nil))

(defmethod cadr-tui:component-dispose ((component snake-component))
  (snake-component-stop component))

(defun snake-saved-state (context)
  (loop for entry in (reverse (or (example-session-entries context) nil))
        when (and (eq (cadr-agent:session-entry-type entry) :custom)
                  (string= (or (cadr-agent:session-entry-custom-type entry) "")
                           +snake-save-type+))
          return (snake-state-from-data (cadr-agent:session-entry-data entry))))

(cadr-agent:define-command
 "snake"
 :description "Play Snake!"
 :handler
 (lambda (arguments context)
   (declare (ignore arguments))
   (if (not (cadr-agent:extension-context-has-ui-p context))
       (cadr-agent:extension-context-notify
        context "Snake requires interactive mode" :level :error)
       (let ((saved (snake-saved-state context)))
         (cadr-agent:extension-context-custom-component
          context
          (lambda (tui theme keybindings done)
            (declare (ignore theme keybindings))
            (let ((component
                    (make-instance
                     'snake-component
                     :state (or saved (make-initial-snake-state))
                     :paused-p (and saved (not (snake-state-game-over-p saved)))
                     :tui tui :done done
                     :save (lambda (data)
                             (cadr-agent:extension-api-append-entry
                              *example-api* +snake-save-type+ data)))))
              (unless (snake-component-paused-p component)
                (snake-component-start component))
              component)))))))
