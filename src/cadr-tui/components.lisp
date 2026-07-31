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

(defun markdown-table-widths
    (rows available-width)
  (let* ((column-count
           (loop for row in rows
                 maximize (length row)))
         (overhead
           (+ 1 (* 3 column-count)))
         (per-column
           (max
            1
            (min
             30
             (floor
              (max column-count
                   (- available-width overhead))
              (max 1 column-count))))))
    (loop for index below column-count
          collect
          (max
           1
           (min
            per-column
            (loop for row in rows
                  maximize
                  (visible-width
                   (or (nth index row) ""))))))))

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
              rows available-width))
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

(defun render-image-component
    (base64-data mime-type width
     &key dimensions filename image-id
       max-width-cells max-height-cells
       (capabilities
         (get-terminal-capabilities)))
  (let* ((image-width (or (first dimensions) 800))
         (image-height (or (second dimensions) 600))
         (maximum-width
           (max 1
                (min (- width 2)
                     (or max-width-cells 60)))))
    (if (terminal-capabilities-images capabilities)
        (let ((result
                (render-terminal-image
                 base64-data image-width image-height
                 :capabilities capabilities
                 :max-width-cells maximum-width
                 :max-height-cells max-height-cells
                 :image-id image-id
                 :move-cursor-p nil)))
          (if result
              (cons
               (image-render-result-sequence result)
               (make-list
                (1- (image-render-result-rows result))
                :initial-element ""))
              (list
               (truncate-to-width
                (image-fallback
                 mime-type :width image-width
                 :height image-height
                 :filename filename
                 :capabilities capabilities)
                width))))
        (list
         (truncate-to-width
          (image-fallback
           mime-type :width image-width
           :height image-height
           :filename filename
           :capabilities capabilities)
          width)))))

(defstruct (tool-block
            (:constructor %make-tool-block))
  (name "" :type string)
  (summary "" :type string)
  (output "" :type string)
  (status :running :type symbol)
  (collapsed-p nil :type boolean)
  started-at
  ended-at)

(defun make-tool-block (&key (name "") (summary "")
                             (output "") (status :running)
                             started-at ended-at
                             (collapsed-p nil
                              collapsed-p-supplied-p))
  (%make-tool-block
   :name name
   :summary summary
   :output output
   :status status
   :started-at started-at
   :ended-at ended-at
   :collapsed-p
   (if collapsed-p-supplied-p
       collapsed-p
       (eq status :complete))))

(defun toggle-tool-block (block)
  (setf (tool-block-collapsed-p block)
        (not (tool-block-collapsed-p block)))
  block)

(defun tool-status-theme-tokens (status)
  (case status
    (:running
     (values :accent
             :tool-pending-bg nil))
    (:error
     (values :error
             :tool-error-bg nil))
    (otherwise
     (values :success
             :tool-success-bg nil))))

(defun normalize-tool-output (text)
  (cl-ppcre:regex-replace-all
   (string #\Tab)
   (strip-terminal-sequences
    (or text ""))
   "   "))

(defun trim-trailing-empty-lines (lines)
  (loop while
        (and lines
             (zerop (length (car (last lines)))))
        do (setf lines (butlast lines)))
  lines)

(defun tool-preview-budget (name)
  (cond
    ((string-equal name "bash") 5)
    ((string-equal name "read") 0)
    ((string-equal name "write") 10)
    ((string-equal name "grep") 15)
    ((member name '("find" "ls")
             :test #'string-equal)
     20)
    (t nil)))

(defun tool-output-line-token (line status)
  (cond
    ((eq status :error) :error)
    ((cl-ppcre:scan
      "(?i)^(?:\\[)?(?:error|failed|failure)\\b"
      (string-left-trim '(#\Space #\Tab) line))
     :error)
    ((cl-ppcre:scan
      "(?i)^(?:\\[)?(?:warning|warn|truncated|timed out)\\b"
      (string-left-trim '(#\Space #\Tab) line))
     :warning)
    (t :tool-output)))

(defun diff-line-data (line)
  (when (plusp (length line))
    (let ((kind
            (case (char line 0)
              (#\- :removed)
              (#\+ :added)
              (#\Space :context))))
      (when kind
        (let ((index 1))
          (loop while
                (and (< index (length line))
                     (member (char line index)
                             '(#\Space #\Tab)))
                do (incf index))
          (loop while
                (and (< index (length line))
                     (digit-char-p (char line index)))
                do (incf index))
          (when
              (and (< index (length line))
                   (member (char line index)
                           '(#\Space #\Tab)))
            (let ((content-start (1+ index)))
              (list kind
                    (subseq line 0 content-start)
                    (subseq line content-start)))))))))

(defun word-diff-token-kind (cluster)
  (cond
    ((every
      (lambda (character)
        (member character
                '(#\Space #\Tab #\Newline #\Return)))
      cluster)
     :space)
    ((every #'alphanumericp cluster) :word)
    (t :punctuation)))

(defun word-diff-tokens (text)
  (let ((tokens nil)
        (current "")
        current-kind)
    (labels
        ((flush ()
           (when (plusp (length current))
             (push (cons current-kind current) tokens)
             (setf current ""
                   current-kind nil))))
      (dolist (cluster (grapheme-clusters text))
        (let ((kind (word-diff-token-kind cluster)))
          (when (and current-kind
                     (not (eq current-kind kind)))
            (flush))
          (setf current-kind kind
                current
                (concatenate 'string current cluster))))
      (flush))
    (nreverse tokens)))

(defconstant +word-diff-max-matrix-cells+
  65536)

(defun word-diff-match-matrix (old new)
  (let* ((old-count (length old))
         (new-count (length new))
         (matrix
           (make-array
            (list (1+ old-count) (1+ new-count))
            :element-type 'fixnum
            :initial-element 0)))
    (loop for old-index downfrom (1- old-count) to 0 do
      (loop for new-index downfrom (1- new-count) to 0 do
        (setf
         (aref matrix old-index new-index)
         (if (string=
              (cdr (aref old old-index))
              (cdr (aref new new-index)))
             (1+
              (aref matrix
                    (1+ old-index)
                    (1+ new-index)))
             (max
              (aref matrix (1+ old-index) new-index)
              (aref matrix old-index (1+ new-index)))))))
    matrix))

(defun word-diff-matched-indices (old new)
  (let* ((old (coerce old 'vector))
         (new (coerce new 'vector))
         (cells
           (* (length old)
              (length new))))
    (when (> cells +word-diff-max-matrix-cells+)
      (return-from word-diff-matched-indices
        (values nil nil t)))
    (let ((matrix (word-diff-match-matrix old new))
        (old-index 0)
        (new-index 0)
        (old-matches nil)
        (new-matches nil))
    (loop while
          (and (< old-index (length old))
               (< new-index (length new)))
          do
          (cond
            ((string=
              (cdr (aref old old-index))
              (cdr (aref new new-index)))
             (push old-index old-matches)
             (push new-index new-matches)
             (incf old-index)
             (incf new-index))
            ((>=
              (aref matrix (1+ old-index) new-index)
              (aref matrix old-index (1+ new-index)))
             (incf old-index))
            (t
             (incf new-index))))
      (values (nreverse old-matches)
              (nreverse new-matches)
              nil))))

(defun render-word-diff-side
    (tokens matched-indices ansi-theme-p)
  (with-output-to-string (stream)
    (loop for token in tokens
          for index from 0
          for kind = (car token)
          for text = (cdr token)
          do
          (write-string
           (if (or (eq kind :space)
                   (member index matched-indices))
               text
               (theme-inverse
                text :enabled-p ansi-theme-p))
           stream))))

(defun render-word-diff
    (old-content new-content ansi-theme-p)
  (let ((old (word-diff-tokens old-content))
        (new (word-diff-tokens new-content)))
    (multiple-value-bind
          (old-matches new-matches bounded-p)
        (word-diff-matched-indices old new)
      (values
       (if bounded-p
           old-content
           (render-word-diff-side
            old old-matches ansi-theme-p))
       (if bounded-p
           new-content
           (render-word-diff-side
            new new-matches ansi-theme-p))))))

(defun style-diff-lines (lines ansi-theme-p)
  (let ((result nil)
        (remaining lines))
    (loop while remaining
          for line = (pop remaining)
          for data = (diff-line-data line)
          do
          (if (and data (eq (first data) :removed))
              (let ((removed (list data))
                    (added nil))
                (loop while
                      (and remaining
                           (let ((next
                                   (diff-line-data
                                    (first remaining))))
                             (and next
                                  (eq (first next)
                                      :removed))))
                      do
                      (push
                       (diff-line-data (pop remaining))
                       removed))
                (setf removed (nreverse removed))
                (loop while
                      (and remaining
                           (let ((next
                                   (diff-line-data
                                    (first remaining))))
                             (and next
                                  (eq (first next)
                                      :added))))
                      do
                      (push
                       (diff-line-data (pop remaining))
                       added))
                (setf added (nreverse added))
                (if (and (= 1 (length removed))
                         (= 1 (length added)))
                    (multiple-value-bind
                          (old-content new-content)
                        (render-word-diff
                         (third (first removed))
                         (third (first added))
                         ansi-theme-p)
                      (push
                       (theme-foreground
                        :tool-diff-removed
                        (concatenate
                         'string
                         (second (first removed))
                         old-content)
                        :enabled-p ansi-theme-p)
                       result)
                      (push
                       (theme-foreground
                        :tool-diff-added
                        (concatenate
                         'string
                         (second (first added))
                         new-content)
                        :enabled-p ansi-theme-p)
                       result))
                    (progn
                      (dolist (entry removed)
                        (push
                         (theme-foreground
                          :tool-diff-removed
                          (concatenate
                           'string (second entry)
                           (third entry))
                          :enabled-p ansi-theme-p)
                         result))
                      (dolist (entry added)
                        (push
                         (theme-foreground
                          :tool-diff-added
                          (concatenate
                           'string (second entry)
                           (third entry))
                          :enabled-p ansi-theme-p)
                         result)))))
              (push
               (if data
                   (theme-foreground
                    (case (first data)
                      (:added :tool-diff-added)
                      (:removed :tool-diff-removed)
                      (otherwise :tool-diff-context))
                    line :enabled-p ansi-theme-p)
                   (theme-foreground
                    :tool-diff-context line
                    :enabled-p ansi-theme-p))
               result)))
    (nreverse result)))

(defun style-tool-output-lines
    (block ansi-theme-p)
  (let* ((lines
           (trim-trailing-empty-lines
            (split-lines-preserving-empty
             (normalize-tool-output
              (tool-block-output block)))))
         (diff-p
           (and
            (string-equal
             (tool-block-name block) "edit")
            (some
             (lambda (line)
               (let ((data (diff-line-data line)))
                 (and data
                      (member (first data)
                              '(:removed :added)))))
             lines))))
    (if diff-p
        (style-diff-lines lines ansi-theme-p)
        (loop for line in lines
              collect
              (theme-foreground
               (tool-output-line-token
                line (tool-block-status block))
               line :enabled-p ansi-theme-p)))))

(defun tool-output-preview-lines
    (block content-width ansi-theme-p)
  (let* ((styled-lines
           (style-tool-output-lines
            block ansi-theme-p))
         (visual-lines
           (loop for line in styled-lines
                 nconc
                 (wrap-logical-line
                  line content-width)))
         (budget
           (and
            (tool-block-collapsed-p block)
            (if (and
                 (string-equal
                  (tool-block-name block) "read")
                 (eq (tool-block-status block) :error))
                10
                (tool-preview-budget
                 (tool-block-name block))))))
    (cond
      ((and budget (zerop budget))
       nil)
      ((or (null budget)
           (<= (length visual-lines) budget))
       visual-lines)
      ((string-equal (tool-block-name block)
                     "bash")
       (let ((skipped (- (length visual-lines)
                         budget)))
         (cons
          (truncate-to-width
           (theme-foreground
            :muted
            (format nil
                    "... (~D earlier lines, to expand)"
                    skipped)
            :enabled-p ansi-theme-p)
           content-width "...")
          (nthcdr skipped visual-lines))))
      (t
       (append
        (subseq visual-lines 0 budget)
        (list
         (truncate-to-width
          (theme-foreground
           :muted
           (format nil
                   "... (~D more lines, to expand)"
                   (- (length visual-lines) budget))
           :enabled-p ansi-theme-p)
          content-width "...")))))))

(defun render-tool-block
    (block width &key (ansi-theme-p nil) now)
  (multiple-value-bind
        (status-token background-token indicator)
      (tool-status-theme-tokens
       (tool-block-status block))
    (let* ((content-width (max 1 (- width 2)))
           (header
             (format
              nil "~@[~A ~]~A~@[ ~A~]"
              (and
               indicator
               (theme-foreground
                status-token indicator
                :enabled-p ansi-theme-p))
              (theme-foreground
               :tool-title
               (theme-bold
                (if
                    (string-equal
                     (tool-block-name block)
                     "bash")
                    "$"
                    (tool-block-name block))
                :enabled-p ansi-theme-p)
               :enabled-p ansi-theme-p)
              (let ((summary
                      (tool-block-summary block)))
                (and
                 (plusp (length summary))
                 (theme-foreground
                  :accent summary
                  :enabled-p ansi-theme-p)))))
           (header-lines
             (wrap-logical-line
              header content-width))
           (output-lines
             (unless
                 (zerop
                   (length
                    (tool-block-output block)))
               (tool-output-preview-lines
                block content-width
                ansi-theme-p)))
           (timing-line
             (and
              (string-equal
               (tool-block-name block) "bash")
              (tool-block-started-at block)
              (let* ((running-p
                       (eq (tool-block-status block)
                           :running))
                     (end
                       (or
                        (tool-block-ended-at block)
                        now
                        (tool-block-started-at block)))
                     (elapsed
                       (max
                        0d0
                        (- end
                           (tool-block-started-at block)))))
                (theme-foreground
                 :muted
                 (format nil "~A ~,1Fs"
                         (if running-p "Elapsed" "Took")
                         elapsed)
                 :enabled-p ansi-theme-p))))
           (box-lines
             (append
              (list "")
              header-lines
              output-lines
              (and timing-line (list timing-line))
              (list ""))))
      (cons
       ""
       (loop for line in box-lines
             for padded =
               (concatenate
                'string " " line
                (make-string
                 (max
                  1
                  (- width
                     1
                     (visible-width line)))
                 :initial-element #\Space))
             collect
             (theme-background
              background-token padded
              :enabled-p ansi-theme-p))))))

(defun fit-status (text width)
  (multiple-value-bind (prefix used)
      (slice-to-width text width)
    (concatenate
     'string prefix
     (make-string
      (max 0 (- width used))
     :initial-element #\Space))))

(defun format-footer-tokens (count)
  (cond
    ((< count 1000)
     (format nil "~D" count))
    ((< count 10000)
     (format nil "~,1Fk"
             (/ count 1000d0)))
    ((< count 1000000)
     (format nil "~Dk"
             (floor (+ count 500) 1000)))
    ((< count 10000000)
     (format nil "~,1FM"
             (/ count 1000000d0)))
    (t
     (format nil "~DM"
             (floor (+ count 500000)
                    1000000)))))

(defun footer-context-text
    (percent context-window
     auto-compact-p ansi-theme-p)
  (let* ((display
           (format
            nil "~A/~A~:[~; (auto)~]"
            (if (numberp percent)
                (format nil "~,1F%"
                        (coerce percent
                                'double-float))
                "?")
            (format-footer-tokens
             (or context-window 0))
            auto-compact-p))
         (token
           (cond
             ((and (numberp percent)
                   (> percent 90))
              :error)
             ((and (numberp percent)
                   (> percent 70))
              :warning)
             (t :dim))))
    (theme-foreground
     token display
     :enabled-p ansi-theme-p)))

(defun sanitize-footer-status (text)
  (string-trim
   '(#\Space #\Tab)
   (cl-ppcre:regex-replace-all
    "[\\r\\n\\t ]+" (or text "") " ")))

(defun render-footer
    (width
     &key cwd branch session-name
       model provider thinking
       (input 0) (output 0)
       (cache-read 0) (cache-write 0)
       latest-cache-hit-rate
       cost subscription-p
       context-percent
       (context-window 0)
       (auto-compact-p t)
       multiple-providers-p
       statuses
       (ansi-theme-p nil))
  (let* ((location
           (format
            nil "~A~@[ (~A)~]~@[ • ~A~]"
            (or cwd "")
            branch session-name))
         (parts nil))
    (when (plusp input)
      (push
       (format nil "↑~A"
               (format-footer-tokens input))
       parts))
    (when (plusp output)
      (push
       (format nil "↓~A"
               (format-footer-tokens output))
       parts))
    (when (plusp cache-read)
      (push
       (format nil "R~A"
               (format-footer-tokens cache-read))
       parts))
    (when (plusp cache-write)
      (push
       (format nil "W~A"
               (format-footer-tokens cache-write))
       parts))
    (when
        (and
         (or (plusp cache-read)
             (plusp cache-write))
         (numberp latest-cache-hit-rate))
      (push
       (format
        nil "CH~,1F%"
        (coerce latest-cache-hit-rate
                'double-float))
       parts))
    (when (or cost subscription-p)
      (push
       (format
        nil "$~,3F~:[~; (sub)~]"
        (coerce (or cost 0d0)
                'double-float)
        subscription-p)
       parts))
    (setf parts (nreverse parts))
    (let* ((plain-left
             (format nil "~{~A~^ ~}" parts))
           (context
             (footer-context-text
              context-percent context-window
              auto-compact-p ansi-theme-p))
           (left
             (if (plusp
                  (length plain-left))
                 (concatenate
                  'string
                  (theme-foreground
                   :dim plain-left
                   :enabled-p ansi-theme-p)
                  " " context)
                 context))
           (thinking-name
             (and thinking
                  (string-downcase
                   (if (symbolp thinking)
                       (symbol-name thinking)
                       (princ-to-string
                        thinking)))))
           (right-without-provider
             (format
              nil "~A~@[ • ~A~]"
              (or model "no-model")
              (and
               thinking-name
               (if (string= thinking-name
                            "off")
                   "thinking off"
                   thinking-name))))
           (right
             (if
                 (and multiple-providers-p
                      provider)
                 (format nil "(~A) ~A"
                         provider
                         right-without-provider)
                 right-without-provider))
           (left-width (visible-width left))
           (right-width (visible-width right)))
      (when (> left-width width)
        (setf left
              (truncate-to-width
               left width "...")
              left-width
              (visible-width left)))
      (when
          (and
           multiple-providers-p
           (> (+ left-width 2 right-width)
              width))
        (setf right right-without-provider
              right-width
              (visible-width right)))
      (let* ((available
               (- width left-width 2))
             (visible-right
               (if (plusp available)
                   (truncate-to-width
                    right available "" nil)
                   ""))
             (visible-right-width
               (visible-width visible-right))
             (second-line
               (if (plusp visible-right-width)
                   (concatenate
                    'string left
                    (make-string
                     (max
                      2
                      (- width left-width
                         visible-right-width))
                     :initial-element #\Space)
                    (theme-foreground
                     :dim visible-right
                     :enabled-p
                     ansi-theme-p))
                   left))
             (lines
               (list
                (truncate-to-width
                 (theme-foreground
                  :dim location
                  :enabled-p ansi-theme-p)
                 width "...")
                (truncate-to-width
                 second-line width "" nil))))
        (if statuses
            (append
             lines
             (list
              (truncate-to-width
               (format
                nil "~{~A~^ ~}"
                (loop for entry in
                        (sort
                         (copy-list statuses)
                         #'string<
                         :key #'car)
                      collect
                      (sanitize-footer-status
                       (cdr entry))))
               width
               (theme-foreground
                :dim "..."
                :enabled-p ansi-theme-p)
               nil)))
            lines)))))

(defun render-status-bar
    (width &key model (input 0) (output 0)
                  (cache 0) cost session)
  (second
   (render-footer
    width
    :session-name session
    :model model
    :input input
    :output output
    :cache-read cache
    :cost cost)))

(defstruct select-item
  (label "" :type string)
  value
  description)

(defstruct (select-list
            (:constructor %make-select-list))
  (items nil :type list)
  (query "" :type string)
  (selected 0 :type (integer 0 *))
  (height 8 :type (integer 1 *))
  (show-filter-p t :type boolean)
  (min-primary-column-width 32
                            :type (integer 1 *))
  (max-primary-column-width 32
                            :type (integer 1 *))
  truncate-primary)

(defun make-select-list
    (&key items (height 5) (show-filter-p t)
       (min-primary-column-width 32)
       (max-primary-column-width 32)
       truncate-primary)
  (%make-select-list
   :items (copy-list items)
   :height height
   :show-filter-p show-filter-p
   :min-primary-column-width
   min-primary-column-width
   :max-primary-column-width
   max-primary-column-width
   :truncate-primary truncate-primary))

(defun select-list-filtered-items (list)
  (let ((query
          (string-downcase
           (select-list-query list))))
    (if (zerop (length query))
        (copy-list (select-list-items list))
        (remove-if-not
         (lambda (item)
           (let ((value
                   (select-item-value item)))
             (string-prefix-p
              query
              (string-downcase
               (cond
                 ((stringp value) value)
                 ((symbolp value)
                  (symbol-name value))
                 (t
                  (select-item-label item)))))))
         (select-list-items list)))))

(defun clamp-select-index (list)
  (let ((count
          (length
           (select-list-filtered-items list))))
    (setf (select-list-selected list)
          (if (zerop count)
              0
              (min (select-list-selected list)
                   (1- count))))))

(defun move-select-index (list delta)
  (let ((count
          (length
           (select-list-filtered-items list))))
    (setf (select-list-selected list)
          (if (zerop count)
              0
              (mod (+ (select-list-selected list)
                      delta)
                   count)))))

(defun select-list-handle-event (list event)
  (let ((kind (input-event-kind event)))
    (case kind
      (:text
       (setf
        (select-list-query list)
        (concatenate 'string
                     (select-list-query list)
                     (or (input-event-text event) ""))
        (select-list-selected list) 0))
      (:backspace
       (let ((query (select-list-query list)))
         (when (> (length query) 0)
           (setf
            (select-list-query list)
            (subseq
             query 0
             (previous-cluster-boundary
              query (length query)))
            (select-list-selected list) 0))))
      (:up
       (move-select-index list -1))
      (:down
       (move-select-index list 1))
      (:page-up
       (move-select-index
        list (- (select-list-height list))))
      (:page-down
       (move-select-index
        list (select-list-height list)))
      (:escape
       (return-from select-list-handle-event
         (values :cancel nil)))
      (:enter
       (clamp-select-index list)
       (let ((item
               (nth (select-list-selected list)
                    (select-list-filtered-items list))))
         (when item
           (return-from select-list-handle-event
             (values :select
                     (select-item-value item)))))))
    (values nil nil)))

(defun render-select-list
    (list width &key (ansi-theme-p nil))
  (let* ((items (select-list-filtered-items list))
         (count (length items))
         (selected
           (if (zerop count)
               0
               (min (select-list-selected list)
                    (1- count))))
         (height (select-list-height list))
         (start
           (max
            0
            (min
             (- selected
                (floor height 2))
             (- count height))))
         (end
           (min count (+ start height)))
         (minimum
           (min
            (select-list-min-primary-column-width
             list)
            (select-list-max-primary-column-width
             list)))
         (maximum
           (max
            (select-list-min-primary-column-width
             list)
            (select-list-max-primary-column-width
             list)))
         (widest
           (loop for item in items
                 maximize
                 (+ 2
                    (visible-width
                     (select-item-label item)))))
         (primary-width
           (max minimum
                (min maximum widest))))
    (labels
        ((normalize-description (description)
           (when description
             (string-trim
              '(#\Space #\Tab)
              (cl-ppcre:regex-replace-all
               "[\\r\\n]+" description " "))))
         (primary (item selected-p max-width)
           (let* ((label (select-item-label item))
                  (custom
                    (select-list-truncate-primary list))
                  (value
                    (if custom
                        (funcall
                         custom label max-width
                         primary-width item selected-p)
                        (truncate-to-width
                         label max-width ""))))
             (truncate-to-width value max-width "")))
         (render-item (item index)
           (let* ((selected-p (= index selected))
                  (prefix
                    (if selected-p "→ " "  "))
                  (prefix-width (visible-width prefix))
                  (description
                    (normalize-description
                     (select-item-description item))))
             (if (and description (> width 40))
                 (let* ((effective
                          (max
                           1
                           (min primary-width
                                (- width
                                   prefix-width 4))))
                        (maximum-primary
                          (max 1 (- effective 2)))
                        (label
                          (primary
                           item selected-p
                           maximum-primary))
                        (label-width
                          (visible-width label))
                        (spacing
                          (make-string
                           (max 1
                                (- effective label-width))
                           :initial-element #\Space))
                        (remaining
                          (- width prefix-width
                             label-width
                             (length spacing) 2)))
                   (if (> remaining 10)
                       (let ((line
                               (concatenate
                                'string
                                prefix label spacing
                                (truncate-to-width
                                 description
                                 remaining ""))))
                         (if selected-p
                             (theme-foreground
                              :accent line
                              :enabled-p
                              ansi-theme-p)
                             (concatenate
                              'string
                              prefix label
                              (theme-foreground
                               :muted
                               (concatenate
                                'string spacing
                                (truncate-to-width
                                 description
                                 remaining ""))
                               :enabled-p
                               ansi-theme-p))))
                       (let ((line
                               (concatenate
                                'string prefix
                                (primary
                                 item selected-p
                                 (- width
                                    prefix-width
                                    2)))))
                         (if selected-p
                             (theme-foreground
                              :accent line
                              :enabled-p
                              ansi-theme-p)
                             line))))
                 (concatenate
                  'string
                  (if selected-p
                      (theme-foreground
                       :accent
                       (concatenate
                        'string prefix
                        (primary
                         item selected-p
                         (max
                          1
                          (- width
                             prefix-width 2))))
                       :enabled-p ansi-theme-p)
                      (concatenate
                       'string prefix
                       (primary
                        item selected-p
                        (max
                         1
                         (- width
                            prefix-width 2))))))))))
      (nconc
       (when (select-list-show-filter-p list)
         (list
          (theme-foreground
           :muted
           (fit-status
            (format nil "filter: ~A"
                    (select-list-query list))
            width)
           :enabled-p ansi-theme-p)))
       (if (zerop count)
           (list
            (theme-foreground
             :muted "  No matching commands"
             :enabled-p ansi-theme-p))
           (nconc
            (loop for item in
                  (subseq items start end)
                  for index from start
                  collect
                  (render-item item index))
            (when
                (or (plusp start)
                    (< end count))
              (list
               (theme-foreground
                :muted
                (truncate-to-width
                 (format nil "  (~D/~D)"
                         (1+ selected)
                         count)
                 (max 1 (- width 2))
                 "")
                :enabled-p
                ansi-theme-p)))))))))
