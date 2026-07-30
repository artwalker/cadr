(in-package #:pi-tui)

(defstruct (multiline-editor
            (:constructor %make-multiline-editor))
  (text "" :type string)
  (cursor 0 :type (integer 0 *))
  (prompt "› " :type string)
  (history nil :type list)
  (history-limit 100 :type (integer 1 *))
  history-index
  history-draft)

(defun make-multiline-editor (&key (text "") (prompt "› ")
                                   (history-limit 100))
  (%make-multiline-editor
   :text text
   :cursor (length text)
   :prompt prompt
   :history-limit history-limit))

(defun editor-text (editor)
  (multiline-editor-text editor))

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

(defun editor-insert (editor text)
  (let* ((old (multiline-editor-text editor))
         (cursor (multiline-editor-cursor editor)))
    (setf
     (multiline-editor-text editor)
     (concatenate 'string
                  (subseq old 0 cursor)
                  text
                  (subseq old cursor))
     (multiline-editor-cursor editor)
     (+ cursor (length text))
     (multiline-editor-history-index editor) nil))
  editor)

(defun editor-delete-backward (editor)
  (let ((cursor (multiline-editor-cursor editor)))
    (when (> cursor 0)
      (let* ((text (multiline-editor-text editor))
             (start (previous-cluster-boundary text cursor)))
        (setf
         (multiline-editor-text editor)
         (concatenate 'string
                      (subseq text 0 start)
                      (subseq text cursor))
         (multiline-editor-cursor editor) start))))
  editor)

(defun editor-delete-forward (editor)
  (let* ((text (multiline-editor-text editor))
         (cursor (multiline-editor-cursor editor)))
    (when (< cursor (length text))
      (let ((end (next-cluster-boundary text cursor)))
        (setf
         (multiline-editor-text editor)
         (concatenate 'string
                      (subseq text 0 cursor)
                      (subseq text end))))))
  editor)

(defun line-start-at (text cursor)
  (let ((newline (position #\Newline text :end cursor :from-end t)))
    (if newline (1+ newline) 0)))

(defun line-end-at (text cursor)
  (or (position #\Newline text :start cursor)
      (length text)))

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

(defun editor-move-vertical (editor direction)
  (let* ((text (multiline-editor-text editor))
         (cursor (multiline-editor-cursor editor))
         (start (line-start-at text cursor))
         (end (line-end-at text cursor))
         (column (visible-width (subseq text start cursor))))
    (declare (ignore end))
    (cond
      ((minusp direction)
       (if (zerop start)
           (editor-history-previous editor)
           (let* ((previous-end (1- start))
                  (previous-start
                    (line-start-at text previous-end)))
             (setf
              (multiline-editor-cursor editor)
              (position-at-column
               text previous-start previous-end column)))))
      (t
       (let ((current-end (line-end-at text cursor)))
         (if (= current-end (length text))
             (editor-history-next editor)
             (let* ((next-start (1+ current-end))
                    (next-end
                      (line-end-at text next-start)))
               (setf
                (multiline-editor-cursor editor)
                (position-at-column
                 text next-start next-end column))))))))
  editor)

(defun editor-history-previous (editor)
  (let ((history (multiline-editor-history editor)))
    (when history
      (unless (multiline-editor-history-index editor)
        (setf
         (multiline-editor-history-draft editor)
         (multiline-editor-text editor)
         (multiline-editor-history-index editor) 0))
      (setf
       (multiline-editor-history-index editor)
       (min (1- (length history))
            (multiline-editor-history-index editor)))
      (let ((text
              (nth (multiline-editor-history-index editor)
                   history)))
        (setf (multiline-editor-text editor) text
              (multiline-editor-cursor editor)
              (length text)))))
  editor)

(defun editor-history-next (editor)
  (let ((index (multiline-editor-history-index editor)))
    (when index
      (if (zerop index)
          (let ((draft
                  (or
                   (multiline-editor-history-draft editor)
                   "")))
            (setf
             (multiline-editor-text editor) draft
             (multiline-editor-cursor editor) (length draft)
             (multiline-editor-history-index editor) nil))
          (progn
            (decf (multiline-editor-history-index editor))
            (let ((text
                    (nth
                     (multiline-editor-history-index editor)
                     (multiline-editor-history editor))))
              (setf
               (multiline-editor-text editor) text
               (multiline-editor-cursor editor)
               (length text)))))))
  editor)

(defun editor-record-history (editor text)
  (unless (or (zerop (length text))
              (and (multiline-editor-history editor)
                   (string=
                    text
                    (first
                     (multiline-editor-history editor)))))
    (push text (multiline-editor-history editor))
    (when (> (length (multiline-editor-history editor))
             (multiline-editor-history-limit editor))
      (setf
       (multiline-editor-history editor)
       (subseq
        (multiline-editor-history editor)
        0
        (multiline-editor-history-limit editor))))))

(defun editor-clear (editor)
  (setf
   (multiline-editor-text editor) ""
   (multiline-editor-cursor editor) 0
   (multiline-editor-history-index editor) nil
   (multiline-editor-history-draft editor) nil)
  editor)

(defun editor-handle-event (editor event)
  (case (input-event-kind event)
    (:text
     (editor-insert editor (or (input-event-text event) "")))
    (:paste
     (editor-insert editor
                    (normalize-paste
                     (or (input-event-text event) ""))))
    (:newline
     (editor-insert editor (string #\Newline)))
    (:tab
     (editor-insert editor (string #\Tab)))
    (:left
     (setf
      (multiline-editor-cursor editor)
      (previous-cluster-boundary
       (multiline-editor-text editor)
       (multiline-editor-cursor editor))))
    (:right
     (setf
      (multiline-editor-cursor editor)
      (next-cluster-boundary
       (multiline-editor-text editor)
       (multiline-editor-cursor editor))))
    (:home
     (setf
      (multiline-editor-cursor editor)
      (line-start-at
       (multiline-editor-text editor)
       (multiline-editor-cursor editor))))
    (:end
     (setf
      (multiline-editor-cursor editor)
      (line-end-at
       (multiline-editor-text editor)
       (multiline-editor-cursor editor))))
    (:up (editor-move-vertical editor -1))
    (:down (editor-move-vertical editor 1))
    (:backspace (editor-delete-backward editor))
    (:delete (editor-delete-forward editor))
    (:clear (editor-clear editor))
    (:enter
     (let ((text (multiline-editor-text editor)))
       (unless
           (zerop
            (length
             (string-trim
              '(#\Space #\Tab #\Newline #\Return)
              text)))
         (editor-record-history editor text)
         (editor-clear editor)
         (return-from editor-handle-event
           (values :submit text))))))
  (values nil nil))

(defun render-editor (editor width)
  (let* ((prompt (multiline-editor-prompt editor))
         (prompt-width (visible-width prompt))
         (continuation
           (make-string prompt-width :initial-element #\Space))
         (text (multiline-editor-text editor))
         (cursor (multiline-editor-cursor editor))
         (lines (list prompt))
         (row 0)
         (column prompt-width)
         (cursor-row nil)
         (cursor-column nil)
         (position 0))
    (labels ((current-line ()
               (car (last lines)))
             ((setf current-line) (value)
               (setf (car (last lines)) value))
             (new-line ()
               (setf lines
                     (nconc lines (list continuation)))
               (incf row)
               (setf column prompt-width))
             (mark-cursor ()
               (unless cursor-row
                 (setf cursor-row row
                       cursor-column column))))
      (dolist (cluster (grapheme-clusters text))
        (when (= position cursor)
          (mark-cursor))
        (cond
          ((string= cluster (string #\Newline))
           (new-line))
          (t
           (let ((cluster-width (grapheme-width cluster)))
             (when (and (> column prompt-width)
                        (> (+ column cluster-width) width))
               (new-line))
             (setf
              (current-line)
              (concatenate
               'string
               (current-line)
               (if (string= cluster (string #\Tab))
                   "   "
                   cluster)))
             (incf column cluster-width))))
        (incf position (length cluster)))
      (when (= position cursor)
        (mark-cursor))
      (values lines
              (or cursor-row row)
              (or cursor-column column)))))
