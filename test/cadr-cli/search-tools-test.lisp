(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(test glob-is-recursive-stable-limited-and-ignores-heavy-directories
  (with-test-directory (directory)
    (write-text (merge-pathnames "src/a.lisp" directory) "a")
    (write-text (merge-pathnames "src/nested/b.lisp" directory) "b")
    (write-text (merge-pathnames "node_modules/x.lisp" directory) "x")
    (write-text (merge-pathnames ".git/y.lisp" directory) "y")
    (let ((tool (make-glob-tool directory)))
      (multiple-value-bind (content details)
          (invoke-tool tool
                       (args "pattern" "**/*.lisp"
                             "path" "."
                             "limit" 1))
        (is (string= "src/a.lisp" (result-text content)))
        (is (eq t (getf details :truncated))))
      (multiple-value-bind (content details)
          (invoke-tool tool
                       (args "pattern" "**/*.lisp"
                             "path" "."
                             "limit" 10))
        (declare (ignore details))
        (is (equal '("src/a.lisp" "src/nested/b.lisp")
                   (uiop:split-string
                    (result-text content)
                    :separator '(#\Newline))))))))

(test grep-supports-regex-literal-context-filter-and-limit
  (with-test-directory (directory)
    (write-text
     (merge-pathnames "src/a.txt" directory)
     (format nil "before~%Needle 42~%after~%"))
    (write-text
     (merge-pathnames "src/b.log" directory)
     (format nil "needle 7~%"))
    (let ((tool (make-grep-tool directory)))
      (multiple-value-bind (content details)
          (invoke-tool
           tool
           (args "pattern" "needle [0-9]+"
                 "path" "."
                 "glob" "**/*.txt"
                 "ignore_case" t
                 "context" 1
                 "limit" 10))
        (declare (ignore details))
        (is (search "src/a.txt:2: Needle 42"
                    (result-text content)))
        (is (search "src/a.txt-1- before"
                    (result-text content)))
        (is (not (search "b.log"
                         (result-text content)))))
      (multiple-value-bind (content details)
          (invoke-tool
           tool
           (args "pattern" "Needle 42"
                 "literal" t
                 "path" "."
                 "limit" 1))
        (is (search "Needle 42" (result-text content)))
        (is (= 1 (getf details :match-limit-reached)))))))

(test glob-and-grep-follow-parseable-gitignore-rules
  (with-test-directory (directory)
    (write-text
     (merge-pathnames ".gitignore" directory)
     (format nil "*.log~%build/~%!important.log~%"))
    (write-text (merge-pathnames "debug.log" directory) "needle")
    (write-text (merge-pathnames "important.log" directory) "needle")
    (write-text (merge-pathnames "build/generated.lisp" directory)
                "needle")
    (write-text (merge-pathnames "src/kept.lisp" directory) "needle")
    (write-text
     (merge-pathnames "src/.gitignore" directory)
     (format nil "private.txt~%"))
    (write-text (merge-pathnames "src/private.txt" directory) "needle")
    (let ((glob-tool (make-glob-tool directory))
          (grep-tool (make-grep-tool directory)))
      (multiple-value-bind (content details)
          (invoke-tool
           glob-tool (args "pattern" "**/*" "limit" 100))
        (declare (ignore details))
        (let ((text (result-text content)))
          (is (search "important.log" text))
          (is (search "src/kept.lisp" text))
          (is (not (search "debug.log" text)))
          (is (not (search "build/generated.lisp" text)))
          (is (not (search "src/private.txt" text)))))
      (multiple-value-bind (content details)
          (invoke-tool
           grep-tool
           (args "pattern" "needle" "literal" t "limit" 100))
        (declare (ignore details))
        (let ((text (result-text content)))
          (is (search "important.log" text))
          (is (search "src/kept.lisp" text))
          (is (not (search "debug.log" text)))
          (is (not (search "generated.lisp" text)))
          (is (not (search "private.txt" text))))))))

(test nested-gitignore-rules-do-not-leak-into-sibling-trees
  (with-test-directory (directory)
    (write-text
     (merge-pathnames "a/.gitignore" directory)
     (format nil "ignored.txt~%"))
    (write-text
     (merge-pathnames "a/deep/.gitignore" directory)
     (format nil "secret.txt~%"))
    (dolist (path '("a/ignored.txt"
                    "a/kept.txt"
                    "a/deep/ignored.txt"
                    "a/deep/secret.txt"
                    "a/deep/kept.txt"
                    "b/ignored.txt"
                    "b/kept.txt"
                    "root.txt"))
      (write-text (merge-pathnames path directory) ""))
    (multiple-value-bind (content details)
        (invoke-tool
         (make-glob-tool directory)
         (args "pattern" "**/*.txt" "limit" 100))
      (declare (ignore details))
      (is
       (equal
        '("a/deep/kept.txt"
          "a/kept.txt"
          "b/ignored.txt"
          "b/kept.txt"
          "root.txt")
        (uiop:split-string
         (result-text content)
         :separator '(#\Newline)))))))

(test grep-output-is-bounded-by-utf8-bytes-even-with-context
  (with-test-directory (directory)
    (write-text
     (merge-pathnames "large.txt" directory)
     (format nil "~{~A~%~}"
             (loop repeat 100
                   collect
                   (concatenate
                    'string "needle-"
                    (make-string 9993
                                 :initial-element #\x)))))
    (multiple-value-bind (content details)
        (invoke-tool
         (make-grep-tool directory)
         (args "pattern" "needle"
               "literal" t
               "context" 1
               "limit" 100))
      (is (search "50.0KB limit reached"
                  (result-text content)))
      (is (eq t
              (getf (getf details :truncation)
                    :truncated))))))
