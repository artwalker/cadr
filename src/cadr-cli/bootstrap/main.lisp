(in-package #:cadr-cli)

(defun print-cli-models
    (pattern &optional
               (output *standard-output*))
  (let ((needle
          (and
           (stringp pattern)
           (string-downcase pattern))))
    (dolist
        (metadata
         (sort
          (copy-list
           (cadr-ai:list-model-metadata))
          #'string<
          :key
          (lambda (item)
            (format nil "~(~A~)/~A"
                    (cadr-ai:model-metadata-provider
                     item)
                    (cadr-ai:model-metadata-id
                     item)))))
      (let ((name
              (format nil "~(~A~)/~A"
                      (cadr-ai:model-metadata-provider
                       metadata)
                      (cadr-ai:model-metadata-id
                       metadata))))
        (when
            (or
             (null needle)
             (search needle
                     (string-downcase name)))
          (format output "~A~%" name)))))
  (finish-output output))

(defun main (&optional
               (argv
                 (uiop:command-line-arguments)))
  (handler-case
      (progn
        (ensure-user-data-migrated :argv argv)
        (ensure-agent-layout-migrated)
        (multiple-value-bind
              (handled-p status)
            (handle-package-command
             argv
             :offline-p
             (or
              (member "--offline" argv
                      :test #'string=)
              (string=
               "1"
               (or
                (uiop:getenv
                 "CADR_OFFLINE")
                ""))))
          (when handled-p
            (return-from main status)))
        (multiple-value-bind
              (handled-p status)
            (run-credential-print-command
             argv)
          (when handled-p
            (return-from main status)))
        (let ((arguments
                (parse-cli-arguments argv)))
          (dolist
              (diagnostic
               (cli-arguments-diagnostics
                arguments))
            ;; Baseline main.ts:563-566 — diagnostics print to stderr,
            ;; red for errors and yellow for warnings.
            (let ((error-p (eq (getf diagnostic :type) :error)))
              (format
               *error-output*
               "~A~%"
               (funcall
                (if error-p #'cli-error-text #'cli-warning-text)
                *error-output*
                (format
                 nil
                 "~A: ~A"
                 (if error-p "Error" "Warning")
                 (getf diagnostic :message))))))
          (when
              (find
               :error
               (cli-arguments-diagnostics
                arguments)
               :key
               (lambda (diagnostic)
                 (getf diagnostic :type)))
            (return-from main 1))
          (cond
            ((cli-arguments-help-p arguments)
             (print-cli-usage
              *standard-output*
              (cli-help-extension-flags arguments))
             0)
            ((cli-arguments-version-p arguments)
             (format t "~A~%"
                     (cadr-ai::cadr-release-identity))
             0)
            ((cli-arguments-list-models arguments)
             (print-cli-models
              (let ((value
                      (cli-arguments-list-models
                       arguments)))
                (and (stringp value)
                     value)))
             0)
            ((cli-arguments-export arguments)
             (let* ((source
                      (merge-pathnames
                       (pathname
                        (cli-arguments-export arguments))
                       (uiop:ensure-directory-pathname
                        (uiop:getcwd)))))
               ;; Baseline main.ts:578-590 + export-html/index.ts:292-294 —
               ;; --export reads a session FILE; a missing file is a hard
               ;; red error, never a raw condition report.
               (unless (probe-file source)
                 (format
                  *error-output*
                  "~A~%"
                  (cli-error-text
                   *error-output*
                   (format
                    nil
                    "Error: File not found: ~A"
                    (namestring source))))
                 (finish-output *error-output*)
                 (return-from main 1))
               (let* ((session
                      (cadr-agent:load-session
                       source))
                    (target
                      (pathname
                       (or
                        (first
                         (cli-arguments-messages
                          arguments))
                        (format
                         nil "~A.html"
                         (cadr-agent:session-id
                          session))))))
               (cadr-agent:export-session-html
                session target)
               (format t "Exported to: ~A~%"
                       (namestring target))
               0)))
            ((and
              (eq
               (cli-arguments-mode arguments)
               :rpc)
              (cli-arguments-file-arguments
               arguments))
             (format
              *error-output*
              "~A~%"
              (cli-error-text
               *error-output*
               "Error: @file arguments are not supported in RPC mode"))
             1)
            (t
             (cli-handler arguments)))))
    (cli-session-abort (condition)
      ;; Clean early exit (baseline process.exit(0) paths such as the
      ;; declined cross-project session fork).
      (cli-session-abort-status condition))
    (cadr-ai:cadr-error (condition)
      ;; Baseline prints expected CLI failures as chalk.red(message) with
      ;; no product prefix; messages carry their own "Error: " prefix when
      ;; the baseline site has one (main.ts).
      (format *error-output* "~A~%"
              (cli-error-text *error-output* (princ-to-string condition)))
      (finish-output *error-output*)
      1)
    (error (condition)
      (format *error-output* "cadr: ~A~%" condition)
      (finish-output *error-output*)
      1)))
