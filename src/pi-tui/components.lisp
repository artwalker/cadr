(in-package #:pi-tui)

(defun trim-markdown-prefix (line character)
  (string-left-trim
   (list #\Space character)
   line))

(defun markdown-line (line in-code-p)
  (cond
    ((string-prefix-p "```" line)
     (values "" (not in-code-p) t))
    (in-code-p
     (values (concatenate 'string "  " line)
             in-code-p nil))
    ((and (> (length line) 0)
          (char= (char line 0) #\#))
     (values
      (trim-markdown-prefix line #\#)
      in-code-p nil))
    ((or (string-prefix-p "- " line)
         (string-prefix-p "* " line))
     (values
      (concatenate 'string "• " (subseq line 2))
      in-code-p nil))
    ((string-prefix-p "> " line)
     (values
      (concatenate 'string "│ " (subseq line 2))
      in-code-p nil))
    (t
     (values line in-code-p nil))))

(defun render-inline-markdown (line)
  (with-output-to-string (output)
    (loop with index = 0
          while (< index (length line))
          do
          (cond
            ((and
              (<= (+ index 2) (length line))
              (string= "**" line
                       :start2 index
                       :end2 (+ index 2)))
             (let ((end
                     (search "**" line
                             :start2 (+ index 2))))
               (if end
                   (progn
                     (write-string
                      line output
                      :start (+ index 2)
                      :end end)
                     (setf index (+ end 2)))
                   (progn
                     (write-char
                      (char line index)
                      output)
                     (incf index)))))
            ((char= (char line index) #\`)
             (let ((end
                     (position #\` line
                               :start
                               (1+ index))))
               (if end
                   (progn
                     (write-string
                      line output
                      :start (1+ index)
                      :end end)
                     (setf index (1+ end)))
                   (progn
                     (write-char #\` output)
                     (incf index)))))
            (t
             (write-char
              (char line index)
              output)
             (incf index))))))

(defun render-markdown (text width)
  (let ((in-code-p nil)
        (result nil))
    (dolist (line (split-lines-preserving-empty text))
      (let ((was-code-p in-code-p))
        (multiple-value-bind
              (rendered next-code-p fence-p)
            (markdown-line line in-code-p)
          (setf in-code-p next-code-p)
          (unless fence-p
            (setf result
                  (nconc
                   result
                   (wrap-logical-line
                    (if was-code-p
                        rendered
                        (render-inline-markdown
                         rendered))
                    width)))))))
    (or result (list ""))))

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
  value)

(defstruct (select-list
            (:constructor %make-select-list))
  (items nil :type list)
  (query "" :type string)
  (selected 0 :type (integer 0 *))
  (height 8 :type (integer 1 *)))

(defun make-select-list (&key items (height 8))
  (%make-select-list
   :items (copy-list items)
   :height height))

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
                   (1- height)))))
    (nconc
     (list
      (fit-status
       (format nil "filter: ~A"
               (select-list-query list))
       width))
     (if (zerop count)
         (list "(no matches)")
         (loop for item in
               (subseq items
                       start
                       (min count (+ start height)))
               for index from start
               collect
               (fit-status
                (format nil "~A ~A"
                        (if (= index selected) "›" " ")
                        (select-item-label item))
                width))))))
