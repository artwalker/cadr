(load (merge-pathnames "support.lisp" *load-truename*))

(defconstant +tic-tac-toe-save-type+ "tic-tac-toe-save")
(defconstant +tic-tac-toe-move-type+ "tic-tac-toe-move")
(defconstant +tic-tac-toe-game-over-type+ "tic-tac-toe-game-over")

(defstruct tic-tac-toe-state
  (board (make-array '(3 3) :initial-element #\Space))
  (user-row 1) (user-column 1)
  (agent-row 0) (agent-column 0)
  (status :playing)
  (current-turn #\X))

(defvar *tic-tac-toe-state* (make-tic-tac-toe-state))
(defvar *tic-tac-toe-component* nil)
(defvar *tic-tac-toe-active-p* nil)

(defun tic-tac-toe-winning-line (board)
  (find-if
   (lambda (line)
     (destructuring-bind ((r0 c0) (r1 c1) (r2 c2)) line
       (let ((value (aref board r0 c0)))
         (and (not (char= value #\Space))
              (char= value (aref board r1 c1))
              (char= value (aref board r2 c2))))))
   '(((0 0) (0 1) (0 2)) ((1 0) (1 1) (1 2)) ((2 0) (2 1) (2 2))
     ((0 0) (1 0) (2 0)) ((0 1) (1 1) (2 1)) ((0 2) (1 2) (2 2))
     ((0 0) (1 1) (2 2)) ((0 2) (1 1) (2 0)))))

(defun tic-tac-toe-status (board)
  (let ((line (tic-tac-toe-winning-line board)))
    (cond
      (line (if (char= (aref board (caar line) (cadar line)) #\X)
                :win-x :win-o))
      ((loop for row below 3 always
             (loop for column below 3 always
                   (not (char= (aref board row column) #\Space))))
       :draw)
      (t :playing))))

(defun tic-tac-toe-board-data (state)
  (list
   :board (loop for row below 3 collect
                (loop for column below 3
                      collect (string (aref (tic-tac-toe-state-board state)
                                            row column))))
   :agent-row (tic-tac-toe-state-agent-row state)
   :agent-column (tic-tac-toe-state-agent-column state)
   :status (tic-tac-toe-state-status state)
   :current-turn (string (tic-tac-toe-state-current-turn state))))

(defun tic-tac-toe-state-from-data (data)
  (when (and (listp data) (getf data :board))
    (let ((state (make-tic-tac-toe-state)))
      (loop for row-data in (getf data :board)
            for row below 3
            do (loop for value in row-data
                     for column below 3
                     do (setf (aref (tic-tac-toe-state-board state) row column)
                              (if (and (stringp value) (plusp (length value)))
                                  (char value 0) #\Space))))
      (setf (tic-tac-toe-state-agent-row state) (or (getf data :agent-row) 0)
            (tic-tac-toe-state-agent-column state) (or (getf data :agent-column) 0)
            (tic-tac-toe-state-status state) (or (getf data :status) :playing)
            (tic-tac-toe-state-current-turn state)
            (let ((value (getf data :current-turn)))
              (if (and (stringp value) (plusp (length value)))
                  (char value 0) #\X)))
      state)))

(defun tic-tac-toe-board-ascii (state)
  (with-output-to-string (output)
    (loop for row below 3
          do
          (loop for column below 3
                for value = (aref (tic-tac-toe-state-board state) row column)
                for cursor-p = (and (= row (tic-tac-toe-state-agent-row state))
                                    (= column (tic-tac-toe-state-agent-column state)))
                do (format output "~A~:[~A~;[~A]~]~A"
                           (if (zerop column) "" "|")
                           cursor-p
                           (if (char= value #\Space)
                               (format nil "~D,~D" row column)
                               (string value))
                           (if (= column 2) "" "")))
          unless (= row 2) do (format output "~%-----+-----+-----~%"))))

(defun tic-tac-toe-save ()
  (cadr-agent:extension-api-append-entry
   *example-api* +tic-tac-toe-save-type+
   (tic-tac-toe-board-data *tic-tac-toe-state*)))

(defun tic-tac-toe-send-game-over ()
  (let ((label
          (ecase (tic-tac-toe-state-status *tic-tac-toe-state*)
            (:win-x "Player X (human) wins")
            (:win-o "Player O (agent) wins")
            (:draw "Draw"))))
    (cadr-agent:extension-api-send-message
     *example-api*
     (list :custom-type +tic-tac-toe-game-over-type+
           :content (format nil "Game over: ~A." label)
           :display-p t
           :details (tic-tac-toe-board-data *tic-tac-toe-state*)))))

(defun tic-tac-toe-reconstruct (context)
  (setf *tic-tac-toe-state* (make-tic-tac-toe-state)
        *tic-tac-toe-active-p* nil)
  (dolist (entry (or (example-session-branch context) nil))
    (when (and (eq (cadr-agent:session-entry-type entry) :custom)
               (string= (or (cadr-agent:session-entry-custom-type entry) "")
                        +tic-tac-toe-save-type+))
      (let ((restored
              (tic-tac-toe-state-from-data
               (cadr-agent:session-entry-data entry))))
        (when restored (setf *tic-tac-toe-state* restored)))))
  *tic-tac-toe-state*)

(defclass tic-tac-toe-board-component (cadr-tui:component)
  ((state :initarg :state :reader tic-tac-toe-component-state)
   (agent-view-p :initarg :agent-view-p :initform nil
                 :reader tic-tac-toe-component-agent-view-p)
   (done :initarg :done :initform nil :reader tic-tac-toe-component-done)
   (on-play :initarg :on-play :initform nil :reader tic-tac-toe-component-on-play)))

(defmethod cadr-tui:component-render
    ((component tic-tac-toe-board-component) width &key focused-p)
  (declare (ignore width focused-p))
  (let* ((state (tic-tac-toe-component-state component))
         (board (tic-tac-toe-state-board state))
         (cursor-row (if (tic-tac-toe-component-agent-view-p component)
                         (tic-tac-toe-state-agent-row state)
                         (tic-tac-toe-state-user-row state)))
         (cursor-column (if (tic-tac-toe-component-agent-view-p component)
                            (tic-tac-toe-state-agent-column state)
                            (tic-tac-toe-state-user-column state))))
    (append
     (list (format nil "TIC-TAC-TOE · ~A"
                   (ecase (tic-tac-toe-state-status state)
                     (:playing
                      (if (char= (tic-tac-toe-state-current-turn state) #\X)
                          "Your turn (X)" "Agent turn (O)"))
                     (:win-x "Player X wins") (:win-o "Player O wins")
                     (:draw "Draw")))
           "")
     (loop for row below 3 append
           (list
            (format nil " ~{~A~^ │ ~}"
                    (loop for column below 3
                          for value = (aref board row column)
                          collect
                          (format nil "~:[ ~;>~]~A~:[ ~; <~]"
                                  (and (= row cursor-row) (= column cursor-column))
                                  (if (char= value #\Space) "·" (string value))
                                  (and (= row cursor-row) (= column cursor-column)))))
            (if (= row 2) "" "───┼───┼───")))
     (unless (tic-tac-toe-component-agent-view-p component)
       (list "arrows move · enter plays · escape closes")))))

(defmethod cadr-tui:component-handle-event
    ((component tic-tac-toe-board-component) event)
  (let ((state (tic-tac-toe-component-state component)))
    (case (cadr-tui:input-event-kind event)
      (:up (setf (tic-tac-toe-state-user-row state)
                 (max 0 (1- (tic-tac-toe-state-user-row state)))))
      (:down (setf (tic-tac-toe-state-user-row state)
                   (min 2 (1+ (tic-tac-toe-state-user-row state)))))
      (:left (setf (tic-tac-toe-state-user-column state)
                   (max 0 (1- (tic-tac-toe-state-user-column state)))))
      (:right (setf (tic-tac-toe-state-user-column state)
                    (min 2 (1+ (tic-tac-toe-state-user-column state)))))
      (:enter
       (when (and (eq (tic-tac-toe-state-status state) :playing)
                  (char= (tic-tac-toe-state-current-turn state) #\X)
                  (char= (aref (tic-tac-toe-state-board state)
                               (tic-tac-toe-state-user-row state)
                               (tic-tac-toe-state-user-column state)) #\Space)
                  (tic-tac-toe-component-on-play component))
         (funcall (tic-tac-toe-component-on-play component)
                  (tic-tac-toe-state-user-row state)
                  (tic-tac-toe-state-user-column state))))
      ((:escape :cancel :interrupt)
       (when (tic-tac-toe-component-done component)
         (funcall (tic-tac-toe-component-done component) nil)))))
  (values nil nil))

(cadr-agent:define-component-message-renderer
 +tic-tac-toe-move-type+
 :renderer
 (lambda (message options theme)
   (declare (ignore theme))
   (let ((state (or (tic-tac-toe-state-from-data (getf message :details))
                    *tic-tac-toe-state*)))
     (if (getf options :expanded-p)
         (make-instance 'tic-tac-toe-board-component
                        :state state :agent-view-p t)
         (cadr-tui:make-text-component
          "Player X played → next: O (Agent)" :padding-x 0 :padding-y 0)))))

(cadr-agent:define-component-message-renderer
 +tic-tac-toe-game-over-type+
 :renderer
 (lambda (message options theme)
   (declare (ignore options theme))
   (make-instance
    'tic-tac-toe-board-component
    :state (or (tic-tac-toe-state-from-data (getf message :details))
               *tic-tac-toe-state*)
    :agent-view-p t)))

(dolist (event-type '(:session-start :session-tree))
  (cadr-agent:define-event-hook
   event-type
   :handler
   (lambda (event context)
     (declare (ignore event))
     (tic-tac-toe-reconstruct context))))

(cadr-agent:define-event-hook
 :before-agent-start
 :handler
 (lambda (event context)
   (declare (ignore context))
   (when *tic-tac-toe-active-p*
     (list
      :system-prompt
      (format nil
              "~A~%~%## Tic-Tac-Toe (you are Player O)~%Use tic_tac_toe for exactly one move action per call. Emit all cursor moves and the final play as separate tool calls in the same response. Use tic_tac_toe_see_board to inspect state."
              (or (example-event-value event :system-prompt) ""))))))

(cadr-agent:define-command
 "tic-tac-toe"
 :description "Play tic-tac-toe against the agent"
 :handler
 (lambda (arguments context)
   (declare (ignore arguments))
   (if (not (cadr-agent:extension-context-has-ui-p context))
       (cadr-agent:extension-context-notify
        context "Tic-tac-toe requires interactive mode" :level :error)
       (progn
         (tic-tac-toe-reconstruct context)
         (unless (eq (tic-tac-toe-state-status *tic-tac-toe-state*) :playing)
           (setf *tic-tac-toe-state* (make-tic-tac-toe-state)))
         (setf *tic-tac-toe-active-p* t)
         (cadr-agent:extension-context-set-session-name context "Tic-Tac-Toe")
         (cadr-agent:extension-context-custom-component
          context
          (lambda (tui theme keybindings done)
            (declare (ignore tui theme keybindings))
            (setf *tic-tac-toe-component*
                  (make-instance
                   'tic-tac-toe-board-component
                   :state *tic-tac-toe-state* :done done
                   :on-play
                   (lambda (row column)
                     (setf (aref (tic-tac-toe-state-board *tic-tac-toe-state*)
                                 row column) #\X
                           (tic-tac-toe-state-status *tic-tac-toe-state*)
                           (tic-tac-toe-status
                            (tic-tac-toe-state-board *tic-tac-toe-state*)))
                     (tic-tac-toe-save)
                     (if (eq (tic-tac-toe-state-status *tic-tac-toe-state*) :playing)
                         (progn
                           (setf (tic-tac-toe-state-current-turn *tic-tac-toe-state*) #\O)
                           (cadr-agent:extension-api-send-message
                            *example-api*
                            (list
                             :custom-type +tic-tac-toe-move-type+
                             :content
                             (format nil
                                     "Player X played at (row=~D, col=~D). It is now Player O's turn.~%~%Board (your cursor marked with <>):~%~A"
                                     row column
                                     (tic-tac-toe-board-ascii *tic-tac-toe-state*))
                             :display-p t
                             :details (tic-tac-toe-board-data *tic-tac-toe-state*))
                            :trigger-turn-p t))
                         (progn
                           (setf *tic-tac-toe-active-p* nil)
                           (tic-tac-toe-send-game-over))))))))))))

(defun tic-tac-toe-action (action)
  (let ((state *tic-tac-toe-state*))
    (cond
      ((string= action "move_up")
       (setf (tic-tac-toe-state-agent-row state)
             (max 0 (1- (tic-tac-toe-state-agent-row state))))
       (format nil "Moved up. Cursor: (~D, ~D)"
               (tic-tac-toe-state-agent-row state)
               (tic-tac-toe-state-agent-column state)))
      ((string= action "move_down")
       (setf (tic-tac-toe-state-agent-row state)
             (min 2 (1+ (tic-tac-toe-state-agent-row state))))
       (format nil "Moved down. Cursor: (~D, ~D)"
               (tic-tac-toe-state-agent-row state)
               (tic-tac-toe-state-agent-column state)))
      ((string= action "move_left")
       (setf (tic-tac-toe-state-agent-column state)
             (max 0 (1- (tic-tac-toe-state-agent-column state))))
       (format nil "Moved left. Cursor: (~D, ~D)"
               (tic-tac-toe-state-agent-row state)
               (tic-tac-toe-state-agent-column state)))
      ((string= action "move_right")
       (setf (tic-tac-toe-state-agent-column state)
             (min 2 (1+ (tic-tac-toe-state-agent-column state))))
       (format nil "Moved right. Cursor: (~D, ~D)"
               (tic-tac-toe-state-agent-row state)
               (tic-tac-toe-state-agent-column state)))
      ((string= action "play")
       (unless (eq (tic-tac-toe-state-status state) :playing)
         (error "Game is over (~(~A~))." (tic-tac-toe-state-status state)))
       (unless (char= (tic-tac-toe-state-current-turn state) #\O)
         (error "It is not your turn."))
       (let ((row (tic-tac-toe-state-agent-row state))
             (column (tic-tac-toe-state-agent-column state)))
         (unless (char= (aref (tic-tac-toe-state-board state) row column)
                        #\Space)
           (error "Cell (~D,~D) is already ~A. Your cursor is still at (~D,~D)."
                  row column (aref (tic-tac-toe-state-board state) row column)
                  row column))
         (setf (aref (tic-tac-toe-state-board state) row column) #\O
               (tic-tac-toe-state-status state)
               (tic-tac-toe-status (tic-tac-toe-state-board state))
               (tic-tac-toe-state-agent-row state) 0
               (tic-tac-toe-state-agent-column state) 0)
         (if (eq (tic-tac-toe-state-status state) :playing)
             (progn
               (setf (tic-tac-toe-state-current-turn state) #\X)
               (format nil "Placed O at (~D,~D). Cursor reset to (0,0). Your turn, X!"
                       row column))
             (progn
               (setf *tic-tac-toe-active-p* nil)
               (tic-tac-toe-send-game-over)
               (format nil "Placed O at (~D,~D). ~A"
                       row column
                       (if (eq (tic-tac-toe-state-status state) :win-o)
                           "Player O wins!" "It's a draw!"))))))
      (t (error "Unknown tic-tac-toe action: ~A" action)))))

(cadr-agent:define-rich-tool
 "tic_tac_toe"
 :label "Tic-Tac-Toe"
 :description "Execute one move_up, move_down, move_left, move_right, or play action as Player O"
 :prompt-snippet "Play one tic-tac-toe action as Player O"
 :prompt-guidelines
 '("Emit every cursor move and the final play in one assistant response as separate calls.")
 :parameters
 (example-object-schema "action" "string" "One atomic tic-tac-toe action")
 :execution-mode :sequential
 :handler
 (lambda (call-id arguments signal on-update context)
   (declare (ignore call-id signal on-update context))
   (let ((action (example-argument arguments "action" "")))
     (when (member action '("move_up" "move_down" "move_left" "move_right")
                   :test #'string=)
       (sleep 0.3))
     (let ((result (tic-tac-toe-action action)))
       (tic-tac-toe-save)
       (values result (tic-tac-toe-board-data *tic-tac-toe-state*) nil)))))

(cadr-agent:define-rich-tool
 "tic_tac_toe_see_board"
 :label "See Board"
 :description "Return the current board and Player O cursor"
 :prompt-snippet "Inspect the tic-tac-toe board and your cursor"
 :parameters (example-empty-schema)
 :handler
 (lambda (call-id arguments signal on-update context)
   (declare (ignore call-id arguments signal on-update context))
   (values
    (format nil
            "Board (your cursor marked with <>):~%~A~%~%Your cursor: (row=~D, col=~D)~%Status: ~(~A~)~%Turn: ~A"
            (tic-tac-toe-board-ascii *tic-tac-toe-state*)
            (tic-tac-toe-state-agent-row *tic-tac-toe-state*)
            (tic-tac-toe-state-agent-column *tic-tac-toe-state*)
            (tic-tac-toe-state-status *tic-tac-toe-state*)
            (if (char= (tic-tac-toe-state-current-turn *tic-tac-toe-state*) #\O)
                "Player O (you)" "Player X"))
    (tic-tac-toe-board-data *tic-tac-toe-state*) nil)))
