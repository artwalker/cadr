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

(defun bounded-lines (lines direction)
  (let* ((total-lines (length lines))
         (ordered (if (eq direction :head)
                      lines
                      (reverse lines)))
         (selected nil)
         (bytes 0))
    (dolist (line ordered)
      (let ((line-bytes (+ (utf8-length line)
                           (if selected 1 0))))
        (when (or (>= (length selected)
                      +maximum-output-lines+)
                  (> (+ bytes line-bytes)
                     +maximum-output-bytes+))
          (return))
        (push line selected)
        (incf bytes line-bytes)))
    (let ((result
            (if (eq direction :head)
                (nreverse selected)
                selected)))
      (values
       (join-lines result)
       (list :truncated (< (length result) total-lines)
             :total-lines total-lines
             :output-lines (length result))))))

(defun truncate-head (text)
  (bounded-lines (text-lines text) :head))

(defun truncate-tail (text)
  (bounded-lines (text-lines text) :tail))
