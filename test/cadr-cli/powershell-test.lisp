(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(test g21-powershell-args-match-baseline
  (is (equal
       '("-NoProfile" "-NonInteractive" "-ExecutionPolicy"
         "Bypass" "-Command")
       +powershell-args+)))

(test g21-powershell-tool-rejects-non-windows-execution
  (unless (uiop:os-windows-p)
    (with-test-directory (directory)
      (let ((tool (make-powershell-tool directory))
            (condition
              (handler-case
                  (progn
                    (invoke-tool tool (args "command" "Write-Output test"))
                    nil)
                (error (condition) condition))))
        (is (not (null condition)))
        (when condition
          (is (search
               "The powershell tool is only available on Windows."
               (princ-to-string condition))))))))

(test g21-powershell-tool-is-available-in-all-coding-tools
  (with-test-directory (directory)
    (is (member
         "powershell"
         (mapcar #'cadr-ai:tool-name
                 (make-all-coding-tools directory))
         :test #'string=))))

(test g21-powershell-default-tools-can-select-powershell-instead-of-bash
  (with-test-directory (temporary)
    (multiple-value-bind (session)
        (cadr-cli::create-agent-session
         :cwd temporary
         :agent-directory (merge-pathnames "agent/" temporary)
         :model (cadr-cli/tests::goal12-sdk-model)
         :provider :faux
         :thinking-level :off
         :stream-function #'cadr-cli/tests::goal12-sdk-stream
         :session-manager
         (cadr-cli::session-manager-in-memory temporary)
         :tools '("read" "powershell" "edit" "write"))
      (is (equal '("edit" "powershell" "read" "write")
                 (sort
                  (mapcar
                   #'cadr-ai:tool-name
                   (cadr-agent::registry-tools
                    (cadr-agent::agent-tool-registry
                     (cadr-cli::agent-session-agent session))))
                  #'string<)))
      (let ((prompt
              (cadr-agent::agent-system-prompt
               (cadr-cli::agent-session-agent session))))
        (is (search "- powershell: Execute PowerShell commands" prompt))
        (is (null (search "- bash:" prompt))))
      (cadr-cli::agent-session-dispose session))))
