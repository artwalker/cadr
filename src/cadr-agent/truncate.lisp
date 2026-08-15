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

(defun make-complete-harness-truncation
    (content lines max-lines max-bytes)
  (let ((bytes (harness-utf8-length content)))
    (make-harness-truncation-result
     :content content
     :total-lines (length lines)
     :total-bytes bytes
     :output-lines (length lines)
     :output-bytes bytes
     :max-lines max-lines
     :max-bytes max-bytes)))

(defun truncate-harness-head
    (content &key
               (max-lines
                 +harness-default-max-lines+)
               (max-bytes
                 +harness-default-max-bytes+))
  (let* ((lines (harness-text-lines content))
         (total-lines (length lines))
         (total-bytes
           (harness-utf8-length content)))
    (when (and
           (<= total-lines max-lines)
           (<= total-bytes max-bytes))
      (return-from truncate-harness-head
        (make-complete-harness-truncation
         content lines max-lines max-bytes)))
    (when
        (and
         lines
         (> (harness-utf8-length (first lines))
            max-bytes))
      (return-from truncate-harness-head
        (make-harness-truncation-result
         :truncated-p t
         :truncated-by :bytes
         :total-lines total-lines
         :total-bytes total-bytes
         :first-line-exceeds-limit-p t
         :max-lines max-lines
         :max-bytes max-bytes)))
    (let ((selected nil)
          (bytes 0)
          (reason :lines))
      (dolist (line lines)
        (when (>= (length selected) max-lines)
          (return))
        (let ((line-bytes
                (+ (harness-utf8-length line)
                   (if selected 1 0))))
          (when (> (+ bytes line-bytes)
                   max-bytes)
            (setf reason :bytes)
            (return))
          (push line selected)
          (incf bytes line-bytes)))
      (setf selected (nreverse selected))
      (let ((output
              (harness-join-lines selected)))
        (make-harness-truncation-result
         :content output
         :truncated-p t
         :truncated-by reason
         :total-lines total-lines
         :total-bytes total-bytes
         :output-lines (length selected)
         :output-bytes
         (harness-utf8-length output)
         :max-lines max-lines
         :max-bytes max-bytes)))))

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

(defun truncate-harness-tail
    (content &key
               (max-lines
                 +harness-default-max-lines+)
               (max-bytes
                 +harness-default-max-bytes+))
  (let* ((lines (harness-text-lines content))
         (total-lines (length lines))
         (total-bytes
           (harness-utf8-length content)))
    (when (and
           (<= total-lines max-lines)
           (<= total-bytes max-bytes))
      (return-from truncate-harness-tail
        (make-complete-harness-truncation
         content lines max-lines max-bytes)))
    (let ((selected nil)
          (bytes 0)
          (reason :lines)
          (partial-p nil))
      (dolist (line (reverse lines))
        (when (>= (length selected) max-lines)
          (return))
        (let ((line-bytes
                (+ (harness-utf8-length line)
                   (if selected 1 0))))
          (when (> (+ bytes line-bytes)
                   max-bytes)
            (setf reason :bytes)
            (when (null selected)
              (let ((tail
                      (utf8-tail-bytes
                       line max-bytes)))
                (push tail selected)
                (setf
                 bytes
                 (harness-utf8-length tail)
                 partial-p t)))
            (return))
          (push line selected)
          (incf bytes line-bytes)))
      (let ((output
              (harness-join-lines selected)))
        (make-harness-truncation-result
         :content output
         :truncated-p t
         :truncated-by reason
         :total-lines total-lines
         :total-bytes total-bytes
         :output-lines (length selected)
         :output-bytes
         (harness-utf8-length output)
         :last-line-partial-p partial-p
         :max-lines max-lines
         :max-bytes max-bytes)))))

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
