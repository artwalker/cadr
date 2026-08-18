(load (merge-pathnames "support.lisp" *load-truename*))

(defun github-issue-prefix (lines row column)
  (let* ((line (cadr-tui:editor-line-at lines row))
         (before (subseq line 0 (min column (length line))))
         (hash (position #\# before :from-end t)))
    (and hash
         (or (zerop hash)
             (find (char before (1- hash)) " \t([{" :test #'char=))
         (subseq before hash))))

(defun github-issue-items (cwd prefix signal)
  (when (cadr-tui:autocomplete-request-aborted-p signal)
    (return-from github-issue-items nil))
  (let ((result
          (example-exec
           "gh" '("issue" "list" "--limit" "50" "--json" "number,title")
           :cwd (namestring cwd) :timeout-ms 5000)))
    (when (zerop (example-exec-code result))
      (handler-case
          (loop for issue across
                (cadr-ai::parse-json (example-exec-output result))
                for number = (cadr-ai::json-get issue "number")
                for title = (cadr-ai::json-get issue "title")
                for value = (format nil "#~A" number)
                when (or (string= prefix "#")
                         (search (string-downcase (subseq prefix 1))
                                 (string-downcase
                                  (format nil "~A ~A" value title))))
                  collect
                  (cadr-tui:make-autocomplete-item
                   :value value :label value :description title))
        (error () nil)))))

(cadr-agent:define-event-hook
 :session-start
 :handler
 (lambda (event context)
   (declare (ignore event))
   (let ((cwd (cadr-agent:extension-context-cwd context)))
     (cadr-agent:extension-context-add-autocomplete-provider
      context
      (lambda (current)
        (cadr-tui:make-autocomplete-provider
         :base-path cwd
         :trigger-characters
         (adjoin #\# (copy-list
                      (cadr-tui:autocomplete-provider-trigger-characters current)))
         :suggestions-function
         (lambda (lines row column options)
           (let ((prefix (github-issue-prefix lines row column)))
             (if prefix
                 (cadr-tui:make-autocomplete-suggestions
                  :items (github-issue-items
                          cwd prefix (getf options :signal))
                  :prefix prefix)
                 (cadr-tui:autocomplete-provider-get-suggestions
                  current lines row column
                  :signal (getf options :signal)
                  :force-p (getf options :force-p)))))
         :apply-completion-function
         (lambda (lines row column item prefix)
           (if (and prefix (plusp (length prefix))
                    (char= (char prefix 0) #\#))
               (let* ((line (cadr-tui:editor-line-at lines row))
                      (start (- column (length prefix)))
                      (updated
                        (concatenate
                         'string (subseq line 0 start)
                         (cadr-tui:autocomplete-item-value item) " "
                         (subseq line column)))
                      (new-lines (copy-seq lines)))
                 (setf (elt new-lines row) updated)
                 (values
                  new-lines
                  row
                  (+ start
                     (length (cadr-tui:autocomplete-item-value item)) 1)))
               (cadr-tui:autocomplete-provider-apply-completion
                current lines row column item prefix)))
         :should-trigger-file-completion-function
         (lambda (lines row column)
           (cadr-tui:autocomplete-provider-should-trigger-file-completion-p
            current lines row column))))))))
