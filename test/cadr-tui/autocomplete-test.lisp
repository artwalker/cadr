(in-package #:cadr-tui/tests)

(in-suite cadr-tui-suite)

(defun with-autocomplete-tree (function)
  (let* ((root
           (merge-pathnames
            (format nil "cadr-autocomplete-~36R/"
                    (random (expt 36 8)))
            (uiop:temporary-directory)))
         (nested
           (merge-pathnames "packages/tui/src/"
                            root)))
    (unwind-protect
         (progn
           (ensure-directories-exist nested)
           (ensure-directories-exist
            (merge-pathnames "my folder/" root))
           (ensure-directories-exist
            (merge-pathnames ".pi/" root))
           (dolist (entry
                    '(("README.md" . "readme")
                      ("update.sh" . "update")
                      ("packages/tui/src/autocomplete.ts"
                       . "source")
                      ("my folder/test.txt" . "space")
                      (".pi/config.json" . "{}")))
             (with-open-file
                 (stream
                  (merge-pathnames (car entry) root)
                  :direction :output
                  :if-exists :supersede
                  :if-does-not-exist :create)
               (write-string (cdr entry) stream)))
           (funcall function root))
      (uiop:delete-directory-tree
       root :validate t :if-does-not-exist :ignore))))

(test autocomplete-slash-and-path-prefix-semantics
  (with-autocomplete-tree
   (lambda (root)
     (let* ((provider
              (cadr-tui:make-autocomplete-provider
               :base-path root
               :commands
               (list
                (cadr-tui:make-autocomplete-command
                 :name "model"
                 :description "Choose model")
                (cadr-tui:make-autocomplete-command
                 :name "messages"
                 :description "Show messages"))))
            (slash
              (cadr-tui:autocomplete-get-suggestions
               provider '("/mo") 0 3))
            (path
              (cadr-tui:autocomplete-get-suggestions
               provider '("./up") 0 4 :force-p t))
            (quoted
              (cadr-tui:autocomplete-get-suggestions
               provider '("\"my") 0 3 :force-p t)))
       (is (string= "/mo"
                    (cadr-tui:autocomplete-suggestions-prefix
                     slash)))
       (is (equal '("model")
                  (mapcar
                   #'cadr-tui:autocomplete-item-value
                   (cadr-tui:autocomplete-suggestions-items
                    slash))))
       (is (member
            "./update.sh"
            (mapcar
             #'cadr-tui:autocomplete-item-value
             (cadr-tui:autocomplete-suggestions-items
              path))
            :test #'string=))
       (is (member
            "\"my folder/\""
            (mapcar
             #'cadr-tui:autocomplete-item-value
             (cadr-tui:autocomplete-suggestions-items
              quoted))
            :test #'string=))
       (let* ((item
                (find
                 "\"my folder/\""
                 (cadr-tui:autocomplete-suggestions-items
                  quoted)
                 :key
                 #'cadr-tui:autocomplete-item-value
                 :test #'string=)))
         (multiple-value-bind (lines line column)
             (cadr-tui:autocomplete-apply
              '("\"my\"") 0 3 item "\"my")
           (is (equal '("\"my folder/\"") lines))
           (is (= 0 line))
           (is (= 11 column))))))))

(test autocomplete-at-search-is-recursive-hidden-and-stably-ranked
  (with-autocomplete-tree
   (lambda (root)
     (let ((fd (merge-pathnames "fake-fd.sh" root)))
       (with-open-file
           (stream fd
                   :direction :output
                   :if-exists :supersede
                   :if-does-not-exist :create)
         (write-line "#!/bin/sh" stream)
         (dolist (path
                   '("README.md"
                     "update.sh"
                     "packages/"
                     "packages/tui/"
                     "packages/tui/src/"
                     "packages/tui/src/autocomplete.ts"
                     "my folder/"
                     "my folder/test.txt"
                     ".pi/"
                     ".pi/config.json"
                     ".git/"
                     ".git/config"))
           (format stream "printf '%s\\n' '~A'~%" path)))
       (uiop:run-program
        (list "chmod" "+x" (namestring fd)))
       (let* ((provider
                (cadr-tui:make-autocomplete-provider
                 :base-path root :fd-path fd))
              (nested
                (cadr-tui:autocomplete-get-suggestions
                 provider '("@auto") 0 5))
              (hidden
                (cadr-tui:autocomplete-get-suggestions
                 provider '("@.pi") 0 4))
              (spaced
                (cadr-tui:autocomplete-get-suggestions
                 provider '("@my") 0 3)))
         (is (member
              "@packages/tui/src/autocomplete.ts"
              (mapcar
               #'cadr-tui:autocomplete-item-value
               (cadr-tui:autocomplete-suggestions-items
                nested))
              :test #'string=))
         (is (member
              "@.pi/"
              (mapcar
               #'cadr-tui:autocomplete-item-value
               (cadr-tui:autocomplete-suggestions-items
                hidden))
              :test #'string=))
         (is (member
              "@\"my folder/\""
              (mapcar
               #'cadr-tui:autocomplete-item-value
               (cadr-tui:autocomplete-suggestions-items
                spaced))
              :test #'string=))
         (is (notany
              (lambda (item)
                (search "@.git"
                        (cadr-tui:autocomplete-item-value
                         item)))
              (cadr-tui:autocomplete-suggestions-items
               hidden))))))))

(test autocomplete-quoted-completion-does-not-duplicate-closing-quote
  (with-autocomplete-tree
   (lambda (root)
     (let* ((provider
              (cadr-tui:make-autocomplete-provider
               :base-path root))
            (line "\"my folder/te\"")
            (cursor (1- (length line)))
            (suggestions
              (cadr-tui:autocomplete-get-suggestions
               provider (list line) 0 cursor
               :force-p t))
            (item
              (find
               "\"my folder/test.txt\""
               (cadr-tui:autocomplete-suggestions-items
                suggestions)
               :key
               #'cadr-tui:autocomplete-item-value
               :test #'string=)))
       (is (not (null item)))
       (multiple-value-bind (lines row column)
           (cadr-tui:autocomplete-apply
            (list line) 0 cursor item
            (cadr-tui:autocomplete-suggestions-prefix
             suggestions))
         (is (equal
              '("\"my folder/test.txt\"")
              lines))
         (is (= 0 row))
         (is (= (length "\"my folder/test.txt\"")
                column)))))))

(test autocomplete-provider-callbacks-preserve-the-full-baseline-contract
  (let* ((signal
           (cadr-tui:make-autocomplete-request-signal))
         (suggestion-calls nil)
         (trigger-calls nil)
         (apply-calls nil)
         (item
           (cadr-tui:make-autocomplete-item
            :value "issue:42"
            :label "#42"))
         (provider
           (cadr-tui:make-autocomplete-provider
            :base-path #P"/tmp/cadr-autocomplete-contract/"
            :trigger-characters '(#\#)
            :suggestions-function
            (lambda (lines row column options)
              (push (list lines row column options)
                    suggestion-calls)
              (cadr-tui:make-autocomplete-suggestions
               :items (list item)
               :prefix "#4"))
            :apply-completion-function
            (lambda (lines row column actual-item prefix)
              (push (list lines row column actual-item prefix)
                    apply-calls)
              (values '("issue:42 ") 0 9))
            :should-trigger-file-completion-function
            (lambda (lines row column)
              (push (list lines row column) trigger-calls)
              t))))
    (let ((suggestions
            (cadr-tui:autocomplete-provider-get-suggestions
             provider '("#4") 0 2
             :signal signal :force-p t)))
      (is (eq item
              (first
               (cadr-tui:autocomplete-suggestions-items
                suggestions))))
      (destructuring-bind (lines row column options)
          (first suggestion-calls)
        (is (equal '("#4") lines))
        (is (= 0 row))
        (is (= 2 column))
        (is (eq signal (getf options :signal)))
        (is (getf options :force-p))
        (is (equal #P"/tmp/cadr-autocomplete-contract/"
                   (getf options :cwd)))))
    (is
     (cadr-tui:autocomplete-provider-should-trigger-file-completion-p
      provider '("#4") 0 2))
    (is (equal '(("#4") 0 2) (first trigger-calls)))
    (multiple-value-bind (lines row column)
        (cadr-tui:autocomplete-provider-apply-completion
         provider '("#4") 0 2 item "#4")
      (is (equal '("issue:42 ") lines))
      (is (= 0 row))
      (is (= 9 column)))
    (is (equal '("#4") (first (first apply-calls))))
    (is (equal '(#\#)
               (cadr-tui:autocomplete-provider-trigger-characters
                provider)))
    (is (not
         (cadr-tui:autocomplete-request-aborted-p signal)))
    (cadr-tui:autocomplete-request-abort signal)
    (is (cadr-tui:autocomplete-request-aborted-p signal))))

(test autocomplete-provider-without-callbacks-delegates-byte-for-byte
  (let* ((command
           (cadr-tui:make-autocomplete-command
            :name "model"
            :description "Choose model"))
         (provider
           (cadr-tui:make-autocomplete-provider
            :commands (list command)))
         (legacy
           (cadr-tui:autocomplete-get-suggestions
            provider '("/mo") 0 3))
         (dispatched
           (cadr-tui:autocomplete-provider-get-suggestions
            provider '("/mo") 0 3)))
    (is (equal
         (mapcar #'cadr-tui:autocomplete-item-value
                 (cadr-tui:autocomplete-suggestions-items legacy))
         (mapcar #'cadr-tui:autocomplete-item-value
                 (cadr-tui:autocomplete-suggestions-items dispatched))))
    (is (string=
         (cadr-tui:autocomplete-suggestions-prefix legacy)
         (cadr-tui:autocomplete-suggestions-prefix dispatched)))
    (is
     (cadr-tui:autocomplete-provider-should-trigger-file-completion-p
      provider '("plain") 0 5))))

(test autocomplete-dead-when-gone
  (let ((source
          (uiop:read-file-string
           (asdf:system-relative-pathname
            "cadr-tui" "src/cadr-tui/autocomplete.lisp"))))
    (is (null
         (search
          "(zerop
                (length
                 (autocomplete-provider-commands"
          source)))))
