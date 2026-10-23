;;; v1.4.0 easter-egg-3d.ts animation, play entry, and logo click.
(in-package #:cadr-cli)

(defvar *easter-egg-playing* nil)

(defclass easter-egg-3d-animation (cadr-tui:component)
  ((screen :initarg :screen :reader egg-anim-screen)
   (model :initarg :model :reader egg-anim-model)
   (foreground :initarg :foreground :reader egg-anim-foreground)
   (background :initarg :background :reader egg-anim-background)
   (on-done :initarg :on-done :reader egg-anim-on-done)
   (rows :initarg :rows :accessor egg-anim-rows)
   (request-render :initarg :request-render
                   :initform nil
                   :accessor egg-anim-request-render)
   (forced-elapsed :initarg :forced-elapsed
                   :initform nil
                   :accessor egg-anim-forced-elapsed)
   (start-ms :initform nil :accessor egg-anim-start-ms)
   (last-render-ms :initform nil :accessor egg-anim-last-render-ms)
   (thread :initform nil :accessor egg-anim-thread)
   (stop-p :initform nil :accessor egg-anim-stop-p)
   (exit :initform nil :accessor egg-anim-exit)
   (shuffle :initform nil :accessor egg-anim-shuffle)
   (screen-width :initform -1 :accessor egg-anim-screen-width)
   (screen-height :initform -1 :accessor egg-anim-screen-height)
   (stars :initform nil :accessor egg-anim-stars)
   (cells :initform nil :accessor egg-anim-cells)
   (ansi-cache :initform (make-hash-table) :reader egg-anim-ansi-cache)
   (raster :initform nil :accessor egg-anim-raster)
   (finished-p :initform nil :accessor egg-anim-finished-p)))

(defun egg-now-ms ()
  (* (/ (get-internal-real-time) internal-time-units-per-second) 1000d0))

;;; v1.4.0 dark.json after vars resolve. The builtin dark table still stores
;;; the pre-okhsl chrome hex; theme.colors in theme.ts is this okhsl.
(defparameter +egg-v140-dark-okhsl+
  '((:muted . "okhsl(229 6% 67%)")
    (:dim . "okhsl(229 8% 56%)")
    (:accent . "okhsl(295 50% 67%)")
    (:text . "okhsl(234 3% 89%)")))

(defparameter +egg-builtin-dark-hex+
  '((:muted . "#808080")
    (:dim . "#666666")
    (:accent . "#8abeb7")
    (:text . "#d4d4d4")))

(defun egg-theme-color-text (key theme)
  "Current theme color. Builtin dark muted/dim/accent/text resolve like v1.4.0."
  (let* ((value (cadr-tui:theme-color-value key :theme theme))
         (okhsl (cdr (assoc key +egg-v140-dark-okhsl+)))
         (builtin (cdr (assoc key +egg-builtin-dark-hex+))))
    (if (and okhsl
             (eq (cadr-tui:terminal-theme-name theme) :dark)
             (stringp value)
             (string-equal value builtin))
        (cadr-tui:normalize-theme-color okhsl)
        value)))

(defun egg-theme-rgb (key)
  (let* ((value (egg-theme-color-text key (cadr-tui:current-theme)))
         (color (cadr-tui:parse-theme-hex-color value)))
    (list (float (cadr-tui:rgb-color-red color) 1d0)
          (float (cadr-tui:rgb-color-green color) 1d0)
          (float (cadr-tui:rgb-color-blue color) 1d0))))

(defun egg-ansi (red green blue background-p)
  (let* ((theme (cadr-tui:current-theme))
         (mode (cadr-tui:terminal-theme-color-mode theme))
         (base (if background-p 48 38))
         (r (egg-js-round red))
         (g (egg-js-round green))
         (b (egg-js-round blue)))
    (if (eq mode :truecolor)
        (format nil "~C[~D;2;~D;~D;~Dm" #\Escape base r g b)
        (format nil "~C[~D;5;~Dm" #\Escape base
                (cadr-tui:rgb-to-ansi-256 r g b)))))

(defun make-easter-egg-3d-animation
    (screen model foreground background on-done
     &key rows request-render forced-elapsed start-p)
  (let ((animation
          (make-instance 'easter-egg-3d-animation
                         :screen (coerce screen 'list)
                         :model model
                         :foreground foreground
                         :background background
                         :on-done on-done
                         :rows (or rows 24)
                         :request-render request-render
                         :forced-elapsed forced-elapsed)))
    (setf (egg-anim-raster animation)
          (egg-make-raster (egg-model-camera-distance model))
          (egg-anim-start-ms animation) (egg-now-ms)
          (egg-anim-last-render-ms animation) (egg-now-ms))
    (when start-p
      (egg-anim-start animation))
    animation))

(defun egg-anim-elapsed (animation)
  (or (egg-anim-forced-elapsed animation)
      (/ (- (egg-now-ms) (egg-anim-start-ms animation)) 1000d0)))

(defun egg-anim-exit-progress (animation)
  (let ((exit (egg-anim-exit animation)))
    (if exit
        (egg-clamp01
         (/ (- (egg-now-ms) (getf exit :start))
            1000d0 +egg-exit-duration+))
        0d0)))

(defun egg-anim-finish (animation)
  (unless (egg-anim-finished-p animation)
    (setf (egg-anim-finished-p animation) t
          (egg-anim-stop-p animation) t)
    (let ((thread (egg-anim-thread animation)))
      (setf (egg-anim-thread animation) nil)
      (stop-thread-for-cleanup thread))
    (setf *easter-egg-playing* nil)
    (when (egg-anim-on-done animation)
      (funcall (egg-anim-on-done animation)))))

(defun egg-anim-close (animation)
  (if (egg-anim-exit animation)
      (egg-anim-finish animation)
      (let* ((time (egg-anim-elapsed animation))
             (yaw (egg-spin-angle time))
             (turn (* +egg-pi+ 2d0)))
        (setf (egg-anim-exit animation)
              (list :start (egg-now-ms)
                    :time time
                    :yaw yaw
                    :target-yaw (* (ceiling (/ yaw turn)) turn)
                    :offsets (egg-block-offsets animation time))))))

(defun egg-anim-start (animation)
  (unless (egg-anim-thread animation)
    (setf (egg-anim-stop-p animation) nil
          (egg-anim-thread animation)
          (sb-thread:make-thread
           (lambda ()
             (loop until (egg-anim-stop-p animation)
                   do (sleep (/ +egg-frame-ms+ 1000d0))
                      (cond
                        ((and (egg-anim-exit animation)
                              (>= (egg-anim-exit-progress animation) 1d0))
                         (egg-anim-finish animation))
                        ((> (- (egg-now-ms)
                               (or (egg-anim-last-render-ms animation) 0d0))
                            1000d0)
                         (egg-anim-finish animation))
                        ((egg-anim-request-render animation)
                         (funcall (egg-anim-request-render animation))))))
           :name "cadr-easter-egg-3d"))))

(defun egg-block-offsets (animation time)
  (let* ((model (egg-anim-model animation))
         (blocks (egg-model-blocks model))
         (home (lambda ()
                 (mapcar (lambda (block)
                           (declare (ignore block))
                           '(0d0 0d0 0d0))
                         blocks))))
    (when (< time +egg-puzzle-start+)
      (return-from egg-block-offsets (funcall home)))
    (let* ((cycle (floor (/ (- time +egg-puzzle-start+) +egg-puzzle-cycle+)))
           (local (- time +egg-puzzle-start+ (* cycle +egg-puzzle-cycle+)))
           (cached (egg-anim-shuffle animation)))
      (unless (and cached (eql (getf cached :cycle) cycle))
        (setf cached (list :cycle cycle
                           :steps (egg-shuffle-steps model cycle))
              (egg-anim-shuffle animation) cached))
      (let ((steps (getf cached :steps))
            (shuffle-end (* +egg-puzzle-step+ +egg-puzzle-steps+)))
        (labels ((offset (position index)
                   (let ((block (nth index blocks)))
                     (list (- (first position) (egg-block-hx block))
                           (- (second position) (egg-block-hy block))
                           (- (third position) (egg-block-hz block))))))
          (cond
            ((< local shuffle-end)
             (let* ((step (floor (/ local +egg-puzzle-step+)))
                    (progress
                      (egg-smooth
                       (/ (- local (* step +egg-puzzle-step+))
                          +egg-puzzle-step+)))
                    (from-row (aref steps step))
                    (to-row (aref steps (1+ step))))
               (loop for index below (length blocks)
                     for a = (offset (aref from-row index) index)
                     for b = (offset (aref to-row index) index)
                     collect (list (+ (first a) (* (- (first b) (first a)) progress))
                                   (+ (second a) (* (- (second b) (second a)) progress))
                                   (+ (third a) (* (- (third b) (third a)) progress))))))
            ((< local (+ shuffle-end +egg-puzzle-return+))
             (let* ((u (/ (- local shuffle-end) +egg-puzzle-return+))
                    (remaining (- 1d0 (egg-smooth u)))
                    (arc (* (sin (* +egg-pi+ (egg-clamp01 u))) 0.8d0))
                    (row (aref steps +egg-puzzle-steps+)))
               (loop for index below (length blocks)
                     for pos = (offset (aref row index) index)
                     collect (list (* (first pos) remaining)
                                   (* (second pos) remaining)
                                   (+ (* (third pos) remaining)
                                      (if (evenp index) arc (- arc)))))))
            (t (funcall home))))))))

(defun egg-fly-progress (time)
  (egg-smooth (/ (- time +egg-fly-start+) +egg-fly-duration+)))

(defun egg-star-alpha (time)
  (egg-smooth (/ (- time +egg-stars-start+) +egg-stars-fade+)))

(defun egg-hint-alpha (time)
  (egg-smooth (/ (- time +egg-fly-start+ +egg-fly-duration+)
                 +egg-hint-fade+)))

(defun egg-pose (model width height progress time)
  (let* ((columns (egg-model-columns model))
         (rows (egg-model-rows model))
         (camera (egg-model-camera-distance model))
         (radius (egg-model-radius model))
         (width-share (egg-model-width-share model))
         (origin-p (egg-model-origin-p model))
         (reach (* radius (/ camera (- camera radius))))
         (start-scale
           (if origin-p
               (/ (* 2d0 (- camera (/ +egg-depth+ 2d0))) camera)
               +egg-start-scale+))
         (end-scale
           (max start-scale
                (/ (min (* width 2d0 width-share)
                        (* (- (* height 4d0) 8d0) 0.48d0))
                   reach)))
         (end-x (float width 1d0))
         (end-y (- (* height 2d0) 2d0))
         (start-x
           (if origin-p
               (+ (* (egg-model-origin-column model) 2d0) columns)
               end-x))
         (start-y
           (if origin-p
               (+ (* (egg-model-origin-row model) 4d0) rows)
               end-y))
         (phase (egg-spin-phase time)))
    (list :center-x (+ start-x (* (- end-x start-x) progress))
          :center-y (+ start-y (* (- end-y start-y) progress))
          :scale (* start-scale (expt (/ end-scale start-scale) progress))
          :yaw (egg-spin-angle time)
          :pitch (* 0.3d0 (sin phase) progress)
          :roll (* 0.06d0 (sin (* 2d0 phase)) progress))))

(defun egg-hint (width height alpha background)
  (when (plusp alpha)
    (let* ((keys (cadr-tui:keybinding-keys
                  (cadr-tui:get-keybindings)
                  "tui.select.cancel"))
           (key (format-key-text (or (first keys) "escape")))
           (text (format nil "~A to return" key)))
      (when (<= (length text) width)
        (list :row (- height 2)
              :start (floor (/ (- width (length text)) 2))
              :text text
              :key-length (length key)
              :key-color (egg-mix background (egg-theme-rgb :muted) alpha)
              :color (egg-mix background (egg-theme-rgb :dim) alpha))))))

(defun egg-prepare-stars (width height)
  (let ((stars (make-array (* width height) :initial-element nil)))
    (dotimes (index (* width height))
      (when (< (egg-hash (+ (* index 3) #x51ed)) +egg-star-density+)
        (flet ((star-random (salt)
                 (egg-hash (+ (* index 7) (* salt #x9e37)))))
          (setf (aref stars index)
                (list :glyph (aref +egg-braille+
                                   (aref +egg-dot-bits+
                                         (floor (* (star-random 1) 8))))
                      :tint (nth (floor (* (star-random 2)
                                           (length +egg-star-tints+)))
                                 +egg-star-tints+)
                      :strength (+ 0.1d0 (* (star-random 3) 0.12d0))
                      :phase (* (star-random 4) +egg-pi+ 2d0)
                      :speed (+ 0.4d0 (* (star-random 5) 0.8d0)))))))
    stars))

(defun egg-prepare-cells (animation width foreground)
  (let* ((model (egg-anim-model animation))
         (background (egg-anim-background animation))
         (cells (egg-parse-screen (egg-anim-screen animation)
                                  width foreground background))
         (height (max 1 (egg-anim-rows animation)))
         (columns (egg-model-columns model))
         (rows (egg-model-rows model))
         (origin-p (egg-model-origin-p model))
         (center-x
           (if origin-p
               (+ (egg-model-origin-column model) (/ columns 2d0))
               (/ width 2d0)))
         (center-y
           (if origin-p
               (+ (egg-model-origin-row model) (/ rows 4d0))
               (/ height 2d0)))
         (farthest
           (sqrt (+ (expt (max center-x (- width center-x)) 2)
                    (expt (* (max center-y (- height center-y)) 2) 2)))))
    (loop for row from 0
          for line in cells
          do (loop for column from 0
                   for cell in line
                   do (let* ((owner
                               (if (zerop (egg-cell-width cell))
                                   (nth (1- column) line)
                                   cell))
                             (seed (egg-hash (+ (* row 65537) column))))
                        (if (plusp (egg-cell-width cell))
                            (let ((distance
                                    (/ (sqrt (+ (expt (- column center-x) 2)
                                                (expt (* (- row center-y) 2) 2)))
                                       farthest)))
                              (setf (egg-cell-delay cell)
                                    (+ +egg-fly-start+
                                       (* distance +egg-wave-spread+)
                                       (* seed +egg-wave-jitter+))))
                            (setf (egg-cell-delay cell)
                                  (egg-cell-delay owner)))
                        (setf (egg-cell-seed cell) (+ (* row 65537) column)
                              (egg-cell-ink cell)
                              (egg-glyph-ink (egg-cell-text owner) seed)))))
    (when origin-p
      (loop for row from (egg-model-origin-row model)
            below (+ (egg-model-origin-row model)
                     (ceiling (/ rows 2)))
            for line = (nth row cells)
            when line
              do (loop for column from (egg-model-origin-column model)
                       below (+ (egg-model-origin-column model) columns)
                       for cell = (nth column line)
                       when cell
                         do (setf (egg-cell-text cell) " "
                                  (egg-cell-width cell) 1
                                  (egg-cell-ink cell) 0
                                  (egg-cell-bg cell) nil))))
    cells))

(defun egg-pack-color (color)
  (logior (ash (egg-js-round (first color)) 16)
          (ash (egg-js-round (second color)) 8)
          (egg-js-round (third color))))

(defun egg-cached-ansi (animation key background-p)
  (let* ((cache (egg-anim-ansi-cache animation))
         (cache-key (+ (* key 2) (if background-p 1 0)))
         (cached (gethash cache-key cache)))
    (or cached
        (setf (gethash cache-key cache)
              (egg-ansi (logand (ash key -16) 255)
                        (logand (ash key -8) 255)
                        (logand key 255)
                        background-p)))))

(defmethod cadr-tui:component-invalidate
    ((component easter-egg-3d-animation))
  (setf (egg-anim-screen-width component) -1
        (egg-anim-screen-height component) -1)
  (clrhash (egg-anim-ansi-cache component))
  component)

(defmethod cadr-tui:component-dispose
    ((component easter-egg-3d-animation))
  (egg-anim-finish component)
  component)

(defmethod cadr-tui:component-render
    ((component easter-egg-3d-animation) width &key focused-p)
  (declare (ignore focused-p))
  (let* ((height (max 1 (egg-anim-rows component)))
         (foreground (egg-anim-foreground component))
         (background (egg-anim-background component))
         (model (egg-anim-model component))
         (raster (egg-anim-raster component)))
    (setf (egg-anim-last-render-ms component) (egg-now-ms))
    (when (or (/= width (egg-anim-screen-width component))
              (/= height (egg-anim-screen-height component)))
      (setf (egg-anim-screen-width component) width
            (egg-anim-screen-height component) height
            (egg-anim-cells component)
            (egg-prepare-cells component width foreground)
            (egg-anim-stars component)
            (egg-prepare-stars width height)))
    (multiple-value-bind (dissolve-time pose hint-alpha star-alpha offsets)
        (if (egg-anim-exit component)
            (let* ((exit (egg-anim-exit component))
                   (progress (egg-anim-exit-progress component))
                   (landing (egg-clamp01 (/ progress 0.8d0)))
                   (settle (- 1d0 (egg-smooth landing)))
                   (pose (egg-pose model width height
                                   (* (egg-fly-progress (getf exit :time))
                                      settle)
                                   (getf exit :time)))
                   (gather (- 1d0 (egg-smooth (/ progress 0.5d0)))))
              (setf (getf pose :yaw)
                    (+ (getf exit :yaw)
                       (* (- (getf exit :target-yaw) (getf exit :yaw))
                          (egg-ease-out landing)))
                    (getf pose :pitch) (* (getf pose :pitch) settle)
                    (getf pose :roll) (* (getf pose :roll) settle))
              (values (* (min (getf exit :time) +egg-dissolve-end+)
                         (- 1d0 progress))
                      pose
                      (* (egg-hint-alpha (getf exit :time))
                         (- 1d0 (egg-smooth (/ progress 0.2d0))))
                      (* (egg-star-alpha (getf exit :time))
                         (- 1d0 (egg-smooth (/ progress 0.3d0))))
                      (mapcar (lambda (offset)
                                (list (* (first offset) gather)
                                      (* (second offset) gather)
                                      (* (third offset) gather)))
                              (getf exit :offsets))))
            (let ((time (egg-anim-elapsed component)))
              (values time
                      (egg-pose model width height
                                (egg-fly-progress time) time)
                      (egg-hint-alpha time)
                      (egg-star-alpha time)
                      (egg-block-offsets component time))))
      (let* ((columns (egg-model-columns model))
             (rows (egg-model-rows model))
             (boxes
               (loop for block in (egg-model-blocks model)
                     for offset in offsets
                     for x = (+ (- (egg-block-hx block) (/ columns 2d0))
                                (first offset))
                     for y = (+ (- (egg-block-hy block) (/ rows 2d0))
                                (second offset))
                     for dz = (third offset)
                     collect (list :min (vector x y (- dz (/ +egg-depth+ 2d0)))
                                   :max (vector (+ x 1d0) (+ y 1d0)
                                                (+ dz (/ +egg-depth+ 2d0)))
                                   :color (egg-block-color block))))
             (halo-strength
               (if (egg-light-p background) +egg-light-halo-strength+ 0d0)))
        (egg-render-raster raster width height pose boxes background
                           halo-strength)
        (labels
            ((halo (index base)
               (let ((amount (float (aref (egg-raster-halo-amount raster) index)
                                    1d0)))
                 (if (<= amount 0d0)
                     base
                     (egg-mix (or base background)
                              (list (float (aref (egg-raster-halo-rgb raster)
                                                 (* index 3))
                                           1d0)
                                    (float (aref (egg-raster-halo-rgb raster)
                                                 (+ (* index 3) 1))
                                           1d0)
                                    (float (aref (egg-raster-halo-rgb raster)
                                                 (+ (* index 3) 2))
                                           1d0))
                              amount))))
             (pack (color) (egg-pack-color color))
             (ansi (key background-p)
               (egg-cached-ansi component key background-p)))
          (let* ((background-fade
                   (egg-smooth (/ dissolve-time +egg-background-fade+)))
                 (text-fade (* (egg-smooth (/ dissolve-time 0.6d0)) 0.3d0))
                 (text-active
                   (or (< dissolve-time +egg-dissolve-end+)
                       (< background-fade 1d0)))
                 (hint (egg-hint width height hint-alpha background))
                 (frame (floor (* dissolve-time 14)))
                 (now (egg-anim-elapsed component))
                 (star-level
                   (/ (egg-js-round (* star-alpha +egg-star-alpha-levels+))
                      +egg-star-alpha-levels+))
                 (lines nil))
            (labels
                ((starfield (index)
                   (when (plusp star-level)
                     (let ((star (aref (egg-anim-stars component) index)))
                       (when star
                         (let ((flicker
                                 (/ (egg-js-round
                                     (* (+ 0.5d0
                                           (* 0.5d0
                                              (sin (+ (* now (getf star :speed))
                                                      (getf star :phase)))))
                                        +egg-star-flicker-levels+))
                                    +egg-star-flicker-levels+)))
                           (list :text (getf star :glyph)
                                 :fg (egg-mix
                                      background
                                      (egg-mix foreground
                                               (getf star :tint) 0.5d0)
                                      (* (getf star :strength)
                                         (+ 0.7d0 (* 0.3d0 flicker))
                                         star-level))))))))
                 (emit-line (row)
                   (let ((cells (or (nth row (egg-anim-cells component)) '()))
                         (line "")
                         (current-fg -1)
                         (current-bg -1)
                         (column 0))
                     (labels
                         ((emit (text fg bg)
                            (let ((fg-key (if fg (pack fg) -1))
                                  (bg-key (if bg (pack bg) -1)))
                              (when (and (/= fg-key current-fg)
                                         (string/= text " "))
                                (setf line
                                      (concatenate
                                       'string line
                                       (if fg (ansi fg-key nil) (format nil "~C[39m" #\Escape)))
                                      current-fg fg-key))
                              (when (/= bg-key current-bg)
                                (setf line
                                      (concatenate
                                       'string line
                                       (if bg (ansi bg-key t) (format nil "~C[49m" #\Escape)))
                                      current-bg bg-key))
                              (setf line (concatenate 'string line text)))))
                       (loop while (< column width)
                             do (let* ((index (+ (* row width) column))
                                       (cell (and text-active
                                                  (nth column cells)))
                                       (cell-bg
                                         (halo
                                          index
                                          (and cell
                                               (egg-cell-bg cell)
                                               (< background-fade 1d0)
                                               (egg-mix (egg-cell-bg cell)
                                                        background
                                                        background-fade)))))
                                  (cond
                                    ((and hint
                                          (= row (getf hint :row))
                                          (<= (getf hint :start) column)
                                          (< column (+ (getf hint :start)
                                                       (length (getf hint :text)))))
                                     (let ((offset (- column (getf hint :start))))
                                       (emit (string (char (getf hint :text) offset))
                                             (if (< offset (getf hint :key-length))
                                                 (getf hint :key-color)
                                                 (getf hint :color))
                                             cell-bg)
                                       (incf column)))
                                    ((plusp (aref (egg-raster-bits raster) index))
                                     (let* ((step (* +egg-logo-color-step+
                                                     (aref (egg-raster-counts raster)
                                                           index)))
                                            (rgb (egg-raster-rgb raster))
                                            (color
                                              (list
                                               (* (egg-js-round
                                                   (/ (float (aref rgb (* index 3)) 1d0)
                                                      step))
                                                  +egg-logo-color-step+)
                                               (* (egg-js-round
                                                   (/ (float (aref rgb (+ (* index 3) 1))
                                                             1d0)
                                                      step))
                                                  +egg-logo-color-step+)
                                               (* (egg-js-round
                                                   (/ (float (aref rgb (+ (* index 3) 2))
                                                             1d0)
                                                      step))
                                                  +egg-logo-color-step+))))
                                       (emit (aref +egg-braille+
                                                   (aref (egg-raster-bits raster) index))
                                             color cell-bg)
                                       (incf column)))
                                    ((null cell)
                                     (let ((star (starfield index)))
                                       (emit (or (getf star :text) " ")
                                             (getf star :fg)
                                             cell-bg)
                                       (incf column)))
                                    (t
                                     (let ((dust (/ (- dissolve-time
                                                       (egg-cell-delay cell))
                                                    +egg-dust-duration+)))
                                       (cond
                                         ((and (minusp dust)
                                               (= (egg-cell-width cell) 2)
                                               (zerop
                                                (aref (egg-raster-bits raster)
                                                      (1+ index))))
                                          (emit (egg-cell-text cell)
                                                (egg-mix (egg-cell-fg cell)
                                                         background text-fade)
                                                cell-bg)
                                          (incf column 2))
                                         ((and (minusp dust)
                                               (= (egg-cell-width cell) 1))
                                          (emit (egg-cell-text cell)
                                                (egg-mix (egg-cell-fg cell)
                                                         background text-fade)
                                                cell-bg)
                                          (incf column))
                                         (t
                                          (let ((dot-count
                                                  (if (minusp dust)
                                                      (egg-cell-ink cell)
                                                      (egg-js-round
                                                       (* (egg-cell-ink cell)
                                                          (- 1d0 (egg-clamp01 dust)))))))
                                            (if (<= dot-count 0)
                                                (let ((star (starfield index)))
                                                  (emit (or (getf star :text) " ")
                                                        (getf star :fg)
                                                        cell-bg)
                                                  (incf column))
                                                (let ((bits 0)
                                                      (placed 0))
                                                  (loop for attempt below 32
                                                        while (< placed dot-count)
                                                        for bit = (aref
                                                                   +egg-dot-bits+
                                                                   (floor
                                                                    (* (egg-hash
                                                                        (+ (* (egg-cell-seed cell)
                                                                              7919)
                                                                           (* frame 131)
                                                                           attempt))
                                                                       8)))
                                                        unless (plusp (logand bits bit))
                                                          do (setf bits (logior bits bit))
                                                             (incf placed))
                                                  (emit
                                                   (aref +egg-braille+ bits)
                                                   (egg-mix
                                                    (egg-cell-fg cell)
                                                    background
                                                    (+ text-fade
                                                       (* (- 1d0 text-fade)
                                                          (expt (egg-clamp01 dust)
                                                                0.8d0))))
                                                   cell-bg)
                                                  (incf column)))))))))))
                       (concatenate 'string line (format nil "~C[0m" #\Escape))))))
              (dotimes (row height)
                (push (emit-line row) lines))
              (nreverse lines))))))))

(defun egg-strip-for-logo (line)
  (cadr-tui:strip-terminal-sequences (or line "")))

(defun pi-logo-click-origin (lines x y)
  "Return (values column row) for a click on the 4x2 half-block mark, else NIL.
LINES are viewport rows; X and Y are 0-based screen cells."
  (when (and (integerp x) (integerp y) (>= y 0) (listp lines))
    (loop for row from 0 below (max 0 (1- (length lines)))
          for top = (egg-strip-for-logo (nth row lines))
          for bottom = (egg-strip-for-logo (nth (1+ row) lines))
          for column = (search "▀▀█ " top)
          when (and column
                    (eql column (search "█▀ █" bottom))
                    (or (= y row) (= y (1+ row)))
                    (<= column x (+ column 3)))
            do (return (values column row)))))

(defun egg-resolved-colors (terminal)
  (let* ((reported
           (ignore-errors
             (cadr-tui:terminal-query-theme-colors
              terminal :timeout-seconds 0.1d0)))
         (dark-p (eq (cadr-tui:terminal-theme-name
                      (cadr-tui:current-theme))
                     :dark))
         (fallback-fg (egg-theme-rgb :text))
         (fallback-bg (if dark-p '(0d0 0d0 0d0) '(255d0 255d0 255d0)))
         (fg (getf reported :foreground))
         (bg (getf reported :background)))
    (values
     (if (and (consp fg) (= (length fg) 3))
         (mapcar (lambda (channel) (float channel 1d0)) fg)
         fallback-fg)
     (if (and (consp bg) (= (length bg) 3))
         (mapcar (lambda (channel) (float channel 1d0)) bg)
         fallback-bg))))

(defun play-easter-egg-3d
    (terminal renderer screen egg
     &key request-render on-done overlay-check rows)
  "Start the fullscreen egg. Return (values started-or-swallowed animation).
Not alt-screen -> NIL. Overlay or already playing -> T with no animation."
  (unless (cadr-tui:alt-screen-renderer-p renderer)
    (return-from play-easter-egg-3d (values nil nil)))
  (when (or (and overlay-check (funcall overlay-check))
            *easter-egg-playing*)
    (return-from play-easter-egg-3d (values t nil)))
  (setf *easter-egg-playing* t)
  (multiple-value-bind (foreground background)
      (egg-resolved-colors terminal)
    (when (and overlay-check (funcall overlay-check))
      (setf *easter-egg-playing* nil)
      (return-from play-easter-egg-3d (values t nil)))
    (let* ((model
             (if (eq (getf egg :kind) :armin)
                 (armin-egg-model (egg-theme-rgb :accent))
                 (pi-logo-model (getf egg :column) (getf egg :row))))
           (finished nil)
           (animation
             (make-easter-egg-3d-animation
              screen model foreground background
              (lambda ()
                (unless finished
                  (setf finished t
                        *easter-egg-playing* nil)
                  (when on-done (funcall on-done))))
              :rows (or rows (cadr-tui:terminal-rows terminal))
              :request-render request-render
              :start-p t)))
      (values t animation))))

(defun egg-visible-overlay-p (overlay)
  "v1.4.0 Tui.hasOverlay: any visible overlay, including nonCapturing.
Hidden entries do not count. A nil overlay does not count."
  (and overlay
       (or (not (extension-custom-ui-state-p overlay))
           (not (extension-custom-ui-state-overlay-p overlay))
           (extension-custom-ui-visible-p overlay))))

(defun egg-logo-mouse-claim
    (gesture lines &key (logo-supported-p t) selector-handled-p)
  "BuiltInHeader.handleMouse. A selector that already handled the point
wins, the same way an overlay hit is not forwarded to the header.
Otherwise a click on the 4x2 half-block mark returns
(values T column row)."
  (when (or selector-handled-p
            (not logo-supported-p)
            (not (eq (getf gesture :type) :click)))
    (return-from egg-logo-mouse-claim nil))
  (let ((x (getf gesture :x))
        (y (getf gesture :y)))
    (when (and x y)
      (multiple-value-bind (column row)
          (pi-logo-click-origin lines x y)
        (when column
          (values t column row))))))

(defun egg-mouse-after-widget
    (handled gesture lines &key (logo-supported-p t))
  "Keep a widget hit. A miss falls through to the header logo."
  (if handled
      handled
      (egg-logo-mouse-claim
       gesture lines :logo-supported-p logo-supported-p)))

(defun play-pi-logo-3d
    (terminal renderer screen column row
     &key request-render on-done overlay-check rows)
  (play-easter-egg-3d
   terminal renderer screen
   (list :kind :pi-logo :column column :row row)
   :request-render request-render
   :on-done on-done
   :overlay-check overlay-check
   :rows rows))

(defun play-armin-3d
    (terminal renderer screen
     &key request-render on-done overlay-check rows)
  (play-easter-egg-3d
   terminal renderer screen
   (list :kind :armin)
   :request-render request-render
   :on-done on-done
   :overlay-check overlay-check
   :rows rows))
