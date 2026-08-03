(in-package #:cadr-cli)

(defparameter +thinking-level-names+
  '("off" "minimal" "low" "medium"
    "high" "xhigh" "max"))

(defstruct cli-arguments
  provider
  model
  api-key
  base-url
  system-prompt
  (append-system-prompts nil :type list)
  thinking
  mode
  name
  slynk-port
  (print-p nil :type boolean)
  (messages nil :type list)
  (file-arguments nil :type list)
  (continue-p nil :type boolean)
  (resume-p nil :type boolean)
  resume
  (no-session-p nil :type boolean)
  session
  session-id
  fork
  session-directory
  (models nil :type list)
  (tools nil :type list)
  (exclude-tools nil :type list)
  (no-tools-p nil :type boolean)
  (no-builtin-tools-p nil :type boolean)
  (extensions nil :type list)
  (no-extensions-p nil :type boolean)
  export
  (skills nil :type list)
  (no-skills-p nil :type boolean)
  (prompt-templates nil :type list)
  (no-prompt-templates-p nil :type boolean)
  (themes nil :type list)
  (no-themes-p nil :type boolean)
  (no-context-files-p nil :type boolean)
  list-models
  (offline-p nil :type boolean)
  (alt-p nil :type boolean)
  (verbose-p nil :type boolean)
  project-trust-override
  (project-trust-override-supplied-p nil :type boolean)
  (unknown-flags (make-hash-table :test #'equal)
                 :type hash-table)
  (diagnostics nil :type list)
  (no-tui-p nil :type boolean)
  (help-p nil :type boolean)
  (version-p nil :type boolean))

(defmethod print-object ((value cli-arguments) stream)
  (print-unreadable-object (value stream :type t)
    (format stream ":mode ~A :provider ~A :model ~A :credentials [REDACTED]"
            (cli-arguments-mode value)
            (cli-arguments-provider value)
            (cli-arguments-model value))))

(defparameter +cli-value-options+
  '(("--provider" . :provider)
    ("--model" . :model)
    ("--api-key" . :api-key)
    ("--base-url" . :base-url)
    ("--system-prompt" . :system-prompt)
    ("--append-system-prompt" . :append-system-prompt)
    ("--thinking" . :thinking)
    ("--mode" . :mode)
    ("--name" . :name)
    ("-n" . :name)
    ("--slynk" . :slynk)
    ("--session" . :session)
    ("--session-id" . :session-id)
    ("--fork" . :fork)
    ("--session-dir" . :session-directory)
    ("--models" . :models)
    ("--tools" . :tools)
    ("-t" . :tools)
    ("--exclude-tools" . :exclude-tools)
    ("-xt" . :exclude-tools)
    ("--extension" . :extension)
    ("-e" . :extension)
    ("--export" . :export)
    ("--skill" . :skill)
    ("--prompt-template" . :prompt-template)
    ("--theme" . :theme)))

(defparameter +cli-flag-options+
  '(("--continue" . :continue)
    ("-c" . :continue)
    ("--no-session" . :no-session)
    ("--no-tools" . :no-tools)
    ("-nt" . :no-tools)
    ("--no-builtin-tools" . :no-builtin-tools)
    ("-nbt" . :no-builtin-tools)
    ("--no-extensions" . :no-extensions)
    ("-ne" . :no-extensions)
    ("--print" . :print)
    ("-p" . :print)
    ("--no-skills" . :no-skills)
    ("-ns" . :no-skills)
    ("--no-prompt-templates" . :no-prompt-templates)
    ("-np" . :no-prompt-templates)
    ("--no-themes" . :no-themes)
    ("--no-context-files" . :no-context-files)
    ("-nc" . :no-context-files)
    ("--offline" . :offline)
    ("--alt" . :alt)
    ("--verbose" . :verbose)
    ("--approve" . :approve)
    ("-a" . :approve)
    ("--no-approve" . :no-approve)
    ("-na" . :no-approve)
    ("--no-tui" . :no-tui)
    ("--help" . :help)
    ("-h" . :help)
    ("--version" . :version)
    ("-v" . :version)))

(defun cli-string-prefix-p (prefix value)
  (and (<= (length prefix) (length value))
       (string= prefix value
                :end2 (length prefix))))

(defun option-with-equals (argument)
  (let ((equals (position #\= argument)))
    (when equals
      (values (subseq argument 0 equals)
              (subseq argument (1+ equals))))))

(defun split-comma-option (value)
  (remove
   ""
   (mapcar
    (lambda (item)
      (string-trim
       '(#\Space #\Tab #\Newline #\Return)
       item))
    (uiop:split-string value :separator '(#\,)))
   :test #'string=))

(defun add-cli-diagnostic (arguments type message)
  (setf
   (cli-arguments-diagnostics arguments)
   (append
    (cli-arguments-diagnostics arguments)
    (list (list :type type :message message)))))

(defun set-cli-value (arguments key value)
  (case key
    (:provider
     (setf (cli-arguments-provider arguments) value))
    (:model
     (setf (cli-arguments-model arguments) value))
    (:api-key
     (setf (cli-arguments-api-key arguments) value))
    (:base-url
     (setf (cli-arguments-base-url arguments) value))
    (:system-prompt
     (setf (cli-arguments-system-prompt arguments) value))
    (:append-system-prompt
     (setf
      (cli-arguments-append-system-prompts arguments)
      (append
       (cli-arguments-append-system-prompts arguments)
       (list value))))
    (:thinking
     (if (valid-thinking-level-p value)
         (setf
          (cli-arguments-thinking arguments)
          (intern (string-upcase value) :keyword))
         (add-cli-diagnostic
          arguments :warning
          (format nil
                  "Invalid thinking level ~S. Valid values: ~{~A~^, ~}"
                  value +thinking-level-names+))))
    (:mode
     (let ((mode
             (find
              value
              '(:text :json :rpc)
              :key #'symbol-name
              :test #'string-equal)))
       (if mode
           (setf (cli-arguments-mode arguments) mode)
           (error
            'cadr-ai:configuration-error
            :message
            "--mode must be text, json, or rpc"))))
    (:name
     (setf (cli-arguments-name arguments) value))
    (:slynk
     (if
         (and
          (plusp (length value))
          (every
           (lambda (character)
             (digit-char-p character 10))
           value))
         (let ((port (parse-integer value :radix 10)))
           (if (<= 1 port 65535)
               (setf
                (cli-arguments-slynk-port arguments)
                port)
               (error
                'cadr-ai:configuration-error
                :message
                "--slynk must be a decimal port in the range 1..65535")))
         (error
          'cadr-ai:configuration-error
          :message
          "--slynk must be a decimal port in the range 1..65535")))
    (:session
     (setf (cli-arguments-session arguments) value))
    (:session-id
     (setf (cli-arguments-session-id arguments) value))
    (:fork
     (setf (cli-arguments-fork arguments) value))
    (:session-directory
     (setf
      (cli-arguments-session-directory arguments)
      value))
    (:models
     (setf
      (cli-arguments-models arguments)
      (split-comma-option value)))
    (:tools
     (setf
      (cli-arguments-tools arguments)
      (split-comma-option value)))
    (:exclude-tools
     (setf
      (cli-arguments-exclude-tools arguments)
      (split-comma-option value)))
    (:extension
     (setf
      (cli-arguments-extensions arguments)
      (append
       (cli-arguments-extensions arguments)
       (list value))))
    (:export
     (setf (cli-arguments-export arguments) value))
    (:skill
     (setf
      (cli-arguments-skills arguments)
      (append
       (cli-arguments-skills arguments)
       (list value))))
    (:prompt-template
     (setf
      (cli-arguments-prompt-templates arguments)
      (append
       (cli-arguments-prompt-templates arguments)
       (list value))))
    (:theme
     (setf
      (cli-arguments-themes arguments)
      (append
       (cli-arguments-themes arguments)
       (list value)))))
  arguments)

(defun set-cli-flag (arguments key)
  (case key
    (:continue
     (setf (cli-arguments-continue-p arguments) t))
    (:no-session
     (setf (cli-arguments-no-session-p arguments) t))
    (:no-tools
     (setf (cli-arguments-no-tools-p arguments) t))
    (:no-builtin-tools
     (setf (cli-arguments-no-builtin-tools-p arguments) t))
    (:no-extensions
     (setf (cli-arguments-no-extensions-p arguments) t))
    (:print
     (setf (cli-arguments-print-p arguments) t))
    (:no-skills
     (setf (cli-arguments-no-skills-p arguments) t))
    (:no-prompt-templates
     (setf
      (cli-arguments-no-prompt-templates-p arguments)
      t))
    (:no-themes
     (setf (cli-arguments-no-themes-p arguments) t))
    (:no-context-files
     (setf
      (cli-arguments-no-context-files-p arguments)
      t))
    (:offline
     (setf (cli-arguments-offline-p arguments) t))
    (:alt
     (setf (cli-arguments-alt-p arguments) t))
    (:verbose
     (setf (cli-arguments-verbose-p arguments) t))
    (:approve
     (setf
      (cli-arguments-project-trust-override arguments) t
      (cli-arguments-project-trust-override-supplied-p
       arguments) t))
    (:no-approve
     (setf
      (cli-arguments-project-trust-override arguments) nil
      (cli-arguments-project-trust-override-supplied-p
       arguments) t))
    (:no-tui
     (setf (cli-arguments-no-tui-p arguments) t))
    (:help
     (setf (cli-arguments-help-p arguments) t))
    (:version
     (setf (cli-arguments-version-p arguments) t)))
  arguments)

(defun cli-option-token-p (value)
  (and value
       (cli-string-prefix-p "-" value)
       (not
        (cli-string-prefix-p "---" value))))

(defun require-cli-value
    (argv equals-name equals-value)
  (let ((value
          (if equals-name
              equals-value
              (and
               argv
               (not
                (cli-option-token-p
                 (first argv)))
               (pop argv)))))
    (if (and value
             (or equals-name
                 (not
                  (cli-option-token-p value))))
        (values value argv)
        (values nil argv))))

(defun parse-cli-arguments (argv)
  (let ((arguments (make-cli-arguments)))
    (loop while argv
          for argument = (pop argv)
          do
          (cond
            ((or (string= argument "--resume")
                 (string= argument "-r"))
             ;; cadr historically accepted an exact id here. Preserve that
             ;; stable surface while also accepting the reference flag form.
             (if (and argv
                      (not (cli-option-token-p (first argv)))
                      (not (cli-string-prefix-p "@" (first argv))))
                 (setf
                  (cli-arguments-resume arguments)
                  (pop argv))
                 (setf
                  (cli-arguments-resume-p arguments)
                  t)))
            ((string= argument "--list-models")
             (if (and argv
                      (not (cli-option-token-p (first argv)))
                      (not (cli-string-prefix-p "@" (first argv))))
                 (setf
                  (cli-arguments-list-models arguments)
                  (pop argv))
                 (setf
                  (cli-arguments-list-models arguments)
                  t)))
            ((or (string= argument "--print")
                 (string= argument "-p"))
             (set-cli-flag arguments :print)
             (when
                 (and argv
                      (not
                       (cli-string-prefix-p
                        "@" (first argv)))
                      (or
                       (not
                        (cli-option-token-p
                         (first argv)))
                       (cli-string-prefix-p
                        "---" (first argv))))
               (setf
                (cli-arguments-messages arguments)
                (append
                 (cli-arguments-messages arguments)
                 (list (pop argv))))))
            ((and (plusp (length argument))
                  (char= (char argument 0) #\@))
             (setf
              (cli-arguments-file-arguments arguments)
              (append
               (cli-arguments-file-arguments arguments)
               (list (subseq argument 1)))))
            (t
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
                    (multiple-value-bind (value rest)
                        (require-cli-value
                         argv equals-name equals-value)
                      (setf argv rest)
                      (if value
                          (set-cli-value
                           arguments
                           (cdr value-option)
                           value)
                          (error
                           'cadr-ai:configuration-error
                           :message
                           (format nil "~A requires a value"
                                   name)))))
                   (flag-option
                    (if equals-name
                        (add-cli-diagnostic
                         arguments :error
                         (format nil
                                 "Flag ~A takes no value"
                                 name))
                        (set-cli-flag
                         arguments
                         (cdr flag-option))))
                   ((string= argument "--yolo")
                    (error
                     'cadr-ai:configuration-error
                     :message "Unknown option: --yolo"))
                   ((cli-string-prefix-p "--" argument)
                    (let ((flag-name
                            (subseq
                             (or equals-name argument)
                             2)))
                      (cond
                        (equals-name
                         (setf
                          (gethash
                           flag-name
                           (cli-arguments-unknown-flags
                            arguments))
                          equals-value))
                        ((and argv
                              (not
                               (cli-option-token-p
                                (first argv)))
                              (not
                               (cli-string-prefix-p
                                "@" (first argv))))
                         (setf
                          (gethash
                           flag-name
                           (cli-arguments-unknown-flags
                            arguments))
                          (pop argv)))
                        (t
                         (setf
                          (gethash
                           flag-name
                           (cli-arguments-unknown-flags
                            arguments))
                          t)))))
                   ((cli-string-prefix-p "-" argument)
                    (add-cli-diagnostic
                     arguments :error
                     (format nil
                             "Unknown option: ~A"
                             argument)))
                   (t
                    (setf
                     (cli-arguments-messages arguments)
                     (append
                      (cli-arguments-messages arguments)
                      (list argument))))))))))
    arguments))

(defun print-cli-usage
    (&optional (stream *standard-output*))
  (format stream
          "NAME:~%  cadr - Common Lisp coding agent~%~%")
  (format stream
          "USAGE:~%  cadr [options] [@files...] [messages...]~%~%")
  (format stream
          "COMMANDS:~%  install  remove  uninstall  update  list  config  auth~%~%")
  (format stream "OPTIONS:~%")
  (dolist
      (line
       '("      --provider <name>             Provider name"
         "      --model <id>                  Model ID"
         "      --api-key <key>               Runtime API key"
         "      --system-prompt <text|file>    Replace system prompt"
         "      --append-system-prompt <value> Append system prompt (repeatable)"
         "      --thinking <level>             off|minimal|low|medium|high|xhigh|max"
         "  -c, --continue                     Continue latest session"
         "  -r, --resume                       Resume via selector (or exact id)"
         "      --mode <mode>                  text|json|rpc"
         "  -n, --name <name>                  Session name"
         "      --slynk <port>                 Enable loopback Slynk REPL"
         "      --no-session                   Disable persistence"
         "      --session <path|id>            Session JSONL path or ID"
         "      --session-id <id>              Explicit session id"
         "      --fork <id|path>               Fork from session ID prefix/path"
         "      --session-dir <path>           Session directory"
         "      --models <list>                Scoped models"
         "  -t, --tools <list>                 Tool allowlist"
         " -xt, --exclude-tools <list>         Tool denylist"
         " -nt, --no-tools                     Disable all tools"
         "-nbt, --no-builtin-tools             Disable built-ins only"
         "  -e, --extension <path>             Extension (repeatable)"
         " -ne, --no-extensions                Disable discovered extensions"
         "  -p, --print                        Process prompts and exit"
         "      --export <path>                Export session"
         "      --skill <path>                 Skill path (repeatable)"
         " -ns, --no-skills                    Disable skills"
         "      --prompt-template <path>        Prompt path (repeatable)"
         " -np, --no-prompt-templates          Disable prompt templates"
         "      --theme <path>                 Theme path (repeatable)"
         "      --no-themes                    Disable themes"
         " -nc, --no-context-files             Disable context files"
         "      --list-models [pattern]         List models"
         "      --offline                      Disable package network access"
         "      --alt                          Use the alternate-screen TUI"
         "      --verbose                      Verbose diagnostics"
         "      --no-tui                       Use the line-oriented frontend"
         "  -a, --approve                      Trust project"
         " -na, --no-approve                   Do not trust project"
         "  -h, --help                         Display usage"
         "  -v, --version                      Display version"))
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
    (arguments stdin-content
     &key file-text file-images)
  (let* ((messages
           (copy-list
            (cli-arguments-messages arguments)))
         (first-message (pop messages))
         (text
           (format
            nil "~{~A~}"
            (remove nil
                    (list stdin-content
                          file-text
                          first-message))))
         (initial
           (cond
             (file-images
              (cadr-ai:make-user-message
               :content
               (append
                (when (plusp (length text))
                  (list
                   (cadr-ai:make-text-content
                    :text text)))
                file-images)))
             ((plusp (length text))
              text)
             (t nil))))
    (values initial messages)))
