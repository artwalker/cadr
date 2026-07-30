(in-package #:cadr-tui)

(defparameter +overlay-segment-reset+
  (format nil "~C[0m~C]8;;~C"
          #\Escape #\Escape (code-char 7)))

(defun parse-overlay-size (value reference)
  (cond
    ((numberp value) (floor value))
    ((stringp value)
     (when (cl-ppcre:scan
            "^[0-9]+(?:\\.[0-9]+)?%$"
            value)
       (floor
        (* reference
           (/ (read-from-string
               (subseq value 0
                       (1- (length value))))
              100)))))
    (t nil)))

(defun overlay-margin-values (margin)
  (if (numberp margin)
      (let ((value (max 0 (floor margin))))
        (values value value value value))
      (values
       (max 0 (or (getf margin :top) 0))
       (max 0 (or (getf margin :right) 0))
       (max 0 (or (getf margin :bottom) 0))
       (max 0 (or (getf margin :left) 0)))))

(defun overlay-top-anchor-p (anchor)
  (member anchor
          '(:top-left :top-center :top-right)))

(defun overlay-bottom-anchor-p (anchor)
  (member anchor
          '(:bottom-left :bottom-center :bottom-right)))

(defun overlay-left-anchor-p (anchor)
  (member anchor
          '(:top-left :left-center :bottom-left)))

(defun overlay-right-anchor-p (anchor)
  (member anchor
          '(:top-right :right-center :bottom-right)))

(defun overlay-anchor-row
    (anchor height available-height margin-top)
  (cond
    ((overlay-top-anchor-p anchor) margin-top)
    ((overlay-bottom-anchor-p anchor)
     (+ margin-top available-height (- height)))
    (t
     (+ margin-top
        (floor (- available-height height) 2)))))

(defun overlay-anchor-column
    (anchor width available-width margin-left)
  (cond
    ((overlay-left-anchor-p anchor) margin-left)
    ((overlay-right-anchor-p anchor)
     (+ margin-left available-width (- width)))
    (t
     (+ margin-left
        (floor (- available-width width) 2)))))

(defun overlay-percent-position
    (value available-size object-size margin)
  (when (stringp value)
    (let ((percent
            (parse-overlay-size value 100)))
      (when percent
        (+ margin
           (floor
            (* (max 0 (- available-size object-size))
               (/ percent 100))))))))

(defun resolve-overlay-layout
    (terminal-width terminal-height overlay-height
     &key width min-width max-height
       (anchor :center)
       (offset-x 0) (offset-y 0)
       row col margin)
  (multiple-value-bind
        (margin-top margin-right
         margin-bottom margin-left)
      (overlay-margin-values margin)
    (let* ((available-width
             (max 1
                  (- terminal-width
                     margin-left margin-right)))
           (available-height
             (max 1
                  (- terminal-height
                     margin-top margin-bottom)))
           (resolved-width
             (or (parse-overlay-size
                  width terminal-width)
                 (min 80 available-width)))
           (resolved-width
             (if min-width
                 (max resolved-width min-width)
                 resolved-width))
           (resolved-width
             (max 1
                  (min resolved-width
                       available-width)))
           (resolved-max-height
             (parse-overlay-size
              max-height terminal-height))
           (resolved-max-height
             (and resolved-max-height
                  (max 1
                       (min resolved-max-height
                            available-height))))
           (effective-height
             (if resolved-max-height
                 (min overlay-height
                      resolved-max-height)
                 overlay-height))
           (resolved-row
             (or
              (and (stringp row)
                   (overlay-percent-position
                    row available-height
                    effective-height margin-top))
              (and (numberp row) (floor row))
              (overlay-anchor-row
               anchor effective-height
               available-height margin-top)))
           (resolved-column
             (or
              (and (stringp col)
                   (overlay-percent-position
                    col available-width
                    resolved-width margin-left))
              (and (numberp col) (floor col))
              (overlay-anchor-column
               anchor resolved-width
               available-width margin-left))))
      (incf resolved-row offset-y)
      (incf resolved-column offset-x)
      (setf
       resolved-row
       (max margin-top
            (min resolved-row
                 (- terminal-height
                    margin-bottom
                    effective-height)))
       resolved-column
       (max margin-left
            (min resolved-column
                 (- terminal-width
                    margin-right
                    resolved-width))))
      (values resolved-width resolved-row
              resolved-column resolved-max-height))))

(defun composite-overlay-line
    (base-line overlay-line start-column
     overlay-width total-width)
  (when (image-line-p base-line)
    (return-from composite-overlay-line base-line))
  (let ((after-start (+ start-column overlay-width)))
    (multiple-value-bind
          (before before-width after after-width)
        (extract-segments
         base-line start-column after-start
         total-width t)
      (multiple-value-bind (overlay overlay-visible-width)
          (slice-with-width
           overlay-line 0 overlay-width t)
        (let* ((before-padding
                 (max 0
                      (- start-column before-width)))
               (overlay-padding
                 (max 0
                      (- overlay-width
                         overlay-visible-width)))
               (actual-before-width
                 (max start-column before-width))
               (actual-overlay-width
                 (max overlay-width
                      overlay-visible-width))
               (after-target
                 (max 0
                      (- total-width
                         actual-before-width
                         actual-overlay-width)))
               (after-padding
                 (max 0
                      (- after-target after-width)))
               (result
                 (concatenate
                  'string
                  before
                  (make-string
                   before-padding
                   :initial-element #\Space)
                  +overlay-segment-reset+
                  overlay
                  (make-string
                   overlay-padding
                   :initial-element #\Space)
                  +overlay-segment-reset+
                  after
                  (make-string
                   after-padding
                   :initial-element #\Space))))
          (if (<= (visible-width result)
                  total-width)
              result
              (slice-by-column
               result 0 total-width t)))))))

(defstruct overlay-placement
  (lines nil :type list)
  width
  min-width
  max-height
  (anchor :center)
  (offset-x 0 :type integer)
  (offset-y 0 :type integer)
  row col margin
  (hidden-p nil :type boolean)
  (visible-p t))

(defun overlay-placement-visible-p-at
    (placement terminal-width terminal-height)
  (and (not (overlay-placement-hidden-p placement))
       (let ((visible
               (overlay-placement-visible-p placement)))
         (if (functionp visible)
             (funcall visible
                      terminal-width terminal-height)
             visible))))

(defun overlay-placement-layout
    (placement terminal-width terminal-height
     overlay-height)
  (resolve-overlay-layout
   terminal-width terminal-height overlay-height
   :width (overlay-placement-width placement)
   :min-width (overlay-placement-min-width placement)
   :max-height (overlay-placement-max-height placement)
   :anchor (overlay-placement-anchor placement)
   :offset-x (overlay-placement-offset-x placement)
   :offset-y (overlay-placement-offset-y placement)
   :row (overlay-placement-row placement)
   :col (overlay-placement-col placement)
   :margin (overlay-placement-margin placement)))

(defun composite-overlay-frame
    (base-lines placements terminal-width
     terminal-height)
  (let ((rendered nil)
        (minimum-lines (length base-lines)))
    (dolist (placement placements)
      (when (overlay-placement-visible-p-at
             placement terminal-width terminal-height)
        (multiple-value-bind (width row column
                              maximum-height)
            (overlay-placement-layout
             placement terminal-width terminal-height 0)
          (declare (ignore row column))
          (let ((lines
                  (copy-list
                   (overlay-placement-lines placement))))
            (when (and maximum-height
                       (> (length lines) maximum-height))
              (setf lines
                    (subseq lines 0 maximum-height)))
            (multiple-value-bind
                  (ignored-width final-row final-column
                   ignored-maximum-height)
                (overlay-placement-layout
                 placement terminal-width terminal-height
                 (length lines))
              (declare
               (ignore ignored-width
                       ignored-maximum-height))
              (push
               (list lines final-row
                     final-column width)
               rendered)
              (setf minimum-lines
                    (max minimum-lines
                         (+ final-row
                            (length lines)))))))))
    (let* ((working-height
             (max (length base-lines)
                  terminal-height minimum-lines))
           (viewport-start
             (max 0 (- working-height
                       terminal-height)))
           (result (copy-list base-lines)))
      (loop while (< (length result) working-height)
            do (setf result
                     (nconc result (list ""))))
      (dolist (entry (nreverse rendered))
        (destructuring-bind
            (lines row column width) entry
          (loop for line in lines
                for offset from 0
                for index = (+ viewport-start row
                               offset)
                when (between-p
                      index 0 (1- (length result)))
                  do
                  (setf
                   (nth index result)
                   (composite-overlay-line
                    (nth index result)
                    line column width
                    terminal-width)))))
      (loop for line in result
            collect
            (if (= (visible-width line)
                   terminal-width)
                line
                (multiple-value-bind (clipped used)
                    (slice-to-width line terminal-width)
                  (concatenate
                   'string clipped
                   (make-string
                    (max 0 (- terminal-width used))
                    :initial-element #\Space))))))))

(defstruct overlay-stack-entry
  component
  (lines nil :type list)
  (non-capturing-p nil :type boolean)
  (hidden-p nil :type boolean)
  (visible-p t)
  pre-focus
  (focus-order 0 :type (integer 0 *))
  (removed-p nil :type boolean))

(defstruct (overlay-stack
            (:constructor make-overlay-stack
                (&key focused-component)))
  (entries nil :type list)
  focused-component
  (focus-counter 0 :type (integer 0 *)))

(defstruct (overlay-handle
            (:constructor %make-overlay-handle))
  stack
  entry)

(defun overlay-entry-visible-p (entry)
  (and (not (overlay-stack-entry-removed-p entry))
       (not (overlay-stack-entry-hidden-p entry))
       (let ((visible
               (overlay-stack-entry-visible-p entry)))
         (if (functionp visible)
             (funcall visible)
             visible))))

(defun top-capturing-overlay (stack &optional exclude)
  (first
   (sort
    (remove-if-not
     (lambda (entry)
       (and (not (eq entry exclude))
            (not
             (overlay-stack-entry-non-capturing-p
              entry))
            (overlay-entry-visible-p entry)))
     (copy-list (overlay-stack-entries stack)))
    #'>
    :key #'overlay-stack-entry-focus-order)))

(defun overlay-stack-show
    (stack component lines
     &key non-capturing-p (visible-p t))
  (let ((entry
          (make-overlay-stack-entry
           :component component
           :lines (copy-list lines)
           :non-capturing-p non-capturing-p
           :visible-p visible-p
           :pre-focus
           (overlay-stack-focused-component stack)
           :focus-order
           (incf
            (overlay-stack-focus-counter stack)))))
    (setf
     (overlay-stack-entries stack)
     (nconc
      (overlay-stack-entries stack)
      (list entry)))
    (when (and (not non-capturing-p)
               (overlay-entry-visible-p entry))
      (setf
       (overlay-stack-focused-component stack)
       component))
    (%make-overlay-handle
     :stack stack :entry entry)))

(defun overlay-stack-input-target (stack)
  (overlay-stack-focused-component stack))

(defun overlay-stack-visible-p (stack)
  (some #'overlay-entry-visible-p
        (overlay-stack-entries stack)))

(defun overlay-handle-focused-p (handle)
  (eq
   (overlay-stack-focused-component
    (overlay-handle-stack handle))
   (overlay-stack-entry-component
    (overlay-handle-entry handle))))

(defun overlay-handle-focus (handle)
  (let ((stack (overlay-handle-stack handle))
        (entry (overlay-handle-entry handle)))
    (when (overlay-entry-visible-p entry)
      (setf
       (overlay-stack-entry-focus-order entry)
       (incf
        (overlay-stack-focus-counter stack))
       (overlay-stack-focused-component stack)
       (overlay-stack-entry-component entry))))
  handle)

(defun overlay-restored-focus (stack entry)
  (let ((top (top-capturing-overlay stack entry)))
    (if top
        (overlay-stack-entry-component top)
        (overlay-stack-entry-pre-focus entry))))

(defun overlay-handle-set-hidden (handle hidden-p)
  (let ((stack (overlay-handle-stack handle))
        (entry (overlay-handle-entry handle)))
    (unless (eq (not (null hidden-p))
                (overlay-stack-entry-hidden-p entry))
      (setf
       (overlay-stack-entry-hidden-p entry)
       (not (null hidden-p)))
      (cond
        ((and hidden-p
              (overlay-handle-focused-p handle))
         (setf
          (overlay-stack-focused-component stack)
          (overlay-restored-focus stack entry)))
        ((and (not hidden-p)
              (not
               (overlay-stack-entry-non-capturing-p
                entry))
              (overlay-entry-visible-p entry))
         (overlay-handle-focus handle)))))
  handle)

(defun overlay-handle-unfocus
    (handle &key (target nil target-supplied-p))
  (when (overlay-handle-focused-p handle)
    (let ((stack (overlay-handle-stack handle))
          (entry (overlay-handle-entry handle)))
      (setf
       (overlay-stack-focused-component stack)
       (if target-supplied-p
           target
           (overlay-restored-focus
            stack entry)))))
  handle)

(defun overlay-handle-hide (handle)
  (let ((stack (overlay-handle-stack handle))
        (entry (overlay-handle-entry handle)))
    (when (overlay-handle-focused-p handle)
      (setf
       (overlay-stack-focused-component stack)
       (overlay-restored-focus stack entry)))
    (setf
     (overlay-stack-entry-removed-p entry) t
     (overlay-stack-entries stack)
     (remove entry
             (overlay-stack-entries stack))))
  handle)
