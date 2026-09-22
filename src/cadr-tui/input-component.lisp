(in-package #:cadr-tui)

(defstruct (single-line-input
            (:constructor %make-single-line-input))
  (value "" :type string)
  (cursor 0 :type (integer 0 *))
  (prompt "> " :type string)
  (kill-ring (make-kill-ring) :type kill-ring)
  (undo-stack (make-undo-stack) :type undo-stack)
  last-action
  last-yank-start
  last-yank-end
  (rendered-start-column 0 :type (integer 0 *)))

(defun make-single-line-input
    (&key (value "") (prompt "> "))
  (%make-single-line-input
   :value value
   :cursor (length value)
   :prompt prompt))

(defun single-line-input-reset-yank (input)
  (setf
   (single-line-input-last-yank-start input) nil
   (single-line-input-last-yank-end input) nil)
  input)

(defun single-line-input-clear-action (input)
  ;; One owner for the 3-form reset (action + yank span).
  ;; pi@16787ad5b packages/tui/src/input.ts Input reset sites.
  (setf (single-line-input-last-action input) nil)
  (single-line-input-reset-yank input))

(defun single-line-input-set-value (input value)
  (setf
   (single-line-input-value input) value
   (single-line-input-cursor input)
   (min
    (single-line-input-cursor input)
    (length value)))
  (single-line-input-clear-action input)
  input)

(defun single-line-input-snapshot (input)
  (list
   :value (single-line-input-value input)
   :cursor (single-line-input-cursor input)))

(defun single-line-input-push-undo (input)
  (undo-stack-push
   (single-line-input-undo-stack input)
   (single-line-input-snapshot input)))

(defun single-line-input-replace-range
    (input start end replacement)
  (let ((value (single-line-input-value input)))
    (setf
     (single-line-input-value input)
     (concatenate
      'string
      (subseq value 0 start)
      replacement
      (subseq value end))
     (single-line-input-cursor input)
     (+ start (length replacement))))
  input)

(defun single-line-input-insert (input text)
  (when (or
         (some #'navigation-whitespace-p text)
         (not
          (eq :type-word
              (single-line-input-last-action input))))
    (single-line-input-push-undo input))
  (single-line-input-replace-range
   input
   (single-line-input-cursor input)
   (single-line-input-cursor input)
   text)
  (setf
   (single-line-input-last-action input)
   :type-word)
  (single-line-input-reset-yank input))

(defun single-line-input-delete-backward (input)
  (let ((cursor (single-line-input-cursor input)))
    (when (> cursor 0)
      (single-line-input-push-undo input)
      (single-line-input-replace-range
       input
       (previous-cluster-boundary
        (single-line-input-value input)
        cursor)
       cursor ""))
    (single-line-input-clear-action input))
  input)

(defun single-line-input-delete-forward (input)
  (let* ((value (single-line-input-value input))
         (cursor (single-line-input-cursor input)))
    (when (< cursor (length value))
      (single-line-input-push-undo input)
      (single-line-input-replace-range
       input cursor
       (next-cluster-boundary value cursor)
       ""))
    (single-line-input-clear-action input))
  input)

(defun single-line-input-kill-range
    (input start end prepend-p)
  (when (< start end)
    (single-line-input-push-undo input)
    (let ((was-kill
            (eq :kill
                (single-line-input-last-action input)))
          (deleted
            (subseq
             (single-line-input-value input)
             start end)))
      (kill-ring-push
       (single-line-input-kill-ring input)
       deleted
       :prepend-p prepend-p
       :accumulate-p was-kill)
      (single-line-input-replace-range
       input start end "")
      (setf
       (single-line-input-last-action input)
       :kill)))
  (single-line-input-reset-yank input)
  input)

(defun single-line-input-delete-word-backward
    (input)
  (let ((cursor (single-line-input-cursor input)))
    (when (> cursor 0)
      (single-line-input-kill-range
       input
       (find-word-backward
        (single-line-input-value input)
        cursor)
       cursor t)))
  input)

(defun single-line-input-delete-word-forward
    (input)
  (let ((cursor (single-line-input-cursor input)))
    (when (< cursor
             (length
              (single-line-input-value input)))
      (single-line-input-kill-range
       input cursor
       (find-word-forward
        (single-line-input-value input)
        cursor)
       nil)))
  input)

(defun single-line-input-yank (input)
  (let ((text
          (kill-ring-peek
           (single-line-input-kill-ring input))))
    (when text
      (single-line-input-push-undo input)
      (let ((start
              (single-line-input-cursor input)))
        (single-line-input-replace-range
         input start start text)
        (setf
         (single-line-input-last-yank-start input)
         start
         (single-line-input-last-yank-end input)
         (+ start (length text))
         (single-line-input-last-action input)
         :yank))))
  input)

(defun single-line-input-yank-pop (input)
  (when
      (and
       (eq :yank
           (single-line-input-last-action input))
       (> (kill-ring-length
           (single-line-input-kill-ring input))
          1)
       (single-line-input-last-yank-start input)
       (single-line-input-last-yank-end input))
    (single-line-input-push-undo input)
    (let ((start
            (single-line-input-last-yank-start input))
          (end
            (single-line-input-last-yank-end input)))
      (single-line-input-replace-range
       input start end "")
      (kill-ring-rotate
       (single-line-input-kill-ring input))
      (let ((replacement
              (or
               (kill-ring-peek
                (single-line-input-kill-ring input))
               "")))
        (single-line-input-replace-range
         input start start replacement)
        (setf
         (single-line-input-last-yank-start input)
         start
         (single-line-input-last-yank-end input)
         (+ start (length replacement))
         (single-line-input-last-action input)
         :yank))))
  input)

(defun single-line-input-undo (input)
  (let ((snapshot
          (undo-stack-pop
           (single-line-input-undo-stack input))))
    (when snapshot
      (setf
       (single-line-input-value input)
       (getf snapshot :value)
       (single-line-input-cursor input)
       (getf snapshot :cursor))
      (single-line-input-clear-action input)))
  input)

(defun normalize-single-line-paste (text)
  (with-output-to-string (output)
    (loop with index = 0
          while (< index (length text))
          for character = (char text index)
          do
          (cond
            ((char= character #\Return)
             (when (and (< (1+ index) (length text))
                        (char= (char text (1+ index))
                               #\Newline))
               (incf index)))
            ((char= character #\Newline))
            ((char= character #\Tab)
             (write-string "    " output))
            ((>= (codepoint character) 32)
             (write-char character output)))
          (incf index))))

(defun single-line-input-handle-event
    (input event)
  (let ((kind (input-event-kind event))
        (text (or (input-event-text event) "")))
    (case kind
      (:text
       (single-line-input-insert input text))
      (:paste
       (let ((clean
               (normalize-single-line-paste text)))
         (when (plusp (length clean))
           (single-line-input-push-undo input)
           (single-line-input-replace-range
            input
            (single-line-input-cursor input)
            (single-line-input-cursor input)
            clean))
         (single-line-input-clear-action input)))
      (:left
       (setf
        (single-line-input-cursor input)
        (previous-cluster-boundary
         (single-line-input-value input)
         (single-line-input-cursor input)))
       (single-line-input-clear-action input))
      (:right
       (setf
        (single-line-input-cursor input)
        (next-cluster-boundary
         (single-line-input-value input)
         (single-line-input-cursor input)))
       (single-line-input-clear-action input))
      ((:line-start :home)
       (setf (single-line-input-cursor input) 0)
       (single-line-input-clear-action input))
      ((:line-end :end)
       (setf
        (single-line-input-cursor input)
        (length
         (single-line-input-value input)))
       (single-line-input-clear-action input))
      (:word-left
       (setf
        (single-line-input-cursor input)
        (find-word-backward
         (single-line-input-value input)
         (single-line-input-cursor input)))
       (single-line-input-clear-action input))
      (:word-right
       (setf
        (single-line-input-cursor input)
        (find-word-forward
         (single-line-input-value input)
         (single-line-input-cursor input)))
       (single-line-input-clear-action input))
      (:backspace
       (single-line-input-delete-backward input))
      (:delete
       (single-line-input-delete-forward input))
      (:delete-word-backward
       (single-line-input-delete-word-backward input))
      (:delete-word-forward
       (single-line-input-delete-word-forward input))
      (:delete-line-start
       (single-line-input-kill-range
        input 0
        (single-line-input-cursor input)
        t))
      (:delete-line-end
       (single-line-input-kill-range
        input
        (single-line-input-cursor input)
        (length
         (single-line-input-value input))
        nil))
      (:yank (single-line-input-yank input))
      (:yank-pop
       (single-line-input-yank-pop input))
      (:undo (single-line-input-undo input))
      (:enter
       (return-from single-line-input-handle-event
         (values
          :submit
          (single-line-input-value input)))))
    (values nil nil)))

(defun single-line-input-handle-mouse
    (input &key type button x y)
  (unless (and (eq type :press)
               (eq button :left)
               (eql y 0)
               (integerp x))
    (return-from single-line-input-handle-mouse nil))
  (let* ((value (single-line-input-value input))
         (target
           (+ (single-line-input-rendered-start-column input)
              (max 0
                   (- x
                      (visible-width
                       (single-line-input-prompt input)))))))
    (setf (single-line-input-cursor input) (length value))
    (loop with column = 0
          with position = 0
          while (< position (length value))
          for next = (next-cluster-boundary value position)
          for width = (grapheme-width (subseq value position next))
          do (when (< target (+ column width))
               (setf (single-line-input-cursor input) position)
               (return))
             (incf column width)
             (setf position next))
    (single-line-input-clear-action input)
    t))

(defun render-single-line-input (input width)
  (let* ((prompt
           (single-line-input-prompt input))
         (prompt-width (visible-width prompt))
         (available-width
           (- width prompt-width))
         (value (single-line-input-value input))
         (cursor (single-line-input-cursor input)))
    (when (<= available-width 0)
      (return-from render-single-line-input
        (values (list prompt) 0 0)))
    (let* ((total-width (visible-width value))
           (visible-text value)
           (cursor-display cursor))
      (setf (single-line-input-rendered-start-column input) 0)
      (when (>= total-width available-width)
        (let* ((scroll-width
                 (if (= cursor (length value))
                     (1- available-width)
                     available-width))
               (cursor-column
                 (visible-width (subseq value 0 cursor))))
          (if (plusp scroll-width)
              (let* ((half-width (floor scroll-width 2))
                     (start-column
                       (cond
                         ((< cursor-column half-width) 0)
                         ((> cursor-column
                             (- total-width half-width))
                          (max 0 (- total-width scroll-width)))
                         (t
                          (max 0 (- cursor-column half-width)))))
                     (before-cursor
                       (slice-by-column
                        value start-column
                        (max 0 (- cursor-column start-column))
                        t)))
                (setf
                 (single-line-input-rendered-start-column input)
                 start-column
                 visible-text
                 (slice-by-column
                  value start-column scroll-width t)
                 cursor-display (length before-cursor)))
              (setf visible-text "" cursor-display 0))))
      (let* ((remaining
               (subseq visible-text cursor-display))
             (cursor-end
               (if (plusp (length remaining))
                   (next-cluster-boundary remaining 0)
                   0))
             (before-cursor
               (subseq visible-text 0 cursor-display))
             (at-cursor
               (if (plusp cursor-end)
                   (subseq remaining 0 cursor-end)
                   " "))
             (after-cursor
               (if (plusp cursor-end)
                   (subseq remaining cursor-end)
                   ""))
             (content
               (concatenate
                'string
                before-cursor
                (theme-inverse at-cursor :enabled-p t)
                after-cursor))
             (line
               (concatenate
                'string prompt content
                (make-string
                 (max 0 (- available-width
                           (visible-width content)))
                 :initial-element #\Space))))
        (values
         (list line)
         0
         (min
          (max 0 (1- width))
          (+ prompt-width
             (visible-width before-cursor))))))))
