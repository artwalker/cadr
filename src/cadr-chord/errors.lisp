(in-package #:cadr-chord)

(defparameter +protocol-version+ 4)
(defparameter +pack-threshold+ (* 64 1024))

(define-condition chord-error (error)
  ((code :initarg :code :reader chord-error-code)
   (reason :initarg :reason :initform nil :reader chord-error-reason)
   (text :initarg :text :reader chord-error-text)
   (details :initarg :details :initform nil :reader chord-error-details))
  (:report (lambda (condition stream)
             (write-string (chord-error-message condition) stream))))

(defun chord-error-p (condition &optional code)
  (and (typep condition 'chord-error)
       (or (null code) (string= (chord-error-code condition) code))))

(defun chord-error-retryable-p (condition)
  (and (typep condition 'chord-error)
       (member (chord-error-code condition)
               '("superseded" "upgrade_conflict")
               :test #'string=)))

(defun chord-error-message (condition)
  (format nil "~A~@[~A~]: ~A"
          (chord-error-code condition)
          (let ((reason (chord-error-reason condition)))
            (and reason (format nil "/~A" reason)))
          (chord-error-text condition)))

(defun signal-chord (code text &key reason details)
  (error 'chord-error :code code :text text :reason reason :details details))

(defun forbidden (&optional (text "forbidden"))
  (signal-chord "forbidden" text))

(defun invalid (reason text &optional details)
  (signal-chord "invalid" text :reason reason :details details))
