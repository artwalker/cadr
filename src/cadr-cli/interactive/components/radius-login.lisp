;;; pi@71023aec1 radius-login-selector.ts. The selected "Sign in with
;;; Radius" label cycles the four logo colors. Mixing is sRGB, then
;;; smoothstep between adjacent bands.
(in-package #:cadr-cli)

(defparameter +radius-shimmer-colors+
  '((77 154 191)
    (131 204 210)
    (241 190 87)
    (240 144 130)))

(defconstant +radius-chars-per-color+ 4)
(defconstant +radius-chars-per-second+ 10)

(defun radius-js-round (value)
  ;; JavaScript Math.round for a non-negative channel.
  (floor (+ value 0.5d0)))

(defun radius-mix-srgb (from to amount)
  (values
   (radius-js-round
    (+ (first from) (* (- (first to) (first from)) amount)))
   (radius-js-round
    (+ (second from) (* (- (second to) (second from)) amount)))
   (radius-js-round
    (+ (third from) (* (- (third to) (third from)) amount)))))

(defun radius-shimmer (text elapsed-ms &key (mode (cadr-tui:terminal-theme-color-mode
                                                    (cadr-tui:current-theme))))
  (let* ((cycle (* (length +radius-shimmer-colors+)
                   +radius-chars-per-color+))
         (offset (* (/ elapsed-ms 1000d0) +radius-chars-per-second+))
         (out (make-string-output-stream)))
    (loop for char across text
          for index from 0
          for position = (mod (- index offset) cycle)
          for band = (floor position +radius-chars-per-color+)
          for blend = (- (/ position +radius-chars-per-color+) band)
          for amount = (* blend blend (- 3 (* 2 blend)))
          do (multiple-value-bind (red green blue)
                 (radius-mix-srgb
                  (nth band +radius-shimmer-colors+)
                  (nth (mod (1+ band) (length +radius-shimmer-colors+))
                       +radius-shimmer-colors+)
                  amount)
               (write-string
                (logo-color-ansi red green blue :mode mode)
                out)
               (write-char char out)))
    (write-string (format nil "~C[39m" #\Escape) out)
    (get-output-stream-string out)))
