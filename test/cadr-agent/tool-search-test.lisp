(in-package #:cadr-agent/tests)
(in-suite cadr-agent-suite)

(defun tool-search-object (properties)
  (let ((schema (make-hash-table :test #'equal)))
    (setf (gethash "type" schema) "object"
          (gethash "properties" schema) properties)
    schema))

(defun tool-search-property (description)
  (let ((property (make-hash-table :test #'equal)))
    (setf (gethash "type" property) "string"
          (gethash "description" property) description)
    property))

(defun tool-search-document-for (name description &optional properties namespace)
  (cadr-agent:tool-search-document
   (list :name name
         :description description
         :parameters (tool-search-object (or properties
                                             (make-hash-table :test #'equal))))
   namespace))

(defun tool-search-rank-names (query documents &optional (limit 8))
  (mapcar #'cadr-agent:tool-search-match-name
          (cadr-agent:tool-search-rank query documents limit)))

(test tool-search-tokenizes-and-ranks-like-the-pin
  ;; pi@4a080252f extensions/tool-search/tool.ts tokenize and Bm25Ranker.
  (is (equal (cadr-agent:tool-search-tokenize
              "listIssues for the GitHub_repo")
             '("list" "issue" "git" "hub" "repo")))
  (is (equal (cadr-agent:tool-search-tokenize
              "searches queries HTTPServer")
             '("search" "query" "http" "server")))
  (let* ((state (make-hash-table :test #'equal))
         (documents
           (progn
             (setf (gethash "state" state)
                   (tool-search-property "open or closed"))
             (list
              (tool-search-document-for
               "mcp__github__list_issues"
               "List issues in a repository."
               state)
              (tool-search-document-for
               "mcp__github__create_pull_request"
               "Open a pull request.")
              (tool-search-document-for
               "mcp__linear__search_issues"
               "Search Linear issues by text.")
              (tool-search-document-for
               "mcp__docs__search"
               "Search the documentation.")))))
    (is (equal (tool-search-rank-names "issue" documents)
               '("mcp__linear__search_issues"
                 "mcp__github__list_issues")))
    (is (string= (first (tool-search-rank-names "pull requests" documents))
                 "mcp__github__create_pull_request"))
    (is (= 1 (length (tool-search-rank-names "search" documents 1))))
    (is (equal (tool-search-rank-names "closed" documents)
               '("mcp__github__list_issues")))
    (is (null (tool-search-rank-names "kubernetes" documents)))
    (is (null (tool-search-rank-names "the" documents)))
    (is (null (tool-search-rank-names "tickets" documents))))
  (let* ((document
           (tool-search-document-for
            "mcp__x__run"
            "Run it."
            nil
            (list :name "mcp__x"
                  :description "Kubernetes cluster tools")))
         (matches
           (cadr-agent:tool-search-rank "kubernetes" (list document) 8)))
    (is (= 1 (length matches)))
    (is (string= "mcp__x__run"
                 (cadr-agent:tool-search-match-name (first matches))))
    (is (plusp (cadr-agent:tool-search-match-score (first matches))))))

(test tool-search-loads-deferred-tools-for-the-next-call
  ;; pi@4a080252f searchAndLoad: deferred and codemode tools stay out of
  ;; the declaration until tool_search activates them.
  (let* ((schema (tool-search-object (make-hash-table :test #'equal)))
         (bundle
           (let ((definition
                   (cadr-agent::make-extension-bundle
                    :id "tool-search"
                    :path "/tmp/tool-search.lisp"
                    :scope :project
                    :rank 1
                    :order 0)))
             (cadr-agent::call-with-extension-registration
              definition
              (lambda ()
                (cadr-agent::register-extension-tool
                 "read_notes"
                 :description "Read notes."
                 :parameters schema
                 :handler (lambda (arguments)
                            (declare (ignore arguments))
                            nil))
                (cadr-agent::register-extension-tool
                 "mcp__github__list_issues"
                 :description "List issues in a repository."
                 :parameters schema
                 :exposure :deferred
                 :handler (lambda (arguments)
                            (declare (ignore arguments))
                            nil))
                (cadr-agent::register-extension-tool
                 "secret_admin"
                 :description "Hidden admin tool."
                 :parameters schema
                 :exposure :hidden
                 :handler (lambda (arguments)
                            (declare (ignore arguments))
                            nil))))
             definition))
         (host
           (let ((created
                   (cadr-agent::make-extension-host
                    :cwd #P"/tmp/"
                    :mode :repl)))
             (cadr-agent::replace-extension-bundles
              created (list bundle))
             created))
         (search-tool (cadr-agent:make-tool-search-tool))
         (agent
           (cadr-agent:make-agent
            :provider :openai
            :model (cadr-ai:make-model
                    :id "gpt"
                    :name "gpt"
                    :provider :openai
                    :api :openai-completions)
            :tools (list search-tool)
            :extension-host host))
         (names
           (lambda ()
             (mapcar #'cadr-ai:tool-name
                     (cadr-agent::registry-tools
                      (cadr-agent::agent-tool-registry agent))))))
    (is (member "read_notes" (funcall names) :test #'string=))
    (is (member "tool_search" (funcall names) :test #'string=))
    (is (not (member "mcp__github__list_issues"
                     (funcall names) :test #'string=)))
    (is (not (member "secret_admin" (funcall names) :test #'string=)))
    (let ((cadr-agent::*tool-search-agent* agent)
          (arguments (make-hash-table :test #'equal)))
      (setf (gethash "query" arguments) "   ")
      (is (search
           "query must not be empty"
           (handler-case
               (progn
                 (funcall (cadr-ai:tool-executor search-tool)
                          "call-1" arguments)
                 "")
             (error (condition) (princ-to-string condition)))))
      (setf (gethash "query" arguments) "issues"
            (gethash "limit" arguments) 1.5)
      (is (search
           "limit must be a positive integer"
           (handler-case
               (progn
                 (funcall (cadr-ai:tool-executor search-tool)
                          "call-2" arguments)
                 "")
             (error (condition) (princ-to-string condition)))))
      (setf (gethash "limit" arguments) 8.0)
      (multiple-value-bind (content details)
          (funcall (cadr-ai:tool-executor search-tool)
                   "call-3" arguments)
        (is (search "Loaded 1 tool."
                    (cadr-ai:text-content-text (first content))))
        (is (search "mcp__github__list_issues"
                    (cadr-ai:text-content-text (first content))))
        (is (equalp (gethash "loaded" details)
                    #("mcp__github__list_issues")))))
    (is (member "mcp__github__list_issues"
                (funcall names) :test #'string=))
    (is (member "read_notes" (funcall names) :test #'string=))
    (is (not (member "secret_admin" (funcall names) :test #'string=)))
    (let ((cadr-agent::*tool-search-agent* nil)
          (lone (cadr-agent:make-tool-search-tool))
          (arguments (make-hash-table :test #'equal)))
      (setf (gethash "query" arguments) "issues")
      (multiple-value-bind (content details)
          (funcall (cadr-ai:tool-executor lone) "call-4" arguments)
        (is (string= "No matching tools found."
                     (cadr-ai:text-content-text (first content))))
        (is (equalp (gethash "loaded" details) #()))))))
