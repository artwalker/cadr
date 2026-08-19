(in-package #:cadr-cli)

(defparameter +maximum-output-lines+ 2000)
(defparameter +maximum-output-bytes+ (* 50 1024))

(defun make-text-line-table (text)
  ;; text-lines semantics: drop the trailing empty split part
  ;; (file ending in newline) and trim CR. Empty → 0 lines.
  ;; Keep the full starts vector so the last content line still
  ;; sees its terminating newline as the next start.
  (let ((source
          (if (simple-string-p text)
              text
              (coerce text 'simple-string))))
    (when (zerop (length source))
      (return-from make-text-line-table
        (list source (make-array 0 :element-type 'fixnum) 0)))
    (multiple-value-bind (starts source)
        (split-line-starts source)
      (let ((n (length starts)))
        (when (and (plusp n)
                   (= (aref starts (1- n)) (length source)))
          (decf n))
        (list source starts n)))))

(defun text-line-ref (source starts index)
  (string-right-trim
   '(#\Return)
   (split-line-ref source starts index)))

(defun text-lines (text)
  (let* ((table (make-text-line-table text))
         (source (first table))
         (starts (second table))
         (n (third table)))
    (loop for index from 0 below n
          collect (text-line-ref source starts index))))

(defun join-lines (lines)
  (format nil "~{~A~^~%~}" lines))

(defun utf8-length (text)
  ;; pi Buffer.byteLength. Count without allocating a full
  ;; octet vector. cadr-agent::harness-utf8-length is the
  ;; allocation-free walk (goal 20 DS audit class A).
  (cadr-agent::harness-utf8-length
   (if (simple-string-p text)
       text
       (coerce text 'simple-string))))

(defun utf16-code-unit-length (text)
  (cadr-agent::utf16-code-unit-length text))

(defun split-octet-line-starts (octets)
  ;; JS split("\n") on UTF-8: 0x0A cannot appear inside a
  ;; multi-byte scalar, so a ub8 scan matches a character scan.
  ;; Empty → #(0). Trailing newline → extra start at length.
  ;; One pass, same hint as truncate-harness-tail (64..8192,
  ;; 1+length/20). Pairing 4000 lines fits the cap. Grow by
  ;; doubling; shrink to exact so LENGTH is the line count.
  ;; Not a second 0x0A walk (sprof SPLIT-OCTET-LINE-STARTS
  ;; 27.4% at ad1e91711). Not intern. Not FFI. Not empty SWAR.
  (declare (type (simple-array (unsigned-byte 8) (*)) octets)
           (optimize (speed 3) (safety 1)))
  (let* ((length (length octets))
         (hint
           (max 64 (min 8192 (1+ (truncate length 20)))))
         (starts (make-array hint :element-type 'fixnum))
         (cap hint)
         (slot 1))
    (declare (type fixnum length hint cap slot)
             (type (simple-array fixnum (*)) starts))
    (setf (aref starts 0) 0)
    (loop for index of-type fixnum from 0 below length
          when (= (aref octets index) 10)
            do
            (when (>= slot cap)
              (setf cap (the fixnum (* cap 2)))
              (let ((grown
                      (make-array cap :element-type 'fixnum)))
                (replace grown starts)
                (setf starts grown)))
            (setf (aref starts slot)
                  (the fixnum (1+ index)))
            (incf slot))
    (if (= slot cap)
        starts
        (let ((exact (make-array slot :element-type 'fixnum)))
          (replace exact starts)
          exact))))

(defun octet-line-byte-end (starts nbytes index)
  (let ((next (1+ index)))
    (if (< next (length starts))
        (1- (aref starts next))
        nbytes)))

(defun octet-decode-line-end
    (starts nbytes sel-start sel-end max-lines max-bytes)
  ;; Exclusive line index covering offset/limit plus one
  ;; overflowing line so truncate-head still sees the limit.
  (declare (type (simple-array fixnum (*)) starts)
           (type fixnum nbytes sel-start sel-end max-lines max-bytes)
           (optimize (speed 3) (safety 1)))
  (let ((join-bytes 0)
        (lines 0))
    (declare (type fixnum join-bytes lines))
    (loop for index of-type fixnum from sel-start below sel-end
          for from of-type fixnum = (aref starts index)
          for to of-type fixnum = (octet-line-byte-end
                                   starts nbytes index)
          for line-bytes of-type fixnum = (max 0 (- to from))
          for with-nl of-type fixnum = (+ line-bytes
                                          (if (plusp lines) 1 0))
          do
          (when (or (>= lines max-lines)
                    (> (+ join-bytes with-nl) max-bytes))
            (return-from octet-decode-line-end
              (min sel-end (the fixnum (1+ index)))))
          (incf join-bytes with-nl)
          (incf lines))
    sel-end))

(defun split-line-starts (text)
  ;; pi String.prototype.split("\n"): one start index per part.
  ;; Empty → #(0). Trailing newline → extra start at length.
  ;; Exact-size fixnum vector (count then fill). Not
  ;; vector-push-extend (sprof PREPARE-VECTOR-PUSH-EXTEND
  ;; 12.7% at 39b3707bf). Not uiop:split-string.
  (let* ((source
           (if (simple-string-p text)
               text
               (coerce text 'simple-string)))
         (length (length source)))
    (declare (type simple-string source)
             (type fixnum length)
             (optimize (speed 3) (safety 1)))
    (let ((nlines 1))
      (declare (type fixnum nlines))
      (loop for index of-type fixnum from 0 below length
            when (char= (schar source index) #\Newline)
              do (incf nlines))
      (let ((starts
              (make-array nlines :element-type 'fixnum)))
        (setf (aref starts 0) 0)
        (let ((slot 1))
          (declare (type fixnum slot))
          (loop for index of-type fixnum from 0 below length
                when (char= (schar source index) #\Newline)
                  do (setf (aref starts slot)
                           (the fixnum (1+ index)))
                     (incf slot)))
        (values starts source)))))

(defun split-line-ref (text starts index)
  (let* ((from (aref starts index))
         (next (1+ index))
         (to (if (< next (length starts))
                 (1- (aref starts next))
                 (length text))))
    (if (< from to)
        (subseq text from to)
        "")))

(defun split-line-join (text starts start end)
  (let ((n (length starts)))
    (cond
      ((or (>= start n) (<= end start))
       "")
      (t
       (let* ((from (aref starts start))
              (to (if (>= end n)
                      (length text)
                      (1- (aref starts end)))))
         (if (< from to)
             (subseq text from to)
             ""))))))

(defun split-all-lines (text)
  (multiple-value-bind (starts source)
      (split-line-starts text)
    (loop for index from 0 below (length starts)
          collect (split-line-ref source starts index))))

(defun format-byte-size (bytes)
  (cadr-agent::format-size bytes))

(defun harness-truncation-details
    (result max-lines max-bytes)
  (list
   :truncated
   (cadr-agent:harness-truncation-result-truncated-p result)
   :truncated-by
   (cadr-agent:harness-truncation-result-truncated-by result)
   :total-lines
   (cadr-agent:harness-truncation-result-total-lines result)
   :total-bytes
   (cadr-agent:harness-truncation-result-total-bytes result)
   :output-lines
   (cadr-agent:harness-truncation-result-output-lines result)
   :output-bytes
   (cadr-agent:harness-truncation-result-output-bytes result)
   :last-line-partial
   (cadr-agent:harness-truncation-result-last-line-partial-p result)
   :first-line-exceeds-limit
   (cadr-agent:harness-truncation-result-first-line-exceeds-limit-p result)
   :max-lines max-lines
   :max-bytes max-bytes))

(defun truncate-head
    (text &key
            (max-lines +maximum-output-lines+)
            (max-bytes +maximum-output-bytes+))
  (let ((result
          (cadr-agent::truncate-head
           text :max-lines max-lines :max-bytes max-bytes)))
    (values
     (cadr-agent:harness-truncation-result-content result)
     (harness-truncation-details
      result max-lines max-bytes))))

(defun truncate-tail
    (text &key
            (max-lines +maximum-output-lines+)
            (max-bytes +maximum-output-bytes+))
  (let ((result
          (cadr-agent::truncate-tail
           text :max-lines max-lines :max-bytes max-bytes)))
    (values
     (cadr-agent:harness-truncation-result-content result)
     (harness-truncation-details
      result max-lines max-bytes))))

(defun truncate-tool-line (line &optional (max-units 500))
  (cadr-agent::truncate-line line max-units))
