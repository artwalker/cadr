(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defun goal26-clipboard-pgid-text (text)
  (string-trim '(#\Space #\Tab #\Newline #\Return) text))

(defun goal26-clipboard-pgid-digits-p (text)
  (and (plusp (length text))
       (every (lambda (character)
                (char<= #\0 character #\9))
              text)))

(defun goal26-clipboard-command-output (argv)
  ;; Same spawn as the clipboard runners. Stdout is a string here so the
  ;; assertion can see the process group the upstream test prints.
  (uiop:run-program
   (cadr-cli::clipboard-process-argv argv)
   :output :string
   :error-output nil))

(test goal26-clipboard-command-runs-outside-the-process-group
  ;; v1.4.0 packages/coding-agent/test/clipboard-command.test.ts
  ;; "runs commands outside pi's process group" (#11179).
  ;; sh prints its own process group. ps prints this process's group.
  (if (uiop:os-windows-p)
      (skip "upstream skips process-group detachment on win32")
      (let ((child
              (goal26-clipboard-pgid-text
               (goal26-clipboard-command-output
                '("sh" "-c" "ps -o pgid= -p $$"))))
            (own
              (goal26-clipboard-pgid-text
               (goal26-clipboard-command-output
                (list "ps" "-o" "pgid=" "-p"
                      (princ-to-string (sb-posix:getpid)))))))
        (is (goal26-clipboard-pgid-digits-p child))
        (is (goal26-clipboard-pgid-digits-p own))
        (is (not (string= child own)))
        ;; Node's detached flag is setsid(2), so the helper's session
        ;; id differs from this process.
        (when (probe-file #P"/usr/bin/setsid")
          (let ((child-sid
                  (goal26-clipboard-pgid-text
                   (goal26-clipboard-command-output
                    '("sh" "-c" "ps -o sid= -p $$"))))
                (own-sid
                  (goal26-clipboard-pgid-text
                   (goal26-clipboard-command-output
                    (list "ps" "-o" "sid=" "-p"
                          (princ-to-string (sb-posix:getpid)))))))
            (is (goal26-clipboard-pgid-digits-p child-sid))
            (is (goal26-clipboard-pgid-digits-p own-sid))
            (is (not (string= child-sid own-sid)))))
        (uiop:with-temporary-file (:pathname path)
          (is (eq t
                  (cadr-cli::default-clipboard-copy-runner
                   (list "sh" "-c"
                         (format nil "ps -o pgid= -p $$ > '~A'"
                                 (namestring path)))
                   "copied")))
          (let ((written
                  (goal26-clipboard-pgid-text
                   (uiop:read-file-string path))))
            (is (goal26-clipboard-pgid-digits-p written))
            (is (not (string= written own)))))
        (uiop:with-temporary-file (:pathname path)
          (cadr-cli::default-clipboard-image-runner
           (list "sh" "-c"
                 (format nil "ps -o pgid= -p $$ > '~A'"
                         (namestring path))))
          (let ((written
                  (goal26-clipboard-pgid-text
                   (uiop:read-file-string path))))
            (is (goal26-clipboard-pgid-digits-p written))
            (is (not (string= written own)))))
        (is (null
             (cadr-cli::default-clipboard-copy-runner
              '("sh" "-c" "exit 1")
              "")))
        (is (null
             (cadr-cli::default-clipboard-copy-runner
              '("cadr-clipboard-command-does-not-exist")
              ""))))))
