(in-package #:cadr-cli)

(defun write-unsigned-decimal (stream value)
  (cond
    ((< value 10)
     (write-char (code-char (+ 48 value)) stream))
    (t
     (multiple-value-bind (quotient remainder)
         (truncate value 10)
       (write-unsigned-decimal stream quotient)
       (write-char (code-char (+ 48 remainder)) stream)))))

(defun unsigned-decimal-length (value)
  (loop for n = value then (floor n 10)
        for length from 1
        until (< n 10)
        finally (return length)))

(defun list-models-token-scale (count)
  (cond
    ((>= count 1000000) (values 1000000 #\M))
    ((>= count 1000) (values 1000 #\K))
    (t (values 1 nil))))

(defun write-list-models-token-count (stream count)
  ;; Same bytes as format-list-models-token-count, no FORMAT.
  (multiple-value-bind (scale suffix)
      (list-models-token-scale count)
    (cond
      ((null suffix)
       (write-unsigned-decimal stream count))
      ((zerop (mod count scale))
       (write-unsigned-decimal stream (truncate count scale))
       (write-char suffix stream))
      (t
       (let ((tenths (round (* count 10) scale)))
         (multiple-value-bind (whole frac)
             (truncate tenths 10)
           (write-unsigned-decimal stream whole)
           (write-char #\. stream)
           (write-char (code-char (+ 48 frac)) stream)
           (write-char suffix stream)))))))

(defun list-models-token-count-length (count)
  (multiple-value-bind (scale suffix)
      (list-models-token-scale count)
    (cond
      ((null suffix)
       (unsigned-decimal-length count))
      ((zerop (mod count scale))
       (1+ (unsigned-decimal-length (truncate count scale))))
      (t
       (let ((tenths (round (* count 10) scale)))
         (multiple-value-bind (whole)
             (truncate tenths 10)
           (+ 3 (unsigned-decimal-length whole))))))))

(defun format-list-models-token-count (count)
  ;; Baseline cli/list-models.ts:9-22 formatTokenCount.
  (with-output-to-string (stream)
    (write-list-models-token-count stream count)))

(defun write-ascii-downcase (stream string)
  (loop for char across string
        do (write-char (char-downcase char) stream)))

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
                       (symbol-name
                        (cadr-ai:model-provider left)))
                     (right-provider
                       (symbol-name
                        (cadr-ai:model-provider right))))
                 (if (string-equal left-provider right-provider)
                     (string<
                      (cadr-ai:model-id left)
                      (cadr-ai:model-id right))
                     (string-lessp left-provider right-provider))))))
      (let* ((width-provider (length "provider"))
             (width-model (length "model"))
             (width-context (length "context"))
             (width-max-out (length "max-out"))
             (width-thinking (length "thinking"))
             (width-images (length "images"))
             (table nil))
        (dolist (model models)
          (setf width-provider
                (max width-provider
                     (length
                      (symbol-name
                       (cadr-ai:model-provider model))))
                width-model
                (max width-model
                     (length (cadr-ai:model-id model)))
                width-context
                (max width-context
                     (list-models-token-count-length
                      (cadr-ai:model-context-window model)))
                width-max-out
                (max width-max-out
                     (list-models-token-count-length
                      (cadr-ai:model-max-tokens model)))))
        (setf table
              (with-output-to-string (buffer)
                (flet ((pad (used width)
                         (loop repeat (- width used)
                               do (write-char #\Space buffer)))
                       (gap ()
                         (write-string "  " buffer)))
                  (write-string "provider" buffer)
                  (pad 8 width-provider)
                  (gap)
                  (write-string "model" buffer)
                  (pad 5 width-model)
                  (gap)
                  (write-string "context" buffer)
                  (pad 7 width-context)
                  (gap)
                  (write-string "max-out" buffer)
                  (pad 7 width-max-out)
                  (gap)
                  (write-string "thinking" buffer)
                  (pad 8 width-thinking)
                  (gap)
                  (write-string "images" buffer)
                  (pad 6 width-images)
                  (write-char #\Newline buffer)
                  (dolist (model models)
                    (let* ((provider
                             (symbol-name
                              (cadr-ai:model-provider model)))
                           (id (cadr-ai:model-id model))
                           (context
                             (cadr-ai:model-context-window model))
                           (max-out
                             (cadr-ai:model-max-tokens model)))
                      (write-ascii-downcase buffer provider)
                      (pad (length provider) width-provider)
                      (gap)
                      (write-string id buffer)
                      (pad (length id) width-model)
                      (gap)
                      (write-list-models-token-count buffer context)
                      (pad
                       (list-models-token-count-length context)
                       width-context)
                      (gap)
                      (write-list-models-token-count buffer max-out)
                      (pad
                       (list-models-token-count-length max-out)
                       width-max-out)
                      (gap)
                      (let ((thinking
                              (if (cadr-ai:model-reasoning-p model)
                                  "yes"
                                  "no")))
                        (write-string thinking buffer)
                        (pad (length thinking) width-thinking))
                      (gap)
                      (let ((images
                              (if (cadr-ai:model-supports-images-p model)
                                  "yes"
                                  "no")))
                        (write-string images buffer)
                        (pad (length images) width-images))
                      (write-char #\Newline buffer))))))
        (write-string table output)))
   (finish-output output)))

(defun main (&optional
               (argv
                 (uiop:command-line-arguments)))
  ;; pi@d981de122 cli.ts:13-15 — the running agent publishes its
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
