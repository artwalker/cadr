;;; v1.4.0 packages/coding-agent/src/modes/interactive/components/easter-egg-3d.ts
;;; Fullscreen braille ray cast. The header logo lifts off; /arminsayshi grows
;;; Armin from the center. Leaving runs the same timeline backwards.
(in-package #:cadr-cli)

(defparameter +egg-pi+ (coerce pi 'double-float))
(defparameter +egg-depth+ 0.7d0)
(defparameter +egg-fly-start+ 0.1d0)
(defparameter +egg-fly-duration+ 1.3d0)
(defparameter +egg-start-scale+ 0.1d0)
(defparameter +egg-puzzle-step+ 0.3d0)
(defparameter +egg-puzzle-steps+ 12)
(defparameter +egg-puzzle-return+ 1d0)
(defparameter +egg-puzzle-hold+ 0.6d0)
(defparameter +egg-puzzle-start+
  (+ +egg-fly-start+ +egg-fly-duration+ 3d0))
(defparameter +egg-puzzle-cycle+
  (+ (* +egg-puzzle-step+ +egg-puzzle-steps+)
     +egg-puzzle-return+ +egg-puzzle-hold+))
(defparameter +egg-frame-ms+ (/ 1000d0 30d0))
(defparameter +egg-dust-duration+ 0.35d0)
(defparameter +egg-wave-spread+ 0.55d0)
(defparameter +egg-wave-jitter+ 0.12d0)
(defparameter +egg-dissolve-end+
  (+ +egg-fly-start+ +egg-wave-spread+ +egg-wave-jitter+
     +egg-dust-duration+))
(defparameter +egg-background-fade+ 0.5d0)
(defparameter +egg-exit-duration+ 1.1d0)
(defparameter +egg-stars-start+ 2.5d0)
(defparameter +egg-stars-fade+ 2d0)
(defparameter +egg-star-density+ 0.018d0)
(defparameter +egg-logo-color-step+ 5d0)
(defparameter +egg-light-halo-strength+ 0.3d0)
(defparameter +egg-halo-radius-x+ 6)
(defparameter +egg-halo-radius-y+ 3)
(defparameter +egg-halo-levels+ 32d0)
(defparameter +egg-star-alpha-levels+ 8d0)
(defparameter +egg-star-flicker-levels+ 3d0)
(defparameter +egg-hint-fade+ 0.5d0)
(defparameter +egg-spin-ramp+ 1.4d0)
(defparameter +egg-spin-linger+ 0.6d0)
(defparameter +egg-dot-bits+
  #(#x01 #x08 #x02 #x10 #x04 #x20 #x40 #x80))
(defparameter +egg-puzzle-moves+
  '((1 0 0) (-1 0 0) (0 1 0) (0 -1 0)
    (1 0 0) (-1 0 0) (0 1 0) (0 -1 0)
    (0 0 1) (0 0 -1)))
(defparameter +egg-logo-pixels+ #("ccc." "b.c." "bb.y" "b..y"))
(defparameter +egg-coral+ '(228d0 138d0 122d0))
(defparameter +egg-blue+ '(79d0 142d0 179d0))
(defparameter +egg-yellow+ '(234d0 182d0 93d0))
(defparameter +egg-star-tints+
  '((255d0 255d0 255d0) (170d0 195d0 255d0)
    (255d0 225d0 170d0) (255d0 190d0 205d0)))

(defun egg-u32 (value)
  (logand (floor value) #xffffffff))

(defun egg-imul (left right)
  (egg-u32 (* (egg-u32 left) (egg-u32 right))))

(defun egg-hash (value)
  (let ((x (egg-imul (logxor (egg-u32 value) #x9e3779b9)
                     #x85ebca6b)))
    (setf x (logxor x (ash x -13)))
    (setf x (egg-imul x #xc2b2ae35))
    (setf x (logxor x (ash x -16)))
    (/ (float (egg-u32 x) 1d0) 4294967296d0)))

(defun egg-clamp01 (value)
  (cond ((minusp value) 0d0)
        ((> value 1d0) 1d0)
        (t (float value 1d0))))

(defun egg-smooth (value)
  (let ((tee (egg-clamp01 value)))
    (* tee tee tee (+ (* tee (- (* tee 6d0) 15d0)) 10d0))))

(defun egg-ease-out (value)
  (let ((tee (- 1d0 (egg-clamp01 value))))
    (- 1d0 (* tee tee tee))))

(defun egg-js-round (value)
  (if (minusp value)
      (- (floor (+ (- value) 0.5d0)))
      (floor (+ value 0.5d0))))

(defun egg-mix (left right amount)
  (list (+ (first left) (* (- (first right) (first left)) amount))
        (+ (second left) (* (- (second right) (second left)) amount))
        (+ (third left) (* (- (third right) (third left)) amount))))

(defun egg-normalize (x y z)
  (let ((length (sqrt (+ (* x x) (* y y) (* z z)))))
    (list (/ x length) (/ y length) (/ z length))))

(defparameter +egg-light+ (egg-normalize -0.45d0 -0.6d0 0.75d0))
(defparameter +egg-half-vector+
  (egg-normalize (first +egg-light+)
                 (second +egg-light+)
                 (+ (third +egg-light+) 1d0)))

(defparameter +egg-braille+
  (let ((table (make-array 256)))
    (dotimes (bits 256)
      (setf (aref table bits) (string (code-char (+ #x2800 bits)))))
    table))

(defun egg-light-p (rgb)
  (> (+ (* 0.2126d0 (first rgb))
        (* 0.7152d0 (second rgb))
        (* 0.0722d0 (third rgb)))
     128d0))

(defun egg-indexed-rgb (index)
  (let ((basic
          #((0 0 0) (128 0 0) (0 128 0) (128 128 0)
            (0 0 128) (128 0 128) (0 128 128) (192 192 192)
            (128 128 128) (255 0 0) (0 255 0) (255 255 0)
            (0 0 255) (255 0 255) (0 255 255) (255 255 255)))
        (cube #(0 95 135 175 215 255)))
    (cond ((< index 16)
           (map 'list (lambda (channel) (float channel 1d0))
                (aref basic index)))
          ((< index 232)
           (let ((cube-index (- index 16)))
             (list (float (aref cube (floor cube-index 36)) 1d0)
                   (float (aref cube (floor (mod cube-index 36) 6)) 1d0)
                   (float (aref cube (mod cube-index 6)) 1d0))))
          (t
           (let ((gray (float (+ 8 (* (- index 232) 10)) 1d0)))
             (list gray gray gray))))))

(defun egg-glyph-ink (text seed)
  (cond ((string= (string-trim '(#\Space #\Tab #\Newline #\Return) text) "")
         0)
        ((and (= (length text) 1)
              (find (char text 0) ".,:;' `-_·"))
         2)
        ((and (= (length text) 1)
              (<= #x2500 (char-code (char text 0)) #x257f))
         3)
        (t (+ 4 (floor (* seed 3d0))))))

(defstruct egg-cell
  (text " " :type string)
  (width 1 :type integer)
  fg bg delay (ink 0) (seed 0))

(defstruct egg-model
  columns rows blocks camera-distance radius width-share
  puzzle-moves origin-column origin-row origin-p)

(defstruct egg-block hx hy hz color)

(defun egg-create-model (columns rows pixel camera-distance width-share
                         origin puzzle-moves)
  (let ((blocks nil))
    (dotimes (row rows)
      (dotimes (column columns)
        (let ((color (funcall pixel column row)))
          (when color
            (push (make-egg-block :hx column :hy row :hz 0 :color color)
                  blocks)))))
    (setf blocks (nreverse blocks))
    (make-egg-model
     :columns columns :rows rows :blocks blocks
     :camera-distance (float camera-distance 1d0)
     :radius (sqrt (+ (expt (/ columns 2d0) 2)
                      (expt (/ rows 2d0) 2)
                      (expt (+ 1d0 (/ +egg-depth+ 2d0)) 2)))
     :width-share (float width-share 1d0)
     :puzzle-moves puzzle-moves
     :origin-column (and origin (first origin))
     :origin-row (and origin (second origin))
     :origin-p (not (null origin)))))

(defun pi-logo-model (column row)
  (egg-create-model
   4 4
   (lambda (x y)
     (let ((code (char (aref +egg-logo-pixels+ y) x)))
       (case code
         (#\c +egg-coral+)
         (#\b +egg-blue+)
         (#\y +egg-yellow+))))
   10d0 0.35d0 (list column row)
   (lambda (random) (if (< random 0.4d0) 2 1))))

(defun armin-egg-model (color)
  (let ((model nil))
    (setf model
          (egg-create-model
           +armin-width+ +armin-height+
           (lambda (x y) (when (armin-pixel-p x y) color))
           80d0 0.45d0 nil
           (lambda (random)
             (egg-js-round
              (* (length (egg-model-blocks model))
                 (+ 0.03d0 (* random 0.04d0)))))))
    model))

(defun egg-cell-key (cell columns rows)
  (+ (* (+ (* (+ (third cell) 1) rows) (second cell)) columns)
     (first cell)))

(defun egg-shuffle-steps (model cycle)
  (let* ((columns (egg-model-columns model))
         (rows (egg-model-rows model))
         (count (length (egg-model-blocks model)))
         (positions
           (make-array count
                       :initial-contents
                       (mapcar (lambda (block)
                                 (list (egg-block-hx block)
                                       (egg-block-hy block)
                                       (egg-block-hz block)))
                               (egg-model-blocks model))))
         (steps (make-array (1+ +egg-puzzle-steps+)))
         (last-moved (make-hash-table))
         (random (+ (* cycle 7919) 1)))
    (setf (aref steps 0) (copy-seq positions))
    (labels ((next ()
               (prog1 (egg-hash random) (incf random))))
      (dotimes (step +egg-puzzle-steps+)
        (let ((occupied (make-hash-table))
              (next-positions (copy-seq positions))
              (moved (make-hash-table)))
          (loop for index below count
                do (setf (gethash (egg-cell-key (aref positions index)
                                                columns rows)
                                  occupied)
                         t))
          (dotimes (move (funcall (egg-model-puzzle-moves model) (next)))
            (let ((candidates nil))
              (loop for block below count
                    unless (gethash block moved)
                      do (let ((cell (aref positions block)))
                           (dolist (delta +egg-puzzle-moves+)
                             (let ((target
                                     (list (+ (first cell) (first delta))
                                           (+ (second cell) (second delta))
                                           (+ (third cell) (third delta)))))
                               (when (and (<= 0 (first target) (1- columns))
                                          (<= 0 (second target) (1- rows))
                                          (<= -1 (third target) 1)
                                          (not (gethash
                                                (egg-cell-key target columns rows)
                                                occupied)))
                                 (push (list block target) candidates))))))
              (let* ((ordered (nreverse candidates))
                     (fresh
                       (remove-if (lambda (candidate)
                                    (gethash (first candidate) last-moved))
                                  ordered))
                     (pool (if fresh fresh ordered))
                     (choice
                       (and pool
                            (nth (floor (* (next) (length pool))) pool))))
                (unless choice (return))
                (setf (gethash (egg-cell-key (second choice) columns rows)
                               occupied)
                      t
                      (aref next-positions (first choice))
                      (second choice)
                      (gethash (first choice) moved)
                      t))))
          (clrhash last-moved)
          (maphash (lambda (block value)
                     (declare (ignore value))
                     (setf (gethash block last-moved) t))
                   moved)
          (setf positions next-positions
                (aref steps (1+ step)) (copy-seq positions)))))
    steps))

(defun egg-base-spin-phase (time)
  (let ((elapsed (- time +egg-fly-start+))
        (speed (/ (* +egg-pi+ 2d0) +egg-puzzle-cycle+)))
    (cond ((<= elapsed 0d0) 0d0)
          (t
           (let ((unit (/ elapsed +egg-spin-ramp+)))
             (if (< unit 1d0)
                 (* speed +egg-spin-ramp+
                    (+ (expt unit 6) (* -3d0 (expt unit 5))
                       (* 2.5d0 (expt unit 4))))
                 (* speed (+ (* +egg-spin-ramp+ 0.5d0)
                             (- elapsed +egg-spin-ramp+)))))))))

(defparameter +egg-first-front-view+
  (+ +egg-puzzle-start+
     (* +egg-puzzle-step+ +egg-puzzle-steps+)
     +egg-puzzle-return+
     (/ +egg-puzzle-hold+ 2d0)))

(defparameter +egg-spin-alignment+
  (- (* +egg-pi+ 2d0)
     (mod (egg-base-spin-phase +egg-first-front-view+)
          (* +egg-pi+ 2d0))))

(defun egg-spin-phase (time)
  (+ (egg-base-spin-phase time)
     (* +egg-spin-alignment+
        (egg-smooth (/ (- time +egg-fly-start+) +egg-fly-duration+)))))

(defun egg-spin-angle (time)
  (let ((phase (egg-spin-phase time)))
    (- phase (* +egg-spin-linger+ (sin phase)))))

(defun egg-rotation (yaw pitch roll)
  (let* ((sy (sin yaw)) (cy (cos yaw))
         (sx (sin pitch)) (cx (cos pitch))
         (sz (sin roll)) (cz (cos roll))
         (ry (vector cy 0d0 sy 0d0 1d0 0d0 (- sy) 0d0 cy))
         (rx (vector 1d0 0d0 0d0 0d0 cx (- sx) 0d0 sx cx))
         (rz (vector cz (- sz) 0d0 sz cz 0d0 0d0 0d0 1d0)))
    (labels ((mul (a b)
               (let ((result (make-array 9 :element-type 'double-float)))
                 (dotimes (row 3)
                   (dotimes (column 3)
                     (setf (aref result (+ (* row 3) column))
                           (+ (* (aref a (+ (* row 3) 0)) (aref b column))
                              (* (aref a (+ (* row 3) 1))
                                 (aref b (+ 3 column)))
                              (* (aref a (+ (* row 3) 2))
                                 (aref b (+ 6 column)))))))
                 result)))
      (mul rz (mul rx ry)))))

(defstruct egg-raster
  camera-distance width height bits counts rgb halo-amount halo-rgb
  depth face-ids dirty halo-dirty)

(defun egg-make-raster (camera-distance)
  (make-egg-raster :camera-distance (float camera-distance 1d0)))

(defun egg-f32 (value)
  (coerce value 'single-float))

(defun egg-fill (array start end value)
  (loop for index from start below end
        do (setf (aref array index) value)))

(defun egg-ensure-raster (raster width height)
  (let ((dots-x (* width 2))
        (dots-y (* height 4)))
    (if (and (eql width (egg-raster-width raster))
             (eql height (egg-raster-height raster)))
        (when (egg-raster-dirty raster)
          (destructuring-bind (min-x min-y max-x max-y)
              (egg-raster-dirty raster)
            (loop for row from min-y to max-y
                  do (egg-fill (egg-raster-bits raster)
                               (+ (* row width) min-x)
                               (+ (* row width) max-x 1) 0)
                     (egg-fill (egg-raster-counts raster)
                               (+ (* row width) min-x)
                               (+ (* row width) max-x 1) 0)
                     (egg-fill (egg-raster-rgb raster)
                               (* (+ (* row width) min-x) 3)
                               (* (+ (* row width) max-x 1) 3)
                               (egg-f32 0d0))))
          (setf (egg-raster-dirty raster) nil))
        (setf (egg-raster-width raster) width
              (egg-raster-height raster) height
              (egg-raster-bits raster)
              (make-array (* width height) :element-type '(unsigned-byte 8)
                          :initial-element 0)
              (egg-raster-counts raster)
              (make-array (* width height) :element-type '(unsigned-byte 8)
                          :initial-element 0)
              (egg-raster-rgb raster)
              (make-array (* width height 3) :element-type 'single-float
                          :initial-element 0f0)
              (egg-raster-halo-amount raster)
              (make-array (* width height) :element-type 'single-float
                          :initial-element 0f0)
              (egg-raster-halo-rgb raster)
              (make-array (* width height 3) :element-type 'single-float
                          :initial-element 0f0)
              (egg-raster-halo-dirty raster) nil
              (egg-raster-depth raster)
              (make-array (* dots-x dots-y) :element-type 'single-float
                          :initial-element most-positive-single-float)
              (egg-raster-face-ids raster)
              (make-array (* dots-x dots-y) :element-type '(unsigned-byte 16)
                          :initial-element 0)
              (egg-raster-dirty raster) nil))
    (when (egg-raster-halo-dirty raster)
      (destructuring-bind (min-x min-y max-x max-y)
          (egg-raster-halo-dirty raster)
        (loop for row from min-y to max-y
              do (egg-fill (egg-raster-halo-amount raster)
                           (+ (* row width) min-x)
                           (+ (* row width) max-x 1) 0f0)
                 (egg-fill (egg-raster-halo-rgb raster)
                           (* (+ (* row width) min-x) 3)
                           (* (+ (* row width) max-x 1) 3) 0f0)))
      (setf (egg-raster-halo-dirty raster) nil))))

(defstruct egg-face
  axis plane u-min u-max v-min v-max min-x min-y max-x max-y
  red green blue)

(defun egg-visible-faces (raster matrix origin pose boxes dot-width
                          dot-height light-p)
  (let ((faces nil)
        (camera (egg-raster-camera-distance raster))
        (scale (getf pose :scale))
        (center-x (getf pose :center-x))
        (center-y (getf pose :center-y)))
    (dolist (box boxes)
      (dotimes (axis 3)
        (let ((u (mod (1+ axis) 3))
              (v (mod (+ axis 2) 3)))
          (dolist (side '(-1d0 1d0))
            (let* ((plane (if (plusp side)
                              (aref (getf box :max) axis)
                              (aref (getf box :min) axis)))
                   (covered nil))
              (unless (<= (* (- (nth axis origin) plane) side) 0d0)
              (dolist (other boxes)
                (when (and (not (eq other box))
                           (= (if (plusp side)
                                  (aref (getf other :min) axis)
                                  (aref (getf other :max) axis))
                              plane)
                           (<= (aref (getf other :min) u)
                               (aref (getf box :min) u))
                           (>= (aref (getf other :max) u)
                               (aref (getf box :max) u))
                           (<= (aref (getf other :min) v)
                               (aref (getf box :min) v))
                           (>= (aref (getf other :max) v)
                               (aref (getf box :max) v)))
                  (setf covered t)))
              (unless covered
                (let ((min-x most-positive-double-float)
                      (min-y most-positive-double-float)
                      (max-x most-negative-double-float)
                      (max-y most-negative-double-float)
                      (corner (make-array 3 :element-type 'double-float)))
                  (dolist (corner-u (list (aref (getf box :min) u)
                                          (aref (getf box :max) u)))
                    (dolist (corner-v (list (aref (getf box :min) v)
                                            (aref (getf box :max) v)))
                      (setf (aref corner axis) plane
                            (aref corner u) corner-u
                            (aref corner v) corner-v)
                      (let* ((x (+ (* (aref matrix 0) (aref corner 0))
                                   (* (aref matrix 1) (aref corner 1))
                                   (* (aref matrix 2) (aref corner 2))))
                             (y (+ (* (aref matrix 3) (aref corner 0))
                                   (* (aref matrix 4) (aref corner 1))
                                   (* (aref matrix 5) (aref corner 2))))
                             (z (+ (* (aref matrix 6) (aref corner 0))
                                   (* (aref matrix 7) (aref corner 1))
                                   (* (aref matrix 8) (aref corner 2))))
                             (perspective
                               (/ (* scale camera) (- camera z)))
                             (screen-x (+ center-x (* x perspective)))
                             (screen-y (+ center-y (* y perspective))))
                        (setf min-x (min min-x screen-x)
                              min-y (min min-y screen-y)
                              max-x (max max-x screen-x)
                              max-y (max max-y screen-y)))))
                  (let ((face-min-x (max 0 (floor min-x)))
                        (face-min-y (max 0 (floor min-y)))
                        (face-max-x (min (1- dot-width) (ceiling max-x)))
                        (face-max-y (min (1- dot-height) (ceiling max-y))))
                    (when (and (>= face-max-x face-min-x)
                               (>= face-max-y face-min-y))
                      (let* ((nx (* (aref matrix axis) side))
                             (ny (* (aref matrix (+ 3 axis)) side))
                             (nz (* (aref matrix (+ 6 axis)) side))
                             (diffuse
                               (max 0d0
                                    (+ (* nx (first +egg-light+))
                                       (* ny (second +egg-light+))
                                       (* nz (third +egg-light+)))))
                             (rim (max 0d0 (- (* nx 0.8d0) (* nz 0.3d0))))
                             (specular
                               (if light-p
                                   0d0
                                   (* (expt
                                       (max 0d0
                                            (+ (* nx (first +egg-half-vector+))
                                               (* ny (second +egg-half-vector+))
                                               (* nz (third +egg-half-vector+))))
                                       24)
                                      0.6d0 255d0)))
                             (light
                               (if light-p
                                   (min 1d0 (+ 0.55d0 (* diffuse 0.45d0)
                                               (* rim 0.1d0)))
                                   (+ 0.45d0 (* diffuse 0.78d0)
                                      (* rim 0.25d0))))
                             (color (getf box :color)))
                        (push (make-egg-face
                               :axis axis :plane plane
                               :u-min (aref (getf box :min) u)
                               :u-max (aref (getf box :max) u)
                               :v-min (aref (getf box :min) v)
                               :v-max (aref (getf box :max) v)
                               :min-x face-min-x :min-y face-min-y
                               :max-x face-max-x :max-y face-max-y
                               :red (min 255d0 (+ (* (first color) light) specular))
                               :green (min 255d0 (+ (* (second color) light) specular))
                               :blue (min 255d0 (+ (* (third color) light) specular)))
                              faces))))))))))))
    (nreverse faces)))
