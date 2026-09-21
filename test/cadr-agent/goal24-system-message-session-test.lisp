(in-package #:cadr-agent/tests)
(in-suite cadr-agent-suite)

(defun goal24-empty-tool-schema ()
  (cadr-ai::json-object
   "type" "object"
   "properties" (cadr-ai::json-object)))

(defun goal24-plain-tool (&key (executor nil))
  (cadr-ai:make-tool
   :name "plain"
   :description "Plain tool"
   :parameters (goal24-empty-tool-schema)
   :executor executor))

(defun goal24-system-sections-equal-p (expected actual)
  (and (= (length expected) (length actual))
       (every
        (lambda (pair)
          (let ((found (assoc (car pair) actual :test #'string=)))
            (and found
                 (equal (cdr pair) (cdr found)))))
        expected)))

(test goal24-session-json-round-trips-system-message
  (let* ((executable
           (goal24-plain-tool
            :executor
            (lambda (&rest args)
              (declare (ignore args))
              (list :content nil :details nil))))
         (message
           (cadr-ai:make-system-message
            :content ""
            :sections
            '(("preamble" . "You are helpful.")
              ("skills" . nil)
              ("cwd" . "/project"))
            :tools-added (list executable)
            :tools-removed
            (list (cadr-ai:make-tool-reference :name "write"))
            :timestamp 1733234400000))
         (json (cadr-agent::message-to-json message))
         (declaration
           (let ((added (cadr-ai::json-get json "toolsAdded")))
             (and (vectorp added) (plusp (length added))
                  (aref added 0))))
         (loaded (cadr-agent::message-from-json json))
         (sections-json (cadr-ai::json-get json "sections")))
    (is (string= "system" (cadr-ai::json-get json "role")))
    (is (string= "" (cadr-ai::json-get json "content")))
    (is (= 1733234400000 (cadr-ai::json-get json "timestamp")))
    (is (hash-table-p sections-json))
    (is (string=
         "You are helpful."
         (cadr-ai::json-get sections-json "preamble")))
    (is (cadr-ai::json-null-p
         (cadr-ai::json-get sections-json "skills")))
    (is (string= "/project" (cadr-ai::json-get sections-json "cwd")))
    (is (hash-table-p declaration))
    (is (string= "plain" (cadr-ai::json-get declaration "name")))
    (is (string=
         "Plain tool"
         (cadr-ai::json-get declaration "description")))
    (multiple-value-bind (value present-p)
        (gethash "execute" declaration)
      (declare (ignore value))
      (is (not present-p)))
    (multiple-value-bind (value present-p)
        (gethash "constrainedSampling" declaration)
      (declare (ignore value))
      (is (not present-p)))
    (is (typep loaded 'cadr-ai:system-message))
    (is (string= "" (cadr-ai:system-message-content loaded)))
    (is (= 1733234400000
           (cadr-ai:system-message-timestamp loaded)))
    (is (goal24-system-sections-equal-p
         '(("preamble" . "You are helpful.")
           ("skills" . nil)
           ("cwd" . "/project"))
         (cadr-ai:system-message-sections loaded)))
    (is (= 1 (length (cadr-ai:system-message-tools-added loaded))))
    (is (cadr-ai:declarations-equal
         (goal24-plain-tool)
         (first (cadr-ai:system-message-tools-added loaded))))
    (is (null
         (cadr-ai:tool-executor
          (first (cadr-ai:system-message-tools-added loaded)))))
    (is (= 1 (length (cadr-ai:system-message-tools-removed loaded))))
    (is (string=
         "write"
         (cadr-ai:tool-reference-name
          (first (cadr-ai:system-message-tools-removed loaded)))))))

(test goal24-session-json-bag-path-restores-system-message
  (let* ((tool-json
           (cadr-ai::json-object
            "name" "plain"
            "description" "Plain tool"
            "parameters" (goal24-empty-tool-schema)))
         (sections
           (cadr-ai::json-object
            "preamble" "base"
            "gone" 'null))
         (bag
           (cadr-agent::make-session-json-message
            :role "system"
            :content ""
            :timestamp 42
            :extra
            (list :sections sections
                  :tools-added (vector tool-json)
                  :tools-removed
                  (vector
                   (cadr-ai::json-object "name" "old")))))
         (loaded (cadr-agent::message-from-json bag)))
    (is (typep loaded 'cadr-ai:system-message))
    (is (eq loaded (cadr-agent::message-from-json loaded)))
    (is (goal24-system-sections-equal-p
         '(("preamble" . "base") ("gone" . nil))
         (cadr-ai:system-message-sections loaded)))
    (is (cadr-ai:declarations-equal
         (goal24-plain-tool)
         (first (cadr-ai:system-message-tools-added loaded))))
    (is (string=
         "old"
         (cadr-ai:tool-reference-name
          (first (cadr-ai:system-message-tools-removed loaded)))))))

(test goal24-session-json-round-trip-keeps-replay-helpers
  (let* ((messages
           (list
            (cadr-ai:make-system-message
             :content "base"
             :sections '(("a" . "<a>1</a>") ("b" . "<b>1</b>"))
             :tools-added (list (goal24-plain-tool))
             :timestamp 10)
            (cadr-ai:make-user-message :content "hello" :timestamp 11)
            (cadr-ai:make-system-message
             :content ""
             :sections '(("a" . "<a>2</a>") ("b" . nil) ("c" . "<c>1</c>"))
             :tools-removed
             (list (cadr-ai:make-tool-reference :name "plain"))
             :tools-added
             (list
              (cadr-ai:make-tool
               :name "second"
               :description "second tool"
               :parameters (goal24-empty-tool-schema)))
             :timestamp 14)))
         (round-tripped
           (mapcar
            (lambda (message)
              (cadr-agent::message-from-json
               (cadr-agent::message-to-json message)))
            messages))
         (tools (cadr-ai:get-current-tools round-tripped))
         (prompt (cadr-ai:get-current-system-prompt round-tripped)))
    (is (= 1 (length tools)))
    (is (string= "second" (cadr-ai:tool-name (first tools))))
    (is (string=
         (format nil "base~%~%<a>2</a>~%~%<c>1</c>")
         prompt))))
