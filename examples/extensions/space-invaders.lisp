(load (merge-pathnames "support.lisp" *load-truename*))

(defconstant +invaders-width+ 60)
(defconstant +invaders-height+ 24)
(defconstant +invaders-player-y+ 22)
(defconstant +invaders-tick-seconds+ 0.05)
(defconstant +invaders-save-type+ "space-invaders-save")

(defstruct invader x y type (alive-p t))
(defstruct invader-bullet x y direction)
(defstruct invader-shield x segments)
(defstruct invaders-state
  player-x
  (lives 3)
  aliens
  (alien-direction 1)
  (alien-move-counter 0)
  (alien-move-delay 18)
  (alien-dropping-p nil)
  bullets shields
  (score 0)
  (high-score 0)
  (level 1)
  (game-over-p nil)
  (victory-p nil)
  (alien-shoot-counter 0))

(defun make-invaders-aliens ()
  (loop for row below 5 append
        (loop for column below 11
              collect
              (make-invader
               :x (+ 4 (* column 5))
               :y (+ 2 (* row 2))
               :type (cond ((zerop row) 2) ((< row 3) 1) (t 0))))))

(defun make-invaders-shields ()
  (loop for x in '(8 22 36 50)
        collect
        (make-invader-shield
         :x x
         :segments
         (vector (vector t t t t)
                 (vector t t t t)
                 (vector t nil nil t)))))

(defun make-initial-invaders-state (&key (high-score 0) (level 1))
  (make-invaders-state
   :player-x (floor +invaders-width+ 2)
   :aliens (make-invaders-aliens)
   :alien-move-delay (max 5 (- 20 (* level 2)))
   :bullets nil
   :shields (make-invaders-shields)
   :high-score high-score
   :level level))

(defun invaders-state-to-data (state)
  (list
   :player-x (invaders-state-player-x state)
   :lives (invaders-state-lives state)
   :aliens
   (mapcar (lambda (alien)
             (list :x (invader-x alien) :y (invader-y alien)
                   :type (invader-type alien)
                   :alive-p (invader-alive-p alien)))
           (invaders-state-aliens state))
   :alien-direction (invaders-state-alien-direction state)
   :alien-move-counter (invaders-state-alien-move-counter state)
   :alien-move-delay (invaders-state-alien-move-delay state)
   :alien-dropping-p (invaders-state-alien-dropping-p state)
   :bullets
   (mapcar (lambda (bullet)
             (list :x (invader-bullet-x bullet)
                   :y (invader-bullet-y bullet)
                   :direction (invader-bullet-direction bullet)))
           (invaders-state-bullets state))
   :shields
   (mapcar (lambda (shield)
             (list :x (invader-shield-x shield)
                   :segments
                   (map 'list (lambda (row) (coerce row 'list))
                        (invader-shield-segments shield))))
           (invaders-state-shields state))
   :score (invaders-state-score state)
   :high-score (invaders-state-high-score state)
   :level (invaders-state-level state)
   :game-over-p (invaders-state-game-over-p state)
   :victory-p (invaders-state-victory-p state)
   :alien-shoot-counter (invaders-state-alien-shoot-counter state)))

(defun invaders-state-from-data (data)
  (when (and (listp data) (getf data :aliens))
    (make-invaders-state
     :player-x (or (getf data :player-x) 30)
     :lives (or (getf data :lives) 3)
     :aliens
     (mapcar (lambda (alien)
               (make-invader
                :x (getf alien :x) :y (getf alien :y)
                :type (getf alien :type)
                :alive-p (not (null (getf alien :alive-p)))))
             (getf data :aliens))
     :alien-direction (or (getf data :alien-direction) 1)
     :alien-move-counter (or (getf data :alien-move-counter) 0)
     :alien-move-delay (or (getf data :alien-move-delay) 18)
     :alien-dropping-p (not (null (getf data :alien-dropping-p)))
     :bullets
     (mapcar (lambda (bullet)
               (make-invader-bullet
                :x (getf bullet :x) :y (getf bullet :y)
                :direction (getf bullet :direction)))
             (getf data :bullets))
     :shields
     (mapcar (lambda (shield)
               (make-invader-shield
                :x (getf shield :x)
                :segments
                (map 'vector (lambda (row) (coerce row 'vector))
                     (getf shield :segments))))
             (getf data :shields))
     :score (or (getf data :score) 0)
     :high-score (or (getf data :high-score) 0)
     :level (or (getf data :level) 1)
     :game-over-p (not (null (getf data :game-over-p)))
     :victory-p (not (null (getf data :victory-p)))
     :alien-shoot-counter (or (getf data :alien-shoot-counter) 0))))

(defun invaders-alive-aliens (state)
  (remove-if-not #'invader-alive-p (invaders-state-aliens state)))

(defun invaders-move-aliens (state)
  (let ((alive (invaders-alive-aliens state)))
    (when alive
      (if (invaders-state-alien-dropping-p state)
          (progn
            (dolist (alien alive)
              (incf (invader-y alien))
              (when (>= (invader-y alien) (1- +invaders-player-y+))
                (setf (invaders-state-game-over-p state) t)))
            (setf (invaders-state-alien-dropping-p state) nil))
          (let ((minimum (reduce #'min alive :key #'invader-x))
                (maximum (reduce #'max alive :key #'invader-x)))
            (if (or (and (= (invaders-state-alien-direction state) 1)
                         (>= maximum (- +invaders-width+ 3)))
                    (and (= (invaders-state-alien-direction state) -1)
                         (<= minimum 2)))
                (setf (invaders-state-alien-direction state)
                      (- (invaders-state-alien-direction state))
                      (invaders-state-alien-dropping-p state) t)
                (dolist (alien alive)
                  (incf (invader-x alien)
                        (invaders-state-alien-direction state))))))
      (let ((count (length alive)))
        (setf (invaders-state-alien-move-delay state)
              (cond ((<= count 5) 1)
                    ((<= count 10) 2)
                    ((<= count 20) 3)
                    (t (invaders-state-alien-move-delay state))))))))

(defun invaders-alien-shoot (state &optional (random-state *random-state*))
  (let ((bottom-by-x (make-hash-table :test #'eql)))
    (dolist (alien (invaders-alive-aliens state))
      (let ((existing (gethash (invader-x alien) bottom-by-x)))
        (when (or (null existing) (> (invader-y alien) (invader-y existing)))
          (setf (gethash (invader-x alien) bottom-by-x) alien))))
    (let ((shooters (loop for alien being the hash-values of bottom-by-x
                          collect alien)))
      (when (and shooters
                 (< (count 1 (invaders-state-bullets state)
                           :key #'invader-bullet-direction) 3))
        (let ((alien (nth (random (length shooters) random-state) shooters)))
          (push (make-invader-bullet
                 :x (invader-x alien) :y (1+ (invader-y alien))
                 :direction 1)
                (invaders-state-bullets state)))))))

(defun invaders-shield-hit-p (state bullet)
  (dolist (shield (invaders-state-shields state) nil)
    (let ((x (- (invader-bullet-x bullet) (invader-shield-x shield)))
          (y (- (invader-bullet-y bullet) (- +invaders-player-y+ 5))))
      (when (and (<= 0 x 3) (<= 0 y 2)
                 (aref (aref (invader-shield-segments shield) y) x))
        (setf (aref (aref (invader-shield-segments shield) y) x) nil)
        (return t)))))

(defun invaders-collisions (state)
  (let ((kept nil))
    (dolist (bullet (invaders-state-bullets state))
      (let ((hit-p nil))
        (cond
          ((= (invader-bullet-direction bullet) -1)
           (dolist (alien (invaders-state-aliens state))
             (when (and (not hit-p) (invader-alive-p alien)
                        (= (invader-y alien) (invader-bullet-y bullet))
                        (<= (abs (- (invader-x alien)
                                   (invader-bullet-x bullet))) 1))
               (setf (invader-alive-p alien) nil
                     hit-p t)
               (incf (invaders-state-score state)
                     (aref #(10 20 30) (invader-type alien)))
               (setf (invaders-state-high-score state)
                     (max (invaders-state-high-score state)
                          (invaders-state-score state))))))
          ((and (= (invader-bullet-direction bullet) 1)
                (= (invader-bullet-y bullet) +invaders-player-y+)
                (<= (abs (- (invader-bullet-x bullet)
                            (invaders-state-player-x state))) 1))
           (setf hit-p t)
           (decf (invaders-state-lives state))
           (when (<= (invaders-state-lives state) 0)
             (setf (invaders-state-game-over-p state) t))))
        (when (and (not hit-p) (invaders-shield-hit-p state bullet))
          (setf hit-p t))
        (unless hit-p (push bullet kept))))
    (setf (invaders-state-bullets state) (nreverse kept))))

(defun invaders-tick (state keys &optional (random-state *random-state*))
  (unless (or (invaders-state-game-over-p state)
              (invaders-state-victory-p state))
    (when (and (getf keys :left) (> (invaders-state-player-x state) 2))
      (decf (invaders-state-player-x state)))
    (when (and (getf keys :right)
               (< (invaders-state-player-x state) (- +invaders-width+ 3)))
      (incf (invaders-state-player-x state)))
    (when (and (getf keys :fire)
               (< (count -1 (invaders-state-bullets state)
                         :key #'invader-bullet-direction) 2))
      (push (make-invader-bullet
             :x (invaders-state-player-x state)
             :y (1- +invaders-player-y+) :direction -1)
            (invaders-state-bullets state))
      (setf (getf keys :fire) nil))
    (setf (invaders-state-bullets state)
          (loop for bullet in (invaders-state-bullets state)
                do (incf (invader-bullet-y bullet)
                         (invader-bullet-direction bullet))
                when (<= 0 (invader-bullet-y bullet) (1- +invaders-height+))
                  collect bullet))
    (when (>= (incf (invaders-state-alien-move-counter state))
              (invaders-state-alien-move-delay state))
      (setf (invaders-state-alien-move-counter state) 0)
      (invaders-move-aliens state))
    (when (>= (incf (invaders-state-alien-shoot-counter state)) 30)
      (setf (invaders-state-alien-shoot-counter state) 0)
      (invaders-alien-shoot state random-state))
    (invaders-collisions state)
    (when (every (lambda (alien) (not (invader-alive-p alien)))
                 (invaders-state-aliens state))
      (setf (invaders-state-victory-p state) t)))
  state)

(defvar *space-invaders-state* nil)
(defvar *space-invaders-component* nil)

(defclass space-invaders-component (cadr-tui:component)
  ((state :initarg :state :accessor space-invaders-state)
   (keys :initform (list :left nil :right nil :fire nil)
         :accessor space-invaders-keys)
   (tui :initarg :tui :reader space-invaders-tui)
   (done :initarg :done :reader space-invaders-done)
   (save :initarg :save :reader space-invaders-save)
   (paused-p :initarg :paused-p :accessor space-invaders-paused-p)
   (running-p :initform nil :accessor space-invaders-running-p)
   (thread :initform nil :accessor space-invaders-thread)
   (lock :initform (sb-thread:make-mutex :name "invaders example state")
         :reader space-invaders-lock)))

(defun space-invaders-live-state (component)
  "Live overlay reads the global when bound. Restart replaces that
object; a slot captured at /invaders would otherwise keep painting
the previous level. Tests that only set the slot fall back to it."
  (or *space-invaders-state* (space-invaders-state component)))

(defun space-invaders-bind-live-state (component state)
  (setf *space-invaders-component* component
        *space-invaders-state* state
        (space-invaders-state component) state)
  state)

(defmethod cadr-tui:component-wants-key-release-p
    ((component space-invaders-component))
  (declare (ignore component))
  t)

(defun space-invaders-advance (component)
  "Timer tick (baseline space-invaders.ts:144-151): mutate then
requestRender. Restart and key paths go through handle-event;
tui-dispatch-event request-renders those (root.lisp:207-208)."
  (sb-thread:with-mutex ((space-invaders-lock component))
    (invaders-tick (space-invaders-live-state component)
                   (space-invaders-keys component)))
  (cadr-tui:tui-request-render (space-invaders-tui component))
  component)

(defun space-invaders-start (component)
  (unless (space-invaders-running-p component)
    (setf (space-invaders-running-p component) t)
    (unless (example-render-diff-harness-p)
      (setf (space-invaders-thread component)
            (sb-thread:make-thread
             (lambda ()
               (loop while (space-invaders-running-p component)
                     do (sleep +invaders-tick-seconds+)
                        (when (and (space-invaders-running-p component)
                                   (not (space-invaders-paused-p component)))
                          (space-invaders-advance component))))
             :name "cadr space invaders example timer"))))
  component)

(defun space-invaders-stop (component)
  (setf (space-invaders-running-p component) nil)
  (let ((thread (space-invaders-thread component)))
    (when (and thread (sb-thread:thread-alive-p thread)
               (not (eq thread sb-thread:*current-thread*)))
      (ignore-errors (sb-thread:join-thread thread))))
  (setf (space-invaders-thread component) nil)
  component)

(defun invaders-dim (text)
  (format nil "~C[2m~A~C[22m" #\Escape text #\Escape))

(defun invaders-color (code text)
  (format nil "~C[~Am~A~C[0m" #\Escape code text #\Escape))

(defun invaders-bold (text)
  (format nil "~C[1m~A~C[22m" #\Escape text #\Escape))

(defun invaders-alien-sprite (type x alien-x)
  "Baseline sprites (space-invaders.ts render): type 0 ▼ with ╲╱,
type 1 ◆ with ╱╲, type 2 ☆ with ◄►, colored green, cyan, magenta."
  (multiple-value-bind (center left right code)
      (ecase type
        (0 (values "▼" "╲" "╱" "32"))
        (1 (values "◆" "╱" "╲" "36"))
        (2 (values "☆" "◄" "►" "35")))
    (invaders-color code
                    (cond ((= x alien-x) center)
                          ((< x alien-x) left)
                          (t right)))))

(defun invaders-shield-cell (state x y)
  "Nil outside every shield. :hit is a live segment. :miss is a
destroyed segment, which still masks the player and bullets the way
the baseline shield loop breaks inside the 4×3 bounds."
  (dolist (shield (invaders-state-shields state) nil)
    (let ((relative-x (- x (invader-shield-x shield)))
          (relative-y (- y (- +invaders-player-y+ 5))))
      (when (and (<= 0 relative-x 3) (<= 0 relative-y 2))
        (return (if (aref (aref (invader-shield-segments shield) relative-y)
                          relative-x)
                    :hit
                    :miss))))))

(defun invaders-cell (state x y)
  (let ((alien
          (find-if
           (lambda (candidate)
             (and (invader-alive-p candidate)
                  (= y (invader-y candidate))
                  (<= (abs (- x (invader-x candidate))) 1)))
           (invaders-state-aliens state)))
        (shield (invaders-shield-cell state x y)))
    (cond
      (alien (invaders-alien-sprite (invader-type alien) x (invader-x alien)))
      ((eq shield :hit) (invaders-dim "█"))
      ((eq shield :miss) " ")
      ((and (= y +invaders-player-y+)
            (<= (abs (- x (invaders-state-player-x state))) 1))
       (invaders-color "97"
                       (if (= x (invaders-state-player-x state)) "▲" "═")))
      (t
       (let ((bullet
               (find-if (lambda (candidate)
                          (and (= x (invader-bullet-x candidate))
                               (= y (invader-bullet-y candidate))))
                        (invaders-state-bullets state))))
         (if bullet
             (invaders-color
              (if (= (invader-bullet-direction bullet) -1) "33" "31")
              "│")
             " "))))))

(defun invaders-column-width (text)
  "One column per character after CSI is removed. The baseline's
visibleWidth and padLine do that for this board. U+2665 is one cell
there and in the terminal; cadr-tui:visible-width counts it as two,
which shortens the header padding and moves the right border."
  (loop with index = 0
        with width = 0
        while (< index (length text))
        do (if (and (char= (char text index) #\Escape)
                    (< (1+ index) (length text))
                    (char= (char text (1+ index)) #\[))
               (let ((end (position #\m text :start index)))
                 (setf index (if end (1+ end) (length text))))
               (progn
                 (incf width)
                 (incf index)))
        finally (return width)))

(defun invaders-box-line (content)
  (format nil "~A~A~A~A"
          (invaders-dim " │")
          content
          (make-string (max 0 (- +invaders-width+
                                 (invaders-column-width content)))
                       :initial-element #\Space)
          (invaders-dim "│")))

(defun invaders-pad-line (line width)
  (let ((padding (max 0 (- width (invaders-column-width line)))))
    (if (zerop padding)
        line
        (concatenate 'string
                     line
                     (make-string padding :initial-element #\Space)))))

(defun invaders-header (state)
  (format nil "~A │ Score: ~A │ Hi: ~A │ Lv: ~A │ ~A"
          (invaders-bold (invaders-color "32" "SPACE INVADERS"))
          (invaders-bold
           (invaders-color "33"
                           (princ-to-string (invaders-state-score state))))
          (invaders-bold
           (invaders-color "33"
                           (princ-to-string (invaders-state-high-score state))))
          (invaders-bold
           (invaders-color "36"
                           (princ-to-string (invaders-state-level state))))
          (invaders-color "31"
                          (make-string (max 0 (invaders-state-lives state))
                                       :initial-element #\♥))))

(defun invaders-footer (component state)
  (cond
    ((space-invaders-paused-p component)
     (format nil "~A Press any key to continue, ~A to quit"
             (invaders-color "33" (invaders-bold "PAUSED"))
             (invaders-bold "Q")))
    ((invaders-state-game-over-p state)
     (format nil "~A Press ~A to restart, ~A to quit"
             (invaders-color "31" (invaders-bold "GAME OVER!"))
             (invaders-bold "R")
             (invaders-bold "Q")))
    ((invaders-state-victory-p state)
     (format nil "~A Press ~A for level ~D, ~A to quit"
             (invaders-color "32" (invaders-bold "VICTORY!"))
             (invaders-bold "R")
             (1+ (invaders-state-level state))
             (invaders-bold "Q")))
    (t
     (format nil "←→ or AD to move, ~A/F to fire, ~A pause, ~A quit"
             (invaders-bold "SPACE")
             (invaders-bold "ESC")
             (invaders-bold "Q")))))

(defun invaders-border (left right)
  (invaders-dim
   (format nil "~A~A~A"
           left
           (make-string +invaders-width+ :initial-element #\─)
           right)))

(defun invaders-board-line (state y)
  (with-output-to-string (output)
    (write-string (invaders-dim " │") output)
    (loop for x below +invaders-width+
          do (write-string (invaders-cell state x y) output))
    (write-string (invaders-dim "│") output)))

(defmethod cadr-tui:component-render
    ((component space-invaders-component) width &key focused-p)
  (declare (ignore focused-p))
  (sb-thread:with-mutex ((space-invaders-lock component))
    (let* ((state (space-invaders-live-state component))
           (footer (invaders-footer component state)))
      (mapcar (lambda (line) (invaders-pad-line line width))
              (append
               (list (invaders-border " ╭" "╮")
                     (invaders-box-line (invaders-header state))
                     (invaders-border " ├" "┤"))
               (loop for y below +invaders-height+
                     collect (invaders-board-line state y))
               (list (invaders-border " ├" "┤")
                     (invaders-box-line footer)
                     (invaders-border " ╰" "╯")))))))

(defun invaders-event-key-p (event key-id)
  (let ((text (or (cadr-tui:input-event-text event) "")))
    (or (cadr-tui:matches-key text key-id)
        (string-equal text key-id))))

(defmethod cadr-tui:component-handle-event
    ((component space-invaders-component) event)
  (let* ((release-p (eq (cadr-tui:input-event-kind event) :key-release))
         (text (or (cadr-tui:input-event-text event) ""))
         (state (space-invaders-live-state component)))
    (cond
      ((and (space-invaders-paused-p component) (not release-p)
            (not (member (cadr-tui:input-event-kind event)
                         '(:escape :cancel :interrupt))))
       (setf (space-invaders-paused-p component) nil)
       (space-invaders-start component))
      ((and (not release-p)
            (member (cadr-tui:input-event-kind event)
                    '(:escape :cancel :interrupt)))
       (funcall (space-invaders-save component) (invaders-state-to-data state))
       (space-invaders-stop component)
       (funcall (space-invaders-done component) nil))
      ((and (not release-p) (member text '("q" "Q") :test #'string=))
       (funcall (space-invaders-save component) nil)
       (space-invaders-stop component)
       (funcall (space-invaders-done component) nil))
      ((and (not release-p)
            (or (invaders-state-game-over-p state)
                (invaders-state-victory-p state))
            (member text '("r" "R" " ") :test #'string=))
       (let ((next-level (if (invaders-state-victory-p state)
                             (1+ (invaders-state-level state)) 1)))
         (space-invaders-bind-live-state
          component
          (make-initial-invaders-state
           :high-score (invaders-state-high-score state)
           :level next-level))
         (funcall (space-invaders-save component) nil)))
      (t
       (when (or (eq (cadr-tui:input-event-kind event) :left)
                 (invaders-event-key-p event "a"))
         (setf (getf (space-invaders-keys component) :left) (not release-p)))
       (when (or (eq (cadr-tui:input-event-kind event) :right)
                 (invaders-event-key-p event "d"))
         (setf (getf (space-invaders-keys component) :right) (not release-p)))
       (when (or (string= text " ") (invaders-event-key-p event "f"))
         (setf (getf (space-invaders-keys component) :fire) (not release-p))))))
  (values nil nil))

(defmethod cadr-tui:component-dispose ((component space-invaders-component))
  (space-invaders-stop component))

(defun invaders-saved-state (context)
  (loop for entry in (reverse (or (example-session-entries context) nil))
        when (and (eq (cadr-agent:session-entry-type entry) :custom)
                  (string= (or (cadr-agent:session-entry-custom-type entry) "")
                           +invaders-save-type+))
          return (invaders-state-from-data (cadr-agent:session-entry-data entry))))

(cadr-agent:define-command
 "invaders"
 :description "Play Space Invaders!"
 :handler
 (lambda (arguments context)
   (declare (ignore arguments))
   (if (not (cadr-agent:extension-context-has-ui-p context))
       (cadr-agent:extension-context-notify
        context "Space Invaders requires interactive mode" :level :error)
       (let ((saved (invaders-saved-state context)))
         (cadr-agent:extension-context-custom-component
          context
          (lambda (tui theme keybindings done)
            (declare (ignore theme keybindings))
            (let* ((state (or saved (make-initial-invaders-state)))
                   (component
                     (make-instance
                      'space-invaders-component
                      :state state
                      :paused-p (and saved
                                     (not (invaders-state-game-over-p saved))
                                     (not (invaders-state-victory-p saved)))
                      :tui tui :done done
                      :save (lambda (data)
                              (cadr-agent:extension-api-append-entry
                               *example-api* +invaders-save-type+ data)))))
              (space-invaders-bind-live-state component state)
              (unless (space-invaders-paused-p component)
                (space-invaders-start component))
              component)))))))
