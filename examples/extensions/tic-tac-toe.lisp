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
  ;; Baseline boardToAscii (tic-tac-toe.ts:161-176): 9-wide cells,
  ;; agent cursor in <>, empty cells as [r,c], never the user cursor.
  (let ((board (tic-tac-toe-state-board state))
        (agent-row (tic-tac-toe-state-agent-row state))
        (agent-column (tic-tac-toe-state-agent-column state)))
    (with-output-to-string (output)
      (loop for row below 3
            do
            (loop for column below 3
                  for value = (aref board row column)
                  for cursor-p = (and (= row agent-row)
                                      (= column agent-column))
                  do
                  (unless (zerop column)
                    (write-string "|" output))
                  (write-string
                   (cond
                     ((and (char= value #\Space) cursor-p)
                      (format nil "<[~D,~D]>" row column))
                     ((char= value #\Space)
                      (format nil " [~D,~D] " row column))
                     (cursor-p
                      (format nil "   <~A>   " value))
                     (t
                      (format nil "    ~A    " value)))
                   output))
            unless (= row 2)
              do (format output "~%---------+---------+---------~%")))))

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
  (tic-tac-toe-request-render)
  *tic-tac-toe-state*)

(defclass tic-tac-toe-board-component
    (cadr-cli::render-aware-component cadr-tui:component)
  ((state :initarg :state :accessor tic-tac-toe-component-state)
   ;; Baseline BoardOverlayComponent keeps the tui handle so agent-driven
   ;; state changes can repaint (tic-tac-toe.ts:389-393 updateState); the
   ;; user-input repaints are the framework's post-event render, matching
   ;; the requestRender calls at tic-tac-toe.ts:412-420.
   (tui :initarg :tui :initform nil :reader tic-tac-toe-component-tui)
   (agent-view-p :initarg :agent-view-p :initform nil
                 :reader tic-tac-toe-component-agent-view-p)
   (done :initarg :done :initform nil :reader tic-tac-toe-component-done)
   (on-play :initarg :on-play :initform nil :reader tic-tac-toe-component-on-play)))

(defun tic-tac-toe-live-state (component)
  "Live overlay reads the global. Agent-view transcript boards keep the
snapshot they were built with. Reconstruct replaces the global, so a
slot captured at /tic-tac-toe would otherwise keep painting the
pre-O thinking frame."
  (if (tic-tac-toe-component-agent-view-p component)
      (tic-tac-toe-component-state component)
      *tic-tac-toe-state*))

(defun tic-tac-toe-request-render ()
  "Baseline updateState (tic-tac-toe.ts:389-393): point the overlay at
the current global, then request a frame."
  (let ((component *tic-tac-toe-component*))
    (when component
      (unless (tic-tac-toe-component-agent-view-p component)
        (setf (tic-tac-toe-component-state component)
              *tic-tac-toe-state*))
      (let ((request
              (cadr-cli::component-render-request-function
               component)))
        (cond
          ((functionp request)
           (funcall request))
          ((tic-tac-toe-component-tui component)
           (cadr-tui:tui-request-render
            (tic-tac-toe-component-tui component))))))))

(defconstant +tic-tac-toe-cell-width+ 7)
(defconstant +tic-tac-toe-cell-height+ 3)

(defun tic-tac-toe-sgr (code text)
  "Baseline tic-tac-toe.ts paints the cursor and marks with raw SGR, not
theme tokens.  CODE carries its own trailing m (e.g. \"32;1m\"); the format
string must not add another one - the goal 20 P0 stray-m defect came from
exactly that duplication."
  (format nil "~C[~A~A~C[0m" #\Escape code text #\Escape))

(defun tic-tac-toe-dim (text)
  "Baseline DIM() closes with ESC[22m, not ESC[0m (tic-tac-toe.ts:200)."
  (format nil "~C[2m~A~C[22m" #\Escape text #\Escape))

(defun tic-tac-toe-cell-fg (value win-p)
  (cond
    ((char= value #\Space) nil)
    (win-p "32")
    ((char= value #\X) "34")
    (t "33")))

(defun tic-tac-toe-center-pad (content width)
  (let ((content-width (cadr-tui:visible-width content)))
    (cond
      ((>= content-width width)
       (cadr-tui:truncate-to-width content width))
      (t
       (let* ((pad (- width content-width))
              (left (floor pad 2)))
         (concatenate 'string
                      (make-string left :initial-element #\Space)
                      content
                      (make-string (- pad left) :initial-element #\Space)))))))

(defun tic-tac-toe-win-cells (board)
  (let ((line (tic-tac-toe-winning-line board)))
    (and line
         (mapcar (lambda (cell) (cons (first cell) (second cell))) line))))

(defun tic-tac-toe-win-p (win-cells row column)
  (and win-cells (member (cons row column) win-cells :test #'equal)))

(defun tic-tac-toe-border-fg (adjacent)
  (let ((codes
          (remove nil
                  (mapcar
                   (lambda (item)
                     (tic-tac-toe-cell-fg (car item) (cdr item)))
                   adjacent))))
    (cond
      ((null codes) nil)
      ((every (lambda (code) (string= code (first codes))) codes)
       (first codes))
      (t nil))))

(defun tic-tac-toe-paint-border (character highlighted-p fg)
  (cond
    (highlighted-p (tic-tac-toe-sgr "32;1m" character))
    (fg (tic-tac-toe-sgr (format nil "~A;1m" fg) character))
    (t (tic-tac-toe-dim character))))

(defun tic-tac-toe-cell-at (board win-cells row column)
  (cons (aref board row column)
        (tic-tac-toe-win-p win-cells row column)))

(defun tic-tac-toe-build-cell (value line-index win-p)
  (let ((empty (make-string +tic-tac-toe-cell-width+ :initial-element #\Space)))
    (if (or (char= value #\Space)
            (/= line-index (floor +tic-tac-toe-cell-height+ 2)))
        empty
        (let* ((glyph (if (char= value #\X) (string #\BOX_DRAWINGS_LIGHT_DIAGONAL_CROSS)
                          (string #\LARGE_CIRCLE)))
               (fg (tic-tac-toe-cell-fg value win-p))
               (pad (- +tic-tac-toe-cell-width+ (cadr-tui:visible-width glyph)))
               (left (floor pad 2)))
          (concatenate
           'string
           (make-string left :initial-element #\Space)
           (tic-tac-toe-sgr (format nil "~A;1m" fg) glyph)
           (make-string (- pad left) :initial-element #\Space))))))

(defun tic-tac-toe-corner-char (grid-row grid-column)
  (cond
    ((and (zerop grid-row) (zerop grid-column)) (string #\BOX_DRAWINGS_LIGHT_DOWN_AND_RIGHT))
    ((and (zerop grid-row) (= grid-column 3)) (string #\BOX_DRAWINGS_LIGHT_DOWN_AND_LEFT))
    ((and (= grid-row 3) (zerop grid-column)) (string #\BOX_DRAWINGS_LIGHT_UP_AND_RIGHT))
    ((and (= grid-row 3) (= grid-column 3)) (string #\BOX_DRAWINGS_LIGHT_UP_AND_LEFT))
    ((zerop grid-row) (string #\BOX_DRAWINGS_LIGHT_DOWN_AND_HORIZONTAL))
    ((= grid-row 3) (string #\BOX_DRAWINGS_LIGHT_UP_AND_HORIZONTAL))
    ((zerop grid-column) (string #\BOX_DRAWINGS_LIGHT_VERTICAL_AND_RIGHT))
    ((= grid-column 3) (string #\BOX_DRAWINGS_LIGHT_VERTICAL_AND_LEFT))
    (t (string #\BOX_DRAWINGS_LIGHT_VERTICAL_AND_HORIZONTAL))))

(defun tic-tac-toe-cursor-corner-p (show-p cursor-row cursor-column grid-row grid-column)
  (and show-p
       (or (= grid-row cursor-row) (= grid-row (1+ cursor-row)))
       (or (= grid-column cursor-column) (= grid-column (1+ cursor-column)))))

(defun tic-tac-toe-cursor-h-p (show-p cursor-row cursor-column grid-row column)
  (and show-p (= column cursor-column)
       (or (= grid-row cursor-row) (= grid-row (1+ cursor-row)))))

(defun tic-tac-toe-cursor-v-p (show-p cursor-row cursor-column row grid-column)
  (and show-p (= row cursor-row)
       (or (= grid-column cursor-column) (= grid-column (1+ cursor-column)))))

(defun tic-tac-toe-render-visual-board
    (state width &key agent-view-p snapshot-p)
  (let* ((board (tic-tac-toe-state-board state))
         (win-cells (tic-tac-toe-win-cells board))
         (playing-p (eq (tic-tac-toe-state-status state) :playing))
         (user-turn-p (char= (tic-tac-toe-state-current-turn state) #\X))
         (show-cursor-p (and playing-p (not snapshot-p)))
         (cursor-row (cond
                       ((not show-cursor-p) -1)
                       ((or agent-view-p (not user-turn-p))
                        (tic-tac-toe-state-agent-row state))
                       (t (tic-tac-toe-state-user-row state))))
         (cursor-column (cond
                          ((not show-cursor-p) -1)
                          ((or agent-view-p (not user-turn-p))
                           (tic-tac-toe-state-agent-column state))
                          (t (tic-tac-toe-state-user-column state))))
         (cursor-code (if (or agent-view-p (not user-turn-p)) "33;1m" "32;1m"))
         (lines nil))
    (labels
        ((paint (character highlighted-p fg)
           (cond
             (highlighted-p (tic-tac-toe-sgr cursor-code character))
             (fg (tic-tac-toe-sgr (format nil "~A;1m" fg) character))
             (t (tic-tac-toe-dim character))))
         (adjacent-cells (pairs)
           (loop for (row column) in pairs
                 when (and (<= 0 row 2) (<= 0 column 2))
                   collect (tic-tac-toe-cell-at board win-cells row column))))
      (loop for grid-row from 0 to 3
            do
            (push
             (tic-tac-toe-center-pad
              (with-output-to-string (out)
                (loop for grid-column from 0 to 3
                      do
                      (write-string
                       (paint
                        (tic-tac-toe-corner-char grid-row grid-column)
                        (tic-tac-toe-cursor-corner-p
                         show-cursor-p cursor-row cursor-column
                         grid-row grid-column)
                        (tic-tac-toe-border-fg
                         (adjacent-cells
                          (list (list (1- grid-row) (1- grid-column))
                                (list (1- grid-row) grid-column)
                                (list grid-row (1- grid-column))
                                (list grid-row grid-column)))))
                       out)
                      (when (< grid-column 3)
                        (write-string
                         (paint
                          (make-string +tic-tac-toe-cell-width+
                                       :initial-element
                                       #\BOX_DRAWINGS_LIGHT_HORIZONTAL)
                          (tic-tac-toe-cursor-h-p
                           show-cursor-p cursor-row cursor-column
                           grid-row grid-column)
                          (tic-tac-toe-border-fg
                           (adjacent-cells
                            (list (list (1- grid-row) grid-column)
                                  (list grid-row grid-column)))))
                         out))))
              width)
             lines)
            (when (< grid-row 3)
              (loop for line-index below +tic-tac-toe-cell-height+
                    do
                    (push
                     (tic-tac-toe-center-pad
                      (with-output-to-string (out)
                        (loop for grid-column from 0 to 3
                              do
                              (write-string
                               (paint
                                (string #\BOX_DRAWINGS_LIGHT_VERTICAL)
                                (tic-tac-toe-cursor-v-p
                                 show-cursor-p cursor-row cursor-column
                                 grid-row grid-column)
                                (tic-tac-toe-border-fg
                                 (adjacent-cells
                                  (list (list grid-row (1- grid-column))
                                        (list grid-row grid-column)))))
                               out)
                              (when (< grid-column 3)
                                (write-string
                                 (tic-tac-toe-build-cell
                                  (aref board grid-row grid-column)
                                  line-index
                                  (tic-tac-toe-win-p
                                   win-cells grid-row grid-column))
                                 out))))
                      width)
                     lines)))))
    (nreverse lines)))

(defmethod cadr-tui:component-render
    ((component tic-tac-toe-board-component) width &key focused-p)
  (declare (ignore focused-p))
  ;; Overlay chrome follows tic-tac-toe.ts:443-500 byte for byte.  The
  ;; overlay-local helpers there all close with ESC[0m (unlike the board's
  ;; DIM, which closes with ESC[22m), which is exactly what
  ;; tic-tac-toe-sgr produces: dim rules around a bold blue title banner,
  ;; a center-padded status line, the board, a center-padded footer, and a
  ;; dim full-width separator.
  (let* ((state (tic-tac-toe-live-state component))
         (status (tic-tac-toe-state-status state))
         (user-turn-p (char= (tic-tac-toe-state-current-turn state) #\X))
         (title-text " Tic-Tac-Toe ")
         (border-length
           (max 0 (- width (cadr-tui:visible-width title-text))))
         (left-border (floor border-length 2))
         (title
           (format nil "~A~A~A"
                   (tic-tac-toe-sgr
                    "2m" (make-string left-border :initial-element #\─))
                   (tic-tac-toe-sgr "1m" (tic-tac-toe-sgr "34m" title-text))
                   (tic-tac-toe-sgr
                    "2m" (make-string (- border-length left-border)
                                      :initial-element #\─))))
         (status-line
           (ecase status
             (:playing
              (if user-turn-p
                  (format nil "Turn: ~A (You)  ~A  ~A (Agent)"
                          (tic-tac-toe-sgr "1m" (tic-tac-toe-sgr "34m" "X"))
                          (tic-tac-toe-sgr "2m" "|")
                          (tic-tac-toe-sgr "1m" (tic-tac-toe-sgr "33m" "O")))
                  (format nil "~A (You)  ~A  Turn: ~A (Agent)"
                          (tic-tac-toe-sgr "34m" "X")
                          (tic-tac-toe-sgr "2m" "|")
                          (tic-tac-toe-sgr "1m" (tic-tac-toe-sgr "33m" "O")))))
             (:win-x (tic-tac-toe-sgr "1m" (tic-tac-toe-sgr "32m" "X wins!")))
             (:win-o (tic-tac-toe-sgr "1m" (tic-tac-toe-sgr "33m" "O wins!")))
             (:draw (tic-tac-toe-sgr "1m" (tic-tac-toe-sgr "33m" "Draw!")))))
         (footer
           (cond
             ((not (eq status :playing))
              (format nil "~A restart  ~A  ~A/~A quit"
                      (tic-tac-toe-sgr "1m" "R")
                      (tic-tac-toe-sgr "2m" "|")
                      (tic-tac-toe-sgr "1m" "Q")
                      (tic-tac-toe-sgr "1m" "ESC")))
             ((not user-turn-p)
              (tic-tac-toe-sgr "2m" "Agent is thinking..."))
             (t
              (format nil "~A move  ~A  ~A play  ~A  ~A quit"
                      (tic-tac-toe-sgr "1m" "←↑↓→")
                      (tic-tac-toe-sgr "2m" "|")
                      (tic-tac-toe-sgr "1m" "ENTER")
                      (tic-tac-toe-sgr "2m" "|")
                      (tic-tac-toe-sgr "1m" "ESC"))))))
    (append
     (list title "" (tic-tac-toe-center-pad status-line width) "" "")
     (tic-tac-toe-render-visual-board
      state width
      :agent-view-p (tic-tac-toe-component-agent-view-p component))
     (list "" "")
     (unless (tic-tac-toe-component-agent-view-p component)
       (list (tic-tac-toe-center-pad footer width)))
     (list ""
           (tic-tac-toe-sgr
            "2m" (make-string width :initial-element #\─))))))

(defmethod cadr-tui:component-handle-event
    ((component tic-tac-toe-board-component) event)
  (let ((state (tic-tac-toe-live-state component)))
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

(defun tic-tac-toe-theme-fg (theme token text)
  (let ((fg (getf theme :fg)))
    (if (functionp fg)
        (funcall fg token text)
        text)))

(defun tic-tac-toe-theme-bold (theme text)
  (let ((bold (getf theme :bold)))
    (if (functionp bold)
        (funcall bold text)
        text)))

(defclass tic-tac-toe-banner-message (cadr-tui:component)
  ((title :initarg :title :reader tic-tac-toe-banner-title)
   (details :initarg :details :reader tic-tac-toe-banner-details)
   (expanded-p :initarg :expanded-p :initform nil
               :reader tic-tac-toe-banner-expanded-p)
   (theme :initarg :theme :initform nil
          :reader tic-tac-toe-banner-theme)))

(defun tic-tac-toe-move-banner-title (details theme)
  "Baseline BannerMessageComponent title (tic-tac-toe.ts:685-692)."
  (let* ((turn (or (getf details :current-turn) "O"))
         (agent-p (string= turn "O"))
         (turn-label
           (format nil "~A (~A)"
                   (tic-tac-toe-theme-fg
                    theme
                    (if agent-p :warning :accent)
                    (tic-tac-toe-theme-bold theme (if agent-p "O" "X")))
                   (if agent-p "Agent" "You"))))
    (format nil "~A  ~A  next: ~A"
            (tic-tac-toe-theme-fg
             theme :accent
             (tic-tac-toe-theme-bold theme "Player X played"))
            (tic-tac-toe-theme-fg theme :dim "→")
            turn-label)))

(defmethod cadr-tui:component-render
    ((component tic-tac-toe-banner-message) width &key focused-p)
  (declare (ignore focused-p))
  (let* ((theme (tic-tac-toe-banner-theme component))
         (title (tic-tac-toe-banner-title component))
         (title-width (cadr-tui:visible-width title))
         (fill (max 0 (- width title-width 2)))
         (left (floor fill 2))
         (right (- fill left))
         (rule (lambda (n)
                 (tic-tac-toe-theme-fg
                  theme :dim
                  (make-string n :initial-element #\─))))
         (lines
           (list
            (format nil "~A ~A ~A"
                    (funcall rule left) title (funcall rule right)))))
    (if (and (tic-tac-toe-banner-expanded-p component)
             (tic-tac-toe-banner-details component))
        (let ((state
                (or (tic-tac-toe-state-from-data
                     (tic-tac-toe-banner-details component))
                    *tic-tac-toe-state*)))
          (append
           lines
           (list "")
           (tic-tac-toe-render-visual-board
            state width :snapshot-p t)))
        lines)))

(cadr-agent:define-component-message-renderer
 +tic-tac-toe-move-type+
 :renderer
 (lambda (message options theme)
   (let ((details (getf message :details)))
     (make-instance
      'tic-tac-toe-banner-message
      :title (tic-tac-toe-move-banner-title details theme)
      :details details
      :expanded-p (getf options :expanded-p)
      :theme theme))))

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
     (tic-tac-toe-reconstruct context)
     nil)))

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
            (declare (ignore theme keybindings))
            (setf *tic-tac-toe-component*
                  (make-instance
                   'tic-tac-toe-board-component
                   :state *tic-tac-toe-state* :tui tui :done done
                   :on-play
                   (lambda (row column)
                     (tic-tac-toe-apply-user-play row column))))))))))

(defun tic-tac-toe-user-play-content (row column)
  "Baseline tic-tac-toe.ts:823-827: cursor plus THIS-response move_*+play."
  (format
   nil
   "Player X played at (row=~D, col=~D). It is now Player O's turn.~%~%Board (your cursor marked with <>):~%~A~%~%Your cursor is at (row=~D, col=~D). Decide your target cell, then emit every move_* and the final play as separate tic_tac_toe tool calls in THIS response."
   row column
   (tic-tac-toe-board-ascii *tic-tac-toe-state*)
   (tic-tac-toe-state-agent-row *tic-tac-toe-state*)
   (tic-tac-toe-state-agent-column *tic-tac-toe-state*)))

(defun tic-tac-toe-apply-user-play (row column)
  "Place X, flip the turn, then trigger O. Restore the cell if send fails."
  (let* ((state *tic-tac-toe-state*)
         (board (tic-tac-toe-state-board state))
         (previous-cell (aref board row column))
         (previous-status (tic-tac-toe-state-status state))
         (previous-turn (tic-tac-toe-state-current-turn state))
         (previous-active *tic-tac-toe-active-p*))
    (setf (aref board row column) #\X
          (tic-tac-toe-state-status state) (tic-tac-toe-status board))
    ;; Baseline tic-tac-toe.ts:805-809 flips the turn (or ends the
    ;; game) before persisting the save entry.
    (if (eq (tic-tac-toe-state-status state) :playing)
        (setf (tic-tac-toe-state-current-turn state) #\O)
        (setf *tic-tac-toe-active-p* nil))
    (tic-tac-toe-save)
    (handler-case
        (if (eq (tic-tac-toe-state-status state) :playing)
            (cadr-agent:extension-api-send-message
             *example-api*
             (list
              :custom-type +tic-tac-toe-move-type+
              :content (tic-tac-toe-user-play-content row column)
              :display-p t
              :details (tic-tac-toe-board-data state))
             :trigger-turn-p t)
            (tic-tac-toe-send-game-over))
      (error (condition)
        (setf (aref board row column) previous-cell
              (tic-tac-toe-state-status state) previous-status
              (tic-tac-toe-state-current-turn state) previous-turn
              *tic-tac-toe-active-p* previous-active)
        (tic-tac-toe-save)
        (tic-tac-toe-request-render)
        (error condition)))))

(defun tic-tac-toe-render-call (arguments theme context)
  ;; Host rich path: (arguments theme context)
  ;; (rendering.lisp:197). Baseline renderCall (tic-tac-toe.ts:950-952)
  ;; is toolTitle+bold name and muted action.
  (declare (ignore context))
  (concatenate
   'string
   (tic-tac-toe-theme-fg
    theme :tool-title
    (tic-tac-toe-theme-bold theme "tic_tac_toe "))
   (tic-tac-toe-theme-fg
    theme :muted
    (or (example-argument arguments "action") ""))))

(defun tic-tac-toe-render-result (result options theme context)
  ;; Host rich path: (result options theme context)
  ;; (rendering.lisp:230). Baseline renderResult (tic-tac-toe.ts:955-966):
  ;; check/cross + muted text; expanded + details → banner.
  (let* ((text (example-tool-result-text result))
         (error-p
           (or (getf context :is-error-p)
               (getf context :is-error)
               (and (typep result 'cadr-ai:tool-result-message)
                    (cadr-ai:tool-result-message-is-error result))))
         (prefix
           (tic-tac-toe-theme-fg
            theme (if error-p :error :success)
            (if error-p "✗ " "✓ ")))
         (summary
           (concatenate
            'string prefix
            (tic-tac-toe-theme-fg theme :muted text)))
         (details
           (and (typep result 'cadr-ai:tool-result-message)
                (cadr-ai:tool-result-message-details result))))
    (if (and (getf options :expanded-p) details)
        (make-instance
         'tic-tac-toe-banner-message
         :title summary
         :details details
         :expanded-p t
         :theme theme)
        summary)))

(defun tic-tac-toe-see-board-render-call (arguments theme context)
  ;; Baseline tic-tac-toe.ts:993-995.
  (declare (ignore arguments context))
  (tic-tac-toe-theme-fg
   theme :tool-title
   (tic-tac-toe-theme-bold theme "tic_tac_toe_see_board")))

(defun tic-tac-toe-see-board-render-result (result options theme context)
  ;; Baseline tic-tac-toe.ts:997-1006: fold to check + cursor.
  (declare (ignore options context))
  (let* ((details
           (and (typep result 'cadr-ai:tool-result-message)
                (cadr-ai:tool-result-message-details result)))
         (row (or (and (listp details) (getf details :agent-row)) 0))
         (column (or (and (listp details) (getf details :agent-column)) 0)))
    (concatenate
     'string
     (tic-tac-toe-theme-fg theme :success "✓ ")
     (tic-tac-toe-theme-fg
      theme :muted
      (format nil "cursor (~A,~A)" row column)))))

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
           ;; Baseline tic-tac-toe.ts:909-916 persists the cursor position
           ;; before throwing, so a retry survives session reconstruction.
           (tic-tac-toe-save)
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
 :description
 "Execute ONE tic-tac-toe action as Player O. `action` is exactly one of: move_up, move_down, move_left, move_right (move YOUR cursor one cell, clamped at edges), or play (place O under YOUR cursor; errors if the cell is not empty). There is no batched form. To play at (r, c) from your current cursor (r0, c0), emit the required move_down/move_up and move_right/move_left calls, then play, all as separate tool_use blocks in the SAME assistant response. Do not split the sequence across responses and do not wait for a result before emitting the next call. Your cursor position persists between turns and is reset to (0,0) only after a successful play."
 :prompt-snippet "Play a tic-tac-toe action (move_up/down/left/right or play) as Player O"
 :prompt-guidelines
 '("When it is your tic-tac-toe turn, decide the target cell first, then emit every move_* plus the final play as separate tic_tac_toe tool calls in a SINGLE assistant response. Never split them across responses or wait for intermediate results."
   "Never ask the user for the board. The board and your cursor position are included in the user's move message; use tic_tac_toe_see_board if you need them restated.")
 :parameters
 (example-object-schema
  "action" "string"
  "The single action to perform this call. Emit multiple tic_tac_toe calls in one response to string actions together.")
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
      ;; Baseline updateState fires after every agent action
      ;; (tic-tac-toe.ts:389-393): repaint the live overlay from the
      ;; agent's execution path.
      (tic-tac-toe-request-render)
      ;; Tool-result content must be a list of content blocks, not a raw
      ;; string (hello.lisp and todo.lisp use the same helper).
      (example-text-result
       result (tic-tac-toe-board-data *tic-tac-toe-state*)))))
 :render-call #'tic-tac-toe-render-call
 :render-result #'tic-tac-toe-render-result)

(cadr-agent:define-rich-tool
 "tic_tac_toe_see_board"
 :label "See Board"
 :description
 "Return the current tic-tac-toe board state and YOUR cursor position (Player O). Takes no arguments. Use this if you need the current state restated mid-turn (for example after a failed play). The user's cursor is never exposed."
 :prompt-snippet "Inspect the tic-tac-toe board and your cursor"
 :parameters (example-empty-schema)
 :handler
 (lambda (call-id arguments signal on-update context)
   (declare (ignore call-id arguments signal on-update context))
   (example-text-result
    (format nil
            "Board (your cursor marked with <>):~%~A~%~%Your cursor: (row=~D, col=~D)~%Status: ~(~A~)~%Turn: ~A"
            (tic-tac-toe-board-ascii *tic-tac-toe-state*)
            (tic-tac-toe-state-agent-row *tic-tac-toe-state*)
            (tic-tac-toe-state-agent-column *tic-tac-toe-state*)
            (tic-tac-toe-state-status *tic-tac-toe-state*)
            (if (char= (tic-tac-toe-state-current-turn *tic-tac-toe-state*) #\O)
                "Player O (you)" "Player X"))
    (tic-tac-toe-board-data *tic-tac-toe-state*)))
 :render-call #'tic-tac-toe-see-board-render-call
 :render-result #'tic-tac-toe-see-board-render-result)
