(defpackage #:cadr-chord/tests
  (:use #:cl #:fiveam #:cadr-chord))

(in-package #:cadr-chord/tests)

(in-suite cadr-core/tests::cadr-core-suite)

(defun chord-caught (thunk)
  (handler-case (funcall thunk)
    (chord-error (condition) condition)
    (error (condition) condition)))

(defun chat-contract ()
  (remote-contract
   "t.chat"
   :version 1
   :input (schema-object (list (list "session" (schema-string))
                               (list "conversation" (schema-number :default 0))))
   :host (host-family "session:" "session")
   :variants (variant-table
              "viewer" (member-alist "view" (schema-object (list (list "text" (schema-string)))))
              nil
              "participant"
              (member-alist "view" (schema-object (list (list "text" (schema-string)))))
              (member-alist "send" (make-method-spec
                                    :args (schema-object (list (list "text" (schema-string))))
                                    :result (schema-object (list (list "id" (schema-number)))))))))

(test chord-contract-fingerprint-matches-v140
  (is (string= "e8ee3f28594f8426" (contract-fingerprint (chat-contract)))))

(test chord-normalizes-input-and-omits-defaults
  (let* ((contract (chat-contract))
         (normalized (schema-normalize (contract-input contract)
                                       (json-object "session" "s" "extra" 1)
                                       "input")))
    (is (string= "{\"conversation\":0,\"session\":\"s\"}" (canonical-json normalized)))
    (is (string= "{\"session\":\"s\"}" (canonical-identity (contract-input contract) normalized)))
    (let ((condition (chord-caught
                      (lambda ()
                        (schema-normalize (contract-input contract)
                                          (json-object "session" 1)
                                          "input")))))
      (is (chord-error-p condition "invalid"))
      (is (string= "input" (chord-error-reason condition))))))

(test chord-rejects-reserved-and-remote-opaque-members
  (is (typep (chord-caught
              (lambda ()
                (local-contract "t.x" :version 1 :input (schema-object nil)
                                :members (member-alist "status" (make-method-spec)))))
             'error))
  (is (typep (chord-caught
              (lambda ()
                (remote-contract "t.x" :version 1 :input (schema-object nil)
                                 :host (host-named "server")
                                 :variants (variant-table "a"
                                                          (member-alist "h" (make-opaque-spec :id "x@1"))
                                                          nil))))
             'error)))

(test chord-coverage-locks-arguments-and-state
  (let* ((chat (chat-contract))
         (none (local-contract "t.methods" :version 1 :input (schema-object nil)
                               :members (member-alist "m" (make-method-spec)))))
    (is (null (contract-coverage (contract-description none) (contract-description none))))
    (let ((with-args (local-contract "t.methods" :version 1 :input (schema-object nil)
                                     :members (member-alist "m" (make-method-spec :args (schema-string))))))
      (is (search "arguments" (contract-coverage (contract-description with-args)
                                                 (contract-description none)))))
    (let ((retyped (remote-contract
                    "t.chat" :version 1
                    :input (contract-input chat)
                    :host (host-family "session:" "session")
                    :variants (variant-table
                               "viewer" (member-alist "view" (schema-object (list (list "text" (schema-number)))))
                               nil
                               "participant" (member-alist "view" (schema-object (list (list "text" (schema-string)))))
                               (member-alist "send" (make-method-spec
                                                    :args (schema-object (list (list "text" (schema-string))))
                                                    :result (schema-object (list (list "id" (schema-number))))))))))
      (is (search "state" (contract-coverage (contract-description retyped)
                                             (contract-description chat)))))))

(test chord-bind-requires-an-adapter-across-versions
  (let* ((chat (chat-contract))
         (same (remote-contract "t.chat" :version 1
                                :input (contract-input chat)
                                :host (host-family "session:" "session")
                                :variants (json-get (contract-def chat) "variants"))))
    (is (string= (contract-fingerprint chat) (contract-fingerprint same)))
    (is (null (contract-bind same nil chat))))
  (let* ((chat (chat-contract))
         (v2 (remote-contract "t.chat" :version 2
                              :input (contract-input chat)
                              :host (host-family "session:" "session")
                              :variants (variant-table "viewer"
                                                       (member-alist "body" (schema-object (list (list "text" (schema-string)))))
                                                       nil)))
         (missing (chord-caught (lambda () (contract-bind v2 nil chat))))
         (adapter (lambda (current) current))
         (accepts (make-hash-table)))
    (is (chord-error-p missing "contract_mismatch"))
    (setf (gethash 1 accepts) adapter)
    (is (eq adapter (contract-bind v2 accepts chat)))))

(test chord-copy-json-rejects-cycles-and-absent-array-elements
  (let ((object (json-object "a" 1)))
    (json-put object "self" object)
    (is (typep (chord-caught (lambda () (copy-json object))) 'error)))
  (let ((copied (copy-json (json-object "keep" 1 "skip" +json-absent+) :omit-undefined-properties t)))
    (is (string= "{\"keep\":1}" (canonical-json copied))))
  (is (typep (chord-caught
              (lambda ()
                (copy-json (json-array 1 +json-absent+) :omit-undefined-properties t)))
             'error)))

(test chord-schema-fits-is-contravariant-for-functions
  (is (schema-fits (schema-function (list (schema-unknown)) (json-object "type" "void"))
                   (schema-function (list (schema-string)) (json-object "type" "void"))))
  (is (not (schema-fits (schema-function (list (schema-string)) (json-object "type" "void"))
                        (schema-function (list (schema-unknown)) (json-object "type" "void"))))))

(test chord-delta-codec-omits-and-interns-paths
  (let ((encoder (make-encoder)))
    (is (equal (encoder-encode encoder (list (list "s" (list "counter") 1)
                                             (list "s" (list "counter") 2)))
               (list (list "s" (list "counter") 1) (list "s" 2))))
    (is (equal (encoder-encode encoder (list (list "s" (list "other") 3)
                                             (list "s" (list "counter") 4)))
               (list (list "s" (list "other") 3)
                     (list "#" 0 (list "counter"))
                     (list "s" 0 4)))))
  (let* ((decoder (make-decoder))
         (ops (decoder-decode decoder (list (list "s" (list "counter") 1) (list "s" 2)))))
    (is (equal ops (list (list "s" (list "counter") 1) (list "s" (list "counter") 2))))))

(test chord-delta-apply-overlap-and-rejects-unsafe-paths
  (let ((root (json-object "text" "abcdefgh")))
    (apply-ops root (list (list "a" (list "text") "ij")))
    (is (string= "abcdefghij" (json-get root "text"))))
  (let ((ops (diff-revisions "abcdefgh" (concatenate 'string (subseq "abcdefgh" 3) "xyz")
                             (list "text"))))
    (is (equal ops (list (list "t" (list "text") 3) (list "a" (list "text") "xyz")))))
  (is (typep (chord-caught (lambda () (assert-valid-op (list "s" (list "__proto__") 1))))
             'unsafe-path-error))
  (let* ((stable (json-object "kept" t))
         (root (json-object "stable" stable "n" 0))
         (next (apply-immutable root (list (list "s" (list "n") 1)))))
    (is (eq stable (json-get next "stable")))
    (is (= 0 (json-get root "n")))
    (is (= 1 (json-get next "n")))))

(test chord-tracker-generations-match-v140
  (let* ((tracker (track (json-object "n" 0)))
         (change (tracker-begin-change tracker)))
    (draft-set (change-state change) "n" 1)
    (let ((prepared (change-prepare change)))
      (is (eq (preparation-value prepared) (change-state change)))
      (tracker-adopt tracker prepared)
      (is (= 1 (json-get (tracker-value tracker) "n")))))
  (let* ((tracker (track (json-object "n" 0)))
         (replacement (json-object "n" 2))
         (same (tracker-prepare-replace tracker (json-object "n" 0)))
         (changed (tracker-prepare-replace tracker replacement)))
    (is (eq (preparation-value same) (tracker-value tracker)))
    (is (null (preparation-ops same)))
    (is (eq (preparation-value changed) replacement))
    (is (equal (preparation-ops changed) (list (list "r" replacement)))))
  (let* ((tracker (track (json-object)))
         (other (track (json-object)))
         (prepared (tracker-prepare-replace tracker (json-object "a" 1))))
    (is (search "different tracker"
                (princ-to-string (chord-caught (lambda () (tracker-adopt other prepared))))))
    (tracker-adopt tracker prepared)
    (is (search "already been used"
                (princ-to-string (chord-caught (lambda () (tracker-adopt tracker prepared)))))))
  (let* ((tracker (track (json-object "n" 0)))
         (stale (tracker-prepare-replace tracker (json-object "n" 1))))
    (tracker-adopt tracker (tracker-prepare-replace tracker (json-object "n" 2)))
    (is (search "stale" (princ-to-string (chord-caught (lambda () (tracker-adopt tracker stale)))))))
  (let ((change (tracker-begin-change (track (json-object)))))
    (change-prepare change)
    (is (search "Change has already been settled"
                (princ-to-string (chord-caught (lambda () (change-prepare change)))))))
  (let* ((tracker (track (json-object "n" 0)))
         (aborted (tracker-begin-change tracker))
         (live (tracker-begin-change tracker)))
    (draft-set (change-state aborted) "n" 1)
    (change-abort aborted)
    (draft-set (change-state live) "n" 1)
    (let* ((ready (change-prepare live))
           (settled (princ-to-string
                     (chord-caught (lambda () (change-prepare aborted)))))
           (again (chord-caught (lambda () (change-abort aborted))))
           (rejected (princ-to-string
                      (chord-caught
                       (lambda ()
                         (change-abort live)
                         (tracker-adopt tracker ready)))))
           (second (chord-caught (lambda () (change-abort live)))))
      (is (and (search "Change has already been settled" settled)
               (null again)
               (search "Prepared change has been aborted" rejected)
               (null second)
               (= 0 (json-get (tracker-value tracker) "n")))
          "v1.4.0 settled=~S again=~S rejected=~S second=~S value=~S"
          settled again rejected second
          (json-get (tracker-value tracker) "n")))))

(defun counter-contract ()
  (local-contract "t.counter"
                  :version 1
                  :input (schema-object (list (list "name" (schema-string))))
                  :members (member-alist
                            "count" (schema-object (list (list "n" (schema-number))))
                            "add" (make-method-spec :args (schema-integer) :result (schema-integer)))))

(defun note (log text)
  (setf (cdr log) (append (cdr log) (list text))))

(defun serve-counter (host log &key linger)
  (host-serve host (counter-contract)
              (lambda (input principal self)
                (declare (ignore principal))
                (let ((name (json-get input "name"))
                      (count (self-state self "count"
                                         (schema-object (list (list "n" (schema-number))))
                                         (json-object "n" 0))))
                  (self-resource self "r"
                                 :open (lambda () (note log (format nil "open ~A" name)))
                                 :close (lambda () (note log (format nil "close ~A" name))))
                  (note log (format nil "factory ~A" name))
                  (list (cons "add" (lambda (delta)
                                      (cell-change count
                                                   (lambda (draft)
                                                     (setf (gethash "n" draft)
                                                           (+ (or (gethash "n" draft) 0) delta))))
                                      (json-get (cell-value count) "n"))))))
              :linger linger))

(test chord-host-activates-queues-and-disposes
  (let ((host (create-host))
        (log (list nil)))
    (serve-counter host log)
    (let ((ref (host-hold host (counter-contract) (json-object "name" "a"))))
      (is (string= "loading" (ref-status ref)))
      (is (chord-error-p (chord-caught (lambda () (ref-member ref "count"))) "not_ready"))
      (let ((pending (ref-call ref "add" 2)))
        (is (= 2 (chord-await pending))))
      (is (string= "live" (ref-status ref)))
      (is (string= "{\"n\":2}" (canonical-json (cell-value (ref-member ref "count")))))
      (ref-release ref)
      (is (string= "released" (ref-status ref)))
      (is (chord-error-p (chord-caught (lambda () (chord-await (ref-call ref "add" 1)))) "released"))
      (is (equal (cdr log) (list "factory a" "open a" "close a"))))))

(test chord-host-coalesces-holds-and-lingers
  (let ((host (create-host))
        (log (list nil)))
    (serve-counter host log)
    (let ((left (host-hold host (counter-contract) (json-object "name" "x")))
          (right (host-hold host (counter-contract) (json-object "name" "x"))))
      (chord-flush)
      (is (equal (cdr log) (list "factory x" "open x")))
      (ref-release left)
      (is (= 1 (chord-await (ref-call right "add" 1))))
      (ref-release right)
      (is (equal (cdr log) (list "factory x" "open x" "close x")))))
  (let ((host (create-host))
        (log (list nil)))
    (serve-counter host log :linger 0.03)
    (let ((first (host-hold host (counter-contract) (json-object "name" "l"))))
      (chord-await (ref-call first "add" 5))
      (ref-release first)
      (let ((second (host-hold host (counter-contract) (json-object "name" "l"))))
        (chord-flush)
        (is (string= "{\"n\":5}" (canonical-json (cell-value (ref-member second "count")))))
        (ref-release second)
        (sleep 0.06)
        (chord-flush)
        (is (equal (cdr log) (list "factory l" "open l" "close l")))))))

(defun greeter-contract ()
  (local-contract "t.greeter"
                  :version 1
                  :input (schema-object (list (list "id" (schema-string) :optional t)))
                  :members (member-alist "count" (schema-unknown)
                                         "greet" (make-method-spec :args (schema-string)
                                                                   :result (schema-string)))))

(defun greeter-facet (greeting &key schema initial version migrate bump extra)
  (make-facet
   :name "greeter"
   :setup (lambda (host)
            (host-serve host (greeter-contract)
                        (lambda (input principal self)
                          (declare (ignore principal))
                          (when extra (funcall extra self input))
                          (let ((count (self-state self "count"
                                                   (or schema (schema-object (list (list "n" (schema-number)))))
                                                   (or initial (json-object "n" 0))
                                                   :version (or version 1)
                                                   :migrate migrate)))
                            (list (cons "greet"
                                        (lambda (name)
                                          (cell-change count
                                                       (lambda (draft)
                                                         (if bump
                                                             (funcall bump draft)
                                                             (setf (gethash "n" draft)
                                                                   (+ (or (gethash "n" draft) 0) 1)))))
                                          (format nil "~A ~A" greeting name))))))))))

(test chord-reload-pins-old-roots-and-preserves-state
  (let ((host (create-host)))
    (host-install host (greeter-facet "hello"))
    (let ((ref (host-hold host (greeter-contract) (json-object))))
      (is (string= "hello a" (chord-await (ref-call ref "greet" "a"))))
      (let ((root (host-open-root host))
            (shapes nil))
        (is (string= "hello p" (chord-await (ref-call ref "greet" "p" root))))
        (ref-on-shape ref (lambda (shape) (setf shapes (append shapes (list (json-get shape "contract"))))))
        (let ((report (host-reload host (list (greeter-facet "hi")))))
          (is (null (reload-report-gated report)))
          (is (= 1 (length (reload-report-prepared report))))
          (is (string= "hi b" (chord-await (ref-call ref "greet" "b"))))
          (is (= 1 (length shapes)))
          (is (eql (host-previous-code-version host) (reload-report-previous report)))
          (is (string= "hello p" (chord-await (ref-call ref "greet" "p" root))))
          (host-finish-root host root)
          (is (null (host-previous-code-version host)))
          (is (string= "{\"n\":4}" (canonical-json (cell-value (ref-member ref "count"))))))))))

(test chord-reload-is-read-only-and-abort-restores-code
  (let ((host (create-host))
        (log (list nil)))
    (host-install host (greeter-facet "hello"))
    (let ((first (host-hold host (greeter-contract) (json-object "id" "a"))))
      (host-hold host (greeter-contract) (json-object "id" "b"))
      (chord-flush)
      (let ((writing (greeter-facet "hi" :extra
                                    (lambda (self input)
                                      (declare (ignore input))
                                      (let ((probe (self-state self "probe" (schema-object nil) (json-object))))
                                        (cell-replace probe (json-object)))))))
        (is (search "read_only" (princ-to-string (chord-caught (lambda () (host-reload host (list writing))))))))
      (let ((version (host-code-version host))
            (failing (greeter-facet "hi" :extra
                                    (lambda (self input)
                                      (self-resource self "extra"
                                                     :open (lambda ()
                                                             (note log (format nil "open ~A" (json-get input "id"))))
                                                     :close (lambda ()
                                                              (note log (format nil "close ~A" (json-get input "id")))))
                                      (when (string= (json-get input "id") "b")
                                        (error "b fails"))))))
        (let ((condition (chord-caught (lambda () (host-reload host (list failing))))))
          (is (chord-error-p condition "unavailable"))
          (is (search "reload aborted" (chord-error-message condition)))
          (is (search "b fails" (chord-error-message condition))))
        (is (= version (host-code-version host)))
        (is (equal (cdr log) (list "open a" "close a")))
        (is (string= "hello x" (chord-await (ref-call first "greet" "x"))))))))

(test chord-reload-refuses-a-schema-change-without-a-version-bump
  (let ((host (create-host)))
    (host-install host (greeter-facet "hello"))
    (chord-flush)
    (host-hold host (greeter-contract) (json-object))
    (chord-flush)
    (let ((condition (chord-caught
                      (lambda ()
                        (host-reload host (list (greeter-facet "hi"
                                                               :schema (schema-object (list (list "total" (schema-number))))
                                                               :initial (json-object "total" 0))))))))
      (is (chord-error-p condition "invalid"))
      (is (string= "state" (chord-error-reason condition)))
      (is (search "without a version bump" (chord-error-message condition))))))

(test chord-reload-version-bump-conflicts-with-old-roots
  (let ((host (create-host))
        (froms nil)
        (events nil))
    (host-install host (greeter-facet "hello"))
    (let ((ref (host-hold host (greeter-contract) (json-object))))
      (chord-await (ref-call ref "greet" "a"))
      (chord-await (ref-call ref "greet" "a"))
      (cell-on-event (ref-member ref "count") (lambda (event) (setf events (append events (list event)))))
      (let ((root (host-open-root host))
            (report (host-reload host (list (greeter-facet
                                             "hi"
                                             :schema (schema-object (list (list "total" (schema-number))))
                                             :initial (json-object "total" 0)
                                             :version 2
                                             :migrate (lambda (old from)
                                                        (setf froms (append froms (list from)))
                                                        (json-object "total" (json-get old "n")))
                                             :bump (lambda (draft)
                                                     (setf (gethash "total" draft)
                                                           (+ (or (gethash "total" draft) 0) 1))))))))
        (is (= 1 (length (reload-report-gated report))))
        (is (equal froms (list 1)))
        (is (string= "reset" (json-get (car (last events)) "type")))
        (is (string= "{\"total\":2}" (canonical-json (json-get (car (last events)) "value"))))
        (is (string= "hi b" (chord-await (ref-call ref "greet" "b"))))
        (is (string= "{\"total\":3}" (canonical-json (cell-value (ref-member ref "count")))))
        (let ((condition (chord-caught (lambda () (chord-await (ref-call ref "greet" "late" root))))))
          (is (chord-error-p condition "upgrade_conflict"))
          (is (chord-error-retryable-p condition)))))))

(test chord-protocol-version-4-drops-old-peers
  (let ((server (create-host :name "server"))
        (seen nil)
        (frames nil)
        (closed nil))
    (serve-counter server nil)
    (multiple-value-bind (down raw) (memory-link-pair)
      (host-accept server down :principal (json-object "guest" "g")
                   :on-protocol-mismatch (lambda (versions) (setf seen (append seen (list versions)))))
      (link-receive raw (lambda (frame) (setf frames (append frames (list frame)))))
      (link-on-close raw (lambda (reason) (setf closed reason)))
      (link-send raw (json-object "t" "hello" "name" "old" "kind" "client" "codeVersion" 0))
      (link-send raw (json-object "t" "hold" "id" 1 "name" "t.counter" "input" (json-object "name" "c")))
      (is (= 4 (json-get (first seen) "local")))
      (is (= 1 (json-get (first seen) "peer")))
      (is (string= "protocol-version 4" closed))
      (is (link-closed-p down))
      (is (not (some (lambda (frame) (equal (json-get frame "t") "shape")) frames)))))
  (let ((seen nil))
    (multiple-value-bind (down up) (memory-link-pair)
      (let ((browser (create-host :name "browser" :kind "client")))
        (host-connect browser up :principal (json-object "kind" "server")
                      :on-protocol-mismatch (lambda (versions) (setf seen (append seen (list versions)))))
        (link-send down (json-object "t" "hello" "protocol" 5 "name" "server" "kind" "host" "codeVersion" 1))
        (is (= 5 (json-get (first seen) "peer")))
        (is (link-closed-p up)))))
  (let ((seen nil))
    (multiple-value-bind (down up) (memory-link-pair)
      (host-accept (create-host :name "server") down
                   :on-protocol-mismatch (lambda (versions) (setf seen (append seen (list versions)))))
      (host-connect (create-host :name "browser" :kind "client") up
                    :on-protocol-mismatch (lambda (versions) (setf seen (append seen (list versions)))))
      (link-close up "bye")
      (is (null seen)))))

(test chord-sqlite-migrations-pragmas-and-durable-binding
  (let ((database (open-node-sqlite-database ":memory:")))
    (apply-sqlite-migrations database
                             (list (list :version 1 :statements (list "CREATE TABLE notes (body TEXT)"
                                                                      "INSERT INTO notes VALUES ('kept')")))
                             :table "notes_schema")
    (apply-sqlite-migrations database
                             (list (list :version 1 :statements (list "CREATE TABLE notes (body TEXT)"
                                                                      "INSERT INTO notes VALUES ('kept')"))
                                   (list :version 2 :statements (list "ALTER TABLE notes ADD COLUMN title TEXT")))
                             :table "notes_schema")
    (is (json-null-p (json-get (first (sqlite-all database "SELECT body, title FROM notes")) "title")))
    (is (= 2 (json-get (sqlite-get database "SELECT version FROM notes_schema") "version")))
    (is (search "newer than supported"
                (princ-to-string
                 (chord-caught
                  (lambda ()
                    (apply-sqlite-migrations database
                                             (list (list :version 1 :statements nil))
                                             :table "notes_schema"))))))
    (dolist (versions (list (list 0) (list 2) (list 1 3) (list 1 1)))
      (is (search "contiguous versions starting at 1"
                  (princ-to-string
                   (chord-caught
                    (lambda ()
                      (apply-sqlite-migrations
                       database
                       (mapcar (lambda (version) (list :version version :statements nil)) versions)
                       :table "fresh_schema")))))))
    (dolist (prefix (list "" "1bad" "bad-prefix" "sqlite_app" "SQLITE_app"))
      (is (typep (chord-caught (lambda () (validate-sqlite-schema-prefix prefix))) 'error)))
    (dolist (prefix (list "pi_" "_private" "app2"))
      (is (string= prefix (validate-sqlite-schema-prefix prefix))))
    (sqlite-close database))
  (let ((database (open-node-sqlite-database ":memory:")))
    (is (search "contiguous versions starting at 1"
                (princ-to-string
                 (chord-caught
                  (lambda ()
                    (apply-sqlite-migrations database
                                             (list (list :version 2 :statements (list "CREATE TABLE nope (id INT)")))
                                             :table "app_schema"))))))
    (is (null (sqlite-all database "SELECT name FROM sqlite_schema")))
    (is (typep (chord-caught
                (lambda ()
                  (apply-sqlite-migrations
                   database
                   (list (list :version 1
                               :statements (list "CREATE TABLE migration_first (value TEXT) STRICT"
                                                 "INSERT INTO migration_first (value) VALUES ('retained')"))
                         (list :version 2
                               :statements (list "CREATE TABLE migration_second (value TEXT) STRICT"
                                                 "THIS IS NOT SQL")))
                   :table "app_schema")))
               'error))
    (is (= 0 (json-get (sqlite-get database "SELECT count(*) AS count FROM sqlite_schema WHERE name IN ('app_schema', 'migration_first', 'migration_second')")
                       "count")))
    (sqlite-close database))
  (let ((database (open-node-sqlite-database ":memory:")))
    (is (= 5000 (json-get (sqlite-get database "PRAGMA busy_timeout") "timeout")))
    (is (= 1000 (json-get (sqlite-get database "PRAGMA wal_autocheckpoint") "wal_autocheckpoint")))
    (is (= 1 (json-get (sqlite-get database "PRAGMA synchronous") "synchronous")))
    (sqlite-transaction database
                        (lambda (transaction)
                          (sqlite-handle-exec transaction "CREATE TABLE async_probe (value INTEGER)")
                          (sqlite-handle-run transaction "INSERT INTO async_probe (value) VALUES (?)" 1)))
    (is (= 1 (json-get (sqlite-get database "SELECT value FROM async_probe") "value")))
    (sqlite-close database)
    (sqlite-close database))
  (let* ((steps nil)
         (storage (make-durable-storage
                   :exec (lambda (sql &rest bindings)
                           (declare (ignore sql bindings))
                           (make-durable-cursor
                            :next (lambda ()
                                    (setf steps (append steps (list :next)))
                                    (json-object "value" (json-object "body" "one")))
                            :to-array (lambda ()
                                        (setf steps (append steps (list :array)))
                                        (list (json-object "body" "one")))))))
         (database (make-durable-object-sqlite-database storage)))
    (is (string= "one" (json-get (sqlite-get-durable database "SELECT body FROM notes") "body")))
    (sqlite-all-durable database "SELECT body FROM notes")
    (is (equal steps (list :next :array)))
    (is (search "without losing precision"
                (princ-to-string
                 (chord-caught
                  (lambda ()
                    (sqlite-get-durable database "SELECT ?" (+ +max-safe-integer+ 1)))))))))

(test chord-process-lock-admits-one-holder
  (let ((release (process-lock "chord-test-lock")))
    (let ((condition (chord-caught (lambda () (process-lock "chord-test-lock")))))
      (is (chord-error-p condition "unavailable"))
      (is (string= "locked" (chord-error-reason condition)))
      (is (search "lock chord-test-lock is held" (chord-error-message condition))))
    (funcall release))
  (let ((release (process-lock "chord-test-lock")))
    (funcall release)))

(test chord-child-host-echoes-and-stops
  (let* ((manager (create-host-manager
                   :driver (fork-driver :init (json-object "greeting" "hi")
                                        :env (list (cons "HOST_NAME" "w1")))))
         (instance (manager-start manager))
         (server (create-host :name "server")))
    (host-accept server (instance-link instance) :principal (json-object "worker" "w1") :name "w1")
    (let ((echo (host-hold server (echo-contract) (json-object))))
      (is (string= (format nil "hi x from ~A" (instance-pid instance))
                   (chord-await (ref-call echo "echo" "x")))))
    (manager-stop manager)
    (is (string= "stopped" (manager-status manager)))
    (is (eql 0 (json-get (instance-exited instance) "code")))))
