(in-package #:cadr-cli)

(defun format-list-models-token-count (count)
  ;; Baseline cli/list-models.ts:9-22 formatTokenCount.
  (cond
    ((>= count 1000000)
     (multiple-value-bind (millions remainder)
         (floor count 1000000)
       (if (zerop remainder)
           (format nil "~DM" millions)
           (format nil "~,1FM" (/ count 1000000d0)))))
    ((>= count 1000)
     (multiple-value-bind (thousands remainder)
         (floor count 1000)
       (if (zerop remainder)
           (format nil "~DK" thousands)
           (format nil "~,1FK" (/ count 1000d0)))))
    (t
     (format nil "~D" count))))

(defun no-models-available-message ()
  ;; Baseline core/auth-guidance.ts formatNoModelsAvailableMessage.
  (cadr-ai::no-models-available-message))

(defun print-cli-models
    (pattern &optional
               (output *standard-output*))
  ;; Baseline cli/list-models.ts listModels: warn about a models.json
  ;; load failure, list the auth-available models (built-in catalog plus
  ;; models.json customs), fuzzy-filter on "provider id", and print the
  ;; padded six-column table.
  (let* ((registry
           (cached-cli-model-registry
            :path (cadr-core:agent-models-path)
            ;; A models.json provider outside the built-in catalog is only
            ;; available when the registry can read auth.json, so the
            ;; listing needs the same credential store every other
            ;; make-model-registry caller passes.
            :credentials
            (make-file-auth-storage (default-auth-path))))
         (load-error
           (model-registry-error registry)))
    (when load-error
      (format
       *error-output*
       "~A~%"
       (cli-warning-text
        *error-output*
        (format nil "Warning: errors loading models.json:~%~A"
                load-error)))
      (finish-output *error-output*))
    (let ((models
            (model-registry-available-models registry)))
      (when (null models)
        (format output "~A~%" (no-models-available-message))
        (finish-output output)
        (return-from print-cli-models nil))
      (when (and (stringp pattern)
                 (plusp (length pattern)))
        (setf models
              (cadr-tui:fuzzy-filter
               models pattern
               (lambda (model)
                 (format nil "~(~A~) ~(~A~)"
                         (symbol-name
                          (cadr-ai:model-provider model))
                         (cadr-ai:model-id model))))))
      (when (null models)
        (format output "No models matching \"~A\"~%" pattern)
        (finish-output output)
        (return-from print-cli-models nil))
      (setf models
            (sort
             models
             (lambda (left right)
               (let ((left-provider
                       (string-downcase
                        (symbol-name
                         (cadr-ai:model-provider left))))
                     (right-provider
                       (string-downcase
                        (symbol-name
                         (cadr-ai:model-provider right)))))
                 (if (string= left-provider right-provider)
                     (string<
                      (cadr-ai:model-id left)
                      (cadr-ai:model-id right))
                     (string< left-provider right-provider))))))
      (let* ((rows
               (mapcar
                (lambda (model)
                  (list
                   (string-downcase
                    (symbol-name
                     (cadr-ai:model-provider model)))
                   (cadr-ai:model-id model)
                   (format-list-models-token-count
                    (cadr-ai:model-context-window model))
                   (format-list-models-token-count
                    (cadr-ai:model-max-tokens model))
                   (if (cadr-ai:model-reasoning-p model)
                       "yes"
                       "no")
                   (if (cadr-ai:model-supports-images-p model)
                       "yes"
                       "no")))
                models))
             (headers
               (list "provider" "model" "context"
                     "max-out" "thinking" "images"))
             (widths
               (loop for column from 0 below 6
                     collect
                     (reduce
                      #'max
                      (mapcar
                       (lambda (row)
                         (length (nth column row)))
                       rows)
                      :initial-value
                      (length (nth column headers)))))
             (table
               (with-output-to-string (buffer)
                 (flet ((emit-row (cells)
                          (loop for cell in cells
                                for width in widths
                                for first-p = t then nil
                                do
                                (unless first-p
                                  (write-string "  " buffer))
                                (write-string cell buffer)
                                (loop repeat
                                      (- width (length cell))
                                      do (write-char #\Space buffer)))
                          (write-char #\Newline buffer)))
                   (emit-row headers)
                   (dolist (row rows)
                     (emit-row row))))))
        (write-string table output)))
   (finish-output output)))

(defun main (&optional
               (argv
                 (uiop:command-line-arguments)))
  ;; pi@914cf1472 cli.ts:13-15 — the running agent publishes its
  ;; identity to child processes (bash tool, hooks, extensions); cadr
  ;; publishes its own names per the product-identity contract.
  (sb-posix:setenv "CADR_CODING_AGENT" "true" 1)
  (sb-posix:setenv "AI_AGENT" "cadr" 1)
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
            (run-auth-command
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
            ((cli-arguments-version-p arguments)
             (format t "~A~%"
                      (cadr-ai::cadr-release-identity))
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
             ;; Baseline main.ts:605-607 — flag conflict validation runs
             ;; before the startup content migrations.
            (validate-cli-session-flags
             :continue-p (cli-arguments-continue-p arguments)
             :resume-selector-p (cli-arguments-resume-p arguments)
              :no-session-p (cli-arguments-no-session-p arguments)
              :session-path (cli-arguments-session arguments)
              :session-id (cli-arguments-session-id arguments)
              :fork-source (cli-arguments-fork arguments))
             (run-content-migrations (uiop:getcwd))
             (cond
               ((cli-arguments-help-p arguments)
                (print-cli-usage
                 *standard-output*
                 (cli-help-extension-flags arguments))
                0)
               ((cli-arguments-list-models arguments)
                (print-cli-models
                 (let ((value
                         (cli-arguments-list-models
                          arguments)))
                   (and (stringp value)
                        value)))
                0)
               (t
              ;; Baseline main.ts:857-860 — the startup benchmark only
              ;; supports interactive mode.
              (when
                 (and
                  (truthy-env-flag-p "CADR_STARTUP_BENCHMARK")
                  (not
                   (eq
                    (resolve-cli-mode
                     arguments
                     (cadr-tui:terminal-stream-p
                      *standard-input* :input)
                     (cadr-tui:terminal-stream-p
                      *standard-output* :output))
                    :tui)))
               (format
                *error-output*
                "~A~%"
                (cli-error-text
                 *error-output*
                 "Error: CADR_STARTUP_BENCHMARK only supports interactive mode"))
                 (finish-output *error-output*)
                 (return-from main 1))
               (cli-handler arguments)))))))
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
