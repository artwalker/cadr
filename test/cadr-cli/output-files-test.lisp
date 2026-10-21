(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defun output-file-mode (path)
  (logand (sb-posix:stat-mode (sb-posix:stat (namestring path)))
          #o777))

(test output-file-is-private-and-exclusive
  ;; pi@71023aec1 output-files.ts: mode #o600 and wx, so a planted symlink
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
