(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defun captured-tool-error (tool arguments)
  (handler-case
      (progn
        (invoke-tool tool arguments)
        nil)
    (error (condition)
      (princ-to-string condition))))

(test goal9-b3-write-result-matches-baseline-utf16-code-unit-count
  (with-test-directory (directory)
    (let* ((content
             (format nil "中~C" (code-char #x1f642)))
           (tool (make-write-tool directory)))
      (multiple-value-bind (result details)
          (invoke-tool
           tool
           (args "path" "unicode.txt"
                 "content" content))
        (declare (ignore details))
        (is
         (string=
          "Successfully wrote 3 bytes to unicode.txt"
          (result-text result)))))))

(test goal9-b3-edit-result-and-errors-match-baseline-copy
  (with-test-directory (directory)
    (let ((path (merge-pathnames "edit.txt" directory))
          (tool (make-edit-tool directory)))
      (is
       (string=
        "Could not edit file: missing.txt. Error code: ENOENT."
        (captured-tool-error
         tool
         (args
          "path" "missing.txt"
          "edits"
          (vector
           (args "oldText" "before" "newText" "after"))))))
      (write-text path "alpha beta gamma")
      (multiple-value-bind (result details)
          (invoke-tool
           tool
           (args
            "path" "edit.txt"
            "edits"
            (vector
             (args "oldText" "alpha" "newText" "ALPHA")
             (args "oldText" "gamma" "newText" "GAMMA"))))
        (declare (ignore details))
        (is
         (string=
          "Successfully replaced 2 block(s) in edit.txt."
          (result-text result))))
      (write-text path "same same")
      (is
       (string=
        "Found 2 occurrences of the text in edit.txt. The text must be unique. Please provide more context to make it unique."
        (captured-tool-error
         tool
         (args
          "path" "edit.txt"
          "edits"
          (vector
           (args "oldText" "same" "newText" "changed"))))))
      (is
       (string=
        "Could not find the exact text in edit.txt. The old text must match exactly including all whitespace and newlines."
        (captured-tool-error
         tool
         (args
          "path" "edit.txt"
          "edits"
          (vector
           (args "oldText" "missing" "newText" "changed"))))))
      (write-text path "unique")
      (is
       (string=
        "No changes made to edit.txt. The replacement produced identical content. This might indicate an issue with special characters or the text not existing as expected."
        (captured-tool-error
         tool
         (args
          "path" "edit.txt"
          "edits"
          (vector
           (args "oldText" "unique" "newText" "unique")))))))))

(test goal9-b3-read-result-notices-match-baseline-line-counts
  (with-test-directory (directory)
    (let ((tool (make-read-tool directory)))
      (write-text
       (merge-pathnames "limited.txt" directory)
       (format nil "one~%two~%three~%four"))
      (multiple-value-bind (result details)
          (invoke-tool
           tool
           (args "path" "limited.txt" "limit" 2))
        (declare (ignore details))
        (is
         (string=
          (format nil
                  "one~%two~%~%[2 more lines in file. Use offset=3 to continue.]")
          (result-text result))))
      (write-text
       (merge-pathnames "many.txt" directory)
       (format nil "~{line-~D~^~%~}"
               (loop for index from 1 to 2001 collect index)))
      (multiple-value-bind (result details)
          (invoke-tool tool (args "path" "many.txt"))
        (declare (ignore details))
        (is
         (search
          (format nil
                  "line-2000~%~%[Showing lines 1-2000 of 2001. Use offset=2001 to continue.]")
          (result-text result))))
      (write-text
       (merge-pathnames "one-long-line.txt" directory)
       (make-string (* 60 1024) :initial-element #\x))
      (multiple-value-bind (result details)
          (invoke-tool tool (args "path" "one-long-line.txt"))
        (declare (ignore details))
        (is
         (string=
          "[Line 1 is 60.0KB, exceeds 50.0KB limit. Use bash: sed -n '1p' one-long-line.txt | head -c 51200]"
          (result-text result))))
      (write-binary
       (merge-pathnames "pixel.bmp" directory)
       (make-test-bmp))
      (multiple-value-bind (result details)
          (invoke-tool tool (args "path" "pixel.bmp"))
        (declare (ignore details))
        (is
         (string=
          (format nil
                  "Read image file [image/png]~%[Image converted from image/bmp to image/png.]")
          (cadr-ai:text-content-text (first result)))))
      (write-binary
       (merge-pathnames "broken.bmp" directory)
       #(66 77))
      (multiple-value-bind (result details)
          (invoke-tool tool (args "path" "broken.bmp"))
        (declare (ignore details))
        (is
         (string=
          (format nil
                  "Read image file [image/bmp]~%[Image omitted: could not be converted to a supported inline image format.]")
          (result-text result))))
      (is
       (string=
        "[Image: original 4000x2000, displayed at 2000x1000. Multiply coordinates by 2.00 to map to original image.]"
        (cadr-cli:format-image-dimension-note
         (cadr-cli::make-image-process-result
          :original-width 4000
          :original-height 2000
          :width 2000
          :height 1000
          :resized-p t)))))))

(test goal9-b3-bash-result-status-and-truncation-copy-match-baseline
  (with-test-directory (directory)
    (let ((tool (make-bash-tool directory)))
      (multiple-value-bind (result details)
          (invoke-tool tool (args "command" "true"))
        (declare (ignore details))
        (is (string= "(no output)" (result-text result))))
      (is
       (string=
        (format nil "(no output)~%~%Command exited with code 7")
        (captured-tool-error
         tool (args "command" "exit 7"))))
      (is
       (string=
        "Command timed out after 1 seconds"
        (captured-tool-error
         tool
         (args "command" "exec /usr/bin/tail -f /dev/null" "timeout" 1))))
      (multiple-value-bind (result details)
          (invoke-tool
           tool
           (args
            "command"
            "head -c 61440 /dev/zero | tr '\\0' x"))
        (let ((path (getf details :full-output-path)))
          (is
           (search
            "[Showing last 50.0KB of line 1 (line is 60.0KB). Full output: "
            (result-text result)))
          (when (and path (probe-file path))
            (delete-file path))))
      (multiple-value-bind (result details)
          (invoke-tool
           tool
           (args
            "command"
            "for i in $(seq 1 2001); do printf 'line-%s\\n' \"$i\"; done"))
        (let ((path (getf details :full-output-path)))
          (is
           (search
            (format nil
                    "line-2001~%~%[Showing lines 2-2001 of 2001. Full output: ")
            (result-text result)))
          (is (and path (probe-file path)))
          (when (and path (probe-file path))
            (delete-file path)))))))

(test goal9-b3-bash-timeout-never-leaks-wrapper-diagnostics
  (with-test-directory (directory)
    (let* ((tool (make-bash-tool directory))
           (message
             (captured-tool-error
              tool
              (args
               "command" "exec /usr/bin/tail -f /dev/null"
               "timeout" 1))))
      (is (search "Command timed out after 1 seconds" message))
      (is (null (search "setsid:" message)))
      (is (null (search "cadr-bash-wrapper" message))))))

(test goal9-b3-search-tool-results-match-baseline-copy-and-counts
  (with-test-directory (directory)
    (write-text
     (merge-pathnames "a.txt" directory)
     (format nil "before~%needle one~%after"))
    (write-text (merge-pathnames "b.txt" directory) "needle two")
    (multiple-value-bind (result details)
        (invoke-tool
         (cadr-cli:make-find-tool directory)
         (args "pattern" "*.txt" "limit" 1))
      (declare (ignore details))
      (is
       (string=
        (format nil
                "a.txt~%~%[1 results limit reached. Use limit=2 for more, or refine pattern]")
        (result-text result))))
    (multiple-value-bind (result details)
        (invoke-tool
         (make-grep-tool directory)
         (args "pattern" "needle"
               "path" "."
               "context" 1
               "limit" 1))
      (declare (ignore details))
      (is
       (string=
        (format nil
                "a.txt-1- before~%a.txt:2: needle one~%a.txt-3- after~%~%[1 matches limit reached. Use limit=2 for more, or refine pattern]")
        (result-text result))))
    (write-text
     (merge-pathnames "long.txt" directory)
     (concatenate 'string "needle "
                  (make-string 600 :initial-element #\x)))
    (multiple-value-bind (result details)
        (invoke-tool
         (make-grep-tool directory)
         (args "pattern" "needle" "path" "long.txt"))
      (declare (ignore details))
      (let ((text (result-text result)))
        (is (search "... [truncated]" text))
        (is
         (search
          "[Some lines truncated to 500 chars. Use read tool to see full lines]"
          text))))
    (let* ((emoji (code-char #x1f642))
           (prefix
             (concatenate
              'string "needle "
              (make-string 246 :initial-element emoji)
              "中")))
      (write-text
       (merge-pathnames "unicode-long.txt" directory)
       (concatenate 'string prefix "X"))
      (multiple-value-bind (result details)
          (invoke-tool
           (make-grep-tool directory)
           (args "pattern" "needle" "path" "unicode-long.txt"))
        (declare (ignore details))
        (is
         (string=
          (format
           nil
           "unicode-long.txt:1: ~A... [truncated]~%~%[Some lines truncated to 500 chars. Use read tool to see full lines]"
           prefix)
          (result-text result)))))
    (multiple-value-bind (result details)
        (invoke-tool
         (cadr-cli:make-ls-tool directory)
         (args "limit" 1))
      (declare (ignore details))
      (is
       (string=
        (format nil
                "a.txt~%~%[1 entries limit reached. Use limit=2 for more]")
        (result-text result))))))
