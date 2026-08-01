(in-package #:cadr-cli)

(defstruct output-snapshot
  (content "" :type string)
  (truncation nil :type list)
  full-output-path)

(defstruct (output-accumulator (:constructor %make-output-accumulator))
  (max-lines +maximum-output-lines+ :type (integer 0 *))
  (max-bytes +maximum-output-bytes+ :type (integer 0 *))
  (temp-file-prefix "cadr-output" :type string)
  (raw-history (make-array 0 :element-type '(unsigned-byte 8)
                           :adjustable t :fill-pointer 0))
  (pending (make-array 0 :element-type '(unsigned-byte 8)))
  (tail-text "" :type string)
  (tail-bytes 0 :type (integer 0 *))
  (tail-starts-at-line-boundary-p t :type boolean)
  (total-raw-bytes 0 :type (integer 0 *))
  (total-decoded-bytes 0 :type (integer 0 *))
  (completed-lines 0 :type (integer 0 *))
  (current-line-bytes 0 :type (integer 0 *))
  (has-open-line-p nil :type boolean)
  (finished-p nil :type boolean)
  temp-file-path
  temp-file-stream)

(defun make-output-accumulator
    (&key (max-lines +maximum-output-lines+)
          (max-bytes +maximum-output-bytes+)
          (temp-file-prefix "cadr-output"))
  (%make-output-accumulator
   :max-lines max-lines :max-bytes max-bytes
   :temp-file-prefix temp-file-prefix))

(defun octet-vector (data)
  (etypecase data
    (string (cadr-ai::utf8-octets data))
    ((vector (unsigned-byte 8)) data)))

(defun concatenate-octets (first second)
  (let ((result (make-array (+ (length first) (length second))
                            :element-type '(unsigned-byte 8))))
    (replace result first)
    (replace result second :start1 (length first))
    result))

(defun decode-complete-utf8 (octets)
  (loop for trim from 0 to (min 3 (length octets))
        for end = (- (length octets) trim)
        do
        (handler-case
            (return
              (values (cadr-ai::utf8-string (subseq octets 0 end))
                      (subseq octets end)))
          (error () nil))
        finally (error "Invalid UTF-8 output")))

(defun output-accumulator-total-lines (accumulator)
  (+ (output-accumulator-completed-lines accumulator)
     (if (output-accumulator-has-open-line-p accumulator) 1 0)))

(defun trim-output-tail (accumulator)
  (let* ((limit (max 1 (* 2 (output-accumulator-max-bytes accumulator))))
         (octets (cadr-ai::utf8-octets
                  (output-accumulator-tail-text accumulator))))
    (when (> (length octets) limit)
      (let ((start (- (length octets) limit)))
        (loop while (and (< start (length octets))
                         (= #x80 (logand #xc0 (aref octets start))))
              do (incf start))
        (setf (output-accumulator-tail-starts-at-line-boundary-p accumulator)
              (if (zerop start)
                  (output-accumulator-tail-starts-at-line-boundary-p accumulator)
                  (= #x0a (aref octets (1- start))))
              (output-accumulator-tail-text accumulator)
              (cadr-ai::utf8-string (subseq octets start))
              (output-accumulator-tail-bytes accumulator)
              (- (length octets) start))))))

(defun output-accumulator-append-decoded (accumulator text)
  (when (plusp (length text))
    (let ((bytes (utf8-length text))
          (last-newline (position #\Newline text :from-end t)))
      (incf (output-accumulator-total-decoded-bytes accumulator) bytes)
      (setf (output-accumulator-tail-text accumulator)
            (concatenate 'string
                         (output-accumulator-tail-text accumulator) text))
      (incf (output-accumulator-tail-bytes accumulator) bytes)
      (incf (output-accumulator-completed-lines accumulator)
            (count #\Newline text))
      (if last-newline
          (let ((tail (subseq text (1+ last-newline))))
            (setf (output-accumulator-current-line-bytes accumulator)
                  (utf8-length tail)
                  (output-accumulator-has-open-line-p accumulator)
                  (plusp (length tail))))
          (progn
            (incf (output-accumulator-current-line-bytes accumulator) bytes)
            (setf (output-accumulator-has-open-line-p accumulator) t)))
      (when (> (output-accumulator-tail-bytes accumulator)
               (* 2 (max 1 (* 2 (output-accumulator-max-bytes accumulator)))))
        (trim-output-tail accumulator)))))

(defun output-accumulator-snapshot-text (accumulator)
  (let ((text (output-accumulator-tail-text accumulator)))
    (if (output-accumulator-tail-starts-at-line-boundary-p accumulator)
        text
        (let ((newline (position #\Newline text)))
          (if newline (subseq text (1+ newline)) text)))))

(defun output-accumulator-needs-file-p (accumulator)
  (or (> (output-accumulator-total-raw-bytes accumulator)
         (output-accumulator-max-bytes accumulator))
      (> (output-accumulator-total-decoded-bytes accumulator)
         (output-accumulator-max-bytes accumulator))
      (> (output-accumulator-total-lines accumulator)
         (output-accumulator-max-lines accumulator))))

(defun output-accumulator-ensure-file (accumulator)
  (unless (output-accumulator-temp-file-path accumulator)
    (let* ((path
             (merge-pathnames
              (format nil "~A-~16,'0X.log"
                      (output-accumulator-temp-file-prefix accumulator)
                      (random (ash 1 64)))
              (uiop:temporary-directory)))
           (stream
             (open path :direction :output :if-exists :supersede
                        :if-does-not-exist :create
                        :element-type '(unsigned-byte 8))))
      (write-sequence (output-accumulator-raw-history accumulator) stream)
      (setf (output-accumulator-temp-file-path accumulator) path
            (output-accumulator-temp-file-stream accumulator) stream
            (fill-pointer (output-accumulator-raw-history accumulator)) 0)))
  (output-accumulator-temp-file-path accumulator))

(defun output-accumulator-append (accumulator data)
  (when (output-accumulator-finished-p accumulator)
    (error "Cannot append to a finished output accumulator"))
  (let ((octets (octet-vector data)))
    (incf (output-accumulator-total-raw-bytes accumulator) (length octets))
    (if (output-accumulator-temp-file-stream accumulator)
        (write-sequence octets (output-accumulator-temp-file-stream accumulator))
        (loop for octet across octets
              do (vector-push-extend
                  octet (output-accumulator-raw-history accumulator))))
    (multiple-value-bind (text pending)
        (decode-complete-utf8
         (concatenate-octets
          (output-accumulator-pending accumulator) octets))
      (setf (output-accumulator-pending accumulator) pending)
      (output-accumulator-append-decoded accumulator text))
    (when (output-accumulator-needs-file-p accumulator)
      (output-accumulator-ensure-file accumulator)))
  accumulator)

(defun output-accumulator-finish (accumulator)
  (unless (output-accumulator-finished-p accumulator)
    (setf (output-accumulator-finished-p accumulator) t)
    (when (plusp (length (output-accumulator-pending accumulator)))
      (output-accumulator-append-decoded accumulator (string (code-char #xfffd)))
      (setf (output-accumulator-pending accumulator)
            (make-array 0 :element-type '(unsigned-byte 8))))
    (when (output-accumulator-needs-file-p accumulator)
      (output-accumulator-ensure-file accumulator)))
  accumulator)

(defun output-accumulator-snapshot
    (accumulator &key persist-if-truncated-p)
  (multiple-value-bind (content details)
      (truncate-tail
       (output-accumulator-snapshot-text accumulator)
       :max-lines (output-accumulator-max-lines accumulator)
       :max-bytes (output-accumulator-max-bytes accumulator))
    (let* ((truncated-p (output-accumulator-needs-file-p accumulator))
           (details (copy-list details)))
      (setf (getf details :truncated) truncated-p
            (getf details :total-lines)
            (output-accumulator-total-lines accumulator)
            (getf details :total-bytes)
            (output-accumulator-total-decoded-bytes accumulator))
      (when (and persist-if-truncated-p truncated-p)
        (output-accumulator-ensure-file accumulator))
      (make-output-snapshot
       :content content :truncation details
       :full-output-path
       (and (output-accumulator-temp-file-path accumulator)
            (namestring (output-accumulator-temp-file-path accumulator)))))))

(defun output-accumulator-close-temp-file (accumulator)
  (let ((stream (output-accumulator-temp-file-stream accumulator)))
    (when stream
      (finish-output stream)
      (close stream)
      (setf (output-accumulator-temp-file-stream accumulator) nil)))
  nil)

(defun output-accumulator-last-line-bytes (accumulator)
  (output-accumulator-current-line-bytes accumulator))
