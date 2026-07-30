(in-package #:pi-cli/tests)
(in-suite pi-cli-suite)

(test core-exposes-no-built-in-approval-or-yolo-switch
  (multiple-value-bind (symbol status)
      (find-symbol "CONFIRM-TOOL-CALL" :pi-cli)
    (declare (ignore symbol))
    (is (not (eq :external status))))
  (signals error
    (pi-cli::parse-cli-arguments
     '("--yolo"))))

(test side-effect-tools-execute-directly-by-default
  (with-test-directory (directory)
    (let* ((path (merge-pathnames "direct.txt" directory))
           (tool (make-write-tool directory)))
      (multiple-value-bind (content details)
          (funcall
           (pi-ai:tool-executor tool)
           "direct-write"
           (args
            "path" "direct.txt"
            "content" "executed"))
        (declare (ignore details))
        (is (probe-file path))
        (is (string= "executed" (read-text path)))
        (is (search "Wrote"
                    (result-text content)))))))
