(in-package #:cadr-cli/tests)

(in-suite cadr-cli-suite)

(defun goal12-example-manifest ()
  (let ((path
          (merge-pathnames
           "examples/manifest.sexp"
           (asdf:system-source-directory "cadr-cli"))))
    (with-open-file (stream path :direction :input)
      (read stream))))

(defun goal12-source-parity-example-paths ()
  (let* ((path
           (merge-pathnames
            "docs/source-parity.md"
            (asdf:system-source-directory "cadr-cli")))
         (prefix "| `packages/coding-agent/examples/")
         (paths nil))
    (with-open-file (stream path :direction :input
                                 :external-format :utf-8)
      (loop for line = (read-line stream nil nil)
            while line
            when (uiop:string-prefix-p prefix line)
              do
              (let ((end (position #\` line :start (length prefix))))
                (is (not (null end)))
                (push (subseq line 3 end) paths))))
    (sort paths #'string<)))

(defun goal12-read-project-file (relative)
  (uiop:read-file-string
   (merge-pathnames
    relative
    (asdf:system-source-directory "cadr-cli"))))

(defun goal12-count-substring (needle haystack)
  (loop with start = 0
        for position = (search needle haystack :start2 start)
        while position
        count 1
        do (setf start (+ position (length needle)))))

(test goal12-example-manifest-covers-every-baseline-source-exactly-once
  (let* ((manifest (goal12-example-manifest))
         (baseline-paths
           (sort (mapcar (lambda (row) (getf row :baseline)) manifest)
                 #'string<))
         (ledger-paths (goal12-source-parity-example-paths)))
    (is (= 99 (length manifest)))
    (is (= 17 (count :ported manifest :key
                     (lambda (row) (getf row :status)))))
    (is (= 82 (count :gap manifest :key
                     (lambda (row) (getf row :status)))))
    (is (= 99 (length (remove-duplicates baseline-paths :test #'string=))))
    (is (equal ledger-paths baseline-paths))
    (dolist (row manifest)
      (is (member (getf row :status) '(:ported :gap)))
      (ecase (getf row :status)
        (:ported
         (let ((target (getf row :lisp)))
           (is (stringp target))
           (is (probe-file
                (merge-pathnames
                 target
                 (asdf:system-source-directory "cadr-cli"))))))
        (:gap
         (is (consp (getf row :gaps))))))))

(test goal12-every-example-gap-is-defined-by-the-blocked-proposal
  (let* ((proposal
           (goal12-read-project-file
            "docs/proposals/goal-v12-example-api-gaps.md"))
         (amendment
           (goal12-read-project-file
            "docs/proposals/goal-v12-api-scope-amendment-2.md"))
         (mapping-start (search (format nil "~%## 4.") proposal))
         (mapping-end (and mapping-start
                           (search (format nil "~%## 5.")
                                   proposal :start2 mapping-start)))
         (mapping (and mapping-end
                       (subseq proposal mapping-start mapping-end)))
         (mapping-table-end
           (and mapping
                (search (format nil "~%~%机械校验") mapping)))
         (mapping-table
           (and mapping-table-end
                (subseq mapping 0 mapping-table-end)))
         (gap-ids nil))
    (dolist (row (goal12-example-manifest))
      (dolist (gap (getf row :gaps))
        (pushnew gap gap-ids)))
    (is (= 42 (length gap-ids)))
    (is (stringp mapping))
    (is (= 42 (goal12-count-substring "`:" mapping-table)))
    (dolist (gap gap-ids)
      (let ((token (format nil "`:~(~A~)`" gap)))
        (is (search token proposal))
        (is (= 1 (goal12-count-substring token mapping)))))
    (is (search "当前按硬约束再次 blocked" proposal))
    (is (search "状态：**blocked，等待用户逐项裁决。**"
                amendment))))

(test goal12-ported-extension-entrypoints-load-without-diagnostics
  (let ((root (asdf:system-source-directory "cadr-cli")))
    (dolist (row (goal12-example-manifest))
      (when (and (eq :ported (getf row :status))
                 (getf row :entry-p))
        (with-test-directory (temporary)
          (let* ((output (make-string-output-stream))
                 (target
                   (merge-pathnames (getf row :lisp) root))
                 (manager
                   (make-test-extension-manager
                    temporary
                    (merge-pathnames "global/" temporary)
                    output
                    (list target)))
                 (report
                   (cadr-cli::reload-cli-extensions manager)))
            (is (null (getf report :errors)))
            (is (plusp (getf report :loaded)))
            (is (string= "" (get-output-stream-string output)))))))))

(defparameter *goal12-example-registrations*
  '(("packages/coding-agent/examples/extensions/bookmark.ts"
     :commands ("bookmark" "unbookmark"))
    ("packages/coding-agent/examples/extensions/claude-rules.ts"
     :hooks (:session-start :before-agent-start))
    ("packages/coding-agent/examples/extensions/dynamic-resources/index.ts"
     :hooks (:resources-discover))
    ("packages/coding-agent/examples/extensions/input-transform-streaming.ts"
     :hooks (:input))
    ("packages/coding-agent/examples/extensions/input-transform.ts"
     :hooks (:input))
    ("packages/coding-agent/examples/extensions/mac-system-theme.ts"
     :hooks (:session-start :session-shutdown))
    ("packages/coding-agent/examples/extensions/model-status.ts"
     :hooks (:model-select))
    ("packages/coding-agent/examples/extensions/notify.ts"
     :hooks (:agent-end))
    ("packages/coding-agent/examples/extensions/pirate.ts"
     :commands ("pirate") :hooks (:before-agent-start))
    ("packages/coding-agent/examples/extensions/provider-payload.ts"
     :hooks (:before-provider-request :after-provider-response))
    ("packages/coding-agent/examples/extensions/send-user-message.ts"
     :commands ("ask" "steer" "followup" "askwith"))
    ("packages/coding-agent/examples/extensions/session-name.ts"
     :commands ("session-name"))
    ("packages/coding-agent/examples/extensions/titlebar-spinner.ts"
     :hooks (:agent-start :agent-end :session-shutdown))))

(test goal12-ported-extension-registrations-cover-the-baseline-surface
  (let ((root (asdf:system-source-directory "cadr-cli")))
    (dolist (expected *goal12-example-registrations*)
      (let* ((row
               (find (first expected) (goal12-example-manifest)
                     :key (lambda (candidate) (getf candidate :baseline))
                     :test #'string=))
             (output (make-string-output-stream)))
        (with-test-directory (temporary)
          (let* ((manager
                   (make-test-extension-manager
                    temporary (merge-pathnames "global/" temporary)
                    output
                    (list (merge-pathnames (getf row :lisp) root))))
                 (report (cadr-cli::reload-cli-extensions manager))
                 (snapshot
                   (cadr-agent::extension-host-snapshot
                    (cadr-cli::cli-extension-manager-host manager))))
            (is (null (getf report :errors)))
            (dolist (command (getf (rest expected) :commands))
              (is
               (find command
                     (cadr-agent::extension-snapshot-commands snapshot)
                     :key #'cadr-agent::extension-command-definition-name
                     :test #'string=)))
            (dolist (hook (getf (rest expected) :hooks))
              (is (gethash hook
                           (cadr-agent::extension-snapshot-hooks snapshot))))))))))

(defun goal12-load-pure-example (relative)
  (load
   (merge-pathnames relative
                    (asdf:system-source-directory "cadr-cli"))))

(test goal12-pure-example-ports-preserve-edge-case-behavior
  (goal12-load-pure-example "examples/extensions/doom-overlay/doom-keys.lisp")
  (goal12-load-pure-example "examples/extensions/doom-overlay/wad-finder.lisp")
  (goal12-load-pure-example "examples/extensions/plan-mode/utils.lisp")
  (goal12-load-pure-example "examples/extensions/subagent/agents.lisp")
  (let ((map-key (symbol-function 'map-key-to-doom)))
    (is (equal '(173) (funcall map-key (format nil "~C[A" #\Escape))))
    (is (equal '(173 182) (funcall map-key "W")))
    (is (equal '(163) (funcall map-key "F")))
    (is (equal '(121) (funcall map-key "Y")))
    (is (equal '(49) (funcall map-key "1")))
    (is (null (funcall map-key (string (code-char 3))))))
  (is (string=
       "https://distro.ibiblio.org/slitaz/sources/packages/d/doom1.wad"
       (symbol-value '+doom-wad-url+)))
  (is (= (+ #x80 #x58) (symbol-value '+doom-key-f12+)))
  (is (funcall (symbol-function 'plan-mode-safe-command-p)
               "git status"))
  (is (not (funcall (symbol-function 'plan-mode-safe-command-p)
                    "git reset --hard")))
  (let* ((extract
           (symbol-function 'plan-mode-extract-todo-items))
         (items
           (funcall extract
                    (format nil
                            "Plan:~%1. **Use the `read` tool**~%2) Verify tests pass~%3. /skip this"))))
    (is (= 2 (length items)))
    (is (string= "Read tool"
                 (funcall (symbol-function 'plan-mode-todo-item-text)
                          (first items))))
    (is (= 2
           (funcall (symbol-function 'plan-mode-mark-completed-steps)
                    "[DONE:2] [DONE:99]" items)))
    (is
     (funcall (symbol-function 'plan-mode-todo-item-completed-p)
              (second items))))
  (with-test-directory (directory)
    (let ((wad (merge-pathnames "custom.wad" directory)))
      (write-text wad "IWADpayload")
      (is (string=
           (namestring (truename wad))
           (funcall (symbol-function 'find-wad-file) (namestring wad))))))
  (with-test-directory (directory)
    (let* ((wad (merge-pathnames "downloaded.wad" directory))
           (payload
             (make-array 5 :element-type '(unsigned-byte 8)
                           :initial-contents '(0 1 2 3 255)))
           (original-download
             (symbol-function 'doom-download-wad-octets)))
      (unwind-protect
          (progv (list '+doom-bundled-wad-path+) (list wad)
            (setf (symbol-function 'doom-download-wad-octets)
                  (lambda () payload))
            (is (string= (namestring wad)
                         (funcall (symbol-function 'ensure-wad-file))))
            (with-open-file
                (stream wad :direction :input
                            :element-type '(unsigned-byte 8))
              (let ((actual
                      (make-array (file-length stream)
                                  :element-type '(unsigned-byte 8))))
                (read-sequence actual stream)
                (is (equalp payload actual)))))
        (setf (symbol-function 'doom-download-wad-octets)
              original-download))))
  (with-test-directory (directory)
    (let* ((agents-directory (merge-pathnames ".cadr/agents/" directory))
           (nested (merge-pathnames "src/deep/" directory)))
      (ensure-directories-exist (merge-pathnames "anchor" nested))
      (write-text
       (merge-pathnames "reviewer.md" agents-directory)
       (format nil
               "---~%name: 'reviewer'~%description: \"Review changes\"~%tools: read, grep~%model: test-model~%---~%Be strict.~%"))
      (let* ((result
               (funcall (symbol-function 'discover-subagents)
                        nested :project))
             (agent (first (getf result :agents))))
        (is (= 1 (length (getf result :agents))))
        (is (string= "reviewer" (getf agent :name)))
        (is (equal '("read" "grep") (getf agent :tools)))
        (is (string= (format nil "Be strict.~%")
                     (getf agent :system-prompt)))))))
