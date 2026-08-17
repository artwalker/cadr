(load (merge-pathnames "support.lisp" *load-truename*))

(defun truncated-rg-temp-file ()
  (let ((directory
          (merge-pathnames
           (format nil "cadr-rg-~36R/" (random most-positive-fixnum))
           (uiop:temporary-directory))))
    (ensure-directories-exist (merge-pathnames "anchor" directory))
    (merge-pathnames "output.txt" directory)))

(cadr-agent:define-rich-tool
 "rg"
 :label "ripgrep"
 :description
 (format nil
         "Search file contents using ripgrep. Output is truncated to ~D lines or ~A. If truncated, full output is saved to a temp file."
         cadr-agent:+default-max-lines+
         (cadr-agent:format-size cadr-agent:+default-max-bytes+))
 :parameters
 (cadr-ai::json-object
  "type" "object"
  "properties"
  (cadr-ai::json-object
   "pattern" (cadr-ai::json-object "type" "string")
   "path" (cadr-ai::json-object "type" "string")
   "glob" (cadr-ai::json-object "type" "string"))
  "required" #("pattern") "additionalProperties" nil)
 :handler
 (lambda (call-id arguments signal on-update context)
   (declare (ignore call-id))
   (block rg-handler
     (when (cadr-agent:extension-cancellation-aborted-p signal)
       (return-from rg-handler (example-result "Search cancelled")))
     (funcall on-update "Searching...")
     (let* ((pattern (example-argument arguments "pattern" ""))
          (path (example-argument arguments "path" "."))
          (glob (example-argument arguments "glob" nil))
          (argv
            (append '("--line-number" "--color=never")
                    (and glob (list "--glob" glob))
                    (list pattern path)))
          (result
            (example-exec
             "rg" argv
             :cwd (namestring (cadr-agent:extension-context-cwd context))
             :timeout-ms 120000))
          (status (example-exec-code result))
          (output (example-exec-output result)))
     (cond
       ((= status 1)
        (example-result
         "No matches found"
         :details (list :pattern pattern :path path :glob glob
                        :match-count 0)))
       ((not (zerop status))
        (error "ripgrep failed (~D): ~A" status (example-exec-error result)))
       ((zerop (length (example-trim output)))
        (example-result
         "No matches found"
         :details (list :pattern pattern :path path :glob glob
                        :match-count 0)))
       (t
        (let* ((match-count
                 (count-if #'plusp
                           (mapcar #'length
                                   (uiop:split-string
                                    output :separator '(#\Newline)))))
               (truncation (cadr-agent:truncate-head output))
               (text (cadr-agent:truncation-result-content truncation))
               (full-output-path nil))
          (when (cadr-agent:truncation-result-truncated-p truncation)
            (setf full-output-path (truncated-rg-temp-file))
            (cadr-agent:with-file-mutation-queue (full-output-path)
               (with-open-file
                   (stream full-output-path :direction :output
                                            :if-exists :supersede
                                            :if-does-not-exist :create
                                            :external-format :utf-8)
                 (write-string output stream)))
            (setf
             text
             (format nil
                     "~A~%~%[Output truncated: showing ~D of ~D lines (~A of ~A). Full output saved to: ~A]"
                     text
                     (cadr-agent:truncation-result-output-lines truncation)
                     (cadr-agent:truncation-result-total-lines truncation)
                     (cadr-agent:format-size
                      (cadr-agent:truncation-result-output-bytes truncation))
                     (cadr-agent:format-size
                      (cadr-agent:truncation-result-total-bytes truncation))
                     (namestring full-output-path))))
          (example-result
           text
           :details
           (list :pattern pattern :path path :glob glob
                 :match-count match-count :truncation truncation
                 :full-output-path
                 (and full-output-path (namestring full-output-path))))))))))
 :render-call
 (lambda (arguments render-context theme)
   (declare (ignore render-context theme))
   (format nil "rg ~S~@[ in ~A~]~@[ --glob ~A~]"
           (example-argument arguments "pattern" "")
           (example-argument arguments "path" nil)
           (example-argument arguments "glob" nil)))
 :render-result
 (lambda (result options render-context theme)
   (declare (ignore options render-context theme))
   (let* ((details (cadr-ai:tool-result-message-details result))
          (count (getf details :match-count 0)))
     (if (zerop count)
         "No matches found"
         (format nil "~D matches~:[~; (truncated)~]"
                 count
                 (and (getf details :truncation)
                      (cadr-agent:truncation-result-truncated-p
                       (getf details :truncation))))))))
