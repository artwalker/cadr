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
    (text marker &key open-code ansi-theme-p)
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
          (ansi-style
           open-code
           (subseq text
                   (+ start (length marker))
                   end)
           ansi-theme-p))
         position (+ end (length marker)))
        finally
        (return
          (concatenate 'string result
                       (subseq text position)))))

(defun markdown-link-replacement
    (label url image-p capabilities)
  (if image-p
      (format nil "Image: ~A (~A)" label url)
      (if (terminal-capabilities-hyperlinks-p
           capabilities)
          (terminal-hyperlink label url)
          (format nil "~A (~A)" label url))))

(defun replace-markdown-links (text capabilities)
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
                          image-p capabilities)
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
           line capabilities)))
    (setf result
          (replace-paired-marker
           result "**" :open-code "1"
           :ansi-theme-p ansi-theme-p)
          result
          (replace-paired-marker
           result "__" :open-code "1"
           :ansi-theme-p ansi-theme-p)
          result
          (replace-paired-marker
           result "~~" :open-code "9"
           :ansi-theme-p ansi-theme-p)
          result
          (replace-paired-marker
           result "`" :open-code "36"
           :ansi-theme-p ansi-theme-p))
    (unless (search "**" result)
      (setf
       result
       (replace-paired-marker
        result "*" :open-code "3"
        :ansi-theme-p ansi-theme-p)))
    (unless (search "__" result)
      (setf
       result
       (replace-paired-marker
        result "_" :open-code "3"
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

(defun markdown-table-line (line)
  (let* ((parts
           (uiop:split-string
            line :separator '(#\|)))
         (parts
           (remove-if
            (lambda (part)
              (zerop
               (length
                (string-trim
                 '(#\Space #\Tab) part))))
            parts)))
    (format nil "│ ~{~A~^ │ ~} │"
            (mapcar
             (lambda (part)
               (string-trim
                '(#\Space #\Tab) part))
             parts))))

(defun markdown-ordered-prefix-end (line)
  (let ((dot (position #\. line)))
    (when (and dot (plusp dot)
               (< (1+ dot) (length line))
               (char= (char line (1+ dot))
                      #\Space)
               (every #'digit-char-p
                      (subseq line 0 dot)))
      (+ dot 2))))

(defun markdown-line
    (line in-code-p ansi-theme-p capabilities)
  (cond
    ((string-prefix-p "```" line)
     (values "" (not in-code-p) t))
    (in-code-p
     (values
      (ansi-style
       "36" (concatenate 'string "  " line)
       ansi-theme-p)
      in-code-p nil))
    ((markdown-horizontal-rule-p line)
     (values
      (make-string 3 :initial-element #\─)
      in-code-p nil))
    ((markdown-table-divider-p line)
     (values "" in-code-p t))
    ((and (> (length line) 0)
          (char= (char line 0) #\#))
     (values
      (ansi-style
       "1" (trim-markdown-prefix line #\#)
       ansi-theme-p)
      in-code-p nil))
    ((or (string-prefix-p "- " line)
         (string-prefix-p "* " line)
         (string-prefix-p "+ " line))
     (values
      (concatenate
       'string "• "
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
       'string "│ "
       (render-inline-markdown
        (subseq line 2)
        ansi-theme-p capabilities))
      in-code-p nil))
    ((find #\| line)
     (values
      (markdown-table-line line)
      in-code-p nil))
    (t
     (values
      (render-inline-markdown
       line ansi-theme-p capabilities)
      in-code-p nil))))

(defun render-markdown
    (text width &key ansi-theme-p
                     (capabilities
                       (get-terminal-capabilities)))
  (let ((in-code-p nil)
        (result nil))
    (dolist (line (split-lines-preserving-empty text))
      (multiple-value-bind
            (rendered next-code-p skip-p)
          (markdown-line
           line in-code-p ansi-theme-p capabilities)
        (setf in-code-p next-code-p)
        (unless skip-p
          (setf result
                (nconc
                 result
                 (wrap-text rendered width))))))
    (or result (list ""))))

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

(defun render-tool-block (block width)
  (let* ((indicator
           (case (tool-block-status block)
             (:running "…")
             (:error "×")
             (otherwise "✓")))
         (header
           (format nil "~A ~A ~A"
                   indicator
                   (tool-block-name block)
                   (tool-block-summary block)))
         (lines (wrap-logical-line header width)))
    (if (or (tool-block-collapsed-p block)
            (zerop (length (tool-block-output block))))
        lines
        (nconc
         lines
         (loop for line in
               (wrap-text (tool-block-output block)
                          (max 1 (- width 2)))
               collect (concatenate 'string "  " line))))))

(defun fit-status (text width)
  (multiple-value-bind (prefix used)
      (slice-to-width text width)
    (concatenate
     'string prefix
     (make-string
      (max 0 (- width used))
      :initial-element #\Space))))

(defun render-status-bar
    (width &key model (input 0) (output 0)
                  (cache 0) cost session)
  (fit-status
   (format nil "~A  in:~D out:~D cache:~D  $~A  session:~A"
           (or model "—")
           input output cache
           (if cost
               (format nil "~,4F" cost)
               "—")
           (or session "—"))
   width))

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
    (&key items (height 8) (show-filter-p t)
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
           (search query
                   (string-downcase
                    (select-item-label item))))
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

(defun render-select-list (list width)
  (let* ((items (select-list-filtered-items list))
         (count (length items))
         (selected
           (if (zerop count)
               0
               (min (select-list-selected list)
                    (1- count))))
         (height (select-list-height list))
         (start
           (max 0
                (- selected
                   (1- height))))
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
                       (concatenate
                        'string prefix label spacing
                        (truncate-to-width
                         description remaining ""))
                       (concatenate
                        'string prefix
                        (primary
                         item selected-p
                         (- width prefix-width 2)))))
                 (concatenate
                  'string prefix
                  (primary
                   item selected-p
                   (max 1
                        (- width prefix-width 2))))))))
      (nconc
       (when (select-list-show-filter-p list)
         (list
          (fit-status
           (format nil "filter: ~A"
                   (select-list-query list))
           width)))
       (if (zerop count)
           (list "(no matches)")
           (loop for item in
                 (subseq items
                         start
                         (min count (+ start height)))
                 for index from start
                 collect (render-item item index)))))))
