(in-package #:cadr-cli)

;; pi@71023aec1 system-theme.ts. Colors come from the terminal palette and
;; background. With no background, tokens are ANSI indexes and faint neutrals.

(defparameter +system-families+
  '(("neutral" 231.49d0 0.02d0 0.08d0 8)
    ("blue" 231.49d0 0.1d0 0.68d0 4)
    ("green" 158.68d0 0.1d0 0.76d0 2)
    ("red" 20d0 0.1d0 0.92d0 1)
    ("yellow" 82.36d0 0.5d0 1d0 3)
    ("orange" 52d0 0.12d0 0.85d0 3)
    ("violet" 295d0 0.2d0 0.6d0 5)
    ("calamine" 202.43d0 0.1d0 0.74d0 6)
    ("thinkingSlate" 231.49d0 0.08d0 0.2d0 4)
    ("thinkingBlue" 231.49d0 0.2d0 0.45d0 4)
    ("thinkingPeriwinkle" 263.25d0 0.3d0 0.6d0 6)
    ("thinkingViolet" 295d0 0.4d0 0.75d0 5)
    ("thinkingMagenta" 337.5d0 0.5d0 0.85d0 13)
    ("thinkingRed" 20d0 0.95d0 1d0 1)))

(defparameter +system-token-families+
  '(("selectedBg" . "blue")
    ("searchMatchBg" . "orange")
    ("userMessageBg" . "blue")
    ("customMessageBg" . "violet")
    ("toolPendingBg" . "neutral")
    ("toolSuccessBg" . "green")
    ("toolErrorBg" . "red")
    ("text" . "neutral")
    ("userMessageText" . "neutral")
    ("customMessageText" . "neutral")
    ("toolTitle" . "neutral")
    ("syntaxOperator" . "neutral")
    ("syntaxPunctuation" . "neutral")
    ("muted" . "neutral")
    ("dim" . "neutral")
    ("thinkingText" . "neutral")
    ("toolOutput" . "neutral")
    ("mdLinkUrl" . "neutral")
    ("mdQuote" . "neutral")
    ("mdQuoteBorder" . "neutral")
    ("mdHr" . "neutral")
    ("mdCodeBlockBorder" . "neutral")
    ("toolDiffContext" . "neutral")
    ("syntaxComment" . "neutral")
    ("scrollbarTrack" . "neutral")
    ("scrollbarThumb" . "neutral")
    ("searchMatchText" . "neutral")
    ("borderMuted" . "neutral")
    ("accent" . "violet")
    ("borderAccent" . "violet")
    ("customMessageLabel" . "violet")
    ("mdCode" . "violet")
    ("mdListBullet" . "violet")
    ("syntaxType" . "violet")
    ("border" . "blue")
    ("mdLink" . "blue")
    ("syntaxKeyword" . "blue")
    ("syntaxVariable" . "calamine")
    ("success" . "green")
    ("mdCodeBlock" . "green")
    ("toolDiffAdded" . "green")
    ("bashMode" . "green")
    ("syntaxNumber" . "green")
    ("error" . "red")
    ("toolDiffRemoved" . "red")
    ("warning" . "yellow")
    ("mdHeading" . "yellow")
    ("syntaxFunction" . "yellow")
    ("syntaxString" . "orange")
    ("thinkingOff" . "neutral")
    ("thinkingMinimal" . "thinkingSlate")
    ("thinkingLow" . "thinkingBlue")
    ("thinkingMedium" . "thinkingPeriwinkle")
    ("thinkingHigh" . "thinkingViolet")
    ("thinkingXhigh" . "thinkingMagenta")
    ("thinkingMax" . "thinkingRed")))

(defparameter +system-token-slots+
  '(("syntaxString" . 2) ("syntaxNumber" . 5) ("searchMatchBg" . 3)))

(defparameter +system-panels+
  '("userMessageBg" "toolPendingBg" "toolSuccessBg" "toolErrorBg"
    "selectedBg" "searchMatchBg" "customMessageBg"))

(defparameter +system-foreground-tokens+
  '("text" "userMessageText" "toolTitle"))

(defparameter +system-text-contrast+ 4.5d0)

(defun system-level (name appearance coefficients low high)
  (list name appearance coefficients low high))

(defparameter +system-levels+
  (list
   (system-level "panel" :dark
                 '(0.29131d0 -0.39746d0 2.33185d0 -0.85524d0 -1.2076d0 0.86276d0)
                 0d0 0.979d0)
   (system-level "panel" :light
                 '(-3.74073d0 27.94549d0 -78.44258d0 112.6798d0 -79.60015d0 22.11277d0)
                 0.348d0 1d0)
   (system-level "track" :dark
                 '(0.39028d0 -0.23015d0 0.83573d0 2.43829d0 -4.38292d0 2.01582d0)
                 0d0 0.946d0)
   (system-level "track" :light
                 '(-5.24921d0 38.37322d0 -107.28833d0 152.10005d0 -106.17127d0 29.18061d0)
                 0.368d0 1d0)
   (system-level "thinking0" :dark
                 '(0.52988d0 -0.05809d0 -0.30924d0 4.63567d0 -6.52933d0 2.89108d0)
                 0d0 0.873d0)
   (system-level "thinking0" :light
                 '(-28.27749d0 182.85284d0 -469.62416d0 603.15916d0 -384.59976d0 97.35147d0)
                 0.51d0 1d0)
   (system-level "thinking1" :dark
                 '(0.55278d0 -0.03667d0 -0.45659d0 4.95347d0 -6.90265d0 3.0706d0)
                 0d0 0.858d0)
   (system-level "thinking1" :light
                 '(-37.10484d0 235.86282d0 -596.62344d0 754.3633d0 -474.00763d0 118.3551d0)
                 0.535d0 1d0)
   (system-level "thinking2" :dark
                 '(0.57486d0 -0.01765d0 -0.58987d0 5.25227d0 -7.27175d0 3.25532d0)
                 0d0 0.842d0)
   (system-level "thinking2" :light
                 '(-59.89653d0 377.05024d0 -945.07843d0 1182.03145d0 -734.96375d0 181.68658d0)
                 0.556d0 1d0)
   (system-level "thinking3" :dark
                 '(0.59621d0 -0.00062d0 -0.71148d0 5.53588d0 -7.6392d0 3.44606d0)
                 0d0 0.827d0)
   (system-level "thinking3" :light
                 '(-72.07122d0 445.84082d0 -1099.57352d0 1353.88793d0 -829.53392d0 202.26164d0)
                 0.58d0 1d0)
   (system-level "thinking4" :dark
                 '(0.61691d0 0.01462d0 -0.82288d0 5.80651d0 -8.00641d0 3.64333d0)
                 0d0 0.811d0)
   (system-level "thinking4" :light
                 '(-110.14338d0 674.21488d0 -1645.75941d0 2004.32367d0 -1215.15899d0 293.3183d0)
                 0.6d0 1d0)
   (system-level "thinking5" :dark
                 '(0.63702d0 0.02826d0 -0.92498d0 6.06465d0 -8.37246d0 3.84651d0)
                 0d0 0.795d0)
   (system-level "thinking5" :light
                 '(-175.47701d0 1063.54495d0 -2570.70594d0 3098.80776d0 -1860.15527d0 444.76392d0)
                 0.62d0 1d0)
   (system-level "thinking6" :dark
                 '(0.65658d0 0.04044d0 -1.01835d0 6.30989d0 -8.73529d0 4.05439d0)
                 0d0 0.779d0)
   (system-level "thinking6" :light
                 '(-183.81712d0 1094.70055d0 -2602.68539d0 3088.71276d0 -1826.91131d0 430.75931d0)
                 0.643d0 1d0)
   (system-level "subtle" :dark
                 '(0.56762d0 -0.02475d0 -0.5383d0 5.12628d0 -7.10931d0 3.17324d0)
                 0d0 0.848d0)
   (system-level "subtle" :light
                 '(-232.85459d0 1376.54473d0 -3249.11801d0 3827.91186d0 -2248.29472d0 526.55751d0)
                 0.657d0 1d0)
   (system-level "thumb" :dark
                 '(0.60323d0 0.00278d0 -0.73328d0 5.57157d0 -7.68067d0 3.46933d0)
                 0d0 0.823d0)
   (system-level "thumb" :light
                 '(-82.89897d0 511.01355d0 -1255.98095d0 1540.76821d0 -940.68087d0 228.58523d0)
                 0.586d0 1d0)
   (system-level "readable" :dark
                 '(0.66937d0 0.04704d0 -1.06871d0 6.43941d0 -8.9332d0 4.17229d0)
                 0d0 0.77d0)
   (system-level "readable" :light
                 '(-1554.52576d0 8733.56817d0 -19604.93507d0 21977.72696d0 -12300.99599d0 2749.81288d0)
                 0.751d0 1d0)
   (system-level "emphasis" :dark
                 '(0.7303d0 0.07695d0 -1.31626d0 7.1681d0 -10.14436d0 4.92846d0)
                 0d0 0.712d0)
   (system-level "emphasis" :light
                 '(-4948.31942d0 26870.91986d0 -58334.48399d0 63280.17197d0 -34298.01053d0 7430.30146d0)
                 0.811d0 1d0)
   (system-level "textOnPanel" :dark
                 '(0.86713d0 0.05232d0 -0.89428d0 4.79014d0 -5.5432d0 1.75023d0)
                 0d0 0.542d0)
   (system-level "textOnPanel" :light
                 '(-8570.89457d0 43954.60805d0 -90084.00702d0 92220.6791d0 -47152.15802d0 9632.27113d0)
                 0.867d0 1d0)
   (system-level "text" :dark
                 '(0.89242d0 0.02311d0 -0.44862d0 2.34417d0 -0.06084d0 -2.63844d0)
                 0d0 0.5d0)
   (system-level "text" :light
                 '(-2004.67048d0 6664.47299d0 -6060.70202d0 -1792.61209d0 5133.82359d0 -1939.85583d0)
                 0.894d0 1d0)))

(defun system-rule (token level surfaces)
  (list token level surfaces))

(defun system-rules (tokens surfaces level)
  (mapcar (lambda (token) (system-rule token level surfaces)) tokens))

(defparameter +system-tool-panels+
  '("toolPendingBg" "toolSuccessBg" "toolErrorBg"))

(defparameter +system-message-panels+
  '("userMessageBg" "customMessageBg"))

(defparameter +system-rules+
  (append
   (system-rules +system-panels+ '("background") "panel")
   (list
    (system-rule "text" "text" '("background"))
    (system-rule "text" "textOnPanel" '("selectedBg"))
    (system-rule "userMessageText" "textOnPanel" '("userMessageBg"))
    (system-rule "toolTitle" "textOnPanel" +system-tool-panels+)
    (system-rule "muted" "readable"
                 (append '("background" "selectedBg" "customMessageBg")
                         +system-tool-panels+))
    (system-rule "dim" "subtle"
                 (append '("background" "selectedBg" "customMessageBg")
                         +system-tool-panels+))
    (system-rule "thinkingText" "readable" '("background"))
    (system-rule "customMessageText" "readable"
                 (append '("customMessageBg") +system-tool-panels+))
    (system-rule "customMessageLabel" "readable"
                 (append '("background" "customMessageBg" "selectedBg")
                         +system-tool-panels+))
    (system-rule "toolOutput" "readable"
                 (append '("background") +system-tool-panels+))
    (system-rule "mdCodeBlock" "readable"
                 (append '("background")
                         +system-message-panels+
                         +system-tool-panels+))
    (system-rule "searchMatchText" "readable" '("searchMatchBg"))
    (system-rule "borderMuted" "subtle" '("background"))
    (system-rule "scrollbarTrack" "track" '("background"))
    (system-rule "scrollbarThumb" "thumb" '("scrollbarTrack")))
   (system-rules '("accent" "success" "error" "warning")
                 (append '("background" "selectedBg") +system-tool-panels+)
                 "readable")
   (system-rules '("mdHeading" "mdLink" "mdLinkUrl" "mdCode" "mdQuote"
                   "mdCodeBlockBorder" "mdListBullet")
                 (append '("background") +system-message-panels+)
                 "readable")
   (system-rules '("toolDiffAdded" "toolDiffRemoved" "toolDiffContext")
                 (append '("background") +system-tool-panels+)
                 "readable")
   (system-rules '("syntaxComment" "syntaxKeyword" "syntaxFunction"
                   "syntaxVariable" "syntaxString" "syntaxNumber"
                   "syntaxType" "syntaxOperator" "syntaxPunctuation")
                 (append '("background")
                         +system-message-panels+
                         +system-tool-panels+)
                 "readable")
   (system-rules '("bashMode" "border" "borderAccent")
                 '("background") "readable")
   (system-rules '("mdQuoteBorder" "mdHr")
                 (append '("background")
                         +system-message-panels+
                         +system-tool-panels+)
                 "readable")
   (loop for token in '("thinkingOff" "thinkingMinimal" "thinkingLow"
                        "thinkingMedium" "thinkingHigh" "thinkingXhigh"
                        "thinkingMax")
         for level in '("thinking0" "thinking1" "thinking2" "thinking3"
                        "thinking4" "thinking5" "thinking6")
         collect (system-rule token level '("background")))))

(defun system-solve-order ()
  (let ((order nil))
    (labels ((visit (token)
               (unless (member token order :test #'string=)
                 (dolist (rule +system-rules+)
                   (when (string= (first rule) token)
                     (dolist (surface (third rule))
                       (unless (string= surface "background")
                         (visit surface)))))
                 (push token order))))
      (dolist (rule +system-rules+)
        (visit (first rule)))
      (nreverse order))))

(defparameter +system-solve-order+ (system-solve-order))

(defun system-family (name)
  (assoc name +system-families+ :test #'string=))

(defun system-polynomial (coefficients value)
  (loop for coefficient in coefficients
        for power from 0
        sum (* coefficient (expt value power))))

(defun system-level-target (level appearance surface-l)
  (let ((curve
          (find-if
           (lambda (entry)
             (and (string= (first entry) level)
                  (eq (second entry) appearance)))
           +system-levels+)))
    (when (and curve
               (<= (fourth curve) surface-l (fifth curve)))
      (system-polynomial (third curve) surface-l))))

(defun system-hex (rgb)
  (cadr-tui::rgb-hex (first rgb) (second rgb) (third rgb)))

(defun system-lightness (rgb)
  (cadr-tui:color-lightness (first rgb) (second rgb) (third rgb)))

(defun system-contrast (first second)
  (cadr-tui:wcag-contrast
   (first first) (second first) (third first)
   (first second) (second second) (third second)))

(defun system-terminal-appearance (background foreground)
  (let* ((white '(255 255 255))
         (black '(0 0 0))
         (white-contrast (system-contrast white background))
         (black-contrast (system-contrast black background)))
    (when foreground
      (let ((foreground-l (system-lightness foreground))
            (background-l (system-lightness background)))
        (when (> (abs (- foreground-l background-l)) 0.05d0)
          (let* ((appearance
                   (if (> foreground-l background-l) :dark :light))
                 (best
                   (if (eq appearance :dark)
                       white-contrast
                       black-contrast)))
            (when (>= best +system-text-contrast+)
              (return-from system-terminal-appearance appearance))))))
    (if (>= white-contrast black-contrast) :dark :light)))

(defun system-bell (lightness)
  (flet ((gaussian (value)
           (exp (- (/ (expt (- value 0.5d0) 2d0)
                      (* 2d0 (expt 0.25d0 2d0)))))))
    (/ (- (gaussian lightness) (gaussian 0d0))
       (- 1d0 (gaussian 0d0)))))

(defun system-saturation-curve (family lightness)
  (let* ((min (third family))
         (max (fourth family))
         (floor (if (> max 0d0) (/ min max) 1d0)))
    (+ floor (* (- 1d0 floor) (system-bell lightness)))))

(defun system-source (rgb)
  (multiple-value-bind (hue saturation lightness)
      (cadr-tui:rgb-okhsl-channels
       (first rgb) (second rgb) (third rgb))
    (multiple-value-bind (l chroma h)
        (cadr-tui:rgb-oklch-channels
         (first rgb) (second rgb) (third rgb))
      (declare (ignore l h))
      (list hue saturation lightness chroma))))

(defun system-anchored (source family lightness saturation)
  (let* ((anchor (system-saturation-curve family (third source)))
         (falloff
           (if (> anchor 0d0)
               (min 1d0
                    (/ (system-saturation-curve family lightness)
                       anchor))
               1d0))
         (color
           (cadr-tui:okhsl-to-rgb
            (first source)
            (* (second source) falloff saturation)
            lightness))
         (cap (* (fourth source) falloff saturation)))
    (multiple-value-bind (l chroma h)
        (cadr-tui:rgb-oklch-channels
         (first color) (second color) (third color))
      (declare (ignore h))
      (if (<= chroma cap)
          color
          (cadr-tui:oklch-to-rgb l cap (first source))))))

(defun system-indexed-colors (saturation appearance)
  (let ((colors (make-hash-table :test #'equal))
        (dim nil))
    (dolist (entry +system-token-families+)
      (let ((token (car entry))
            (family (cdr entry)))
        (cond
          ((member token +system-panels+ :test #'string=)
           (setf (gethash token colors) ""))
          (t
           (let ((neutral (string= family "neutral")))
             (setf (gethash token colors)
                   (if (and (not neutral) (> saturation 0d0))
                       (or (cdr (assoc token +system-token-slots+
                                       :test #'string=))
                           (fifth (system-family family)))
                       ""))
             (when (and neutral
                        (not (member token +system-foreground-tokens+
                                     :test #'string=)))
               (push token dim)))))))
    (values colors (nreverse dim) appearance)))

(defun generate-system-theme-colors
    (&key foreground background palette (saturation 1d0) appearance-hint)
  (let ((saturation (max 0d0 (min 1d0 saturation))))
    (unless background
      (return-from generate-system-theme-colors
        (system-indexed-colors saturation appearance-hint)))
    (let* ((palette
             (and (listp palette)
                  (= (length palette) 16)
                  (mapcar #'system-source palette)))
           (appearance
             (system-terminal-appearance background foreground))
           (lighter (eq appearance :dark))
           (extreme (if lighter 1d0 0d0))
           (background-l (system-lightness background))
           (readable-floor (if lighter "readable" "subtle")))
      (labels ((paint (token oklab-l)
                 (let* ((lightness
                          (cadr-tui:oklab-to-okhsl-lightness oklab-l))
                        (family
                          (system-family
                           (cdr (assoc token +system-token-families+
                                       :test #'string=)))))
                   (if (not palette)
                       (let ((min (third family))
                             (max (fourth family)))
                         (cadr-tui:okhsl-to-rgb
                          (second family)
                          (* (+ min (* (- max min) (system-bell lightness)))
                             saturation)
                          lightness))
                       (system-anchored
                        (nth (or (cdr (assoc token +system-token-slots+
                                             :test #'string=))
                                 (fifth family))
                             palette)
                        family lightness saturation))))
               (target (level surface-l relaxation)
                 (let* ((reached
                          (system-level-target level appearance surface-l))
                        (distance (- (or reached extreme) surface-l))
                        (floor
                          (- (or (system-level-target
                                  readable-floor appearance surface-l)
                                 extreme)
                             surface-l))
                        (compressed
                          (if (> (abs distance) (abs floor))
                              (- distance
                                 (* (- distance floor)
                                    (min relaxation 1d0)))
                              distance)))
                   (when (or reached (/= relaxation 0d0))
                     (+ surface-l
                        (* compressed
                           (- 1d0 (max 0d0 (- relaxation 1d0))))))))
               (readable (color)
                 (>= (system-contrast
                      (if lighter '(255 255 255) '(0 0 0))
                      color)
                     +system-text-contrast+))
               (limit-panel (token lightness)
                 (let ((color (paint token lightness)))
                   (if (readable color)
                       color
                       (let ((low background-l)
                             (high lightness))
                         (loop repeat 20
                               for middle = (/ (+ low high) 2d0)
                               do (if (readable (paint token middle))
                                      (setf low middle)
                                      (setf high middle)))
                         (paint token low)))))
               (solve (relaxation)
                 (let ((colors (make-hash-table :test #'equal)))
                   (setf (gethash "background" colors) background)
                   (dolist (token +system-solve-order+)
                     (let ((targets nil))
                       (dolist (rule +system-rules+)
                         (when (string= (first rule) token)
                           (dolist (surface (third rule))
                             (let ((value
                                     (target
                                      (second rule)
                                      (system-lightness
                                       (or (gethash surface colors)
                                           background))
                                      relaxation)))
                               (when (or (null value)
                                         (< value 0d0)
                                         (> value 1d0))
                                 (return-from solve nil))
                               (push value targets)))))
                       (let ((lightness
                               (if lighter
                                   (reduce #'max targets)
                                   (reduce #'min targets))))
                         (setf (gethash token colors)
                               (if (member token +system-panels+
                                           :test #'string=)
                                   (limit-panel token lightness)
                                   (paint token lightness))))))
                   colors)))
        (let ((relaxation 0d0)
              (colors (solve 0d0)))
          (unless colors
            (let ((low 0d0)
                  (high 2d0))
              (setf colors (solve high))
              (loop repeat 20
                    for middle = (/ (+ low high) 2d0)
                    for attempt = (solve middle)
                    do (if attempt
                           (setf high middle
                                 colors attempt)
                           (setf low middle)))
              (setf relaxation high)))
          (let ((solved (or colors (make-hash-table :test #'equal)))
                (result (make-hash-table :test #'equal)))
            (dolist (entry +system-token-families+)
              (let ((color (gethash (car entry) solved)))
                (setf (gethash (car entry) result)
                      (if color (system-hex color) ""))))
            (dolist (token +system-foreground-tokens+)
              (let ((surfaces
                      (loop for rule in +system-rules+
                            when (string= (first rule) token)
                              append (mapcar
                                      (lambda (surface)
                                        (or (gethash surface solved)
                                            background))
                                      (third rule))))
                    (text (gethash token solved))
                    (kept-default nil))
                (when foreground
                  (let ((targets
                          (mapcar
                           (lambda (surface)
                             (target "emphasis"
                                     (system-lightness surface)
                                     relaxation))
                           surfaces)))
                    (when (every (lambda (value)
                                   (and value (<= 0d0 value 1d0)))
                                 targets)
                      (let ((needed
                              (if lighter
                                  (reduce #'max targets)
                                  (reduce #'min targets)))
                            (foreground-l (system-lightness foreground)))
                        (if (if lighter
                                (>= foreground-l needed)
                                (<= foreground-l needed))
                            (setf (gethash token result) ""
                                  kept-default t)
                            (setf text
                                  (system-anchored
                                   (system-source foreground)
                                   (system-family "neutral")
                                   (cadr-tui:oklab-to-okhsl-lightness needed)
                                   saturation)))))))
                (unless kept-default
                  (when text
                    (setf (gethash token result)
                          (system-hex
                           (system-with-text-contrast
                            text surfaces lighter)))))))
            (values result nil appearance)))))))

(defun system-with-text-contrast (color surfaces lighter)
  (flet ((meets (candidate)
           (every (lambda (surface)
                    (>= (system-contrast candidate surface)
                        +system-text-contrast+))
                  surfaces)))
    (if (meets color)
        color
        (multiple-value-bind (hue saturation lightness)
            (cadr-tui:rgb-okhsl-channels
             (first color) (second color) (third color))
          (flet ((at (value)
                   (cadr-tui:okhsl-to-rgb hue saturation value)))
            (let ((extreme (if lighter 1d0 0d0)))
              (if (not (meets (at extreme)))
                  (at extreme)
                  (let ((low lightness)
                        (high extreme))
                    (loop repeat 20
                          for middle = (/ (+ low high) 2d0)
                          do (if (meets (at middle))
                                 (setf high middle)
                                 (setf low middle)))
                    (at high)))))))))
