(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(test part-b-tool-set-matches-baseline-names
  (with-test-directory (directory)
    (is
     (equal
      '("read" "write" "edit" "bash" "find" "grep" "ls")
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
      (is (string= (format nil "A.txt~%dir/")
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
           (guard (sb-thread:make-mutex :name "part-b-order")))
      (write-text file "seed")
      (sb-posix:symlink (namestring file) (namestring alias))
      (let ((first
              (sb-thread:make-thread
               (lambda ()
                 (cadr-cli::with-file-mutation-queue
                  file
                  (lambda ()
                    (sb-thread:with-mutex (guard)
                      (push :first-start order))
                    (sleep 0.05)
                    (sb-thread:with-mutex (guard)
                      (push :first-end order)))))))
            (second
              (sb-thread:make-thread
               (lambda ()
                 (sleep 0.01)
                 (cadr-cli::with-file-mutation-queue
                  alias
                  (lambda ()
                    (sb-thread:with-mutex (guard)
                      (push :second order))))))))
        (sb-thread:join-thread first)
        (sb-thread:join-thread second))
      (is (equal '(:first-start :first-end :second)
                 (nreverse order))))))

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
          (cadr-cli::make-baseline-coding-tools directory)
          :allow '("read" "write" "bash")
          :exclude '("write")))))
      (is
       (equal
        '("extension-tool")
        (names
         (cadr-cli::select-coding-tools
          (append
           (cadr-cli::make-baseline-coding-tools directory)
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
          '("read" "write" "edit" "bash" "find" "grep" "ls"))))))))

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
