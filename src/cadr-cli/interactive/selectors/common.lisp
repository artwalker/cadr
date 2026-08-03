(in-package #:cadr-cli)

(defun selector-modified-cursor-key (data)
  (multiple-value-bind
        (matched registers)
      (cl-ppcre:scan-to-strings
       (format nil "^~C\\[1;(\\d+)([ABCD])$"
               #\Escape)
       data)
    (when matched
      (let* ((mask
               (1-
                (parse-integer
                 (aref registers 0))))
             (direction
               (cdr
                (assoc
                 (char (aref registers 1) 0)
                 '((#\A . "up")
                   (#\B . "down")
                   (#\C . "right")
                   (#\D . "left"))))))
        (when direction
          (format
           nil "~{~A~^+~}"
           (append
            (when (logtest 1 mask)
              '("shift"))
            (when (logtest 4 mask)
              '("ctrl"))
            (when (logtest 2 mask)
              '("alt"))
            (when (logtest 8 mask)
              '("super"))
            (list direction))))))))

(defun selector-keybinding-matches-p
    (manager data name)
  (or
   (cadr-tui:keybinding-matches-p
    manager data name)
   (let ((parsed
           (selector-modified-cursor-key data)))
     (and parsed
          (member
           (cadr-tui::canonical-key-id parsed)
           (cadr-tui:keybinding-keys
            manager name)
           :key #'cadr-tui::canonical-key-id
           :test #'string=)))))

(defun selector-align-left-right
    (left right width)
  (let* ((right
           (cadr-tui:truncate-to-width
            right (max 0 width) ""))
         (left-width
           (max 0
                (- width
                   (cadr-tui:visible-width right)
                   1)))
         (left
           (cadr-tui:truncate-to-width
            left left-width "")))
    (concatenate
     'string left
     (make-string
      (max 0
           (- width
              (cadr-tui:visible-width left)
              (cadr-tui:visible-width right)))
      :initial-element #\Space)
     right)))

(defun selector-frame-visible-slice
    (items selected maximum)
  (let* ((count (length items))
         (start
           (max
            0
            (min
             (- selected (floor maximum 2))
             (- count maximum))))
         (end (min (+ start maximum) count)))
    (values (subseq items start end)
            start end count)))

(defun centered-visible-slice
    (items selected maximum)
  (selector-frame-visible-slice
   items selected maximum))

(defun selector-frame-move-index
    (selected count delta)
  (if (plusp count)
      (mod (+ selected delta) count)
      0))

(defun selector-fit-line (line width &key (pad-p nil))
  (let* ((available (max 0 width))
         (limited
           (cadr-tui:truncate-to-width
            line available ""))
         (padding
           (if pad-p
               (max
                0
                (- available
                   (cadr-tui:visible-width limited)))
               0)))
    (concatenate
     'string limited
     (make-string padding
                  :initial-element #\Space))))

(defun selector-border-line
    (width &optional (color :border-muted))
  (cadr-tui:theme-foreground
   color
   (make-string (max 0 width)
                :initial-element #\─)))

(defun auth-overlay-border-line (width)
  (selector-border-line width :border))

(defun selector-title-line (title width)
  (selector-fit-line
   (cadr-tui:theme-foreground
    :accent
    (cadr-tui:theme-bold title))
   width))

(defun selector-overlay-title-line (title width)
  (selector-fit-line
   (concatenate
    'string " "
    (cadr-tui:theme-foreground
     :accent
     (cadr-tui:theme-bold title :enabled-p t)
     :enabled-p t))
   width))

(defun selector-input-line (value width)
  (first
   (nth-value
    0
    (cadr-tui:render-single-line-input
     (cadr-tui:make-single-line-input
      :value value :prompt "> ")
     width))))

(defun selector-selected-line (line width)
  (cadr-tui:theme-background
   :selected-bg
   (selector-fit-line line width :pad-p t)))

(defun selector-muted-line (line width)
  (selector-fit-line
   (cadr-tui:theme-foreground :muted line)
   width))

(defun selector-dim-line (line width)
  (selector-fit-line
   (cadr-tui:theme-foreground :dim line)
   width))

(defun selector-fuzzy-filter
    (items query text-function)
  (let ((tokens
          (cadr-tui::fuzzy-query-tokens query)))
    (when (null tokens)
      (return-from selector-fuzzy-filter
        (copy-list items)))
    (let ((matches nil))
      (dolist (item items)
        (let ((score 0d0)
              (matched-p t)
              (text
                (funcall text-function item)))
          (dolist (token tokens)
            (multiple-value-bind
                  (token-matched-p token-score)
                (cadr-tui:fuzzy-match token text)
              (unless token-matched-p
                (setf matched-p nil)
                (return))
              (incf score token-score)))
          (when matched-p
            (push (cons item score) matches))))
      (mapcar
       #'car
       (stable-sort
        (nreverse matches)
        #'< :key #'cdr)))))

(defun selector-delete-query-character (query)
  (if (zerop (length query))
      query
      (subseq
       query 0
       (cadr-tui::previous-cluster-boundary
        query (length query)))))

(defstruct (selector-frame
            (:constructor %make-selector-frame))
  (items nil :type list)
  (selected 0 :type (integer 0 *))
  (maximum 8 :type (integer 1 *))
  (sections nil :type list)
  viewport-renderer
  item-renderer
  empty-renderer
  count-renderer)

(defun make-selector-frame
    (&key items (selected 0) (maximum 8) sections
       viewport-renderer item-renderer
       empty-renderer count-renderer)
  (%make-selector-frame
   :items items
   :selected selected
   :maximum maximum
   :sections sections
   :viewport-renderer viewport-renderer
   :item-renderer item-renderer
   :empty-renderer empty-renderer
   :count-renderer count-renderer))

(defun selector-frame-section-lines
    (frame section width visible start end total)
  (let ((kind (if (consp section) (first section) section))
        (arguments (and (consp section) (rest section))))
    (case kind
      (:blank (list ""))
      (:border
       (list
        (selector-border-line
         width (or (first arguments) :border-muted))))
      (:title
       (destructuring-bind (title &optional (style :standard)) arguments
         (list
          (case style
            (:overlay
             (selector-overlay-title-line title width))
            (:plain
             (selector-fit-line
              (cadr-tui:theme-bold title) width))
            (:raw
             (selector-fit-line title width))
            (otherwise
             (selector-title-line title width))))))
      (:input
       (destructuring-bind (value &optional (style :component)) arguments
         (list
          (case style
            (:accent
             (selector-fit-line
              (concatenate
               'string
               (cadr-tui:theme-foreground :muted "> ")
               (cadr-tui:theme-foreground :accent (or value "")))
              width))
            (:tree
             (selector-fit-line
              (concatenate
               'string "  "
               (cadr-tui:theme-foreground
                :muted "Type to search:")
               (if (plusp (length (or value "")))
                   (concatenate
                    'string " "
                    (cadr-tui:theme-foreground
                     :accent value))
                   ""))
              width))
            (otherwise
             (selector-input-line (or value "") width))))))
      (:lines (copy-list (first arguments)))
      (:help
       (destructuring-bind (lines &optional (style :dim)) arguments
         (mapcar
          (lambda (line)
            (case style
              (:muted (selector-muted-line line width))
              (:raw (selector-fit-line line width))
              (otherwise (selector-dim-line line width))))
          lines)))
      (:viewport
       (cond
         ((selector-frame-viewport-renderer frame)
          (funcall
           (selector-frame-viewport-renderer frame)
           visible start end total width))
         ((null visible)
          (let ((renderer
                  (selector-frame-empty-renderer frame)))
            (cond
              ((functionp renderer)
               (funcall renderer width total))
              (renderer (copy-list renderer))
              (t nil))))
         ((selector-frame-item-renderer frame)
          (mapcan
           (lambda (item index)
             (let ((rendered
                     (funcall
                      (selector-frame-item-renderer frame)
                      item index
                      (= index
                         (selector-frame-selected frame))
                      total width)))
               (if (listp rendered)
                   rendered
                   (list rendered))))
           visible
           (loop for index from start below end
                 collect index)))
         (t nil)))
      (:count
       (when (or (> start 0) (< end total))
         (let ((renderer
                 (selector-frame-count-renderer frame)))
           (if renderer
               (funcall renderer
                        (selector-frame-selected frame)
                        total width)
               (list
                (selector-muted-line
                 (format nil "  (~D/~D)"
                         (1+ (selector-frame-selected frame))
                         total)
                 width))))))
      (otherwise
       (error "Unknown selector-frame section: ~S" section)))))

(defun render-selector-frame (frame width)
  (multiple-value-bind (visible start end total)
      (selector-frame-visible-slice
       (selector-frame-items frame)
       (selector-frame-selected frame)
       (selector-frame-maximum frame))
    (mapcan
     (lambda (section)
       (selector-frame-section-lines
        frame section width visible start end total))
     (selector-frame-sections frame))))
