(in-package #:cadr-tui/tests)
(in-suite cadr-tui-suite)

(test fuzzy-match-scores-reference-cases
  (multiple-value-bind (matched-p score)
      (cadr-tui:fuzzy-match "" "anything")
      (is (not (null matched-p)))
    (is (zerop score)))
  (is (not (nth-value
            0
            (cadr-tui:fuzzy-match
             "longquery" "short"))))
  (multiple-value-bind (matched-p score)
      (cadr-tui:fuzzy-match "test" "test")
      (is (not (null matched-p)))
    (is (minusp score)))
  (is (nth-value
       0
       (cadr-tui:fuzzy-match "abc" "aXbXc")))
  (is (not (nth-value
            0
            (cadr-tui:fuzzy-match "abc" "cba"))))
  (is (nth-value
       0
       (cadr-tui:fuzzy-match "ABC" "abc")))
  (is
   (< (nth-value
       1
       (cadr-tui:fuzzy-match "foo" "foobar"))
      (nth-value
       1
       (cadr-tui:fuzzy-match "foo" "f_o_o_bar"))))
  (is
   (< (nth-value
       1
       (cadr-tui:fuzzy-match "fb" "foo-bar"))
      (nth-value
       1
       (cadr-tui:fuzzy-match "fb" "afbx"))))
  (is (nth-value
       0
       (cadr-tui:fuzzy-match
        "codex52" "gpt-5.2-codex"))))

(test fuzzy-match-long-haystack-early-miss
  (let ((haystack
          (concatenate
           'string
           (make-string 4096 :initial-element #\a)
           "xyz")))
    (is (not (nth-value
              0
              (cadr-tui:fuzzy-match "q" haystack))))
    (multiple-value-bind (matched-p score)
        (cadr-tui:fuzzy-match "xyz" haystack)
      (is (not (null matched-p)))
      (is (> score 0d0)))))

(test fuzzy-filter-orders-and-tokenizes
  (is
   (equal
    '("apple" "banana" "cherry")
    (cadr-tui:fuzzy-filter
     '("apple" "banana" "cherry") "" #'identity)))
  (is
   (equal
    '("banana")
    (cadr-tui:fuzzy-filter
     '("apple" "banana" "cherry") "an" #'identity)))
  (is
   (string=
    "app"
    (first
     (cadr-tui:fuzzy-filter
      '("a_p_p" "app" "application")
      "app" #'identity))))
  (is
   (equal
    '("cl" "clone")
    (cadr-tui:fuzzy-filter
     '("clone" "cl") "cl" #'identity)))
  (let ((item '(:id "gpt-5.5"
                :provider "openai-codex")))
    (is
     (equal
      (list item)
      (cadr-tui:fuzzy-filter
       (list item)
       "openai-codex/gpt-5.5"
       (lambda (entry)
         (format nil "~A ~A"
                 (getf entry :id)
                 (getf entry :provider))))))))
