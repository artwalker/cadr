(in-package #:cadr-agent)

(defconstant +harness-default-max-lines+ 2000)
(defconstant +harness-default-max-bytes+
  (* 50 1024))

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

(defun harness-utf8-length (text)
  (length (cadr-ai::utf8-octets text)))

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
          for character = (char text index)
          for character-bytes =
            (harness-utf8-length
             (string character))
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
