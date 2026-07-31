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
  (length (cadr-ai::utf8-octets text)))

(defun utf16-code-unit-length (text)
  (loop for character across text
        sum (if (> (char-code character) #xffff) 2 1)))

(defun split-all-lines (text)
  (if (zerop (length text))
      (list "")
      (uiop:split-string text :separator '(#\Newline))))

(defun format-byte-size (bytes)
  (cond
    ((< bytes 1024)
     (format nil "~DB" bytes))
    ((< bytes (* 1024 1024))
     (format nil "~,1FKB" (/ bytes 1024.0)))
    (t
     (format nil "~,1FMB" (/ bytes (* 1024.0 1024.0))))))

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
          (cadr-agent:truncate-harness-head
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
          (cadr-agent:truncate-harness-tail
           text :max-lines max-lines :max-bytes max-bytes)))
    (values
     (cadr-agent:harness-truncation-result-content result)
     (harness-truncation-details
      result max-lines max-bytes))))

(defun truncate-tool-line (line &optional (max-units 500))
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
