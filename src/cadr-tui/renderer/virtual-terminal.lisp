(in-package #:cadr-tui)

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
                  (virtual-erase-line terminal))
                 (#\A
                  (decf
                   (virtual-cursor-row terminal)
                   (or (first numbers) 1))
                  (setf
                   (virtual-cursor-row terminal)
                   (max 0
                        (virtual-cursor-row
                         terminal))))
                 (#\B
                  (incf
                   (virtual-cursor-row terminal)
                   (or (first numbers) 1)))
                 (#\G
                  (setf
                   (virtual-cursor-column terminal)
                   (max
                    0
                    (1-
                     (or (first numbers)
                         1)))))))
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
