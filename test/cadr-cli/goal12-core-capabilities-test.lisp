(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defclass goal12-fake-tool-context (cadr-agent:execution-tool-context)
  ((files :initform (make-hash-table :test #'equal)
          :reader goal12-fake-tool-files)
   (commands :initform nil :accessor goal12-fake-tool-commands)))

(defmethod cadr-agent:execution-tool-resolve-path
    ((context goal12-fake-tool-context) path &optional base-directory)
  (declare (ignore context base-directory))
  (values (concatenate 'string "/virtual/" path) nil))

(defmethod cadr-agent:execution-tool-read-text
    ((context goal12-fake-tool-context) path)
  (let ((value (gethash path (goal12-fake-tool-files context))))
    (if value
        (values value nil)
        (values nil (cadr-agent:make-harness-operation-error
                     :code :enoent :message "ENOENT" :path path)))))

(defmethod cadr-agent:execution-tool-read-binary
    ((context goal12-fake-tool-context) path)
  (multiple-value-bind (text operation-error)
      (cadr-agent:execution-tool-read-text context path)
    (values (and text (cadr-ai::utf8-octets text)) operation-error)))

(defmethod cadr-agent:execution-tool-write
    ((context goal12-fake-tool-context) path content)
  (setf (gethash path (goal12-fake-tool-files context)) content)
  (values t nil))

(defmethod cadr-agent:execution-tool-exec
    ((context goal12-fake-tool-context) command
     &key cwd timeout signal on-stdout on-stderr)
  (declare (ignore cwd timeout signal on-stdout on-stderr))
  (push command (goal12-fake-tool-commands context))
  (values (cadr-agent:make-execution-result
           :stdout "context output" :stderr "" :exit-code 0)
          nil))

(test goal12-coding-core-auth-default-event-bus-and-timings-match-baseline
  (is (eq :medium cadr-cli:+default-thinking-level+))
  (is (search "Use /login" (cadr-cli:get-provider-login-help)))
  (is (search "Then use /model"
              (cadr-cli:format-no-model-selected-message)))
  (is (search "the selected model"
              (cadr-cli:format-no-api-key-found-message "unknown")))
  (let ((output (make-string-output-stream))
        (seen nil)
        (bus (cadr-cli:make-event-bus)))
    (setf (cadr-cli::event-bus-error-output bus) output)
    (let ((unsubscribe
            (cadr-cli:event-bus-on
             bus "channel"
             (lambda (value) (push value seen)))))
      (cadr-cli:event-bus-on bus "channel" (lambda (value)
                                               (declare (ignore value))
                                               (error "boom")))
      (cadr-cli:event-bus-emit bus "channel" 7)
      (is (equal '(7) seen))
      (is (search "Event handler error (channel): boom"
                  (get-output-stream-string output)))
      (funcall unsubscribe)
      (cadr-cli:event-bus-emit bus "channel" 8)
      (is (equal '(7) seen))
      (cadr-cli:event-bus-clear bus)))
  (let ((cadr-cli::*timing-enabled-p* t)
        (ticks '(100 106 115))
        (cadr-cli::*timing-namespaces* (make-hash-table :test #'eq))
        (output (make-string-output-stream)))
    (let ((cadr-cli::*timing-clock* (lambda () (pop ticks))))
      (cadr-cli:reset-timings)
      (cadr-cli:record-timing "config")
      (cadr-cli:record-timing "extensions")
      (cadr-cli:print-timings output))
    (is (string=
         (format nil
                 "~%--- Startup Timings: main ---~%  config: 6ms~%  extensions: 9ms~%  TOTAL: 15ms~%-----------------------------~%~%")
         (get-output-stream-string output)))))

(test goal12-coding-core-json-path-shell-and-watcher-match-baseline
  (is (string=
       (format nil "{~%  \"url\": \"https://x//y\", ~%  \"items\": [1,2]~%}~%")
       (cadr-cli:strip-json-comments
        (format nil "{~%  \"url\": \"https://x//y\", // comment~%  \"items\": [1,2,],~%}~%"))))
  (is (cadr-cli:local-path-p "file:///tmp/a"))
  (is (not (cadr-cli:local-path-p "https://example.invalid/a")))
  (is (string= "/tmp/a b"
               (cadr-cli:normalize-path-input
                "@/tmp/a b" :strip-at-prefix-p t
                :normalize-unicode-spaces-p t)))
  (is (string= "child/file"
               (cadr-cli:format-path-relative-to-cwd-or-absolute
                "/tmp/root/child/file" "/tmp/root/")))
  (let ((config (cadr-cli:get-shell-config)))
    (is (string= "/bin/bash" (cadr-cli:shell-config-shell config)))
    (is (equal '("-c") (cadr-cli:shell-config-arguments config))))
  (with-test-directory (bin)
    (let* ((environment (cadr-cli:get-shell-env :bin-directory bin))
           (path (cdr (find-if (lambda (pair)
                                 (string-equal "PATH" (car pair)))
                               environment))))
      (is (uiop:string-prefix-p
           (string-right-trim '(#\/ #\\) (namestring bin)) path))))
  (is (string= (format nil "ab~C~Cc" #\Tab #\Newline)
               (cadr-cli:sanitize-binary-output
                (format nil "a~Cb~C~Cc~C" (code-char 0) #\Tab #\Newline
                        (code-char #xfffa)))))
  (with-test-directory (root)
    (let* ((path (merge-pathnames "watch.txt" root))
           (events nil)
           (errors 0))
      (cadr-cli::write-utf8-file path "one")
      (let ((watcher
              (cadr-cli:watch-with-error-handler
               path (lambda (kind changed)
                      (push (list kind changed) events))
               (lambda () (incf errors))
               :poll-interval 60d0)))
        (unwind-protect
             (progn
               (cadr-cli::write-utf8-file path "different length")
               (is (cadr-cli::poll-file-watcher-once watcher))
               (is (= 1 (length events)))
               (is (zerop errors)))
          (cadr-cli:close-watcher watcher))))))

(test goal12-output-accumulator-preserves-split-utf8-and-bounds-tail
  (let* ((accumulator
           (cadr-cli:make-output-accumulator
            :max-lines 2 :max-bytes 12 :temp-file-prefix "goal12-output"))
         (octets (cadr-ai::utf8-octets (format nil "first~%中🙂~%last"))))
    (unwind-protect
         (progn
           (cadr-cli:output-accumulator-append accumulator (subseq octets 0 7))
           (cadr-cli:output-accumulator-append accumulator (subseq octets 7 9))
           (cadr-cli:output-accumulator-append accumulator (subseq octets 9))
           (cadr-cli:output-accumulator-finish accumulator)
           (let ((snapshot
                   (cadr-cli:output-accumulator-snapshot
                    accumulator :persist-if-truncated-p t)))
             (is (search "last" (cadr-cli:output-snapshot-content snapshot)))
             (is (getf (cadr-cli:output-snapshot-truncation snapshot)
                       :truncated))
             (is (= 3 (getf (cadr-cli:output-snapshot-truncation snapshot)
                             :total-lines)))
             (is (probe-file (cadr-cli:output-snapshot-full-output-path snapshot)))
             (cadr-cli:output-accumulator-close-temp-file accumulator)
             (is (equalp octets
                         (cadr-cli::read-binary-file
                          (cadr-cli:output-snapshot-full-output-path snapshot))))))
      (cadr-cli:output-accumulator-close-temp-file accumulator)
      (let ((path (cadr-cli::output-accumulator-temp-file-path accumulator)))
        (when (and path (probe-file path)) (delete-file path)))))
  (let ((accumulator
          (cadr-cli:make-output-accumulator :max-lines 10 :max-bytes 4)))
    (unwind-protect
         (progn
           (cadr-cli:output-accumulator-append
            accumulator
            (format nil "~A~%tail" (make-string 20 :initial-element #\x)))
           (cadr-cli:output-accumulator-finish accumulator)
           (is (string= "tail"
                        (cadr-cli:output-snapshot-content
                         (cadr-cli:output-accumulator-snapshot accumulator)))))
      (cadr-cli:output-accumulator-close-temp-file accumulator)
      (let ((path (cadr-cli::output-accumulator-temp-file-path accumulator)))
        (when (and path (probe-file path)) (delete-file path))))))

(test goal12-tool-manager-and-platform-cleanup-have-baseline-contract
  (is (string=
       "fd-v10.2.0-x86_64-unknown-linux-musl.tar.gz"
       (cadr-cli::tool-release-asset :fd "10.2.0" :linux :x64)))
  (is (string=
       "ripgrep-14.1.0-aarch64-unknown-linux-musl.tar.gz"
       (cadr-cli::tool-release-asset :rg "14.1.0" :linux :arm64)))
  (is (= 2 (length
            (cadr-cli::tool-extraction-commands
             "fd.zip" #P"/tmp/fd.zip" #P"/tmp/fd/" :windows))))
  (is (string= "powershell.exe"
               (first (second
                       (cadr-cli::tool-extraction-commands
                        "fd.zip" #P"/tmp/fd.zip" #P"/tmp/fd/"
                        :windows)))))
  (is (stringp (cadr-cli:get-tool-path :rg)))
  (let ((commands nil))
    (cadr-cli:track-detached-child-pid 12345)
    (cadr-cli:kill-tracked-detached-children
     :runner (lambda (argv)
               (push argv commands)
               (values nil nil 0)))
    (is (equal '(("/bin/kill" "-KILL" "--" "-12345")) commands)))
  (with-test-directory (root)
    (let* ((node-modules (merge-pathnames "node_modules/" root))
           (package (merge-pathnames "pkg/" node-modules))
           (native (merge-pathnames "native/addon.so" package)))
      (cadr-cli::write-utf8-file native "binary")
      (cadr-cli:quarantine-windows-native-dependencies
       package :loaded-paths (list native))
      (is (probe-file native))
      (is (string= "binary" (uiop:read-file-string native)))
      (is (probe-file
           (merge-pathnames cadr-cli::+windows-native-quarantine-directory+
                            node-modules)))
      (cadr-cli:cleanup-windows-self-update-quarantine package)
      (is (not (probe-file
                (merge-pathnames cadr-cli::+windows-native-quarantine-directory+
                                 node-modules)))))))

(test goal12-built-in-tools-consume-replaceable-execution-context
  (let ((context (make-instance 'goal12-fake-tool-context)))
    (setf (gethash "/virtual/read.txt" (goal12-fake-tool-files context))
          "alpha")
    (setf (gethash "/virtual/edit.txt" (goal12-fake-tool-files context))
          "old value")
    (multiple-value-bind (content details)
        (invoke-tool (cadr-cli:make-read-tool #P"/ignored/" :context context)
                     (args "path" "read.txt"))
      (declare (ignore details))
      (is (string= "alpha" (result-text content))))
    (invoke-tool (cadr-cli:make-write-tool #P"/ignored/" :context context)
                 (args "path" "write.txt" "content" "written"))
    (is (string= "written"
                 (gethash "/virtual/write.txt"
                          (goal12-fake-tool-files context))))
    (invoke-tool
     (cadr-cli:make-edit-tool #P"/ignored/" :context context)
     (args "path" "edit.txt"
           "edits" (vector (args "oldText" "old" "newText" "new"))))
    (is (string= "new value"
                 (gethash "/virtual/edit.txt"
                          (goal12-fake-tool-files context))))
    (multiple-value-bind (content details)
        (invoke-tool (cadr-cli:make-bash-tool #P"/ignored/" :context context)
                     (args "command" "echo ignored"))
      (is (string= "context output" (result-text content)))
      (is (= 0 (getf details :exit-code))))
    (is (equal '("echo ignored") (goal12-fake-tool-commands context)))))

(test tool-latest-version-uses-the-release-page-redirect
  ;; Baseline #8708: the anonymous Releases API is not the version source.
  (let ((seen nil))
    (flet ((runner (arguments &key output-file)
             (declare (ignore output-file))
             (push arguments seen)
             (values
              (format nil "HTTP/2 302~%location: ~A~%~%"
                      "https://github.com/sharkdp/fd/releases/tag/v10.4.2")
              "" 0)))
      (is (string= "10.4.2"
                   (cadr-cli::latest-tool-version :fd #'runner)))
      (is (find "https://github.com/sharkdp/fd/releases/latest"
                (first seen) :test #'string=))
      (is (null (search "api.github.com"
                        (format nil "~{~A~^ ~}" (first seen)))))))
  (flet ((runner (arguments &key output-file)
           (declare (ignore arguments output-file))
           (values
            (format nil "HTTP/1.1 302 Found~%Location: ~A~%~%"
                    "/BurntSushi/ripgrep/releases/tag/15.2.0")
            "" 0)))
    (is (string= "15.2.0"
                 (cadr-cli::latest-tool-version :rg #'runner))))
  (flet ((runner (arguments &key output-file)
           (declare (ignore arguments output-file))
           (values "HTTP/2 404~%content-type: text/plain~%~%" "" 0)))
    (let ((message
            (handler-case
                (progn
                  (cadr-cli::latest-tool-version :fd #'runner)
                  nil)
              (error (condition)
                (princ-to-string condition)))))
      (is (search
           "Failed to resolve latest sharkdp/fd release: HTTP 404 without redirect"
           message))))
  (flet ((runner (arguments &key output-file)
           (declare (ignore arguments output-file))
           (values
            (format nil "HTTP/2 302~%location: https://github.com/login~%~%")
            "" 0)))
    (let ((message
            (handler-case
                (progn
                  (cadr-cli::latest-tool-version :fd #'runner)
                  nil)
              (error (condition)
                (princ-to-string condition)))))
      (is (search
           "unexpected redirect to https://github.com/login"
           message)))))
