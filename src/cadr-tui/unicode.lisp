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
             when (char= (char text index) (code-char 7))
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

(defun normalize-terminal-output (text)
  (with-output-to-string (output)
    (loop with index = 0
          while (< index (length text))
          for ansi-end = (ansi-sequence-end text index)
          do
          (cond
            (ansi-end
             (write-string text output :start index :end ansi-end)
             (setf index ansi-end))
            ((char= (char text index) #\Tab)
             (write-string "   " output)
             (incf index))
            ((= (codepoint (char text index)) #x0e33)
             (write-char (code-char #x0e4d) output)
             (write-char (code-char #x0e32) output)
             (incf index))
            ((= (codepoint (char text index)) #x0eb3)
             (write-char (code-char #x0ecd) output)
             (write-char (code-char #x0eb2) output)
             (incf index))
            (t
             (write-char (char text index) output)
             (incf index))))))

(defun slice-with-width
    (text start-column length &optional strict-p)
  (when (<= length 0)
    (return-from slice-with-width (values "" 0)))
  (let ((end-column (+ start-column length))
        (column 0)
        (width 0)
        (index 0)
        (pending-ansi "")
        (done-p nil))
    (values
     (with-output-to-string (output)
       (loop while (and (< index (length text))
                        (not done-p))
             for ansi-end = (ansi-sequence-end text index)
             do
             (if ansi-end
                 (let ((code (subseq text index ansi-end)))
                   (cond
                     ((and (>= column start-column)
                           (< column end-column))
                      (write-string code output))
                     ((< column start-column)
                      (setf pending-ansi
                            (concatenate
                             'string pending-ansi code))))
                   (setf index ansi-end))
                 (let* ((next-ansi
                          (or (position #\Escape text
                                        :start index)
                              (length text)))
                        (fragment
                          (subseq text index next-ansi)))
                   (dolist (cluster (grapheme-clusters fragment))
                     (let* ((cluster-width
                              (grapheme-width cluster))
                            (in-range-p
                              (and (>= column start-column)
                                   (< column end-column)))
                            (fits-p
                              (or (not strict-p)
                                  (<= (+ column cluster-width)
                                      end-column))))
                       (when (and in-range-p fits-p)
                         (when (plusp (length pending-ansi))
                           (write-string pending-ansi output)
                           (setf pending-ansi ""))
                         (write-string cluster output)
                         (incf width cluster-width))
                       (incf column cluster-width)
                       (when (>= column end-column)
                         (setf done-p t)
                         (return))))
                   (setf index next-ansi)))))
     width)))

(defun slice-by-column
    (text start-column length &optional strict-p)
  (nth-value
   0
   (slice-with-width
    text start-column length strict-p)))

(defun slice-to-width (text maximum-width)
  (slice-with-width text 0 maximum-width t))

(defstruct ansi-state
  bold-p
  dim-p
  italic-p
  underline-p
  blink-p
  inverse-p
  hidden-p
  strikethrough-p
  foreground
  background
  hyperlink-open
  hyperlink-close)

(defun reset-ansi-state (state)
  (setf
   (ansi-state-bold-p state) nil
   (ansi-state-dim-p state) nil
   (ansi-state-italic-p state) nil
   (ansi-state-underline-p state) nil
   (ansi-state-blink-p state) nil
   (ansi-state-inverse-p state) nil
   (ansi-state-hidden-p state) nil
   (ansi-state-strikethrough-p state) nil
   (ansi-state-foreground state) nil
   (ansi-state-background state) nil)
  state)

(defun parse-sgr-integer (text)
  (or (parse-integer text :junk-allowed t) 0))

(defun process-sgr-code (state code)
  (let* ((body (subseq code 2 (1- (length code))))
         (parts
           (if (zerop (length body))
               '("0")
               (uiop:split-string body
                                  :separator '(#\;)))))
    (loop while parts
          for part = (pop parts)
          for value = (parse-sgr-integer part)
          do
          (cond
            ((and (member value '(38 48))
                  parts
                  (member (first parts) '("2" "5")
                          :test #'string=))
             (let* ((mode (pop parts))
                    (count
                      (if (string= mode "2") 3 1))
                    (arguments
                      (loop repeat count
                            while parts
                            collect (pop parts)))
                    (color
                      (format nil "~D;~A~{;~A~}"
                              value mode arguments)))
               (if (= value 38)
                   (setf
                    (ansi-state-foreground state)
                    color)
                   (setf
                    (ansi-state-background state)
                    color))))
            (t
             (case value
               (0 (reset-ansi-state state))
               (1 (setf (ansi-state-bold-p state) t))
               (2 (setf (ansi-state-dim-p state) t))
               (3 (setf (ansi-state-italic-p state) t))
               (4 (setf (ansi-state-underline-p state) t))
               (5 (setf (ansi-state-blink-p state) t))
               (7 (setf (ansi-state-inverse-p state) t))
               (8 (setf (ansi-state-hidden-p state) t))
               (9 (setf
                   (ansi-state-strikethrough-p state) t))
               (21 (setf (ansi-state-bold-p state) nil))
               (22 (setf
                    (ansi-state-bold-p state) nil
                    (ansi-state-dim-p state) nil))
               (23 (setf (ansi-state-italic-p state) nil))
               (24 (setf
                    (ansi-state-underline-p state) nil))
               (25 (setf (ansi-state-blink-p state) nil))
               (27 (setf (ansi-state-inverse-p state) nil))
               (28 (setf (ansi-state-hidden-p state) nil))
               (29 (setf
                    (ansi-state-strikethrough-p state) nil))
               (39 (setf
                    (ansi-state-foreground state) nil))
               (49 (setf
                    (ansi-state-background state) nil))
               (otherwise
                (cond
                  ((or (between-p value 30 37)
                       (between-p value 90 97))
                   (setf
                    (ansi-state-foreground state)
                    (write-to-string value)))
                  ((or (between-p value 40 47)
                       (between-p value 100 107))
                   (setf
                    (ansi-state-background state)
                    (write-to-string value))))))))))
  state)

(defun osc-eight-code-p (code)
  (and (>= (length code) 4)
       (char= (char code 0) #\Escape)
       (char= (char code 1) #\])
       (char= (char code 2) #\8)
       (char= (char code 3) #\;)))

(defun process-osc-eight-code (state code)
  (let* ((bell-p
           (char= (char code (1- (length code))) (code-char 7)))
         (terminator-length (if bell-p 1 2))
         (terminator
           (if bell-p
               (string (code-char 7))
               (format nil "~C\\" #\Escape)))
         (body
           (subseq code 4
                   (- (length code)
                      terminator-length)))
         (separator (position #\; body))
         (url
           (and separator
                (subseq body (1+ separator)))))
    (when separator
      (if (or (null url) (zerop (length url)))
          (setf
           (ansi-state-hyperlink-open state) nil
           (ansi-state-hyperlink-close state) nil)
          (setf
           (ansi-state-hyperlink-open state) code
           (ansi-state-hyperlink-close state)
           (format nil "~C]8;;~A"
                   #\Escape terminator)))))
  state)

(defun process-ansi-code (state code)
  (cond
    ((osc-eight-code-p code)
     (process-osc-eight-code state code))
    ((and (> (length code) 2)
          (char= (char code 1) #\[)
          (char= (char code (1- (length code))) #\m))
     (process-sgr-code state code)))
  state)

(defun ansi-state-active-codes (state)
  (let ((codes nil))
    (when (ansi-state-bold-p state) (push "1" codes))
    (when (ansi-state-dim-p state) (push "2" codes))
    (when (ansi-state-italic-p state) (push "3" codes))
    (when (ansi-state-underline-p state) (push "4" codes))
    (when (ansi-state-blink-p state) (push "5" codes))
    (when (ansi-state-inverse-p state) (push "7" codes))
    (when (ansi-state-hidden-p state) (push "8" codes))
    (when (ansi-state-strikethrough-p state)
      (push "9" codes))
    (when (ansi-state-foreground state)
      (push (ansi-state-foreground state) codes))
    (when (ansi-state-background state)
      (push (ansi-state-background state) codes))
    (concatenate
     'string
     (if codes
         (format nil "~C[~{~A~^;~}m"
                 #\Escape (nreverse codes))
         "")
     (or (ansi-state-hyperlink-open state) ""))))

(defun ansi-state-line-end-reset (state)
  (concatenate
   'string
   (if (ansi-state-underline-p state)
       (format nil "~C[24m" #\Escape)
       "")
   (or (ansi-state-hyperlink-close state) "")))

(defun update-ansi-state (state text)
  (loop with index = 0
        while (< index (length text))
        for ansi-end = (ansi-sequence-end text index)
        do
        (if ansi-end
            (progn
              (process-ansi-code
               state (subseq text index ansi-end))
              (setf index ansi-end))
            (incf index)))
  state)

(defun extract-segments
    (text before-end after-start total-width
     &optional strict-after-p)
  (let ((before "")
        (after "")
        (before-width 0)
        (after-width 0)
        (column 0)
        (index 0)
        (pending-before "")
        (after-started-p nil)
        (state (make-ansi-state)))
    (loop while (< index (length text))
          for ansi-end = (ansi-sequence-end text index)
          do
          (if ansi-end
              (let ((code (subseq text index ansi-end)))
                (process-ansi-code state code)
                (cond
                  ((< column before-end)
                   (setf pending-before
                         (concatenate
                          'string pending-before code)))
                  ((and after-started-p
                        (>= column after-start)
                        (< column total-width))
                   (setf after
                         (concatenate 'string after code))))
                (setf index ansi-end))
              (let* ((next-ansi
                       (or (position #\Escape text
                                     :start index)
                           (length text)))
                     (fragment
                       (subseq text index next-ansi)))
                (dolist (cluster (grapheme-clusters fragment))
                  (let ((cluster-width
                          (grapheme-width cluster)))
                    (cond
                      ((and (< column before-end)
                            (<= (+ column cluster-width)
                                before-end))
                       (setf before
                             (concatenate
                              'string before
                              pending-before cluster)
                             pending-before "")
                       (incf before-width cluster-width))
                      ((and (>= column after-start)
                            (< column total-width)
                            (or (not strict-after-p)
                                (<= (+ column cluster-width)
                                    total-width)))
                       (unless after-started-p
                         (setf after
                               (concatenate
                                'string after
                                (ansi-state-active-codes
                                 state))
                               after-started-p t))
                       (setf after
                             (concatenate
                              'string after cluster))
                       (incf after-width cluster-width)))
                    (incf column cluster-width)))
                (setf index next-ansi))))
    (values before before-width after after-width)))

(defun truncate-fragment-to-width (text maximum-width)
  (slice-with-width text 0 maximum-width t))

(defun finalize-truncated-result
    (prefix prefix-width ellipsis ellipsis-width
     maximum-width pad-p)
  (let* ((reset (format nil "~C[0m" #\Escape))
         (visible (+ prefix-width ellipsis-width))
         (result
           (if (plusp (length ellipsis))
               (format nil "~A~A~A~A"
                       prefix reset ellipsis reset)
               (format nil "~A~A" prefix reset))))
    (if pad-p
        (concatenate
         'string result
         (make-string
          (max 0 (- maximum-width visible))
          :initial-element #\Space))
        result)))

(defun truncate-to-width
    (text maximum-width
     &optional (ellipsis "...") pad-p)
  (when (<= maximum-width 0)
    (return-from truncate-to-width ""))
  (when (zerop (length text))
    (return-from truncate-to-width
      (if pad-p
          (make-string maximum-width
                       :initial-element #\Space)
          "")))
  (let* ((text-width (visible-width text))
         (ellipsis-width (visible-width ellipsis)))
    (when (<= text-width maximum-width)
      (return-from truncate-to-width
        (if pad-p
            (concatenate
             'string text
             (make-string
              (- maximum-width text-width)
              :initial-element #\Space))
            text)))
    (when (>= ellipsis-width maximum-width)
      (multiple-value-bind (clipped clipped-width)
          (truncate-fragment-to-width
           ellipsis maximum-width)
        (return-from truncate-to-width
          (if (zerop clipped-width)
              (if pad-p
                  (make-string maximum-width
                               :initial-element #\Space)
                  "")
              (finalize-truncated-result
               "" 0 clipped clipped-width
               maximum-width pad-p)))))
    (let ((target-width
            (- maximum-width ellipsis-width)))
      (multiple-value-bind (prefix prefix-width)
          (truncate-fragment-to-width text target-width)
        (finalize-truncated-result
         prefix prefix-width ellipsis ellipsis-width
         maximum-width pad-p)))))

(defun split-lines-preserving-empty (text)
  (let ((lines nil)
        (start 0)
        (index 0))
    (loop while (< index (length text))
          for character = (char text index)
          when (or (char= character #\Newline)
                   (char= character #\Return))
            do
            (push (subseq text start index) lines)
            (when (and (char= character #\Return)
                       (< (1+ index) (length text))
                       (char= (char text (1+ index))
                              #\Newline))
              (incf index))
            (setf start (1+ index))
          do (incf index))
    (push (subseq text start) lines)
    (nreverse lines)))

(defun cjk-cluster-p (cluster)
  (and (plusp (length cluster))
       (let ((value (codepoint (char cluster 0))))
         (or
          (between-p value #x2e80 #x9fff)
          (between-p value #x3040 #x30ff)
          (between-p value #xac00 #xd7af)
          (between-p value #x3100 #x312f)))))

(defstruct wrap-token
  kind
  (text "" :type string))

(defun split-wrap-tokens (text)
  (let ((tokens nil)
        (current "")
        current-kind
        (pending-ansi "")
        (index 0))
    (labels
        ((flush-current ()
           (when (plusp (length current))
             (push
              (make-wrap-token
               :kind current-kind
               :text current)
              tokens)
             (setf current ""
                   current-kind nil)))
         (accept-cluster (cluster)
           (let ((kind
                   (if (or (string= cluster " ")
                           (string= cluster
                                    (string #\Tab)))
                       :space
                       :word)))
             (when (cjk-cluster-p cluster)
               (flush-current)
               (push
                (make-wrap-token
                 :kind :word
                 :text
                 (concatenate
                  'string pending-ansi cluster))
                tokens)
               (setf pending-ansi "")
               (return-from accept-cluster nil))
             (when (and current-kind
                        (not (eq current-kind kind)))
               (flush-current))
             (when (plusp (length pending-ansi))
               (setf current
                     (concatenate
                      'string current pending-ansi)
                     pending-ansi ""))
             (setf current-kind kind
                   current
                   (concatenate
                    'string current cluster)))))
      (loop while (< index (length text))
            for ansi-end = (ansi-sequence-end text index)
            do
            (if ansi-end
                (progn
                  (setf pending-ansi
                        (concatenate
                         'string pending-ansi
                         (subseq text index ansi-end)))
                  (setf index ansi-end))
                (let* ((next-ansi
                         (or (position #\Escape text
                                       :start index)
                             (length text)))
                       (fragment
                         (subseq text index next-ansi)))
                  (dolist
                      (cluster (grapheme-clusters fragment))
                    (accept-cluster cluster))
                  (setf index next-ansi))))
      (when (plusp (length pending-ansi))
        (cond
          ((plusp (length current))
           (setf current
                 (concatenate
                  'string current pending-ansi)))
          (tokens
           (setf
            (wrap-token-text (first tokens))
            (concatenate
             'string
             (wrap-token-text (first tokens))
             pending-ansi)))
          (t
           (setf current pending-ansi
                 current-kind :word))))
      (flush-current))
    (nreverse tokens)))

(defun break-long-wrap-token (text width state)
  (let ((lines nil)
        (current (ansi-state-active-codes state))
        (current-width 0)
        (index 0))
    (loop while (< index (length text))
          for ansi-end = (ansi-sequence-end text index)
          do
          (if ansi-end
              (let ((code (subseq text index ansi-end)))
                (setf current
                      (concatenate 'string current code))
                (process-ansi-code state code)
                (setf index ansi-end))
              (let* ((next-ansi
                       (or (position #\Escape text
                                     :start index)
                           (length text)))
                     (fragment
                       (subseq text index next-ansi)))
                (dolist (cluster (grapheme-clusters fragment))
                  (let ((cluster-width
                          (grapheme-width cluster)))
                    (when (and (plusp current-width)
                               (> (+ current-width
                                     cluster-width)
                                  width))
                      (push
                       (concatenate
                        'string current
                        (ansi-state-line-end-reset state))
                       lines)
                      (setf current
                            (ansi-state-active-codes state)
                            current-width 0))
                    (setf current
                          (concatenate
                           'string current cluster))
                    (incf current-width cluster-width)))
                (setf index next-ansi))))
    (when (plusp (length current))
      (push current lines))
    (nreverse lines)))

(defun wrap-logical-line (line width)
  (when (< width 1)
    (error "Terminal width must be positive"))
  (when (zerop (length line))
    (return-from wrap-logical-line (list "")))
  (when (<= (visible-width line) width)
    (return-from wrap-logical-line (list line)))
  (let ((wrapped nil)
        (state (make-ansi-state))
        (current "")
        (current-width 0))
    (dolist (token (split-wrap-tokens line))
      (let* ((text (wrap-token-text token))
             (token-width (visible-width text))
             (space-p (eq (wrap-token-kind token) :space)))
        (cond
          ((and (> token-width width)
                (not space-p))
           (when (plusp (length current))
             (push
              (concatenate
               'string
               (string-right-trim
                '(#\Space #\Tab #\Newline #\Return)
                current)
               (ansi-state-line-end-reset state))
              wrapped)
             (setf current ""
                   current-width 0))
           (let ((broken
                   (break-long-wrap-token
                    text width state)))
             (dolist (complete (butlast broken))
               (push complete wrapped))
             (setf current (or (car (last broken)) "")
                   current-width
                   (visible-width current))))
          ((and (plusp current-width)
                (> (+ current-width token-width)
                   width))
           (push
            (concatenate
             'string
             (string-right-trim
              '(#\Space #\Tab #\Newline #\Return)
              current)
             (ansi-state-line-end-reset state))
            wrapped)
           (if space-p
               (setf current
                     (ansi-state-active-codes state)
                     current-width 0)
               (setf current
                     (concatenate
                      'string
                      (ansi-state-active-codes state)
                      text)
                     current-width token-width)))
          (t
           (setf current
                 (concatenate 'string current text))
           (incf current-width token-width)))
        (update-ansi-state state text)))
    (when (plusp (length current))
      (push current wrapped))
    (let ((result (nreverse wrapped)))
      (if result
          (mapcar
           (lambda (entry)
             (string-right-trim
              '(#\Space #\Tab #\Newline #\Return)
              entry))
           result)
          (list "")))))

(defun wrap-text (text width)
  (let ((result nil)
        (state (make-ansi-state)))
    (dolist (line (split-lines-preserving-empty text))
      (let* ((prefix
               (if result
                   (ansi-state-active-codes state)
                   ""))
             (wrapped
               (wrap-logical-line
                (concatenate 'string prefix line)
                width)))
        (setf result (nconc result wrapped))
        (update-ansi-state state line)))
    (or result (list ""))))
