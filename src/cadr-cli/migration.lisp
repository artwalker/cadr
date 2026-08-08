(in-package #:cadr-cli)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sb-posix))

(defparameter *migration-interactive-p-function*
  #'cadr-tui:terminal-stream-p)

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
