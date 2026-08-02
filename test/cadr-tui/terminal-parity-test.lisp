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

(test apple-terminal-native-modifier-fixtures-match-coregraphics-masks
  (dolist (spec '((:shift #x00020000)
                  (:control #x00040000)
                  (:option #x00080000)
                  (:command #x00100000)))
    (destructuring-bind (key mask) spec
      (is
       (cadr-tui::native-modifier-pressed-p
        key t "arm64" (lambda () mask)))
      (is
       (cadr-tui::native-modifier-pressed-p
        (string-downcase (symbol-name key))
        t "x86-64" (lambda () mask)))
      (is
       (not
        (cadr-tui::native-modifier-pressed-p
         key t "arm64" (constantly 0))))))
  (is
   (not
    (cadr-tui::native-modifier-pressed-p
     :unknown t "arm64" (constantly #xffffffffffffffff)))))

(test apple-terminal-native-modifier-query-is-fail-closed
  (let ((queries 0))
    (flet ((flags ()
             (incf queries)
             #x00020000))
      (is
       (not
        (cadr-tui::native-modifier-pressed-p
         :shift nil "arm64" #'flags)))
      (is (= 0 queries))
      (is
       (not
        (cadr-tui::native-modifier-pressed-p
         :shift t "powerpc" #'flags)))
      (is (= 0 queries))))
  (is
   (not
    (cadr-tui::native-modifier-pressed-p
     :shift t "arm64"
     (lambda () (error "fixture failure")))))
  #-darwin
  (is (not (cadr-tui::is-native-modifier-pressed :shift))))

(test apple-terminal-session-detection-matches-baseline
  (flet ((apple-environment (name)
           (and (string= name "TERM_PROGRAM")
                "Apple_Terminal"))
         (iterm-environment (name)
           (and (string= name "TERM_PROGRAM")
                "iTerm.app")))
    (is
     (cadr-tui::apple-terminal-session-with-environment-p
      t #'apple-environment))
    (is
     (not
      (cadr-tui::apple-terminal-session-with-environment-p
       nil #'apple-environment)))
    (is
     (not
      (cadr-tui::apple-terminal-session-with-environment-p
       t #'iterm-environment)))))

(test process-terminal-queries-shift-only-for-apple-terminal-return
  (let* ((queries nil)
        (terminal
          (cadr-tui:make-process-terminal
           :input (make-string-input-stream (string #\Return))
           :output (make-string-output-stream)
           :apple-terminal-function (constantly t)
           :native-modifier-function
           (lambda (key)
             (push key queries)
             t))))
    (is (string= (csi "13;2u")
                 (cadr-tui:terminal-read-input terminal)))
    (is (equal '(:shift) queries)))
  (dolist (spec
           (list
            (list (string #\Return) nil t (string #\Return))
            (list (string #\Return) t nil (string #\Return))
            (list "x" t t "x")))
    (destructuring-bind
        (input apple-terminal-p shift-pressed-p expected) spec
      (let* ((queries 0)
            (terminal
              (cadr-tui:make-process-terminal
               :input (make-string-input-stream input)
               :output (make-string-output-stream)
               :apple-terminal-function
               (constantly apple-terminal-p)
               :native-modifier-function
               (lambda (key)
                 (declare (ignore key))
                 (incf queries)
                 shift-pressed-p))))
        (is (string= expected
                     (cadr-tui:terminal-read-input terminal)))
        (is (= (if (and apple-terminal-p
                        (string= input (string #\Return)))
                   1
                   0)
               queries))))))

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

(test process-terminal-preserves-batched-input-event-boundaries
  (let* ((press
           (format nil "~C[<0;2;1M" #\Escape))
         (drag
           (format nil "~C[<32;4;1M" #\Escape))
         (release
           (format nil "~C[<0;4;1m" #\Escape))
         (terminal
           (cadr-tui:make-process-terminal
            :input
            (make-string-input-stream
             (concatenate
              'string press drag release))
            :output
            (make-string-output-stream))))
    (is (string=
         press
         (cadr-tui:terminal-read-input terminal)))
    (is (string=
         drag
         (cadr-tui:terminal-read-input terminal)))
    (is (string=
         release
         (cadr-tui:terminal-read-input terminal)))
    (is (string=
         ""
         (cadr-tui:terminal-read-input terminal)))))

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
