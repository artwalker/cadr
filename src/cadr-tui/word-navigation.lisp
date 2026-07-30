(in-package #:cadr-tui)

(defparameter +word-punctuation+
  "(){}[]<>.,;:'\"!?+-=*/\\|&%^$#@~`")

(defun navigation-whitespace-p (character)
  (find character
        '(#\Space #\Tab #\Newline #\Return)
        :test #'char=))

(defun navigation-punctuation-p (character)
  (find character +word-punctuation+
        :test #'char=))

(defun navigation-cjk-p (character)
  (let ((value (codepoint character)))
    (or (between-p value #x2e80 #x9fff)
        (between-p value #x3040 #x30ff)
        (between-p value #xac00 #xd7af)
        (between-p value #x3100 #x312f))))

(defun atomic-segment-at (text cursor segments)
  (find-if
   (lambda (segment)
     (and (<= (+ cursor (length segment))
              (length text))
          (string= segment text
                   :start2 cursor
                   :end2 (+ cursor
                            (length segment)))))
   segments))

(defun atomic-segment-before (text cursor segments)
  (find-if
   (lambda (segment)
     (let ((start (- cursor (length segment))))
       (and (>= start 0)
            (string= segment text
                     :start2 start
                     :end2 cursor))))
   segments))

(defun find-word-backward
    (text cursor &key atomic-segments)
  (let ((position (max 0 (min cursor (length text)))))
    (when (zerop position)
      (return-from find-word-backward 0))
    (loop while (and (> position 0)
                     (navigation-whitespace-p
                      (char text (1- position))))
          do (decf position))
    (when (zerop position)
      (return-from find-word-backward 0))
    (let ((atomic
            (atomic-segment-before
             text position atomic-segments)))
      (when atomic
        (return-from find-word-backward
          (- position (length atomic)))))
    (let ((character (char text (1- position))))
      (cond
        ((navigation-punctuation-p character)
         (loop while
                 (and (> position 0)
                      (navigation-punctuation-p
                       (char text (1- position))))
               do (decf position)))
        ((navigation-cjk-p character)
         (loop repeat 2
               while (and (> position 0)
                          (navigation-cjk-p
                           (char text (1- position))))
               do (decf position)))
        (t
         (loop while
                 (and (> position 0)
                      (let ((candidate
                              (char text (1- position))))
                        (and
                         (not
                          (navigation-whitespace-p
                           candidate))
                         (not
                          (navigation-punctuation-p
                           candidate))
                         (not
                          (navigation-cjk-p
                           candidate)))))
               do (decf position)))))
    position))

(defun find-word-forward
    (text cursor &key atomic-segments)
  (let ((position (max 0 (min cursor (length text)))))
    (when (= position (length text))
      (return-from find-word-forward position))
    (loop while
            (and (< position (length text))
                 (navigation-whitespace-p
                  (char text position)))
          do (incf position))
    (when (= position (length text))
      (return-from find-word-forward position))
    (let ((atomic
            (atomic-segment-at
             text position atomic-segments)))
      (when atomic
        (return-from find-word-forward
          (+ position (length atomic)))))
    (let ((character (char text position)))
      (cond
        ((navigation-punctuation-p character)
         (loop while
                 (and (< position (length text))
                      (navigation-punctuation-p
                       (char text position)))
               do (incf position)))
        ((navigation-cjk-p character)
         (loop repeat 2
               while
                 (and (< position (length text))
                      (navigation-cjk-p
                       (char text position)))
               do (incf position)))
        (t
         (loop while
                 (and (< position (length text))
                      (let ((candidate
                              (char text position)))
                        (and
                         (not
                          (navigation-whitespace-p
                           candidate))
                         (not
                          (navigation-punctuation-p
                           candidate))
                         (not
                          (navigation-cjk-p
                           candidate)))))
               do (incf position)))))
    position))
