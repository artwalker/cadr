(in-package #:cadr-tui)

(defun prepare-alt-line (source width)
  (let ((line (strip-osc133-zone-prefix source)))
    (if
        (or (image-line-p line)
            (<= (visible-width line) width))
        line
        (slice-by-column line 0 width t))))

(defun prepare-alt-document (lines width)
  (loop for source in lines
        collect (prepare-alt-line source width)))

(defun prepare-alt-document-incrementally
    (renderer lines width)
  (let ((old-sources
          (and
           (= width
              (terminal-renderer-prepared-width
               renderer))
           (terminal-renderer-prepared-source-lines
            renderer)))
        (old-document
          (terminal-renderer-prepared-document
           renderer))
        (remaining lines)
        (reused nil)
        (reused-count 0))
    (loop while
          (and remaining old-sources old-document
               (eq (car remaining)
                   (car old-sources)))
          do
          (push (car old-document) reused)
          (incf reused-count)
          (setf remaining (cdr remaining)
                old-sources (cdr old-sources)
                old-document (cdr old-document)))
    (let ((document
            (nconc
             (nreverse reused)
             (prepare-alt-document remaining width))))
      (setf
       (terminal-renderer-prepared-source-lines
        renderer)
       lines
       (terminal-renderer-prepared-document renderer)
       document
       (terminal-renderer-prepared-width renderer)
       width
       (terminal-renderer-prepared-prefix-reused
        renderer)
       reused-count)
      document)))

(defun cropped-image-at-viewport-top
    (document top height)
  (when (plusp top)
    (loop for image-row downfrom (1- top) to 0
          for image-line = (nth image-row document)
          for metadata =
          (get-kitty-image-metadata image-line)
          when metadata
            do
            (let ((hidden-rows (- top image-row)))
              (return
                (and
                 (< hidden-rows
                    (getf metadata :rows))
                 (crop-kitty-image-line
                  image-line
                  hidden-rows
                  (min
                   height
                   (-
                    (getf metadata :rows)
                    hidden-rows))))))
          when
          (plusp
           (length
            (strip-terminal-sequences
             image-line)))
            do (return nil))))

(defun alt-scrollbar-visible-p (renderer content-height height)
  ;; pi@914cf1472 components/scroll-view.ts:62-70 — "always" whenever a
  ;; viewport exists, "hidden" never, "auto" only while overflowing and
  ;; within the one-second hide delay after scroll activity.
  (and (plusp height)
       (case (terminal-renderer-scrollbar-mode renderer)
         (:always t)
         (:hidden nil)
         (otherwise
          (and (> content-height height)
               (let ((at
                       (terminal-renderer-scrollbar-activity-at
                        renderer)))
                 (and at
                      (< (- (/ (get-internal-real-time)
                               (coerce
                                internal-time-units-per-second
                                'double-float))
                            at)
                         1.0d0))))))))

(defun style-alt-scrollbar-cell (line column width)
  ;; pi@914cf1472 layout.ts:242-267 — the last-column cell keeps its
  ;; text and leading SGR; the thumb background wraps only that cell.
  (if (image-line-p line)
      line
      (let* ((before
               (slice-by-column line 0 column t))
             (before-padding
               (make-string
                (max 0 (- column (visible-width before)))
                :initial-element #\Space))
             (target
               (slice-by-column line column 1 t))
             (prefix-end
               (loop with index = 0
                     for end =
                       (ansi-sequence-end target index)
                     while end
                     do (setf index end)
                     finally (return index)))
             (target-prefix (subseq target 0 prefix-end))
             (target-text
               (let ((text (subseq target prefix-end)))
                 (if (plusp (length text))
                     text
                     " ")))
             (after
               (slice-by-column
                line (1+ column)
                (max 0 (- width (1+ column))) t)))
        (concatenate
         'string before before-padding target-prefix
         (theme-background-ansi :scrollbar-thumb :enabled-p t)
         target-text
         (format nil "~C[49m" #\Escape)
         after))))

(defun apply-alt-scrollbar (renderer lines width height)
  ;; pi@914cf1472 layout.ts:268-303 — thumb height is the
  ;; track-proportional share clamped to [min(2, track), track], the
  ;; offset maps scrollTop onto the remaining track.
  (let ((content-height
          (terminal-renderer-content-line-count renderer)))
    (if (alt-scrollbar-visible-p renderer content-height height)
        (let* ((track-height height)
               (min-thumb-height (min 2 track-height))
               (thumb-height
                 (max min-thumb-height
                      (min track-height
                           (round
                            (/ (* track-height track-height)
                               content-height)))))
               (max-scroll-top
                 (max 0 (- content-height track-height)))
               (max-thumb-top
                 (- track-height thumb-height))
               (scroll-top
                 (if (terminal-renderer-stick-to-bottom-p renderer)
                     max-scroll-top
                     (terminal-renderer-scroll-top renderer)))
               (thumb-offset
                 (if (zerop max-scroll-top)
                     0
                     (round
                      (* (/ scroll-top max-scroll-top)
                         max-thumb-top))))
               (column (1- width)))
          (loop for offset below thumb-height
                for row = (+ thumb-offset offset)
                when (and (>= row 0) (< row (length lines)))
                  do (setf
                      (nth row lines)
                      (style-alt-scrollbar-cell
                       (nth row lines) column width)))
          lines)
        lines)))

(defun alt-viewport-lines
    (renderer document height)
  (let* ((top
           (terminal-renderer-scroll-top
            renderer))
         (screen
           (subseq
            document
            (min top (length document))
            (min
             (length document)
             (+ top height))))
         (cropped
           (cropped-image-at-viewport-top
            document top height)))
    (when cropped
      (if screen
          (setf (first screen) cropped)
          (setf screen (list cropped))))
    (nconc
     screen
     (make-list
      (max 0 (- height (length screen)))
      :initial-element ""))))

(defun style-search-match-text (text current-p)
  ;; Baseline interactive-mode.ts createInteractiveTui: themed search
  ;; match styles (underline / bold+inverse over the search colors).
  (let ((colored
          (concatenate
           'string
           (theme-background-ansi :search-match-bg :enabled-p t)
           (theme-foreground-ansi :search-match-text :enabled-p t)
           text
           (format nil "~C[39m" #\Escape)
           (format nil "~C[49m" #\Escape))))
    (if current-p
        (format nil "~C[1;7m~A~C[22;27m" #\Escape colored #\Escape)
        (format nil "~C[4m~A~C[24m" #\Escape colored #\Escape))))

(defun renderer-refresh-search (renderer document height)
  ;; Baseline tui-alt-screen.ts refreshSearch: recompute matches over
  ;; the current document, resolve the selection by mode, and reveal it.
  (let ((search (terminal-renderer-alt-search-state renderer)))
    (when search
      (if (zerop
           (length
            (normalize-search-query
             (alt-search-state-query search))))
          (setf (alt-search-state-matches search) nil
                (alt-search-state-selected-index search) -1
                (alt-search-state-selected-key search) nil
                (alt-search-state-selection-mode search) :retain)
          (let* ((matches
                   (find-alt-screen-search-matches
                    document (alt-search-state-query search)))
                 (mode (alt-search-state-selection-mode search))
                 (key (alt-search-state-selected-key search))
                 (exact
                   (and key
                        (position key matches
                                  :key #'search-match-key
                                  :test #'string=)))
                 (count (length matches))
                 (selected
                   (cond
                     ((zerop count) -1)
                     ((eq mode :query)
                      (or (position-if
                           (lambda (match)
                             (>= (search-source-span-row
                                  (first
                                   (search-match-segments match)))
                                 (alt-search-state-anchor-row search)))
                           matches)
                          0))
                     ((eq mode :next)
                      (let ((base
                              (or exact
                                  (min (alt-search-state-selected-index
                                        search)
                                       (1- count)))))
                        (if (minusp base) 0 (mod (1+ base) count))))
                     ((eq mode :previous)
                      (let ((base
                              (or exact
                                  (min (alt-search-state-selected-index
                                        search)
                                       (1- count)))))
                        (if (minusp base)
                            (1- count)
                            (mod (1- base) count))))
                     (t
                      (or exact
                          (min (max 0
                                    (alt-search-state-selected-index
                                     search))
                               (1- count)))))))
            (setf (alt-search-state-matches search) matches
                  (alt-search-state-selected-index search) selected
                  (alt-search-state-selected-key search)
                  (and (>= selected 0)
                       (search-match-key (nth selected matches)))
                  (alt-search-state-selection-mode search) :retain)
            (when (and (not (eq mode :retain)) (>= selected 0))
              (let* ((match (nth selected matches))
                     (first-seg
                       (first (search-match-segments match)))
                     (last-seg
                       (car (last (search-match-segments match))))
                     (before (terminal-renderer-scroll-top renderer))
                     (visible-bottom (+ before height -1)))
                (when (or (< (search-source-span-row first-seg) before)
                          (> (search-source-span-row last-seg)
                             visible-bottom))
                  (setf (terminal-renderer-stick-to-bottom-p renderer)
                        nil)
                  (setf (terminal-renderer-scroll-top renderer)
                        (max 0
                             (min (- (search-source-span-row first-seg)
                                     (floor height 3))
                                  (max 0
                                       (- (length document)
                                          height)))))))))))))

(defun apply-search-highlights (renderer lines)
  ;; Baseline tui-alt-screen.ts applySearchHighlights: style the match
  ;; ranges visible in the viewport slice.
  (let ((search (terminal-renderer-alt-search-state renderer)))
    (if (or (null search)
            (minusp (alt-search-state-selected-index search))
            (null (alt-search-state-matches search)))
        lines
        (let ((top (terminal-renderer-scroll-top renderer))
              (selected (alt-search-state-selected-index search)))
          (loop for line in lines
                for viewport-row from 0
                collect
                (if (image-line-p line)
                    line
                    (let ((ranges nil))
                      (loop for match
                              in (alt-search-state-matches search)
                            for match-index from 0
                            do (dolist (segment
                                        (search-match-segments match))
                                 (when (= (search-source-span-row segment)
                                          (+ top viewport-row))
                                   (push (list
                                          (search-source-span-start-col
                                           segment)
                                          (search-source-span-end-col
                                           segment)
                                          (= match-index selected))
                                         ranges))))
                      (if (null ranges)
                          line
                          (let ((width (visible-width line)))
                            (dolist (range
                                     (sort ranges #'> :key #'first))
                              (destructuring-bind
                                  (start-col end-col current-p) range
                                (let ((start (min start-col width))
                                      (end (min end-col width)))
                                  (when (> end start)
                                    (setf line
                                          (concatenate
                                           'string
                                           (slice-by-column
                                            line 0 start t)
                                           (style-search-match-text
                                            (slice-by-column
                                             line start
                                             (- end start) t)
                                            current-p)
                                           (slice-by-column
                                            line end
                                            (max 0 (- width end))
                                            t)))))))
                            line)))))))))

(defun overlay-search-bar (renderer lines width)
  ;; The find bar docks at the top right (baseline: 40% width, at least
  ;; 24 columns, one column of margin).
  (let ((search (terminal-renderer-alt-search-state renderer)))
    (if (null search)
        lines
        (let* ((bar-width (max 24 (floor (* width 2) 5)))
               (bar
                 (render-search-bar
                  (alt-search-state-query search) bar-width
                  (alt-search-state-selected-index search)
                  (length (alt-search-state-matches search))))
               (left-edge (max 0 (- width bar-width 1))))
          (loop for line in lines
                for row from 0
                collect
                (if (< row (length bar))
                    (concatenate
                     'string
                     (slice-by-column line 0 left-edge t)
                     (nth row bar)
                     (slice-by-column
                      line (+ left-edge bar-width)
                      (max 0 (- width left-edge bar-width)) t))
                    line))))))

(defun render-alt-frame
    (renderer lines &key
                      (cursor-row
                        (max 0 (1- (length lines))))
                      (cursor-column 0))
  (let* ((terminal
           (terminal-renderer-terminal renderer))
         (width
           (max 1 (terminal-columns terminal)))
         (height
           (max 1 (terminal-rows terminal)))
         (document
           (prepare-alt-document-incrementally
            renderer lines width))
         (maximum-top
           (max 0 (- (length document) height))))
    (setf
     (terminal-renderer-content-line-count
      renderer)
     (length document)
     (terminal-renderer-last-document renderer)
     (coerce document 'simple-vector))
    (if
        (terminal-renderer-stick-to-bottom-p
         renderer)
        (setf
         (terminal-renderer-scroll-top renderer)
         maximum-top)
        (progn
          (setf
           (terminal-renderer-scroll-top renderer)
           (max
            0
            (min
             (terminal-renderer-scroll-top
              renderer)
             maximum-top)))
          (when
              (=
               (terminal-renderer-scroll-top
                renderer)
               maximum-top)
            (setf
             (terminal-renderer-stick-to-bottom-p
              renderer)
             t))))
    (when (terminal-renderer-alt-search-state renderer)
      (renderer-refresh-search renderer document height))
    (let* ((selected
             (apply-search-highlights
              renderer
              (apply-renderer-selection
               renderer
               (alt-viewport-lines
                renderer document height))))
           (selected
             ;; pi@914cf1472 tui-alt-screen.ts:969-981
             ;; compositeFlashes: surviving flash lines overlay the
             ;; top rows, right-aligned.
             (let ((flash-lines
                     (renderer-live-flash-lines renderer width)))
               (if (null flash-lines)
                   selected
                   (loop for line in selected
                         for row from 0
                         collect
                         (if (< row (length flash-lines))
                             (let* ((flash
                                      (nth row flash-lines))
                                    (flash-width
                                      (visible-width flash)))
                               (if (zerop flash-width)
                                   line
                                   (concatenate
                                    'string
                                    (slice-by-column
                                     line 0
                                     (max 0
                                          (- width flash-width))
                                     t)
                                    flash)))
                             line)))))
           (current
             (loop for line in selected
                   collect
                   (if
                       (or
                        (image-line-p line)
                        (<= (visible-width line)
                            width))
                       line
                       (slice-by-column
                        line 0 width t))))
           (current
             (overlay-search-bar renderer current width))
          (current
            (apply-alt-scrollbar
             renderer current width height))
           (previous
             (terminal-renderer-previous-lines
              renderer))
           (full-p
             (or
              (terminal-renderer-invalid-p
               renderer)
              (null previous)
              (/=
               width
               (terminal-renderer-previous-width
                renderer))
              (/=
               height
               (terminal-renderer-previous-height
                renderer))))
           (image-change-p
             (frame-image-change-p
              current previous))
           (visible-cursor-row
             (and cursor-row
                  (- cursor-row
                     (terminal-renderer-scroll-top
                      renderer))))
           (cursor-visible-p
             (and visible-cursor-row cursor-column
              (>= visible-cursor-row 0)
              (< visible-cursor-row height)))
           (output
             (with-output-to-string (stream)
               (write-string +synchronized-update-begin+ stream)
               (cond
                 (full-p
                  (when
                      (eq
                       :kitty
                       (terminal-renderer-image-protocol
                        renderer))
                    (write-string
                     (delete-all-kitty-images)
                     stream))
                  (format stream "~C[2J"
                          #\Escape))
                 (image-change-p
                  (if
                      (eq
                       :iterm2
                       (terminal-renderer-image-protocol
                        renderer))
                      (format stream "~C[2J"
                              #\Escape)
                      (when
                          (eq
                           :kitty
                           (terminal-renderer-image-protocol
                            renderer))
                        (write-string
                         (delete-all-kitty-images)
                         stream)))))
               (loop for row below height
                     for new-tail = current then (cdr new-tail)
                     for old-tail = previous then (cdr old-tail)
                     for new = (if new-tail (car new-tail) "")
                     for old = (and old-tail (car old-tail))
                     when
                     (or
                      full-p
                      image-change-p
                      (null old)
                      (not (string= new old)))
                       do
                       (render-frame-line
                        stream current row new))
               (if cursor-visible-p
                   (progn
                     (ansi-position
                      stream
                      visible-cursor-row
                      (min
                       (max 0 cursor-column)
                       (1- width)))
                     (format stream "~C[?25~C"
                             #\Escape
                             (if
                                 (terminal-renderer-show-hardware-cursor-p
                                  renderer)
                                 #\h
                                 #\l)))
                   (format stream "~C[?25l"
                           #\Escape))
               (write-string +synchronized-update-end+ stream))))
      (terminal-write terminal output)
      (setf
       (terminal-renderer-previous-lines renderer)
       (copy-list current)
       (terminal-renderer-previous-image-ids
        renderer)
       (frame-image-ids current)
       (terminal-renderer-previous-width renderer)
       width
       (terminal-renderer-previous-height renderer)
       height
       (terminal-renderer-invalid-p renderer)
       nil)
      output)))

(defun render-frame
    (renderer lines &key
                      (cursor-row
                        (max 0 (1- (length lines))))
                      (cursor-column 0)
                      overlay-active-p)
  (if (terminal-renderer-alt-screen-p renderer)
      (render-alt-frame
       renderer lines
       :cursor-row cursor-row
       :cursor-column cursor-column)
      (render-main-frame
       renderer lines
       :cursor-row cursor-row
       :cursor-column cursor-column
       :overlay-active-p overlay-active-p)))
