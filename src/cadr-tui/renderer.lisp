(in-package #:cadr-tui)

(defclass terminal ()
  ((columns
    :initarg :columns
    :initform 80
    :accessor terminal-columns)
   (rows
    :initarg :rows
    :initform 24
    :accessor terminal-rows)))

(defgeneric terminal-start (terminal))
(defgeneric terminal-stop (terminal))
(defgeneric terminal-write (terminal text))
(defgeneric terminal-read-input (terminal))
(defgeneric terminal-resized-p (terminal))

(defmethod terminal-start ((terminal terminal))
  (declare (ignore terminal))
  nil)

(defmethod terminal-stop ((terminal terminal))
  (declare (ignore terminal))
  nil)

(defmethod terminal-write ((terminal terminal) text)
  (declare (ignore terminal text))
  nil)

(defmethod terminal-read-input ((terminal terminal))
  (declare (ignore terminal))
  "")

(defmethod terminal-resized-p ((terminal terminal))
  (declare (ignore terminal))
  nil)

(defclass virtual-terminal (terminal)
  ((screen :accessor virtual-terminal-screen)
   (cursor-row :initform 0 :accessor virtual-cursor-row)
   (cursor-column :initform 0 :accessor virtual-cursor-column)
   (writes :initform nil :accessor virtual-writes)))

(defmethod initialize-instance :after ((terminal virtual-terminal) &key)
  (setf
   (virtual-terminal-screen terminal)
   (make-array
    (terminal-rows terminal)
    :initial-element "")))

(defun make-virtual-terminal (&key (columns 80) (rows 24))
  (make-instance
   'virtual-terminal
   :columns columns
   :rows rows))

(defun ensure-virtual-screen (terminal)
  (when
      (/= (length (virtual-terminal-screen terminal))
          (terminal-rows terminal))
    (let ((screen
            (make-array
             (terminal-rows terminal)
             :initial-element "")))
      (loop for index below
            (min
             (length screen)
             (length
              (virtual-terminal-screen terminal)))
            do
            (setf
             (aref screen index)
             (aref
              (virtual-terminal-screen terminal)
              index)))
      (setf (virtual-terminal-screen terminal) screen))))

(defun csi-end-position (text start)
  (loop for index from (+ start 2) below (length text)
        for value = (codepoint (char text index))
        when (between-p value #x40 #x7e)
          do (return index)))

(defun parse-csi-numbers (parameters)
  (if (zerop (length parameters))
      nil
      (mapcar
       (lambda (part)
         (or (parse-integer part :junk-allowed t) 0))
       (uiop:split-string
        (string-left-trim '(#\?) parameters)
        :separator '(#\;)))))

(defun virtual-erase-line (terminal)
  (let ((row (virtual-cursor-row terminal)))
    (when (< row (length
                  (virtual-terminal-screen terminal)))
      (setf
       (aref
        (virtual-terminal-screen terminal)
        row)
       ""))))

(defun virtual-clear (terminal)
  (fill (virtual-terminal-screen terminal) "")
  (setf
   (virtual-cursor-row terminal) 0
   (virtual-cursor-column terminal) 0))

(defun virtual-write-character (terminal character)
  (let ((row (virtual-cursor-row terminal)))
    (when (< row (length
                  (virtual-terminal-screen terminal)))
      (setf
       (aref
        (virtual-terminal-screen terminal)
        row)
       (concatenate
        'string
        (aref
         (virtual-terminal-screen terminal)
         row)
        (string character)))
      (incf
       (virtual-cursor-column terminal)
       (visible-width (string character))))))

(defun apply-virtual-output (terminal text)
  (ensure-virtual-screen terminal)
  (loop with index = 0
        while (< index (length text))
        for character = (char text index)
        do
        (cond
          ((and (char= character #\Escape)
                (< (1+ index) (length text))
                (char= (char text (1+ index)) #\[))
           (let ((end (csi-end-position text index)))
             (unless end
               (return))
             (let* ((command (char text end))
                    (parameters
                      (subseq text (+ index 2) end))
                    (numbers
                      (parse-csi-numbers parameters)))
               (case command
                 (#\H
                  (setf
                   (virtual-cursor-row terminal)
                   (max 0 (1-
                           (or (first numbers) 1)))
                   (virtual-cursor-column terminal)
                   (max 0 (1-
                           (or (second numbers) 1)))))
                 (#\J
                  (when (= (or (first numbers) 0) 2)
                    (virtual-clear terminal)))
                 (#\K
                  (virtual-erase-line terminal))))
             (setf index (1+ end))))
          ((char= character #\Newline)
           (incf (virtual-cursor-row terminal))
           (setf (virtual-cursor-column terminal) 0)
           (incf index))
          ((char= character #\Return)
           (setf (virtual-cursor-column terminal) 0)
           (incf index))
          (t
           (virtual-write-character terminal character)
           (incf index)))))

(defmethod terminal-write ((terminal virtual-terminal) text)
  (push text (virtual-writes terminal))
  (apply-virtual-output terminal text)
  text)

(defun virtual-terminal-snapshot (terminal)
  (ensure-virtual-screen terminal)
  (coerce
   (virtual-terminal-screen terminal)
   'list))

(defstruct (terminal-renderer
            (:constructor %make-terminal-renderer))
  terminal
  (previous-lines nil :type list)
  (previous-image-ids nil :type list)
  (previous-width 0 :type (integer 0 *))
  (invalid-p t :type boolean))

(defun make-terminal-renderer (terminal)
  (%make-terminal-renderer :terminal terminal))

(defun invalidate-renderer (renderer)
  (setf (terminal-renderer-invalid-p renderer) t)
  renderer)

(defun clipped-frame-lines (terminal lines)
  (loop for line in lines
        repeat (terminal-rows terminal)
        collect
        (multiple-value-bind (prefix width)
            (slice-to-width line
                            (terminal-columns terminal))
          (declare (ignore width))
          (concatenate
           'string prefix
           (format nil "~C[0m" #\Escape)))))

(defun kitty-parameter-integer
    (line parameter)
  (let ((position
          (search parameter line)))
    (when position
      (parse-integer
       line
       :start (+ position
                 (length parameter))
       :junk-allowed t))))

(defun kitty-image-id (line)
  (when (search (format nil "~C_G" #\Escape)
                line)
    (kitty-parameter-integer line "i=")))

(defun kitty-image-rows (line)
  (if (search (format nil "~C_G" #\Escape)
              line)
      (or (kitty-parameter-integer line "r=")
          1)
      1))

(defun frame-image-ids (lines)
  (remove-duplicates
   (remove nil
           (mapcar #'kitty-image-id lines))
   :test #'=))

(defun frame-image-change-p (current previous)
  (loop for row below
        (max (length current)
             (length previous))
        for new =
        (if (< row (length current))
            (nth row current)
            "")
        for old =
        (if (< row (length previous))
            (nth row previous)
            "")
        thereis
        (and
         (not (string= new old))
         (or (image-line-p new)
             (image-line-p old)))))

(defun write-kitty-deletions (stream ids)
  (dolist (id ids)
    (write-string
     (delete-kitty-image id)
     stream)))

(defun render-frame-line
    (stream lines row line)
  (ansi-position stream row 0)
  (format stream "~C[2K" #\Escape)
  (let ((reserved
          (min
           (kitty-image-rows line)
           (- (length lines) row))))
    (when (> reserved 1)
      (loop for offset from 1 below reserved
            do
            (ansi-position stream
                           (+ row offset) 0)
            (format stream "~C[2K" #\Escape))
      (ansi-position stream row 0))
    (write-string line stream)))

(defun ansi-position (stream row column)
  (format stream "~C[~D;~DH"
          #\Escape
          (1+ row)
          (1+ column)))

(defun render-frame
    (renderer lines &key
                      (cursor-row
                        (max 0 (1- (length lines))))
                      (cursor-column 0))
  (let* ((terminal
           (terminal-renderer-terminal renderer))
         (width (terminal-columns terminal))
         (current
           (clipped-frame-lines terminal lines))
         (previous
           (terminal-renderer-previous-lines renderer))
         (full-p
           (or (terminal-renderer-invalid-p renderer)
               (/= width
                   (terminal-renderer-previous-width renderer))))
         (row-count
           (max (length current)
                (length previous)))
         (image-change-p
           (frame-image-change-p
            current previous))
         (previous-image-ids
           (terminal-renderer-previous-image-ids
            renderer))
         (output
           (with-output-to-string (stream)
             (format stream "~C[?2026h~C[?25l"
                     #\Escape #\Escape)
             (when (or full-p image-change-p)
               (write-kitty-deletions
                stream previous-image-ids))
             (when full-p
               (format stream "~C[2J~C[H"
                       #\Escape #\Escape))
             (loop for row below row-count
                   for new =
                   (if (< row (length current))
                       (nth row current)
                       "")
                   for old =
                   (if (< row (length previous))
                       (nth row previous)
                       nil)
                   when (or full-p
                            (and image-change-p
                                 (image-line-p new))
                            (null old)
                            (not (string= new old)))
                     do
                     (render-frame-line
                      stream current row new))
             (ansi-position
              stream
              (min (max 0 cursor-row)
                   (max 0 (1- (terminal-rows terminal))))
              (min (max 0 cursor-column)
                   (max 0 (1- width))))
             (format stream "~C[?25h~C[?2026l"
                     #\Escape #\Escape))))
    (terminal-write terminal output)
    (setf
     (terminal-renderer-previous-lines renderer)
     (copy-list current)
     (terminal-renderer-previous-image-ids
      renderer)
     (frame-image-ids current)
     (terminal-renderer-previous-width renderer) width
     (terminal-renderer-invalid-p renderer) nil)
    output))
