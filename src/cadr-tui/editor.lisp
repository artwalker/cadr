(in-package #:cadr-tui)

(defstruct (multiline-editor
            (:constructor %make-multiline-editor))
  (text "" :type string)
  (cursor 0 :type (integer 0 *))
  (prompt "› " :type string)
  (history nil :type list)
  (history-limit 100 :type (integer 1 *))
  history-index
  history-draft
  (history-draft-cursor 0 :type (integer 0 *))
  (kill-ring (make-kill-ring) :type kill-ring)
  (undo-stack (make-undo-stack) :type undo-stack)
  last-action
  preferred-column
  jump-mode
  (pastes nil :type list)
  (paste-counter 0 :type (integer 0 *))
  autocomplete-provider
  autocomplete-suggestions
  (autocomplete-selected 0 :type (integer 0 *))
  autocomplete-prefix
  (last-render-width 80 :type (integer 1 *))
  last-yank-start
  last-yank-end)

(defparameter +editor-paste-marker-prefix+ "[paste #")

(defun normalize-editor-text (text)
  (with-output-to-string (output)
    (loop with index = 0
          while (< index (length text))
          for character = (char text index)
          do
          (cond
            ((char= character #\Return)
             (write-char #\Newline output)
             (when (and (< (1+ index) (length text))
                        (char= (char text (1+ index))
                               #\Newline))
               (incf index)))
            ((char= character #\Tab)
             (write-string "    " output))
            (t
             (write-char character output)))
          (incf index))))

(defun make-multiline-editor (&key (text "") (prompt "› ")
                                   (history-limit 100))
  (let ((normalized (normalize-editor-text text)))
    (%make-multiline-editor
     :text normalized
     :cursor (length normalized)
     :prompt prompt
     :history-limit history-limit)))

(defun editor-text (editor)
  (multiline-editor-text editor))

(defun split-editor-lines (text)
  (let ((lines nil)
        (start 0))
    (loop for newline = (position #\Newline text :start start)
          do
          (push (subseq text start newline) lines)
          (if newline
              (setf start (1+ newline))
              (return)))
    (nreverse lines)))

(defun editor-lines (editor)
  (copy-list
   (split-editor-lines
    (multiline-editor-text editor))))

(defun line-start-at (text cursor)
  (let ((newline
          (position #\Newline text
                    :end (min cursor (length text))
                    :from-end t)))
    (if newline (1+ newline) 0)))

(defun line-end-at (text cursor)
  (or (position #\Newline text
                :start (min cursor (length text)))
      (length text)))

(defun editor-cursor (editor)
  (let* ((text (multiline-editor-text editor))
         (cursor (multiline-editor-cursor editor))
         (start (line-start-at text cursor)))
    (values
     (count #\Newline text :end cursor)
     (- cursor start))))

(defun editor-position-for-line-column
    (text target-line target-column)
  (let ((line 0)
        (start 0))
    (loop while (< line target-line)
          for newline = (position #\Newline text :start start)
          do
          (unless newline
            (return-from editor-position-for-line-column
              (length text)))
          (setf start (1+ newline))
          (incf line))
    (min (+ start target-column)
         (line-end-at text start))))

(defun editor-snapshot (editor)
  (list
   :text (multiline-editor-text editor)
   :cursor (multiline-editor-cursor editor)
   :pastes (copy-tree (multiline-editor-pastes editor))
   :paste-counter
   (multiline-editor-paste-counter editor)))

(defun editor-push-undo (editor)
  (undo-stack-push
   (multiline-editor-undo-stack editor)
   (editor-snapshot editor)))

(defun editor-cancel-autocomplete (editor)
  (setf
   (multiline-editor-autocomplete-suggestions editor) nil
   (multiline-editor-autocomplete-prefix editor) nil
   (multiline-editor-autocomplete-selected editor) 0)
  editor)

(defun editor-exit-history (editor)
  (setf
   (multiline-editor-history-index editor) nil
   (multiline-editor-history-draft editor) nil
   (multiline-editor-history-draft-cursor editor) 0)
  editor)

(defun editor-reset-navigation-state (editor)
  (setf
   (multiline-editor-preferred-column editor) nil
   (multiline-editor-last-yank-start editor) nil
   (multiline-editor-last-yank-end editor) nil)
  editor)

(defun editor-set-text-internal
    (editor text &key (cursor :end))
  (let ((normalized (normalize-editor-text text)))
    (setf
     (multiline-editor-text editor) normalized
     (multiline-editor-cursor editor)
     (if (eq cursor :start)
         0
         (length normalized))))
  (editor-reset-navigation-state editor)
  editor)

(defun editor-set-text (editor text)
  (let ((normalized (normalize-editor-text text)))
    (unless (string= normalized
                     (multiline-editor-text editor))
      (editor-push-undo editor))
    (editor-cancel-autocomplete editor)
    (editor-exit-history editor)
    (setf
     (multiline-editor-last-action editor) nil
     (multiline-editor-pastes editor) nil
     (multiline-editor-paste-counter editor) 0)
    (editor-set-text-internal
     editor normalized :cursor :end)))

(defun editor-add-history (editor text)
  (let ((trimmed
          (string-trim
           '(#\Space #\Tab #\Newline #\Return)
           text)))
    (unless (or (zerop (length trimmed))
                (and
                 (multiline-editor-history editor)
                 (string=
                  trimmed
                  (first
                   (multiline-editor-history editor)))))
      (push trimmed
            (multiline-editor-history editor))
      (when
          (> (length
              (multiline-editor-history editor))
             (multiline-editor-history-limit editor))
        (setf
         (multiline-editor-history editor)
         (subseq
          (multiline-editor-history editor)
          0
          (multiline-editor-history-limit editor))))))
  editor)

(defun editor-history-previous (editor)
  (let ((history (multiline-editor-history editor)))
    (when history
      (if (null
           (multiline-editor-history-index editor))
          (progn
            (setf
             (multiline-editor-history-draft editor)
             (multiline-editor-text editor)
             (multiline-editor-history-draft-cursor editor)
             (multiline-editor-cursor editor)
             (multiline-editor-history-index editor) 0))
          (setf
           (multiline-editor-history-index editor)
           (min
            (1- (length history))
            (1+
             (multiline-editor-history-index
              editor)))))
      (when (null
             (multiline-editor-history-draft editor))
        (setf
         (multiline-editor-history-draft editor)
         (multiline-editor-text editor)
         (multiline-editor-history-draft-cursor editor)
         (multiline-editor-cursor editor)))
      (editor-set-text-internal
       editor
       (nth (multiline-editor-history-index editor)
            history)
       :cursor :start)))
  editor)

(defun editor-history-next (editor)
  (let ((index (multiline-editor-history-index editor)))
    (when index
      (if (zerop index)
          (let ((draft
                  (or
                   (multiline-editor-history-draft editor)
                   ""))
                (cursor
                  (multiline-editor-history-draft-cursor
                   editor)))
            (setf
             (multiline-editor-text editor) draft
             (multiline-editor-cursor editor)
             (min cursor (length draft))
             (multiline-editor-history-index editor) nil
             (multiline-editor-history-draft editor) nil))
          (progn
            (decf (multiline-editor-history-index editor))
            (editor-set-text-internal
             editor
             (nth
              (multiline-editor-history-index editor)
              (multiline-editor-history editor))
             :cursor :end)))))
  editor)

(defun editor-paste-marker-spans (editor)
  (let ((text (multiline-editor-text editor))
        (spans nil))
    (dolist (entry
             (multiline-editor-pastes editor))
      (let* ((id (car entry))
             (prefix
               (format nil "[paste #~D" id))
             (start 0))
        (loop for found =
              (search prefix text :start2 start)
              while found
              for end = (position #\] text :start found)
              do
              (when end
                (push (list found (1+ end) id)
                      spans))
              (setf start
                    (if end (1+ end)
                        (+ found (length prefix)))))))
    (sort spans #'< :key #'first)))

(defun editor-atomic-span-at
    (editor cursor &key before-p)
  (find-if
   (lambda (span)
     (if before-p
         (and (> cursor (first span))
              (<= cursor (second span)))
         (and (>= cursor (first span))
              (< cursor (second span)))))
   (editor-paste-marker-spans editor)))

(defun editor-previous-boundary (editor)
  (let* ((text (multiline-editor-text editor))
         (cursor (multiline-editor-cursor editor))
         (span
           (editor-atomic-span-at
            editor cursor :before-p t)))
    (if span
        (first span)
        (previous-cluster-boundary text cursor))))

(defun editor-next-boundary (editor)
  (let* ((text (multiline-editor-text editor))
         (cursor (multiline-editor-cursor editor))
         (span
           (editor-atomic-span-at editor cursor)))
    (if span
        (second span)
        (next-cluster-boundary text cursor))))

(defun previous-cluster-boundary (text cursor)
  (loop with position = 0
        with previous = 0
        for cluster in (grapheme-clusters text)
        for next = (+ position (length cluster))
        while (< position cursor)
        do (setf previous position
                 position next)
        finally (return previous)))

(defun next-cluster-boundary (text cursor)
  (loop with position = 0
        for cluster in (grapheme-clusters text)
        for next = (+ position (length cluster))
        when (> next cursor)
          do (return next)
        do (setf position next)
        finally (return (length text))))

(defun editor-replace-range
    (editor start end replacement)
  (let ((text (multiline-editor-text editor)))
    (setf
     (multiline-editor-text editor)
     (concatenate
      'string
      (subseq text 0 start)
      replacement
      (subseq text end))
     (multiline-editor-cursor editor)
     (+ start (length replacement))))
  editor)

(defun editor-insert-raw (editor text)
  (editor-replace-range
   editor
   (multiline-editor-cursor editor)
   (multiline-editor-cursor editor)
   text))

(defun editor-insert (editor text)
  (editor-exit-history editor)
  (editor-cancel-autocomplete editor)
  (when (or
         (some #'navigation-whitespace-p text)
         (not
          (eq :type-word
              (multiline-editor-last-action editor))))
    (editor-push-undo editor))
  (setf (multiline-editor-last-action editor)
        :type-word)
  (editor-reset-navigation-state editor)
  (editor-insert-raw editor text)
  (editor-refresh-autocomplete editor)
  editor)

(defun editor-insert-text-at-cursor (editor text)
  (when (plusp (length text))
    (editor-push-undo editor)
    (editor-exit-history editor)
    (editor-cancel-autocomplete editor)
    (setf (multiline-editor-last-action editor) nil)
    (editor-reset-navigation-state editor)
    (editor-insert-raw
     editor (normalize-editor-text text)))
  editor)

(defun editor-remove-paste-id (editor id)
  (labels
      ((replace-all (source old new)
         (with-output-to-string (output)
           (loop with start = 0
                 for found =
                 (search old source :start2 start)
                 do
                 (if found
                     (progn
                       (write-string source output
                                     :start start
                                     :end found)
                       (write-string new output)
                       (setf start
                             (+ found
                                (length old))))
                     (progn
                       (write-string source output
                                     :start start)
                       (return)))))))
    (setf
     (multiline-editor-pastes editor)
     (remove id
             (multiline-editor-pastes editor)
             :key #'car))
    (dolist
        (entry
         (sort
          (remove-if
           (lambda (entry)
             (<= (car entry) id))
           (copy-list
            (multiline-editor-pastes editor)))
          #'< :key #'car))
      (let ((old-id (car entry)))
        (setf
         (multiline-editor-text editor)
         (replace-all
          (multiline-editor-text editor)
          (format nil "[paste #~D " old-id)
          (format nil "[paste #~D " (1- old-id)))
         (car entry) (1- old-id))))
    (setf
     (multiline-editor-paste-counter editor)
     (max 0
          (1-
           (multiline-editor-paste-counter
            editor)))))
  editor)

(defun editor-delete-range
    (editor start end &key paste-id)
  (when (< start end)
    (editor-replace-range editor start end "")
    (when paste-id
      (editor-remove-paste-id editor paste-id)))
  editor)

(defun editor-delete-backward (editor)
  (let ((cursor (multiline-editor-cursor editor)))
    (when (> cursor 0)
      (editor-push-undo editor)
      (let* ((span
               (editor-atomic-span-at
                editor cursor :before-p t))
             (start
               (if span
                   (first span)
                   (editor-previous-boundary editor))))
        (editor-delete-range
         editor start cursor
         :paste-id (and span (third span))))))
  (editor-exit-history editor)
  (editor-cancel-autocomplete editor)
  (setf (multiline-editor-last-action editor) nil)
  (editor-reset-navigation-state editor)
  editor)

(defun editor-delete-forward (editor)
  (let* ((text (multiline-editor-text editor))
         (cursor (multiline-editor-cursor editor)))
    (when (< cursor (length text))
      (editor-push-undo editor)
      (let* ((span
               (editor-atomic-span-at editor cursor))
             (end
               (if span
                   (second span)
                   (editor-next-boundary editor))))
        (editor-delete-range
         editor cursor end
         :paste-id (and span (third span))))))
  (editor-exit-history editor)
  (editor-cancel-autocomplete editor)
  (setf (multiline-editor-last-action editor) nil)
  (editor-reset-navigation-state editor)
  editor)

(defun position-at-column (text start end target-column)
  (loop with position = start
        with width = 0
        while (< position end)
        for next = (next-cluster-boundary text position)
        for cluster = (subseq text position next)
        for cluster-width = (grapheme-width cluster)
        while (<= (+ width cluster-width) target-column)
        do (incf width cluster-width)
           (setf position next)
        finally (return position)))

(defun editor-visual-line-spans (editor)
  (let ((text (multiline-editor-text editor))
        (width
          (multiline-editor-last-render-width editor))
        (absolute-start 0)
        (spans nil))
    (dolist (line (split-editor-lines text))
      (dolist
          (chunk
           (editor-word-wrap-line-spans line width))
        (push
         (list
          (+ absolute-start (second chunk))
          (+ absolute-start (third chunk)))
         spans))
      (incf absolute-start (+ (length line) 1)))
    (nreverse spans)))

(defun editor-current-visual-line
    (spans cursor)
  (or
   (position-if
    (lambda (span)
      (and (>= cursor (first span))
           (< cursor (second span))))
    spans)
   (position-if
    (lambda (span)
      (= cursor (second span)))
    spans :from-end t)
   0))

(defun editor-move-vertical (editor direction)
  (let* ((text (multiline-editor-text editor))
         (cursor (multiline-editor-cursor editor))
         (spans (editor-visual-line-spans editor))
         (current
           (editor-current-visual-line
            spans cursor))
         (span (nth current spans))
         (column
           (or
            (multiline-editor-preferred-column editor)
            (visible-width
             (subseq text
                     (first span)
                     cursor))))
         (target (+ current direction)))
    (setf
     (multiline-editor-preferred-column editor)
     column
     (multiline-editor-last-action editor) nil)
    (cond
      ((minusp target)
       (if (or
            (zerop (length text))
            (multiline-editor-history-index editor)
            (zerop cursor))
           (editor-history-previous editor)
           (setf
            (multiline-editor-cursor editor)
            (first span))))
      ((>= target (length spans))
       (if (multiline-editor-history-index editor)
           (editor-history-next editor)
           (setf
            (multiline-editor-cursor editor)
            (second span))))
      (t
       (let ((target-span
               (nth target spans)))
         (setf
          (multiline-editor-cursor editor)
          (position-at-column
           text
           (first target-span)
           (second target-span)
           column)))))
    editor))

(defun editor-move-line-start (editor)
  (setf
   (multiline-editor-cursor editor)
   (line-start-at
    (multiline-editor-text editor)
    (multiline-editor-cursor editor))
   (multiline-editor-last-action editor) nil)
  (editor-reset-navigation-state editor))

(defun editor-move-line-end (editor)
  (setf
   (multiline-editor-cursor editor)
   (line-end-at
    (multiline-editor-text editor)
    (multiline-editor-cursor editor))
   (multiline-editor-last-action editor) nil)
  (editor-reset-navigation-state editor))

(defun editor-atomic-marker-strings (editor)
  (loop for span in (editor-paste-marker-spans editor)
        collect
        (subseq (multiline-editor-text editor)
                (first span) (second span))))

(defun editor-move-word-backward (editor)
  (let* ((text (multiline-editor-text editor))
         (cursor (multiline-editor-cursor editor))
         (start (line-start-at text cursor)))
    (setf
     (multiline-editor-cursor editor)
     (if (= cursor start)
         (if (zerop cursor) 0 (1- cursor))
         (+ start
            (find-word-backward
             (subseq text start
                     (line-end-at text cursor))
             (- cursor start)
             :atomic-segments
             (editor-atomic-marker-strings editor))))
     (multiline-editor-last-action editor) nil)
    (editor-reset-navigation-state editor)))

(defun editor-move-word-forward (editor)
  (let* ((text (multiline-editor-text editor))
         (cursor (multiline-editor-cursor editor))
         (end (line-end-at text cursor))
         (start (line-start-at text cursor)))
    (setf
     (multiline-editor-cursor editor)
     (if (= cursor end)
         (if (= end (length text))
             end
             (1+ end))
         (+ start
            (find-word-forward
             (subseq text start end)
             (- cursor start)
             :atomic-segments
             (editor-atomic-marker-strings editor))))
     (multiline-editor-last-action editor) nil)
    (editor-reset-navigation-state editor)))

(defun editor-kill-range
    (editor start end prepend-p)
  (when (< start end)
    (editor-push-undo editor)
    (let ((was-kill
            (eq :kill
                (multiline-editor-last-action editor)))
          (deleted
            (subseq
             (multiline-editor-text editor)
             start end)))
      (kill-ring-push
       (multiline-editor-kill-ring editor)
       deleted
       :prepend-p prepend-p
       :accumulate-p was-kill)
      (editor-delete-range editor start end)
      (setf
       (multiline-editor-last-action editor) :kill)))
  (editor-exit-history editor)
  (editor-cancel-autocomplete editor)
  (setf (multiline-editor-preferred-column editor) nil)
  editor)

(defun editor-delete-word-backward (editor)
  (let ((cursor (multiline-editor-cursor editor)))
    (when (> cursor 0)
      (let ((last-action
              (multiline-editor-last-action editor)))
        (editor-move-word-backward editor)
        (setf (multiline-editor-last-action editor)
              last-action)
        (let ((start
                (multiline-editor-cursor editor)))
          (setf (multiline-editor-cursor editor)
                cursor)
          (editor-kill-range
           editor start cursor t)))))
  editor)

(defun editor-delete-word-forward (editor)
  (let* ((text (multiline-editor-text editor))
         (cursor (multiline-editor-cursor editor)))
    (when (< cursor (length text))
      (let ((last-action
              (multiline-editor-last-action editor)))
        (editor-move-word-forward editor)
        (let ((end
                (multiline-editor-cursor editor)))
          (setf
           (multiline-editor-cursor editor) cursor
           (multiline-editor-last-action editor)
           last-action)
          (editor-kill-range
           editor cursor end nil)))))
  editor)

(defun editor-delete-line-start (editor)
  (let* ((text (multiline-editor-text editor))
         (cursor (multiline-editor-cursor editor))
         (start (line-start-at text cursor)))
    (if (< start cursor)
        (editor-kill-range editor start cursor t)
        (when (> cursor 0)
          (editor-kill-range
           editor (1- cursor) cursor t))))
  editor)

(defun editor-delete-line-end (editor)
  (let* ((text (multiline-editor-text editor))
         (cursor (multiline-editor-cursor editor))
         (end (line-end-at text cursor)))
    (if (< cursor end)
        (editor-kill-range editor cursor end nil)
        (when (< cursor (length text))
          (editor-kill-range
           editor cursor (1+ cursor) nil))))
  editor)

(defun editor-yank (editor)
  (let ((text
          (kill-ring-peek
           (multiline-editor-kill-ring editor))))
    (when text
      (editor-push-undo editor)
      (let ((start
              (multiline-editor-cursor editor)))
        (editor-insert-raw editor text)
        (setf
         (multiline-editor-last-yank-start editor)
         start
         (multiline-editor-last-yank-end editor)
         (+ start (length text))
         (multiline-editor-last-action editor)
         :yank))))
  editor)

(defun editor-yank-pop (editor)
  (when
      (and
       (eq :yank
           (multiline-editor-last-action editor))
       (> (kill-ring-length
           (multiline-editor-kill-ring editor))
          1)
       (multiline-editor-last-yank-start editor)
       (multiline-editor-last-yank-end editor))
    (editor-push-undo editor)
    (let ((start
            (multiline-editor-last-yank-start editor))
          (end
            (multiline-editor-last-yank-end editor)))
      (editor-replace-range editor start end "")
      (kill-ring-rotate
       (multiline-editor-kill-ring editor))
      (let ((replacement
              (or
               (kill-ring-peek
                (multiline-editor-kill-ring editor))
               "")))
        (editor-replace-range
         editor start start replacement)
        (setf
         (multiline-editor-last-yank-start editor)
         start
         (multiline-editor-last-yank-end editor)
         (+ start (length replacement))
         (multiline-editor-last-action editor)
         :yank))))
  editor)

(defun editor-undo (editor)
  (let ((snapshot
          (undo-stack-pop
           (multiline-editor-undo-stack editor))))
    (when snapshot
      (setf
       (multiline-editor-text editor)
       (getf snapshot :text)
       (multiline-editor-cursor editor)
       (getf snapshot :cursor)
       (multiline-editor-pastes editor)
       (copy-tree (getf snapshot :pastes))
       (multiline-editor-paste-counter editor)
       (getf snapshot :paste-counter)
       (multiline-editor-last-action editor) nil)
      (editor-exit-history editor)
      (editor-cancel-autocomplete editor)
      (editor-reset-navigation-state editor)))
  editor)

(defun decode-pasted-control-keys (text)
  (cl-ppcre:regex-replace-all
   (format nil "~C\\[(\\d+);5u" #\Escape)
   text
   (lambda (target start end match-start match-end
            register-starts register-ends)
     (declare (ignore start end))
     (let ((value
             (parse-integer
              (subseq
               target
               (aref register-starts 0)
               (aref register-ends 0)))))
       (if (or (between-p value 65 90)
               (between-p value 97 122))
           (string
            (code-char
             (if (between-p value 97 122)
                 (- value 96)
                 (- value 64))))
           (subseq target match-start match-end))))))

(defun printable-paste-text (text)
  (remove-if
   (lambda (character)
     (and (not (char= character #\Newline))
          (< (codepoint character) 32)))
   (normalize-editor-text
    (decode-pasted-control-keys text))))

(defun editor-handle-paste (editor text)
  (editor-push-undo editor)
  (editor-exit-history editor)
  (editor-cancel-autocomplete editor)
  (setf (multiline-editor-last-action editor) nil)
  (let* ((filtered
           (printable-paste-text text))
         (line-count
           (1+ (count #\Newline filtered)))
         (large-p
           (or (> line-count 10)
               (> (length filtered) 1000))))
    (when
        (and
         (plusp (length filtered))
         (find (char filtered 0) "/~.")
         (> (multiline-editor-cursor editor) 0)
         (let ((before
                 (char
                  (multiline-editor-text editor)
                  (1-
                   (multiline-editor-cursor editor)))))
           (or (alphanumericp before)
               (char= before #\_))))
      (setf filtered
            (concatenate 'string " " filtered)))
    (if large-p
        (let* ((id
                 (incf
                  (multiline-editor-paste-counter editor)))
               (marker
                 (if (> line-count 10)
                     (format nil
                             "[paste #~D +~D lines]"
                             id line-count)
                     (format nil
                             "[paste #~D ~D chars]"
                             id (length filtered)))))
          (push (cons id filtered)
                (multiline-editor-pastes editor))
          (editor-insert-raw editor marker))
        (editor-insert-raw editor filtered)))
  (editor-reset-navigation-state editor)
  editor)

(defun editor-expanded-text (editor)
  (let ((text (multiline-editor-text editor)))
    (dolist (span
             (reverse
              (editor-paste-marker-spans editor))
             text)
      (let ((payload
              (cdr
               (assoc
                (third span)
                (multiline-editor-pastes editor)))))
        (when payload
          (setf text
                (concatenate
                 'string
                 (subseq text 0 (first span))
                 payload
                 (subseq text (second span)))))))))

(defun editor-clear (editor)
  (setf
   (multiline-editor-text editor) ""
   (multiline-editor-cursor editor) 0
   (multiline-editor-history-index editor) nil
   (multiline-editor-history-draft editor) nil
   (multiline-editor-pastes editor) nil
   (multiline-editor-paste-counter editor) 0
   (multiline-editor-last-action editor) nil)
  (undo-stack-clear
   (multiline-editor-undo-stack editor))
  (editor-cancel-autocomplete editor)
  (editor-reset-navigation-state editor)
  editor)

(defun editor-jump-to-character
    (editor text direction)
  (when (plusp (length text))
    (let* ((needle (subseq text 0 1))
           (source (multiline-editor-text editor))
           (cursor (multiline-editor-cursor editor))
           (position
             (if (eq direction :forward)
                 (search needle source
                         :start2
                         (min (length source)
                              (1+ cursor)))
                 (search needle source
                         :end2 cursor
                         :from-end t))))
      (when position
        (setf
         (multiline-editor-cursor editor)
         position))))
  (setf
   (multiline-editor-jump-mode editor) nil
   (multiline-editor-last-action editor) nil)
  (editor-reset-navigation-state editor)
  editor)

(defun editor-refresh-autocomplete
    (editor &key force-p)
  (let ((provider
          (multiline-editor-autocomplete-provider editor)))
    (unless provider
      (return-from editor-refresh-autocomplete
        (editor-cancel-autocomplete editor)))
    (multiple-value-bind (line column)
        (editor-cursor editor)
      (let ((suggestions
              (autocomplete-get-suggestions
               provider
               (editor-lines editor)
               line column
               :force-p force-p)))
        (if suggestions
            (setf
             (multiline-editor-autocomplete-suggestions
              editor)
             (autocomplete-suggestions-items
              suggestions)
             (multiline-editor-autocomplete-prefix
              editor)
             (autocomplete-suggestions-prefix
              suggestions)
             (multiline-editor-autocomplete-selected
              editor)
             0)
            (editor-cancel-autocomplete editor)))))
  editor)

(defun editor-set-autocomplete-provider
    (editor provider)
  (editor-cancel-autocomplete editor)
  (setf
   (multiline-editor-autocomplete-provider editor)
   provider)
  editor)

(defun editor-autocomplete-visible-p (editor)
  (not
   (null
    (multiline-editor-autocomplete-suggestions
     editor))))

(defun editor-autocomplete-items (editor)
  (copy-list
   (multiline-editor-autocomplete-suggestions
    editor)))

(defun editor-apply-autocomplete (editor)
  (let* ((items
           (multiline-editor-autocomplete-suggestions
            editor))
         (item
           (and items
                (nth
                 (multiline-editor-autocomplete-selected
                  editor)
                 items)))
         (prefix
           (multiline-editor-autocomplete-prefix editor)))
    (when (and item prefix)
      (editor-push-undo editor)
      (multiple-value-bind
            (line column)
          (editor-cursor editor)
        (multiple-value-bind
              (new-lines new-line new-column)
            (autocomplete-apply
             (editor-lines editor)
             line column item prefix)
          (setf
           (multiline-editor-text editor)
           (format nil "~{~A~^~%~}" new-lines)
           (multiline-editor-cursor editor)
           (editor-position-for-line-column
            (format nil "~{~A~^~%~}" new-lines)
            new-line new-column)
           (multiline-editor-last-action editor)
           nil)
          (editor-cancel-autocomplete editor)
          (editor-reset-navigation-state editor)
          t)))))

(defun editor-handle-event (editor event)
  (let ((kind (input-event-kind event))
        (text (or (input-event-text event) "")))
    (when (multiline-editor-jump-mode editor)
      (cond
        ((member kind '(:jump-forward :jump-backward))
         (setf (multiline-editor-jump-mode editor) nil)
         (return-from editor-handle-event
           (values nil nil)))
        ((and (eq kind :text)
              (plusp (length text)))
         (editor-jump-to-character
          editor text
          (multiline-editor-jump-mode editor))
         (return-from editor-handle-event
           (values nil nil)))
        (t
         (setf (multiline-editor-jump-mode editor)
               nil))))
    (when (editor-autocomplete-visible-p editor)
      (case kind
        (:escape
         (editor-cancel-autocomplete editor)
         (return-from editor-handle-event
           (values nil nil)))
        (:up
         (setf
          (multiline-editor-autocomplete-selected editor)
          (mod
           (1-
            (multiline-editor-autocomplete-selected
             editor))
           (length
            (multiline-editor-autocomplete-suggestions
             editor))))
         (return-from editor-handle-event
           (values nil nil)))
        (:down
         (setf
          (multiline-editor-autocomplete-selected editor)
          (mod
           (1+
            (multiline-editor-autocomplete-selected
             editor))
           (length
            (multiline-editor-autocomplete-suggestions
             editor))))
         (return-from editor-handle-event
           (values nil nil)))
        (:tab
         (editor-apply-autocomplete editor)
         (return-from editor-handle-event
           (values nil nil)))
        (:enter
         (let ((slash-command-p
                 (string-prefix-p
                  "/"
                  (or
                   (multiline-editor-autocomplete-prefix
                    editor)
                   ""))))
           (when (editor-apply-autocomplete editor)
             (unless slash-command-p
               (return-from editor-handle-event
                 (values nil nil))))))))
    (case kind
      (:text
       (editor-insert editor text))
      (:paste
       (editor-handle-paste editor text))
      (:newline
       (editor-push-undo editor)
       (editor-exit-history editor)
       (editor-cancel-autocomplete editor)
       (setf (multiline-editor-last-action editor) nil)
       (editor-insert-raw editor (string #\Newline))
       (editor-reset-navigation-state editor))
      (:tab
       (editor-refresh-autocomplete editor :force-p t)
       (when
           (= 1
              (length
               (multiline-editor-autocomplete-suggestions
                editor)))
         (editor-apply-autocomplete editor)))
      (:left
       (setf
        (multiline-editor-cursor editor)
        (editor-previous-boundary editor)
        (multiline-editor-last-action editor) nil)
       (editor-reset-navigation-state editor))
      (:right
       (setf
        (multiline-editor-cursor editor)
        (editor-next-boundary editor)
        (multiline-editor-last-action editor) nil)
       (editor-reset-navigation-state editor))
      (:line-start (editor-move-line-start editor))
      (:home (editor-move-line-start editor))
      (:line-end (editor-move-line-end editor))
      (:end (editor-move-line-end editor))
      (:word-left (editor-move-word-backward editor))
      (:word-right (editor-move-word-forward editor))
      (:up (editor-move-vertical editor -1))
      (:down (editor-move-vertical editor 1))
      (:backspace (editor-delete-backward editor))
      (:delete (editor-delete-forward editor))
      (:delete-word-backward
       (editor-delete-word-backward editor))
      (:delete-word-forward
       (editor-delete-word-forward editor))
      (:delete-line-start
       (editor-delete-line-start editor))
      (:delete-line-end
       (editor-delete-line-end editor))
      (:yank (editor-yank editor))
      (:yank-pop (editor-yank-pop editor))
      (:undo (editor-undo editor))
      (:jump-forward
       (setf (multiline-editor-jump-mode editor)
             :forward))
      (:jump-backward
       (setf (multiline-editor-jump-mode editor)
             :backward))
      (:clear (editor-clear editor))
      (:enter
       (let* ((source
                (multiline-editor-text editor))
              (cursor
                (multiline-editor-cursor editor)))
         (if (and (> cursor 0)
                  (char=
                   (char source (1- cursor))
                   #\\))
             (progn
               (editor-push-undo editor)
               (editor-replace-range
                editor (1- cursor) cursor
                (string #\Newline))
               (setf
                (multiline-editor-last-action editor)
                nil)
               (editor-reset-navigation-state editor))
             (let ((expanded
                     (string-trim
                      '(#\Space #\Tab #\Newline #\Return)
                      (editor-expanded-text editor))))
               (unless (zerop (length expanded))
                 (editor-add-history editor expanded)
                 (editor-clear editor)
                 (return-from editor-handle-event
                   (values :submit expanded))))))))
    (when
        (and
         (member kind
                 '(:text :backspace :delete))
         (multiline-editor-autocomplete-provider editor))
      (editor-refresh-autocomplete editor))
    (values nil nil)))

(defun editor-word-wrap-line-spans
    (line maximum-width)
  (when (or (zerop (length line))
            (<= maximum-width 0))
    (return-from editor-word-wrap-line-spans
      (list (list "" 0 0))))
  (when (<= (visible-width line)
            maximum-width)
    (return-from editor-word-wrap-line-spans
      (list (list line 0 (length line)))))
  (let ((segments nil)
        (position 0))
    (dolist (cluster (grapheme-clusters line))
      (push (list cluster position
                  (+ position (length cluster)))
            segments)
      (incf position (length cluster)))
    (setf segments (nreverse segments))
    (let ((chunks nil)
          (chunk-start 0)
          (current-width 0)
          (wrap-index nil)
          (wrap-width 0))
      (loop for segment in segments
            for index from 0
            for grapheme = (first segment)
            for start = (second segment)
            for width = (grapheme-width grapheme)
            for whitespace-p =
            (every #'navigation-whitespace-p grapheme)
            do
            (when (> (+ current-width width)
                     maximum-width)
              (cond
                ((and wrap-index
                      (<=
                       (+ (- current-width wrap-width)
                          width)
                       maximum-width))
                 (push
                  (list
                   (subseq line chunk-start wrap-index)
                   chunk-start wrap-index)
                  chunks)
                 (setf
                  chunk-start wrap-index
                  current-width
                  (- current-width wrap-width)))
                ((< chunk-start start)
                 (push
                  (list
                   (subseq line chunk-start start)
                   chunk-start start)
                  chunks)
                 (setf
                  chunk-start start
                  current-width 0)))
              (setf wrap-index nil))
            (incf current-width width)
            (let ((next (nth (1+ index) segments)))
              (when
                  (and next
                       (or
                        (and whitespace-p
                             (not
                              (every
                               #'navigation-whitespace-p
                               (first next))))
                        (and
                         (not whitespace-p)
                         (not
                          (every
                           #'navigation-whitespace-p
                           (first next)))
                         (or
                          (some #'navigation-cjk-p
                                grapheme)
                          (some #'navigation-cjk-p
                                (first next))))))
                (setf
                 wrap-index (second next)
                 wrap-width current-width))))
      (push
       (list
        (subseq line chunk-start)
        chunk-start (length line))
       chunks)
      (nreverse chunks))))

(defun render-editor (editor width)
  (let* ((prompt (multiline-editor-prompt editor))
         (prompt-width (visible-width prompt))
         (content-width
           (max 1 (- width prompt-width)))
         (continuation
           (make-string prompt-width
                        :initial-element #\Space))
         (text (multiline-editor-text editor))
         (cursor (multiline-editor-cursor editor))
         (logical-lines (split-editor-lines text))
         (lines nil)
         (cursor-row nil)
         (cursor-column nil)
         (absolute-start 0)
         (row 0))
    (setf
     (multiline-editor-last-render-width editor)
     content-width)
    (loop for logical-line in logical-lines
          for logical-index from 0
          do
          (let ((chunks
                  (editor-word-wrap-line-spans
                   logical-line content-width)))
            (loop for chunk in chunks
                  for chunk-index from 0
                  for chunk-text = (first chunk)
                  for chunk-start = (second chunk)
                  for chunk-end = (third chunk)
                  for line-prefix =
                  (if (and (zerop logical-index)
                           (zerop chunk-index))
                      prompt continuation)
                  do
                  (push
                   (concatenate 'string
                                line-prefix chunk-text)
                   lines)
                  (when
                      (and
                       (null cursor-row)
                       (or
                        (and
                         (>= cursor
                             (+ absolute-start
                                chunk-start))
                         (< cursor
                            (+ absolute-start
                               chunk-end)))
                        (and
                         (= cursor
                            (+ absolute-start
                               chunk-end))
                         (= chunk-index
                            (1-
                             (length chunks))))))
                    (setf
                     cursor-row row
                     cursor-column
                     (+ prompt-width
                        (visible-width
                         (subseq
                          logical-line
                          chunk-start
                          (min
                           chunk-end
                           (- cursor absolute-start)))))))
                  (incf row)))
          (incf absolute-start
                (+ (length logical-line) 1)))
    (let ((result (nreverse lines)))
      (when (editor-autocomplete-visible-p editor)
        (loop for item
              in (multiline-editor-autocomplete-suggestions
                  editor)
              for index from 0
              repeat 5
              for description =
              (autocomplete-item-description item)
              for line =
              (format nil "~A ~A~@[ — ~A~]"
                      (if
                          (= index
                             (multiline-editor-autocomplete-selected
                              editor))
                          "›"
                          " ")
                      (autocomplete-item-label item)
                      description)
              do
              (setf
               result
               (nconc
                result
                (list
                 (truncate-to-width
                  line width "" nil))))))
      (values
       result
       (or cursor-row
           (max 0 (1- (length result))))
       (or cursor-column prompt-width)))))
