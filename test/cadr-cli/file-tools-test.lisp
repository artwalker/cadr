(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(test read-supports-utf8-offset-limit-and-bounded-head-output
  (with-test-directory (directory)
    (let ((file (merge-pathnames "unicode.txt" directory)))
      (write-text file
                  (format nil "一~%二~%三~%四~%"))
      (multiple-value-bind (content details)
          (invoke-tool
           (make-read-tool directory)
           (args "path" "unicode.txt"
                 "offset" 2
                 "limit" 2))
        (declare (ignore details))
        (is (string= (format nil
                             "二~%三~%~%[2 more lines in file. Use offset=4 to continue.]")
                     (result-text content))))
      (signals error
        (invoke-tool
         (make-read-tool directory)
         (args "path" "unicode.txt" "offset" 99))))
    (let ((file (merge-pathnames "large.txt" directory)))
      (with-open-file (stream file
                              :direction :output
                              :if-exists :supersede
                              :if-does-not-exist :create)
        (loop repeat 2105
              for index from 1
              do (format stream "line ~D~%" index)))
      (multiple-value-bind (content details)
          (invoke-tool
           (make-read-tool directory)
           (args "path" "large.txt"))
        (is (search "line 1" (result-text content)))
        (is (not (search "line 2105" (result-text content))))
        (is (eq t (getf details :truncated)))))))

(test read-offset-matches-baseline-zero-negative-and-beyond-end-semantics
  (with-test-directory (directory)
    (let ((file (merge-pathnames "offsets.txt" directory))
          (tool (make-read-tool directory)))
      (write-text file (format nil "first~%second~%third"))
      (dolist (offset '(0 -7))
        (multiple-value-bind (content details)
            (invoke-tool
             tool
             (args "path" "offsets.txt" "offset" offset "limit" 1))
          (declare (ignore details))
          (is (search "first" (result-text content)))
          (is (null (search "second" (result-text content))))))
      (handler-case
          (progn
            (invoke-tool
             tool
             (args "path" "offsets.txt" "offset" 4))
            (fail "offset beyond EOF should fail"))
        (error (condition)
          (is
           (string=
            "Offset 4 is beyond end of file (3 lines total)"
            (princ-to-string condition)))))
      (let ((empty (merge-pathnames "empty.txt" directory)))
        (write-text empty "")
        (multiple-value-bind (content details)
            (invoke-tool tool (args "path" "empty.txt"))
          (declare (ignore details))
          (is (string= "" (result-text content))))))))

(test split-line-table-matches-js-split-join
  ;; Production read indexes a fixnum start vector, then one subseq,
  ;; matching JS split("\n") / slice / join("\n"). Empty and trailing
  ;; newline keep the extra "" part.
  (flet ((legacy (text)
           (if (zerop (length text))
               (list "")
               (uiop:split-string text :separator '(#\Newline)))))
    (dolist (text (list
                   ""
                   "a"
                   (format nil "a~%")
                   (format nil "a~%b")
                   (format nil "a~%b~%")
                   (format nil "~%")
                   (format nil "é🙂中文 mixed tail line~%x")
                   (format nil "~%~%")))
      (multiple-value-bind (starts source)
          (cadr-cli::split-line-starts text)
        (let ((parts (legacy text)))
          (is (= (length starts) (length parts)))
          (loop for index from 0 below (length starts)
                do (is (string=
                        (cadr-cli::split-line-ref source starts index)
                        (nth index parts))))
          (is (string=
               (cadr-cli::split-line-join
                source starts 0 (length starts))
               (cadr-cli::join-lines parts)))
          (when (> (length starts) 1)
            (is (string=
                 (cadr-cli::split-line-join
                  source starts 1 (length starts))
                 (cadr-cli::join-lines (cdr parts))))))))))

(test write-creates-parents-and-overwrites-utf8
  (with-test-directory (directory)
    (let ((tool (make-write-tool directory))
          (file (merge-pathnames "a/b.txt" directory)))
      (invoke-tool tool
                   (args "path" "a/b.txt"
                         "content" "第一版"))
      (is (string= "第一版" (read-text file)))
      (invoke-tool tool
                   (args "path" "a/b.txt"
                         "content" "第二版"))
      (is (string= "第二版" (read-text file))))))

(test edit-requires-unique-nonoverlapping-original-matches
  (with-test-directory (directory)
    (let ((tool (make-edit-tool directory))
          (file (merge-pathnames "code.txt" directory)))
      (write-text file "alpha beta gamma")
      (let ((edits
              (vector
               (args "oldText" "alpha" "newText" "A")
               (args "oldText" "gamma" "newText" "G"))))
        (invoke-tool tool
                     (args "path" "code.txt"
                           "edits" edits)))
      (is (string= "A beta G" (read-text file)))
      (signals error
        (invoke-tool
         tool
         (args "path" "code.txt"
               "edits"
               (vector
                (args "oldText" "missing"
                      "newText" "x")))))
      (write-text file "same same")
      (signals error
        (invoke-tool
         tool
         (args "path" "code.txt"
               "edits"
               (vector
                (args "oldText" "same"
                      "newText" "x")))))
      (write-text file "abcdef")
      (signals error
        (invoke-tool
         tool
         (args "path" "code.txt"
               "edits"
               (vector
                (args "oldText" "abcd" "newText" "x")
                (args "oldText" "bc" "newText" "y"))))))))
