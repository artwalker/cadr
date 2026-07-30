(in-package #:cadr-tui/tests)
(in-suite cadr-tui-suite)

(test apple-terminal-return-normalization
  (is (string=
       (csi "13;2u")
       (cadr-tui:normalize-apple-terminal-input
        (string #\Return) t t)))
  (is (string=
       (string #\Return)
       (cadr-tui:normalize-apple-terminal-input
        (string #\Return) t nil)))
  (is (string=
       (string #\Return)
       (cadr-tui:normalize-apple-terminal-input
        (string #\Return) nil t)))
  (is (string=
       "x"
       (cadr-tui:normalize-apple-terminal-input
        "x" t t))))

(test keyboard-protocol-negotiation-matches-kitty-fallback-order
  (let ((negotiator
          (cadr-tui:make-keyboard-protocol-negotiator)))
    (is (string=
         (format nil "~C[>7u~C[?u~C[c"
                 #\Escape #\Escape #\Escape)
         (cadr-tui:keyboard-protocol-query)))
    (multiple-value-bind (forward writes)
        (cadr-tui:keyboard-protocol-consume
         negotiator "a")
      (is (equal '("a") forward))
      (is (null writes)))
    (multiple-value-bind (forward writes)
        (cadr-tui:keyboard-protocol-consume
         negotiator (csi "?7"))
      (is (null forward))
      (is (null writes)))
    (multiple-value-bind (forward writes)
        (cadr-tui:keyboard-protocol-consume
         negotiator "u")
      (is (null forward))
      (is (null writes)))
    (is (eq :kitty
            (cadr-tui:keyboard-protocol-mode
             negotiator))))
  (let ((negotiator
          (cadr-tui:make-keyboard-protocol-negotiator)))
    (multiple-value-bind (forward writes)
        (cadr-tui:keyboard-protocol-consume
         negotiator (csi "?0u"))
      (is (null forward))
      (is (equal (list (csi ">4;2m")) writes)))
    (is (eq :modify-other-keys
            (cadr-tui:keyboard-protocol-mode
             negotiator))))
  (let ((negotiator
          (cadr-tui:make-keyboard-protocol-negotiator)))
    (multiple-value-bind (forward writes)
        (cadr-tui:keyboard-protocol-consume
         negotiator (csi "?1;2c"))
      (is (null forward))
      (is (equal (list (csi ">4;2m")) writes)))))

(test keyboard-protocol-replays-incomplete-non-response
  (let ((negotiator
          (cadr-tui:make-keyboard-protocol-negotiator)))
    (multiple-value-bind (forward writes)
        (cadr-tui:keyboard-protocol-consume
         negotiator (csi ""))
      (is (null forward))
      (is (null writes)))
    (is (equal (list (csi ""))
               (cadr-tui:keyboard-protocol-flush
                negotiator)))))

(test process-terminal-splits-batched-capability-replies-from-user-input
  (let* ((escape (string #\Escape))
         (output (make-string-output-stream))
         (terminal
           (cadr-tui:make-process-terminal
            :input
            (make-string-input-stream
             (format nil "/~A[?1;2;4c" escape))
            :output output)))
    (is (string= "/"
                 (cadr-tui:terminal-read-input terminal)))
    (is (string=
         (format nil "~A[>4;2m" escape)
         (get-output-stream-string output))))
  (let ((terminal
          (cadr-tui:make-process-terminal
           :input
           (make-string-input-stream
            (format nil "~C[6;24;12tq" #\Escape))
           :output
           (make-string-output-stream))))
    (is (string= "q"
                 (cadr-tui:terminal-read-input terminal)))
    (is (equal
         '(12 24)
         (multiple-value-list
          (cadr-tui:get-cell-dimensions))))))

(test terminal-dimensions-use-environment-before-defaults
  (flet ((lookup (name)
           (cdr (assoc name
                       '(("COLUMNS" . "123")
                         ("LINES" . "45"))
                       :test #'string=))))
    (multiple-value-bind (columns rows)
        (cadr-tui:terminal-dimensions
         nil nil :environment-function #'lookup)
      (is (= 123 columns))
      (is (= 45 rows))))
  (flet ((lookup (name)
           (declare (ignore name))
           "not-a-number"))
    (multiple-value-bind (columns rows)
        (cadr-tui:terminal-dimensions
         nil nil :environment-function #'lookup)
      (is (= 80 columns))
      (is (= 24 rows)))))
