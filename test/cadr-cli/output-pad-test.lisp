(in-package #:cadr-cli/tests)

(in-suite cadr-cli-suite)

(defun output-pad-content-lines (lines)
  (loop for line in lines
        for plain =
          (string-right-trim
           '(#\Space)
           (cadr-cli::strip-ansi line))
        when (some
              (lambda (char)
                (or (alphanumericp char)
                    (char= char #\$)
                    (char= char #\()))
              plain)
        collect plain))

(defun output-pad-shifted-p (zero one)
  (and (plusp (length zero))
       (every
        (lambda (line)
          (or (zerop (length line))
              (not (char= (char line 0) #\Space))))
        zero)
       (equal one
              (mapcar
               (lambda (line)
                 (concatenate 'string " " line))
               zero))))

(test output-pad-applies-to-transcript-blocks
  ;; pi@71023aec1 #10557. Bash, tools, an edit error, and a compaction
  ;; summary take the transcript pad. 0 has no leading space. 1 adds one.
  (cadr-tui:set-current-theme :dark)
  (let ((entries
          (list
           (cadr-cli::make-tui-entry
            :type :bash-execution
            :label "pwd"
            :text "/tmp"
            :custom-options '(:exit-code 1 :running-p nil))
           (cadr-cli::make-tui-entry
            :type :tool
            :tool-block
            (cadr-tui:make-tool-block
             :name "custom_tool"
             :summary "ok"
             :output "ok"
             :status :complete))
           (cadr-cli::make-tui-entry
            :type :tool
            :tool-block
            (cadr-tui:make-tool-block
             :name "edit"
             :summary "file.txt"
             :output "Could not find old text"
             :status :error))
           (cadr-cli::make-tui-entry
            :type :compaction-summary
            :text "summary"
            :tokens-before 10
            :expanded-p t))))
    (dolist (entry entries)
      (let ((zero
              (output-pad-content-lines
               (cadr-cli::render-tui-entry entry 60 :output-pad 0)))
            (one
              (output-pad-content-lines
               (cadr-cli::render-tui-entry entry 60 :output-pad 1))))
        (is (output-pad-shifted-p zero one)))))
  (let ((state (cadr-cli::make-tui-state :output-pad 0)))
    (is (= 0 (cadr-cli::tui-state-output-pad state)))
    (is (= 1
           (cadr-cli::tui-state-output-pad
            (cadr-cli::make-tui-state :output-pad 9)))))
  (let* ((entry
           (cadr-cli::make-tui-entry
            :type :bash-execution
            :label "pwd"
            :text "/tmp"))
         (state (cadr-cli::make-tui-state :output-pad 0))
         (direct
           (output-pad-content-lines
            (cadr-cli::render-tui-entry entry 60 :output-pad 0)))
         (through-state
           (output-pad-content-lines
            (cadr-cli::render-tui-entries
             (list entry) 60
             :output-pad
             (cadr-cli::tui-state-output-pad state)))))
    (is (equal direct through-state))))

(test user-message-keeps-one-copy-of-each-line
  (cadr-tui:set-current-theme :dark)
  (let* ((entry
           (cadr-cli::make-tui-entry
            :type :user
            :text (format nil "alpha~%beta")))
         (lines
           (cadr-cli::render-tui-entry entry 40 :output-pad 1))
         (plain
           (mapcar
            (lambda (line)
              (string-right-trim
               '(#\Space)
               (cadr-cli::strip-ansi line)))
            lines)))
    (is (= 1 (count " alpha" plain :test #'string=)))
    (is (= 1 (count " beta" plain :test #'string=)))
    (is (not (find "alphaalpha" plain :test #'search)))
    (is (not (find "betabeta" plain :test #'search)))))
