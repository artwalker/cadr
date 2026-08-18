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

(defun snake-harness-random (limit &optional random-state)
  (if (example-render-diff-harness-p)
      0
      (if random-state
          (random limit random-state)
          (random limit))))

(defun snake-spawn-food (snake &optional (random-state *random-state*))
  (loop for point = (snake-point (snake-harness-random +snake-width+ random-state)
                                 (snake-harness-random +snake-height+ random-state))
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

(defvar *snake-state* nil)
(defvar *snake-component* nil)

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

(defun snake-live-state (component)
  "Live overlay reads the global when bound. Reconstruct / restart
replace that object; a slot captured at /snake would otherwise keep
painting the pre-replace frame. Tests that only set the slot fall
back to it."
  (or *snake-state* (snake-component-state component)))

(defun snake-bind-live-state (component state)
  (setf *snake-component* component
        *snake-state* state
        (snake-component-state component) state)
  state)

(defun snake-component-advance (component)
  "Timer tick (baseline snake.ts:90-97): mutate then requestRender.
User-input paths do not call this; tui-dispatch-event already
request-renders after component-handle-event (root.lisp:207-208)."
  (sb-thread:with-mutex ((snake-component-lock component))
    (snake-tick (snake-live-state component)))
  (cadr-tui:tui-request-render (snake-component-tui component))
  component)

(defun snake-component-start (component)
  (unless (snake-component-running-p component)
    (setf (snake-component-running-p component) t)
    (unless (example-render-diff-harness-p)
      (setf (snake-component-thread component)
            (sb-thread:make-thread
             (lambda ()
               (loop while (snake-component-running-p component)
                     do (sleep +snake-tick-seconds+)
                        (when (and (snake-component-running-p component)
                                   (not (snake-component-paused-p component)))
                          (snake-component-advance component))))
             :name "cadr snake example timer"))))
  component)

(defun snake-component-stop (component)
  (setf (snake-component-running-p component) nil)
  (let ((thread (snake-component-thread component)))
    (when (and thread (sb-thread:thread-alive-p thread)
               (not (eq thread sb-thread:*current-thread*)))
      (ignore-errors (sb-thread:join-thread thread))))
  (setf (snake-component-thread component) nil)
  component)

;; Baseline snake.ts SGR helpers, byte for byte (snake.ts:220-224):
;; dim/bold close with ESC[22m, colors close with ESC[0m.  Color codes are
;; passed WITHOUT the trailing m - the previous single helper both took
;; m-suffixed codes and appended its own m, painting a literal m before
;; every colored string (the goal 20 P0 stray-m defect).
(defun snake-dim (text)
  (format nil "~C[2m~A~C[22m" #\Escape text #\Escape))

(defun snake-color (code text)
  (format nil "~C[~Am~A~C[0m" #\Escape code text #\Escape))

(defun snake-bold (text)
  (format nil "~C[1m~A~C[22m" #\Escape text #\Escape))

(defun snake-box-line (content box-width)
  "Baseline snake.ts boxLine(): dim borders with the interior padded to the
box width by visible length (snake.ts:229-233)."
  (format nil "~A~A~A~A"
          (snake-dim " │")
          content
          (make-string (max 0 (- box-width (cadr-tui:visible-width content)))
                       :initial-element #\Space)
          (snake-dim "│")))

(defun snake-board-line (state y effective-width)
  (with-output-to-string (output)
    (write-string (snake-dim " │") output)
    (loop for x below effective-width
          for point = (snake-point x y)
          do (write-string
              (cond
                ((snake-point= point (first (snake-state-snake state)))
                 (snake-color "32" "██"))
                ((find point (rest (snake-state-snake state)) :test #'snake-point=)
                 (snake-color "32" "▓▓"))
                ((snake-point= point (snake-state-food state))
                 (snake-color "31" "◆ "))
                (t "  "))
              output))
    (write-string (snake-dim "│") output)))

(defmethod cadr-tui:component-render
    ((component snake-component) width &key focused-p)
  (declare (ignore focused-p))
  (sb-thread:with-mutex ((snake-component-lock component))
    (let* ((state (snake-live-state component))
           (effective-width (max 1 (min +snake-width+ (floor (- width 4) 2))))
           (box-width (* 2 effective-width))
           ;; Footer copy and SGR composition follow snake.ts:238-241 and
           ;; :270-279 byte for byte: bold(green(...)) opens 1m then 32m and
           ;; closes 0m then 22m; yellow(bold(...)) nests the other way.
           ;; The baseline's "ESC pause" copy describes the same
           ;; save-and-exit path cadr takes (snake.ts:165 "ESC to pause and
           ;; save").
           (footer
             (cond
               ((snake-component-paused-p component)
                (format nil "~A Press any key to continue, ~A to quit"
                        (snake-color "33" (snake-bold "PAUSED"))
                        (snake-bold "Q")))
               ((snake-state-game-over-p state)
                (format nil "~A Press ~A to restart, ~A to quit"
                        (snake-color "31" (snake-bold "GAME OVER!"))
                        (snake-bold "R")
                        (snake-bold "Q")))
               (t
                (format nil "↑↓←→ or WASD to move, ~A pause, ~A quit"
                        (snake-bold "ESC")
                        (snake-bold "Q"))))))
      (append
       (list (snake-dim (format nil " ╭~A╮" (make-string box-width :initial-element #\─)))
             (snake-box-line
              (format nil "~A │ Score: ~A │ High: ~A"
                      (snake-bold (snake-color "32" "SNAKE"))
                      (snake-bold
                       (snake-color "33"
                                    (princ-to-string (snake-state-score state))))
                      (snake-bold
                       (snake-color "33"
                                    (princ-to-string
                                     (snake-state-high-score state)))))
              box-width)
             (snake-dim (format nil " ├~A┤" (make-string box-width :initial-element #\─))))
       (loop for y below +snake-height+
             collect (snake-board-line state y effective-width))
       (list (snake-dim (format nil " ├~A┤" (make-string box-width :initial-element #\─)))
             (snake-box-line footer box-width)
             (snake-dim (format nil " ╰~A╯" (make-string box-width :initial-element #\─))))))))

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
                (snake-state-to-data (snake-live-state component)))
       (snake-component-stop component)
       (funcall (snake-component-done component) nil))
      ((member text '("q" "Q") :test #'string=)
       (funcall (snake-component-save component) nil)
       (snake-component-stop component)
       (funcall (snake-component-done component) nil))
      ((and (snake-state-game-over-p (snake-live-state component))
            (or (member text '("r" "R" " ") :test #'string=)
                (eq (cadr-tui:input-event-kind event) :enter)))
       (let ((high-score
               (snake-state-high-score (snake-live-state component))))
         (snake-bind-live-state
          component
          (make-initial-snake-state :high-score high-score))
         (funcall (snake-component-save component) nil)))
      (t
       (let* ((state (snake-live-state component))
              (direction (snake-event-direction event)))
         (when (and direction
                    (not (snake-direction-opposite-p
                          (snake-state-direction state) direction)))
           (setf (snake-state-next-direction state) direction))
         (when (and (example-render-diff-harness-p)
                    (not (snake-state-game-over-p state)))
           (snake-component-advance component))))))
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
            (let* ((state (or saved (make-initial-snake-state)))
                   (component
                     (make-instance
                      'snake-component
                      :state state
                      :paused-p (and saved (not (snake-state-game-over-p saved)))
                      :tui tui :done done
                      :save (lambda (data)
                              (cadr-agent:extension-api-append-entry
                               *example-api* +snake-save-type+ data)))))
              (snake-bind-live-state component state)
              (unless (snake-component-paused-p component)
                (snake-component-start component))
              component)))))))
