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
     document)
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
    (let* ((selected
             (apply-renderer-selection
              renderer
              (alt-viewport-lines
               renderer document height)))
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
               (format stream "~C[?2026h"
                       #\Escape)
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
                     for new =
                     (or (nth row current) "")
                     for old =
                     (nth row previous)
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
               (format stream "~C[?2026l"
                       #\Escape))))
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
