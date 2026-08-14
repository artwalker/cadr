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

(defmethod cadr-tui:component-wants-key-release-p
    ((component space-invaders-component))
  (declare (ignore component))
  t)

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
                          (sb-thread:with-mutex ((space-invaders-lock component))
                            (invaders-tick (space-invaders-state component)
                                           (space-invaders-keys component)))
                          (cadr-tui:tui-request-render
                           (space-invaders-tui component)))))
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

(defun invaders-cell (state x y)
  (let ((alien
          (find-if
           (lambda (candidate)
             (and (invader-alive-p candidate)
                  (= y (invader-y candidate))
                  (<= (abs (- x (invader-x candidate))) 1)))
           (invaders-state-aliens state))))
    (cond
      (alien (if (= x (invader-x alien)) "◆" (if (< x (invader-x alien)) "╱" "╲")))
      ((and (= y +invaders-player-y+)
            (<= (abs (- x (invaders-state-player-x state))) 1))
       (if (= x (invaders-state-player-x state)) "▲" "═"))
      ((find-if (lambda (bullet)
                  (and (= x (invader-bullet-x bullet))
                       (= y (invader-bullet-y bullet))))
                (invaders-state-bullets state)) "│")
      ((some
        (lambda (shield)
          (let ((relative-x (- x (invader-shield-x shield)))
                (relative-y (- y (- +invaders-player-y+ 5))))
            (and (<= 0 relative-x 3) (<= 0 relative-y 2)
                 (aref (aref (invader-shield-segments shield) relative-y)
                       relative-x))))
        (invaders-state-shields state)) "█")
      (t " "))))

(defmethod cadr-tui:component-render
    ((component space-invaders-component) width &key focused-p)
  (declare (ignore width focused-p))
  (sb-thread:with-mutex ((space-invaders-lock component))
    (let* ((state (space-invaders-state component))
           (footer
             (cond
               ((space-invaders-paused-p component) "PAUSED · any key resumes · Q quits")
               ((invaders-state-game-over-p state) "GAME OVER · R restarts · Q quits")
               ((invaders-state-victory-p state)
                (format nil "VICTORY · R starts level ~D · Q quits"
                        (1+ (invaders-state-level state))))
               (t "←→/AD move · SPACE/F fire · ESC saves · Q quits"))))
      (append
       (list (format nil " ╭~A╮" (make-string +invaders-width+ :initial-element #\─))
             (format nil " │SPACE INVADERS · Score ~D · Hi ~D · Lv ~D · Lives ~D│"
                     (invaders-state-score state)
                     (invaders-state-high-score state)
                     (invaders-state-level state)
                     (invaders-state-lives state))
             (format nil " ├~A┤" (make-string +invaders-width+ :initial-element #\─)))
       (loop for y below +invaders-height+
             collect
             (with-output-to-string (output)
               (write-string " │" output)
               (loop for x below +invaders-width+
                     do (write-string (invaders-cell state x y) output))
               (write-string "│" output)))
       (list (format nil " ├~A┤" (make-string +invaders-width+ :initial-element #\─))
             (format nil " │~VA│" +invaders-width+ footer)
             (format nil " ╰~A╯" (make-string +invaders-width+ :initial-element #\─)))))))

(defun invaders-event-key-p (event key-id)
  (let ((text (or (cadr-tui:input-event-text event) "")))
    (or (cadr-tui:matches-key text key-id)
        (string-equal text key-id))))

(defmethod cadr-tui:component-handle-event
    ((component space-invaders-component) event)
  (let* ((release-p (eq (cadr-tui:input-event-kind event) :key-release))
         (text (or (cadr-tui:input-event-text event) ""))
         (state (space-invaders-state component)))
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
         (setf (space-invaders-state component)
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
            (let ((component
                    (make-instance
                     'space-invaders-component
                     :state (or saved (make-initial-invaders-state))
                     :paused-p (and saved
                                    (not (invaders-state-game-over-p saved))
                                    (not (invaders-state-victory-p saved)))
                     :tui tui :done done
                     :save (lambda (data)
                             (cadr-agent:extension-api-append-entry
                              *example-api* +invaders-save-type+ data)))))
              (unless (space-invaders-paused-p component)
                (space-invaders-start component))
              component)))))))
