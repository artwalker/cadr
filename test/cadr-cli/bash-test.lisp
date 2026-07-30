(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(test bash-merges-output-reports-nonzero-and-truncates-tail
  (with-test-directory (directory)
    (let ((tool (make-bash-tool directory)))
      (multiple-value-bind (content details)
          (invoke-tool
           tool
           (args "command"
                 "printf 'out\\n'; printf 'err\\n' >&2; exit 7"))
        (is (search "out" (result-text content)))
        (is (search "err" (result-text content)))
        (is (search "process exited with code 7"
                    (string-downcase (result-text content))))
        (is (= 7 (getf details :exit-code))))
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
