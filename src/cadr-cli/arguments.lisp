(in-package #:cadr-cli)

(defstruct cli-arguments
  provider
  model
  base-url
  system-prompt
  mode
  (print-p nil :type boolean)
  (messages nil :type list)
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
    ("--mode" . :mode)
    ("--resume" . :resume)
    ("--extension" . :extension)))

(defparameter +cli-flag-options+
  '(("--continue" . :continue)
    ("--print" . :print)
    ("-p" . :print)
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
    (error 'cadr-ai:configuration-error
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
    (:mode
     (let ((mode
             (find
              value
              '(:text :json :rpc)
              :key #'symbol-name
              :test #'string-equal)))
       (unless mode
         (error
          'cadr-ai:configuration-error
          :message
          "--mode must be text, json, or rpc"))
       (setf
        (cli-arguments-mode arguments)
        mode)))
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
    (:print
     (setf
      (cli-arguments-print-p arguments)
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
                               'cadr-ai:configuration-error
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
                      'cadr-ai:configuration-error
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
                    'cadr-ai:configuration-error
                    :message
                    (format nil
                            "Flag ~A takes no value"
                            name)))
                 (set-cli-flag
                  arguments (cdr flag-option)))
                ((cli-string-prefix-p "-" argument)
                 (error
                  'cadr-ai:configuration-error
                  :message
                  (format nil
                          "Unknown option: ~A"
                          argument)))
                (t
                 (setf
                  (cli-arguments-messages arguments)
                  (nconc
                   (cli-arguments-messages arguments)
                   (list argument))))))))
    (setf
     (cli-arguments-extensions arguments)
     (nreverse
      (cli-arguments-extensions arguments)))
    arguments))

(defun print-cli-usage
    (&optional (stream *standard-output*))
  (format stream
          "NAME:~%  cadr - Common Lisp coding agent~%~%")
  (format stream
          "USAGE:~%  cadr [options] [messages...]~%~%")
  (format stream "OPTIONS:~%")
  (dolist
      (line
       '("      --base-url <VALUE>       Override provider base URL"
         "      --continue               Continue the latest session"
         "      --extension <VALUE>      Load a Lisp extension (repeatable)"
         "      --help                   Display usage and exit"
         "      --model <VALUE>          Provider model ID"
         "      --mode <VALUE>           Output mode: text, json, or rpc"
         "      --no-tui                 Use the line-oriented REPL"
         "  -p, --print                  Process prompts and exit"
         "      --provider <VALUE>       Provider name"
         "      --resume <VALUE>         Resume an exact session ID"
         "      --system-prompt <VALUE>  System prompt text or file"
         "      --version                Display version and exit"))
    (format stream "~A~%" line))
  (finish-output stream))

(defun resolve-cli-mode
    (arguments input-terminal-p output-terminal-p)
  (or
   (cli-arguments-mode arguments)
   (and
    (cli-arguments-print-p arguments)
    :text)
   (and
    (cli-arguments-no-tui-p arguments)
    :repl)
   (and
    (or
     (not input-terminal-p)
     (not output-terminal-p))
    :text)
   :tui))

(defun build-cli-print-prompts
    (arguments stdin-content)
  (let* ((messages
           (copy-list
            (cli-arguments-messages arguments)))
         (first-message (pop messages))
         (initial
           (cond
             ((and stdin-content first-message)
              (format nil "~A~%~A"
                      stdin-content first-message))
             (stdin-content stdin-content)
             (t first-message))))
    (values initial messages)))
