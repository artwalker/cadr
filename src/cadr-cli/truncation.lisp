(in-package #:cadr-cli)

(defparameter +maximum-output-lines+ 2000)
(defparameter +maximum-output-bytes+ (* 50 1024))

(defun text-lines (text)
  (let ((lines (uiop:split-string text :separator '(#\Newline))))
    (when (and lines
               (string= "" (car (last lines))))
      (setf lines (butlast lines)))
    (mapcar (lambda (line)
              (string-right-trim '(#\Return) line))
            lines)))

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

(defun split-line-starts (text)
  ;; pi String.prototype.split("\n"): one start index per part.
  ;; Empty → #(0). Trailing newline → extra start at length.
  ;; Fixnum vector, not uiop:split-string (goal 20 DS audit class B).
  (let* ((source
           (if (simple-string-p text)
               text
               (coerce text 'simple-string)))
         (length (length source))
         (hint
           (max 64 (min 8192 (1+ (truncate (max 1 length) 20)))))
         (starts
           (make-array hint :element-type 'fixnum
                       :adjustable t :fill-pointer 0)))
    (declare (type simple-string source)
             (type fixnum length)
             (optimize (speed 3) (safety 1)))
    (vector-push-extend 0 starts)
    (loop for index of-type fixnum from 0 below length
          when (char= (schar source index) #\Newline)
            do (vector-push-extend
                (the fixnum (1+ index)) starts))
    (values starts source)))

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
