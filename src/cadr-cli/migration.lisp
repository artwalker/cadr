(in-package #:cadr-cli)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sb-posix))

(defparameter *migration-interactive-p-function*
  #'cadr-tui:terminal-stream-p)

(defparameter *migration-rename-function* #'rename-file
  "Rename entry point for the content migrations; rebound by tests to
exercise the baseline failure arms (migrations.ts:148).")

(defparameter +managed-binary-names+
  '("fd" "rg" "fd.exe" "rg.exe"))

(defun legacy-product-name ()
  (format nil "~C~C-cl" #\p #\i))

(defun data-directory
    (&optional (home (user-homedir-pathname)))
  (merge-pathnames
   ".cadr/"
   (uiop:ensure-directory-pathname home)))

(defun legacy-data-directory
    (&optional (home (user-homedir-pathname)))
  (merge-pathnames
   (format nil ".~A/" (legacy-product-name))
   (uiop:ensure-directory-pathname home)))

(defun shell-single-quote (value)
  (with-output-to-string (output)
    (write-char #\' output)
    (loop for character across value
          do
          (if (char= character #\')
              (write-string "'\\''" output)
              (write-char character output)))
    (write-char #\' output)))

(defun manual-migration-command (old-directory new-directory)
  (format nil
          "mv -- ~A ~A"
          (shell-single-quote (namestring old-directory))
          (shell-single-quote (namestring new-directory))))

(defun refuse-user-data-migration
    (reason old-directory new-directory)
  (error
   'cadr-ai:configuration-error
   :message
   (format nil
           "Legacy data migration refused (~A). Run manually: ~A"
           reason
           (manual-migration-command
            old-directory new-directory))))

(defun affirmative-response-p (response)
  (member
   (string-downcase
    (string-trim
     '(#\Space #\Tab #\Newline #\Return)
     (or response "")))
   '("y" "yes")
   :test #'string=))

(defun move-user-data-directory
    (old-directory new-directory)
  (let ((moved-p nil))
    (handler-case
        (progn
          (rename-file old-directory new-directory)
          (setf moved-p t)
          (let ((auth-path
                  (merge-pathnames
                   "auth.json" new-directory)))
            (when (probe-file auth-path)
              (sb-posix:chmod auth-path #o600)))
          :migrated)
      (error (cause)
        (when (and moved-p
                   (probe-file new-directory)
                   (not (probe-file old-directory)))
          (ignore-errors
            (rename-file new-directory old-directory)))
        (error
         'cadr-ai:configuration-error
         :message
         (format nil
                 "Cannot migrate legacy data directory: ~A"
                 cause)
         :cause cause)))))

(defun ensure-user-data-migrated
    (&key
       (home (user-homedir-pathname))
       (argv nil)
       (input *standard-input*)
       (output *error-output*)
       (interactive-p :detect))
  (let ((old-directory (legacy-data-directory home))
        (new-directory (data-directory home)))
    (unless
        (and (uiop:directory-exists-p old-directory)
             (not (probe-file new-directory)))
      (return-from ensure-user-data-migrated
        :not-needed))
    (when (member "--yolo" argv :test #'string=)
      (refuse-user-data-migration
       "--yolo never authorizes migration"
       old-directory new-directory))
    (when (eq interactive-p :detect)
      (setf interactive-p
            (funcall
             *migration-interactive-p-function*
             input)))
    (unless interactive-p
      (refuse-user-data-migration
       "stdin is not interactive"
       old-directory new-directory))
    (format
     output
     "cadr found legacy data at ~A. Move it to ~A now? [y/N] "
     (namestring old-directory)
     (namestring new-directory))
    (finish-output output)
    (unless
        (affirmative-response-p
         (read-line input nil nil))
      (refuse-user-data-migration
       "user declined"
       old-directory new-directory))
    (move-user-data-directory
     old-directory new-directory)))

;;; Goal 18 flat-layout migration: before the agent/ layer existed, the
;;; nine agent residents (plus cadr-native crash/, config.json, and the
;;; baseline agent-dir residents trust.json and extensions/) sat directly
;;; in ~/.cadr/.  Startup moves them into ~/.cadr/agent/ automatically;
;;; server/ stays at the home root and project .cadr/ is unrelated.

(defparameter +flat-layout-residents+
  '("settings.json" "auth.json" "models.json" "config.json" "trust.json"
    "sessions" "themes" "prompts" "bin" "crash" "extensions"))

(defun flat-layout-present-residents (root)
  (remove-if-not
   (lambda (name)
     (probe-file (merge-pathnames name root)))
   +flat-layout-residents+))

(defun move-flat-layout-resident (root agent name)
  (let ((old (string-right-trim "/" (namestring (merge-pathnames name root))))
        (new (string-right-trim "/" (namestring (merge-pathnames name agent)))))
    (handler-case
        (sb-posix:rename old new)
      (error (cause)
        (error
         'cadr-ai:configuration-error
         :message
         (format nil
                 "Cannot move ~A into the agent layout: ~A"
                 old cause)
         :cause cause)))))

(defun ensure-agent-layout-migrated
    (&key
       (home (user-homedir-pathname))
       (environment-function #'uiop:getenv))
  "Move pre-goal-18 flat ~/.cadr/ residents into ~/.cadr/agent/.
Automatic and idempotent.  Refuses to choose when both layouts hold
data; does nothing when CADR_CODING_AGENT_DIR points elsewhere."
  (let ((override
          (funcall environment-function "CADR_CODING_AGENT_DIR")))
    (when (and override (plusp (length override)))
      (return-from ensure-agent-layout-migrated :not-needed)))
  (let* ((root
           (merge-pathnames
            ".cadr/"
            (uiop:ensure-directory-pathname home)))
         (agent (merge-pathnames "agent/" root))
         (present (flat-layout-present-residents root)))
    (cond
      ((null present) :not-needed)
      ((probe-file agent)
       (error
        'cadr-ai:configuration-error
        :message
        (format
         nil
         "Both the legacy flat layout and the agent layout hold data: ~{~A~^, ~} exist in ~A but ~A already exists. Move the listed entries into the agent directory manually, then restart."
         present
         (namestring root)
         (namestring agent))))
      (t
       (ensure-directories-exist agent)
       (dolist (name present)
         (move-flat-layout-resident root agent name))
       (let ((auth-path (merge-pathnames "auth.json" agent)))
         (when (probe-file auth-path)
           (sb-posix:chmod auth-path #o600)))
       :migrated))))

;;; ------------------------------------------------------------------
;;; Baseline content migrations (packages/coding-agent/src/migrations.ts).
;;; These run on every startup after flag validation and before settings
;;; or session work (baseline main.ts:605-607).  They migrate pi-format
;;; legacies that a ~/.cadr/agent/ directory can still carry: pre-auth.json
;;; credentials, agent-root session files, tools/ binaries, commands/
;;; prompt directories, and deprecated hooks//tools/ directories.

(defparameter +migration-guide-url+
  "https://github.com/earendil-works/pi-mono/blob/main/packages/coding-agent/CHANGELOG.md#extensions-migration"
  ;; Baseline MIGRATION_GUIDE_URL.  The migrated formats are inherited
  ;; from pi, so the baseline guide is the accurate documentation for
  ;; them; surfaced to the user as an identity adjudication item.
  )

(defparameter +extensions-doc-url+
  "https://github.com/earendil-works/pi-mono/blob/main/packages/coding-agent/docs/extensions.md"
  ;; Baseline EXTENSIONS_DOC_URL; see +MIGRATION-GUIDE-URL+.
  )

(defun migration-agent-file (name)
  (merge-pathnames name (cadr-core:coding-agent-directory)))

(defun read-json-file-object (path)
  "Parse PATH as a JSON object, or NIL when unreadable/not an object.
Baseline migrations skip on error rather than failing startup."
  (handler-case
      (let ((object
              (cadr-ai::parse-json
               (uiop:read-file-string path :external-format :utf-8))))
        (and (hash-table-p object) object))
    (error () nil)))

(defun write-json-file-object (path object &key (mode nil))
  (cadr-core:call-with-atomic-output-file
   path
   (lambda (stream)
     (write-string (cadr-ai::stringify-json object) stream)
     (terpri stream))
   :mode (or mode #o644)
   :durability :flush)
  path)

(defun migrate-auth-to-auth-json ()
  "Baseline migrateAuthToAuthJson: fold legacy oauth.json and
settings.json apiKeys into auth.json.  Returns the migrated provider
names.  Skips entirely when auth.json already exists."
  (let ((auth-path (migration-agent-file "auth.json"))
        (oauth-path (migration-agent-file "oauth.json"))
        (settings-path (migration-agent-file "settings.json")))
    (when (probe-file auth-path)
      (return-from migrate-auth-to-auth-json nil))
    (let ((migrated (cadr-ai::json-object))
          (providers nil))
      (when (probe-file oauth-path)
        (let ((oauth (read-json-file-object oauth-path)))
          (when oauth
            (maphash
             (lambda (provider credential)
               (when (hash-table-p credential)
                 (let ((entry (cadr-ai::json-object)))
                   (setf (gethash "type" entry) "oauth")
                   (maphash
                    (lambda (key value)
                      (setf (gethash key entry) value))
                    credential)
                   (setf (gethash provider migrated) entry)
                   (push provider providers))))
             oauth)
            (ignore-errors
              (rename-file oauth-path
                           (merge-pathnames "oauth.json.migrated"
                                            (cadr-core:coding-agent-directory)))))))
      (when (probe-file settings-path)
        (let ((settings (read-json-file-object settings-path)))
          (when settings
            (let ((api-keys (gethash "apiKeys" settings)))
              (when (hash-table-p api-keys)
                (maphash
                 (lambda (provider key)
                   (when (and (stringp key)
                              (not (gethash provider migrated)))
                     (let ((entry (cadr-ai::json-object)))
                       (setf (gethash "type" entry) "api_key"
                             (gethash "key" entry) key)
                       (setf (gethash provider migrated) entry)
                       (push provider providers))))
                 api-keys)
                (remhash "apiKeys" settings)
                (ignore-errors
                  (write-json-file-object settings-path settings)))))))
      (when (plusp (hash-table-count migrated))
        (ensure-directories-exist auth-path)
        (write-json-file-object auth-path migrated :mode #o600))
      (nreverse providers))))

(defun migrate-sessions-from-agent-root ()
  "Baseline migrateSessionsFromAgentRoot: v0.30.0 wrote session files
directly into the agent directory; move them under sessions/.  cadr's
session root is flat (session/discovery.lisp list-sessions), so the
target is the flat sessions/ directory rather than the baseline's
per-cwd encoded subdirectory; the moved files remain discoverable."
  (let* ((agent-directory
           (uiop:ensure-directory-pathname
            (cadr-core:coding-agent-directory)))
         (files
           (ignore-errors
             (directory
              (merge-pathnames "*.jsonl" agent-directory)))))
    (dolist (file (or files nil))
      (handler-case
          (let ((first-line
                  (with-open-file
                      (stream file :external-format :utf-8)
                    (read-line stream nil nil))))
            (when (and first-line (plusp (length (string-trim '(#\Space #\Tab) first-line))))
              (let ((header
                      (ignore-errors
                        (cadr-ai::parse-json first-line))))
                (when (and (hash-table-p header)
                           (string= "session"
                                    (cadr-ai::json-get header "type" ""))
                           (cadr-ai::json-get header "cwd"))
                  (let* ((sessions-directory
                           (cadr-core:agent-sessions-directory))
                         (target
                           (merge-pathnames
                            (file-namestring file)
                            sessions-directory)))
                    (unless (probe-file target)
                      (ensure-directories-exist sessions-directory)
                      (rename-file file target)))))))
        (error () nil)))))

(defun migrate-tools-to-bin (&key (output *standard-output*))
  "Baseline migrateToolsToBin: move managed fd/rg binaries from tools/
to bin/, printing the green baseline line when anything moved."
  (let ((tools-directory (cadr-core:agent-tools-directory))
        (bin-directory (cadr-core:agent-bin-directory))
        (moved-p nil))
    (when (uiop:directory-exists-p tools-directory)
      (dolist (name +managed-binary-names+)
        (let ((old (merge-pathnames name tools-directory))
              (new (merge-pathnames name bin-directory)))
          (when (probe-file old)
            (if (probe-file new)
                (ignore-errors (delete-file old))
                (handler-case
                    (progn
                      (ensure-directories-exist bin-directory)
                      (rename-file old new)
                      (setf moved-p t))
                  (error () nil)))))))
    (when moved-p
      (format output "~A~%"
              (cli-success-text
               output "Migrated managed binaries tools/ → bin/"))
      (finish-output output))
    moved-p))

(defun migrate-commands-to-prompts (base-directory label
                                    &key (output *standard-output*))
  "Baseline migrateCommandsToPrompts: rename commands/ to prompts/
when prompts/ does not exist yet.  BASE-DIRECTORY is the agent or
project config root; LABEL is \"Global\" or \"Project\"."
  (let ((base (uiop:ensure-directory-pathname base-directory)))
    (let ((commands (merge-pathnames "commands/" base))
          (prompts (merge-pathnames "prompts/" base)))
      (when (and (uiop:directory-exists-p commands)
                 (not (probe-file prompts)))
        (handler-case
            (progn
              (funcall *migration-rename-function* commands prompts)
              (format output "~A~%"
                      (cli-success-text
                       output
                       (format nil "Migrated ~A commands/ → prompts/"
                               label)))
              (finish-output output)
              t)
          (error (cause)
            (format output "~A~%"
                    (cli-warning-text
                     output
                     (format
                      nil
                      "Warning: Could not migrate ~A commands/ to prompts/: ~A"
                      label cause)))
            (finish-output output)
            nil))))))

(defun check-deprecated-extension-dirs (base-directory label)
  "Baseline checkDeprecatedExtensionDirs: warn about hooks/ and about
tools/ entries other than the auto-extracted fd/rg binaries."
  (let ((base (uiop:ensure-directory-pathname base-directory))
        (warnings nil))
    (when (uiop:directory-exists-p (merge-pathnames "hooks/" base))
      (push (format nil "~A hooks/ directory found. Hooks have been renamed to extensions."
                    label)
            warnings))
    (let ((tools (merge-pathnames "tools/" base)))
      (when (uiop:directory-exists-p tools)
        (let ((custom
                (remove-if
                 (lambda (name)
                   (let ((lower (string-downcase name)))
                     (or (member lower
                                 +managed-binary-names+
                                 :test #'string=)
                         (and (plusp (length name))
                              (char= (char name 0) #\.)))))
                 (ignore-errors
                   (mapcar
                    (lambda (path)
                      (if (uiop:directory-pathname-p path)
                          (car (last (pathname-directory path)))
                          (file-namestring path)))
                    (append
                     (uiop:directory-files tools)
                     (uiop:subdirectories tools)))))))
          (when custom
            (push (format nil "~A tools/ directory contains custom tools. Custom tools have been merged into extensions."
                          label)
                  warnings)))))
    (nreverse warnings)))

(defvar *pending-deprecation-warnings* nil
  "Deprecation warnings collected by RUN-CONTENT-MIGRATIONS at startup;
shown by the interactive path before the TUI takes over (baseline
main.ts:837-839).")

(defun run-content-migrations (cwd &key (output *standard-output*))
  "Baseline runMigrations (migrations.ts:297-307): content migrations
plus deprecated-directory warnings.  Returns the deprecation warnings;
the migrated auth providers are currently only informational in the
baseline as well."
  (migrate-auth-to-auth-json)
  (migrate-sessions-from-agent-root)
  (migrate-tools-to-bin :output output)
  (migrate-commands-to-prompts
   (cadr-core:coding-agent-directory) "Global" :output output)
  (migrate-commands-to-prompts
   (cadr-core:project-config-directory cwd) "Project" :output output)
  (let ((warnings
          (nconc
           (check-deprecated-extension-dirs
            (cadr-core:coding-agent-directory) "Global")
           (check-deprecated-extension-dirs
            (cadr-core:project-config-directory cwd) "Project"))))
    (setf *pending-deprecation-warnings* warnings)
    warnings))

(defun show-deprecation-warnings (warnings
                                  &key
                                    (output *standard-output*)
                                    (input *standard-input*))
  "Baseline showDeprecationWarnings: print each warning, the move
guidance and the two documentation URLs, then wait for a single
keypress in raw mode."
  (unless warnings
    (return-from show-deprecation-warnings nil))
  (dolist (warning warnings)
    (format output "~A~%"
            (cli-warning-text output (format nil "Warning: ~A" warning))))
  (format output "~A~%"
          (cli-warning-text
           output
           (format nil "~%Move your extensions to the extensions/ directory.")))
  (format output "~A~%"
          (cli-warning-text
           output
           (format nil "Migration guide: ~A" +migration-guide-url+)))
  (format output "~A~%"
          (cli-warning-text
           output
           (format nil "Documentation: ~A" +extensions-doc-url+)))
  (format output "~A~%"
          (cli-dim-text
           output
           (format nil "~%Press any key to continue...")))
  (finish-output output)
  (read-single-keypress input)
  (terpri output)
  (finish-output output)
  t)

(defun read-single-keypress (input)
  "Read one keypress, switching the terminal to raw mode when INPUT is
an interactive terminal (baseline: process.stdin.setRawMode(true))."
  #+sbcl
  (let ((fd
          (and (cadr-tui:terminal-stream-p input :input)
               (cadr-tui::stream-file-descriptor input :input))))
    (if (not fd)
        (read-char input nil nil)
        (let ((original (sb-posix:tcgetattr fd)))
          (unwind-protect
               (progn
                 (let ((raw (cadr-tui::raw-termios original)))
                   ;; Block until one byte arrives (baseline waits
                   ;; indefinitely for the keypress).
                   (setf
                    (aref (sb-posix:termios-cc raw) sb-posix:vmin) 1
                    (aref (sb-posix:termios-cc raw) sb-posix:vtime) 0)
                   (sb-posix:tcsetattr fd sb-posix:tcsanow raw))
                 (read-char input nil nil))
            (sb-posix:tcsetattr fd sb-posix:tcsanow original)))))
  #-sbcl
  (read-char input nil nil))
