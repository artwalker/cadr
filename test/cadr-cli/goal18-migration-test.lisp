(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

;;; Goal 18 Part B: the pre-agent-layer flat ~/.cadr/ layout migrates into
;;; ~/.cadr/agent/ automatically at startup.  Coverage: full move, second
;;; run idempotence, 0600 auth.json preservation, fresh installs, the
;;; both-layouts conflict, and the CADR_CODING_AGENT_DIR skip.

(defun goal18-seed-flat-layout (home &key (auth-mode #o600))
  (let ((root (merge-pathnames ".cadr/" home)))
    (dolist (directory '("sessions/" "crash/" "extensions/"))
      (ensure-directories-exist
       (merge-pathnames (format nil "~Aanchor" directory) root)))
    (dolist (file '("settings.json" "auth.json" "models.json"))
      (let ((path (merge-pathnames file root)))
        (ensure-directories-exist path)
        (write-text path "{}")))
    (sb-posix:chmod (merge-pathnames "auth.json" root) auth-mode)
    ;; server/ lives at the home root and must stay untouched.
    (let ((server-auth (merge-pathnames "server/auth.json" root)))
      (ensure-directories-exist server-auth)
      (write-text server-auth "{}"))
    root))

(test goal18-flat-layout-migrates-into-the-agent-layer
  (with-test-directory (directory)
    (let* ((home (merge-pathnames "home/" directory))
           (root (goal18-seed-flat-layout home))
           (agent (merge-pathnames "agent/" root)))
      (ensure-directories-exist (merge-pathnames "anchor" home))
      (is (eq :migrated
              (cadr-cli::ensure-agent-layout-migrated :home home)))
      (dolist (name '("settings.json" "auth.json" "models.json"
                      "sessions/" "crash/" "extensions/"))
        (is (probe-file (merge-pathnames name agent))
            "~A was not moved into the agent layer" name)
        (is (not (probe-file (merge-pathnames name root)))
            "~A was left behind in the flat layout" name))
      (is (probe-file (merge-pathnames "server/auth.json" root))
          "server/ must stay at the home root"))))

(test goal18-flat-layout-migration-is-idempotent
  (with-test-directory (directory)
    (let ((home (merge-pathnames "home/" directory)))
      (goal18-seed-flat-layout home)
      (ensure-directories-exist (merge-pathnames "anchor" home))
      (is (eq :migrated
              (cadr-cli::ensure-agent-layout-migrated :home home)))
      (is (eq :not-needed
              (cadr-cli::ensure-agent-layout-migrated :home home))))))

(test goal18-flat-layout-migration-preserves-auth-file-mode
  (with-test-directory (directory)
    (let ((home (merge-pathnames "home/" directory)))
      (goal18-seed-flat-layout home :auth-mode #o600)
      (ensure-directories-exist (merge-pathnames "anchor" home))
      (cadr-cli::ensure-agent-layout-migrated :home home)
      (is (= #o600
             (logand
              #o777
              (sb-posix:stat-mode
               (sb-posix:stat
                (merge-pathnames ".cadr/agent/auth.json" home)))))
          "migrated auth.json must stay 0600"))))

(test goal18-fresh-install-needs-no-migration-and-uses-the-agent-layer
  (with-test-directory (directory)
    (let ((home (merge-pathnames "home/" directory)))
      (ensure-directories-exist (merge-pathnames "anchor" home))
      (is (eq :not-needed
              (cadr-cli::ensure-agent-layout-migrated :home home)))
      (let ((cadr-core::*path-environment-function* (constantly nil)))
        (is (equal (merge-pathnames ".cadr/agent/" (user-homedir-pathname))
                   (cadr-cli::default-agent-directory)))))))

(test goal18-conflicting-layouts-fail-closed
  (with-test-directory (directory)
    (let* ((home (merge-pathnames "home/" directory))
           (root (goal18-seed-flat-layout home)))
      (ensure-directories-exist (merge-pathnames "anchor" home))
      (ensure-directories-exist
       (merge-pathnames "agent/settings.json" root))
      (signals cadr-ai:configuration-error
        (cadr-cli::ensure-agent-layout-migrated :home home))
      ;; Nothing moved: the flat residents are all still in place.
      (is (probe-file (merge-pathnames "auth.json" root))))))

(test goal18-env-override-skips-the-layout-migration
  (with-test-directory (directory)
    (let ((home (merge-pathnames "home/" directory)))
      (goal18-seed-flat-layout home)
      (ensure-directories-exist (merge-pathnames "anchor" home))
      (is (eq :not-needed
              (cadr-cli::ensure-agent-layout-migrated
               :home home
               :environment-function
               (lambda (name)
                 (and (string= name "CADR_CODING_AGENT_DIR")
                      "/elsewhere/agent")))))
      (is (probe-file (merge-pathnames ".cadr/auth.json" home))
          "override homes must not be touched"))))
