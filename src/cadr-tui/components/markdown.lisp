(in-package #:cadr-tui)

(defun trim-markdown-prefix (line character)
  (string-left-trim
   (list #\Space character)
   line))

(defun ansi-style (code text enabled-p)
  (if enabled-p
      (format nil "~C[~Am~A~C[0m"
              #\Escape code text #\Escape)
      text))

(defun literal-string-replace-all
    (source needle replacement)
  (with-output-to-string (output)
    (loop with start = 0
          for position =
            (search needle source :start2 start)
          while position
          do
          (write-string source output
                        :start start
                        :end position)
          (write-string replacement output)
          (setf start (+ position
                         (length needle)))
          finally
          (write-string source output :start start))))

(defun style-function-prefix (function)
  (let* ((sentinel "cadr-style-sentinel")
         (styled (funcall function sentinel))
         (position (search sentinel styled)))
    (and position
         (subseq styled 0 position))))

(defun apply-restoring-style (text function)
  (let ((prefix
          (style-function-prefix function)))
    (funcall
     function
     (if (or (null prefix)
             (zerop (length prefix)))
         text
         (let ((result text))
           (dolist
               (reset
                (list
                 (format nil "~C[0m" #\Escape)
                 (format nil "~C[22m" #\Escape)
                 (format nil "~C[23m" #\Escape)
                 (format nil "~C[24m" #\Escape)
                 (format nil "~C[29m" #\Escape)
                 (format nil "~C[39m" #\Escape)))
             (setf
              result
              (literal-string-replace-all
               result reset
               (concatenate 'string
                            reset prefix))))
           result)))))

(defun replace-paired-marker
    (text marker &key open-code style-function
                       ansi-theme-p)
  (loop with position = 0
        with result = ""
        for start = (search marker text
                            :start2 position)
        while start
        for end = (search marker text
                          :start2 (+ start
                                     (length marker)))
        while end
        do
        (setf
         result
         (concatenate
          'string result
          (subseq text position start)
          (let ((value
                  (subseq
                   text
                   (+ start (length marker))
                   end)))
            (if style-function
                (funcall style-function
                         value ansi-theme-p)
                (ansi-style
                 open-code value
                 ansi-theme-p))))
         position (+ end (length marker)))
        finally
        (return
          (concatenate 'string result
                       (subseq text position)))))

(defun markdown-link-replacement
    (label url image-p capabilities
     ansi-theme-p)
  (if image-p
      (format nil "Image: ~A (~A)" label url)
      (let ((styled-label
              (theme-foreground
               :md-link
               (theme-underline
                label
                :enabled-p ansi-theme-p)
               :enabled-p ansi-theme-p)))
        (if (terminal-capabilities-hyperlinks-p
             capabilities)
            (terminal-hyperlink styled-label url)
            (if (or
                 (string= label url)
                 (and
                  (string-prefix-p "mailto:" url)
                  (string= label (subseq url 7))))
                styled-label
                (format
                 nil "~A (~A)"
                 styled-label
                 (theme-foreground
                  :md-link-url url
                  :enabled-p ansi-theme-p)))))))

(defun replace-markdown-links
    (text capabilities ansi-theme-p)
  (with-output-to-string (output)
    (loop with position = 0
          while (< position (length text))
          do
          (let* ((image-p
                   (and
                    (< (1+ position)
                       (length text))
                    (char= (char text position) #\!)
                    (char= (char text
                                 (1+ position))
                           #\[)))
                 (link-p
                   (char= (char text position)
                          #\[))
                 (label-start
                   (cond (image-p (+ position 2))
                         (link-p (1+ position))
                         (t nil))))
            (if (null label-start)
                (progn
                  (write-char
                   (char text position) output)
                  (incf position))
                (let* ((label-end
                         (position #\] text
                                   :start label-start))
                       (url-start
                         (and label-end
                              (< (1+ label-end)
                                 (length text))
                              (char=
                               (char text
                                     (1+ label-end))
                               #\()
                              (+ label-end 2)))
                       (url-end
                         (and url-start
                              (position #\) text
                                        :start url-start))))
                  (if (and label-end url-start url-end)
                      (progn
                        (write-string
                         (markdown-link-replacement
                          (subseq text
                                  label-start label-end)
                          (subseq text
                                  url-start url-end)
                          image-p capabilities
                          ansi-theme-p)
                         output)
                        (setf position (1+ url-end)))
                      (progn
                        (write-char
                         (char text position) output)
                        (incf position)))))))))

(defun render-inline-markdown
    (line ansi-theme-p capabilities
     &optional default-style-function)
  (let ((result
          (replace-markdown-links
           line capabilities ansi-theme-p)))
    (setf result
          (replace-paired-marker
           result "**" :open-code "1"
           :style-function
           (lambda (text enabled-p)
             (theme-bold
              text :enabled-p enabled-p))
           :ansi-theme-p ansi-theme-p)
          result
          (replace-paired-marker
           result "__" :open-code "1"
           :style-function
           (lambda (text enabled-p)
             (theme-bold
              text :enabled-p enabled-p))
           :ansi-theme-p ansi-theme-p)
          result
          (replace-paired-marker
           result "~~" :open-code "9"
           :ansi-theme-p ansi-theme-p)
          result
          (replace-paired-marker
           result "`" :open-code "36"
           :style-function
           (lambda (text enabled-p)
             (theme-foreground
              :md-code text
              :enabled-p enabled-p))
           :ansi-theme-p ansi-theme-p))
    (unless (search "**" result)
      (setf
       result
       (replace-paired-marker
        result "*" :open-code "3"
        :style-function
        (lambda (text enabled-p)
          (theme-italic
           text :enabled-p enabled-p))
        :ansi-theme-p ansi-theme-p)))
    (unless (search "__" result)
      (setf
       result
       (replace-paired-marker
        result "_" :open-code "3"
        :style-function
        (lambda (text enabled-p)
          (theme-italic
           text :enabled-p enabled-p))
        :ansi-theme-p ansi-theme-p)))
    (if default-style-function
        (apply-restoring-style
         result default-style-function)
        result)))

(defun markdown-table-divider-p (line)
  (let ((trimmed
          (string-trim '(#\Space #\Tab #\|)
                       line)))
    (and (plusp (length trimmed))
         (every
          (lambda (character)
            (member character
                    '(#\- #\: #\| #\Space #\Tab)))
          trimmed)
         (>= (count #\- trimmed) 3))))

(defun markdown-horizontal-rule-p (line)
  (let ((trimmed
          (remove-if
           (lambda (character)
             (member character
                     '(#\Space #\Tab)))
           line)))
    (and (>= (length trimmed) 3)
         (member (char trimmed 0)
                 '(#\- #\* #\_))
         (every
          (lambda (character)
            (char= character
                   (char trimmed 0)))
          trimmed))))

(defun markdown-table-cells (line)
  (let ((parts
          (uiop:split-string
           line :separator '(#\|))))
    (when
        (and parts
             (zerop
              (length
               (string-trim
                '(#\Space #\Tab)
                (first parts)))))
      (setf parts (rest parts)))
    (when
        (and parts
             (zerop
              (length
               (string-trim
                '(#\Space #\Tab)
                (car (last parts))))))
      (setf parts (butlast parts)))
    (mapcar
     (lambda (part)
       (string-trim
        '(#\Space #\Tab) part))
     parts)))

(defun markdown-table-border-line
    (left middle right widths
     ansi-theme-p)
  (theme-foreground
   :border-muted
   (with-output-to-string (stream)
     (write-char left stream)
     (loop for width in widths
           for first-p = t then nil
           do
           (unless first-p
             (write-char middle stream))
           (write-string
            (make-string
             (+ width 2)
             :initial-element #\─)
            stream))
     (write-char right stream))
   :enabled-p ansi-theme-p))

(defun markdown-table-row-lines
    (cells widths ansi-theme-p header-p
     capabilities default-style-function)
  (let ((border
          (lambda (text)
            (theme-foreground
             :border-muted text
             :enabled-p ansi-theme-p)))
        (cell-lines nil))
    (loop for width in widths
          for index from 0
          for cell = (or (nth index cells) "")
          for rendered =
            (render-inline-markdown
             cell ansi-theme-p capabilities
             default-style-function)
          do
          (push
           (or (wrap-text rendered width)
               (list ""))
           cell-lines))
    (setf cell-lines (nreverse cell-lines))
    (loop for line-index below
          (loop for lines in cell-lines
                maximize (length lines))
          collect
          (with-output-to-string (stream)
            (write-string (funcall border "│")
                          stream)
            (loop for width in widths
                  for lines in cell-lines
                  for rendered =
                    (or (nth line-index lines) "")
                  for padded =
                    (concatenate
                     'string rendered
                     (make-string
                      (max
                       0
                       (- width
                          (visible-width rendered)))
                      :initial-element #\Space))
                  do
                  (format
                   stream " ~A "
                   (if header-p
                       (theme-bold
                        padded
                        :enabled-p ansi-theme-p)
                       padded))
                  (write-string
                   (funcall border "│")
                   stream))))))

(defun markdown-longest-word-width (text maximum)
  (min
   maximum
   (loop for word in
         (remove-if
          (lambda (value) (zerop (length value)))
          (uiop:split-string
           text :separator '(#\Space #\Tab #\Newline #\Return)))
         maximize (visible-width word) into longest
         finally (return (or longest 0)))))

(defun markdown-table-widths
    (rows available-width ansi-theme-p
     capabilities default-style-function)
  (let* ((column-count
           (loop for row in rows
                 maximize (length row)))
         (overhead
           (+ 1 (* 3 column-count)))
         (available-for-cells
           (- available-width overhead))
         (natural-widths
           (make-list column-count
                      :initial-element 0))
         (minimum-widths
           (make-list column-count
                      :initial-element 1)))
    (dolist (row rows)
      (loop for index below column-count
            for rendered =
              (render-inline-markdown
               (or (nth index row) "")
               ansi-theme-p capabilities
               default-style-function)
            do
            (setf
             (nth index natural-widths)
             (max
              (nth index natural-widths)
              (visible-width rendered))
             (nth index minimum-widths)
             (max
              (nth index minimum-widths)
              (markdown-longest-word-width
               rendered 30)))))
    (let ((minimum-total
            (reduce #'+ minimum-widths
                    :initial-value 0)))
      (when (> minimum-total available-for-cells)
        (let* ((remaining
                 (- available-for-cells
                    column-count))
               (weight-total
                 (reduce
                  #'+ minimum-widths
                  :key
                  (lambda (width)
                    (max 0 (1- width)))
                  :initial-value 0))
               (growth
                 (loop for width in minimum-widths
                       collect
                       (if (plusp weight-total)
                           (floor
                            (*
                             (/ (max 0 (1- width))
                                weight-total)
                             remaining))
                           0)))
               (leftover
                 (- remaining
                    (reduce #'+ growth
                            :initial-value 0))))
          (setf
           minimum-widths
           (loop for amount in growth
                 collect (1+ amount)))
          (loop for tail on minimum-widths
                while (plusp leftover)
                do
                (incf (first tail))
                (decf leftover))
          (setf minimum-total
                (reduce #'+ minimum-widths
                        :initial-value 0))))
      (if
          (<= (+ overhead
                 (reduce #'+ natural-widths
                         :initial-value 0))
              available-width)
          (mapcar #'max
                  natural-widths minimum-widths)
          (let* ((growth-potential
                   (loop for natural in natural-widths
                         for minimum in minimum-widths
                         sum (max 0 (- natural minimum))))
                 (extra
                   (max 0
                        (- available-for-cells
                           minimum-total)))
                 (widths
                   (loop for natural in natural-widths
                         for minimum in minimum-widths
                         for delta =
                           (max 0 (- natural minimum))
                         collect
                         (+ minimum
                            (if (plusp growth-potential)
                                (floor
                                 (* (/ delta
                                       growth-potential)
                                    extra))
                                0))))
                 (remaining
                   (- available-for-cells
                      (reduce #'+ widths
                              :initial-value 0))))
            (loop while (plusp remaining)
                  for grew-p = nil
                  do
                  (loop for tail on widths
                        for natural in natural-widths
                        while (plusp remaining)
                        when (< (first tail) natural)
                          do
                          (incf (first tail))
                          (decf remaining)
                          (setf grew-p t))
                  (unless grew-p
                    (return)))
            widths)))))

(defun render-markdown-table
    (rows available-width
     ansi-theme-p capabilities
     raw-lines default-style-function)
  (let* ((column-count
           (loop for row in rows
                 maximize (length row)))
         (available-for-cells
           (- available-width
              (+ 1 (* 3 column-count)))))
    (when (< available-for-cells column-count)
      (return-from render-markdown-table
        (loop for line in raw-lines
              nconc
              (wrap-text line available-width))))
    (let* ((widths
             (markdown-table-widths
              rows available-width
              ansi-theme-p capabilities
              default-style-function))
           (separator
             (markdown-table-border-line
              #\├ #\┼ #\┤ widths
              ansi-theme-p))
           (result
             (append
              (list
               (markdown-table-border-line
                #\┌ #\┬ #\┐ widths
                ansi-theme-p))
              (markdown-table-row-lines
               (first rows) widths ansi-theme-p
               t capabilities default-style-function)
              (list separator))))
      (loop for remaining on (rest rows)
            for row = (first remaining)
            do
            (setf result
                  (nconc
                   result
                   (markdown-table-row-lines
                    row widths ansi-theme-p
                    nil capabilities
                    default-style-function)))
            (when (rest remaining)
              (setf result
                    (nconc result
                           (list separator)))))
      (nconc
       result
       (list
        (markdown-table-border-line
         #\└ #\┴ #\┘ widths
         ansi-theme-p))))))

(defun markdown-ordered-prefix-end (line)
  (let ((dot (position #\. line)))
    (when (and dot (plusp dot)
               (< (1+ dot) (length line))
               (char= (char line (1+ dot))
                      #\Space)
               (every #'digit-char-p
                      (subseq line 0 dot)))
      (+ dot 2))))

(defun markdown-heading-level (line)
  (loop for character across line
        while (char= character #\#)
        count 1))

(defun markdown-nonblank-line-p (line)
  (and line
       (plusp
        (length
         (string-trim '(#\Space #\Tab) line)))))

(defun markdown-code-fence-info (line)
  (let* ((trimmed
           (string-left-trim '(#\Space #\Tab) line))
         (marker
           (and (plusp (length trimmed))
                (member (char trimmed 0)
                        '(#\` #\~))
                (char trimmed 0))))
    (when marker
      (let ((length
              (loop for character across trimmed
                    while (char= character marker)
                    count 1)))
        (when (>= length 3)
          (values marker length
                  (string-trim
                   '(#\Space #\Tab)
                   (subseq trimmed length))))))))

(defun markdown-closing-fence-p
    (line marker minimum-length)
  (let* ((trimmed
           (string-left-trim '(#\Space #\Tab) line))
         (length
           (loop for character across trimmed
                 while (char= character marker)
                 count 1)))
    (and (>= length minimum-length)
         (zerop
          (length
           (string-trim
            '(#\Space #\Tab)
            (subseq trimmed length)))))))

(defun markdown-partial-closing-fence-p
    (line marker minimum-length)
  (let* ((trimmed
           (string-trim '(#\Space #\Tab) line))
         (length (length trimmed)))
    (and (plusp length)
         (< length minimum-length)
         (every
          (lambda (character)
            (char= character marker))
          trimmed))))

(defun markdown-leading-indent-width (line)
  (loop for character across line
        while (member character '(#\Space #\Tab))
        sum (if (char= character #\Tab) 4 1)))

(defun markdown-quote-data (line)
  (let ((index 0)
        (depth 0))
    (loop
      (when
          (or (>= index (length line))
              (not (char= (char line index) #\>)))
        (return))
      (incf depth)
      (incf index)
      (when
          (and (< index (length line))
               (member (char line index)
                       '(#\Space #\Tab)))
        (incf index)))
    (when (plusp depth)
      (values depth (subseq line index)))))

(defun markdown-quote-line-p (line)
  (nth-value 0 (markdown-quote-data line)))

(defun render-markdown-quote-line
    (line available-width ansi-theme-p
     capabilities)
  (multiple-value-bind (depth content)
      (markdown-quote-data line)
    (let* ((prefix
             (with-output-to-string (stream)
               (loop repeat depth
                     do
                     (write-string
                      (theme-foreground
                       :md-quote-border "│"
                       :enabled-p ansi-theme-p)
                      stream)
                     (write-char #\Space stream))))
           (content-width
             (max 1 (- available-width
                       (* depth 2))))
           (style-function
             (lambda (value)
               (theme-foreground
                :md-quote
                (theme-italic
                 value
                 :enabled-p ansi-theme-p)
                :enabled-p ansi-theme-p)))
           (rendered
             (apply-restoring-style
              (render-inline-markdown
               content ansi-theme-p capabilities)
              style-function))
           (wrapped
             (if (zerop (length content))
                 (list "")
                 (wrap-text rendered content-width))))
      (loop for part in wrapped
            collect
            (concatenate 'string prefix part)))))

(defun markdown-list-item-data
    (line &optional preserve-marker-p)
  (let ((index 0)
        (indent-width 0))
    (loop while (< index (length line))
          for character = (char line index)
          while (member character '(#\Space #\Tab))
          do
          (incf indent-width
                (if (char= character #\Tab) 4 1))
          (incf index))
    (when (< index (length line))
      (multiple-value-bind (marker content-start)
          (cond
            ((and
              (member (char line index)
                      '(#\- #\* #\+))
              (< (1+ index) (length line))
              (member (char line (1+ index))
                      '(#\Space #\Tab)))
             (values
              (if preserve-marker-p
                  (string (char line index))
                  "-")
              (+ index 2)))
            ((digit-char-p (char line index))
             (let ((end index))
               (loop while
                     (and (< end (length line))
                          (digit-char-p
                           (char line end)))
                     do (incf end))
               (if
                   (and
                    (< (1+ end) (length line))
                    (member (char line end)
                            '(#\. #\)))
                    (member (char line (1+ end))
                            '(#\Space #\Tab)))
                   (values
                    (subseq line index (1+ end))
                    (+ end 2))
                   (values nil nil))))
            (t (values nil nil)))
        (when marker
          (let* ((content
                   (subseq line content-start))
                 (task-marker
                   (and
                    (>= (length content) 4)
                    (char= (char content 0) #\[)
                    (member
                     (char-downcase (char content 1))
                     '(#\Space #\x))
                    (char= (char content 2) #\])
                    (member (char content 3)
                            '(#\Space #\Tab))
                    (subseq content 0 3)))
                 (body
                   (if task-marker
                       (subseq content 4)
                       content))
                 (normalized-indent
                   (if (zerop indent-width)
                       0
                       (* 4 (ceiling indent-width 4))))
                 (display-marker
                   (if task-marker
                       (format nil "~A ~A"
                               marker task-marker)
                       marker)))
            (list normalized-indent
                  display-marker body)))))))

(defun render-markdown-list-item
    (line available-width ansi-theme-p
     capabilities preserve-marker-p
     &optional default-style-function)
  (destructuring-bind
        (indent marker content)
      (markdown-list-item-data
       line preserve-marker-p)
    (let* ((plain-prefix
             (concatenate
              'string
              (make-string indent
                           :initial-element #\Space)
              marker " "))
           (styled-prefix
             (concatenate
              'string
              (make-string indent
                           :initial-element #\Space)
              (theme-foreground
               :md-list-bullet marker
               :enabled-p ansi-theme-p)
              " "))
           (continuation
             (make-string
              (visible-width plain-prefix)
              :initial-element #\Space))
           (content-width
             (max
              1
              (- available-width
                 (visible-width plain-prefix))))
           (wrapped
             (wrap-text
              (render-inline-markdown
               content ansi-theme-p capabilities
               default-style-function)
              content-width)))
      (if wrapped
          (cons
           (concatenate 'string
                        styled-prefix
                        (first wrapped))
           (loop for part in (rest wrapped)
                 collect
                 (concatenate 'string
                              continuation part)))
          (list styled-prefix)))))

(defun render-markdown-list-continuation
    (line prefix-width available-width
     ansi-theme-p capabilities
     default-style-function)
  (let* ((content
           (string-left-trim '(#\Space #\Tab) line))
         (prefix
           (make-string prefix-width
                        :initial-element #\Space))
         (content-width
           (max 1 (- available-width prefix-width)))
         (wrapped
           (wrap-text
            (render-inline-markdown
             content ansi-theme-p capabilities
             default-style-function)
            content-width)))
    (loop for part in wrapped
          collect
          (concatenate 'string prefix part))))

(defun markdown-line
    (line in-code-p ansi-theme-p
     capabilities available-width
     &optional default-style-function)
  (cond
    ((string-prefix-p "```" line)
     (values
      (theme-foreground
       :md-code-block-border line
       :enabled-p ansi-theme-p)
      (not in-code-p) nil))
    (in-code-p
     (values
      (theme-foreground
       :md-code-block
       (concatenate 'string "  " line)
       :enabled-p ansi-theme-p)
      in-code-p nil))
    ((markdown-horizontal-rule-p line)
     (values
      (theme-foreground
       :md-hr
       (make-string
        (min 80 available-width)
        :initial-element #\─)
       :enabled-p ansi-theme-p)
      in-code-p nil))
    ((markdown-table-divider-p line)
     (values "" in-code-p t))
    ((and (> (length line) 0)
          (char= (char line 0) #\#))
     (let* ((level
              (markdown-heading-level line))
            (text
              (if (<= level 2)
                  (string-left-trim
                   '(#\Space)
                   (subseq line level))
                  line))
            (style-function
              (lambda (value)
                (theme-foreground
                 :md-heading
                 (if (= level 1)
                     (theme-underline
                      (theme-bold
                       value
                       :enabled-p ansi-theme-p)
                      :enabled-p ansi-theme-p)
                     (theme-bold
                      value
                      :enabled-p ansi-theme-p))
                 :enabled-p ansi-theme-p)))
            (styled
              (apply-restoring-style
               (render-inline-markdown
                text ansi-theme-p capabilities)
               style-function)))
       (values styled in-code-p nil)))
    (t
     (values
      (render-inline-markdown
       line ansi-theme-p capabilities
       default-style-function)
      in-code-p nil))))

(defun render-markdown
    (text width &key ansi-theme-p
                     transform-function
                     syntax-highlight-function
                     default-style-function
                     (preserve-list-markers-p nil)
                     (padding-x 0)
                     (padding-y 0)
                     (capabilities
                       (get-terminal-capabilities)))
  (let* ((available-width
           (max 1 (- width (* 2 padding-x))))
         (text
          (if transform-function
              (let ((transformed
                      (funcall transform-function
                               text available-width)))
                (if (stringp transformed)
                    transformed
                    text))
              text))
        (in-code-p nil)
        (result nil)
        (list-prefix-width nil))
    (let ((source-lines
            (split-lines-preserving-empty text)))
      (loop while source-lines
            for line = (pop source-lines)
            for next = (first source-lines)
            do
            (multiple-value-bind
                  (fence-marker fence-length language)
                (markdown-code-fence-info line)
              (cond
                (fence-marker
                 (setf list-prefix-width nil)
                 (let ((code-lines nil))
                   (loop while source-lines
                         for candidate = (pop source-lines)
                         do
                         (cond
                           ((markdown-closing-fence-p
                             candidate fence-marker
                             fence-length)
                            (return))
                           ((and
                             (null source-lines)
                             (markdown-partial-closing-fence-p
                              candidate fence-marker
                              fence-length))
                            nil)
                           (t
                            (push candidate code-lines))))
                   (setf code-lines (nreverse code-lines))
                   (let* ((source
                            (format nil "~{~A~^~%~}"
                                    code-lines))
                          (highlighted
                            (and
                             syntax-highlight-function
                             (funcall
                              syntax-highlight-function
                              language source)))
                          (display-lines
                            (or
                             (if (stringp highlighted)
                                 (split-lines-preserving-empty
                                  highlighted)
                                 code-lines)
                             (list ""))))
                     (setf result
                           (nconc
                            result
                            (wrap-text
                             (theme-foreground
                              :md-code-block-border
                              (format nil "```~A" language)
                              :enabled-p ansi-theme-p)
                             available-width)))
                     (dolist (code-line display-lines)
                       (setf result
                             (nconc
                              result
                              (wrap-text
                               (concatenate
                                'string "  "
                                (if (stringp highlighted)
                                    code-line
                                    (theme-foreground
                                     :md-code-block
                                     code-line
                                     :enabled-p ansi-theme-p)))
                               available-width))))
                     (setf result
                           (nconc
                            result
                            (wrap-text
                             (theme-foreground
                              :md-code-block-border
                              "```"
                              :enabled-p ansi-theme-p)
                             available-width)))
                     (when
                         (markdown-nonblank-line-p
                          (first source-lines))
                       (setf result
                             (nconc result
                                    (list "")))))))
                ((and
                  (not in-code-p)
                  (find #\| line)
                  next
                  (markdown-table-divider-p next))
                 (setf list-prefix-width nil)
                 (let ((rows
                         (list
                          (markdown-table-cells
                           line)))
                       (raw-lines (list line next)))
                   (pop source-lines)
                   (loop while
                         (and source-lines
                              (find #\|
                                    (first source-lines))
                              (plusp
                               (length
                                (string-trim
                                 '(#\Space #\Tab)
                                 (first source-lines)))))
                         do
                         (let ((raw-line
                                 (pop source-lines)))
                           (setf raw-lines
                                 (nconc raw-lines
                                        (list raw-line))
                                 rows
                                 (nconc
                                  rows
                                  (list
                                   (markdown-table-cells
                                    raw-line))))))
                   (setf result
                         (nconc
                          result
                          (render-markdown-table
                           rows available-width
                           ansi-theme-p
                           capabilities
                           raw-lines
                           default-style-function)))
                   (when
                       (markdown-nonblank-line-p
                        (first source-lines))
                     (setf result
                           (nconc result
                                  (list ""))))))
                ((markdown-quote-line-p line)
                 (setf list-prefix-width nil
                       result
                       (nconc
                        result
                        (render-markdown-quote-line
                         line available-width
                         ansi-theme-p capabilities)))
                 (when
                     (and
                      (markdown-nonblank-line-p next)
                      (not (markdown-quote-line-p next)))
                   (setf result
                         (nconc result (list "")))))
                ((let ((data
                         (markdown-list-item-data
                          line preserve-list-markers-p)))
                   (when data
                     (setf
                      list-prefix-width
                      (+ (first data)
                         (visible-width (second data))
                         1)
                      result
                      (nconc
                       result
                       (render-markdown-list-item
                        line available-width
                        ansi-theme-p capabilities
                        preserve-list-markers-p
                        default-style-function)))
                     t)))
                ((and list-prefix-width
                      (markdown-nonblank-line-p line)
                      (plusp
                       (markdown-leading-indent-width
                        line)))
                 (setf result
                       (nconc
                        result
                        (render-markdown-list-continuation
                         line list-prefix-width
                         available-width ansi-theme-p
                         capabilities
                         default-style-function))))
                (t
                 (unless
                     (zerop
                      (length
                       (string-trim
                        '(#\Space #\Tab) line)))
                   (setf list-prefix-width nil))
                 (multiple-value-bind
                       (rendered next-code-p skip-p)
                     (markdown-line
                      line in-code-p ansi-theme-p
                      capabilities available-width
                      default-style-function)
                   (setf in-code-p next-code-p)
                   (unless skip-p
                     (setf result
                           (nconc
                            result
                            (wrap-text
                             rendered
                             available-width))))
                   (when
                       (and
                        (or
                         (plusp
                          (markdown-heading-level line))
                         (markdown-horizontal-rule-p
                          line))
                        (markdown-nonblank-line-p next))
                     (setf result
                           (nconc result
                                  (list ""))))))))))
    (let ((content
            (loop for line in result
                  collect
                  (if (image-line-p line)
                      line
                      (let* ((with-margins
                               (concatenate
                                'string
                                (make-string
                                 padding-x
                                 :initial-element
                                 #\Space)
                                line
                                (make-string
                                 padding-x
                                 :initial-element
                                 #\Space)))
                             (visible
                               (visible-width
                                with-margins)))
                        (concatenate
                         'string
                         with-margins
                         (make-string
                          (max 0 (- width visible))
                          :initial-element
                          #\Space))))))
          (empty
            (make-string
             width :initial-element #\Space)))
      (or
       (append
        (make-list padding-y
                   :initial-element empty)
        content
        (make-list padding-y
                   :initial-element empty))
       (list "")))))

(defun render-truncated-text
    (text width &key (padding-x 0)
                     (padding-y 0))
  (let* ((empty
           (make-string width
                        :initial-element #\Space))
         (available
           (max 1 (- width (* 2 padding-x))))
         (newline
           (position-if
            (lambda (character)
              (member character
                      '(#\Newline #\Return)))
            text))
         (first-line
           (if newline
               (subseq text 0 newline)
               text))
         (display
           (truncate-to-width
            first-line available))
         (line
           (concatenate
            'string
            (make-string padding-x
                         :initial-element #\Space)
            display
            (make-string padding-x
                         :initial-element #\Space)))
         (line-width (visible-width line))
         (final-line
           (concatenate
            'string line
            (make-string
             (max 0 (- width line-width))
             :initial-element #\Space))))
    (append
     (make-list padding-y
                :initial-element empty)
     (list final-line)
     (make-list padding-y
                :initial-element empty))))
