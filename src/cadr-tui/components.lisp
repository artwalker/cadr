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
            (if (string= label url)
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
    (line ansi-theme-p capabilities)
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
    result))

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

(defun markdown-table-row-line
    (cells widths ansi-theme-p header-p
     capabilities)
  (let ((border
          (lambda (text)
            (theme-foreground
             :border-muted text
             :enabled-p ansi-theme-p))))
    (with-output-to-string (stream)
      (write-string (funcall border "│")
                    stream)
      (loop for width in widths
            for index from 0
            for cell = (or (nth index cells) "")
            for rendered =
              (render-inline-markdown
               (truncate-to-width
                cell width "" nil)
               ansi-theme-p capabilities)
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
             stream)))))

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
     ansi-theme-p capabilities)
  (let ((widths
          (markdown-table-widths
           rows available-width)))
    (append
     (list
      (markdown-table-border-line
       #\┌ #\┬ #\┐ widths
       ansi-theme-p)
      (markdown-table-row-line
       (first rows) widths ansi-theme-p
       t capabilities)
      (markdown-table-border-line
       #\├ #\┼ #\┤ widths
       ansi-theme-p))
     (loop for row in (rest rows)
           collect
           (markdown-table-row-line
            row widths ansi-theme-p
            nil capabilities))
     (list
      (markdown-table-border-line
       #\└ #\┴ #\┘ widths
       ansi-theme-p)))))

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

(defun markdown-line
    (line in-code-p ansi-theme-p
     capabilities available-width)
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
            (styled
              (theme-foreground
               :md-heading
               (if (= level 1)
                   (theme-underline
                    (theme-bold
                     text
                     :enabled-p ansi-theme-p)
                    :enabled-p ansi-theme-p)
                   (if (= level 2)
                       (theme-bold
                        text
                        :enabled-p ansi-theme-p)
                       text))
               :enabled-p ansi-theme-p)))
       (values styled in-code-p nil)))
    ((or (string-prefix-p "- " line)
         (string-prefix-p "* " line)
         (string-prefix-p "+ " line))
     (values
      (concatenate
       'string
       (theme-foreground
        :md-list-bullet "•"
        :enabled-p ansi-theme-p)
       " "
       (render-inline-markdown
        (subseq line 2)
        ansi-theme-p capabilities))
      in-code-p nil))
    ((markdown-ordered-prefix-end line)
     (values
      (render-inline-markdown
       line ansi-theme-p capabilities)
      in-code-p nil))
    ((string-prefix-p "> " line)
     (values
      (concatenate
       'string
       (theme-foreground
        :md-quote-border "│"
        :enabled-p ansi-theme-p)
       " "
       (theme-foreground
        :md-quote
        (theme-italic
         (render-inline-markdown
          (subseq line 2)
          ansi-theme-p capabilities)
         :enabled-p ansi-theme-p)
        :enabled-p ansi-theme-p))
      in-code-p nil))
    (t
     (values
      (render-inline-markdown
       line ansi-theme-p capabilities)
      in-code-p nil))))

(defun render-markdown
    (text width &key ansi-theme-p
                     transform-function
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
        (result nil))
    (let ((source-lines
            (split-lines-preserving-empty text)))
      (loop while source-lines
            for line = (pop source-lines)
            for next = (first source-lines)
            do
            (if
                (and
                 (not in-code-p)
                 (find #\| line)
                 next
                 (markdown-table-divider-p next))
                (let ((rows
                        (list
                         (markdown-table-cells
                          line))))
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
                        (setf rows
                              (nconc
                               rows
                               (list
                                (markdown-table-cells
                                 (pop
                                  source-lines))))))
                  (setf result
                        (nconc
                         result
                         (render-markdown-table
                          rows available-width
                          ansi-theme-p
                          capabilities))))
                (multiple-value-bind
                      (rendered next-code-p skip-p)
                    (markdown-line
                     line in-code-p ansi-theme-p
                     capabilities available-width)
                  (setf in-code-p next-code-p)
                  (unless skip-p
                    (setf result
                          (nconc
                           result
                           (wrap-text
                            rendered
                            available-width))))))))
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
  (collapsed-p nil :type boolean))

(defun make-tool-block (&key (name "") (summary "")
                             (output "") (status :running)
                             collapsed-p)
  (%make-tool-block
   :name name
   :summary summary
   :output output
   :status status
   :collapsed-p
   (if (null collapsed-p)
       (eq status :complete)
       collapsed-p)))

(defun toggle-tool-block (block)
  (setf (tool-block-collapsed-p block)
        (not (tool-block-collapsed-p block)))
  block)

(defun tool-status-theme-tokens (status)
  (case status
    (:running
     (values :accent
             :tool-pending-bg "…"))
    (:error
     (values :error
             :tool-error-bg "×"))
    (otherwise
     (values :success
             :tool-success-bg "✓"))))

(defun render-tool-block
    (block width &key (ansi-theme-p nil))
  (multiple-value-bind
        (status-token background-token indicator)
      (tool-status-theme-tokens
       (tool-block-status block))
    (let* ((content-width (max 1 (- width 2)))
           (header
             (format
              nil "~A ~A~@[ ~A~]"
              (theme-foreground
               status-token indicator
               :enabled-p ansi-theme-p)
              (theme-foreground
               :tool-title
               (theme-bold
                (tool-block-name block)
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
                 (or
                  (tool-block-collapsed-p block)
                  (zerop
                   (length
                    (tool-block-output block))))
               (loop for line in
                     (wrap-text
                      (tool-block-output block)
                      content-width)
                     collect
                     (theme-foreground
                      :tool-output line
                      :enabled-p ansi-theme-p))))
           (box-lines
             (append
              (list "")
              header-lines
              output-lines
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
             (round count 1000)))
    ((< count 10000000)
     (format nil "~,1FM"
             (/ count 1000000d0)))
    (t
     (format nil "~DM"
             (round count 1000000)))))

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
               width "..." nil)))
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
              (mod (select-list-selected list) count)))))

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
       (decf (select-list-selected list))
       (clamp-select-index list))
      (:down
       (incf (select-list-selected list))
       (clamp-select-index list))
      (:page-up
       (decf (select-list-selected list)
             (select-list-height list))
       (clamp-select-index list))
      (:page-down
       (incf (select-list-selected list)
             (select-list-height list))
       (clamp-select-index list))
      (:escape
       (return-from select-list-handle-event
         (values :cancel nil)))
      (:enter
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
