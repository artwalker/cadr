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

(test bash-wrapper-passes-paren-payload-as-argv-not-inner-minus-c
  ;; docs/bugs/bash-format-shell-quoting.md class 1: the shipped
  ;; wrapper puts the tool `command` in bash -lc "$2". Parens in that
  ;; argv string must not become a cadr-constructed `bash -c` syntax
  ;; error. The user FORMAT/(hit) failure was a model-written inner
  ;; script, not this path.
  (with-test-directory (directory)
    (let ((tool (make-bash-tool directory)))
      (multiple-value-bind (content details)
          (invoke-tool
           tool
           (args
            "command"
            "printf '%s\\n' '(format t \"gethash equal 6-char (hit): ~,1F ns/call~%\")'"))
        (is (eql 0 (getf details :exit-code)))
        (is (search
             "gethash equal 6-char (hit)"
             (result-text content)))
        (is (null
             (search
              "syntax error near unexpected token"
              (result-text content))))))))

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
          "/bin/bash -c 'trap \"\" TERM; exec /usr/bin/tail -f /dev/null' & child=$!; printf '%s' \"$child\" > child.pid; wait"
          "timeout" 1)))
      (let* ((pid
               (parse-integer
                (string-trim
                 '(#\Space #\Tab #\Newline #\Return)
                 (read-text
                  (merge-pathnames "child.pid" directory)))))
             (process-path
               (pathname (format nil "/proc/~D/stat" pid)))
             (stat
               (and (probe-file process-path)
                    (ignore-errors
                      (read-text process-path))))
             (close
               (and stat
                    (position #\) stat :from-end t)))
             (state
               (and close
                    (< (+ close 2) (length stat))
                    (char stat (+ close 2)))))
        ;; A container's PID 1 may retain an already-killed orphan as a
        ;; zombie.  That process cannot execute; /proc existence alone does
        ;; not mean the process group survived the timeout.
        (is (member state '(nil #\Z #\X #\x)))))))

(test bash-captures-active-post-exit-output-and-releases-idle-pipes
  (with-test-directory (directory)
    (let* ((tool (make-bash-tool directory))
           (ready (merge-pathnames "ready.fifo" directory))
           (release (merge-pathnames "release.fifo" directory))
           (content nil)
           (details nil)
           (worker-error nil))
      (sb-posix:mkfifo (namestring ready) #o600)
      (sb-posix:mkfifo (namestring release) #o600)
      (let ((worker
              (sb-thread:make-thread
               (lambda ()
                 (handler-case
                     (multiple-value-setq (content details)
                       (invoke-tool
                        tool
                        (args
                         "command"
                         "printf 'HEAD\\n'; (printf 'ready\\n' > ready.fifo; IFS= read -r token < release.fifo; printf 'TICK6\\n') &")))
                   (error (condition)
                     (setf worker-error condition)))))))
        (with-open-file (stream ready :direction :input)
          (is (string= "ready" (read-line stream))))
        (with-open-file (stream release
                                :direction :output
                                :if-exists :overwrite
                                :if-does-not-exist :error)
          (write-line "go" stream)
          (finish-output stream))
        (sb-thread:join-thread worker))
      (is (null worker-error))
      (when (null worker-error)
        (is (= 0 (getf details :exit-code)))
        (is (search "HEAD" (result-text content)))
        (is (search "TICK6" (result-text content))))
      (multiple-value-bind (content details)
          (invoke-tool
           tool
           (args
            "command"
            "printf 'DONE\\n'; (/usr/bin/tail -f /dev/null) & child=$!; printf '%s' \"$child\" > idle.pid"))
        (is (= 0 (getf details :exit-code)))
        (is (search "DONE" (result-text content))))
      (let ((pid
              (parse-integer
               (string-trim
                '(#\Space #\Tab #\Newline #\Return)
                (read-text
                 (merge-pathnames "idle.pid" directory))))))
        (is (not
             (probe-file
              (pathname (format nil "/proc/~D/" pid)))))))))

(test goal10-busy-bash-abort-kills-group-reports-error-and-settles-agent
  (with-test-directory (directory)
    (let* ((ready (merge-pathnames "abort-ready.fifo" directory))
           (pid-path (merge-pathnames "abort.pid" directory))
           (done (sb-thread:make-semaphore :count 0))
           (events nil)
           (stream-calls 0)
           (worker-error nil)
           (agent nil)
           (worker nil))
      (sb-posix:mkfifo (namestring ready) #o600)
      (labels
          ((assistant-message (content stop-reason)
             (cadr-ai:make-assistant-message
              :content content
              :api :openai-responses
              :provider :openai
              :model "faux"
              :stop-reason stop-reason))
           (stream
               (provider model context on-event
                &key max-tokens temperature abort-p)
             (declare
              (ignore provider model context max-tokens temperature))
             (incf stream-calls)
             (let ((message
                     (if (= stream-calls 1)
                         (assistant-message
                          (list
                           (cadr-ai:make-tool-call
                            :id "abort-bash-1"
                            :name "bash"
                            :arguments
                            (args
                             "command"
                             "printf '%s' $$ > abort.pid; printf 'ready\\n' > abort-ready.fifo; exec /usr/bin/tail -f /dev/null")))
                          :tool-use)
                         (assistant-message
                          nil
                          (if (and abort-p (funcall abort-p))
                              :aborted
                              :stop)))))
               (funcall
                on-event
                (cadr-ai:make-stream-event
                 :type :start :message message))
               message)))
        (setf
         agent
         (cadr-agent:make-agent
          :provider :openai
          :model
          (cadr-ai:make-model
           :id "faux" :provider :openai
           :api :openai-responses
           :base-url "https://example.invalid"
           :max-tokens 1024)
          :tools (list (make-bash-tool directory))
          :stream-function #'stream
          :on-event (lambda (event) (push event events)))
         worker
         (sb-thread:make-thread
          (lambda ()
            (unwind-protect
                 (handler-case
                     (cadr-agent:agent-prompt agent "run")
                   (error (condition)
                     (setf worker-error condition)))
              (sb-thread:signal-semaphore done)))
          :name "cadr-bash-abort-test"))
        (with-open-file (stream ready :direction :input)
          (is (string= "ready" (read-line stream))))
        (cadr-agent:agent-abort agent)
        (is (sb-thread:wait-on-semaphore done :timeout 5))
        (sb-thread:join-thread worker)
        (is (null worker-error))
        (is-false (cadr-agent:agent-busy-p agent))
        (let* ((results
                 (remove-if-not
                  (lambda (message)
                    (typep message
                           'cadr-ai:tool-result-message))
                  (cadr-agent:agent-messages agent)))
               (result (first results)))
          (is (= 1 (length results)))
          (is-true
           (cadr-ai:tool-result-message-is-error result))
          (is (string=
               "Command aborted"
               (cadr-ai:text-content-text
                (first
                 (cadr-ai:tool-result-message-content
                  result))))))
        (let* ((pid
                 (parse-integer
                  (string-trim
                   '(#\Space #\Tab #\Newline #\Return)
                   (read-text pid-path))))
               (stat-path
                 (pathname (format nil "/proc/~D/stat" pid)))
               (stat
                 (and (probe-file stat-path)
                      (ignore-errors (read-text stat-path))))
               (close
                 (and stat (position #\) stat :from-end t)))
               (state
                 (and close
                      (< (+ close 2) (length stat))
                      (char stat (+ close 2)))))
          (is (member state '(nil #\Z #\X #\x))))
        (is (= 1
               (count :agent-settled events
                      :key #'cadr-agent:agent-event-type)))))))
