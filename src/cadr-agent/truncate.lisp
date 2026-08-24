(in-package #:cadr-agent)

(defconstant +harness-default-max-lines+ 2000)
(defconstant +harness-default-max-bytes+
  (* 50 1024))

(defconstant +default-max-lines+
  +harness-default-max-lines+)
(defconstant +default-max-bytes+
  +harness-default-max-bytes+)
(defconstant +grep-max-line-length+ 500)

(defstruct harness-truncation-result
  (content "" :type string)
  (truncated-p nil :type boolean)
  truncated-by
  (total-lines 0 :type (integer 0 *))
  (total-bytes 0 :type (integer 0 *))
  (output-lines 0 :type (integer 0 *))
  (output-bytes 0 :type (integer 0 *))
  (last-line-partial-p nil :type boolean)
  (first-line-exceeds-limit-p nil :type boolean)
  (max-lines +harness-default-max-lines+
             :type (integer 0 *))
  (max-bytes +harness-default-max-bytes+
             :type (integer 0 *)))

(deftype truncation-result ()
  'harness-truncation-result)

(defun truncation-result-content (result)
  (harness-truncation-result-content result))

(defun truncation-result-truncated-p (result)
  (harness-truncation-result-truncated-p result))

(defun truncation-result-truncated-by (result)
  (harness-truncation-result-truncated-by result))

(defun truncation-result-total-lines (result)
  (harness-truncation-result-total-lines result))

(defun truncation-result-total-bytes (result)
  (harness-truncation-result-total-bytes result))

(defun truncation-result-output-lines (result)
  (harness-truncation-result-output-lines result))

(defun truncation-result-output-bytes (result)
  (harness-truncation-result-output-bytes result))

(defun truncation-result-last-line-partial-p (result)
  (harness-truncation-result-last-line-partial-p result))

(defun truncation-result-first-line-exceeds-limit-p (result)
  (harness-truncation-result-first-line-exceeds-limit-p result))

(defun truncation-result-max-lines (result)
  (harness-truncation-result-max-lines result))

(defun truncation-result-max-bytes (result)
  (harness-truncation-result-max-bytes result))

(declaim (inline utf8-char-length))
(defun utf8-char-length (character)
  "UTF-8 byte count of CHARACTER without allocating.
Surrogate code points (#xD800-#xDFFF) cannot be encoded; delegate to the
real encoder so the same encoding error is signaled as the previous
encode-the-whole-string implementation (goal 20, 12F-1)."
  (let ((code (char-code character)))
    (cond
      ((< code #x80) 1)
      ((< code #x800) 2)
      ((<= #xd800 code #xdfff)
       (length (cadr-ai::utf8-octets (string character))))
      ((< code #x10000) 3)
      (t 4))))

(defun harness-utf8-length (text)
  (declare (type simple-string text))
  (loop with total of-type fixnum = 0
        for character of-type character across text
        for code of-type fixnum = (char-code character)
        do (incf total
                 (cond
                   ((< code #x80) 1)
                   ((< code #x800) 2)
                   ((<= #xd800 code #xdfff)
                    ;; Surrogate code points cannot be encoded; delegate to
                    ;; the real encoder so the same encoding error is
                    ;; signaled as the previous encode-the-whole-string
                    ;; implementation (goal 20, 12F-1).
                    (length (cadr-ai::utf8-octets (string character))))
                   ((< code #x10000) 3)
                   (t 4)))
        finally (return total)))

(defun harness-text-lines (text)
  (if (zerop (length text))
      nil
      (let ((lines
              (uiop:split-string
               text :separator '(#\Newline))))
        (when (and
               lines
               (char=
                #\Newline
                (char text
                      (1- (length text)))))
          (setf lines (butlast lines)))
        lines)))

(defun harness-join-lines (lines)
  (format nil "~{~A~^~%~}" lines))

(defun harness-utf8-length-range (text start end)
  (loop with total of-type fixnum = 0
        for index from start below end
        do (incf total (utf8-char-length (char text index)))
        finally (return total)))

(defun harness-line-count (text)
  (nth-value 0 (harness-line-and-utf8-length text)))

(defun harness-line-and-utf8-length (text)
  ;; One walk for both totals. truncate-harness-tail used to call
  ;; harness-line-count then harness-utf8-length over the same 500k
  ;; pairing fixture.
  (declare (type simple-string text))
  (let ((length (length text)))
    (if (zerop length)
        (values 0 0)
        (let ((lines 1)
              (bytes 0))
          (declare (type fixnum lines bytes))
          (loop for index from 0 below length
                for character of-type character = (char text index)
                do (incf bytes (utf8-char-length character))
                   (when (char= character #\Newline)
                     (incf lines)))
          (when (char= (char text (1- length)) #\Newline)
            (decf lines))
          (values lines bytes)))))

(defun make-complete-harness-truncation
    (content total-lines total-bytes max-lines max-bytes)
  (make-harness-truncation-result
   :content content
   :total-lines total-lines
   :total-bytes total-bytes
   :output-lines total-lines
   :output-bytes total-bytes
   :max-lines max-lines
   :max-bytes max-bytes))

(defun truncate-harness-head
    (content &key
               (max-lines
                 +harness-default-max-lines+)
               (max-bytes
                 +harness-default-max-bytes+))
  ;; Selection stops at max-lines/max-bytes. The pairing fixture is
  ;; 4000 lines / 50kB limit, so ~90% of the walk is totals after
  ;; the prefix is chosen. sprof named this function 78.8% self plus
  ;; GENERIC-+. Remainder is a typed byte+newline count, not close-line.
  (let* ((text
           (if (simple-string-p content)
               content
               (coerce content 'simple-string)))
         (length (length text))
         (total-lines 0)
         (total-bytes 0)
         (line-start 0)
         (line-utf8 0)
         (selected-end 0)
         (selected-lines 0)
         (selected-bytes 0)
         (reason :lines)
         (selecting t)
         (first-line t)
         (first-line-exceeds nil))
    (declare (type simple-string text)
             (type fixnum length total-lines total-bytes line-start
                   line-utf8 selected-end selected-lines selected-bytes)
             (optimize (speed 3) (safety 1)))
    (labels ((close-line (line-end)
               (declare (type fixnum line-end))
               (incf total-lines)
               (when (and first-line
                          (> line-utf8 max-bytes))
                 (setf first-line-exceeds t
                       selecting nil))
               (setf first-line nil)
               (when selecting
                 (cond
                   ((>= selected-lines max-lines)
                    (setf selecting nil))
                   ((> (+ selected-bytes
                          line-utf8
                          (if (plusp selected-lines) 1 0))
                       max-bytes)
                    (setf reason :bytes
                          selecting nil))
                   (t
                    (incf selected-bytes
                          (+ line-utf8
                             (if (plusp selected-lines) 1 0)))
                    (incf selected-lines)
                    (setf selected-end line-end)))))
             (add-remainder (from)
               (declare (type fixnum from))
               (when (< from length)
                 (let ((open-line from)
                       (index from))
                   (declare (type fixnum open-line index))
                   (loop while (< index length)
                         do
                         (let ((code (char-code (schar text index))))
                           (declare (type fixnum code))
                           (cond
                             ((= code 10)
                              (incf total-bytes)
                              (incf total-lines)
                              (setf open-line (the fixnum (1+ index)))
                              (incf index))
                             ((< code #x80)
                              (let ((run-start index))
                                (declare (type fixnum run-start))
                                (incf index)
                                (loop while (< index length)
                                      for next of-type fixnum
                                        = (char-code (schar text index))
                                      while (and (< next #x80) (/= next 10))
                                      do (incf index))
                                (incf total-bytes
                                      (the fixnum (- index run-start)))))
                             (t
                              (incf total-bytes
                                    (utf8-char-length (schar text index)))
                              (incf index)))))
                   (when (< open-line length)
                     (incf total-lines))))))
      ;; ASCII runs add 1×run. Newline still closes a line.
      ;; Non-ASCII still utf8-char-length. Same totals as the tail fill.
      (loop with index of-type fixnum = 0
            while (< index length)
            do
            (let ((code (char-code (schar text index))))
              (declare (type fixnum code))
              (cond
                ((= code 10)
                 (incf total-bytes)
                 (close-line index)
                 (setf line-start (the fixnum (1+ index))
                       line-utf8 0)
                 (incf index)
                 (unless selecting
                   (add-remainder line-start)
                   (return)))
                ((< code #x80)
                 (let ((run-start index))
                   (declare (type fixnum run-start))
                   (incf index)
                   (loop while (< index length)
                         for next of-type fixnum
                           = (char-code (schar text index))
                         while (and (< next #x80) (/= next 10))
                         do (incf index))
                   (let ((run (the fixnum (- index run-start))))
                     (incf total-bytes run)
                     (incf line-utf8 run))))
                (t
                 (let ((nbytes
                         (utf8-char-length (schar text index))))
                   (declare (type fixnum nbytes))
                   (incf total-bytes nbytes)
                   (incf line-utf8 nbytes)
                   (incf index))))))
      (when (and selecting (< line-start length))
        (close-line length))
      (cond
        ((and (<= total-lines max-lines)
              (<= total-bytes max-bytes))
         (make-complete-harness-truncation
          content total-lines total-bytes max-lines max-bytes))
        (first-line-exceeds
         (make-harness-truncation-result
          :truncated-p t
          :truncated-by :bytes
          :total-lines total-lines
          :total-bytes total-bytes
          :first-line-exceeds-limit-p t
          :max-lines max-lines
          :max-bytes max-bytes))
        (t
         (let ((output
                 (if (zerop selected-end)
                     ""
                     (subseq content 0 selected-end))))
           (make-harness-truncation-result
            :content output
            :truncated-p t
            :truncated-by reason
            :total-lines total-lines
            :total-bytes total-bytes
            :output-lines selected-lines
            :output-bytes selected-bytes
            :max-lines max-lines
            :max-bytes max-bytes)))))))

(defun utf8-tail-bytes (text max-bytes)
  (when (<= max-bytes 0)
    (return-from utf8-tail-bytes ""))
  (let ((start (length text))
        (bytes 0))
    (loop for index downfrom
            (1- (length text)) to 0
          for character-bytes =
            (utf8-char-length (char text index))
          while
            (<= (+ bytes character-bytes)
                max-bytes)
          do
      (incf bytes character-bytes)
      (setf start index))
    (subseq text start)))

(defun utf8-tail-bytes-range (text start end max-bytes)
  (when (<= max-bytes 0)
    (return-from utf8-tail-bytes-range ""))
  (let ((from end)
        (bytes 0))
    (loop for index from (1- end) downto start
          for character-bytes =
            (utf8-char-length (char text index))
          while
            (<= (+ bytes character-bytes)
                max-bytes)
          do
      (incf bytes character-bytes)
      (setf from index))
    (if (= from end)
        ""
        (subseq text from end))))

(defun truncate-harness-tail
    (content &key
               (max-lines
                 +harness-default-max-lines+)
               (max-bytes
                 +harness-default-max-bytes+))
  ;; pi truncateTail: one length + random-access lines + index
  ;; from the end. Lisp encoding is a fixnum start/width table,
  ;; not uiop:split-string and not a second full-string reverse
  ;; scan (docs/adjudications.md 2026-08-19 22:18).
  (let* ((text
           (if (simple-string-p content)
               content
               (coerce content 'simple-string)))
         (length (length text)))
    (declare (type simple-string text)
             (type fixnum length)
             (optimize (speed 3) (safety 1)))
    (when (zerop length)
      (return-from truncate-harness-tail
        (make-complete-harness-truncation
         content 0 0 max-lines max-bytes)))
    (let* ((hint
             (max 64 (min 8192 (1+ (truncate length 20)))))
           (starts (make-array hint :element-type 'fixnum))
           (widths (make-array hint :element-type 'fixnum))
           (cap hint)
           (slot 0)
           (total-bytes 0)
           (line-start 0)
           (line-utf8 0)
           (trailing-bytes 0))
      (declare (type fixnum hint cap slot total-bytes line-start
                     line-utf8 trailing-bytes)
               (type (simple-array fixnum (*)) starts widths)
               (optimize (speed 3) (safety 1)))
      (flet ((push-line (start width)
               (declare (type fixnum start width))
               (when (>= slot cap)
                 (setf cap (the fixnum (* cap 2)))
                 (let ((next-starts
                         (make-array cap :element-type 'fixnum))
                       (next-widths
                         (make-array cap :element-type 'fixnum)))
                   (replace next-starts starts)
                   (replace next-widths widths)
                   (setf starts next-starts
                         widths next-widths)))
               (setf (aref starts slot) start
                     (aref widths slot) width)
               (incf slot)))
        ;; ASCII runs add 1×run. Newline still closes a line.
        ;; Non-ASCII still utf8-char-length. Same start/width table.
        (loop with index of-type fixnum = 0
              while (< index length)
              do
              (let ((code (char-code (schar text index))))
                (declare (type fixnum code))
                (cond
                  ((= code 10)
                   (incf total-bytes)
                   (push-line line-start line-utf8)
                   (setf line-start (the fixnum (1+ index))
                         line-utf8 0)
                   (incf index))
                  ((< code #x80)
                   (let ((run-start index))
                     (declare (type fixnum run-start))
                     (incf index)
                     (loop while (< index length)
                           for next of-type fixnum
                             = (char-code (schar text index))
                           while (and (< next #x80) (/= next 10))
                           do (incf index))
                     (let ((run (the fixnum (- index run-start))))
                       (incf total-bytes run)
                       (incf line-utf8 run))))
                  (t
                   (let ((nbytes
                           (utf8-char-length (schar text index))))
                     (declare (type fixnum nbytes))
                     (incf total-bytes nbytes)
                     (incf line-utf8 nbytes)
                     (incf index))))))
        (if (= line-start length)
            (setf trailing-bytes 1)
            (push-line line-start line-utf8)))
      (when (< slot cap)
        (let ((exact-starts (make-array slot :element-type 'fixnum))
              (exact-widths (make-array slot :element-type 'fixnum)))
          (replace exact-starts starts)
          (replace exact-widths widths)
          (setf starts exact-starts
                widths exact-widths)))
      (let ((total-lines slot))
        (declare (type fixnum total-lines))
        (when (and (<= total-lines max-lines)
                   (<= total-bytes max-bytes))
          (return-from truncate-harness-tail
            (make-complete-harness-truncation
             content total-lines total-bytes max-lines max-bytes)))
        (let ((last-line-end (- length trailing-bytes))
              (selected-start nil)
              (selected-lines 0)
              (selected-bytes 0)
              (reason :lines)
              (partial-p nil)
              (partial-content nil))
          (declare (type fixnum last-line-end selected-lines
                         selected-bytes))
          (loop for i of-type fixnum from (1- total-lines) downto 0
                for line-start of-type fixnum = (aref starts i)
                for line-utf8 of-type fixnum = (aref widths i)
                for needed of-type fixnum =
                  (+ line-utf8
                     (if (plusp selected-lines) 1 0))
                do
            (cond
              ((>= selected-lines max-lines)
               (return))
              ((> (+ selected-bytes needed) max-bytes)
               (setf reason :bytes)
               (when (zerop selected-lines)
                 (let ((line-end
                         (if (= i (1- total-lines))
                             last-line-end
                             (the fixnum (1- (aref starts (1+ i)))))))
                   (setf partial-content
                         (utf8-tail-bytes-range
                          text line-start line-end max-bytes)
                         partial-p t
                         selected-lines 1
                         selected-bytes
                         (harness-utf8-length partial-content))))
               (return))
              (t
               (incf selected-lines)
               (incf selected-bytes needed)
               (setf selected-start line-start))))
          (let ((output
                  (cond
                    (partial-content partial-content)
                    (selected-start
                     (subseq content selected-start last-line-end))
                    (t ""))))
            (make-harness-truncation-result
             :content output
             :truncated-p t
             :truncated-by reason
             :total-lines total-lines
             :total-bytes total-bytes
             :output-lines selected-lines
             :output-bytes selected-bytes
             :last-line-partial-p partial-p
             :max-lines max-lines
             :max-bytes max-bytes)))))))

(defun harness-truncation-omission-line (omitted-lines)
  (format nil "... [~D lines omitted] ..." omitted-lines))

(defun harness-join-line-range (text starts start-line end-line)
  (declare (type simple-string text)
           (type (simple-array fixnum (*)) starts)
           (type fixnum start-line end-line))
  (let ((line-count (length starts)))
    (cond
      ((or (>= start-line line-count) (<= end-line start-line))
       "")
      (t
       (let* ((from (aref starts start-line))
              (to (if (>= end-line line-count)
                      (length text)
                      (1- (aref starts end-line)))))
         (if (< from to)
             (subseq text from to)
             ""))))))

(defun truncate-harness-middle
    (content &key
               (max-lines
                 +harness-default-max-lines+)
               (max-bytes
                 +harness-default-max-bytes+))
  ;; Keep head and tail lines with one omission marker between them.
  ;; pi packages/coding-agent/src/core/tools/truncate.ts truncateMiddle.
  (let* ((text
           (if (simple-string-p content)
               content
               (coerce content 'simple-string)))
         (length (length text)))
    (declare (type simple-string text)
             (type fixnum length)
             (optimize (speed 3) (safety 1)))
    (when (zerop length)
      (return-from truncate-harness-middle
        (make-complete-harness-truncation
         content 0 0 max-lines max-bytes)))
    (let* ((hint
             (max 64 (min 8192 (1+ (truncate length 20)))))
           (starts (make-array hint :element-type 'fixnum))
           (widths (make-array hint :element-type 'fixnum))
           (cap hint)
           (slot 0)
           (total-bytes 0)
           (line-start 0)
           (line-utf8 0))
      (declare (type fixnum hint cap slot total-bytes line-start line-utf8)
               (type (simple-array fixnum (*)) starts widths)
               (optimize (speed 3) (safety 1)))
      (flet ((push-line (start width)
               (declare (type fixnum start width))
               (when (>= slot cap)
                 (setf cap (the fixnum (* cap 2)))
                 (let ((next-starts
                         (make-array cap :element-type 'fixnum))
                       (next-widths
                         (make-array cap :element-type 'fixnum)))
                   (replace next-starts starts)
                   (replace next-widths widths)
                   (setf starts next-starts
                         widths next-widths)))
               (setf (aref starts slot) start
                     (aref widths slot) width)
               (incf slot)))
        (loop with index of-type fixnum = 0
              while (< index length)
              do
              (let ((code (char-code (schar text index))))
                (declare (type fixnum code))
                (cond
                  ((= code 10)
                   (incf total-bytes)
                   (push-line line-start line-utf8)
                   (setf line-start (the fixnum (1+ index))
                         line-utf8 0)
                   (incf index))
                  ((< code #x80)
                   (let ((run-start index))
                     (declare (type fixnum run-start))
                     (incf index)
                     (loop while (< index length)
                           for next of-type fixnum
                             = (char-code (schar text index))
                           while (and (< next #x80) (/= next 10))
                           do (incf index))
                     (let ((run (the fixnum (- index run-start))))
                       (incf total-bytes run)
                       (incf line-utf8 run))))
                  (t
                   (let ((nbytes
                           (utf8-char-length (schar text index))))
                     (declare (type fixnum nbytes))
                     (incf total-bytes nbytes)
                     (incf line-utf8 nbytes)
                     (incf index))))))
        (unless (= line-start length)
          (push-line line-start line-utf8)))
      (when (< slot cap)
        (let ((exact-starts (make-array slot :element-type 'fixnum))
              (exact-widths (make-array slot :element-type 'fixnum)))
          (replace exact-starts starts)
          (replace exact-widths widths)
          (setf starts exact-starts
                widths exact-widths)))
      (let ((total-lines slot))
        (declare (type fixnum total-lines))
        (when (and (<= total-lines max-lines)
                   (<= total-bytes max-bytes))
          (return-from truncate-harness-middle
            (make-complete-harness-truncation
             content total-lines total-bytes max-lines max-bytes)))
        (let ((first-line-bytes (aref widths 0)))
          (when (> first-line-bytes max-bytes)
            (return-from truncate-harness-middle
              (make-harness-truncation-result
               :truncated-p t
               :truncated-by :bytes
               :total-lines total-lines
               :total-bytes total-bytes
               :first-line-exceeds-limit-p t
               :max-lines max-lines
               :max-bytes max-bytes))))
        (labels ((segment-bytes (from to)
                   (declare (type fixnum from to))
                   (let ((bytes 0))
                     (loop for index from from below to
                           do (incf bytes (aref widths index)))
                     (when (< from to)
                       (incf bytes (1- (- to from))))
                     bytes))
                 (selection-bytes (head-count tail-count omitted-lines)
                   (declare (type fixnum head-count tail-count omitted-lines))
                   (let* ((omission
                            (harness-truncation-omission-line
                             omitted-lines))
                          (omission-bytes
                            (harness-utf8-length omission))
                          (head-bytes
                            (if (zerop head-count)
                                0
                                (segment-bytes 0 head-count)))
                          (tail-bytes
                            (if (zerop tail-count)
                                0
                                (segment-bytes
                                 (- total-lines tail-count)
                                 total-lines)))
                          (join-bytes
                            (+ head-bytes
                               tail-bytes
                               omission-bytes
                               (cond
                                 ((and (plusp head-count)
                                       (or (plusp tail-count)
                                           (plusp omitted-lines)))
                                  1)
                                 ((and (zerop head-count)
                                       (plusp tail-count)
                                       (plusp omitted-lines))
                                  1)
                                 (t 0))
                               (if (and (plusp tail-count)
                                        (or (plusp head-count)
                                            (plusp omitted-lines)))
                                   1
                                   0))))
                     join-bytes))
                 (selection-fits-p (head-count tail-count)
                   (declare (type fixnum head-count tail-count))
                   (when (> (+ head-count tail-count) total-lines)
                     (return-from selection-fits-p nil))
                   (let ((omitted (- total-lines head-count tail-count)))
                     (when (<= omitted 0)
                       (return-from selection-fits-p nil))
                     (let ((output-lines (+ head-count 1 tail-count)))
                       (and (<= output-lines max-lines)
                            (<= (selection-bytes
                                 head-count tail-count omitted)
                                max-bytes))))))
          (let ((head-count 0)
                (tail-count 0)
                (reason :lines))
            (declare (type fixnum head-count tail-count))
            (loop
              (let ((improved nil))
                (when (< (+ head-count tail-count) total-lines)
                  (let ((next-head (1+ head-count)))
                    (when (selection-fits-p next-head tail-count)
                      (setf head-count next-head
                            improved t))))
                (when (< (+ head-count tail-count) total-lines)
                  (let ((next-tail (1+ tail-count)))
                    (when (selection-fits-p head-count next-tail)
                      (setf tail-count next-tail
                            improved t))))
                (unless improved
                  (return))))
            (let ((omitted (- total-lines head-count tail-count)))
              (when (<= omitted 0)
                (error "truncate-harness-middle: empty selection on ~D lines"
                       total-lines))
              (let* ((omission
                       (harness-truncation-omission-line omitted))
                     (head-text
                       (if (zerop head-count)
                           ""
                           (harness-join-line-range
                            text starts 0 head-count)))
                     (tail-text
                       (if (zerop tail-count)
                           ""
                           (harness-join-line-range
                            text starts (- total-lines tail-count)
                            total-lines)))
                     (output
                       (cond
                         ((and (plusp head-count) (plusp tail-count))
                          (format nil "~A~%~A~%~A"
                                  head-text omission tail-text))
                         ((plusp head-count)
                          (format nil "~A~%~A" head-text omission))
                         ((plusp tail-count)
                          (format nil "~A~%~A" omission tail-text))
                         (t omission)))
                     (output-lines (+ head-count 1 tail-count))
                     (output-bytes
                       (selection-bytes head-count tail-count omitted)))
                (when (>= output-lines max-lines)
                  (setf reason :lines))
                (when (> output-bytes max-bytes)
                  (setf reason :bytes))
                (make-harness-truncation-result
                 :content output
                 :truncated-p t
                 :truncated-by reason
                 :total-lines total-lines
                 :total-bytes total-bytes
                 :output-lines output-lines
                 :output-bytes output-bytes
                 :max-lines max-lines
                 :max-bytes max-bytes)))))))))

(defun truncate-harness-line
    (line &optional (max-characters 500))
  (if (<= (length line) max-characters)
      (values line nil)
      (values
       (format nil "~A... [truncated]"
               (subseq line 0 max-characters))
       t)))

(defun truncate-head
    (content &key
               (max-lines +default-max-lines+)
               (max-bytes +default-max-bytes+))
  (truncate-harness-head
   content :max-lines max-lines :max-bytes max-bytes))

(defun truncate-tail
    (content &key
               (max-lines +default-max-lines+)
               (max-bytes +default-max-bytes+))
  (truncate-harness-tail
   content :max-lines max-lines :max-bytes max-bytes))

(defun truncate-middle
    (content &key
               (max-lines +default-max-lines+)
               (max-bytes +default-max-bytes+))
  (truncate-harness-middle
   content :max-lines max-lines :max-bytes max-bytes))

(defun format-size (bytes)
  (cond
    ((< bytes 1024)
     (format nil "~DB" bytes))
    ((< bytes (* 1024 1024))
     (format nil "~,1FKB" (/ bytes 1024.0)))
    (t
     (format nil "~,1FMB" (/ bytes (* 1024.0 1024.0))))))

(defun utf16-code-unit-length (text)
  (loop for character across text
        sum (if (> (char-code character) #xffff) 2 1)))

(defun truncate-line
    (line &optional (max-units +grep-max-line-length+))
  (if (<= (utf16-code-unit-length line) max-units)
      (values line nil)
      (let ((end 0)
            (units 0))
        (loop for character across line
              for width =
                (if (> (char-code character) #xffff) 2 1)
              while (<= (+ units width) max-units)
              do (incf units width)
                 (incf end))
        (values
         (format nil "~A... [truncated]"
                 (subseq line 0 end))
         t))))
