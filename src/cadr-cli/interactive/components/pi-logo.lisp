;;; pi@4a080252f components/pi-logo.ts. The half-block mark keeps the pin's
;;; coral, blue, and yellow. The text fallback spells cadr, in the same
;;; coral-then-yellow split the pin uses for "Pi".
(in-package #:cadr-cli)

(defun logo-color-ansi
    (red green blue &key background-p
         (mode (cadr-tui:terminal-theme-color-mode
                (cadr-tui:current-theme))))
  (let ((base (if background-p 48 38)))
    (if (eq mode :truecolor)
        (format nil "~C[~D;2;~D;~D;~Dm"
                #\Escape base red green blue)
        (format nil "~C[~D;5;~Dm"
                #\Escape base
                (cadr-tui:rgb-to-ansi-256 red green blue)))))

(defun logo-reset ()
  (format nil "~C[0m" #\Escape))

(defun pi-logo-lines
    (&key (mode (cadr-tui:terminal-theme-color-mode
                 (cadr-tui:current-theme))))
  (let ((coral (logo-color-ansi 228 138 122 :mode mode))
        (blue (logo-color-ansi 79 142 179 :mode mode))
        (blue-bg (logo-color-ansi 79 142 179 :background-p t :mode mode))
        (yellow (logo-color-ansi 234 182 93 :mode mode))
        (reset (logo-reset)))
    (values
     (concatenate 'string coral blue-bg "▀" reset coral "▀█" reset " ")
     (concatenate 'string blue "█▀" reset " " yellow "█" reset))))

(defun cadr-startup-wordmark
    (&key (mode (cadr-tui:terminal-theme-color-mode
                 (cadr-tui:current-theme))))
  (concatenate 'string
               (logo-color-ansi 228 138 122 :mode mode)
               "c"
               (logo-reset)
               (logo-color-ansi 234 182 93 :mode mode)
               "adr"
               (logo-reset)))

(defun startup-logo-supported-p ()
  ;; Apple Terminal draws gaps between the half blocks.
  (not (cadr-tui:apple-terminal-session-p)))
