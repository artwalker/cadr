(in-package #:cadr-core)

;;; The single owner of the user-level path layout.  Baseline
;;; packages/coding-agent/src/config.ts:488-565 decides the agent config
;;; directory once (getAgentDir) and derives every resident from it; every
;;; cadr system reaches the same decisions through this file so the layout
;;; can never be re-decided per call site.

(defparameter *path-environment-function* #'uiop:getenv
  "Reads process environment variables; rebound by tests.")

(defun expand-config-path-override (value)
  "Expand a leading ~ in an environment-provided path, mirroring the
baseline expandTildePath/normalizePath treatment of override values."
  (if (and (plusp (length value))
           (char= (char value 0) #\~)
           (or (= (length value) 1)
               (char= (char value 1) #\/)))
      (merge-pathnames
       (if (= (length value) 1)
           "./"
           (subseq value 2))
       (user-homedir-pathname))
      (pathname value)))

(defun config-home-directory ()
  "The cadr home root ~/.cadr/.  Only server/ stays at this level; all
agent content lives one level down under CODING-AGENT-DIRECTORY."
  (merge-pathnames ".cadr/" (user-homedir-pathname)))

(defun coding-agent-directory ()
  "The agent config directory: $CADR_CODING_AGENT_DIR (tilde-expanded)
when set, otherwise ~/.cadr/agent/.  Baseline getAgentDir
(config.ts:513-520) with the I04 CADR_ prefix."
  (let ((override
          (funcall *path-environment-function* "CADR_CODING_AGENT_DIR")))
    (if (and override (plusp (length override)))
        (uiop:ensure-directory-pathname
         (expand-config-path-override override))
        (merge-pathnames "agent/" (config-home-directory)))))

(defun agent-settings-path ()
  (merge-pathnames "settings.json" (coding-agent-directory)))

(defun agent-auth-path ()
  (merge-pathnames "auth.json" (coding-agent-directory)))

(defun agent-models-path ()
  (merge-pathnames "models.json" (coding-agent-directory)))

(defun agent-config-path ()
  ;; cadr-native file with no baseline counterpart; it still belongs to
  ;; the agent directory so user config is never split across layouts.
  (merge-pathnames "config.json" (coding-agent-directory)))

(defun agent-trust-path ()
  (merge-pathnames "trust.json" (coding-agent-directory)))

(defun agent-sessions-directory ()
  (merge-pathnames "sessions/" (coding-agent-directory)))

(defun agent-themes-directory ()
  (merge-pathnames "themes/" (coding-agent-directory)))

(defun agent-prompts-directory ()
  (merge-pathnames "prompts/" (coding-agent-directory)))

(defun agent-tools-directory ()
  (merge-pathnames "tools/" (coding-agent-directory)))

(defun agent-bin-directory ()
  (merge-pathnames "bin/" (coding-agent-directory)))

(defun agent-extensions-directory ()
  (merge-pathnames "extensions/" (coding-agent-directory)))

(defun agent-crash-directory ()
  ;; cadr-native I02 crash logs; no baseline counterpart, but they live
  ;; with the agent data rather than at the home root.
  (merge-pathnames "crash/" (coding-agent-directory)))

(defun agent-debug-log-path ()
  ;; Baseline getDebugLogPath: agent/<APP_NAME>-debug.log (I04 name).
  (merge-pathnames "cadr-debug.log" (coding-agent-directory)))

(defparameter +project-config-directory-name+ ".cadr/"
  "The project-level config directory name (cwd/.cadr/).  The name is
decided once here; project code derives from PROJECT-CONFIG-DIRECTORY
instead of repeating the literal.")

(defun project-config-directory (base)
  "The project-level config directory under BASE (a project root)."
  (merge-pathnames
   +project-config-directory-name+
   (uiop:ensure-directory-pathname base)))
