(in-package #:cadr-tui)

(defparameter +search-whitespace-characters+
  '(#\Space #\Tab #\Newline #\Return #\Page))

;;; Baseline v0.84.2 tui/alt-screen-search.ts: transcript search for the
;;; fullscreen viewport — a whitespace-normalizing matcher over the
;;; grapheme-mapped document, plus the overlay bar's presentation.

(defstruct (search-source-span
            (:constructor make-search-source-span
                (row start-col end-col)))
  (row 0 :type (integer 0 *))
  (start-col 0 :type (integer 0 *))
  (end-col 0 :type (integer 0 *)))

(defstruct (search-match
            (:constructor make-search-match (segments)))
  (segments nil :type list))

;;; Search session state (baseline ActiveSearch): held on the renderer
;;; while the find bar is open.

(defstruct (alt-search-state
            (:constructor make-alt-search-state (anchor-row)))
  (query "" :type string)
  (matches nil :type list)
  (selected-index -1 :type integer)
  selected-key
  (anchor-row 0 :type (integer 0 *))
  ;; :query | :retain | :next | :previous
  (selection-mode :query :type symbol))

(defun build-search-corpus (lines)
  ;; Returns (values text source), where SOURCE maps every character
  ;; index in TEXT to its search-source-span (nil for synthesized
  ;; whitespace separators).
  (let ((text (make-string-output-stream))
        (source nil)
        (corpus-length 0)
        (pending-separator-p nil))
    (flet ((append-mapped (chunk span)
             (loop for index below (length chunk)
                   do (push span source))
             (incf corpus-length (length chunk))
             (write-string chunk text)))
      (loop for line in lines
            for row from 0
            do (let ((column 0))
                 (dolist (cluster
                          (grapheme-clusters
                           (strip-terminal-sequences line)))
                   (let ((cluster-width (visible-width cluster)))
                     (if (and (plusp (length cluster))
                              (every (lambda (c)
                                       (member c +search-whitespace-characters+))
                                     cluster))
                         (progn
                           (when (plusp corpus-length)
                             (setf pending-separator-p t))
                           (incf column cluster-width))
                         (progn
                           (when pending-separator-p
                             (append-mapped " " nil)
                             (setf pending-separator-p nil))
                           (append-mapped
                            cluster
                            (make-search-source-span
                             row column
                             (+ column cluster-width)))
                           (incf column cluster-width)))))
                 (when (plusp corpus-length)
                   (setf pending-separator-p t)))))
    (values (get-output-stream-string text)
            (coerce (nreverse source) 'vector))))

(defun normalize-search-query (query)
  (string-trim
   '(#\Space #\Tab #\Newline #\Return #\Page)
   (with-output-to-string (out)
     (let ((pending nil))
       (loop for character across query
             do (if (member character
                            +search-whitespace-characters+)
                    (setf pending t)
                    (progn
                      (when pending
                        (write-char #\Space out))
                      (setf pending nil)
                      (write-char character out))))))))

(defun find-alt-screen-search-matches (lines query)
  ;; Case-insensitive literal search over the corpus; matches map back
  ;; to merged per-row segments.
  (let ((normalized (normalize-search-query query)))
    (when (zerop (length normalized))
      (return-from find-alt-screen-search-matches nil))
    (multiple-value-bind (text source)
        (build-search-corpus lines)
      (let ((matches nil)
            (position 0))
        (loop
          (let ((start
                  (search normalized text
                          :start2 position
                          :test #'char-equal)))
            (unless start (return))
            (let ((end (+ start (length normalized)))
                  (segments nil))
              (loop for index from start below end
                    for span = (aref source index)
                    when span
                      do (let ((previous (first segments)))
                           (if (and previous
                                    (= (search-source-span-row previous)
                                       (search-source-span-row span))
                                    (<= (search-source-span-start-col span)
                                        (search-source-span-end-col previous)))
                               (setf (search-source-span-end-col previous)
                                     (max (search-source-span-end-col previous)
                                          (search-source-span-end-col span)))
                               (push
                                (make-search-source-span
                                 (search-source-span-row span)
                                 (search-source-span-start-col span)
                                 (search-source-span-end-col span))
                                segments))))
              (when segments
                (push (make-search-match (nreverse segments)) matches))
              (setf position (max (1+ start) end)))))
        (nreverse matches)))))

(defun search-match-key (match)
  (let ((first (first (search-match-segments match)))
        (last (car (last (search-match-segments match)))))
    (format nil "~D:~D:~D:~D"
            (search-source-span-row first)
            (search-source-span-start-col first)
            (search-source-span-row last)
            (search-source-span-end-col last))))

;;; Search bar presentation (baseline AltScreenSearchComponent.render):
;;; an inverse title row (" Find transcript" + right-aligned status)
;;; and the query row.

(defun render-search-bar (query width result-index result-count)
  (let* ((safe-width (max 1 width))
         (label " Find transcript")
         (status
           (cond
             ((zerop (length query)) "")
             ((zerop result-count) "No matches ")
             (t (format nil "~D/~D " (1+ result-index) result-count))))
         (gap
           (make-string
            (max 1 (- safe-width
                      (visible-width label)
                      (visible-width status)))
            :initial-element #\Space))
         (title
           (truncate-to-width
            (concatenate 'string label gap status)
            safe-width ""))
         (padding
           (make-string
            (max 0 (- safe-width (visible-width title)))
            :initial-element #\Space))
         (query-line
           (truncate-to-width query safe-width ""))
         (query-padding
           (make-string
            (max 0 (- safe-width (visible-width query-line)))
            :initial-element #\Space)))
    (list
     (concatenate
      'string (format nil "~C[7m" #\Escape) title padding
      (format nil "~C[27m" #\Escape))
     (concatenate
      'string query-line
      (format nil "~C[7m ~C[27m" #\Escape #\Escape)
      query-padding))))
