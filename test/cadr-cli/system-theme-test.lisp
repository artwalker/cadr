(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defun system-rgb (hex)
  (let ((color (cadr-tui:parse-theme-hex-color hex)))
    (list (cadr-tui:rgb-color-red color)
          (cadr-tui:rgb-color-green color)
          (cadr-tui:rgb-color-blue color))))

(defparameter +system-test-panels+
  '("userMessageBg" "toolPendingBg" "toolSuccessBg" "toolErrorBg"
    "selectedBg"))

(defparameter +dracula-palette+
  (mapcar #'system-rgb
          '("#21222c" "#ff5555" "#50fa7b" "#f1fa8c"
            "#bd93f9" "#ff79c6" "#8be9fd" "#f8f8f2"
            "#6272a4" "#ff6e6e" "#69ff94" "#ffffa5"
            "#d6acff" "#ff92df" "#a4ffff" "#ffffff")))

(defun system-resolved (colors background foreground token)
  (let ((value (gethash token colors)))
    (if (and (stringp value) (string= value ""))
        (if (member token +system-test-panels+ :test #'string=)
            background
            foreground)
        (system-rgb value))))

(defun system-oklch (rgb)
  (cadr-tui:rgb-oklch-channels
   (first rgb) (second rgb) (third rgb)))

(test system-theme-follows-the-terminal
  ;; pi@4a080252f system-theme.test.ts.
  (let* ((dracula-bg (system-rgb "#282a36"))
         (dracula-fg (system-rgb "#f8f8f2"))
         (solarized-bg (system-rgb "#fdf6e3"))
         (solarized-fg (system-rgb "#657b83"))
         (plain-bg (system-rgb "#1e1e1e"))
         (gray-bg (system-rgb "#808080"))
         (gray-fg (system-rgb "#ffffff"))
         (frappe-bg (system-rgb "#303446"))
         (frappe-fg (system-rgb "#c6d0f5"))
         (frappe-palette
           (mapcar #'system-rgb
                   '("#51576d" "#e78284" "#a6d189" "#e5c890"
                     "#8caaee" "#f4b8e4" "#81c8be" "#b5bfe2"
                     "#626880" "#e67172" "#8ec772" "#d9ba73"
                     "#7b9ef0" "#f2a4db" "#5abfb5" "#a5adce")))
         (cases
           (list (list "dracula" dracula-bg dracula-fg +dracula-palette+)
                 (list "solarizedLight" solarized-bg solarized-fg nil)
                 (list "backgroundOnly" plain-bg nil nil)
                 (list "midGray" gray-bg gray-fg nil))))
    (dolist (case cases)
      (destructuring-bind (name background foreground palette) case
        (multiple-value-bind (colors dim appearance)
            (cadr-cli::generate-system-theme-colors
             :background background
             :foreground foreground
             :palette palette)
          (declare (ignore dim))
          (flet ((resolved (token)
                   (system-resolved colors background foreground token)))
            (dolist (surface
                     (list background (resolved "selectedBg")))
              (is (>= (cadr-tui:wcag-contrast
                       (first (resolved "text"))
                       (second (resolved "text"))
                       (third (resolved "text"))
                       (first surface) (second surface) (third surface))
                      4.5d0)))
            (is (>= (cadr-tui:wcag-contrast
                     (first (resolved "toolTitle"))
                     (second (resolved "toolTitle"))
                     (third (resolved "toolTitle"))
                     (first (resolved "toolErrorBg"))
                     (second (resolved "toolErrorBg"))
                     (third (resolved "toolErrorBg")))
                    4.5d0))
            (let ((background-l (system-oklch background)))
              (flet ((offset (token)
                       (- (system-oklch (resolved token)) background-l)))
                (unless (string= name "midGray")
                  (is (> (abs (offset "text")) (abs (offset "muted"))))
                  (is (> (abs (offset "muted")) (abs (offset "dim")))))
                (let ((lighter (eq appearance :dark)))
                  (dolist (panel +system-test-panels+)
                    (is (< (cadr-tui:wcag-contrast
                            (first (resolved panel))
                            (second (resolved panel))
                            (third (resolved panel))
                            (first background)
                            (second background)
                            (third background))
                           2d0))
                    (is (eq (> (offset panel) 0d0) lighter)))))))))
    (multiple-value-bind (colors dim appearance)
        (cadr-cli::generate-system-theme-colors
         :background dracula-bg :foreground dracula-fg
         :palette +dracula-palette+)
      (declare (ignore dim appearance))
      (is (string= "" (gethash "text" colors)))
      (multiple-value-bind (l c h)
          (system-oklch (system-resolved colors dracula-bg dracula-fg "error"))
        (declare (ignore l c))
        (multiple-value-bind (pl pc ph)
            (system-oklch (nth 1 +dracula-palette+))
          (declare (ignore pl pc))
          (is (< (abs (- h ph)) 8d0)))))
    (multiple-value-bind (colors dim appearance)
        (cadr-cli::generate-system-theme-colors
         :background solarized-bg :foreground solarized-fg)
      (declare (ignore dim appearance))
      (is (not (string= "" (gethash "text" colors)))))
    (multiple-value-bind (colors dim appearance)
        (cadr-cli::generate-system-theme-colors
         :background frappe-bg :foreground frappe-fg
         :palette frappe-palette)
      (declare (ignore dim appearance))
      (let ((pink (nth 5 frappe-palette))
            (accent
              (system-resolved colors frappe-bg frappe-fg "accent")))
        (is (< (system-oklch accent) (- (system-oklch pink) 0.05d0)))
        (is (<= (nth-value 1 (system-oklch accent))
                (* (nth-value 1 (system-oklch pink)) 1.03d0))))
      (dolist (panel '("userMessageBg" "customMessageBg"))
        (is (<= (nth-value 1
                          (system-oklch
                           (system-resolved
                            colors frappe-bg frappe-fg panel)))
                0.1d0))))
    (multiple-value-bind (colors dim appearance)
        (cadr-cli::generate-system-theme-colors
         :background dracula-bg :foreground dracula-fg
         :palette +dracula-palette+ :saturation 0d0)
      (declare (ignore dim appearance))
      (is (< (nth-value 1 (system-oklch (system-rgb (gethash "error" colors))))
             0.005d0)))
    (multiple-value-bind (colors dim appearance)
        (cadr-cli::generate-system-theme-colors :appearance-hint :light)
      (is (eq :light appearance))
      (is (equal '(1 "" "")
                 (list (gethash "error" colors)
                       (gethash "text" colors)
                       (gethash "userMessageBg" colors))))
      (is (member "muted" dim :test #'string=)))
    (multiple-value-bind (colors dim appearance)
        (cadr-cli::generate-system-theme-colors :saturation 0d0)
      (declare (ignore dim appearance))
      (is (string= "" (gethash "error" colors))))
    (let ((previous (cadr-tui:current-theme))
          (cadr-cli::*system-terminal-colors*
            (list :background dracula-bg
                  :foreground dracula-fg
                  :palette +dracula-palette+)))
      (unwind-protect
           (progn
             (cadr-cli::apply-tui-theme-summary
              "system"
              :capabilities
              (cadr-tui:make-terminal-capabilities :true-color-p t))
             (is (eq :dark
                     (cadr-tui:terminal-theme-name
                      (cadr-tui:current-theme))))
             (is (search (format nil "~C[39m" #\Escape)
                         (cadr-tui:theme-foreground-ansi :text)))
             (is (search (format nil "~C[38;" #\Escape)
                         (cadr-tui:theme-foreground-ansi :error)))
             (setf cadr-cli::*system-terminal-colors* nil)
             (cadr-cli::apply-tui-theme-summary "system")
             (is (search (format nil "~C[2m" #\Escape)
                         (cadr-tui:theme-foreground :muted "x")))
             (is (search (format nil "~C[22;39m" #\Escape)
                         (cadr-tui:theme-foreground :muted "x"))))
        (setf cadr-cli::*system-terminal-colors* nil)
        (cadr-tui:set-current-theme previous))))))

(test terminal-color-report-keeps-a-palette-already-seen
  (let ((previous (cadr-tui:current-theme))
        (palette +dracula-palette+))
    (unwind-protect
         (let ((cadr-cli::*system-terminal-colors*
                 (list :foreground '(248 248 242)
                       :background '(40 42 54)
                       :palette palette)))
           (cadr-cli::merge-reported-terminal-colors
            (list :background '(1 2 3)))
           (is (equal '(248 248 242)
                      (getf cadr-cli::*system-terminal-colors*
                            :foreground)))
           (is (equal '(1 2 3)
                      (getf cadr-cli::*system-terminal-colors*
                            :background)))
           (is (equal palette
                      (getf cadr-cli::*system-terminal-colors*
                            :palette)))
           (cadr-cli::apply-tui-theme-summary
            "system"
            :capabilities
            (cadr-tui:make-terminal-capabilities :true-color-p t))
           (is (search (format nil "~C[38;2;" #\Escape)
                       (cadr-tui:theme-foreground-ansi :error))))
      (setf cadr-cli::*system-terminal-colors* nil)
      (cadr-tui:set-terminal-default-colors)
      (cadr-tui:set-current-theme previous))))
