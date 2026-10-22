(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defun output-file-mode (path)
  (logand (sb-posix:stat-mode (sb-posix:stat (namestring path)))
          #o777))

(test output-file-is-private-and-exclusive
  ;; pi@4a080252f output-files.ts: mode #o600 and wx, so a planted symlink
  ;; is not followed.
  (let ((path (cadr-cli::write-output-file "cadr-output" ".txt" "secret")))
    (unwind-protect
         (progn
           (is (cl-ppcre:scan
                "/cadr-output-[0-9a-f]{16}\\.txt$" path))
           (is (= #o600 (output-file-mode path)))
           (is (string= "secret" (uiop:read-file-string path))))
      (when (probe-file path)
        (delete-file path))))
  (let ((bytes (cadr-ai::utf8-octets "bytes"))
        (path nil))
    (unwind-protect
         (progn
           (setf path
                 (cadr-cli::write-output-file
                  "cadr-output" ".bin" bytes))
           (is (= #o600 (output-file-mode path)))
           (is (equalp bytes
                       (with-open-file
                           (in path :element-type '(unsigned-byte 8))
                         (let ((buffer
                                 (make-array (file-length in)
                                             :element-type
                                             '(unsigned-byte 8))))
                           (read-sequence buffer in)
                           buffer)))))
      (when (and path (probe-file path))
        (delete-file path))))
  (let* ((root
           (merge-pathnames
            (format nil "cadr-output-files-~A/"
                    (cadr-ai:octets-hex
                     (cadr-ai::secure-random-bytes 4)))
            (uiop:temporary-directory)))
         (sentinel (merge-pathnames "secret" root))
         (link (merge-pathnames "link" root))
         (occupied (merge-pathnames "occupied" root)))
    (ensure-directories-exist sentinel)
    (unwind-protect
         (progn
           (with-open-file (out sentinel :direction :output
                                     :if-exists :supersede)
             (write-string "keep" out))
           (sb-posix:symlink (namestring sentinel) (namestring link))
           (signals sb-posix:syscall-error
             (cadr-cli::exclusive-output-stream link))
           (is (string= "keep" (uiop:read-file-string sentinel)))
           (with-open-file (out occupied :direction :output
                                       :if-exists :supersede)
             (write-string "stay" out))
           (signals sb-posix:syscall-error
             (cadr-cli::exclusive-output-stream occupied))
           (is (string= "stay" (uiop:read-file-string occupied))))
      (uiop:delete-directory-tree
       root :validate t :if-does-not-exist :ignore))))

(test output-accumulator-temp-file-is-private
  (let* ((accumulator
           (cadr-cli:make-output-accumulator
            :max-lines 2 :max-bytes 4
            :temp-file-prefix "cadr-output"))
         (path nil))
    (unwind-protect
         (progn
           (cadr-cli:output-accumulator-append accumulator "hello")
           (cadr-cli:output-accumulator-finish accumulator)
           (setf path
                 (cadr-cli:output-snapshot-full-output-path
                  (cadr-cli:output-accumulator-snapshot
                   accumulator :persist-if-truncated-p t)))
           (cadr-cli:output-accumulator-close-temp-file accumulator)
           (is (cl-ppcre:scan
                "/cadr-output-[0-9a-f]{16}\\.log$" path))
           (is (= #o600 (output-file-mode path)))
           (is (string= "hello"
                        (uiop:read-file-string path))))
      (cadr-cli:output-accumulator-close-temp-file accumulator)
      (when (and path (probe-file path))
        (delete-file path)))))

(test mcp-content-over-the-byte-budget-is-cut-in-the-middle
  ;; pi@4a080252f limitMcpContent / truncateMiddle.
  (let ((short
          (list (list :type :text :text "ok")
                (list :type :image :data "img"))))
    (multiple-value-bind (content path)
        (cadr-cli::limit-mcp-content short :max-bytes 20)
      (is (null path))
      (is (equal short content))))
  (let ((boundary (make-string (* 20 1024) :initial-element #\a)))
    (multiple-value-bind (content path)
        (cadr-cli::limit-mcp-content
         (list (list :type :text :text boundary)))
      (is (null path))
      (is (string= boundary (getf (first content) :text)))))
  (let* ((source (concatenate 'string "aaaa" "你" "bbbb"))
         (image (list :type :image :data "img"))
         (path nil))
    (unwind-protect
         (multiple-value-bind (content saved)
             (cadr-cli::limit-mcp-content
              (list (list :type :text :text source)
                    image)
              :max-bytes 9)
           (setf path saved)
           (is (cl-ppcre:scan "/cadr-mcp-[0-9a-f]{16}\\.txt$" path))
           (is (= #o600 (output-file-mode path)))
           (is (string= source (uiop:read-file-string path)))
           (is (= 2 (length content)))
           (is (eq :image (getf (second content) :type)))
           (is (string=
                (format nil
                        "Warning: truncated output (original token count: ~D)~%Total output lines: 1~%~%aaaa…1 chars truncated…bbbb~%~%[Full output: ~A (read it with offset/limit)]"
                        (ceiling 11 4)
                        path)
                (getf (first content) :text))))
      (when (and path (probe-file path))
        (delete-file path))))
  (multiple-value-bind (content path)
      (cadr-cli::limit-mcp-content
       (list (list :type :text :text "abcdef"))
       :max-bytes 4
       :save-output (lambda (data extension)
                      (declare (ignore data extension))
                      (error "disk full")))
    (is (null path))
    (is (search "Could not save the full output: disk full"
                (getf (first content) :text))))
  (let ((joined nil))
    (cadr-cli::limit-mcp-content
     (list (list :type :text :text "aa")
           (list :type :text :text "bb"))
     :max-bytes 4
     :save-output (lambda (data extension)
                    (declare (ignore extension))
                    (setf joined data)
                    "saved.txt"))
    (is (string= (format nil "aa~%bb") joined))))
