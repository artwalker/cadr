(in-package #:cadr-tui/tests)
(in-suite cadr-tui-suite)

(test word-navigation-matches-ascii-path-cjk-and-punctuation
  (flet ((backward (text cursor)
           (cadr-tui:find-word-backward text cursor))
         (forward (text cursor)
           (cadr-tui:find-word-forward text cursor)))
    (is (= 6 (backward "hello world" 11)))
    (is (= 0 (backward "hello world" 6)))
    (is (= 4 (backward "foo.bar" 7)))
    (is (= 3 (backward "foo.bar" 4)))
    (is (= 0 (backward "foo.bar" 3)))
    (is (= 8 (backward "path/to/file" 12)))
    (is (= 7 (backward "path/to/file" 8)))
    (is (= 5 (backward "path/to/file" 7)))
    (is (= 4 (backward "path/to/file" 5)))
    (is (= 0 (backward "path/to/file" 4)))
    (is (= 5 (backward "你好世界 test" 9)))
    (is (= 2 (backward "你好世界 test" 5)))
    (is (= 0 (backward "你好世界 test" 2)))
    (is (= 2 (backward "  hello  " 9)))
    (is (= 6 (backward "foo...bar" 9)))
    (is (= 3 (backward "foo...bar" 6)))
    (is (= 0 (backward "hello" 0)))
    (is (= 5 (forward "hello world" 0)))
    (is (= 11 (forward "hello world" 5)))
    (is (= 3 (forward "foo.bar" 0)))
    (is (= 4 (forward "foo.bar" 3)))
    (is (= 7 (forward "foo.bar" 4)))
    (is (= 4 (forward "path/to/file" 0)))
    (is (= 5 (forward "path/to/file" 4)))
    (is (= 7 (forward "path/to/file" 5)))
    (is (= 8 (forward "path/to/file" 7)))
    (is (= 12 (forward "path/to/file" 8)))
    (is (= 7 (forward "  hello  " 0)))
    (is (= 9 (forward "  hello  " 7)))
    (is (= 3 (forward "foo...bar" 0)))
    (is (= 6 (forward "foo...bar" 3)))
    (is (= 9 (forward "foo...bar" 6)))
    (is (= 5 (forward "hello" 5)))))

(test word-navigation-treats-paste-markers-as-atomic
  (let* ((marker "[paste #1 +5 lines]")
         (text
           (format nil "hello ~A world" marker)))
    (is
     (= 26
        (cadr-tui:find-word-backward
         text (length text)
         :atomic-segments (list marker))))
    (is
     (= 6
        (cadr-tui:find-word-backward
         text 26
         :atomic-segments (list marker))))
    (is
     (= (+ 6 (length marker))
        (cadr-tui:find-word-forward
         text 6
         :atomic-segments (list marker))))))
