(in-package #:cadr-tui/tests)

(in-suite cadr-tui-suite)

(test terminal-color-reports-are-strictly-parsed
  (let ((bell (string (code-char 7)))
        (escape (string #\Escape)))
    (dolist (case
             (list
              (list
               (concatenate 'string
                            escape "]11;rgb:ffff/8000/0000"
                            bell)
               '(255 128 0))
              (list
               (concatenate 'string
                            escape "]11;#112233"
                            escape "\\")
               '(17 34 51))
              (list
               (concatenate 'string
                            escape "]11;#ffff80000000"
                            bell)
               '(255 128 0))))
      (let ((color
              (cadr-tui:parse-osc-11-background-color
               (first case))))
        (is (not (null color)))
        (is (equal
             (second case)
             (list (cadr-tui:rgb-color-red color)
                   (cadr-tui:rgb-color-green color)
                   (cadr-tui:rgb-color-blue color))))))
    (is (null
         (cadr-tui:parse-osc-11-background-color
          (concatenate 'string
                       "prefix" escape "]11;#112233"
                       bell))))
    (is (null
         (cadr-tui:parse-osc-11-background-color
          (concatenate 'string
                       escape "]11;#123" bell))))
    (is (eq :dark
            (cadr-tui:parse-terminal-color-scheme-report
             (format nil "~C[?997;1n" #\Escape))))
    (is (eq :light
            (cadr-tui:parse-terminal-color-scheme-report
             (format nil "~C[?997;2n" #\Escape))))
    (is (null
         (cadr-tui:parse-terminal-color-scheme-report
          (format nil "~C[?997;3n" #\Escape))))))

(test terminal-response-filter-consumes-only-control-replies
  (let* ((filter
           (cadr-tui:make-terminal-response-filter))
         (escape (string #\Escape))
         (reply
           (concatenate 'string
                        escape "]11;#abcdef"
                        (string (code-char 7)))))
    (cadr-tui:terminal-response-expect-color filter)
    (multiple-value-bind (consumed value)
        (cadr-tui:terminal-response-consume filter reply)
      (is (not (null consumed)))
      (is (equal
           '(171 205 239)
           (list (cadr-tui:rgb-color-red value)
                 (cadr-tui:rgb-color-green value)
                 (cadr-tui:rgb-color-blue value)))))
    (multiple-value-bind (consumed value)
        (cadr-tui:terminal-response-consume filter "x")
      (is (not consumed))
      (is (string= "x" value)))
    (multiple-value-bind (consumed value)
        (cadr-tui:terminal-response-consume
         filter
         (format nil "~C[6;20;10t" #\Escape))
      (is (not (null consumed)))
      (is (equal '(10 20) value)))
    (is (equal
         '(10 20)
         (multiple-value-list
          (cadr-tui:get-cell-dimensions))))))
