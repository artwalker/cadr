(load (merge-pathnames "support.lisp" *load-truename*))

(defun merge-example-git (cwd &rest arguments)
  (example-exec "git" arguments :cwd (namestring cwd)))

(defun merge-example-conflict-blocks (cwd)
  (let ((result (merge-example-git cwd "diff" "--name-only" "--diff-filter=U"))
        (blocks nil))
    (when (and (zerop (example-exec-code result))
               (plusp (length (example-trim (example-exec-output result)))))
      (dolist (relative
               (uiop:split-string (example-trim (example-exec-output result))
                                  :separator '(#\Newline)))
        (let ((path (merge-pathnames relative cwd)))
          (when (probe-file path)
            (with-open-file (stream path :direction :input :external-format :utf-8)
              (loop with start = nil with separator = nil
                    for line = (read-line stream nil nil)
                    for number from 1
                    while line
                    do
                    (cond
                      ((uiop:string-prefix-p "<<<<<<<" line)
                       (setf start number separator nil))
                      ((and start (uiop:string-prefix-p "=======" line))
                       (setf separator number))
                      ((and start separator
                            (uiop:string-prefix-p ">>>>>>>" line))
                       (push (list :file relative :start start
                                   :separator separator :end number)
                             blocks)
                       (setf start nil separator nil)))))))))
    (nreverse blocks)))

(defun merge-example-range (start end)
  (cond ((> start end) "empty")
        ((= start end) (princ-to-string start))
        (t (format nil "~D-~D" start end))))

(defun merge-example-format-conflicts (reference blocks)
  (with-output-to-string (output)
    (format output "Merged ~A with conflicts:~%~%" reference)
    (dolist (block blocks)
      (format output "  ~A:~D-~D (ours ~A, theirs ~A)~%"
              (getf block :file) (getf block :start) (getf block :end)
              (merge-example-range (1+ (getf block :start))
                                   (1- (getf block :separator)))
              (merge-example-range (1+ (getf block :separator))
                                   (1- (getf block :end)))))
    (format output "~%Resolve these conflicts.")))

(cadr-agent:define-event-hook
 :agent-end
 :handler
 (lambda (event context)
   (declare (ignore event))
   (let* ((cwd (cadr-agent:extension-context-cwd context))
          (inside (merge-example-git cwd "rev-parse" "--git-dir")))
     (when (zerop (example-exec-code inside))
       (let* ((merge-head (merge-example-git cwd "rev-parse" "MERGE_HEAD"))
              (reference "MERGE_HEAD")
              (continue-p t))
         (unless (zerop (example-exec-code merge-head))
           (let ((status (merge-example-git cwd "status" "--porcelain")))
             (if (plusp (length (example-trim (example-exec-output status))))
                 (setf continue-p nil)
                 (let ((upstream
                         (merge-example-git
                          cwd "rev-parse" "--abbrev-ref"
                          "--symbolic-full-name" "@{u}")))
                   (if (not (zerop (example-exec-code upstream)))
                       (setf continue-p nil)
                       (progn
                         (setf reference
                               (example-trim (example-exec-output upstream)))
                         (let ((remote
                                 (first
                                  (uiop:split-string reference
                                                     :separator '(#\/)))))
                           (cadr-agent:extension-context-notify
                            context
                            (format nil
                                    "git-merge-and-resolve: fetching ~A, merging ~A"
                                    remote reference))
                           (let ((fetch (merge-example-git cwd "fetch" remote)))
                             (if (not (zerop (example-exec-code fetch)))
                                 (progn
                                   (setf continue-p nil)
                                   (cadr-agent:extension-context-notify
                                    context
                                    (format nil
                                            "git-merge-and-resolve: fetch failed: ~A"
                                            (example-trim
                                             (example-exec-error fetch)))
                                    :level :warning))
                                 (let ((merge
                                         (merge-example-git
                                          cwd "merge" "--no-ff" reference)))
                                   (when (zerop (example-exec-code merge))
                                     (setf continue-p nil))))))))))))
         (when continue-p
           (let ((blocks (merge-example-conflict-blocks cwd)))
             (when blocks
               (cadr-agent:extension-api-send-user-message
                *example-api*
                (merge-example-format-conflicts reference blocks)
                :deliver-as :follow-up)))))))))
