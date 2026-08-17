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

(defun scan-word-while
    (text position direction predicate &key (limit most-positive-fixnum))
  (let ((step (if (eq direction :backward) -1 1))
        (end (if (eq direction :backward) 0 (length text)))
        (seen 0))
    (loop while (and (/= position end) (< seen limit))
          for index = (if (eq direction :backward)
                          (1- position)
                          position)
          while (funcall predicate (char text index))
          do (incf position step)
             (incf seen))
    position))

(defun word-body-character-p (character)
  (and (not (navigation-whitespace-p character))
       (not (navigation-punctuation-p character))
       (not (navigation-cjk-p character))))

(defun find-word-backward
    (text cursor &key atomic-segments)
  (let ((position (max 0 (min cursor (length text)))))
    (when (zerop position)
      (return-from find-word-backward 0))
    (setf position
          (scan-word-while
           text position :backward #'navigation-whitespace-p))
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
         (scan-word-while
          text position :backward #'navigation-punctuation-p))
        ((navigation-cjk-p character)
         (scan-word-while
          text position :backward #'navigation-cjk-p
          :limit 2))
        (t
         (scan-word-while
          text position :backward #'word-body-character-p))))))

(defun find-word-forward
    (text cursor &key atomic-segments)
  (let ((position (max 0 (min cursor (length text)))))
    (when (= position (length text))
      (return-from find-word-forward position))
    (setf position
          (scan-word-while
           text position :forward #'navigation-whitespace-p))
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
         (scan-word-while
          text position :forward #'navigation-punctuation-p))
        ((navigation-cjk-p character)
         (scan-word-while
          text position :forward #'navigation-cjk-p
          :limit 2))
        (t
         (scan-word-while
          text position :forward #'word-body-character-p))))))
