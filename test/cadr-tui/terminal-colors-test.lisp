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
    (multiple-value-bind (consumed value)
        (cadr-tui:terminal-response-consume filter reply)
      (is (not consumed))
      (is (string= reply value)))
    (is (equal
         '(10 20)
         (multiple-value-list
          (cadr-tui:get-cell-dimensions))))))

(test terminal-response-filter-consumes-color-scheme-reports
  (let ((filter
          (cadr-tui:make-terminal-response-filter)))
    (dolist (case
             (list
              (cons (format nil "~C[?997;1n" #\Escape)
                    :dark)
              (cons (format nil "~C[?997;2n" #\Escape)
                    :light)))
      (multiple-value-bind (consumed value)
          (cadr-tui:terminal-response-consume
           filter (car case))
        (is (not (null consumed)))
        (is (eq (cdr case) value))))
    (multiple-value-bind (consumed value)
        (cadr-tui:terminal-response-consume filter "typed")
      (is (not consumed))
      (is (string= "typed" value)))))

(test process-terminal-preserves-typed-input-while-capturing-osc11
  (let* ((terminal
           (cadr-tui:make-process-terminal
            :input (make-string-input-stream "")
            :output (make-string-output-stream)))
         (filter
           (cadr-tui::process-terminal-response-filter
            terminal))
         (reply
           (format nil "~C]11;#f0e0d0~C"
                   #\Escape (code-char 7))))
    (cadr-tui:terminal-response-expect-color filter)
    (is (equal
         '("typed")
         (cadr-tui::process-terminal-consume-sequence
          terminal "typed" nil)))
    (is (null
         (cadr-tui::process-terminal-consume-sequence
          terminal reply nil)))
    (let ((color
            (cadr-tui::process-terminal-background-response
             terminal)))
      (is (not (null color)))
      (is (equal
           '(240 224 208)
           (list
            (cadr-tui:rgb-color-red color)
            (cadr-tui:rgb-color-green color)
            (cadr-tui:rgb-color-blue color)))))))

(test process-terminal-consumes-scheme-notifications-without-losing-input
  (let ((terminal
          (cadr-tui:make-process-terminal
           :input (make-string-input-stream "")
           :output (make-string-output-stream))))
    (is (equal
         '("typed")
         (cadr-tui::process-terminal-consume-sequence
          terminal "typed" nil)))
    (is (null
         (cadr-tui::process-terminal-consume-sequence
          terminal
          (format nil "~C[?997;2n" #\Escape)
          nil)))
    (is (eq :light
            (cadr-tui:terminal-color-scheme-change
             terminal)))
    (is (null
         (cadr-tui:terminal-color-scheme-change
          terminal)))))

(test process-terminal-color-scheme-query-preserves-concurrent-input
  (let* ((reply
           (format nil "typed~C[?997;1n" #\Escape))
         (output
           (make-string-output-stream))
         (terminal
           (cadr-tui:make-process-terminal
            :input (make-string-input-stream reply)
            :output output)))
    (setf
     (cadr-tui::process-terminal-started-p terminal)
     t)
    (is (eq :dark
            (cadr-tui:terminal-query-color-scheme
             terminal :timeout-seconds 0.1d0)))
    (is (search
         (format nil "~C[?996n" #\Escape)
         (get-output-stream-string output)))
    (is (string=
         "typed"
         (with-output-to-string (stream)
           (loop repeat 5
                 do
                    (write-string
                     (cadr-tui:terminal-read-input terminal)
                     stream)))))
    (setf
     (cadr-tui::process-terminal-started-p terminal)
     nil)))

(test process-terminal-color-scheme-notification-lifecycle
  (let* ((output
           (make-string-output-stream))
         (terminal
           (cadr-tui:make-process-terminal
            :input (make-string-input-stream "")
            :output output)))
    (setf
     (cadr-tui::process-terminal-started-p terminal)
     t)
    (cadr-tui:terminal-set-color-scheme-notifications
     terminal t)
    (is (search
         (format nil "~C[?2031h" #\Escape)
         (get-output-stream-string output)))
    (cadr-tui:terminal-set-color-scheme-notifications
     terminal nil)
    (is (search
         (format nil "~C[?2031l" #\Escape)
         (get-output-stream-string output)))
    (cadr-tui:terminal-set-color-scheme-notifications
     terminal t)
    (is (search
         (format nil "~C[?2031h" #\Escape)
         (get-output-stream-string output)))
    (cadr-tui:terminal-stop terminal)
    (is (search
         (format nil "~C[?2031l" #\Escape)
         (get-output-stream-string output)))))

(defun osc-color-reply (target value)
  (format nil "~C]~A;~A~C"
          #\Escape
          (cond
            ((eq target :foreground) "10")
            ((eq target :background) "11")
            (t (format nil "4;~D" target)))
          value
          (code-char 7)))

(test terminal-color-query-assembles-foreground-and-palette
  ;; pi@71023aec1 parseOscColorResponse / consumeTerminalColorResponse.
  (multiple-value-bind (target rgb matched-p)
      (cadr-tui:parse-osc-color-response
       (osc-color-reply :foreground "#112233"))
    (is (eq :foreground target))
    (is (not (null matched-p)))
    (is (equal '(17 34 51)
               (list (cadr-tui:rgb-color-red rgb)
                     (cadr-tui:rgb-color-green rgb)
                     (cadr-tui:rgb-color-blue rgb)))))
  (multiple-value-bind (target rgb matched-p)
      (cadr-tui:parse-osc-color-response
       (osc-color-reply 1 "rgb:ffff/8000/0000"))
    (is (eql 1 target))
    (is (not (null matched-p)))
    (is (equal '(255 128 0)
               (list (cadr-tui:rgb-color-red rgb)
                     (cadr-tui:rgb-color-green rgb)
                     (cadr-tui:rgb-color-blue rgb)))))
  (multiple-value-bind (target rgb matched-p)
      (cadr-tui:parse-osc-color-response "hello")
    (declare (ignore target rgb))
    (is (not matched-p)))
  (multiple-value-bind (target rgb matched-p)
      (cadr-tui:parse-osc-color-response
       (osc-color-reply 1 "#123"))
    (is (eql 1 target))
    (is (not (null matched-p)))
    (is (null rgb)))
  (let ((query (cadr-tui:make-terminal-color-query))
        (sequence (cadr-tui:terminal-color-query-sequence)))
    (is (search (format nil "~C]10;?" #\Escape) sequence))
    (is (search (format nil "~C]4;0;?" #\Escape) sequence))
    (is (search (format nil "~C]4;15;?" #\Escape) sequence))
    (is (string= (format nil "~C[c" #\Escape)
                 (subseq sequence (- (length sequence) 3))))
    (is (eq :color
            (cadr-tui:terminal-color-query-note
             query (osc-color-reply :foreground "#010203"))))
    (is (eq :duplicate
            (cadr-tui:terminal-color-query-note
             query (osc-color-reply :foreground "#ffffff"))))
    (is (cadr-tui:terminal-color-query-open-p query))
    (cadr-tui:terminal-color-query-note
     query (osc-color-reply :background "#040506"))
    (loop for index below 16
          do (cadr-tui:terminal-color-query-note
              query
              (osc-color-reply
               index
               (format nil "#~2,'0x~2,'0x~2,'0x"
                       index 0 0))))
    (is (not (cadr-tui:terminal-color-query-open-p query)))
    (let ((colors (cadr-tui:terminal-color-query-plist query)))
      (is (equal '(1 2 3) (getf colors :foreground)))
      (is (equal '(4 5 6) (getf colors :background)))
      (is (= 16 (length (getf colors :palette))))
      (is (equal '(1 0 0) (nth 1 (getf colors :palette))))))
  (let ((query (cadr-tui:make-terminal-color-query)))
    (cadr-tui:terminal-color-query-note
     query (osc-color-reply :foreground "#010203"))
    (loop for index below 16
          unless (= index 3)
            do (cadr-tui:terminal-color-query-note
                query (osc-color-reply index "#000000")))
    (is (eq :complete
            (cadr-tui:terminal-color-query-note
             query (format nil "~C[?64;1;2c" #\Escape))))
    (is (null (getf (cadr-tui:terminal-color-query-plist query)
                    :palette)))
    (is (null
         (cadr-tui:terminal-color-query-note
          query (osc-color-reply :foreground "#ffffff")))))
  (let* ((filter (cadr-tui:make-terminal-response-filter))
         (query (cadr-tui:make-terminal-color-query))
         (reply (osc-color-reply :foreground "#abcdef")))
    (setf (cadr-tui:terminal-response-filter-color-query filter)
          query)
    (multiple-value-bind (consumed value)
        (cadr-tui:terminal-response-consume filter reply)
      (is (not (null consumed)))
      (is (eq :color value)))
    (multiple-value-bind (consumed value)
        (cadr-tui:terminal-response-consume
         filter (format nil "~C[?c" #\Escape))
      (is (not (null consumed)))
      (is (eq :complete value))
      (is (equal '(171 205 239)
                 (getf
                  (cadr-tui:terminal-response-filter-color-result
                   filter)
                  :foreground)))
      (is (null (cadr-tui:terminal-response-filter-color-query
                 filter))))
    (multiple-value-bind (consumed value)
        (cadr-tui:terminal-response-consume filter reply)
      (is (not consumed))
      (is (string= reply value)))))

(test process-terminal-theme-color-query-keeps-typed-input
  (let* ((bell (string (code-char 7)))
         (escape (string #\Escape))
         (reply
           (with-output-to-string (out)
             (format out "~C]10;#010203~A" #\Escape bell)
             (format out "~C]11;#040506~A" #\Escape bell)
             (format out "~C[?c" #\Escape)
             (write-string "typed" out)))
         (output (make-string-output-stream))
         (terminal
           (cadr-tui:make-process-terminal
            :input (make-string-input-stream reply)
            :output output)))
    (setf (cadr-tui::process-terminal-started-p terminal) t)
    (let ((colors
            (cadr-tui:terminal-query-theme-colors
             terminal :timeout-seconds 0.2d0)))
      (is (equal '(1 2 3) (getf colors :foreground)))
      (is (equal '(4 5 6) (getf colors :background)))
      (is (null (getf colors :palette))))
    (let ((written (get-output-stream-string output)))
      (is (search (concatenate 'string escape "]10;?") written))
      (is (search (concatenate 'string escape "]4;15;?") written)))
    (is (string=
         "typed"
         (with-output-to-string (stream)
           (loop repeat 8
                 do (write-string
                     (cadr-tui:terminal-read-input terminal)
                     stream)))))
    (setf (cadr-tui::process-terminal-started-p terminal) nil)))

(test process-terminal-progress-repeats-and-clears
  (let* ((now 10.0d0)
         (output (make-string-output-stream))
         (terminal
           (cadr-tui:make-process-terminal
            :input (make-string-input-stream "")
            :output output
            :progress-clock-function
            (lambda () now)))
         (active
           (format nil "~C]9;4;3~C"
                   #\Escape (code-char 7)))
         (clear
           (format nil "~C]9;4;0~C"
                   #\Escape (code-char 7))))
    (cadr-tui:terminal-set-progress terminal t)
    (is (string= active
                 (get-output-stream-string output)))
    (setf now 10.999d0)
    (is (not
         (cadr-tui:terminal-poll-progress terminal)))
    (is (string= ""
                 (get-output-stream-string output)))
    (setf now 11.0d0)
    (is (cadr-tui:terminal-poll-progress terminal))
    (is (string= active
                 (get-output-stream-string output)))
    (setf now 12.0d0)
    (is (cadr-tui:terminal-poll-progress terminal))
    (is (string= active
                 (get-output-stream-string output)))
    (cadr-tui:terminal-set-progress terminal nil)
    (is (string= clear
                 (get-output-stream-string output)))
    (is (not
         (cadr-tui:terminal-poll-progress terminal)))))
