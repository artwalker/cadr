(in-package #:cadr-tui)

;;; Mouse-wheel line acceleration (pi@71023aec wheel-scroll.ts, #9758).

(defconstant +wheel-scroll-burst-gap-ms+ 5d0)
(defconstant +wheel-scroll-gesture-gap-ms+ 200d0)
(defconstant +wheel-scroll-reference-gap-ms+ 100d0)
(defconstant +wheel-scroll-max-auto-lines+ 6)

(defun terminal-accelerates-wheel-p ()
  ;; Local macOS already accelerates; SSH hides the client platform.
  (and (uiop:os-macosx-p)
       (null (uiop:getenv "SSH_CONNECTION"))
       (null (uiop:getenv "SSH_CLIENT"))
       (null (uiop:getenv "SSH_TTY"))))

(defun wheel-scroll-lines-value (lines)
  (cond
    ((eq lines :auto) :auto)
    ((realp lines) (max 1 (floor lines)))
    (t 1)))
(defstruct (wheel-scroll-accelerator
            (:constructor %make-wheel-scroll-accelerator)
            (:copier nil))
  (lines :auto)
  (accelerate-p t :type boolean)
  (last-time most-negative-double-float
             :type double-float)
  (last-direction 0 :type integer)
  (average-gap nil :type (or null double-float))
  (carry 0d0 :type double-float))

(defun make-wheel-scroll-accelerator
    (&optional (lines :auto)
               (accelerate-p
                 (not (terminal-accelerates-wheel-p))))
  (%make-wheel-scroll-accelerator
   :lines (if (eq lines :auto)
              :auto
              (wheel-scroll-lines-value lines))
   :accelerate-p (not (null accelerate-p))))

(defun wheel-scroll-accelerator-reset (accelerator)
  (setf
   (wheel-scroll-accelerator-last-time accelerator)
   most-negative-double-float
   (wheel-scroll-accelerator-last-direction accelerator)
   0
   (wheel-scroll-accelerator-average-gap accelerator)
   nil
   (wheel-scroll-accelerator-carry accelerator)
   0d0)
  accelerator)

(defun wheel-scroll-accelerator-set-lines
    (accelerator lines)
  (setf
   (wheel-scroll-accelerator-lines accelerator)
   (if (eq lines :auto)
       :auto
       (wheel-scroll-lines-value lines)))
  (wheel-scroll-accelerator-reset accelerator)
  accelerator)

(defun wheel-scroll-accelerator-next
    (accelerator direction now-ms)
  (let ((lines
          (wheel-scroll-accelerator-lines accelerator))
        (now (coerce now-ms 'double-float))
        (direction (if (minusp direction) -1 1)))
    (unless (eq lines :auto)
      (return-from wheel-scroll-accelerator-next
        (wheel-scroll-lines-value lines)))
    (unless (wheel-scroll-accelerator-accelerate-p
             accelerator)
      (return-from wheel-scroll-accelerator-next 1))
    (let* ((gap
             (- now
                (wheel-scroll-accelerator-last-time
                 accelerator)))
           (same-gesture-p
             (and
              (= direction
                 (wheel-scroll-accelerator-last-direction
                  accelerator))
              (<= gap +wheel-scroll-gesture-gap-ms+))))
      (setf
       (wheel-scroll-accelerator-last-time accelerator)
       now
       (wheel-scroll-accelerator-last-direction
        accelerator)
       direction)
      (unless same-gesture-p
        (setf
         (wheel-scroll-accelerator-average-gap
          accelerator)
         nil
         (wheel-scroll-accelerator-carry accelerator)
         0d0)
        (return-from wheel-scroll-accelerator-next 1))
      (when (< gap +wheel-scroll-burst-gap-ms+)
        (return-from wheel-scroll-accelerator-next 1))
      (setf
       (wheel-scroll-accelerator-average-gap accelerator)
       (let ((previous
               (wheel-scroll-accelerator-average-gap
                accelerator)))
         (if previous
             (/ (+ previous gap) 2d0)
             gap)))
      (let* ((scaled
               (+
                (min
                 (coerce +wheel-scroll-max-auto-lines+
                         'double-float)
                 (max
                  1d0
                  (/ +wheel-scroll-reference-gap-ms+
                     (wheel-scroll-accelerator-average-gap
                      accelerator))))
                (wheel-scroll-accelerator-carry
                 accelerator)))
             (whole (floor scaled)))
        (setf
         (wheel-scroll-accelerator-carry accelerator)
         (- scaled whole))
        whole))))
