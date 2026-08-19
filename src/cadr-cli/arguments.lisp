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
  ;; Baseline v0.84.2 --use-theme: initial interactive theme for this
  ;; run (applied as a startup settings override).
  use-theme
  (no-themes-p nil :type boolean)
  (no-context-files-p nil :type boolean)
  list-models
  (offline-p nil :type boolean)
  ;; pi@914cf1472 cli/args.ts:180-186: --tui-mode replaces --alt;
  ;; NIL means the settings manager's tuiMode decides.
  tui-mode
  (verbose-p nil :type boolean)
  project-trust-override
  (project-trust-override-supplied-p nil :type boolean)
  (unknown-flags (make-hash-table :test #'equal)
                 :type hash-table)
  (diagnostics nil :type list)
  (no-tui-p nil :type boolean)
  (help-p nil :type boolean)
  (version-p nil :type boolean))

(cadr-core:define-redacted-print-object (cli-arguments value stream)
  (format stream ":mode ~A :provider ~A :model ~A :credentials [REDACTED]"
          (cli-arguments-mode value)
          (cli-arguments-provider value)
          (cli-arguments-model value)))

(defun cli-token-tail= (name start expected)
  (declare (type string name expected)
           (type fixnum start))
  (let ((need (length expected))
        (have (- (length name) start)))
    (declare (type fixnum need have))
    (when (= have need)
      (loop for index of-type fixnum from 0 below need
            always (char= (char name (the fixnum (+ start index)))
                          (char expected index))))))

(defun lookup-cli-option (name)
  ;; Closed table: length, then the first distinguishing octet.
  ;; Returns (values kind key). kind is :value, :flag, or :special.
  ;; No alist walk. No per-flag assoc string=.
  (declare (type string name))
  (let ((n (length name)))
    (declare (type fixnum n))
    (cond
      ((< n 2)
       (values nil nil))
      ((and (= n 2)
            (char= (char name 0) #\-)
            (char/= (char name 1) #\-))
       (case (char name 1)
         (#\n (values :value :name))
         (#\t (values :value :tools))
         (#\e (values :value :extension))
         (#\c (values :flag :continue))
         (#\p (values :flag :print))
         (#\a (values :flag :approve))
         (#\h (values :flag :help))
         (#\v (values :flag :version))
         (#\r (values :special :resume))
         (t (values nil nil))))
      ((and (= n 3)
            (char= (char name 0) #\-)
            (char/= (char name 1) #\-))
       (let ((a (char name 1))
             (b (char name 2)))
         (cond
           ((and (char= a #\x) (char= b #\t))
            (values :value :exclude-tools))
           ((and (char= a #\n) (char= b #\t))
            (values :flag :no-tools))
           ((and (char= a #\n) (char= b #\e))
            (values :flag :no-extensions))
           ((and (char= a #\n) (char= b #\s))
            (values :flag :no-skills))
           ((and (char= a #\n) (char= b #\p))
            (values :flag :no-prompt-templates))
           ((and (char= a #\n) (char= b #\c))
            (values :flag :no-context-files))
           ((and (char= a #\n) (char= b #\a))
            (values :flag :no-approve))
           (t (values nil nil)))))
      ((and (= n 4)
            (char= (char name 0) #\-)
            (cli-token-tail= name 1 "nbt"))
       (values :flag :no-builtin-tools))
      ((and (>= n 6)
            (char= (char name 0) #\-)
            (char= (char name 1) #\-))
       (case n
         (6
          (case (char name 2)
            (#\m (cond
                   ((cli-token-tail= name 3 "ode")
                    (values :value :mode))
                   (t (values nil nil))))
            (#\n (if (cli-token-tail= name 3 "ame")
                     (values :value :name)
                     (values nil nil)))
            (#\f (if (cli-token-tail= name 3 "ork")
                     (values :value :fork)
                     (values nil nil)))
            (#\h (if (cli-token-tail= name 3 "elp")
                     (values :flag :help)
                     (values nil nil)))
            (#\y (if (cli-token-tail= name 3 "olo")
                     (values :special :yolo)
                     (values nil nil)))
            (t (values nil nil))))
         (7
          (case (char name 2)
            (#\m (if (cli-token-tail= name 3 "odel")
                     (values :value :model)
                     (values nil nil)))
            (#\s (cond
                   ((cli-token-tail= name 3 "lynk")
                    (values :value :slynk))
                   ((cli-token-tail= name 3 "kill")
                    (values :value :skill))
                   (t (values nil nil))))
            (#\t (cond
                   ((cli-token-tail= name 3 "ools")
                    (values :value :tools))
                   ((cli-token-tail= name 3 "heme")
                    (values :value :theme))
                   (t (values nil nil))))
            (#\p (if (cli-token-tail= name 3 "rint")
                     (values :flag :print)
                     (values nil nil)))
            (t (values nil nil))))
         (8
          (case (char name 2)
            (#\m (if (cli-token-tail= name 3 "odels")
                     (values :value :models)
                     (values nil nil)))
            (#\e (if (cli-token-tail= name 3 "xport")
                     (values :value :export)
                     (values nil nil)))
            (#\r (if (cli-token-tail= name 3 "esume")
                     (values :special :resume)
                     (values nil nil)))
            (#\n (if (cli-token-tail= name 3 "o-tui")
                     (values :flag :no-tui)
                     (values nil nil)))
            (t (values nil nil))))
         (9
          (case (char name 2)
            (#\a (cond
                   ((cli-token-tail= name 3 "pi-key")
                    (values :value :api-key))
                   ((cli-token-tail= name 3 "pprove")
                    (values :flag :approve))
                   (t (values nil nil))))
            (#\s (if (cli-token-tail= name 3 "ession")
                     (values :value :session)
                     (values nil nil)))
            (#\o (if (cli-token-tail= name 3 "ffline")
                     (values :flag :offline)
                     (values nil nil)))
            (#\v (cond
                   ((cli-token-tail= name 3 "erbose")
                    (values :flag :verbose))
                   ((cli-token-tail= name 3 "ersion")
                    (values :flag :version))
                   (t (values nil nil))))
            (t (values nil nil))))
         (10
          (case (char name 2)
            (#\p (if (cli-token-tail= name 3 "rovider")
                     (values :value :provider)
                     (values nil nil)))
            (#\b (if (cli-token-tail= name 3 "ase-url")
                     (values :value :base-url)
                     (values nil nil)))
            (#\t (cond
                   ((cli-token-tail= name 3 "hinking")
                    (values :value :thinking))
                   ((cli-token-tail= name 3 "ui-mode")
                    (values :special :tui-mode))
                   (t (values nil nil))))
            (#\c (if (cli-token-tail= name 3 "ontinue")
                     (values :flag :continue)
                     (values nil nil)))
            (#\n (if (cli-token-tail= name 3 "o-tools")
                     (values :flag :no-tools)
                     (values nil nil)))
            (t (values nil nil))))
         (11
          (case (char name 2)
            (#\e (if (cli-token-tail= name 3 "xtension")
                     (values :value :extension)
                     (values nil nil)))
            (#\n (cond
                   ((cli-token-tail= name 3 "o-skills")
                    (values :flag :no-skills))
                   ((cli-token-tail= name 3 "o-themes")
                    (values :flag :no-themes))
                   (t (values nil nil))))
            (#\u (if (cli-token-tail= name 3 "se-theme")
                     (values :special :use-theme)
                     (values nil nil)))
            (t (values nil nil))))
         (12
          (case (char name 2)
            (#\s (if (cli-token-tail= name 3 "ession-id")
                     (values :value :session-id)
                     (values nil nil)))
            (#\n (cond
                   ((cli-token-tail= name 3 "o-session")
                    (values :flag :no-session))
                   ((cli-token-tail= name 3 "o-approve")
                    (values :flag :no-approve))
                   (t (values nil nil))))
            (t (values nil nil))))
         (13
          (case (char name 2)
            (#\s (if (cli-token-tail= name 3 "ession-dir")
                     (values :value :session-directory)
                     (values nil nil)))
            (#\l (if (cli-token-tail= name 3 "ist-models")
                     (values :special :list-models)
                     (values nil nil)))
            (t (values nil nil))))
         (15
          (case (char name 2)
            (#\s (if (cli-token-tail= name 3 "ystem-prompt")
                     (values :value :system-prompt)
                     (values nil nil)))
            (#\e (if (cli-token-tail= name 3 "xclude-tools")
                     (values :value :exclude-tools)
                     (values nil nil)))
            (#\n (if (cli-token-tail= name 3 "o-extensions")
                     (values :flag :no-extensions)
                     (values nil nil)))
            (t (values nil nil))))
         (17
          (if (cli-token-tail= name 2 "prompt-template")
              (values :value :prompt-template)
              (values nil nil)))
         (18
          (cond
            ((cli-token-tail= name 2 "no-builtin-tools")
             (values :flag :no-builtin-tools))
            ((cli-token-tail= name 2 "no-context-files")
             (values :flag :no-context-files))
            (t (values nil nil))))
         (21
          (if (cli-token-tail= name 2 "no-prompt-templates")
              (values :flag :no-prompt-templates)
              (values nil nil)))
         (22
          (if (cli-token-tail= name 2 "append-system-prompt")
              (values :value :append-system-prompt)
              (values nil nil)))
         (t (values nil nil))))
      (t (values nil nil)))))

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
  ;; Closed case. :approve/:no-approve stay special because they write
  ;; two fields (baseline --approve / --no-approve).
  (case key
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
     (setf (cli-arguments-no-prompt-templates-p arguments) t))
    (:no-themes
     (setf (cli-arguments-no-themes-p arguments) t))
    (:no-context-files
     (setf (cli-arguments-no-context-files-p arguments) t))
    (:offline
     (setf (cli-arguments-offline-p arguments) t))
    (:verbose
     (setf (cli-arguments-verbose-p arguments) t))
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
               (let ((name (or equals-name argument)))
                 (multiple-value-bind (kind key)
                     (lookup-cli-option name)
                   (cond
                     ((eq kind :value)
                      (multiple-value-bind (value rest)
                          (require-cli-value
                           argv equals-name equals-value)
                        (setf argv rest)
                        (if value
                            (set-cli-value arguments key value)
                            (error
                             'cadr-ai:configuration-error
                             :message
                             (format nil "~A requires a value"
                                     name)))))
                     ((eq kind :flag)
                      (if equals-name
                          (add-cli-diagnostic
                           arguments :error
                           (format nil
                                   "Flag ~A takes no value"
                                   name))
                          (progn
                            (set-cli-flag arguments key)
                            (when
                                (and (eq key :print)
                                     argv
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
                                (list (pop argv))))))))
                     ((and (null equals-name)
                           (eq kind :special)
                           (eq key :resume))
                      ;; Baseline cli/args.ts:86-87 — a bare flag; a
                      ;; following token is a message, never a session id.
                      (setf
                       (cli-arguments-resume-p arguments)
                       t))
                     ((and (null equals-name)
                           (eq kind :special)
                           (eq key :list-models))
                      (if (and argv
                               (not (cli-option-token-p (first argv)))
                               (not (cli-string-prefix-p
                                     "@" (first argv))))
                          (setf
                           (cli-arguments-list-models arguments)
                           (pop argv))
                          (setf
                           (cli-arguments-list-models arguments)
                           t)))
                     ((and (null equals-name)
                           (eq kind :special)
                           (eq key :tui-mode))
                      ;; pi@914cf1472 cli/args.ts:180-191 — space form
                      ;; only; a missing or dash-prefixed value is not
                      ;; consumed.
                      (let ((mode (first argv)))
                        (cond
                          ((or (and (stringp mode)
                                    (= (length mode) 7)
                                    (cli-token-tail= mode 0 "regular"))
                               (and (stringp mode)
                                    (= (length mode) 10)
                                    (cli-token-tail= mode 0 "fullscreen")))
                           (setf
                            (cli-arguments-tui-mode arguments)
                            (intern (string-upcase mode) :keyword))
                           (pop argv))
                          ((or (null mode)
                               (cli-string-prefix-p "-" mode))
                           (add-cli-diagnostic
                            arguments :error
                            "--tui-mode requires regular or fullscreen"))
                          (t
                           (pop argv)
                           (add-cli-diagnostic
                            arguments :error
                            (format
                             nil
                             "Invalid TUI mode ~S. Valid values: regular, fullscreen"
                             mode))))))
                     ((and (null equals-name)
                           (eq kind :special)
                           (eq key :use-theme))
                      ;; Baseline v0.84.2 cli/args.ts: space form only;
                      ;; a missing or dash-prefixed value is not consumed.
                      (let ((theme-name (first argv)))
                        (if (or (null theme-name)
                                (cli-string-prefix-p "-" theme-name))
                            (add-cli-diagnostic
                             arguments :error
                             "--use-theme requires a theme name")
                            (progn
                              (setf
                               (cli-arguments-use-theme arguments)
                               theme-name)
                              (pop argv)))))
                     ((and (null equals-name)
                           (eq kind :special)
                           (eq key :yolo))
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
                        (list argument)))))))))))
    arguments))

(defun cli-stream-color-p (stream)
  ;; The pre-TUI CLI contract follows chalk: SGR only when the stream is a
  ;; terminal and NO_COLOR is unset or empty.
  (and (interactive-stream-p stream)
       (let ((no-color (uiop:getenv "NO_COLOR")))
         (or (null no-color) (zerop (length no-color))))))

(defun cli-bold-text (stream text)
  (if (cli-stream-color-p stream)
      (format nil "~C[1m~A~C[22m" #\Escape text #\Escape)
      text))

(defun cli-error-text (stream text)
  ;; Baseline console.error(chalk.red(text)).
  (if (cli-stream-color-p stream)
      (format nil "~C[31m~A~C[39m" #\Escape text #\Escape)
      text))

(defun cli-warning-text (stream text)
  ;; Baseline chalk.yellow(text).
  (if (cli-stream-color-p stream)
      (format nil "~C[33m~A~C[39m" #\Escape text #\Escape)
      text))

(defun cli-dim-text (stream text)
  ;; Baseline chalk.dim(text).
  (if (cli-stream-color-p stream)
      (format nil "~C[2m~A~C[22m" #\Escape text #\Escape)
      text))

(defun cli-success-text (stream text)
  ;; Baseline chalk.green(text).
  (if (cli-stream-color-p stream)
      (format nil "~C[32m~A~C[39m" #\Escape text #\Escape)
      text))

(defun cli-pad-right (text width)
  (let ((length (length text)))
    (if (>= length width)
        text
        (concatenate
         'string text
         (make-string (- width length) :initial-element #\Space)))))

(defparameter +cli-usage-prefix+
  "cadr - AI coding assistant with read, bash, edit, write tools

Usage:
  cadr [options] [@files...] [messages...]

Commands:
  cadr install <source> [-l]     Install extension source and add to settings
  cadr remove <source> [-l]      Remove extension source from settings
  cadr uninstall <source> [-l]   Alias for remove
  cadr update [source|self|cadr]   Update cadr, extensions, or model catalogs
  cadr list                      List installed extensions from settings
  cadr config [-l]               Open TUI to enable/disable package resources (Tab switches scope)
  cadr auth <command>            Print credentials or check provider readiness
  cadr <command> --help          Show help for install/remove/uninstall/update/list/config/auth

Options:
  --provider <name>              Provider name (default: google)
  --model <pattern>              Model pattern or ID (supports \"provider/id\" and optional \":<thinking>\")
  --api-key <key>                API key (defaults to env vars)
  --system-prompt <text>         System prompt (default: coding assistant prompt)
  --append-system-prompt <text>  Append text or file contents to the system prompt (can be used multiple times)
  --mode <mode>                  Output mode: text (default), json, or rpc
  --print, -p                    Non-interactive mode: process prompt and exit
  --continue, -c                 Continue previous session
  --resume, -r                   Select a session to resume
  --session <path|id>            Use specific session file or partial UUID
  --session-id <id>              Use exact project session ID, creating it if missing
  --fork <path|id>               Fork specific session file or partial UUID into a new session
  --session-dir <dir>            Directory for session storage and lookup
  --no-session                   Don't save session (ephemeral)
  --name, -n <name>              Set session display name
  --models <patterns>            Comma-separated model patterns for Ctrl+P cycling
                                 Supports globs (anthropic/*, *sonnet*) and fuzzy matching
  --no-tools, -nt                Disable all tools by default (built-in and extension)
  --no-builtin-tools, -nbt       Disable built-in tools by default but keep extension/custom tools enabled
  --tools, -t <tools>            Comma-separated allowlist of tool names to enable
                                 Applies to built-in, extension, and custom tools
  --exclude-tools, -xt <tools>   Comma-separated denylist of tool names to disable
                                 Applies to built-in, extension, and custom tools
  --thinking <level>             Set thinking level: off, minimal, low, medium, high, xhigh, max
  --extension, -e <path>         Load an extension file (can be used multiple times)
  --no-extensions, -ne           Disable extension discovery (explicit -e paths still work)
  --skill <path>                 Load a skill file or directory (can be used multiple times)
  --no-skills, -ns               Disable skills discovery and loading
  --prompt-template <path>       Load a prompt template file or directory (can be used multiple times)
  --no-prompt-templates, -np     Disable prompt template discovery and loading
  --theme <path>                 Load a theme file or directory (can be used multiple times)
  --use-theme <name[/name]>      Set the initial interactive theme for this run
  --no-themes                    Disable theme discovery and loading
  --no-context-files, -nc        Disable AGENTS.md and CLAUDE.md discovery and loading
  --export <file>                Export session file to HTML and exit
  --list-models [search]         List available models (with optional fuzzy search)
  --verbose                      Force verbose startup (overrides quietStartup setting)
  --tui-mode <mode>              TUI mode: regular (default) or fullscreen
  --approve, -a                  Trust project-local files for this run
  --no-approve, -na              Ignore project-local files for this run
  --offline                      Disable startup network operations (same as CADR_OFFLINE=1)
  --help, -h                     Show this help
  --version, -v                  Show version number

Extensions can register additional flags (e.g., --plan from plan-mode extension).")

(defparameter +cli-usage-suffix+
  "
Examples:
  # Print a provider API key for an external client
  cadr auth print-api-key --provider openai

  # Print an OAuth bearer token for an external client (refreshes if expired)
  cadr auth print-bearer-token --provider openai-codex

  # Interactive mode
  cadr

  # Interactive mode with initial prompt
  cadr \"List all .ts files in src/\"

  # Include files in initial message
  cadr @prompt.md @image.png \"What color is the sky?\"

  # Non-interactive mode (process and exit)
  cadr -p \"List all .ts files in src/\"

  # Multiple messages (interactive)
  cadr \"Read package.json\" \"What dependencies do we have?\"

  # Continue previous session
  cadr --continue \"What did we discuss?\"

  # Start a named session
  cadr --name \"Refactor auth module\"

  # Use different model
  cadr --provider openai --model gpt-4o-mini \"Help me refactor this code\"

  # Use model with provider prefix (no --provider needed)
  cadr --model openai/gpt-4o \"Help me refactor this code\"

  # Use model with thinking level shorthand
  cadr --model sonnet:high \"Solve this complex problem\"

  # Limit model cycling to specific models
  cadr --models claude-sonnet,claude-haiku,gpt-4o

  # Limit to a specific provider with glob pattern
  cadr --models \"github-copilot/*\"

  # Cycle models with fixed thinking levels
  cadr --models sonnet:high,haiku:low

  # Start with a specific thinking level
  cadr --thinking high \"Solve this complex problem\"

  # Read-only mode (no file modifications possible)
  cadr --tools read,grep,find,ls -p \"Review the code in src/\"

  # Disable one tool while keeping the rest available
  cadr --exclude-tools ask_question

  # Export a session file to HTML
  cadr --export ~/.cadr/agent/sessions/--path--/session.jsonl
  cadr --export session.jsonl output.html

Environment Variables:
  ANTHROPIC_AUTH_TOKEN             - Anthropic bearer auth token
  ANTHROPIC_API_KEY                - Anthropic Claude API key
  ANTHROPIC_OAUTH_TOKEN            - Anthropic OAuth token (alternative to API key)
  ANT_LING_API_KEY                 - Ant Ling API key
  OPENAI_API_KEY                   - OpenAI GPT API key
  AZURE_OPENAI_API_KEY             - Azure OpenAI API key
  AZURE_OPENAI_BASE_URL            - Azure OpenAI/Cognitive Services base URL (e.g. https://{resource}.openai.azure.com)
  AZURE_OPENAI_RESOURCE_NAME       - Azure OpenAI resource name (alternative to base URL)
  AZURE_OPENAI_API_VERSION         - Azure OpenAI API version (default: v1)
  AZURE_OPENAI_DEPLOYMENT_NAME_MAP - Azure OpenAI model=deployment map (comma-separated)
  DEEPSEEK_API_KEY                 - DeepSeek API key
  NVIDIA_API_KEY                   - NVIDIA NIM API key
  GEMINI_API_KEY                   - Google Gemini API key
  GROQ_API_KEY                     - Groq API key
  CEREBRAS_API_KEY                 - Cerebras API key
  XAI_API_KEY                      - xAI Grok API key
  FIREWORKS_API_KEY                - Fireworks API key
  TOGETHER_API_KEY                 - Together AI API key
  OPENROUTER_API_KEY               - OpenRouter API key
  AI_GATEWAY_API_KEY               - Vercel AI Gateway API key
  ZAI_API_KEY                      - ZAI Coding Plan API key (Global)
  ZAI_CODING_CN_API_KEY            - ZAI Coding Plan API key (China)
  MISTRAL_API_KEY                  - Mistral API key
  MINIMAX_API_KEY                  - MiniMax API key
  MOONSHOT_API_KEY                 - Moonshot AI API key
  OPENCODE_API_KEY                 - OpenCode Zen/OpenCode Go API key
  KIMI_API_KEY                     - Kimi For Coding API key
  CLOUDFLARE_API_KEY               - Cloudflare API token (Workers AI and AI Gateway)
  CLOUDFLARE_ACCOUNT_ID            - Cloudflare account id (required for both)
  CLOUDFLARE_GATEWAY_ID            - Cloudflare AI Gateway slug (required for AI Gateway)
  QWEN_TOKEN_PLAN_API_KEY          - Qwen Token Plan API key (international region)
  QWEN_TOKEN_PLAN_CN_API_KEY       - Qwen Token Plan API key (China region)
  XIAOMI_API_KEY                   - Xiaomi MiMo API key (api.xiaomimimo.com billing)
  XIAOMI_TOKEN_PLAN_CN_API_KEY     - Xiaomi MiMo Token Plan API key (China region)
  XIAOMI_TOKEN_PLAN_AMS_API_KEY    - Xiaomi MiMo Token Plan API key (Amsterdam region)
  XIAOMI_TOKEN_PLAN_SGP_API_KEY    - Xiaomi MiMo Token Plan API key (Singapore region)
  AWS_PROFILE                      - AWS profile for Amazon Bedrock
  AWS_ACCESS_KEY_ID                - AWS access key for Amazon Bedrock
  AWS_SECRET_ACCESS_KEY            - AWS secret key for Amazon Bedrock
  AWS_BEARER_TOKEN_BEDROCK         - Bedrock API key (bearer token)
  AWS_REGION                       - AWS region for Amazon Bedrock (e.g., us-east-1)
  CADR_CODING_AGENT_DIR            - Config directory (default: ~/.cadr/agent)
  CADR_CODING_AGENT_SESSION_DIR    - Session storage directory (overridden by --session-dir)
  CADR_PACKAGE_DIR                 - Override package directory (for Nix/Guix store paths)
  CADR_OFFLINE                     - Disable startup network operations when set to 1/true/yes
  CADR_TELEMETRY                   - Override install telemetry when set to 1/true/yes or 0/false/no
  CADR_SHARE_VIEWER_URL            - Base URL for /share command (default: https://cadr.dev/session/)

Built-in Tool Names:
  read   - Read file contents
  bash   - Execute bash commands
  edit   - Edit files with find/replace
  write  - Write files (creates/overwrites)
  grep   - Search file contents (read-only, off by default)
  find   - Find files by glob pattern (read-only, off by default)
  ls     - List directory contents (read-only, off by default)

")

(defun write-cli-usage-block (stream text)
  ;; Pairing writes the literal. Color TTY wraps known headings.
  (if (not (cli-stream-color-p stream))
      (write-string text stream)
      (let ((start 0)
            (n (length text)))
        (when (and (>= n 4) (cli-token-tail= text 0 "cadr"))
          (write-string (cli-bold-text stream "cadr") stream)
          (setf start 4))
        (loop
          (let ((best-pos nil)
                (best nil))
            (dolist (heading '("Usage:" "Commands:" "Options:"
                               "Examples:" "Environment Variables:"
                               "Built-in Tool Names:"))
              (let* ((hlen (length heading))
                     (pos (search heading text :start2 start)))
                (when (and pos
                           (or (null best-pos) (< pos best-pos))
                           (or (zerop pos)
                               (char= (char text (1- pos)) #\Newline))
                           (let ((end (+ pos hlen)))
                             (or (= end n)
                                 (char= (char text end) #\Newline))))
                  (setf best-pos pos
                        best heading))))
            (unless best
              (write-string text stream :start start)
              (return))
            (when (< start best-pos)
              (write-string text stream :start start :end best-pos))
            (write-string (cli-bold-text stream best) stream)
            (setf start (+ best-pos (length best))))))))

(defun write-cli-extension-flag-line (stream flag)
  (let* ((name (getf flag :name))
         (value
           (if (eq (getf flag :type) :string)
               " <value>"
               ""))
         (path (getf flag :extension-path))
         (description
           (or (getf flag :description)
               (concatenate
                'string
                "Registered by "
                (if path (princ-to-string path) ""))))
         (label
           (concatenate 'string "  --" (if name (princ-to-string name) "") value)))
    (write-string (cli-pad-right label 30) stream)
    (write-string description stream)
    (write-char #\Newline stream)))

(defun print-cli-usage
    (&optional (stream *standard-output*) extension-flags)
  ;; Baseline cli/args.ts printHelp.  Extension flags are plists with
  ;; :name/:type/:description/:extension-path, mirroring ExtensionFlag.
  (write-cli-usage-block stream +cli-usage-prefix+)
  (when extension-flags
    (write-char #\Newline stream)
    (write-string (cli-bold-text stream "Extension CLI Flags:") stream)
    (write-char #\Newline stream)
    (dolist (flag extension-flags)
      (write-cli-extension-flag-line stream flag))
    (write-char #\Newline stream))
  (write-cli-usage-block stream +cli-usage-suffix+)
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
