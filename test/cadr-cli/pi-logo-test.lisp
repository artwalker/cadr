(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(test pi-logo-follows-color-mode-and-apple-fallback
  ;; pi@71023aec1 pi-logo.ts. Capable terminals get the half-block mark.
  ;; Apple Terminal gets the colored wordmark instead.
  (let* ((theme (cadr-tui:current-theme))
         (mode (cadr-tui:terminal-theme-color-mode theme)))
    (unwind-protect
         (progn
           (setf (cadr-tui:terminal-theme-color-mode theme) :truecolor)
           (multiple-value-bind (top bottom)
               (cadr-cli::pi-logo-lines)
             (is (search (format nil "~C[38;2;228;138;122m" #\Escape) top))
             (is (search (format nil "~C[48;2;79;142;179m" #\Escape) top))
             (is (search (format nil "~C[38;2;234;182;93m" #\Escape) bottom))
             (is (string= "▀▀█ "
                          (cadr-tui:strip-terminal-sequences top)))
             (is (string= "█▀ █"
                          (cadr-tui:strip-terminal-sequences bottom))))
           (setf (cadr-tui:terminal-theme-color-mode theme) :256color)
           (let ((top (cadr-cli::pi-logo-lines)))
             (is (not (search "38;2;" top)))
             (is (search "38;5;" top))
             (is (string= "▀▀█ "
                          (cadr-tui:strip-terminal-sequences top))))
           (is (string= "cadr"
                        (cadr-tui:strip-terminal-sequences
                         (cadr-cli::cadr-startup-wordmark)))))
      (setf (cadr-tui:terminal-theme-color-mode theme) mode)))
  (let ((lines
          (cadr-cli::render-tui-startup-lines
           '("cadr v0.2.0" "escape to interrupt")
           40 :logo-p nil)))
    (is (uiop:string-prefix-p
         " cadr v0.2.0"
         (cadr-tui:strip-terminal-sequences (first lines))))
    (is (not (search "▀"
                     (cadr-tui:strip-terminal-sequences
                      (first lines)))))))
