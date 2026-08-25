(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(test part-b-tool-set-matches-baseline-names
  (with-test-directory (directory)
    (is
     (equal
      '("read" "bash" "edit" "write")
      (mapcar #'cadr-ai:tool-name
              (cadr-cli::make-baseline-coding-tools directory))))))

(test find-supports-basename-and-path-globs
  (with-test-directory (directory)
    (write-text (merge-pathnames "src/a.spec.ts" directory) "a")
    (write-text (merge-pathnames "src/nested/b.spec.ts" directory) "b")
    (write-text (merge-pathnames "src/nested/b.ts" directory) "c")
    (dolist (pattern '("*.spec.ts"
                       "src/**/*.spec.ts"
                       "**/nested/*.spec.ts"))
      (multiple-value-bind (content details)
          (invoke-tool
           (cadr-cli:make-find-tool directory)
           (args "pattern" pattern))
        (declare (ignore details))
        (is (search "src/nested/b.spec.ts"
                    (result-text content)))))
    (multiple-value-bind (content details)
        (invoke-tool
         (cadr-cli:make-find-tool directory)
         (args "pattern" "*.missing"))
      (declare (ignore details))
      (is (string= "No files found matching pattern"
                   (result-text content))))))

(test ls-is-stable-marks-directories-and-reports-limits
  (with-test-directory (directory)
    (write-text (merge-pathnames "z.txt" directory) "z")
    (write-text (merge-pathnames "A.txt" directory) "a")
    (ensure-directories-exist
     (merge-pathnames "dir/anchor" directory))
    (multiple-value-bind (content details)
        (invoke-tool
         (cadr-cli:make-ls-tool directory)
         (args "limit" 2))
      (is (string= (format nil
                           "A.txt~%dir/~%~%[2 entries limit reached. Use limit=4 for more]")
                   (result-text content)))
      (is (= 2 (getf details :entry-limit-reached))))
    (signals error
      (invoke-tool
       (cadr-cli:make-ls-tool directory)
       (args "path" "z.txt")))))

(test edit-prepares-legacy-and-stringified-input
  (with-test-directory (directory)
    (let* ((file (merge-pathnames "edit.txt" directory))
           (tool (cadr-cli:make-edit-tool directory))
           (schema (cadr-ai:tool-parameters tool))
           (properties (cadr-ai::json-get schema "properties")))
      (is (null (cadr-ai::json-get properties "oldText")))
      (write-text file "alpha beta")
      (invoke-tool
       tool
       (args "path" "edit.txt"
             "oldText" "alpha"
             "newText" "A"))
      (is (string= "A beta" (read-text file)))
      (invoke-tool
       tool
       (args
        "path" "edit.txt"
        "edits"
        "[{\"oldText\":\"beta\",\"newText\":\"B\"}]"))
      (is (string= "A B" (read-text file))))))

(test file-mutation-queue-serializes-realpath-aliases
  (with-test-directory (directory)
    (let* ((file (merge-pathnames "shared.txt" directory))
           (alias (merge-pathnames "alias.txt" directory))
           (order nil)
           (guard (sb-thread:make-mutex :name "part-b-order"))
           (first-entered
             (sb-thread:make-semaphore :count 0))
           (release-first
             (sb-thread:make-semaphore :count 0))
           (second-started
             (sb-thread:make-semaphore :count 0)))
      (write-text file "seed")
      (sb-posix:symlink (namestring file) (namestring alias))
      (is (eq (cadr-cli::file-mutation-lock file)
              (cadr-cli::file-mutation-lock alias)))
      (let ((first
              (sb-thread:make-thread
               (lambda ()
                 (cadr-cli::with-file-mutation-queue (file)
                    (sb-thread:with-mutex (guard)
                      (push :first-start order))
                    (sb-thread:signal-semaphore first-entered)
                    (sb-thread:wait-on-semaphore release-first)
                    (sb-thread:with-mutex (guard)
                      (push :first-end order)))))))
        (sb-thread:wait-on-semaphore first-entered)
        (let ((second
                (sb-thread:make-thread
                 (lambda ()
                   (sb-thread:signal-semaphore second-started)
                   (cadr-cli::with-file-mutation-queue (alias)
                      (sb-thread:with-mutex (guard)
                        (push :second order)))))))
          (sb-thread:wait-on-semaphore second-started)
          (sb-thread:signal-semaphore release-first)
          (sb-thread:join-thread first)
          (sb-thread:join-thread second)))
      (is (equal '(:first-start :first-end :second)
                 (nreverse order))))))

(test goal12-cli-file-mutation-and-truncation-are-shared-with-agent
  (with-test-directory (directory)
    (let ((file (merge-pathnames "shared.txt" directory)))
      (write-text file "seed")
      (is (eq (cadr-cli::file-mutation-lock file)
              (cadr-agent::file-mutation-queue-lock file)))))
  (dolist (text
           (list ""
                 "alpha"
                 (format nil "alpha~%beta~%")
                 (format nil "éé~%abc")
                 "aé🙂b"))
    (dolist (maximum '(0 1 3 4 5 100))
      (multiple-value-bind (cli-content cli-details)
          (cadr-cli::truncate-head
           text :max-lines 3 :max-bytes maximum)
        (let ((shared
                (cadr-agent::truncate-head
                 text :max-lines 3 :max-bytes maximum)))
          (is (string=
               cli-content
               (cadr-agent::truncation-result-content shared)))
          (is (eql
               (getf cli-details :truncated)
               (cadr-agent::truncation-result-truncated-p shared)))))
      (multiple-value-bind (cli-content cli-details)
          (cadr-cli::truncate-tail
           text :max-lines 3 :max-bytes maximum)
        (let ((shared
                (cadr-agent::truncate-tail
                 text :max-lines 3 :max-bytes maximum)))
          (is (string=
               cli-content
               (cadr-agent::truncation-result-content shared)))
          (is (eql
               (getf cli-details :truncated)
               (cadr-agent::truncation-result-truncated-p shared)))))))
  (multiple-value-bind (text truncated-p)
      (cadr-cli::truncate-tool-line "🙂🙂x" 4)
    (is (string= "🙂🙂... [truncated]" text))
    (is (not (null truncated-p)))))

(test cli-utf8-length-matches-encoder-without-full-reencode
  (dolist
      (text
       (list
        ""
        "ascii"
        (format nil "é🙂中文 mixed~%")
        (make-string 220 :initial-element #\x)))
    (is (= (length (cadr-ai::utf8-octets text))
           (cadr-cli::utf8-length text)))
    (is (= (cadr-agent::harness-utf8-length
            (if (simple-string-p text)
                text
                (coerce text 'simple-string)))
           (cadr-cli::utf8-length text)))))

(test path-utilities-match-baseline-edge-cases
  (with-test-directory (directory)
    (let* ((home (namestring (user-homedir-pathname)))
           (nfd-name
             (format nil "filee~C.txt" (code-char #x301)))
           (nfd-path (merge-pathnames nfd-name directory))
           (ampm-name
             (format nil "shot 10.00~Cam.png" (code-char #x202f)))
           (ampm-path (merge-pathnames ampm-name directory))
           (target (merge-pathnames "target.txt" directory))
           (alias (merge-pathnames "alias.txt" directory)))
      (is (string= home
                   (namestring
                    (cadr-cli::resolve-tool-path directory "~"))))
      (is (search "draft.md"
                  (namestring
                   (cadr-cli::resolve-tool-path
                    directory "@~draft.md"))))
      (write-text nfd-path "nfd")
      (is (equal (truename nfd-path)
                 (truename
                  (cadr-cli::resolve-readable-tool-path
                   directory
                   (format nil "file~C.txt" (code-char #xe9))))))
      (write-text ampm-path "image")
      (is (equal (truename ampm-path)
                 (truename
                  (cadr-cli::resolve-readable-tool-path
                   directory "shot 10.00 am.png"))))
      (write-text target "target")
      (sb-posix:symlink (namestring target) (namestring alias))
      (is (equal (truename target)
                 (cadr-cli::canonicalize-path alias)))
      (is (string= "..config/file"
                   (cadr-cli::cwd-relative-path
                    (merge-pathnames "..config/file" directory)
                    directory)))
      (is (null
           (cadr-cli::cwd-relative-path
            (merge-pathnames "../outside" directory)
            directory)))
      (is (cadr-cli::local-path-p "file:///tmp/file"))
      (is (not (cadr-cli::local-path-p "https://example.com/x")))
      (is (string=
           "/tmp/a b"
           (namestring
           (cadr-cli::resolve-general-path
             "file:///tmp/a%20b" directory)))))))

(test goal13-relative-read-expands-a-shortened-home-cwd-before-resolving
  (let* ((home
           (uiop:ensure-directory-pathname
            (user-homedir-pathname)))
         (expected
           (merge-pathnames
            "projects/sonechka/AGENTS.md" home))
         (resolved
           (cadr-cli::resolve-tool-path
            "~/projects/cadr/"
            "../sonechka/AGENTS.md"))
         (call
           (cadr-ai:make-tool-call
            :id "relative-resource"
            :name "read"
            :arguments
            (args "path" "../sonechka/AGENTS.md"))))
    (is (string=
         (namestring expected)
         (namestring resolved)))
    (handler-case
        (let ((classification
                (cadr-cli::tool-read-classification
                 call "~/projects/cadr/")))
          (is (eq :resource
                  (getf classification :kind)))
          (is (string=
               (namestring expected)
               (getf classification :label))))
      (condition (condition)
        (fail
         "read presentation leaked an implementation condition: ~A"
         condition)))))

(test goal13-file-tool-errors-never-leak-common-lisp-representations
  (with-test-directory (directory)
    (dolist
        (case
         (list
          (list (cadr-cli::make-read-tool directory)
                (args "path" "missing.txt")
                (format nil
                        "ENOENT: no such file or directory, access '~A'"
                        (namestring
                         (merge-pathnames "missing.txt" directory))))
          (list (cadr-cli::make-edit-tool directory)
                (args
                 "path" "missing.txt"
                 "edits"
                 (vector
                  (args "oldText" "a" "newText" "b")))
                "Could not edit file: missing.txt. Error code: ENOENT.")
          (list (cadr-cli::make-ls-tool directory)
                (args "path" "missing")
                (format nil "Path not found: ~A"
                        (namestring
                         (merge-pathnames "missing" directory))))
          (list (cadr-cli::make-find-tool directory)
                (args "pattern" "*" "path" "missing")
                (format nil
                        "[fd error]: Search path '~A' is not a directory.~%[fd error]: No valid search paths given."
                        (namestring
                         (merge-pathnames "missing" directory))))
          (list (cadr-cli::make-grep-tool directory)
                (args "pattern" "x" "path" "missing")
                (format nil "Path not found: ~A"
                        (namestring
                         (merge-pathnames "missing" directory))))
          (list (cadr-cli::make-glob-tool directory)
                (args "pattern" "*" "path" "missing")
                (format nil "Path not found: ~A"
                        (namestring
                         (merge-pathnames "missing" directory))))))
      (handler-case
          (progn
            (invoke-tool (first case) (second case))
            (fail "missing file/path should fail"))
        (condition (condition)
          (let ((message (princ-to-string condition)))
            (is (string= (third case) message))
            (is (not (search "#P\"" message)))
            (is (not (search "not a string designator" message)))
            (is (not (search "SIMPLE-ARRAY" message)))
            (is (not (search "SB-" message)))))))))

(test goal13-file-io-failures-use-stable-tool-level-copy
  (with-test-directory (directory)
    (dolist
        (case
         (list
          (list
           (cadr-cli::make-read-tool directory)
           (args "path" ".")
           "Could not read file: .")
          (list
           (cadr-cli::make-write-tool directory)
           (args "path" "." "content" "x")
           "Could not write file: .")
          (list
           (cadr-cli::make-edit-tool directory)
           (args
            "path" "."
            "edits"
            (vector
             (args "oldText" "a" "newText" "b")))
           "Could not edit file: .")))
      (handler-case
          (progn
            (invoke-tool (first case) (second case))
            (fail "directory-as-file should fail"))
        (condition (condition)
          (is (string= (third case)
                       (princ-to-string condition))))))))

(test edit-fuzzy-matching-preserves-line-endings-and-bom
  (with-test-directory (directory)
    (let* ((file (merge-pathnames "fuzzy.txt" directory))
           (tool (cadr-cli:make-edit-tool directory)))
      (write-text
       file
       (format nil
               "~Cfullwidth~C~C~C~C~%smart ~Cquote~C~%space~Cvalue~%"
               (code-char #xfeff)
               (code-char #xff08)
               (code-char #xff21)
               (code-char #xff11)
               (code-char #xff09)
               (code-char #x2018)
               (code-char #x2019)
               (code-char #xa0)))
      (invoke-tool
       tool
       (args
        "path" "fuzzy.txt"
        "edits"
        (vector
         (args "oldText" "fullwidth(A1)"
               "newText" "normalized")
         (args "oldText" "smart 'quote'"
               "newText" "smart quote")
         (args "oldText" "space value"
               "newText" "space-value"))))
      (let ((updated (read-text file)))
        (is (char= (code-char #xfeff) (char updated 0)))
        (is (search "normalized" updated))
        (is (search "smart quote" updated))
        (is (search "space-value" updated))))
    (let* ((file (merge-pathnames "crlf.txt" directory))
           (tool (cadr-cli:make-edit-tool directory)))
      (write-text file
                  (format nil "~Cfirst~C~%second~C~%third~C~%"
                          (code-char #xfeff)
                          #\Return #\Return #\Return))
      (invoke-tool
       tool
       (args
        "path" "crlf.txt"
        "edits"
        (vector
         (args "oldText" (format nil "second~%")
               "newText" (format nil "SECOND~%")))))
      (is
       (string=
        (format nil "~Cfirst~C~%SECOND~C~%third~C~%"
                (code-char #xfeff)
                #\Return #\Return #\Return)
        (read-text file))))))

(defun make-test-bmp ()
  ;; 1x1, 24-bit, uncompressed BMP with one red pixel.
  (let ((bytes
          (make-array 58
                      :element-type '(unsigned-byte 8)
                      :initial-element 0)))
    (labels ((u16 (offset value)
               (setf (aref bytes offset) (ldb (byte 8 0) value)
                     (aref bytes (1+ offset))
                     (ldb (byte 8 8) value)))
             (u32 (offset value)
               (dotimes (index 4)
                 (setf (aref bytes (+ offset index))
                       (ldb (byte 8 (* 8 index)) value)))))
      (setf (aref bytes 0) (char-code #\B)
            (aref bytes 1) (char-code #\M))
      (u32 2 58)
      (u32 10 54)
      (u32 14 40)
      (u32 18 1)
      (u32 22 1)
      (u16 26 1)
      (u16 28 24)
      (u32 34 4)
      (setf (aref bytes 54) 0
            (aref bytes 55) 0
            (aref bytes 56) 255))
    bytes))

(defun write-binary (path bytes)
  (ensure-directories-exist path)
  (with-open-file
      (stream path
              :direction :output
              :element-type '(unsigned-byte 8)
              :if-exists :supersede
              :if-does-not-exist :create)
    (write-sequence bytes stream)))

(test read-detects-image-magic-and-converts-bmp
  (with-test-directory (directory)
    (let ((bmp (merge-pathnames "pixel.txt" directory))
          (fake (merge-pathnames "fake.png" directory))
          (tool (cadr-cli:make-read-tool directory)))
      (write-binary bmp (make-test-bmp))
      (multiple-value-bind (content details)
          (invoke-tool tool (args "path" "pixel.txt"))
        (declare (ignore details))
        (is (= 2 (length content)))
        (is (typep (second content) 'cadr-ai:image-content))
        (is (string=
             "image/png"
             (cadr-ai:image-content-mime-type
              (second content)))))
      (write-text fake "plain text")
      (multiple-value-bind (content details)
          (invoke-tool tool (args "path" "fake.png"))
        (declare (ignore details))
        (is (= 1 (length content)))
        (is (string= "plain text" (result-text content)))))))

(test tool-selection-applies-allowlist-then-exclusions
  (with-test-directory (directory)
    (flet ((names (tools)
             (mapcar #'cadr-ai:tool-name tools)))
      (is
       (equal
        '("read" "bash")
        (names
         (cadr-cli::select-coding-tools
          (cadr-cli::make-all-coding-tools directory)
          :allow '("read" "write" "bash")
          :exclude '("write")))))
      (is
       (equal
        '("extension-tool")
        (names
         (cadr-cli::select-coding-tools
          (append
           (cadr-cli::make-all-coding-tools directory)
           (list
            (cadr-ai:make-tool
             :name "extension-tool"
             :description "extension"
             :parameters (cadr-ai::json-object)
             :executor (lambda (id arguments)
                         (declare (ignore id arguments))
                         nil))))
          :no-builtin-p t
          :builtin-names
          '("read" "write" "edit" "bash" "powershell" "find" "grep" "ls"))))))))

(test tool-selection-policy-applies-after-extension-reloads
  (let* ((base
           (cadr-ai:make-tool
            :name "read"
            :description "base"
            :parameters (cadr-ai::json-object)
            :executor
            (lambda (call-id arguments)
              (declare (ignore call-id arguments))
              nil)))
         (host
           (cadr-agent::make-extension-host))
         (bundle
           (cadr-agent::make-extension-bundle
            :id "extra"
            :path "extra.lisp"))
         (definition
           (cadr-agent::make-extension-tool-definition
            :name "extra"
            :description "extension"
            :parameters (cadr-ai::json-object)
            :execution-mode :parallel
            :handler
            (lambda (call-id arguments context)
              (declare
               (ignore call-id arguments context))
              nil)
            :bundle bundle))
         (agent
           (cadr-agent:make-agent
            :provider :mock
            :model
            (cadr-ai:make-model
             :id "mock"
             :provider :mock
             :api :openai-responses)
            :tools (list base)
            :extension-host host
            :tool-filter-function
            (lambda (tools)
              (cadr-cli::select-coding-tools
               tools
               :allow '("extra")
               :exclude nil)))))
    (setf
     (cadr-agent::extension-bundle-tools bundle)
     (list definition))
    (cadr-agent::replace-extension-bundles
     host (list bundle))
    (is (equal
         '("extra")
         (mapcar
          #'cadr-ai:tool-name
          (cadr-agent::registry-tools
           (cadr-agent::agent-tool-registry
            agent)))))))

(test experimental-tool-sampling-follows-the-env-flag
  ;; Mirrors experimental-tool-strict-mode.test.ts (v0.84.2): the four
  ;; built-in tools carry strict-prefer sampling only under the
  ;; experimental flag.
  (sb-posix:unsetenv "CADR_EXPERIMENTAL")
  (let ((plain (cadr-cli::make-read-tool "/tmp")))
    (is (null (cadr-ai:tool-constrained-sampling plain))))
  (sb-posix:setenv "CADR_EXPERIMENTAL" "1" 1)
  (unwind-protect
       (dolist (tool (list (cadr-cli::make-read-tool "/tmp")
                           (cadr-cli::make-bash-tool "/tmp")
                           (cadr-cli::make-edit-tool "/tmp")
                           (cadr-cli::make-write-tool "/tmp")))
         (is (equal '(:type :json-schema :strict :prefer)
                    (cadr-ai:tool-constrained-sampling tool))))
    (sb-posix:unsetenv "CADR_EXPERIMENTAL")))
