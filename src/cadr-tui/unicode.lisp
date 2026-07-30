(in-package #:cadr-tui)

(defun codepoint (character)
  (char-code character))

(defun between-p (value lower upper)
  (<= lower value upper))

(defun control-character-p (character)
  (let ((value (codepoint character)))
    (or (< value #x20)
        (between-p value #x7f #x9f))))

(defun combining-character-p (character)
  (let ((value (codepoint character)))
    (or
     (between-p value #x0300 #x036f)
     (between-p value #x0483 #x0489)
     (between-p value #x0591 #x05bd)
     (= value #x05bf)
     (between-p value #x05c1 #x05c2)
     (between-p value #x05c4 #x05c5)
     (= value #x05c7)
     (between-p value #x0610 #x061a)
     (between-p value #x064b #x065f)
     (= value #x0670)
     (between-p value #x06d6 #x06ed)
     (between-p value #x0711 #x0711)
     (between-p value #x0730 #x074a)
     (between-p value #x07a6 #x07b0)
     (between-p value #x07eb #x07f3)
     (between-p value #x0816 #x082d)
     (between-p value #x0859 #x085b)
     (between-p value #x08d3 #x0902)
     (between-p value #x093a #x093c)
     (between-p value #x0941 #x0948)
     (= value #x094d)
     (between-p value #x0951 #x0957)
     (between-p value #x0962 #x0963)
     (between-p value #x0e31 #x0e31)
     (between-p value #x0e34 #x0e3a)
     (between-p value #x0e47 #x0e4e)
     (between-p value #x0eb1 #x0eb1)
     (between-p value #x0eb4 #x0ebc)
     (between-p value #x0ec8 #x0ecd)
     (between-p value #x1ab0 #x1aff)
     (between-p value #x1dc0 #x1dff)
     (between-p value #x20d0 #x20ff)
     (between-p value #xfe00 #xfe0f)
     (between-p value #xfe20 #xfe2f)
     (between-p value #xe0100 #xe01ef)
     (between-p value #x1f3fb #x1f3ff)
     (between-p value #xe0020 #xe007f))))

(defun regional-indicator-p (character)
  (between-p (codepoint character) #x1f1e6 #x1f1ff))

(defun emoji-codepoint-p (character)
  (let ((value (codepoint character)))
    (or
     (between-p value #x1f000 #x1fbff)
     (between-p value #x2600 #x27bf)
     (between-p value #x2300 #x23ff)
     (between-p value #x2b50 #x2b55))))

(defun wide-codepoint-p (character)
  (let ((value (codepoint character)))
    (or
     (between-p value #x1100 #x115f)
     (= value #x2329)
     (= value #x232a)
     (between-p value #x2e80 #xa4cf)
     (between-p value #xac00 #xd7a3)
     (between-p value #xf900 #xfaff)
     (between-p value #xfe10 #xfe19)
     (between-p value #xfe30 #xfe6f)
     (between-p value #xff00 #xff60)
     (between-p value #xffe0 #xffe6)
     (between-p value #x20000 #x3fffd))))

(defun ansi-sequence-end (text start)
  (when (and (< (1+ start) (length text))
             (char= (char text start) #\Escape))
    (case (char text (1+ start))
      (#\[
       (loop for index from (+ start 2) below (length text)
             for code = (codepoint (char text index))
             when (between-p code #x40 #x7e)
               do (return (1+ index))))
      ((#\] #\_)
       (loop for index from (+ start 2) below (length text)
             when (char= (char text index) #\Bell)
               do (return (1+ index))
             when (and (char= (char text index) #\Escape)
                       (< (1+ index) (length text))
                       (char= (char text (1+ index)) #\\))
               do (return (+ index 2)))))))

(defun strip-ansi (text)
  (with-output-to-string (output)
    (loop with index = 0
          while (< index (length text))
          for end = (ansi-sequence-end text index)
          do
          (if end
              (setf index end)
              (progn
                (write-char (char text index) output)
                (incf index))))))

(defun grapheme-clusters (text)
  (let ((clusters nil)
        (start 0)
        (index 0)
        (regional-count 0)
        (join-next-p nil))
    (labels ((emit (end)
               (when (< start end)
                 (push (subseq text start end) clusters))
               (setf start end
                     regional-count 0)))
      (loop while (< index (length text))
            for character = (char text index)
            do
            (cond
              ((= index start)
               (setf regional-count
                     (if (regional-indicator-p character) 1 0)))
              ((or join-next-p
                   (combining-character-p character)
                   (= (codepoint character) #x200d))
               (when (regional-indicator-p character)
                 (incf regional-count)))
              ((and (regional-indicator-p character)
                    (= regional-count 1))
               (incf regional-count))
              (t
               (emit index)
               (setf regional-count
                     (if (regional-indicator-p character) 1 0))))
            (setf join-next-p
                  (= (codepoint character) #x200d))
            (incf index))
      (emit (length text)))
    (nreverse clusters)))

(defun grapheme-width (cluster)
  (cond
    ((string= cluster (string #\Tab)) 3)
    ((or (find #\Newline cluster)
         (find #\Return cluster))
     0)
    ((some (lambda (character)
             (or (regional-indicator-p character)
                 (emoji-codepoint-p character)
                 (= (codepoint character) #x200d)
                 (= (codepoint character) #xfe0f)))
           cluster)
     2)
    (t
     (loop for character across cluster
           unless (or (combining-character-p character)
                      (control-character-p character))
             maximize (if (wide-codepoint-p character) 2 1)
               into width
           finally (return (or width 0))))))

(defun visible-width (text)
  (loop for cluster in (grapheme-clusters (strip-ansi text))
        sum (grapheme-width cluster)))

(defun slice-to-width (text maximum-width)
  (let ((width 0)
        (index 0)
        (done-p nil))
    (values
     (with-output-to-string (output)
       (loop while (and
                    (< index (length text))
                    (not done-p))
             for ansi-end =
             (ansi-sequence-end text index)
             do
             (if ansi-end
                 (progn
                   (write-string
                    text output
                    :start index
                    :end ansi-end)
                   (setf index ansi-end))
                 (let* ((next-ansi
                          (or
                           (position
                            #\Escape text
                            :start index)
                           (length text)))
                        (fragment
                          (subseq text index
                                  next-ansi)))
                   (dolist
                       (cluster
                        (grapheme-clusters
                         fragment))
                     (let ((cluster-width
                             (grapheme-width
                              cluster)))
                       (if
                           (> (+ width
                                 cluster-width)
                              maximum-width)
                           (progn
                             (setf done-p t)
                             (return))
                           (progn
                             (write-string
                              cluster output)
                             (incf
                              width
                              cluster-width)))))
                   (setf index next-ansi)))))
     width)))

(defun split-lines-preserving-empty (text)
  (loop with start = 0
        for end = (position #\Newline text :start start)
        collect (string-right-trim
                 '(#\Return)
                 (subseq text start (or end (length text))))
        while end
        do (setf start (1+ end))))

(defun wrap-logical-line (line width)
  (when (< width 1)
    (error "Terminal width must be positive"))
  (if (zerop (length line))
      (list "")
      (let ((lines nil)
            (output (make-string-output-stream))
            (used 0))
        (dolist (cluster (grapheme-clusters line))
          (let ((cluster-width (grapheme-width cluster)))
            (when (and (> used 0)
                       (> (+ used cluster-width) width))
              (push (get-output-stream-string output) lines)
              (setf output (make-string-output-stream)
                    used 0))
            (when (> cluster-width width)
              (return))
            (write-string
             (if (string= cluster (string #\Tab))
                 "   "
                 cluster)
             output)
            (incf used cluster-width)))
        (push (get-output-stream-string output) lines)
        (nreverse lines))))

(defun wrap-text (text width)
  (loop for line in (split-lines-preserving-empty text)
        append (wrap-logical-line line width)))
