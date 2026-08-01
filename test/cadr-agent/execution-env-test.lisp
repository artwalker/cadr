(in-package #:cadr-agent/tests)
(in-suite cadr-agent-suite)

(defun execution-value (thunk)
  (multiple-value-bind (value error)
      (funcall thunk)
    (when error
      (fail "Unexpected execution environment error: ~A"
            (cadr-agent::harness-operation-error-message
             error)))
    value))

(test node-execution-environment-covers-files-paths-and-symlinks
  (with-session-directories (sessions cwd other-cwd)
    (values sessions other-cwd)
    (let ((environment
            (cadr-agent::make-node-execution-env
             :cwd cwd)))
      (execution-value
       (lambda ()
         (cadr-agent::execution-env-write-file
          environment
          "nested/file.txt"
          (format nil "one~%two~%three"))))
      (is
       (string=
        (format nil "one~%two~%three")
        (execution-value
         (lambda ()
           (cadr-agent::execution-env-read-text-file
            environment
            "nested/file.txt")))))
      (is
       (equal
        '("one" "two")
        (execution-value
         (lambda ()
           (cadr-agent::execution-env-read-text-lines
            environment
            "nested/file.txt"
            :max-lines 2)))))
      (execution-value
       (lambda ()
         (cadr-agent::execution-env-append-file
          environment "nested/file.txt"
          (format nil "~%four"))))
      (is
       (search
        "four"
        (execution-value
         (lambda ()
           (cadr-agent::execution-env-read-text-file
            environment "nested/file.txt")))))
      (let* ((target
               (merge-pathnames
                "nested/file.txt" cwd))
             (link
               (merge-pathnames "link.txt" cwd)))
        (sb-posix:symlink
         (namestring target)
         (namestring link))
        (let ((info
                (execution-value
                 (lambda ()
                   (cadr-agent::execution-env-file-info
                    environment "link.txt")))))
          (is (eq
               :symlink
               (cadr-agent::execution-file-info-kind
                info))))
        (is
         (string=
          (namestring (truename target))
          (execution-value
           (lambda ()
             (cadr-agent::execution-env-canonical-path
              environment "link.txt"))))))
      (let ((entries
              (execution-value
               (lambda ()
                 (cadr-agent::execution-env-list-directory
                  environment ".")))))
        (is
         (equal
          '("link.txt" "nested")
          (sort
           (mapcar
            #'cadr-agent::execution-file-info-name
            entries)
           #'string<))))
      (multiple-value-bind (value error)
          (cadr-agent::execution-env-read-text-file
           environment "missing.txt")
        (is (null value))
        (is
         (eq
          :not-found
          (cadr-agent::harness-operation-error-code
           error))))
      (is
       (not
        (execution-value
         (lambda ()
           (cadr-agent::execution-env-exists-p
            environment "missing.txt")))))
      (let ((directory
              (execution-value
               (lambda ()
                 (cadr-agent::execution-env-create-temp-directory
                  environment :prefix "env-"))))
            (file
              (execution-value
               (lambda ()
                 (cadr-agent::execution-env-create-temp-file
                  environment
                  :prefix "env-"
                  :suffix ".txt")))))
        (is (uiop:directory-exists-p directory))
        (is (probe-file file))
        (execution-value
         (lambda ()
           (cadr-agent::execution-env-remove
            environment directory
            :recursive-p t
            :force-p t)))
        (execution-value
         (lambda ()
           (cadr-agent::execution-env-remove
            environment file
            :force-p t))))
      (cadr-agent::execution-env-cleanup environment))))

(test node-execution-environment-executes-streams-times-out-and-aborts
  (with-session-directories (sessions cwd other-cwd)
    (values sessions other-cwd)
    (let ((environment
            (cadr-agent::make-node-execution-env
             :cwd cwd
             :shell-environment
             '(("BASE" . "base"))))
          (stdout-chunks nil)
          (stderr-chunks nil))
      (let ((result
              (execution-value
               (lambda ()
                 (cadr-agent::execution-env-exec
                  environment
                  "printf '%s' \"$BASE-$EXTRA-$PWD\"; printf err >&2; exit 7"
                  :environment '(("EXTRA" . "extra"))
                  :on-stdout
                  (lambda (chunk)
                    (push chunk stdout-chunks))
                  :on-stderr
                  (lambda (chunk)
                    (push chunk stderr-chunks)))))))
        (is (= 7
               (cadr-agent::execution-result-exit-code
                result)))
        (is
         (search
          "base-extra"
          (cadr-agent::execution-result-stdout
           result)))
        (is
         (string=
          "err"
          (cadr-agent::execution-result-stderr
           result)))
        (is
         (search
          "base-extra"
          (format nil "~{~A~}"
                  (nreverse stdout-chunks))))
        (is
         (string=
          "err"
          (format nil "~{~A~}"
                  (nreverse stderr-chunks)))))
      (multiple-value-bind (value error)
          (cadr-agent::execution-env-exec
           environment "exec /usr/bin/tail -f /dev/null"
           :timeout 1)
        (is (null value))
        (is
         (eq
          :timeout
          (cadr-agent::harness-operation-error-code
           error))))
      (let ((signal
              (cadr-agent::make-extension-cancellation-signal)))
        (cadr-agent::abort-extension-cancellation-signal
         signal)
        (multiple-value-bind (value error)
            (cadr-agent::execution-env-exec
             environment "printf never"
             :signal signal)
          (is (null value))
          (is
           (eq
            :aborted
            (cadr-agent::harness-operation-error-code
             error)))))
      (let ((missing
              (cadr-agent::make-node-execution-env
               :cwd cwd
               :shell-path
               (merge-pathnames "missing-shell" cwd))))
        (multiple-value-bind (value error)
            (cadr-agent::execution-env-exec
             missing "true")
          (is (null value))
          (is
           (eq
            :shell-unavailable
            (cadr-agent::harness-operation-error-code
             error)))))
      (cadr-agent::execution-env-cleanup
       environment))))

(test node-execution-environment-keeps-child-stderr-and-isolates-setsid-stderr
  (with-session-directories (sessions cwd other-cwd)
    (values sessions other-cwd)
    (let* ((environment
             (cadr-agent::make-node-execution-env
              :cwd cwd))
           (argv
             (cadr-agent::execution-wrapper-argv
              #p"/tmp/cadr-test.pgid"
              "/bin/bash"
              "printf child-stderr >&2"))
           (wrapper (third argv)))
      (is (search "3>&2 2>/dev/null" wrapper))
      (is (search "2>&3" wrapper))
      (let ((result
              (execution-value
               (lambda ()
                 (cadr-agent::execution-env-exec
                  environment
                  "printf child-stderr >&2")))))
        (is (string=
             "child-stderr"
             (cadr-agent::execution-result-stderr
              result)))
        (is (null
             (search
              "setsid"
              (cadr-agent::execution-result-stderr
               result)))))
      (cadr-agent::execution-env-cleanup environment))))
