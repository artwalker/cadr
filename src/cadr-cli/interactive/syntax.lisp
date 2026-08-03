(in-package #:cadr-cli)

(defparameter +syntax-highlight-languages+
  '("bash" "c" "clojure" "cmake" "cpp" "csharp"
    "css" "diff" "dockerfile" "elixir" "erlang"
    "fish" "go" "graphql" "haskell" "hcl" "html"
    "java" "javascript" "json" "kotlin" "less"
    "lisp" "lua" "makefile" "markdown" "ocaml"
    "perl" "php" "powershell" "protobuf" "python"
    "r" "ruby" "rust" "sass" "scala" "scss" "sql"
    "swift" "toml" "typescript" "vim" "xml" "yaml"))

(defun supports-syntax-language-p (language)
  (not
   (null
    (member
     (string-downcase language)
     +syntax-highlight-languages+
     :test #'string=))))

(defun decode-highlight-entity (entity)
  (cond
    ((string= entity "lt") "<")
    ((string= entity "gt") ">")
    ((string= entity "quot") "\"")
    ((string= entity "apos") "'")
    ((string= entity "amp") "&")
    ((and
      (> (length entity) 1)
      (char= (char entity 0) #\#)
      (every #'digit-char-p
             (subseq entity 1)))
     (let ((character
             (code-char
              (parse-integer entity
                             :start 1))))
       (and character
            (string character))))
    (t nil)))

(defun decode-highlight-text (text)
  (with-output-to-string (output)
    (loop with index = 0
          while (< index (length text))
          do
          (if (char= (char text index) #\&)
              (let ((semicolon
                      (position #\; text
                                :start (1+ index))))
                (if semicolon
                    (let ((decoded
                            (decode-highlight-entity
                             (subseq text
                                     (1+ index)
                                     semicolon))))
                      (if decoded
                          (progn
                            (write-string decoded output)
                            (setf index
                                  (1+ semicolon)))
                          (progn
                            (write-char #\& output)
                            (incf index))))
                    (progn
                      (write-char #\& output)
                      (incf index))))
              (progn
                (write-char (char text index)
                            output)
                (incf index))))))

(defun highlight-class-name (tag)
  (let ((marker (search "class=\"" tag)))
    (when marker
      (let* ((start (+ marker 7))
             (end (position #\" tag
                            :start start))
             (value
               (and end
                    (subseq tag start end))))
        (and
         value
         (find-if
          (lambda (name)
            (uiop:string-prefix-p
             "hljs-" name))
          (uiop:split-string
           value :separator '(#\Space))))))))

(defun render-highlighted-html
    (html &optional theme)
  (let ((formatters nil)
        (segments nil)
        (index 0))
    (labels
        ((emit (text)
           (when (plusp (length text))
             (let* ((decoded
                      (decode-highlight-text text))
                    (formatter
                      (find-if #'identity
                               formatters)))
               (push
                (if formatter
                    (funcall formatter decoded)
                    decoded)
                segments)))))
      (loop while (< index (length html))
            for open = (position #\< html
                                 :start index)
            do
            (if (null open)
                (progn
                  (emit (subseq html index))
                  (setf index (length html)))
                (progn
                  (emit (subseq html index open))
                  (let ((close
                          (position #\> html
                                    :start open)))
                    (if (null close)
                        (progn
                          (emit (subseq html open))
                          (setf index
                                (length html)))
                        (let ((tag
                                (subseq html
                                        (1+ open)
                                        close)))
                          (cond
                            ((uiop:string-prefix-p
                              "/span" tag)
                             (pop formatters))
                            ((uiop:string-prefix-p
                              "span" tag)
                             (let* ((class
                                      (highlight-class-name
                                       tag))
                                    (scope
                                      (and class
                                           (subseq class 5)))
                                    (formatter
                                      (and scope
                                           (cdr
                                            (assoc
                                             scope theme
                                             :test
                                             #'string=)))))
                               (push
                                (or formatter
                                    (first formatters))
                                formatters))))
                          (setf index (1+ close))))))))
      (apply #'concatenate 'string
             (nreverse segments)))))

(defparameter +simple-syntax-keywords+
  '("as" "async" "await" "break" "case"
    "catch" "class" "const" "continue"
    "def" "default" "do" "else" "enum"
    "export" "extends" "false" "finally"
    "for" "from" "function" "if" "import"
    "in" "interface" "let" "match" "new"
    "nil" "null" "package" "pass" "private"
    "protected" "public" "raise" "return"
    "static" "struct" "super" "switch" "this"
    "throw" "trait" "true" "try" "type"
    "typeof" "undefined" "var" "void" "while"
    "with" "yield"))

(defparameter +simple-syntax-types+
  '("any" "boolean" "byte" "char" "double"
    "float" "int" "integer" "long" "map"
    "number" "object" "record" "short"
    "string" "symbol" "tuple" "uint" "vector"))

(defparameter +simple-syntax-color-keys+
  '(("comment" . :syntax-comment)
    ("keyword" . :syntax-keyword)
    ("function" . :syntax-function)
    ("variable" . :syntax-variable)
    ("string" . :syntax-string)
    ("number" . :syntax-number)
    ("type" . :syntax-type)
    ("operator" . :syntax-operator)
    ("punctuation" . :syntax-punctuation)
    ("meta" . :muted)
    ("addition" . :tool-diff-added)
    ("deletion" . :tool-diff-removed)))

(defun simple-syntax-formatter (scope theme)
  (or
   (cdr (assoc scope theme :test #'string=))
   (let ((color
           (cdr
            (assoc scope
                   +simple-syntax-color-keys+
                   :test #'string=))))
     (and
      color
      (lambda (text)
        (cadr-tui:theme-foreground
         color text :enabled-p t))))))

(defun write-simple-syntax-token
    (text scope theme output)
  (let ((formatter
          (and scope
               (simple-syntax-formatter
                scope theme))))
    (write-string
     (if formatter
         (funcall formatter text)
         text)
     output)))

(defun write-simple-syntax-range
    (code start end scope theme output)
  (when (< start end)
    (write-simple-syntax-token
     (subseq code start end)
     scope theme output)))

(defun simple-syntax-next-nonspace-index
    (code start)
  (loop for index from start below (length code)
        unless
        (member (char code index)
                '(#\Space #\Tab #\Newline
                  #\Return))
          return index))

(defun simple-syntax-quoted-end
    (code start)
  (let ((quote (char code start))
        (index (1+ start))
        (escaped-p nil))
    (loop while (< index (length code))
          for character = (char code index)
          do
          (cond
            (escaped-p
             (setf escaped-p nil))
            ((char= character #\\)
             (setf escaped-p t))
            ((char= character quote)
             (return (1+ index))))
          (incf index)
          finally (return index))))

(defun simple-syntax-highlight-diff
    (code theme)
  (with-output-to-string (output)
    (loop with start = 0
          while (< start (length code))
          for newline =
            (position #\Newline code :start start)
          for end = (or newline (length code))
          for scope =
            (and (< start end)
                 (case (char code start)
                   (#\+ "addition")
                   (#\- "deletion")
                   (otherwise nil)))
          do
          (write-simple-syntax-range
           code start end scope theme output)
          (when newline
            (write-char #\Newline output))
          (setf start
                (if newline
                    (1+ newline)
                    (length code))))))

(defun simple-syntax-markup-name-part-p
    (character)
  (or (alphanumericp character)
      (member character '(#\- #\_ #\:))))

(defun simple-syntax-highlight-markup
    (code theme)
  (with-output-to-string (output)
    (loop with index = 0
          while (< index (length code))
          do
          (cond
            ((and
              (<= (+ index 4) (length code))
              (string= "<!--" code
                       :start2 index
                       :end2 (+ index 4)))
             (let* ((close
                      (search "-->" code
                              :start2 (+ index 4)))
                    (end
                      (if close
                          (+ close 3)
                          (length code))))
               (write-simple-syntax-range
                code index end "comment"
                theme output)
               (setf index end)))
            ((char= (char code index) #\<)
             (let ((prefix-end
                     (if
                         (and
                          (< (1+ index) (length code))
                          (char= (char code (1+ index))
                                 #\/))
                         (+ index 2)
                         (1+ index))))
               (write-simple-syntax-range
                code index prefix-end
                "punctuation" theme output)
               (setf index prefix-end)
               (let ((name-end index))
                 (loop while
                       (and
                        (< name-end (length code))
                        (simple-syntax-markup-name-part-p
                         (char code name-end)))
                       do (incf name-end))
                 (write-simple-syntax-range
                  code index name-end "keyword"
                  theme output)
                 (setf index name-end))
               (loop while (< index (length code))
                     for character = (char code index)
                     do
                     (cond
                       ((char= character #\>)
                        (write-simple-syntax-range
                         code index (1+ index)
                         "punctuation" theme output)
                        (incf index)
                        (return))
                       ((and
                         (char= character #\/)
                         (< (1+ index) (length code))
                         (char= (char code (1+ index))
                                #\>))
                        (write-simple-syntax-range
                         code index (+ index 2)
                         "punctuation" theme output)
                        (incf index 2)
                        (return))
                       ((member character
                                '(#\Space #\Tab
                                  #\Newline #\Return))
                        (let ((end (1+ index)))
                          (loop while
                                (and
                                 (< end (length code))
                                 (member
                                  (char code end)
                                  '(#\Space #\Tab
                                    #\Newline
                                    #\Return)))
                                do (incf end))
                          (write-simple-syntax-range
                           code index end
                           "punctuation" theme output)
                          (setf index end)))
                       ((member character '(#\" #\'))
                        (let ((end
                                (simple-syntax-quoted-end
                                 code index)))
                          (write-simple-syntax-range
                           code index end "string"
                           theme output)
                          (setf index end)))
                       ((simple-syntax-markup-name-part-p
                         character)
                        (let ((end (1+ index)))
                          (loop while
                                (and
                                 (< end (length code))
                                 (simple-syntax-markup-name-part-p
                                  (char code end)))
                                do (incf end))
                          (write-simple-syntax-range
                           code index end "variable"
                           theme output)
                          (setf index end)))
                       (t
                        (write-simple-syntax-range
                         code index (1+ index)
                         "punctuation" theme output)
                        (incf index))))))
            (t
             (let ((end
                     (or (position #\< code
                                   :start (1+ index))
                         (length code))))
               (write-string
                (subseq code index end) output)
               (setf index end)))))))

(defun simple-syntax-highlight-json
    (code theme)
  (with-output-to-string (output)
    (loop with index = 0
          while (< index (length code))
          for character = (char code index)
          do
          (cond
            ((char= character #\")
             (let* ((end
                      (simple-syntax-quoted-end
                       code index))
                    (next
                      (simple-syntax-next-nonspace-index
                       code end))
                    (scope
                      (if
                          (and next
                               (char= (char code next)
                                      #\:))
                          "variable"
                          "string")))
               (write-simple-syntax-range
                code index end scope theme output)
               (setf index end)))
            ((or (digit-char-p character)
                 (and
                  (char= character #\-)
                  (< (1+ index) (length code))
                  (digit-char-p
                   (char code (1+ index)))))
             (let ((end (1+ index)))
               (loop while
                     (and
                      (< end (length code))
                      (or
                       (digit-char-p (char code end))
                       (member (char code end)
                               '(#\. #\e #\E #\+ #\-))))
                     do (incf end))
               (write-simple-syntax-range
                code index end "number"
                theme output)
               (setf index end)))
            ((alpha-char-p character)
             (let ((end (1+ index)))
               (loop while
                     (and (< end (length code))
                          (alpha-char-p
                           (char code end)))
                     do (incf end))
               (write-simple-syntax-range
                code index end
                (and
                 (member
                  (string-downcase
                   (subseq code index end))
                  '("true" "false" "null")
                  :test #'string=)
                 "number")
                theme output)
               (setf index end)))
            (t
             (write-char character output)
             (incf index))))))

(defparameter +simple-bash-built-ins+
  '("alias" "bg" "bind" "break" "builtin"
    "cd" "command" "compgen" "complete"
    "continue" "declare" "dirs" "disown"
    "echo" "enable" "eval" "exec" "exit"
    "export" "fc" "fg" "getopts" "hash"
    "help" "history" "jobs" "kill" "let"
    "local" "logout" "mapfile" "popd"
    "printf" "pushd" "pwd" "read"
    "readonly" "return" "set" "shift"
    "shopt" "source" "suspend" "test"
    "times" "trap" "type" "typeset"
    "ulimit" "umask" "unalias" "unset"
    "wait"))

(defparameter +simple-bash-keywords+
  '("case" "coproc" "do" "done" "elif"
    "else" "esac" "fi" "for" "function"
    "if" "in" "select" "then" "time"
    "until" "while"))

(defun simple-syntax-bash-variable-end
    (code start limit)
  (cond
    ((and (< (1+ start) limit)
          (char= (char code (1+ start)) #\{))
     (let ((close
             (position #\} code
                       :start (+ start 2)
                       :end limit)))
       (if close (1+ close) (1+ start))))
    (t
     (let ((end (1+ start)))
       (loop while
             (and
              (< end limit)
              (or
               (alphanumericp (char code end))
               (member (char code end)
                       '(#\_ #\@ #\# #\? #\!
                         #\- #\$))))
             do (incf end))
       end))))

(defun simple-syntax-write-bash-string
    (code start end theme output)
  (if (char= (char code start) #\')
      (write-simple-syntax-range
       code start end "string" theme output)
      (loop with segment-start = start
            with index = (1+ start)
            while (< index end)
            do
            (if (char= (char code index) #\$)
                (let ((variable-end
                        (simple-syntax-bash-variable-end
                         code index end)))
                  (write-simple-syntax-range
                   code segment-start index
                   "string" theme output)
                  (write-simple-syntax-range
                   code index variable-end
                   "variable" theme output)
                  (setf index variable-end
                        segment-start variable-end))
                (incf index))
            finally
            (write-simple-syntax-range
             code segment-start end
             "string" theme output))))

(defun simple-syntax-highlight-bash
    (code theme)
  (with-output-to-string (output)
    (loop with index = 0
          while (< index (length code))
          for character = (char code index)
          do
          (cond
            ((char= character #\#)
             (let ((end
                     (or (position #\Newline code
                                   :start (1+ index))
                         (length code))))
               (write-simple-syntax-range
                code index end "comment"
                theme output)
               (setf index end)))
            ((member character '(#\" #\'))
             (let ((end
                     (simple-syntax-quoted-end
                      code index)))
               (simple-syntax-write-bash-string
                code index end theme output)
               (setf index end)))
            ((char= character #\$)
             (let ((end
                     (simple-syntax-bash-variable-end
                      code index (length code))))
               (write-simple-syntax-range
                code index end "variable"
                theme output)
               (setf index end)))
            ((or (alpha-char-p character)
                 (char= character #\_))
             (let ((end (1+ index)))
               (loop while
                     (and
                      (< end (length code))
                      (or
                       (alphanumericp (char code end))
                       (char= (char code end) #\_)))
                     do (incf end))
               (let* ((word (subseq code index end))
                      (lower (string-downcase word))
                      (next
                        (simple-syntax-next-nonspace-index
                         code end))
                      (function-p
                        (and next
                             (char= (char code next) #\()
                             (< (1+ next) (length code))
                             (char= (char code (1+ next))
                                    #\)))))
                 (write-simple-syntax-range
                  code index end
                  (cond
                    ((member lower
                             +simple-bash-built-ins+
                             :test #'string=)
                     "type")
                    ((member lower
                             +simple-bash-keywords+
                             :test #'string=)
                     "keyword")
                    (function-p "function")
                    (t nil))
                  theme output))
               (setf index end)))
            ((digit-char-p character)
             (let ((end (1+ index)))
               (loop while
                     (and (< end (length code))
                          (digit-char-p
                           (char code end)))
                     do (incf end))
               (write-simple-syntax-range
                code index end "number"
                theme output)
               (setf index end)))
            (t
             (write-char character output)
             (incf index))))))

(defparameter +simple-sql-keywords+
  '("all" "alter" "and" "as" "asc" "between"
    "by" "case" "create" "delete" "desc"
    "distinct" "drop" "else" "end" "exists"
    "from" "full" "group" "having" "in"
    "inner" "insert" "into" "is" "join"
    "left" "like" "limit" "not" "null"
    "offset" "on" "or" "order" "outer"
    "right" "select" "set" "table" "then"
    "union" "update" "values" "when" "where"))

(defun simple-syntax-highlight-sql
    (code theme)
  (with-output-to-string (output)
    (loop with index = 0
          while (< index (length code))
          for character = (char code index)
          do
          (cond
            ((and
              (< (1+ index) (length code))
              (char= character #\-)
              (char= (char code (1+ index)) #\-))
             (let ((end
                     (or (position #\Newline code
                                   :start (+ index 2))
                         (length code))))
               (write-simple-syntax-range
                code index end "comment"
                theme output)
               (setf index end)))
            ((member character '(#\' #\"))
             (let ((end
                     (simple-syntax-quoted-end
                      code index)))
               (write-simple-syntax-range
                code index end "string"
                theme output)
               (setf index end)))
            ((alpha-char-p character)
             (let ((end (1+ index)))
               (loop while
                     (and
                      (< end (length code))
                      (or
                       (alphanumericp (char code end))
                       (char= (char code end) #\_)))
                     do (incf end))
               (write-simple-syntax-range
                code index end
                (and
                 (member
                  (string-downcase
                   (subseq code index end))
                  +simple-sql-keywords+
                  :test #'string=)
                 "keyword")
                theme output)
               (setf index end)))
            ((digit-char-p character)
             (let ((end (1+ index)))
               (loop while
                     (and
                      (< end (length code))
                      (or
                       (digit-char-p (char code end))
                       (char= (char code end) #\.)))
                     do (incf end))
               (write-simple-syntax-range
                code index end "number"
                theme output)
               (setf index end)))
            ((member character
                     '(#\= #\< #\> #\! #\+ #\-
                       #\* #\/ #\%))
             (let ((end (1+ index)))
               (when
                   (and
                    (< end (length code))
                    (member (char code end)
                            '(#\= #\> #\<)))
                 (incf end))
               (write-simple-syntax-range
                code index end "operator"
                theme output)
               (setf index end)))
            (t
             (write-char character output)
             (incf index))))))

(defun simple-syntax-regexp-start-p
    (code index)
  (let ((previous
          (loop for cursor downfrom (1- index) to 0
                for character = (char code cursor)
                unless
                (member character
                        '(#\Space #\Tab #\Newline
                          #\Return))
                  return character)))
    (or (null previous)
        (member previous
                '(#\= #\( #\[ #\{ #\, #\:
                  #\; #\! #\? #\& #\|)))))

(defun simple-syntax-regexp-end
    (code start)
  (let ((index (1+ start))
        (escaped-p nil)
        (class-p nil))
    (loop while (< index (length code))
          for character = (char code index)
          do
          (cond
            (escaped-p
             (setf escaped-p nil))
            ((char= character #\\)
             (setf escaped-p t))
            ((char= character #\[)
             (setf class-p t))
            ((and class-p
                  (char= character #\]))
             (setf class-p nil))
            ((and (not class-p)
                  (char= character #\/))
             (incf index)
             (loop while
                   (and (< index (length code))
                        (alpha-char-p
                         (char code index)))
                   do (incf index))
             (return index)))
          (incf index)
          finally (return nil))))

(defun simple-syntax-identifier-start-p
    (character)
  (or (alpha-char-p character)
      (member character '(#\_ #\$))))

(defun simple-syntax-identifier-part-p
    (character)
  (or (alphanumericp character)
      (member character '(#\_ #\$))))

(defun simple-syntax-next-character
    (code start)
  (loop for index from start below (length code)
        for character = (char code index)
        unless
        (member character
                '(#\Space #\Tab #\Newline
                  #\Return))
          return character))

(defun simple-syntax-line-comment-length
    (code index language)
  (let ((remaining (- (length code) index)))
    (cond
      ((and
        (member language
                '("c" "cpp" "go" "java"
                  "javascript" "typescript"
                  "rust")
                :test #'string=)
        (>= remaining 2)
            (string= "//" code
                     :start2 index
                     :end2 (+ index 2)))
       2)
      ((and
        (member language '("sql")
                :test #'string=)
        (>= remaining 2)
        (string= "--" code
                 :start2 index
                 :end2 (+ index 2)))
       2)
      ((and
        (member language
                '("bash" "python" "ruby"
                  "yaml")
                :test #'string=)
        (char= (char code index) #\#))
       1)
      ((and
        (string= language "lisp")
        (char= (char code index) #\;))
       1)
      (t nil))))

(defun simple-syntax-word-scope
    (word next-character previous-word
     parameter-depth expect-type-p)
  (let ((lower (string-downcase word)))
    (cond
      ((member lower +simple-syntax-keywords+
               :test #'string=)
       "keyword")
      ((member previous-word
               '("class" "enum" "interface"
                 "struct" "trait")
               :test #'string=)
       "function")
      ((or
        (member lower +simple-syntax-types+
                :test #'string=)
        expect-type-p
        (member previous-word
                '("extends" "implements" "new"
                  "type")
                :test #'string=))
       "type")
      ((and next-character
            (char= next-character #\())
       "function")
      ((plusp parameter-depth)
       "variable")
      (t nil))))

(defun simple-syntax-highlight
    (code language &optional theme)
  (unless
      (and (stringp language)
           (supports-syntax-language-p language))
    (return-from simple-syntax-highlight code))
  (let ((language (string-downcase language)))
    (cond
      ((string= language "diff")
       (return-from simple-syntax-highlight
         (simple-syntax-highlight-diff
          code theme)))
      ((member language '("html" "xml")
               :test #'string=)
       (return-from simple-syntax-highlight
         (simple-syntax-highlight-markup
          code theme)))
      ((string= language "json")
       (return-from simple-syntax-highlight
         (simple-syntax-highlight-json
          code theme)))
      ((string= language "bash")
       (return-from simple-syntax-highlight
         (simple-syntax-highlight-bash
          code theme)))
      ((string= language "sql")
       (return-from simple-syntax-highlight
         (simple-syntax-highlight-sql
          code theme)))))
  (let ((language (string-downcase language))
        (index 0)
        (previous-word nil)
        (parameter-depth 0)
        (pending-function-p nil)
        (expect-type-p nil))
    (with-output-to-string (output)
      (labels
          ((emit (start end &optional scope)
             (let* ((text (subseq code start end))
                    (formatter
                      (and scope
                           (simple-syntax-formatter
                            scope theme))))
               (write-string
                (if formatter
                    (funcall formatter text)
                    text)
                output))))
        (loop while (< index (length code))
              for character = (char code index)
              for comment-length =
              (simple-syntax-line-comment-length
               code index language)
              do
              (cond
                (comment-length
                 (let ((end
                         (or
                          (position #\Newline code
                                    :start
                                    (+ index comment-length))
                          (length code))))
                   (emit index end "comment")
                   (setf previous-word nil
                         pending-function-p nil
                         expect-type-p nil
                         index end)))
                ((and
                  (member language
                          '("c" "cpp" "css" "go"
                            "java" "javascript"
                            "typescript" "rust")
                          :test #'string=)
                  (<= (+ index 2) (length code))
                  (string= "/*" code
                           :start2 index
                           :end2 (+ index 2)))
                 (let* ((close
                          (search "*/" code
                                  :start2 (+ index 2)))
                        (end
                          (if close
                              (+ close 2)
                              (length code))))
                   (emit index end "comment")
                   (setf previous-word nil
                         pending-function-p nil
                         expect-type-p nil
                         index end)))
                ((and
                  (member language
                          '("javascript" "typescript")
                          :test #'string=)
                  (char= character #\/)
                  (simple-syntax-regexp-start-p
                   code index)
                  (simple-syntax-regexp-end
                   code index))
                 (let ((end
                         (simple-syntax-regexp-end
                          code index)))
                   (emit index end "string")
                   (setf previous-word nil
                         pending-function-p nil
                         expect-type-p nil
                         index end)))
                ((and
                  (string= language "python")
                  (char= character #\@))
                 (let ((end (1+ index)))
                   (loop while
                         (and
                          (< end (length code))
                          (not
                           (member
                            (char code end)
                            '(#\Space #\Tab
                              #\Newline #\Return))))
                         do (incf end))
                   (emit index end "meta")
                   (setf previous-word nil
                         pending-function-p nil
                         expect-type-p nil
                         index end)))
                ((member character
                         '(#\" #\' #\`))
                 (let ((quote character)
                       (end (1+ index))
                       (escaped-p nil))
                   (loop while (< end (length code))
                         for current = (char code end)
                         do
                         (cond
                           (escaped-p
                            (setf escaped-p nil))
                           ((char= current #\\)
                            (setf escaped-p t))
                           ((char= current quote)
                            (incf end)
                            (return)))
                         (incf end))
                   (emit index end "string")
                   (setf previous-word nil
                         pending-function-p nil
                         expect-type-p nil
                         index end)))
                ((simple-syntax-identifier-start-p
                  character)
                 (let ((end (1+ index)))
                   (loop while
                         (and
                          (< end (length code))
                          (simple-syntax-identifier-part-p
                           (char code end)))
                         do (incf end))
                   (let* ((word (subseq code index end))
                          (lower
                            (string-downcase word))
                          (scope
                            (simple-syntax-word-scope
                             word
                             (simple-syntax-next-character
                              code end)
                             previous-word
                             parameter-depth
                             expect-type-p)))
                     (emit index end scope)
                     (setf
                      pending-function-p
                      (and
                       scope
                       (string= scope "function")
                       (eql
                        (simple-syntax-next-character
                         code end)
                        #\())
                      expect-type-p nil)
                     (setf previous-word lower
                           index end))))
                ((digit-char-p character)
                 (let ((end (1+ index)))
                   (loop while
                         (and
                          (< end (length code))
                          (or
                           (digit-char-p
                            (char code end))
                           (member
                            (char code end)
                            '(#\. #\_))))
                         do (incf end))
                   (emit index end "number")
                   (setf previous-word nil
                         pending-function-p nil
                         expect-type-p nil
                         index end)))
                ((char= character #\()
                 (if
                     (or pending-function-p
                         (plusp parameter-depth))
                     (progn
                       (emit index (1+ index)
                             "function")
                       (incf parameter-depth))
                     (write-char character output))
                 (setf pending-function-p nil)
                 (setf previous-word nil)
                 (incf index))
                ((and
                  (plusp parameter-depth)
                  (char= character #\)))
                 (emit index (1+ index) "function")
                 (decf parameter-depth)
                 (setf expect-type-p nil
                       previous-word nil)
                 (incf index))
                ((and
                  (plusp parameter-depth)
                  (char= character #\:))
                 (emit index (1+ index) "variable")
                 (setf expect-type-p t
                       previous-word nil)
                 (incf index))
                ((and
                  expect-type-p
                  (member character '(#\Space #\Tab)))
                 (emit index (1+ index) "variable")
                 (incf index))
                (t
                 (write-char character output)
                 (unless
                     (member character
                             '(#\Space #\Tab))
                   (setf previous-word nil
                         pending-function-p nil
                         expect-type-p nil))
                 (incf index))))))))

