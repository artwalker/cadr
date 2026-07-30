(in-package #:cadr-tui)

(defstruct (kill-ring
            (:constructor make-kill-ring ()))
  (entries nil :type list))

(defun kill-ring-push
    (ring text &key prepend-p accumulate-p)
  (when (plusp (length text))
    (if (and accumulate-p
             (kill-ring-entries ring))
        (setf
         (first (kill-ring-entries ring))
         (if prepend-p
             (concatenate
              'string text
              (first (kill-ring-entries ring)))
             (concatenate
              'string
              (first (kill-ring-entries ring))
              text)))
        (push text (kill-ring-entries ring))))
  ring)

(defun kill-ring-peek (ring)
  (first (kill-ring-entries ring)))

(defun kill-ring-rotate (ring)
  (when (> (length (kill-ring-entries ring)) 1)
    (setf
     (kill-ring-entries ring)
     (append
      (last (kill-ring-entries ring))
      (butlast (kill-ring-entries ring)))))
  ring)

(defun kill-ring-length (ring)
  (length (kill-ring-entries ring)))
