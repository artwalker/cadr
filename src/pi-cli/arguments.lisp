(in-package #:pi-cli)

(defstruct cli-arguments
  provider
  model
  base-url
  system-prompt
  (continue-p nil :type boolean)
  resume
  (extensions nil :type list)
  (no-tui-p nil :type boolean)
  (help-p nil :type boolean)
  (version-p nil :type boolean))

(defparameter +cli-value-options+
  '(("--provider" . :provider)
    ("--model" . :model)
    ("--base-url" . :base-url)
    ("--system-prompt" . :system-prompt)
    ("--resume" . :resume)
    ("--extension" . :extension)))

(defparameter +cli-flag-options+
  '(("--continue" . :continue)
    ("--no-tui" . :no-tui)
    ("--help" . :help)
    ("--version" . :version)))

(defun cli-string-prefix-p (prefix value)
  (and (<= (length prefix) (length value))
       (string= prefix value
                :end2 (length prefix))))

(defun option-with-equals (argument)
  (let ((equals (position #\= argument)))
    (when equals
      (values (subseq argument 0 equals)
              (subseq argument (1+ equals))))))

(defun set-cli-value (arguments key value)
  (when (zerop (length value))
    (error 'pi-ai:configuration-error
           :message
           (format nil "Option ~A requires a value"
                   key)))
  (case key
    (:provider
     (setf (cli-arguments-provider arguments)
           value))
    (:model
     (setf (cli-arguments-model arguments)
           value))
    (:base-url
     (setf (cli-arguments-base-url arguments)
           value))
    (:system-prompt
     (setf
      (cli-arguments-system-prompt arguments)
      value))
    (:resume
     (setf (cli-arguments-resume arguments)
           value))
    (:extension
     (push value
           (cli-arguments-extensions
            arguments))))
  arguments)

(defun set-cli-flag (arguments key)
  (case key
    (:continue
     (setf
      (cli-arguments-continue-p arguments)
      t))
    (:no-tui
     (setf
      (cli-arguments-no-tui-p arguments)
      t))
    (:help
     (setf (cli-arguments-help-p arguments) t))
    (:version
     (setf
      (cli-arguments-version-p arguments)
      t)))
  arguments)

(defun parse-cli-arguments (argv)
  (let ((arguments (make-cli-arguments)))
    (loop while argv
          for argument = (pop argv)
          do
          (multiple-value-bind
                (equals-name equals-value)
              (option-with-equals argument)
            (let* ((name (or equals-name argument))
                   (value-option
                     (assoc name
                            +cli-value-options+
                            :test #'string=))
                   (flag-option
                     (assoc name
                            +cli-flag-options+
                            :test #'string=)))
              (cond
                (value-option
                 (let ((value
                         (if equals-name
                             equals-value
                             (or
                              (pop argv)
                              (error
                               'pi-ai:configuration-error
                               :message
                               (format nil
                                       "Option ~A requires a value"
                                       name))))))
                   (when
                       (and
                        (not equals-name)
                        (cli-string-prefix-p
                         "--" value))
                     (error
                      'pi-ai:configuration-error
                      :message
                      (format nil
                              "Option ~A requires a value"
                              name)))
                   (set-cli-value
                    arguments
                    (cdr value-option)
                    value)))
                (flag-option
                 (when equals-name
                   (error
                    'pi-ai:configuration-error
                    :message
                    (format nil
                            "Flag ~A takes no value"
                            name)))
                 (set-cli-flag
                  arguments (cdr flag-option)))
                (t
                 (error
                  'pi-ai:configuration-error
                  :message
                  (format nil
                          "Unknown option or argument: ~A"
                          argument)))))))
    (setf
     (cli-arguments-extensions arguments)
     (nreverse
      (cli-arguments-extensions arguments)))
    arguments))

(defun print-cli-usage
    (&optional (stream *standard-output*))
  (format stream
          "NAME:~%  pi-cl - Common Lisp Pi coding agent~%~%")
  (format stream "USAGE:~%  pi-cl [options]~%~%")
  (format stream "OPTIONS:~%")
  (dolist
      (line
       '("      --base-url <VALUE>       Override provider base URL"
         "      --continue               Continue the latest session"
         "      --extension <VALUE>      Load a Lisp extension (repeatable)"
         "      --help                   Display usage and exit"
         "      --model <VALUE>          Provider model ID"
         "      --no-tui                 Use the line-oriented REPL"
         "      --provider <VALUE>       Provider name"
         "      --resume <VALUE>         Resume an exact session ID"
         "      --system-prompt <VALUE>  System prompt text or file"
         "      --version                Display version and exit"))
    (format stream "~A~%" line))
  (finish-output stream))
