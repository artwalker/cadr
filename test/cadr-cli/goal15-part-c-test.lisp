(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defun make-goal15-fake-rg-program (directory)
  (let ((program (merge-pathnames "rg" directory)))
    (with-open-file
        (stream program
                :direction :output
                :if-exists :supersede
                :if-does-not-exist :create)
      (write-line "#!/bin/sh" stream)
      (write-line "for argument do search_path=$argument; done" stream)
      (write-line
       "printf '{\"type\":\"match\",\"data\":{\"path\":{\"text\":\"%s/beta.md\"},\"lines\":{\"text\":\"needle beta\\\\n\"},\"line_number\":1}}\\n' \"$search_path\""
       stream)
      (write-line
       "printf '{\"type\":\"match\",\"data\":{\"path\":{\"text\":\"%s/alpha.txt\"},\"lines\":{\"text\":\"needle alpha\\\\n\"},\"line_number\":1}}\\n' \"$search_path\""
       stream))
    (uiop:run-program (list "chmod" "+x" (namestring program)))
    program))

(test goal15-grep-preserves-fixed-baseline-ripgrep-stream-order
  (with-test-directory (directory)
    (let ((bin (merge-pathnames "bin/" directory))
          (notes (merge-pathnames "notes/" directory)))
      (ensure-directories-exist (merge-pathnames "anchor" bin))
      (write-text (merge-pathnames "alpha.txt" notes)
                  (format nil "needle alpha~%"))
      (write-text (merge-pathnames "beta.md" notes)
                  (format nil "needle beta~%"))
      (make-goal15-fake-rg-program bin)
      (with-test-path-prefix (bin)
        (multiple-value-bind (content details)
            (invoke-tool
             (cadr-cli::make-grep-tool directory)
             (args "pattern" "needle" "path" "notes"))
          (declare (ignore details))
          (is
           (string=
            (format nil
                    "beta.md:1: needle beta~%alpha.txt:1: needle alpha")
            (result-text content))))))))

(test goal15-ls-relative-subdirectory-lists-the-requested-directory
  (with-test-directory (directory)
    (write-text (merge-pathnames "root-decoy.txt" directory) "root")
    (write-text (merge-pathnames "notes/alpha.txt" directory) "alpha")
    (write-text (merge-pathnames "notes/beta.md" directory) "beta")
    (multiple-value-bind (content details)
        (invoke-tool
         (cadr-cli::make-ls-tool directory)
         (args "path" "notes"))
      (declare (ignore details))
      (is
       (string=
        (format nil "alpha.txt~%beta.md")
        (result-text content))))))

(test goal15-read-missing-relative-path-preserves-baseline-enoent-copy
  (with-test-directory (directory)
    (let* ((display-path "notes/missing.txt")
           (absolute-path
             (namestring (merge-pathnames display-path directory)))
           (expected
             (format nil
                     "ENOENT: no such file or directory, access '~A'"
                     absolute-path)))
      (handler-case
          (progn
            (invoke-tool
             (cadr-cli::make-read-tool directory)
             (args "path" display-path))
            (fail "missing read path should fail"))
        (condition (condition)
          (is (string= expected (princ-to-string condition))))))))

(test goal15-directory-tool-pathname-forms-stay-rooted-in-relative-subdirectories
  (with-test-directory (directory)
    (write-text (merge-pathnames "root-decoy.txt" directory) "root")
    (write-text (merge-pathnames "notes/nested/kept.txt" directory) "kept")
    (multiple-value-bind (content details)
        (invoke-tool
         (cadr-cli::make-find-tool directory)
         (args "pattern" "*.txt" "path" "notes"))
      (declare (ignore details))
      (is (search "nested/kept.txt" (result-text content)))
      (is (not (search "root-decoy.txt" (result-text content)))))
    (multiple-value-bind (content details)
        (invoke-tool
         (cadr-cli::make-glob-tool directory)
         (args "pattern" "**/*.txt" "path" "notes"))
      (declare (ignore details))
      (is (search "notes/nested/kept.txt" (result-text content)))
      (is (not (search "root-decoy.txt" (result-text content)))))
    (invoke-tool
     (cadr-cli::make-write-tool directory)
     (args "path" "notes/generated/result.txt" "content" "written"))
    (is
     (string=
      "written"
      (read-text
       (merge-pathnames "notes/generated/result.txt" directory))))))
