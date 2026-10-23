(in-package #:cadr-tui)

;; pi@4a080252f packages/tui/src/oklab.ts and the color parsing in colors.ts.
;; Oklab and OKHSL follow Bjorn Ottosson's reference implementation.

(defparameter +linear-srgb-to-lms+
  '((0.4122214694707629d0 0.5363325372617349d0 0.0514459932675022d0)
    (0.2119034958178251d0 0.6806995506452344d0 0.1073969535369405d0)
    (0.0883024591900564d0 0.2817188391361215d0 0.6299787016738222d0)))

(defparameter +lms-to-lab+
  '((0.210454268309314d0 0.793617774702305d0 -0.0040720430116193d0)
    (1.9779985324311684d0 -2.42859224204858d0 0.450593709617411d0)
    (0.0259040424655478d0 0.7827717124575296d0 -0.8086757549230774d0)))

(defparameter +lab-to-lms+
  '((1d0 0.3963377773761749d0 0.2158037573099136d0)
    (1d0 -0.1055613458156586d0 -0.0638541728258133d0)
    (1d0 -0.0894841775298119d0 -1.2914855480194092d0)))

(defparameter +lms-to-linear-srgb+
  '((4.0767416360759583d0 -3.3077115392580629d0 0.2309699031821043d0)
    (-1.2684379732850315d0 2.6097573492876882d0 -0.341319376002657d0)
    (-0.0041960761386756d0 -0.7034186179359362d0 1.7076146940746117d0)))

(defparameter +saturation-fit+
  '(((-1.8817031d0 -0.80936501d0)
     (1.19086277d0 1.76576728d0 0.59662641d0 0.75515197d0 0.56771245d0))
    ((1.8144408d0 -1.19445267d0)
     (0.73956515d0 -0.45954404d0 0.08285427d0 0.12541073d0 -0.14503204d0))
    ((0.13110758d0 1.81333971d0)
     (1.35733652d0 -0.00915799d0 -1.1513021d0 -0.50559606d0 0.00692167d0))))

(defconstant +okhsl-k1+ 0.206d0)
(defconstant +okhsl-k2+ 0.03d0)
(defconstant +okhsl-k3+ (/ (+ 1d0 +okhsl-k1+) (+ 1d0 +okhsl-k2+)))

(defparameter +basic-ansi-colors+
  '((0 0 0) (128 0 0) (0 128 0) (128 128 0)
    (0 0 128) (128 0 128) (0 128 128) (192 192 192)
    (128 128 128) (255 0 0) (0 255 0) (255 255 0)
    (0 0 255) (255 0 255) (0 255 255) (255 255 255)))

(defun oklab-map (function values)
  (mapcar function values))

(defun oklab-multiply (matrix x y z)
  (mapcar
   (lambda (row)
     (+ (* (first row) x)
        (* (second row) y)
        (* (third row) z)))
   matrix))

(defun oklab-cube (value)
  (* value value value))

(defun oklab-cbrt (value)
  (if (minusp value)
      (- (expt (- value) (/ 1d0 3d0)))
      (expt value (/ 1d0 3d0))))

(defun oklab-js-round (value)
  (floor (+ value 0.5d0)))

(defun linear-to-srgb (value)
  (if (> value 0.0031308d0)
      (- (* 1.055d0 (expt value (/ 1d0 2.4d0))) 0.055d0)
      (* 12.92d0 value)))

(defun srgb-to-linear (value)
  (if (<= value 0.04045d0)
      (/ value 12.92d0)
      (expt (/ (+ value 0.055d0) 1.055d0) 2.4d0)))

(defun oklab-to-linear-srgb (l a b)
  (let ((lms (oklab-multiply +lab-to-lms+ l a b)))
    (apply #'oklab-multiply +lms-to-linear-srgb+
           (oklab-map #'oklab-cube lms))))

(defun linear-srgb-to-oklab (r g b)
  (apply #'oklab-multiply +lms-to-lab+
         (oklab-map #'oklab-cbrt
                    (oklab-multiply +linear-srgb-to-lms+ r g b))))

(defun rgb-to-oklab (red green blue)
  (apply #'linear-srgb-to-oklab
         (oklab-map #'srgb-to-linear
                    (list (/ red 255d0)
                          (/ green 255d0)
                          (/ blue 255d0)))))

(defun linear-srgb-to-rgb (r g b)
  (mapcar
   (lambda (value)
     (oklab-js-round
      (* (min 1d0 (max 0d0 (linear-to-srgb value))) 255d0)))
   (list r g b)))

(defun lms-slopes (a b)
  (mapcar
   (lambda (row)
     (+ (* (second row) a) (* (third row) b)))
   +lab-to-lms+))

(defun saturation-channel (a b)
  (loop for entry in +saturation-fit+
        for index from 0
        for plane = (first entry)
        when (or (= index 2)
                 (> (+ (* (first plane) a)
                       (* (second plane) b))
                    1d0))
          return index))

(defun max-saturation (a b)
  (let* ((channel (saturation-channel a b))
         (coefficients (second (nth channel +saturation-fit+)))
         (k0 (first coefficients))
         (k1 (second coefficients))
         (k2 (third coefficients))
         (k3 (fourth coefficients))
         (k4 (fifth coefficients))
         (weights (nth channel +lms-to-linear-srgb+))
         (saturation
           (+ k0 (* k1 a) (* k2 b) (* k3 a a) (* k4 a b)))
         (slopes (lms-slopes a b))
         (base (mapcar (lambda (k) (+ 1d0 (* saturation k))) slopes))
         (dot (lambda (values)
                (loop for weight in weights
                      for value in values
                      sum (* weight value)))))
    (let* ((f (funcall dot (mapcar #'oklab-cube base)))
           (f1 (funcall dot
                        (mapcar (lambda (value slope)
                                  (* 3d0 slope value value))
                                base slopes)))
           (f2 (funcall dot
                        (mapcar (lambda (value slope)
                                  (* 6d0 slope slope value))
                                base slopes))))
      (- saturation
         (/ (* f f1)
            (- (* f1 f1) (* 0.5d0 f f2)))))))

(defun oklab-cusp (a b)
  (let* ((saturation (max-saturation a b))
         (linear (oklab-to-linear-srgb 1d0 (* saturation a) (* saturation b)))
         (lightness
           (oklab-cbrt (/ 1d0 (reduce #'max linear)))))
    (list lightness (* lightness saturation))))

(defun max-chroma (a b lightness cusp)
  (let ((cusp-l (first cusp))
        (cusp-c (second cusp)))
    (if (<= lightness cusp-l)
        (/ (* cusp-c lightness) cusp-l)
        (let* ((edge (/ (* cusp-c (- lightness 1d0))
                        (- cusp-l 1d0)))
               (slopes (lms-slopes a b))
               (lms (mapcar (lambda (k) (+ lightness (* edge k))) slopes))
               (cubes (mapcar #'oklab-cube lms))
               (first-derivative
                 (mapcar (lambda (value slope)
                           (* 3d0 slope value value))
                         lms slopes))
               (second-derivative
                 (mapcar (lambda (value slope)
                           (* 6d0 slope slope value))
                         lms slopes))
               (steps
                 (mapcar
                  (lambda (row)
                    (let* ((f (- (loop for weight in row
                                       for value in cubes
                                       sum (* weight value))
                                 1d0))
                           (f1 (loop for weight in row
                                     for value in first-derivative
                                     sum (* weight value)))
                           (f2 (loop for weight in row
                                     for value in second-derivative
                                     sum (* weight value)))
                           (u (/ f1
                                 (- (* f1 f1) (* 0.5d0 f f2)))))
                      (if (>= u 0d0)
                          (- (* f u))
                          most-positive-double-float)))
                  +lms-to-linear-srgb+)))
          (+ edge (reduce #'min steps))))))

(defun chroma-stops (lightness a b)
  (let* ((peak (oklab-cusp a b))
         (c-max (max-chroma a b lightness peak))
         (peak-l (first peak))
         (peak-c (second peak))
         (k (/ c-max
               (min (* lightness (/ peak-c peak-l))
                    (* (- 1d0 lightness)
                       (/ peak-c (- 1d0 peak-l))))))
         (mid-s
           (+ 0.11516993d0
              (/ 1d0
                 (+ 7.4477897d0
                    (* 4.1590124d0 b)
                    (* a
                       (+ -2.19557347d0
                          (* 1.75198401d0 b)
                          (* a
                             (+ -2.13704948d0
                                (* -10.02301043d0 b)
                                (* a
                                   (+ -4.24894561d0
                                      (* 5.38770819d0 b)
                                      (* 4.69891013d0 a)))))))))))
         (mid-t
           (+ 0.11239642d0
              (/ 1d0
                 (+ 1.6132032d0
                    (* -0.68124379d0 b)
                    (* a
                       (+ 0.40370612d0
                          (* 0.90148123d0 b)
                          (* a
                             (+ -0.27087943d0
                                (* 0.6122399d0 b)
                                (* a
                                   (+ 0.00299215d0
                                      (* -0.45399568d0 b)
                                      (* -0.14661872d0 a)))))))))))
         (c-mid
           (* 0.9d0 k
              (expt
               (/ 1d0
                  (+ (expt (/ 1d0 (* lightness mid-s)) 4d0)
                     (expt (/ 1d0 (* (- 1d0 lightness) mid-t)) 4d0)))
               0.25d0)))
         (c0
           (sqrt
            (/ 1d0
               (+ (expt (/ 1d0 (* lightness 0.4d0)) 2d0)
                  (expt (/ 1d0 (* (- 1d0 lightness) 0.8d0)) 2d0))))))
    (list c0 c-mid c-max)))

(defun okhsl-to-oklab-lightness (value)
  (/ (+ (* value value) (* +okhsl-k1+ value))
     (* +okhsl-k3+ (+ value +okhsl-k2+))))

(defun okhsl-to-rgb (hue saturation lightness)
  (let ((l (okhsl-to-oklab-lightness lightness))
        (lab-a 0d0)
        (lab-b 0d0))
    (when (and (> l 0d0) (< l 1d0) (> saturation 0d0))
      (let* ((angle (* 2d0 pi
                       (/ (mod (+ (mod hue 360d0) 360d0) 360d0)
                          360d0)))
             (a (cos angle))
             (b (sin angle))
             (stops (chroma-stops l a b))
             (c0 (first stops))
             (c-mid (second stops))
             (c-max (third stops))
             (chroma
               (if (< saturation 0.8d0)
                   (let* ((scaled (* 1.25d0 saturation))
                          (k1 (* 0.8d0 c0)))
                     (/ (* scaled k1)
                        (- 1d0 (* (- 1d0 (/ k1 c-mid)) scaled))))
                   (let* ((scaled (* 5d0 (- saturation 0.8d0)))
                          (k1 (/ (* 0.2d0 c-mid c-mid 1.25d0 1.25d0)
                                 c0)))
                     (+ c-mid
                        (/ (* scaled k1)
                           (- 1d0
                              (* (- 1d0 (/ k1 (- c-max c-mid)))
                                 scaled))))))))
        (setf lab-a (* chroma a)
              lab-b (* chroma b))))
    (apply #'linear-srgb-to-rgb (oklab-to-linear-srgb l lab-a lab-b))))

(defun srgb-in-gamut-p (channels)
  (every (lambda (channel)
           (<= -1d-7 channel (+ 1d0 1d-7)))
         channels))

(defun oklch-to-rgb (lightness chroma hue)
  (let* ((radians (* hue (/ pi 180d0)))
         (cos (cos radians))
         (sin (sin radians))
         (at-chroma
           (lambda (amount)
             (oklab-to-linear-srgb
              lightness (* amount cos) (* amount sin))))
         (direct (funcall at-chroma chroma)))
    (if (srgb-in-gamut-p direct)
        (apply #'linear-srgb-to-rgb direct)
        (let ((linear (funcall at-chroma 0d0))
              (low 0d0)
              (high chroma))
          (loop repeat 20
                for amount = (/ (+ low high) 2d0)
                for candidate = (funcall at-chroma amount)
                do (if (srgb-in-gamut-p candidate)
                       (setf low amount
                             linear candidate)
                       (setf high amount)))
          (apply #'linear-srgb-to-rgb linear)))))

(defun rgb-hex (red green blue)
  (string-downcase
   (format nil "#~2,'0x~2,'0x~2,'0x" red green blue)))

(defun parse-color-number (text)
  (let ((*read-default-float-format* 'double-float))
    (float (read-from-string text) 1d0)))

(defun indexed-ansi-rgb (index)
  (if (< index 16)
      (nth index +basic-ansi-colors+)
      (if (< index 232)
          (let ((cube (- index 16)))
            (list (aref +ansi-cube-values+ (floor cube 36))
                  (aref +ansi-cube-values+ (floor (mod cube 36) 6))
                  (aref +ansi-cube-values+ (mod cube 6))))
          (let ((gray (+ 8 (* (- index 232) 10))))
            (list gray gray gray)))))

(defun oklab-to-okhsl-lightness (value)
  (* 0.5d0
     (+ (- (* +okhsl-k3+ value) +okhsl-k1+)
        (sqrt
         (+ (expt (- (* +okhsl-k3+ value) +okhsl-k1+) 2d0)
            (* 4d0 +okhsl-k2+ +okhsl-k3+ value))))))

(defun rgb-oklch-channels (red green blue)
  (let* ((lab (rgb-to-oklab red green blue))
         (a (second lab))
         (b (third lab)))
    (values (first lab)
            (sqrt (+ (* a a) (* b b)))
            (mod (+ (* (atan b a) (/ 180d0 pi)) 360d0) 360d0))))

(defun rgb-okhsl-channels (red green blue)
  (let* ((lab (rgb-to-oklab red green blue))
         (l (first lab))
         (a (second lab))
         (b (third lab))
         (chroma (sqrt (+ (* a a) (* b b))))
         (lightness (oklab-to-okhsl-lightness l)))
    (when (or (< chroma 1d-9)
              (<= lightness 0d0)
              (>= lightness 1d0))
      (return-from rgb-okhsl-channels
        (values 0d0 0d0 lightness)))
    (let* ((hue (mod (+ (* (atan b a) (/ 180d0 pi)) 360d0) 360d0))
           (stops (chroma-stops l (/ a chroma) (/ b chroma)))
           (c0 (first stops))
           (c-mid (second stops))
           (c-max (third stops))
           (saturation
             (if (< chroma c-mid)
                 (let ((k1 (* 0.8d0 c0)))
                   (* 0.8d0
                      (/ chroma
                         (+ k1
                            (* (- 1d0 (/ k1 c-mid)) chroma)))))
                 (let ((k1 (/ (* 0.2d0 c-mid c-mid 1.25d0 1.25d0) c0))
                       (offset (- chroma c-mid)))
                   (+ 0.8d0
                      (* 0.2d0
                         (/ offset
                            (+ k1
                               (* (- 1d0 (/ k1 (- c-max c-mid)))
                                  offset)))))))))
      (values hue (min 1d0 (max 0d0 saturation)) lightness))))

(defun wcag-contrast (r1 g1 b1 r2 g2 b2)
  (flet ((luminance (red green blue)
           (+ (* 0.2126d0 (srgb-to-linear (/ red 255d0)))
              (* 0.7152d0 (srgb-to-linear (/ green 255d0)))
              (* 0.0722d0 (srgb-to-linear (/ blue 255d0))))))
    (let ((first (luminance r1 g1 b1))
          (second (luminance r2 g2 b2)))
      (/ (+ (max first second) 0.05d0)
         (+ (min first second) 0.05d0)))))

(defun color-lightness (red green blue)
  (first (rgb-to-oklab red green blue)))

(defun theme-color-lightness (value)
  (cond
    ((and (integerp value) (< value 16))
     nil)
    ((integerp value)
     (apply #'color-lightness (indexed-ansi-rgb value)))
    ((and (stringp value) (= (length value) 7) (char= (char value 0) #\#))
     (let ((rgb (parse-theme-hex-color value)))
       (color-lightness
        (rgb-color-red rgb)
        (rgb-color-green rgb)
        (rgb-color-blue rgb))))
    (t nil)))

(defun normalize-theme-color (value)
  (cond
    ((integerp value)
     (unless (<= 0 value 255)
       (error "ANSI color index must be an integer from 0 to 255: ~A"
              value))
     value)
    ((not (stringp value))
     (error "Invalid color value: ~A" value))
    (t
     (or
      (cl-ppcre:register-groups-bind (digits)
          ("^(?i)#([0-9a-f]{3}|[0-9a-f]{6})$" value)
        (rgb-hex
         (parse-integer
          (if (= (length digits) 3)
              (format nil "~C~C" (char digits 0) (char digits 0))
              (subseq digits 0 2))
          :radix 16)
         (parse-integer
          (if (= (length digits) 3)
              (format nil "~C~C" (char digits 1) (char digits 1))
              (subseq digits 2 4))
          :radix 16)
         (parse-integer
          (if (= (length digits) 3)
              (format nil "~C~C" (char digits 2) (char digits 2))
              (subseq digits 4 6))
          :radix 16)))
      (let ((number
              "[+-]?(?:\\d+(?:\\.\\d*)?|\\.\\d+)(?:e[+-]?\\d+)?"))
        (or
         (cl-ppcre:register-groups-bind (l percent c h)
             ((format nil
                      "(?i)^oklch\\(\\s*(~A)(%)?\\s+(~A)\\s+(~A)(?:deg)?\\s*\\)$"
                      number number number)
              value)
           (let ((lightness
                   (/ (parse-color-number l)
                      (if percent 100d0 1d0))))
             (unless (<= 0d0 lightness 1d0)
               (error "l must be between 0 and 1: ~A" lightness))
             (let ((chroma (parse-color-number c)))
               (when (minusp chroma)
                 (error "c must not be negative: ~A" chroma))
               (apply #'rgb-hex
                      (oklch-to-rgb
                       lightness chroma
                       (mod (+ (mod (parse-color-number h) 360d0) 360d0)
                            360d0))))))
         (cl-ppcre:register-groups-bind (h s s-percent l l-percent)
             ((format nil
                      "(?i)^okhsl\\(\\s*(~A)(?:deg)?\\s+(~A)(%)?\\s+(~A)(%)?\\s*\\)$"
                      number number number)
              value)
           (let ((saturation
                   (/ (parse-color-number s)
                      (if s-percent 100d0 1d0)))
                 (lightness
                   (/ (parse-color-number l)
                      (if l-percent 100d0 1d0))))
             (unless (<= 0d0 saturation 1d0)
               (error "s must be between 0 and 1: ~A" saturation))
             (unless (<= 0d0 lightness 1d0)
               (error "l must be between 0 and 1: ~A" lightness))
             (apply #'rgb-hex
                    (okhsl-to-rgb
                     (parse-color-number h) saturation lightness))))
         (error "Invalid color value: ~A" value)))))))

(defun resolve-theme-color-value
    (value variables &optional seen)
  (cond
    ((integerp value)
     (unless (<= 0 value 255)
       (error "Theme color index is outside 0..255: ~S"
              value))
     value)
    ((not (stringp value))
     (error "Theme color must be a string or integer: ~S"
            value))
    ((zerop (length value))
     "")
    ((or (char= (char value 0) #\#)
         (and (>= (length value) 5)
              (or (string-equal value "oklch" :end1 5)
                  (string-equal value "okhsl" :end1 5))))
     (normalize-theme-color value))
    ((member value seen :test #'string=)
     (error "Cyclic theme variable reference: ~A" value))
    (t
     (multiple-value-bind (resolved present-p)
         (gethash value variables)
       (unless present-p
         (error "Unknown theme variable: ~A" value))
       (resolve-theme-color-value
        resolved variables (cons value seen))))))

(defun builtin-theme-color-alist (document)
  (let ((variables
          (or (gethash "vars" document)
              (make-hash-table :test #'equal)))
        (colors (gethash "colors" document))
        (export (gethash "export" document)))
    (unless (hash-table-p variables)
      (error "Theme vars must be an object"))
    (mapcar
     (lambda (key)
       (let* ((name (theme-json-name key))
              (raw
                (or (and (hash-table-p colors)
                         (nth-value 0 (gethash name colors)))
                    (and (hash-table-p export)
                         (nth-value 0 (gethash name export))))))
         (unless raw
           (error "Built-in theme is missing ~A" name))
         (cons key
               (resolve-theme-color-value raw variables))))
     +builtin-theme-color-keys+)))

(defun install-builtin-theme-colors ()
  (unless (and +dark-theme-colors+ +light-theme-colors+)
    (setf +dark-theme-colors+
          (builtin-theme-color-alist
           (read-theme-json (builtin-theme-json-text :dark)))
          +light-theme-colors+
          (builtin-theme-color-alist
           (read-theme-json (builtin-theme-json-text :light)))))
  nil)

(setf *install-builtin-theme-colors*
      #'install-builtin-theme-colors)

(install-builtin-theme-colors)
