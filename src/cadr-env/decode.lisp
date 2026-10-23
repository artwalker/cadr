(in-package #:cadr-env)

(defstruct utf8-decoder
  (bom t)
  (pending nil)
  (started nil))

(defun utf8-expected (lead)
  (cond ((< lead #x80) 1)
        ((< lead #xc2) nil)
        ((< lead #xe0) 2)
        ((< lead #xf0) 3)
        ((< lead #xf5) 4)
        (t nil)))

(defun utf8-continuation-p (byte)
  (<= #x80 byte #xbf))

(defun utf8-valid-prefix (input index width)
  (loop for offset from 1 below width
        unless (utf8-continuation-p (aref input (+ index offset)))
          do (return-from utf8-valid-prefix offset))
  width)

(defun utf8-decode-chunk (decoder octets last)
  (let ((input (if (utf8-decoder-pending decoder)
                   (concatenate '(vector (unsigned-byte 8))
                                (utf8-decoder-pending decoder) octets)
                   octets))
        (text (make-string-output-stream)))
    (setf (utf8-decoder-pending decoder) nil)
    (let ((index 0)
          (end (length input)))
      (loop while (< index end)
            do (let ((lead (aref input index)))
                 (cond
                   ((and (utf8-decoder-bom decoder)
                         (not (utf8-decoder-started decoder))
                         (<= (+ index 3) end)
                         (= lead #xef)
                         (= (aref input (+ index 1)) #xbb)
                         (= (aref input (+ index 2)) #xbf))
                    (setf (utf8-decoder-bom decoder) nil
                          (utf8-decoder-started decoder) t)
                    (incf index 3))
                   (t
                    (let ((width (utf8-expected lead)))
                      (cond
                        ((null width)
                         (write-char #\ufffd text)
                         (setf (utf8-decoder-started decoder) t
                               (utf8-decoder-bom decoder) nil)
                         (incf index))
                        ((> (+ index width) end)
                         (if last
                             (progn
                               (write-char #\ufffd text)
                               (setf index end))
                             (progn
                               (setf (utf8-decoder-pending decoder)
                                     (subseq input index))
                               (setf index end))))
                        (t
                         (let ((taken (utf8-valid-prefix input index width)))
                           (cond
                             ((= taken width)
                              (write-string
                               (sb-ext:octets-to-string
                                input :external-format :utf-8
                                :start index :end (+ index width))
                               text)
                              (setf (utf8-decoder-started decoder) t
                                    (utf8-decoder-bom decoder) nil)
                              (incf index width))
                             (t
                              (write-char #\ufffd text)
                              (setf (utf8-decoder-started decoder) t
                                    (utf8-decoder-bom decoder) nil)
                              (incf index taken)))))))))))
      (when (and last (utf8-decoder-pending decoder))
        (write-char #\ufffd text)
        (setf (utf8-decoder-pending decoder) nil)))
    (get-output-stream-string text)))

(defun utf8-decode (decoder octets &key last)
  (utf8-decode-chunk decoder (coerce octets '(vector (unsigned-byte 8))) last))

(defstruct line-scanner
  start-line
  end-line
  (position 0)
  (newlines 0)
  (line-start 0)
  (start nil)
  (end nil)
  (first-line-end nil)
  (last-line-start nil)
  (selected-bytes 0)
  (first-line-bytes 0)
  (selection nil)
  (first-line nil)
  (head (make-array 0 :element-type '(unsigned-byte 8) :adjustable t :fill-pointer 0))
  (bom nil))

(defun make-line-scan (start-line &optional end-line)
  (let ((scanner (make-line-scanner :start-line start-line :end-line end-line)))
    (when (zerop start-line)
      (line-scan-begin scanner 0))
    scanner))

(defun line-scan-last-p (scanner line)
  (and (line-scanner-end-line scanner)
       (= (1+ line) (line-scanner-end-line scanner))))

(defun line-scan-begin (scanner start)
  (setf (line-scanner-start scanner) start)
  (when (line-scan-last-p scanner (line-scanner-start-line scanner))
    (setf (line-scanner-last-line-start scanner) start))
  (setf (line-scanner-selection scanner) (make-utf8-decoder :bom nil)
        (line-scanner-first-line scanner) (make-utf8-decoder :bom nil)))

(defun decoded-size (decoder octets last)
  (length (utf8-bytes (utf8-decode decoder octets :last last))))

(defun line-scan-feed (scanner octets base from to)
  (when (and (line-scanner-bom scanner) (< (+ base from) 3))
    (setf from (min to (- 3 base))))
  (when (< from to)
    (let ((slice (subseq octets from to)))
      (when (line-scanner-selection scanner)
        (incf (line-scanner-selected-bytes scanner)
              (decoded-size (line-scanner-selection scanner) slice nil)))
      (when (line-scanner-first-line scanner)
        (incf (line-scanner-first-line-bytes scanner)
              (decoded-size (line-scanner-first-line scanner) slice nil))))))

(defun line-scan-end-first (scanner position)
  (setf (line-scanner-first-line-end scanner) position)
  (when (line-scanner-first-line scanner)
    (incf (line-scanner-first-line-bytes scanner)
          (decoded-size (line-scanner-first-line scanner) #() t))
    (setf (line-scanner-first-line scanner) nil)))

(defun line-scan-end-selection (scanner position)
  (setf (line-scanner-end scanner) position)
  (when (line-scanner-selection scanner)
    (incf (line-scanner-selected-bytes scanner)
          (decoded-size (line-scanner-selection scanner) #() t))
    (setf (line-scanner-selection scanner) nil)))

(defun line-scan-process (scanner octets)
  (let ((base (line-scanner-position scanner))
        (from 0)
        (index 0)
        (end (length octets)))
    (loop
      (let ((found (position 10 octets :start index)))
        (unless found (return))
        (line-scan-feed scanner octets base from found)
        (let ((line (line-scanner-newlines scanner))
              (position (+ base found)))
          (when (= line (line-scanner-start-line scanner))
            (line-scan-end-first scanner position))
          (when (line-scan-last-p scanner line)
            (line-scan-end-selection scanner position))
          (line-scan-feed scanner octets base found (1+ found))
          (setf from (1+ found))
          (incf (line-scanner-newlines scanner))
          (setf (line-scanner-line-start scanner) (1+ position))
          (when (= (line-scanner-newlines scanner) (line-scanner-start-line scanner))
            (line-scan-begin scanner (line-scanner-line-start scanner)))
          (when (line-scan-last-p scanner (line-scanner-newlines scanner))
            (setf (line-scanner-last-line-start scanner)
                  (line-scanner-line-start scanner)))
          (setf index (1+ found)))))
    (line-scan-feed scanner octets base from end)
    (incf (line-scanner-position scanner) end)))

(defun line-scan-release-head (scanner)
  (let ((head (line-scanner-head scanner)))
    (setf (line-scanner-head scanner) nil
          (line-scanner-bom scanner)
          (and (>= (length head) 3)
               (= (aref head 0) #xef)
               (= (aref head 1) #xbb)
               (= (aref head 2) #xbf)))
    (line-scan-process scanner head)))

(defun line-scan-push (scanner octets)
  (when (line-scanner-head scanner)
    (let* ((head (line-scanner-head scanner))
           (take (min (length octets) (- 3 (length head)))))
      (loop for index from 0 below take
            do (vector-push-extend (aref octets index) head))
      (if (< (length head) 3)
          (return-from line-scan-push nil)
          (progn
            (line-scan-release-head scanner)
            (setf octets (subseq octets take))))))
  (line-scan-process scanner octets))

(defun line-scan-finish (scanner)
  (when (line-scanner-head scanner)
    (line-scan-release-head scanner))
  (let ((size (line-scanner-position scanner)))
    (unless (line-scanner-start scanner)
      (return-from line-scan-finish
        (json-object "newlines" (line-scanner-newlines scanner)
                     "start" size "end" size "firstLineEnd" size
                     "lastLineStart" size "selectedBytes" 0 "firstLineBytes" 0)))
    (unless (line-scanner-first-line-end scanner)
      (line-scan-end-first scanner size))
    (unless (line-scanner-end scanner)
      (line-scan-end-selection scanner size))
    (json-object "newlines" (line-scanner-newlines scanner)
                 "start" (line-scanner-start scanner)
                 "end" (or (line-scanner-end scanner) size)
                 "firstLineEnd" (or (line-scanner-first-line-end scanner) size)
                 "lastLineStart" (or (line-scanner-last-line-start scanner)
                                     (line-scanner-line-start scanner))
                 "selectedBytes" (line-scanner-selected-bytes scanner)
                 "firstLineBytes" (line-scanner-first-line-bytes scanner))))
