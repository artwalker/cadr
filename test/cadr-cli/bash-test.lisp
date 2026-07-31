(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(test bash-merges-output-reports-nonzero-and-truncates-tail
  (with-test-directory (directory)
    (let ((tool (make-bash-tool directory)))
      (let ((condition
              (handler-case
                  (progn
                    (invoke-tool
                     tool
                     (args "command"
                           "printf 'out\\n'; printf 'err\\n' >&2; exit 7"))
                    nil)
                (error (condition)
                  condition))))
        (is (not (null condition)))
        (when condition
          (let ((message (princ-to-string condition)))
            (is (search "out" message))
            (is (search "err" message))
            (is (search
                 "Command exited with code 7"
                 message)))))
      (multiple-value-bind (content details)
          (invoke-tool
           tool
           (args "command"
                 "for i in $(seq 1 2105); do echo line-$i; done"))
        (is (not (search (format nil "line-1~%")
                         (result-text content))))
        (is (search "line-2105" (result-text content)))
        (is (eq t (getf details :truncated)))
        (is (probe-file (getf details :full-output-path)))
        (delete-file (getf details :full-output-path))))))

(test goal9-b-bash-nonzero-exit-is-a-tool-error
  (with-test-directory (directory)
    (let* ((tool (make-bash-tool directory))
           (condition
             (handler-case
                 (progn
                   (invoke-tool
                    tool
                    (args
                     "command"
                     "printf 'out\\n'; printf 'err\\n' >&2; exit 7"))
                   nil)
               (error (condition)
                 condition))))
      (is (not (null condition)))
      (when condition
        (let ((message (princ-to-string condition)))
          (is (search "out" message))
          (is (search "err" message))
          (is (search
               "Command exited with code 7"
               message)))))))

(test bash-timeout-kills-the-process-group
  (with-test-directory (directory)
    (let ((tool (make-bash-tool directory)))
      (signals error
        (invoke-tool
         tool
         (args
          "command"
          "/bin/bash -c 'trap \"\" TERM; while :; do sleep 1; done' & child=$!; printf '%s' \"$child\" > child.pid; wait"
          "timeout" 0.2)))
      (let* ((pid
               (parse-integer
                (string-trim
                 '(#\Space #\Tab #\Newline #\Return)
                 (read-text
                  (merge-pathnames "child.pid" directory)))))
             (process-path
               (pathname (format nil "/proc/~D/" pid))))
        (is (not (probe-file process-path)))))))

(test bash-captures-active-post-exit-output-and-releases-idle-pipes
  (with-test-directory (directory)
    (let ((tool (make-bash-tool directory)))
      (multiple-value-bind (content details)
          (invoke-tool
           tool
           (args
            "command"
            "printf 'HEAD\\n'; (for i in 1 2 3 4 5 6; do sleep 0.05; printf 'TICK%s\\n' \"$i\"; done) &"))
        (is (= 0 (getf details :exit-code)))
        (is (search "HEAD" (result-text content)))
        (is (search "TICK6" (result-text content))))
      (let ((started
              (get-internal-real-time)))
        (multiple-value-bind (content details)
            (invoke-tool
             tool
             (args
              "command"
              "printf 'DONE\\n'; (sleep 30) &"))
          (is (= 0 (getf details :exit-code)))
          (is (search "DONE" (result-text content)))
          (is
           (< (/ (- (get-internal-real-time)
                    started)
                 internal-time-units-per-second)
              2.0)))))))
