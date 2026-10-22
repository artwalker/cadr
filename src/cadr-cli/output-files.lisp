;;; pi@4a080252f utils/output-files.ts. Truncated tool output can contain
;;; private data, so the file is created mode #o600 and O_EXCL. O_EXCL fails
;;; when the name already exists, including when that name is a symlink.
(in-package #:cadr-cli)

(defun output-file-name (prefix extension)
  (format nil "~A-~A~A"
          prefix
          (cadr-ai:octets-hex (cadr-ai::secure-random-bytes 8))
          extension))

(defun exclusive-output-stream
    (path &key (element-type 'character) (external-format :utf-8))
  (let ((descriptor
          (sb-posix:open
           (namestring path)
           (logior sb-posix:o-wronly
                   sb-posix:o-creat
                   sb-posix:o-excl)
           #o600)))
    (apply #'sb-sys:make-fd-stream
           descriptor
           :output t
           :element-type element-type
           :buffering :full
           :auto-close t
           :name (pathname path)
           (if (subtypep element-type 'character)
               (list :external-format external-format)
               nil))))

(defun open-output-file-stream
    (prefix extension &key (element-type 'character)
                           (external-format :utf-8))
  (loop repeat 8
        for path = (merge-pathnames
                    (output-file-name prefix extension)
                    (uiop:temporary-directory))
        do (handler-case
               (return
                 (values path
                         (exclusive-output-stream
                          path
                          :element-type element-type
                          :external-format external-format)))
             (sb-posix:syscall-error (condition)
               (unless (= (sb-posix:syscall-errno condition)
                          sb-posix:eexist)
                 (error condition))))
        finally (error "Unable to allocate an output file")))

(defun write-output-file (prefix extension data)
  (let ((binary-p (not (stringp data))))
    (multiple-value-bind (path stream)
        (open-output-file-stream
         prefix extension
         :element-type (if binary-p '(unsigned-byte 8) 'character))
      (unwind-protect
           (progn
             (if binary-p
                 (write-sequence data stream)
                 (write-string data stream))
             (finish-output stream))
        (when (open-stream-p stream)
          (close stream)))
      (namestring path))))

(defun write-mcp-output-file (data extension)
  (write-output-file "cadr-mcp" extension data))

(defun mcp-content-type (block)
  (let ((type (getf block :type)))
    (etypecase type
      (keyword type)
      (string (intern (string-upcase type) :keyword)))))

(defun mcp-content-text (blocks)
  (with-output-to-string (out)
    (loop with first-p = t
          for block in blocks
          when (eq (mcp-content-type block) :text)
            do (if first-p
                   (setf first-p nil)
                   (write-char #\Newline out))
               (write-string (or (getf block :text) "") out))))

(defun mcp-output-line-count (content)
  (if (zerop (length content))
      0
      (let ((newlines (count #\Newline content)))
        (if (char= (char content (1- (length content))) #\Newline)
            newlines
            (1+ newlines)))))

(defun mcp-utf8-boundary-p (octets index)
  (or (>= index (length octets))
      (/= (logand (aref octets index) #xc0) #x80)))

(defun mcp-octets-string (octets start end)
  (sb-ext:octets-to-string
   (subseq octets start end)
   :external-format :utf-8))

(defun truncate-mcp-middle (content max-bytes)
  ;; pi@4a080252f truncateMiddle: keep half the byte budget at each end and
  ;; mark the omitted code points. Cuts only on UTF-8 character boundaries.
  (let* ((octets (cadr-ai::utf8-octets content))
         (total (length octets))
         (lines (mcp-output-line-count content)))
    (when (<= total max-bytes)
      (return-from truncate-mcp-middle
        (values content nil 0 total lines)))
    (let ((head-end (floor max-bytes 2))
          (tail-start
            (- total (- max-bytes (floor max-bytes 2)))))
      (loop while (and (> head-end 0)
                       (not (mcp-utf8-boundary-p octets head-end)))
            do (decf head-end))
      (loop while (and (< tail-start total)
                       (not (mcp-utf8-boundary-p octets tail-start)))
            do (incf tail-start))
      (let ((removed
              (length (mcp-octets-string octets head-end tail-start))))
        (values
         (concatenate
          'string
          (mcp-octets-string octets 0 head-end)
          (format nil "…~D chars truncated…" removed)
          (mcp-octets-string octets tail-start total))
         t
         removed
         total
         lines)))))

(defun limit-mcp-content
    (blocks &key (max-bytes (* 20 1024))
                 (save-output #'write-mcp-output-file))
  ;; pi@4a080252f limitMcpContent: text over the byte budget becomes one
  ;; warning block plus the saved original. Image blocks stay after it.
  (let ((combined (mcp-content-text blocks)))
    (multiple-value-bind (text truncated removed total lines)
        (truncate-mcp-middle combined max-bytes)
      (declare (ignore removed))
      (unless truncated
        (return-from limit-mcp-content (values blocks nil)))
      (let ((path nil)
            (where nil))
        (handler-case
            (progn
              (setf path (funcall save-output combined ".txt"))
              (setf where
                    (format nil
                            "[Full output: ~A (read it with offset/limit)]"
                            path)))
          (error (condition)
            (setf path nil)
            (setf where
                  (format nil
                          "[Could not save the full output: ~A]"
                          condition))))
        (values
         (cons (list :type :text
                     :text
                     (format nil
                             "Warning: truncated output (original token count: ~D)~%Total output lines: ~D~%~%~A~%~%~A"
                             (ceiling total 4)
                             lines
                             text
                             where))
               (loop for block in blocks
                     when (eq (mcp-content-type block) :image)
                       collect block))
         path)))))
