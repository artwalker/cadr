(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defun egg-test-sha256-hex (text)
  (string-downcase
   (format nil "~{~2,'0X~}"
           (coerce (cadr-ai::sha256-bytes (cadr-ai::utf8-octets text))
                   'list))))

(defun egg-test-frame-hash (animation width)
  (let* ((lines (cadr-tui:component-render animation width))
         (joined (format nil "~{~A~^~%~}" lines)))
    (egg-test-sha256-hex joined)))

(test egg-hash-matches-v1.4.0-imul-mix
  ;; Locked to Node Math.imul / >>> of easter-egg-3d.ts hash().
  (is (= 0.11478774505667388d0 (cadr-cli::egg-hash 0)))
  (is (= 0.24678996880538762d0 (cadr-cli::egg-hash 1)))
  (is (= 0.02330568921752274d0 (cadr-cli::egg-hash 2)))
  (is (= 0.38546495721675456d0 (cadr-cli::egg-hash 7)))
  (is (= 0.09437634493224323d0 (cadr-cli::egg-hash 7919)))
  (is (= 0.8311750083230436d0 (cadr-cli::egg-hash #x51ed))))

(test egg-spin-angle-matches-v1.4.0-timeline
  (is (= 0d0 (cadr-cli::egg-spin-angle 0d0)))
  (is (< (abs (- (cadr-cli::egg-spin-angle 1.4d0) 2.9486011175136504d0))
         1d-9))
  (is (< (abs (- (cadr-cli::egg-spin-angle cadr-cli::+egg-first-front-view+)
                 12.566370614359172d0))
         1d-9)))

(test egg-pi-logo-model-has-ten-blocks
  (let ((model (cadr-cli::pi-logo-model 1 1)))
    (is (= 10 (length (cadr-cli::egg-model-blocks model))))
    (is (equal
         '((0 0 228 138 122) (1 0 228 138 122) (2 0 228 138 122)
           (0 1 79 142 179) (2 1 228 138 122)
           (0 2 79 142 179) (1 2 79 142 179) (3 2 234 182 93)
           (0 3 79 142 179) (3 3 234 182 93))
         (mapcar
          (lambda (block)
            (list (cadr-cli::egg-block-hx block)
                  (cadr-cli::egg-block-hy block)
                  (floor (first (cadr-cli::egg-block-color block)))
                  (floor (second (cadr-cli::egg-block-color block)))
                  (floor (third (cadr-cli::egg-block-color block)))))
          (cadr-cli::egg-model-blocks model))))))

(test egg-render-frames-match-v1.4.0-node-goldens
  ;; SHA256 of lines.join("\n") from Node on v1.4.0, dark-theme muted/dim,
  ;; foreground 212,212,212, background 0,0,0, width 24, height 8.
  (let* ((screen
           (list "hello"
                 (format nil "~C[38;2;10;20;30mwide~C[0m" #\Escape #\Escape)
                 "  x"))
         (fg '(212d0 212d0 212d0))
         (bg '(0d0 0d0 0d0))
         (model (cadr-cli::pi-logo-model 1 1))
         (saved-theme (cadr-tui:current-theme)))
    (unwind-protect
         (progn
           (cadr-tui:reset-current-theme)
           (setf (cadr-tui:terminal-theme-color-mode
                  (cadr-tui:current-theme))
                 :truecolor)
           (dolist (pair '((0d0
                            "6a1bdc88a4f72b51e58253c0a97e30dda82384ad6d180c55df7ae25c41ffb0f2")
                           (0.1d0
                            "f5aa3a7a3ccb08ecd82c980ae3b76cbdf596969df30d38c4abf51388478f7e2a")
                           (0.5d0
                            "72ea6ae17c6f24fe6177c007cd2a9b46cf08688e6e5e748ca2482d8dd62c0aab")
                           (1.5d0
                            "aea189f767659c2d84cfa053fc956caab5404f679d3fefefd7db984fe38602ca")
                           (4d0
                            "dad790d59cd5846c90a5943a2affa2ac0c49a7258e7811b865f084f66dcc0ee4")
                           (7d0
                            "c51c013d429d2d9654269a47e996c275e1589bd888810b31b1ddfea9d5f6d023")))
             (destructuring-bind (elapsed expected) pair
               (let ((animation
                       (cadr-cli::make-easter-egg-3d-animation
                        screen model fg bg (lambda ())
                        :rows 8
                        :forced-elapsed elapsed
                        :start-p nil)))
                 (is (string= expected (egg-test-frame-hash animation 24))
                     "elapsed ~A expected ~A" elapsed expected)
                 (cadr-tui:component-dispose animation)))))
      (cadr-tui:set-current-theme saved-theme))))

(test egg-theme-colors-match-v140-dark-and-follow-overrides
  ;; initTheme("dark") on Node 22.22.0: muted 157,165,169 dim 126,136,142
  ;; accent 167,152,215 text 222,224,225. A replaced token follows the theme.
  (cadr-tui:reset-current-theme)
  (unwind-protect
       (progn
         (is (equal '(157d0 165d0 169d0) (cadr-cli::egg-theme-rgb :muted)))
         (is (equal '(126d0 136d0 142d0) (cadr-cli::egg-theme-rgb :dim)))
         (is (equal '(167d0 152d0 215d0) (cadr-cli::egg-theme-rgb :accent)))
         (is (equal '(222d0 224d0 225d0) (cadr-cli::egg-theme-rgb :text)))
         (let ((model
                 (cadr-cli::armin-egg-model
                  (cadr-cli::egg-theme-rgb :accent))))
           (is (equal '(167d0 152d0 215d0)
                      (cadr-cli::egg-block-color
                       (first (cadr-cli::egg-model-blocks model))))))
         (multiple-value-bind (foreground background)
             (cadr-cli::egg-resolved-colors
              (cadr-tui:make-process-terminal))
           (is (equal '(222d0 224d0 225d0) foreground))
           (is (equal '(0d0 0d0 0d0) background)))
         (cadr-tui:set-current-theme
          :dark :overrides '((:accent . "#010203")))
         (is (equal '(1d0 2d0 3d0) (cadr-cli::egg-theme-rgb :accent)))
         (is (equal '(157d0 165d0 169d0) (cadr-cli::egg-theme-rgb :muted)))
         (cadr-tui:set-current-theme :light)
         (is (equal '(108d0 108d0 108d0) (cadr-cli::egg-theme-rgb :muted)))
         (is (equal '(118d0 118d0 118d0) (cadr-cli::egg-theme-rgb :dim)))
         (is (equal '(90d0 128d0 128d0) (cadr-cli::egg-theme-rgb :accent)))
         (is (equal '(31d0 35d0 40d0) (cadr-cli::egg-theme-rgb :text))))
    (cadr-tui:reset-current-theme)))

(test egg-logo-click-origin-hits-half-block-mark
  (multiple-value-bind (top bottom)
      (cadr-cli::pi-logo-lines :mode :truecolor)
    (let* ((pad " ")
           (lines (list (concatenate 'string pad top)
                        (concatenate 'string pad bottom)
                        "prompt")))
      (multiple-value-bind (column row)
          (cadr-cli::pi-logo-click-origin lines 1 0)
        (is (= 1 column))
        (is (= 0 row)))
      (multiple-value-bind (column row)
          (cadr-cli::pi-logo-click-origin lines 4 1)
        (is (= 1 column))
        (is (= 0 row)))
      (is (null (cadr-cli::pi-logo-click-origin lines 0 0)))
      (is (null (cadr-cli::pi-logo-click-origin lines 5 0)))
      (is (null (cadr-cli::pi-logo-click-origin lines 1 2))))))

(test egg-play-gates-match-lazy-contract
  ;; Mirrors easter-egg-3d.lazy.ts: not alt -> false; overlay/playing -> true.
  (setf cadr-cli::*easter-egg-playing* nil)
  (let* ((terminal (cadr-tui:make-process-terminal))
         (main (cadr-tui:make-terminal-renderer terminal :alt-p nil))
         (alt (cadr-tui:make-terminal-renderer terminal :alt-p t)))
    (multiple-value-bind (ok animation)
        (cadr-cli::play-easter-egg-3d
         terminal main '("x")
         (list :kind :pi-logo :column 1 :row 0)
         :overlay-check (constantly nil))
      (is (null ok))
      (is (null animation)))
    (multiple-value-bind (ok animation)
        (cadr-cli::play-easter-egg-3d
         terminal alt '("x")
         (list :kind :pi-logo :column 1 :row 0)
         :overlay-check (constantly t))
      (is-true ok)
      (is (null animation)))
    (setf cadr-cli::*easter-egg-playing* t)
    (multiple-value-bind (ok animation)
        (cadr-cli::play-easter-egg-3d
         terminal alt '("x")
         (list :kind :pi-logo :column 1 :row 0)
         :overlay-check (constantly nil))
      (is-true ok)
      (is (null animation)))
    (setf cadr-cli::*easter-egg-playing* nil)))

(defun egg-test-logo-lines ()
  (multiple-value-bind (top bottom)
      (cadr-cli::pi-logo-lines :mode :truecolor)
    (list (concatenate 'string " " top)
          (concatenate 'string " " bottom)
          "prompt")))

(test egg-visible-overlay-swallows-logo-and-armin
  ;; v1.4.0 playEasterEgg3d: not TuiAltScreen -> false, even with an
  ;; overlay. hasOverlay (any visible overlay, including nonCapturing)
  ;; -> true and does not play. handleArminSaysHi returns on true, so
  ;; no inline Armin. BuiltInHeader still claims the 4x2 click.
  (setf cadr-cli::*easter-egg-playing* nil)
  (let* ((visible
           (cadr-cli::make-extension-custom-ui-state
            :overlay-p t
            :overlay-options '(:non-capturing t)))
         (hidden
           (cadr-cli::make-extension-custom-ui-state
            :overlay-p t
            :overlay-options '(:visible nil)))
         (selector (cadr-cli::make-settings-selector-state))
         (lines (egg-test-logo-lines))
         (on-logo '(:type :click :x 1 :y 0))
         (off-logo '(:type :click :x 0 :y 0))
         (terminal (cadr-tui:make-process-terminal))
         (main (cadr-tui:make-terminal-renderer terminal :alt-p nil))
         (alt (cadr-tui:make-terminal-renderer terminal :alt-p t))
         (check (lambda () (cadr-cli::egg-visible-overlay-p visible))))
    (is-true (cadr-cli::egg-visible-overlay-p visible))
    (is-true (cadr-cli::egg-visible-overlay-p selector))
    (is (null (cadr-cli::egg-visible-overlay-p hidden)))
    (is (null (cadr-cli::egg-visible-overlay-p nil)))
    (multiple-value-bind (ok animation)
        (cadr-cli::play-pi-logo-3d
         terminal alt lines 1 0
         :overlay-check check)
      (is-true ok)
      (is (null animation)))
    (is (null cadr-cli::*easter-egg-playing*))
    (multiple-value-bind (ok animation)
        (cadr-cli::play-armin-3d
         terminal alt lines
         :overlay-check check)
      (is-true ok)
      (is (null animation)))
    (is (null cadr-cli::*easter-egg-playing*))
    (multiple-value-bind (ok animation)
        (cadr-cli::play-armin-3d
         terminal main lines
         :overlay-check check)
      (is (null ok))
      (is (null animation)))
    (multiple-value-bind (claim column row)
        (cadr-cli::egg-mouse-after-widget nil on-logo lines)
      (is (eq t claim))
      (is (= 1 column))
      (is (= 0 row)))
    (multiple-value-bind (claim column row)
        (cadr-cli::egg-mouse-after-widget t on-logo lines)
      (is-true claim)
      (is (null column))
      (is (null row)))
    (is (null (cadr-cli::egg-mouse-after-widget nil off-logo lines)))
    (is (null
         (cadr-cli::egg-logo-mouse-claim
          on-logo lines :logo-supported-p nil)))
    (let ((controller
            (uiop:read-file-string
             (merge-pathnames
              "src/cadr-cli/interactive/controller.lisp"
              (asdf:system-source-directory "cadr-cli")))))
      (is (search "(egg-visible-overlay-p overlay)" controller))
      (is (search "egg-mouse-after-widget" controller))
      (is (null
           (search ":overlay-check #'overlay-captures-input-p"
                   controller))))
    (setf cadr-cli::*easter-egg-playing* nil)))

(test egg-second-close-finishes-immediately
  (let* ((done 0)
         (animation
           (cadr-cli::make-easter-egg-3d-animation
            '("hi") (cadr-cli::pi-logo-model 0 0)
            '(212d0 212d0 212d0) '(0d0 0d0 0d0)
            (lambda () (incf done))
            :rows 4
            :forced-elapsed 2d0
            :start-p nil)))
    (cadr-cli::egg-anim-close animation)
    (is (not (null (cadr-cli::egg-anim-exit animation))))
    (cadr-cli::egg-anim-close animation)
    (is (= 1 done))
    (is-true (cadr-cli::egg-anim-finished-p animation))))
