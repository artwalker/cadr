(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(test goal28-session-dir-settings-reach-existing-resolver
  (let* ((manager (cadr-cli::make-memory-settings-manager))
         (expected-default
           (namestring
            (cadr-agent:default-session-directory)))
         (resolved-absent
           (cadr-cli::resolve-session-directory
            :settings-directory
            (cadr-cli::settings-session-dir manager)
            :cwd (uiop:getcwd)))
         (created-absent
           (cadr-cli::session-manager-create
            (uiop:getcwd) resolved-absent)))
    (is (null (cadr-cli::settings-session-dir manager)))
    (is (string= expected-default
                 (namestring resolved-absent)))
    (is (string=
         expected-default
         (namestring
          (cadr-cli::session-manager-directory
           created-absent))))
    (is (eq t (cadr-cli::settings-boolean-value
               manager "compaction" t "enabled")))
    (is (= 20000
           (cadr-cli::settings-compaction-keep-recent-tokens
            manager)))
    (is (= 16384
           (cadr-cli::settings-compaction-reserve-tokens
            manager)))
    (is (= 16384
           (cadr-cli::settings-branch-summary-reserve-tokens
            manager)))
    (is (eq nil
            (cadr-cli::settings-branch-summary-skip-prompt-p
             manager)))
    (is (null (cadr-cli::settings-shell-path manager)))
    (is (null
         (cadr-cli::settings-shell-command-prefix manager))))
  (with-test-directory (root)
    (let* ((global (merge-pathnames "settings.json" root))
           (expected-custom
             "/tmp/cadr-g28-session-dir-custom/")
           (_
             (write-text
              global
              "{\"sessionDir\":\"/tmp/cadr-g28-session-dir-custom\"}"))
           (manager
             (cadr-cli::make-settings-manager
              :global-path global))
           (resolved
             (cadr-cli::resolve-session-directory
              :settings-directory
              (cadr-cli::settings-session-dir manager)
              :cwd root))
           (created
             (cadr-cli::session-manager-create
              root resolved)))
      (declare (ignore _))
      (is (string=
           "/tmp/cadr-g28-session-dir-custom"
           (cadr-cli::settings-session-dir manager)))
      (is (string= expected-custom (namestring resolved)))
      (is (string=
           expected-custom
           (namestring
            (cadr-cli::session-manager-directory
             created))))))
  (let* ((settings
           (cadr-cli::make-memory-sdk-settings-manager
            (args
             "sessionDir"
             "/tmp/cadr-g28-session-dir-custom")))
         (expected-custom
           "/tmp/cadr-g28-session-dir-custom/")
         (resolved
           (cadr-cli::resolve-session-directory
            :settings-directory
            (cadr-cli:sdk-settings-session-dir settings)
            :cwd (uiop:getcwd)))
         (created
           (cadr-cli::session-manager-create
            (uiop:getcwd) resolved)))
    (is (string=
         "/tmp/cadr-g28-session-dir-custom"
         (cadr-cli:sdk-settings-session-dir settings)))
    (is (string= expected-custom (namestring resolved)))
    (is (string=
         expected-custom
         (namestring
          (cadr-cli::session-manager-directory
           created))))
    (is (eq t
            (cadr-cli:sdk-settings-compaction-enabled-p
             settings)))
    (is (= 20000
           (cadr-cli:sdk-settings-compaction-keep-recent-tokens
            settings)))
    (is (= 16384
           (cadr-cli:sdk-settings-branch-summary-reserve-tokens
            settings)))
    (is (null
         (cadr-cli:sdk-settings-shell-path settings)))))

(defmacro with-path-env ((pairs) &body body)
  `(let ((cadr-core::*path-environment-function*
           (lambda (name)
             (cdr (assoc name ,pairs :test #'string=)))))
     ,@body))

(defun set-test-env (name value)
  (if (null value)
      (sb-posix:unsetenv name)
      (setf (uiop:getenv name) value)))

(defun call-with-restored-env (pairs function)
  (let ((saved
          (loop for (name) in pairs
                collect (cons name (uiop:getenv name)))))
    (unwind-protect
         (progn
           (dolist (pair pairs)
             (set-test-env (car pair) (cdr pair)))
           (funcall function))
      (dolist (pair saved)
        (set-test-env (car pair) (cdr pair))))))

(test goal46-session-dir-env-sits-between-cli-and-settings
  ;; pi@4a080252f main.ts sessionDir precedence and environment-variables.md.
  (is (search "CADR_CODING_AGENT_SESSION_DIR"
              cadr-cli::+cli-usage-suffix+))
  (is (search "overridden by --session-dir"
              cadr-cli::+cli-usage-suffix+))
  (with-test-directory (root)
    (let ((cli (merge-pathnames "from-cli/" root))
          (env (merge-pathnames "from-env/" root))
          (settings (merge-pathnames "from-settings/" root)))
      (with-path-env ((list (cons "CADR_CODING_AGENT_SESSION_DIR"
                                  (namestring env))))
        (is (equal
             (uiop:ensure-directory-pathname cli)
             (cadr-cli::resolve-session-directory
              :cli-directory (namestring cli)
              :settings-directory (namestring settings)
              :cwd root)))
        (is (equal
             (uiop:ensure-directory-pathname env)
             (cadr-cli::resolve-session-directory
              :settings-directory (namestring settings)
              :cwd root))))
      (with-path-env ((list (cons "CADR_CODING_AGENT_SESSION_DIR" "")))
        (is (equal
             (uiop:ensure-directory-pathname settings)
             (cadr-cli::resolve-session-directory
              :settings-directory (namestring settings)
              :cwd root))))
      (with-path-env ((list (cons "CADR_CODING_AGENT_SESSION_DIR"
                                  "rel-sessions")))
        (is (equal
             (merge-pathnames "rel-sessions/" root)
             (cadr-cli::resolve-session-directory :cwd root))))
      (with-path-env ((list (cons "CADR_CODING_AGENT_SESSION_DIR"
                                  "~/g46-sessions")))
        (is (equal
             (uiop:ensure-directory-pathname
              (cadr-core::expand-config-path-override "~/g46-sessions"))
             (cadr-cli::resolve-session-directory :cwd root)))))))

(test goal46-package-dir-overrides-the-asset-root
  ;; pi@4a080252f getPackageDir. A non-empty CADR_PACKAGE_DIR replaces
  ;; the ASDF root, including the docs path derived from it.
  (is (search "CADR_PACKAGE_DIR" cadr-cli::+cli-usage-suffix+))
  (with-test-directory (root)
    (with-path-env ((list (cons "CADR_PACKAGE_DIR" (namestring root))))
      (is (equal (uiop:ensure-directory-pathname root)
                 (cadr-ai::cadr-cli-source-directory)))
      (is (equal (merge-pathnames "docs/" root)
                 (cadr-ai::cadr-docs-directory)))))
  (with-path-env ((list (cons "CADR_PACKAGE_DIR" "")))
    (is (equal (uiop:ensure-directory-pathname
                (asdf:system-source-directory "cadr-cli"))
               (cadr-ai::cadr-cli-source-directory))))
  (with-path-env ((list (cons "CADR_PACKAGE_DIR" "~/g46-package")))
    (is (equal (uiop:ensure-directory-pathname
                (cadr-core::expand-config-path-override "~/g46-package"))
               (cadr-ai::cadr-cli-source-directory)))))

(test goal46-hardware-cursor-setting-beats-exact-one
  ;; pi@4a080252f getShowHardwareCursor. false stays off when the
  ;; environment is "1". Only a missing key consults that exact string.
  (let ((missing (cadr-cli::make-memory-settings-manager))
        (disabled
          (cadr-cli::make-memory-settings-manager
           (cadr-ai::json-object "showHardwareCursor" nil)))
        (enabled
          (cadr-cli::make-memory-settings-manager
           (cadr-ai::json-object "showHardwareCursor" t))))
    (is (cadr-cli::settings-show-hardware-cursor-p
         missing :environment "1"))
    (is (not (cadr-cli::settings-show-hardware-cursor-p
              missing :environment "true")))
    (is (not (cadr-cli::settings-show-hardware-cursor-p
              missing :environment "0")))
    (is (not (cadr-cli::settings-show-hardware-cursor-p
              missing :environment "")))
    (is (not (cadr-cli::settings-show-hardware-cursor-p
              missing :environment nil)))
    (is (not (cadr-cli::settings-show-hardware-cursor-p
              disabled :environment "1")))
    (is (cadr-cli::settings-show-hardware-cursor-p
         enabled :environment "0")))
  (call-with-restored-env
   '(("CADR_HARDWARE_CURSOR" . "1"))
   (lambda ()
     (is (cadr-cli::settings-show-hardware-cursor-p
          (cadr-cli::make-memory-settings-manager))))))

(test goal46-telemetry-env-overrides-the-setting
  ;; pi@4a080252f isInstallTelemetryEnabled. A set CADR_TELEMETRY wins,
  ;; including the empty string. 1/true/yes enable; anything else disables.
  (is (search "CADR_TELEMETRY" cadr-cli::+cli-usage-suffix+))
  (let* ((manager
           (cadr-cli::make-memory-settings-manager
            (cadr-ai::json-object "enableInstallTelemetry" nil))))
    (is (not (cadr-cli::install-telemetry-enabled-p
              manager :environment nil)))
    (is (cadr-cli::install-telemetry-enabled-p
         manager :environment "1"))
    (is (cadr-cli::install-telemetry-enabled-p
         manager :environment "YES"))
    (is (cadr-cli::install-telemetry-enabled-p
         manager :environment "true"))
    (is (not (cadr-cli::install-telemetry-enabled-p
              manager :environment "no")))
    (is (not (cadr-cli::install-telemetry-enabled-p
              manager :environment "false")))
    (is (not (cadr-cli::install-telemetry-enabled-p
              manager :environment "0")))
    (is (not (cadr-cli::install-telemetry-enabled-p
              manager :environment "")))
    (is (not (cadr-cli::install-telemetry-enabled-p
              manager :environment "2"))))
  (call-with-restored-env
   '(("CADR_TELEMETRY" . "no"))
   (lambda ()
     (is (not (cadr-cli::install-telemetry-enabled-p
               (cadr-cli::make-memory-settings-manager)))))))

(test goal46-fullscreen-wheel-scroll-lines-clamp-on-read-and-write
  ;; pi@4a080252f settings-manager.test.ts "persists fullscreen wheel
  ;; scroll lines" and get/setFullscreenWheelScrollLines.
  (dolist (case '(("{\"fullscreenWheelScrollLines\":7.9}" 7)
                  ("{\"fullscreenWheelScrollLines\":0}" 1)
                  ("{\"fullscreenWheelScrollLines\":1000}" 100)
                  ("{\"fullscreenWheelScrollLines\":-3.2}" 1)
                  ("{\"fullscreenWheelScrollLines\":\"fast\"}" :auto)
                  ("{\"fullscreenWheelScrollLines\":null}" :auto)
                  ("{\"fullscreenWheelScrollLines\":\"3\"}" :auto)
                  ("{\"fullscreenWheelScrollLines\":false}" :auto)
                  ("{}" :auto)))
    (destructuring-bind (text expected) case
      (let ((manager
              (cadr-cli::make-memory-settings-manager
               (cadr-ai::parse-json text))))
        (is (equal expected
                   (cadr-cli::settings-fullscreen-wheel-scroll-lines
                    manager))
            text))))
  (with-test-directory (root)
    (let* ((path (merge-pathnames "settings.json" root))
           (manager
             (cadr-cli::make-settings-manager :global-path path)))
      (cadr-cli::settings-assign-fullscreen-wheel-scroll-lines
       manager 3)
      (is (= 3
             (cadr-ai::json-get
              (cadr-ai::parse-json (read-text path))
              "fullscreenWheelScrollLines")))
      (cadr-cli::settings-assign-fullscreen-wheel-scroll-lines
       manager 0)
      (is (= 1
             (cadr-ai::json-get
              (cadr-ai::parse-json (read-text path))
              "fullscreenWheelScrollLines")))
      (cadr-cli::settings-assign-fullscreen-wheel-scroll-lines
       manager 1000)
      (is (= 100
             (cadr-ai::json-get
              (cadr-ai::parse-json (read-text path))
              "fullscreenWheelScrollLines")))
      (cadr-cli::settings-assign-fullscreen-wheel-scroll-lines
       manager 7.9)
      (is (= 7
             (cadr-ai::json-get
              (cadr-ai::parse-json (read-text path))
              "fullscreenWheelScrollLines")))
      (cadr-cli::settings-assign-fullscreen-wheel-scroll-lines
       manager "auto")
      (is (string=
           "auto"
           (cadr-ai::json-get
            (cadr-ai::parse-json (read-text path))
            "fullscreenWheelScrollLines"))))))
