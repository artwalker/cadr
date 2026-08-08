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
            (format
             *error-output*
             "~:(~A~): ~A~%"
             (getf diagnostic :type)
             (getf diagnostic :message)))
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
             (print-cli-usage)
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
             (let* ((session
                      (cadr-agent:load-session
                       (cli-arguments-export
                        arguments)))
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
               0))
            ((and
              (eq
               (cli-arguments-mode arguments)
               :rpc)
              (cli-arguments-file-arguments
               arguments))
             (format
              *error-output*
              "cadr: @file arguments are not supported in RPC mode~%")
             1)
            (t
             (cli-handler arguments)))))
    (cadr-ai:cadr-error (condition)
      (format *error-output* "cadr: ~A~%" condition)
      (finish-output *error-output*)
      1)
    (error (condition)
      (format *error-output* "cadr: ~A~%" condition)
      (finish-output *error-output*)
      1)))
