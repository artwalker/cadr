(in-package #:cadr-tui)

(defstruct (tool-block
            (:constructor %make-tool-block))
  (name "" :type string)
  (summary "" :type string)
  (header-segments nil :type list)
  (output "" :type string)
  output-token
  source-language
  syntax-highlight-function
  (expand-key-text "ctrl+o" :type string)
  (supplemental-lines nil :type list)
  (status :running :type symbol)
  preview-status
  (collapsed-p nil :type boolean)
  started-at
  ended-at)

(defun make-tool-block (&key (name "") (summary "")
                             header-segments
                             (output "") output-token
                             source-language
                             syntax-highlight-function
                             (expand-key-text "ctrl+o")
                             supplemental-lines
                             (status :running) preview-status
                             started-at ended-at
                             (collapsed-p nil
                              collapsed-p-supplied-p))
  (%make-tool-block
   :name name
   :summary summary
   :header-segments (copy-tree header-segments)
   :output output
   :output-token output-token
   :source-language source-language
   :syntax-highlight-function syntax-highlight-function
   :expand-key-text expand-key-text
   :supplemental-lines (copy-list supplemental-lines)
   :status status
   :preview-status preview-status
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

(defun tool-status-theme-tokens (block)
  (case (or (tool-block-preview-status block)
            (tool-block-status block))
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

(defun tool-output-line-token (block)
  (or
   (tool-block-output-token block)
   (and
    (eq (tool-block-status block) :error)
    (member (string-downcase (tool-block-name block))
            '("write" "edit") :test #'string=)
    :error)
   :tool-output))

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
  (let* ((normalized
           (normalize-tool-output
            (tool-block-output block)))
         (highlighted
           (if (and
                (tool-block-source-language block)
                (tool-block-syntax-highlight-function block)
                (not (eq (tool-block-status block) :error)))
               (funcall
                (tool-block-syntax-highlight-function block)
                (tool-block-source-language block)
                normalized)
               normalized))
         (lines
           (trim-trailing-empty-lines
            (split-lines-preserving-empty highlighted)))
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
        (if (and
             (tool-block-source-language block)
             (tool-block-syntax-highlight-function block)
             (not (eq (tool-block-status block) :error)))
            lines
            (loop for line in lines
                  collect
                  (theme-foreground
                   (tool-output-line-token block)
                   line :enabled-p ansi-theme-p))))))

(defun render-tool-header-segment (segment ansi-theme-p)
  (let* ((text (or (getf segment :text) ""))
         (bold
           (if (getf segment :bold-p)
               (theme-bold text :enabled-p ansi-theme-p)
               text))
         (styled
           (if (getf segment :token)
               (theme-foreground
                (getf segment :token) bold
                :enabled-p ansi-theme-p)
               bold))
         (url (getf segment :url)))
    (if (and url
             (terminal-capabilities-hyperlinks-p
              (get-terminal-capabilities)))
        (terminal-hyperlink styled url)
        styled)))

(defun style-default-tool-header-parts
    (text suffix-regex main-token suffix-token ansi-theme-p
     &key bold-main-p prefix)
  (multiple-value-bind (start end)
      (cl-ppcre:scan suffix-regex text)
    (declare (ignore end))
    (let* ((split (or start (length text)))
           (main
             (concatenate
              'string (or prefix "")
              (subseq text 0 split)))
           (suffix (subseq text split)))
      (concatenate
       'string
       (theme-foreground
        main-token
        (if bold-main-p
            (theme-bold main :enabled-p ansi-theme-p)
            main)
        :enabled-p ansi-theme-p)
       (if (plusp (length suffix))
           (theme-foreground
            suffix-token suffix :enabled-p ansi-theme-p)
           "")))))

(defun render-default-tool-header
    (block status-token indicator ansi-theme-p)
  (let* ((name (tool-block-name block))
         (summary (tool-block-summary block))
         (indicator-text
           (and
            indicator
            (theme-foreground
             status-token indicator :enabled-p ansi-theme-p))))
    (if (string-equal name "bash")
        (format
         nil "~@[~A ~]~A"
         indicator-text
         (style-default-tool-header-parts
          summary
          " \\(timeout [0-9]+(?:\\.[0-9]+)?s\\)$"
          :tool-title :muted ansi-theme-p
          :bold-main-p t :prefix "$ "))
        (format
         nil "~@[~A ~]~A~@[ ~A~]"
         indicator-text
         (theme-foreground
          :tool-title
          (theme-bold name :enabled-p ansi-theme-p)
          :enabled-p ansi-theme-p)
         (and
          (plusp (length summary))
          (if (string-equal name "read")
              (style-default-tool-header-parts
               summary ":[0-9]+(?:-[0-9]+)?$"
               :accent :warning ansi-theme-p)
              (theme-foreground
               :accent summary :enabled-p ansi-theme-p)))))))

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
           (concatenate
            'string
            (theme-foreground
             :muted
             (format nil "... (~D earlier lines," skipped)
             :enabled-p ansi-theme-p)
            " "
            (theme-foreground
             :dim
             (tool-block-expand-key-text block)
             :enabled-p ansi-theme-p)
            (theme-foreground
             :muted " to expand)"
             :enabled-p ansi-theme-p))
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
                   "... (~D more lines, ~A to expand)"
                   (- (length visual-lines) budget)
                   (tool-block-expand-key-text block))
           :enabled-p ansi-theme-p)
          content-width "...")))))))

(defun render-tool-block
    (block width &key (ansi-theme-p nil) now)
  (multiple-value-bind
        (status-token background-token indicator)
      (tool-status-theme-tokens
       block)
    (let* ((content-width (max 1 (- width 2)))
           (header
             (if (tool-block-header-segments block)
                 (format
                  nil "~{~A~}"
                  (mapcar
                   (lambda (segment)
                     (render-tool-header-segment
                      segment ansi-theme-p))
                   (tool-block-header-segments block)))
                 (render-default-tool-header
                  block status-token indicator ansi-theme-p)))
           (header-lines
             (wrap-text
              (cl-ppcre:regex-replace-all
               (string #\Tab) header "   ")
              content-width))
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
              (and output-lines
                   (cons "" output-lines))
              (and (tool-block-supplemental-lines block)
                   (cons
                    ""
                    (loop for line in
                          (tool-block-supplemental-lines block)
                          nconc
                          (wrap-logical-line
                           (theme-foreground
                            :warning line
                            :enabled-p ansi-theme-p)
                           content-width))))
              (and timing-line
                   (list "" timing-line))
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
