(in-package #:cadr-cli)

(defparameter +armin-width+ 31)
(defparameter +armin-height+ 36)

(defparameter +armin-bits+
  #(#xff #xff #xff #x7f #xff #xf0 #xff #x7f #xff #xed #xff #x7f
    #xff #xdb #xff #x7f #xff #xb7 #xff #x7f #xff #x77 #xfe #x7f
    #x3f #xf8 #xfe #x7f #xdf #xff #xfe #x7f #xdf #x3f #xfc #x7f
    #x9f #xc3 #xfb #x7f #x6f #xfc #xf4 #x7f #xf7 #x0f #xf7 #x7f
    #xf7 #xff #xf7 #x7f #xf7 #xff #xe3 #x7f #xf7 #x07 #xe8 #x7f
    #xef #xf8 #x67 #x70 #x0f #xff #xbb #x6f #xf1 #x00 #xd0 #x5b
    #xfd #x3f #xec #x53 #xc1 #xff #xef #x57 #x9f #xfd #xee #x5f
    #x9f #xfc #xae #x5f #x1f #x78 #xac #x5f #x3f #x00 #x50 #x6c
    #x7f #x00 #xdc #x77 #xff #xc0 #x3f #x78 #xff #x01 #xf8 #x7f
    #xff #x03 #x9c #x78 #xff #x07 #x8c #x7c #xff #x0f #xce #x78
    #xff #xff #xcf #x7f #xff #xff #xcf #x78 #xff #xff #xdf #x78
    #xff #xff #xdf #x7d #xff #xff #x3f #x7e #xff #xff #xff #x7f))

(defun armin-pixel-p (x y)
  (when (< y +armin-height+)
    (let* ((bytes-per-row (ceiling +armin-width+ 8))
           (byte
             (aref +armin-bits+
                   (+ (* y bytes-per-row) (floor x 8)))))
      (zerop (logand byte (ash 1 (mod x 8)))))))

(defun armin-cell (x row)
  (let ((upper (armin-pixel-p x (* row 2)))
        (lower (armin-pixel-p x (1+ (* row 2)))))
    (cond
      ((and upper lower) #\█)
      (upper #\▀)
      (lower #\▄)
      (t #\Space))))

(defun armin-grid-height ()
  (ceiling +armin-height+ 2))

(defparameter +armin-final-grid+
  (let* ((height (ceiling +armin-height+ 2))
         (grid (make-array (list height +armin-width+)
                           :element-type 'character
                           :initial-element #\Space)))
    (dotimes (row height)
      (dotimes (x +armin-width+)
        (setf (aref grid row x) (armin-cell x row))))
    grid)
  "Baked half-block grid for make-armin-grid final-p.")

(defun make-armin-grid (&optional final-p)
  (if final-p
      (copy-armin-grid +armin-final-grid+)
      (make-array (list (armin-grid-height) +armin-width+)
                  :element-type 'character
                  :initial-element #\Space)))

(defun copy-armin-grid (grid)
  ;; Row-major replace on displaced vectors (no nested aref walk).
  (let* ((dims (array-dimensions grid))
         (n (array-total-size grid))
         (etype (array-element-type grid))
         (copy (make-array dims :element-type etype)))
    (replace
     (make-array n :element-type etype :displaced-to copy)
     (make-array n :element-type etype :displaced-to grid))
    copy))

(defun armin-grid-row-string (grid row)
  (let* ((width (array-dimension grid 1))
         (text (make-string width)))
    (dotimes (column width)
      (setf (char text column) (aref grid row column)))
    text))

(defclass armin-component (cadr-tui:component)
  ((ui :initarg :ui :reader armin-component-ui)
   (effect :initarg :effect :reader armin-component-effect)
   (final-grid
    :initform (make-armin-grid t)
    :reader armin-component-final-grid)
   (current-grid
    :initform (make-armin-grid nil)
    :accessor armin-component-current-grid)
   (position :initform 0 :accessor armin-component-position)
   (thread :initform nil :accessor armin-component-thread)
   (stop-p :initform nil :accessor armin-component-stop-p)
   (version :initform 0 :accessor armin-component-version)
   (cached-key :initform nil :accessor armin-component-cached-key)
   (cached-lines :initform nil :accessor armin-component-cached-lines)))

(defparameter +armin-effects+
  #(:typewriter :scanline :rain :fade :crt :glitch :dissolve))

(defun make-armin-component
    (ui &key effect (start-p t))
  (let ((component
          (make-instance
           'armin-component :ui ui
           :effect
           (or effect
               (aref +armin-effects+
                     (random (length +armin-effects+)))))))
    (when (eq (armin-component-effect component) :dissolve)
      (let ((grid (make-armin-grid nil)))
        (dotimes (row (array-dimension grid 0))
          (dotimes (column +armin-width+)
            (setf (aref grid row column)
                  (aref " ░▒▓█▀▄" (random 7)))))
        (setf (armin-component-current-grid component) grid)))
    (when start-p (armin-component-start component))
    component))

(defun armin-copy-cell (component position)
  (let ((row (floor position +armin-width+))
        (column (mod position +armin-width+))
        (final (armin-component-final-grid component)))
    (when (< row (array-dimension final 0))
      (setf (aref (armin-component-current-grid component) row column)
            (aref final row column))
      t)))

(defun armin-copy-row (destination source row)
  (dotimes (column +armin-width+)
    (setf (aref destination row column)
          (aref source row column))))

(defun armin-rotate-row (source row offset)
  (let ((shift (mod offset +armin-width+))
        (result (make-array +armin-width+ :element-type 'character)))
    (dotimes (column +armin-width+)
      (setf (aref result column)
            (aref source row (mod (+ column shift) +armin-width+))))
    result))

(defun armin-component-tick (component)
  (let* ((final (armin-component-final-grid component))
         (height (array-dimension final 0))
         (effect (armin-component-effect component))
         (position (armin-component-position component))
         (done-p nil))
    (case effect
      (:typewriter
       (loop repeat 3
             do
         (unless (armin-copy-cell component position)
           (setf done-p t)
           (return))
         (incf position)))
      (:scanline
       (if (>= position height)
           (setf done-p t)
           (progn
             (armin-copy-row
              (armin-component-current-grid component)
              final position)
             (incf position))))
      (:fade
       (loop repeat 15
             do
         (unless (armin-copy-cell component position)
           (setf done-p t)
           (return))
         (incf position)))
      (:dissolve
       (loop repeat 20
             do
         (unless (armin-copy-cell component position)
           (setf done-p t)
           (return))
         (incf position)))
      (:crt
       (let* ((middle (floor height 2))
              (top (max 0 (- middle position)))
              (bottom (min (1- height) (+ middle position)))
              (current (make-armin-grid nil)))
         (loop for row from top to bottom
               do (armin-copy-row current final row))
         (setf (armin-component-current-grid component) current)
         (incf position)
         (setf done-p (> position height))))
      (:glitch
       (if (>= position 8)
           (progn
             (setf
              (armin-component-current-grid component)
              (copy-armin-grid final)
              done-p t))
           (let ((current (make-armin-grid nil)))
             (dotimes (row height)
               (if (< (random 10) 3)
                   (let ((rotated
                           (armin-rotate-row
                            final row (- (random 7) 3))))
                     (dotimes (column +armin-width+)
                       (setf (aref current row column)
                             (aref rotated column))))
                   (armin-copy-row current final row)))
             (setf (armin-component-current-grid component) current)
             (incf position))))
      (:rain
       (dotimes (column +armin-width+)
         (let ((row (mod (+ position column) height)))
           (setf (aref (armin-component-current-grid component)
                       row column)
                 (aref final row column))))
       (incf position)
       (when (>= position (* height 2))
         (setf
          (armin-component-current-grid component)
          (copy-armin-grid final)
          done-p t))))
    (setf
     (armin-component-position component) position
     (armin-component-cached-key component) nil)
    (incf (armin-component-version component))
    (cadr-tui:tui-request-render
     (armin-component-ui component))
    (when done-p
      (setf (armin-component-stop-p component) t))
    done-p))

(defun armin-component-run (component)
  (loop
    (sleep
     (if (eq (armin-component-effect component) :glitch)
         (/ 1d0 60d0)
         (/ 1d0 30d0)))
    (when (armin-component-stop-p component)
      (return))
    (when (armin-component-tick component)
      (return))))

(defun armin-component-start (component)
  (setf (armin-component-stop-p component) nil)
  (unless (armin-component-thread component)
    (setf
     (armin-component-thread component)
     (sb-thread:make-thread
      (lambda () (armin-component-run component))
      :name "cadr Armin animation")))
  component)

(defmethod cadr-tui:component-render
    ((component armin-component) width &key focused-p)
  (declare (ignore focused-p))
  (let ((key (list width (armin-component-version component))))
    (when (equal key (armin-component-cached-key component))
      (return-from cadr-tui:component-render
        (armin-component-cached-lines component)))
    (let* ((available (max 0 (1- width)))
           (grid (armin-component-current-grid component))
           (lines
             (append
              (loop for row below (array-dimension grid 0)
                    collect
                    (let* ((raw (armin-grid-row-string grid row))
                           (clipped
                             (subseq raw 0 (min available
                                                (length raw)))))
                      (concatenate
                       'string " "
                       (cadr-tui:theme-foreground :accent clipped)
                       (make-string
                        (max 0 (- available (length clipped)))
                        :initial-element #\Space))))
              (list
               (concatenate
                'string " "
                (cadr-tui:theme-foreground
                 :accent "ARMIN SAYS HI")
                (make-string
                 (max 0 (- available 13))
                 :initial-element #\Space))))))
      (setf
       (armin-component-cached-key component) key
       (armin-component-cached-lines component) lines)
      lines)))

(defmethod cadr-tui:component-invalidate
    ((component armin-component))
  (setf (armin-component-cached-key component) nil)
  component)

(defmethod cadr-tui:component-dispose
    ((component armin-component))
  (setf (armin-component-stop-p component) t)
  (let ((thread (armin-component-thread component)))
    (when (and thread
               (not (eq thread sb-thread:*current-thread*))
               (sb-thread:thread-alive-p thread))
      (stop-thread-for-cleanup thread))
    (setf (armin-component-thread component) nil))
  component)
