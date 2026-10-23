(in-package #:cadr-cli)

;;; Codemode tool, loadout, and worker admission.
;;; pi@4a080252f packages/coding-agent/src/extensions/codemode/{tool,execute,index}.ts
;;; and packages/codemode/src/{source,identifier,declarations}.ts

(defparameter +codemode-memory-limit+ (* 256 1024 1024))
(defparameter +codemode-worker-wait-ms+ 60000)
(defparameter +codemode-default-workers+ 2)
(defparameter +codemode-default-output-tokens+ 10000)
(defparameter +codemode-inline-budget+ 3000)
(defparameter +codemode-chars-per-token+ 4)
(defparameter +codemode-options-prefix+ "// @options:")
(defparameter +codemode-max-timeout-ms+ 2147483647)
(defparameter +codemode-store-type+ "codemode-store")

(defvar *codemode-settings-manager* nil)
(defvar *codemode-worker-lock* (sb-thread:make-mutex :name "codemode-workers"))
(defvar *codemode-worker-wait* (sb-thread:make-waitqueue :name "codemode-workers"))
(defvar *codemode-active-workers* 0)
(defvar *codemode-worker-waiters* nil)
(defvar *codemode-base-descriptions* (make-hash-table :test #'eq))
(defvar *codemode-model-runtime* nil)
(defvar *codemode-model-in-flight* 0)
(defvar *codemode-model-lock* (sb-thread:make-mutex :name "codemode-models"))
(defvar *codemode-model-wait* (sb-thread:make-waitqueue :name "codemode-models"))
(defvar *codemode-script-tools* nil)
(defvar *codemode-tool-namespaces* nil)

(defstruct codemode-namespace
  (name "" :type string)
  (aliases nil :type list)
  (description nil :type (or null string))
  (instructions nil :type (or null string))
  (tool-names nil :type list))

(defstruct codemode-resolved-model
  (type "" :type string)
  (provider "" :type string)
  (id "" :type string)
  (name "" :type string)
  (api "" :type string)
  (base-url "" :type string)
  (input nil :type list)
  (context-window nil)
  (source nil))

(defstruct codemode-model-backend
  (models nil :type list)
  (classify-function nil :type (or null function))
  (images-function nil :type (or null function))
  (available-providers nil :type list))

(define-condition codemode-source-error (error)
  ((text :initarg :text :reader codemode-source-error-text))
  (:report (lambda (condition stream)
             (write-string (codemode-source-error-text condition) stream))))

(defun codemode-source-error (text)
  (error 'codemode-source-error :text text))

(defun codemode-identifier (name)
  (let ((identifier
          (with-output-to-string (output)
            (loop for char across name
                  for index from 0
                  for valid = (if (zerop index)
                                  (or (alpha-char-p char) (char= char #\_) (char= char #\$))
                                  (or (alphanumericp char) (char= char #\_) (char= char #\$)))
                  do (write-char (if valid char #\_) output)))))
    (if (string= identifier "") "_" identifier)))

(defun codemode-safe-integer-p (value)
  (and (integerp value) (>= value 0) (<= value (1- (ash 1 53)))))

(defun codemode-parse-options (directive)
  (let ((text (string-trim '(#\Space #\Tab) directive)))
    (when (string= text "")
      (codemode-source-error
       "@options must be a JSON object with supported fields `max_output_tokens` and `timeout_ms`"))
    (let ((value (handler-case (cadr-ai::parse-json text)
                   (error (condition)
                     (codemode-source-error
                      (format nil "@options must be valid JSON with supported fields `max_output_tokens` and `timeout_ms`: ~A"
                              condition))))))
      (unless (hash-table-p value)
        (codemode-source-error
         "@options must be a JSON object with supported fields `max_output_tokens` and `timeout_ms`"))
      (maphash (lambda (key value)
                 (declare (ignore value))
                 (unless (member key '("max_output_tokens" "timeout_ms") :test #'string=)
                   (codemode-source-error
                    (format nil "@options only supports `max_output_tokens` and `timeout_ms`; got `~A`" key))))
               value)
      (let ((tokens (gethash "max_output_tokens" value))
            (timeout (gethash "timeout_ms" value))
            (options nil))
        (when (nth-value 1 (gethash "max_output_tokens" value))
          (unless (codemode-safe-integer-p tokens)
            (codemode-source-error
             "@options field `max_output_tokens` must be a non-negative safe integer"))
          (setf (getf options :max-output-tokens) tokens))
        (when (nth-value 1 (gethash "timeout_ms" value))
          (unless (and (codemode-safe-integer-p timeout)
                       (plusp timeout)
                       (<= timeout +codemode-max-timeout-ms+))
            (codemode-source-error
             (format nil "@options field `timeout_ms` must be a positive integer up to ~A"
                     +codemode-max-timeout-ms+)))
          (setf (getf options :timeout-ms) timeout))
        options))))

(defun codemode-parse-source (input)
  (unless (and (stringp input)
               (plusp (length (string-trim '(#\Space #\Tab #\Newline #\Return) input))))
    (codemode-source-error
     "Expected JavaScript source text (non-empty). Provide JS only, optionally with a first line `// @options: {\"max_output_tokens\": 1000}`."))
  (let* ((lines (uiop:split-string input :separator '(#\Newline)))
         (misplaced (position-if (lambda (line)
                                   (let ((trimmed (string-left-trim '(#\Space #\Tab) line)))
                                     (and (plusp (length trimmed))
                                          (eql 0 (search +codemode-options-prefix+ trimmed)))))
                                 lines :start 1)))
    (when misplaced
      (codemode-source-error
       (format nil "The // @options: line must be the first line of the input; found one on line ~A"
               (+ misplaced 1))))
    (let* ((first (string-right-trim '(#\Return) (first lines)))
           (trimmed (string-left-trim '(#\Space #\Tab) first)))
      (unless (eql 0 (search +codemode-options-prefix+ trimmed))
        (return-from codemode-parse-source (values input nil)))
      (let* ((newline (position #\Newline input))
             (code (if newline (subseq input newline) "")))
        (when (string= (string-trim '(#\Space #\Tab #\Newline #\Return) code) "")
          (codemode-source-error
           "The @options line must be followed by JavaScript source on subsequent lines"))
        (values code
                (codemode-parse-options
                 (string-trim '(#\Space #\Tab)
                              (subseq trimmed (length +codemode-options-prefix+)))))))))

(defun codemode-json-string (value key)
  (and (hash-table-p value) (cadr-ai::json-get value key)))

(defun codemode-schema-type (schema)
  (cond
    ((eq schema t) "unknown")
    ((eq schema nil) "never")
    ((not (hash-table-p schema)) "unknown")
    (t
     (let ((type (gethash "type" schema)))
       (cond
         ((and (stringp type) (member type '("string" "number" "integer" "boolean" "null") :test #'string=))
          (if (string= type "integer") "number" type))
         ((and (stringp type) (string= type "array"))
          (let ((items (gethash "items" schema)))
            (if (hash-table-p items)
                (format nil "Array<~A>" (codemode-schema-type items))
                "unknown[]")))
         ((or (and (stringp type) (string= type "object"))
              (gethash "properties" schema))
          (codemode-object-type schema))
         (t "unknown"))))))

(defun codemode-object-type (schema)
  (let* ((properties (gethash "properties" schema))
         (required (gethash "required" schema))
         (names (when (hash-table-p properties)
                  (sort (loop for key being the hash-keys of properties collect key) #'string<))))
    (if (null names)
        "{}"
        (format nil "{ ~{~A~^ ~} }"
                (mapcar (lambda (name)
                          (format nil "~A~A: ~A;"
                                  name
                                  (if (and (vectorp required)
                                           (find name required :test #'string=))
                                      ""
                                      "?")
                                  (codemode-schema-type (gethash name properties))))
                        names)))))

(defun codemode-tool-sample (name description parameters)
  (let ((input (if (hash-table-p parameters)
                   (codemode-schema-type parameters)
                   "unknown")))
    (format nil "~A~%~%codemode tool declaration:~%```ts~%declare const tools: { ~A(args: ~A): Promise<string>; };~%```"
            (string-trim '(#\Space #\Tab #\Newline #\Return) (or description ""))
            (codemode-identifier name)
            input)))

(defun codemode-section (name description parameters)
  (let* ((id (codemode-identifier name))
         (heading (if (string= id name)
                      (format nil "### `~A`" id)
                      (format nil "### `~A` (`~A`)" id name))))
    (format nil "~A~%~A" heading
            (string-trim '(#\Newline) (codemode-tool-sample name description parameters)))))

(defun codemode-docs-path ()
  (cadr-agent::mcp-join (cadr-ai::cadr-docs-directory) "codemode.md"))

(defun codemode-description (tools &key (models t) (budget +codemode-inline-budget+)
                                     (deferred nil))
  (let* ((listed (remove-if (lambda (tool)
                              (or (string= (cadr-ai:tool-name tool) "codemode")
                                  (member (cadr-ai:tool-name tool) deferred :test #'string=)))
                            tools))
         (entries (mapcar (lambda (tool)
                            (let ((section (codemode-section
                                            (cadr-ai:tool-name tool)
                                            (cadr-ai:tool-description tool)
                                            (cadr-ai:tool-parameters tool))))
                              (list (cadr-ai:tool-name tool)
                                    section
                                    (ceiling (length section) +codemode-chars-per-token+))))
                          listed))
         (queue (sort (copy-list entries) #'< :key #'third))
         (shown nil)
         (remaining budget))
    (when budget
      (loop while queue
            for next = (first queue)
            do (if (> (third next) remaining)
                   (setf queue nil)
                   (progn
                     (decf remaining (third next))
                     (push (first next) shown)
                     (pop queue)))))
    (unless budget
      (setf shown (mapcar #'first entries)))
    (let ((sections
            (list
             (format nil "Run JavaScript that calls other tools. The input is raw JavaScript (not JSON, no code fence), run as an async function body in a QuickJS sandbox: top-level `await` and `return` work. No Node, file system, network, or timers.
- `await tools.<name>({ ...args })` resolves to a string, or an object if the tool's declaration says so, and rejects with an Error on failure. A tool whose declaration returns an object resolves on failure too when it returned that object; check its fields. Calls still running when the script ends are cancelled.
- Optional first line: `// @options: {\"max_output_tokens\": 10000, \"timeout_ms\": 60000}`")
             (format nil "Globals:
- `text(value)`, `image(dataUrlOrImageBlock)`, `console.log(...)`, and top-level `return` add output; `exit()` ends the script. With several text items, each starts with a `==> text N/M <==` line, and `console` lines follow the other output in one `<console_output>` block. `image()` also saves the image to a temp file and the result names its path.
- `store(key, value)` and `load(key)` keep JSON values across codemode calls.
- `ALL_TOOLS`, `await searchTools(query, { limit?, namespace? })`, `await describeTool(name)`, `await describeNamespace(name)`: find unlisted tools, such as MCP tools.~A"
                     (if models
                         (format nil "~%- `models`: classifiers and image generation. Read ~A first."
                                 (codemode-docs-path))
                         "")))))
      (when listed
        (let ((blocks (list "Nested tools:")))
          (dolist (entry entries)
            (when (member (first entry) shown :test #'string=)
              (push (second entry) blocks)))
          (push (format nil "~{~A~^~%~%~}" (nreverse blocks)) sections)))
      (format nil "~{~A~^~%~%~}" sections))))

(defun codemode-settings-object ()
  (let ((manager *codemode-settings-manager*))
    (when manager
      (let ((value (cadr-cli::settings-value manager "codemode")))
        (when (hash-table-p value) value)))))

(defun codemode-mode ()
  (let ((mode (gethash "mode" (or (codemode-settings-object) (cadr-ai::json-object)))))
    (if (and (stringp mode) (string= mode "only")) "only" "on")))

(defun codemode-inline-budget ()
  (let ((budget (gethash "inlineBudget" (or (codemode-settings-object) (cadr-ai::json-object)))))
    (if (and (realp budget)
             (not (sb-ext:float-infinity-p (float budget 1.0d0)))
             (not (sb-ext:float-nan-p (float budget 1.0d0)))
             (>= budget 0))
        budget
        +codemode-inline-budget+)))

(defun codemode-script-call (tool)
  (format nil "~A~%~%Codemode: `tools.~A(args)` resolves to a string."
          (string-trim '(#\Space #\Tab #\Newline #\Return)
                       (cadr-ai:tool-description tool))
          (codemode-identifier (cadr-ai:tool-name tool))))

(defun codemode-base-description (tool)
  (or (gethash tool *codemode-base-descriptions*)
      (setf (gethash tool *codemode-base-descriptions*)
            (cadr-ai:tool-description tool))))

(defun codemode-prepare-loadout (agent)
  (let* ((registry (cadr-agent::agent-tool-registry agent))
         (declared (and registry (cadr-agent:registry-tools registry)))
         (host (cadr-agent::agent-extension-host agent))
         (callable (remove "codemode"
                           (if host
                               (cadr-agent::agent-callable-tools agent)
                               declared)
                           :key #'cadr-ai:tool-name :test #'string=))
         (mode (codemode-mode))
         (live (make-hash-table :test #'eq)))
    (unless (find "codemode" declared :key #'cadr-ai:tool-name :test #'string=)
      (setf (cadr-agent::agent-codemode-hidden-declarations agent) nil)
      (return-from codemode-prepare-loadout nil))
    (dolist (tool declared) (setf (gethash tool live) t))
    (maphash (lambda (tool description)
               (declare (ignore description))
               (unless (gethash tool live)
                 (remhash tool *codemode-base-descriptions*)))
             *codemode-base-descriptions*)
    (dolist (tool declared)
      (setf (cadr-ai:tool-description tool) (codemode-base-description tool)))
    (let ((hidden nil)
          (listed (if (string= mode "only")
                      callable
                      (remove-if (lambda (tool)
                                   (eq :direct
                                       (cadr-agent::extension-tool-exposure
                                        host (cadr-ai:tool-name tool))))
                                 callable))))
      (let ((codemode (find "codemode" declared :key #'cadr-ai:tool-name :test #'string=))
            (deferred (loop for tool in listed
                            when (eq :deferred
                                     (cadr-agent::extension-tool-exposure
                                      host (cadr-ai:tool-name tool)))
                            collect (cadr-ai:tool-name tool))))
        (when codemode
          (setf (cadr-ai:tool-description codemode)
                (codemode-description listed
                                      :budget (codemode-inline-budget)
                                      :deferred deferred))))
      (when (string= mode "on")
        (dolist (tool declared)
          (when (find (cadr-ai:tool-name tool) callable
                      :key #'cadr-ai:tool-name :test #'string=)
            (let ((base (cadr-ai:tool-description tool)))
              (setf (cadr-ai:tool-description tool)
                    (format nil "~A~%~%Codemode: `tools.~A(args)` resolves to a string."
                            (string-trim '(#\Space #\Tab #\Newline #\Return) base)
                            (codemode-identifier (cadr-ai:tool-name tool))))))))
      (when (string= mode "only")
        (dolist (tool callable)
          (when (and (eq :direct (cadr-agent::extension-tool-exposure
                                  host (cadr-ai:tool-name tool)))
                     (find (cadr-ai:tool-name tool) declared
                           :key #'cadr-ai:tool-name :test #'string=))
            (push (cadr-ai:tool-name tool) hidden))))
      (setf (cadr-agent::agent-codemode-hidden-declarations agent)
            (nreverse hidden)))))

(defun codemode-max-workers ()
  (let ((raw (uiop:getenv "CADR_CODEMODE_MAX_WORKERS")))
    (if (or (null raw) (string= (string-trim '(#\Space #\Tab) raw) ""))
        +codemode-default-workers+
        (let* ((text (string-trim '(#\Space #\Tab #\Newline #\Return) raw))
               (value (ignore-errors
                        (multiple-value-bind (object end)
                            (read-from-string text)
                          (when (= end (length text)) object)))))
          (if (and (realp value) (= value (floor value)) (plusp (floor value)))
              (floor value)
              +codemode-default-workers+)))))

(defun codemode-admit-workers ()
  (loop while (and *codemode-worker-waiters*
                   (< *codemode-active-workers* (codemode-max-workers)))
        do (incf *codemode-active-workers*)
           (setf (cdr (pop *codemode-worker-waiters*)) t))
  (sb-thread:condition-broadcast *codemode-worker-wait*))

(defun codemode-reserve-worker (timeout-ms aborted-p)
  (when (and aborted-p (funcall aborted-p))
    (return-from codemode-reserve-worker :aborted))
  (sb-thread:with-mutex (*codemode-worker-lock*)
    (when (and aborted-p (funcall aborted-p))
      (return-from codemode-reserve-worker :aborted))
    (let ((cell (cons (gensym "CODEMODE-WAITER") nil))
          (deadline (+ (get-internal-real-time)
                       (round (* timeout-ms
                                 (/ internal-time-units-per-second 1000))))))
      (setf *codemode-worker-waiters*
            (append *codemode-worker-waiters* (list cell)))
      (codemode-admit-workers)
      (loop
        (when (cdr cell) (return :reserved))
        (when (and aborted-p (funcall aborted-p))
          (setf *codemode-worker-waiters*
                (remove cell *codemode-worker-waiters* :test #'eq))
          (return :aborted))
        (let ((now (get-internal-real-time)))
          (when (>= now deadline)
            (setf *codemode-worker-waiters*
                  (remove cell *codemode-worker-waiters* :test #'eq))
            (return :timeout))
          ;; A timed-out CONDITION-WAIT returns without the mutex. Do not
          ;; loop, and reacquire before touching the waiter list.
          (unless (sb-thread:condition-wait
                   *codemode-worker-wait* *codemode-worker-lock*
                   :timeout (max 0 (/ (- deadline now)
                                      internal-time-units-per-second)))
            (sb-thread:with-mutex (*codemode-worker-lock*)
              (cond ((cdr cell)
                     (return :reserved))
                    (t
                     (setf *codemode-worker-waiters*
                           (remove cell *codemode-worker-waiters* :test #'eq))
                     (return-from codemode-reserve-worker :timeout))))))))))

(defun codemode-release-worker ()
  (sb-thread:with-mutex (*codemode-worker-lock*)
    (when (plusp *codemode-active-workers*)
      (decf *codemode-active-workers*))
    (codemode-admit-workers)))

(defun codemode-text-of (content)
  (cadr-ai::content-text content (string #\Newline)))

(defparameter +codemode-search-limit+ 8)
(defparameter +codemode-classifier-shape+
  "{ state: { ... }, images?: [{ type: \"image\", data: <base64>, mimeType }], questions: { <id>: { type: \"choice\", instructions, criteria: { <label>: <meaning> } } | { type: \"score\", instructions, criteria: [<lowest level>, ..., <highest level>] } | { type: \"bool\", instructions, criteria: { true: <meaning>, false: <meaning> } } } }")
(defparameter +codemode-images-shape+
  "{ input: [{ type: \"text\", text: <prompt> }, ...optional { type: \"image\", data: <base64>, mimeType } references] }")

(defun codemode-json-null-p (value)
  (and (symbolp value)
       (not (keywordp value))
       (string= (symbol-name value) "NULL")))

(defun codemode-skip-ws (source start)
  (loop for index from start below (length source)
        for char = (char source index)
        while (member char '(#\Space #\Tab #\Newline #\Return))
        finally (return index)))

(defun codemode-read-string (source start)
  (let ((index (1+ start)))
    (loop while (< index (length source))
          do (cond ((char= (char source index) #\\)
                    (incf index 2))
                   ((char= (char source index) #\")
                    (return-from codemode-read-string
                      (values (cadr-ai::parse-json
                               (subseq source start (1+ index)))
                              (1+ index))))
                   (t (incf index))))
    (error "unterminated JSON string")))

(defun codemode-read-json (source start)
  (let ((index (codemode-skip-ws source start)))
    (when (>= index (length source))
      (error "empty JSON value"))
    (case (char source index)
      (#\{ (codemode-read-object source index))
      (#\[ (codemode-read-array source index))
      (#\" (codemode-read-string source index))
      (t (let ((end (or (position-if
                         (lambda (char)
                           (member char '(#\, #\] #\} #\: #\Space #\Tab
                                          #\Newline #\Return)))
                         source :start index)
                        (length source))))
           (values (cadr-ai::parse-json (subseq source index end)) end))))))

(defun codemode-read-object (source start)
  (let ((index (codemode-skip-ws source (1+ start)))
        (pairs nil))
    (when (and (< index (length source)) (char= (char source index) #\}))
      (return-from codemode-read-object (values (list :json-object) (1+ index))))
    (loop
      (multiple-value-bind (key next) (codemode-read-json source index)
        (unless (stringp key)
          (error "JSON object key must be a string"))
        (setf index (codemode-skip-ws source next))
        (unless (and (< index (length source)) (char= (char source index) #\:))
          (error "JSON object expected a colon"))
        (multiple-value-bind (value after) (codemode-read-json source (1+ index))
          (setf pairs (append pairs (list key value)))
          (setf index (codemode-skip-ws source after))))
      (cond
        ((and (< index (length source)) (char= (char source index) #\,))
         (incf index))
        ((and (< index (length source)) (char= (char source index) #\}))
         (return (values (cons :json-object pairs) (1+ index))))
        (t (error "JSON object expected a comma or end"))))))

(defun codemode-read-array (source start)
  (let ((index (codemode-skip-ws source (1+ start)))
        (items nil))
    (when (and (< index (length source)) (char= (char source index) #\]))
      (return-from codemode-read-array (values #() (1+ index))))
    (loop
      (multiple-value-bind (value next) (codemode-read-json source index)
        (push value items)
        (setf index (codemode-skip-ws source next)))
      (cond
        ((and (< index (length source)) (char= (char source index) #\,))
         (incf index))
        ((and (< index (length source)) (char= (char source index) #\]))
         (return (values (coerce (nreverse items) 'vector) (1+ index))))
        (t (error "JSON array expected a comma or end"))))))

(defun codemode-parse-ordered (source)
  (unless (stringp source)
    (return-from codemode-parse-ordered source))
  (multiple-value-bind (value end) (codemode-read-json source 0)
    (when (< (codemode-skip-ws source end) (length source))
      (error "trailing JSON"))
    value))

(defun codemode-object-p (value)
  (or (hash-table-p value) (cadr-ai::json-object-pairs-p value)))

(defun codemode-object-keys (value)
  (cond
    ((cadr-ai::json-object-pairs-p value)
     (loop for (key item) on (cdr value) by #'cddr
           when (stringp key) collect key))
    ((hash-table-p value)
     (loop for key being the hash-keys of value collect key))
    (t nil)))

(defun codemode-field (value key)
  (if (and (codemode-object-p value) (cadr-ai::json-present-p value key))
      (cadr-ai::json-get value key)
      :codemode-absent))

(defun codemode-describe-value (value)
  (cond
    ((eq value :codemode-absent) "undefined")
    ((codemode-json-null-p value) "null")
    ((null value) "a boolean")
    ((eq value t) "a boolean")
    ((stringp value) "a string")
    ((vectorp value)
     (if (zerop (length value)) "an empty array" "an array"))
    ((codemode-object-p value)
     (let ((keys (codemode-object-keys value)))
       (if (null keys)
           "{}"
           (format nil "{ ~{~A~^, ~}~A }"
                   (subseq keys 0 (min 6 (length keys)))
                   (if (> (length keys) 6) ", ..." "")))))
    ((numberp value) "a number")
    (t "a object")))

(defun codemode-shown (value)
  (if (eq value :codemode-absent)
      "undefined"
      (cadr-ai::stringify-json value)))

(defun codemode-with-article (word)
  (format nil "~A ~A"
          (if (and (plusp (length word))
                   (member (char word 0) '(#\a #\e #\i #\o #\u)))
              "an" "a")
          word))

(defun codemode-arguments (arguments)
  (cond ((vectorp arguments) arguments)
        ((null arguments) #())
        ((listp arguments) (coerce arguments 'vector))
        (t (vector arguments))))

(defun codemode-arg (arguments index)
  (let ((vector (codemode-arguments arguments)))
    (if (< index (length vector))
        (aref vector index)
        :codemode-absent)))

(defun codemode-describe-args (arguments)
  (format nil "~{~A~^, ~}"
          (map 'list #'codemode-describe-value (codemode-arguments arguments))))

(defun codemode-payload (value)
  (cond ((eq value :codemode-undefined) nil)
        ((codemode-json-null-p value) "null")
        ((null value) "false")
        (t (cadr-ai::stringify-json value))))

(defun codemode-script-value (tool is-error text structured)
  (if (and tool (cadr-ai::tool-output-schema tool) structured)
      structured
      (if is-error
          (error "Tool \"~A\" failed~@[~%~A~]"
                 (cadr-ai:tool-name tool)
                 (and (stringp text) (plusp (length text)) text))
          (or text ""))))

(defun codemode-tool-result-value (tool outcome)
  (let ((result (cadr-agent::nested-tool-call-outcome-result outcome)))
    (codemode-script-value
     tool
     (cadr-agent::nested-tool-call-outcome-is-error outcome)
     (and result (codemode-text-of (cadr-ai:tool-result-message-content result)))
     (and result (cadr-ai:tool-result-message-structured-content result)))))

(defun codemode-executor-value (tool arguments)
  (let ((value (funcall (cadr-ai:tool-executor tool) "codemode" arguments)))
    (if (typep value 'cadr-ai:tool-result-message)
        (codemode-script-value
         tool
         (cadr-ai:tool-result-message-is-error value)
         (codemode-text-of (cadr-ai:tool-result-message-content value))
         (cadr-ai:tool-result-message-structured-content value))
        value)))

(defun codemode-find-tool (agent name)
  (find name (cadr-agent::agent-callable-tools agent)
        :key #'cadr-ai:tool-name :test #'string=))

(defun codemode-execute-named-tool (context tool arguments)
  (let ((outcome (cadr-agent:extension-context-execute-tool
                  context (cadr-ai:tool-name tool) arguments)))
    (codemode-tool-result-value tool outcome)))

(defun codemode-store-json (context)
  (let ((store (cadr-ai::json-object))
        (session (and context (cadr-agent:extension-context-session context))))
    (when session
      (dolist (entry (cadr-agent::session-path-entries session))
        (when (and (eq (cadr-agent:session-entry-type entry) :custom)
                   (string= (cadr-agent:session-entry-custom-type entry)
                            +codemode-store-type+)
                   (hash-table-p (cadr-agent:session-entry-data entry)))
          (let ((data (cadr-agent:session-entry-data entry)))
            (let ((deleted (gethash "delete" data)))
              (when (vectorp deleted)
                (loop for key across deleted
                      when (stringp key)
                      do (remhash key store))))
            (let ((set (gethash "set" data)))
              (when (hash-table-p set)
                (maphash (lambda (key value)
                           (when (stringp key)
                             (setf (gethash key store)
                                   (cadr-ai::stringify-json value))))
                         set)))))))
    (cadr-ai::stringify-json store)))

(defun codemode-parse-writes (json)
  (let ((entries (cadr-ai::parse-json json))
        (set (cadr-ai::json-object))
        (deleted nil))
    (unless (vectorp entries)
      (error "store writes are not an array"))
    (loop for entry across entries
          do (unless (and (vectorp entry) (plusp (length entry))
                          (stringp (aref entry 0))
                          (or (= (length entry) 1)
                              (and (= (length entry) 2)
                                   (stringp (aref entry 1)))))
               (error "store writes contain a malformed entry"))
             (if (= (length entry) 1)
                 (push (aref entry 0) deleted)
                 (setf (gethash (aref entry 0) set)
                       (cadr-ai::parse-json (aref entry 1)))))
    (values set (coerce (nreverse deleted) 'vector))))

(defun codemode-append-store (api set deleted)
  (when (or (plusp (hash-table-count set)) (plusp (length deleted)))
    (let ((data (cadr-ai::json-object "set" set "delete" deleted)))
      (when api
        (cadr-agent:extension-api-append-entry api +codemode-store-type+ data)))))

(defun codemode-with-model-slot (function)
  (sb-thread:with-mutex (*codemode-model-lock*)
    (loop while (>= *codemode-model-in-flight* 4)
          do (sb-thread:condition-wait *codemode-model-wait* *codemode-model-lock*))
    (incf *codemode-model-in-flight*))
  (unwind-protect (funcall function)
    (sb-thread:with-mutex (*codemode-model-lock*)
      (decf *codemode-model-in-flight*)
      (sb-thread:condition-broadcast *codemode-model-wait*))))

(defun codemode-to-model-type (value)
  (if (and (stringp value)
           (member value '("chat" "image" "classifier") :test #'string=))
      value
      (error "Unknown model type ~A. Use \"chat\", \"image\", or \"classifier\"."
             (codemode-shown value))))

(defun codemode-provider-keyword (name)
  (intern (string-upcase name) :keyword))

(defun codemode-wire-name (value)
  (cond ((stringp value) value)
        ((symbolp value) (string-downcase (symbol-name value)))
        (t "")))

(defun codemode-input-names (input)
  (mapcar (lambda (item)
            (string-downcase
             (if (symbolp item) (symbol-name item) (princ-to-string item))))
          (or input nil)))

(defun codemode-resolved-chat (metadata)
  (make-codemode-resolved-model
   :type "chat"
   :provider (codemode-wire-name (cadr-ai::model-metadata-provider metadata))
   :id (cadr-ai::model-metadata-id metadata)
   :name (cadr-ai::model-metadata-name metadata)
   :api (codemode-wire-name (cadr-ai::model-metadata-api metadata))
   :base-url (cadr-ai::model-metadata-base-url metadata)
   :input (if (cadr-ai::model-metadata-supports-images-p metadata)
              '("text" "image")
              '("text"))
   :context-window (cadr-ai::model-metadata-context-window metadata)
   :source metadata))

(defun codemode-resolved-image (model)
  (make-codemode-resolved-model
   :type "image"
   :provider (codemode-wire-name (cadr-ai::image-model-provider model))
   :id (cadr-ai::image-model-id model)
   :name (cadr-ai::image-model-name model)
   :api (codemode-wire-name (cadr-ai::image-model-api model))
   :base-url (cadr-ai::image-model-base-url model)
   :input (codemode-input-names (cadr-ai::image-model-input model))
   :source model))

(defun codemode-resolved-classifier (model)
  (make-codemode-resolved-model
   :type "classifier"
   :provider (codemode-wire-name (cadr-ai::classifier-model-provider model))
   :id (cadr-ai::classifier-model-id model)
   :name (cadr-ai::classifier-model-name model)
   :api (codemode-wire-name (cadr-ai::classifier-model-api model))
   :base-url (cadr-ai::classifier-model-base-url model)
   :input (codemode-input-names (cadr-ai::classifier-model-input model))
   :context-window (cadr-ai::classifier-model-context-window model)
   :source model))

(defun codemode-catalog-models (type provider)
  (let ((keyword (and provider (codemode-provider-keyword provider))))
    (cond
      ((string= type "chat")
       (mapcar #'codemode-resolved-chat (cadr-ai:list-model-metadata keyword)))
      ((string= type "image")
       (mapcar #'codemode-resolved-image (cadr-ai:list-image-models keyword)))
      ((string= type "classifier")
       (mapcar #'codemode-resolved-classifier
               (cadr-ai:list-classifier-models keyword)))
      (t nil))))

(defun codemode-extra-models ()
  (let ((backend *codemode-model-runtime*))
    (if (typep backend 'codemode-model-backend)
        (codemode-model-backend-models backend)
        nil)))

(defun codemode-models-of-type (type provider)
  (remove-if-not
   (lambda (model)
     (and (string= (codemode-resolved-model-type model) type)
          (or (null provider)
              (string= (codemode-resolved-model-provider model) provider))))
   (append (codemode-catalog-models type provider) (codemode-extra-models))))

(defun codemode-find-model (type provider id)
  (find-if (lambda (model)
             (and (string= (codemode-resolved-model-provider model) provider)
                  (string= (codemode-resolved-model-id model) id)))
           (codemode-models-of-type type provider)))

(defun codemode-model-info (model)
  (let ((info (cadr-ai::json-object
               "provider" (codemode-resolved-model-provider model)
               "id" (codemode-resolved-model-id model)
               "name" (codemode-resolved-model-name model)
               "api" (codemode-resolved-model-api model)
               "baseUrl" (codemode-resolved-model-base-url model)
               "input" (coerce (codemode-resolved-model-input model) 'vector))))
    (when (codemode-resolved-model-context-window model)
      (setf (gethash "contextWindow" info)
            (codemode-resolved-model-context-window model)))
    info))

(defun codemode-provider-available-p (provider)
  (let ((backend *codemode-model-runtime*))
    (or (and (typep backend 'codemode-model-backend)
             (member provider
                     (codemode-model-backend-available-providers backend)
                     :test #'string=))
        (let ((registry *active-native-model-registry*))
          (and registry
               (model-registry-authentication-status
                registry (codemode-provider-keyword provider)))))))

(defun codemode-list-hint (type)
  (format nil "List the ~A models you can use with models.getAvailableOfType(\"~A\")."
          type type))

(defun codemode-model-reference-p (value)
  (and (codemode-object-p value)
       (stringp (codemode-field value "provider"))
       (stringp (codemode-field value "id"))))

(defun codemode-require-model (name type given)
  (unless (codemode-model-reference-p given)
    (error "~A() expects ~A model as its first argument, got ~A.~A ~A"
           name
           (codemode-with-article type)
           (codemode-describe-value given)
           (if (or (eq given :codemode-absent) (codemode-json-null-p given))
               " models.getModelOfType() returns undefined for an unknown provider or id."
               "")
           (codemode-list-hint type)))
  (let* ((provider (codemode-field given "provider"))
         (id (codemode-field given "id"))
         (resolved (codemode-find-model type provider id)))
    (unless resolved
      (let ((actual (find-if (lambda (other)
                               (and (not (string= other type))
                                    (codemode-find-model other provider id)))
                             '("chat" "image" "classifier"))))
        (if actual
            (error "\"~A/~A\" is ~A model, not ~A model. ~A"
                   provider id
                   (codemode-with-article actual)
                   (codemode-with-article type)
                   (codemode-list-hint type))
            (error "Unknown ~A model \"~A/~A\". ~A"
                   type provider id
                   (codemode-list-hint type)))))
    resolved))

(defun codemode-string-values-p (value)
  (let ((items (cond
                 ((vectorp value) (coerce value 'list))
                 ((codemode-object-p value)
                  (mapcar (lambda (key) (codemode-field value key))
                          (codemode-object-keys value)))
                 (t nil))))
    (and items (every #'stringp items))))

(defun codemode-classify-fail (problem)
  (error "models.classify() ~A. Expected context: ~A. See \"Classify\" in ~A."
         problem +codemode-classifier-shape+ (codemode-docs-path)))

(defun codemode-check-question (id question fail)
  (let ((at (format nil "context.questions.~A" id)))
    (unless (codemode-object-p question)
      (funcall fail (format nil "~A must be a question object, got ~A"
                            at (codemode-describe-value question))))
    (let ((type (codemode-field question "type"))
          (instructions (codemode-field question "instructions"))
          (criteria (codemode-field question "criteria")))
      (unless (stringp instructions)
        (funcall fail (format nil "~A.instructions must be a string" at)))
      (cond
        ((equal type "choice")
         (unless (and (codemode-object-p criteria)
                      (not (vectorp criteria))
                      (codemode-string-values-p criteria))
           (funcall fail
                    (format nil "~A is a \"choice\" question, so criteria must map each label to its meaning"
                            at))))
        ((equal type "score")
         (unless (and (vectorp criteria) (codemode-string-values-p criteria))
           (funcall fail
                    (format nil "~A is a \"score\" question, so criteria must list the levels as strings, lowest first"
                            at))))
        ((equal type "bool")
         (unless (and (stringp (codemode-field criteria "true"))
                      (stringp (codemode-field criteria "false")))
           (funcall fail
                    (format nil "~A is a \"bool\" question, so criteria must be { true: string, false: string }"
                            at))))
        (t (funcall fail
                    (format nil "~A.type must be \"choice\", \"score\", or \"bool\", got ~A"
                            at (codemode-shown type))))))))

(defun codemode-check-classifier-context (context)
  (unless (codemode-object-p context)
    (codemode-classify-fail
     (format nil "expects a context object as its second argument, got ~A"
             (codemode-describe-value context))))
  (let ((state (codemode-field context "state"))
        (images (codemode-field context "images"))
        (questions (codemode-field context "questions")))
    (unless (codemode-object-p state)
      (codemode-classify-fail
       (format nil "context.state must be an object, got ~A"
               (codemode-describe-value state))))
    (unless (eq images :codemode-absent)
      (unless (vectorp images)
        (codemode-classify-fail
         (format nil "context.images must be an array, got ~A"
                 (codemode-describe-value images))))
      (loop for image across images
            for index from 0
            unless (and (codemode-object-p image)
                        (equal (codemode-field image "type") "image")
                        (stringp (codemode-field image "data"))
                        (stringp (codemode-field image "mimeType")))
              do (codemode-classify-fail
                  (format nil "context.images[~A] must be an image block, got ~A"
                          index (codemode-describe-value image)))))
    (unless (and (codemode-object-p questions)
                 (codemode-object-keys questions))
      (codemode-classify-fail
       (format nil "context.questions must map question IDs to questions, got ~A"
               (codemode-describe-value questions))))
    (dolist (id (codemode-object-keys questions))
      (codemode-check-question id (codemode-field questions id)
                               #'codemode-classify-fail)))
  context)

(defun codemode-images-fail (problem)
  (error "models.generateImages() ~A. Expected context: ~A. See \"Generate images\" in ~A."
         problem +codemode-images-shape+ (codemode-docs-path)))

(defun codemode-check-images-context (context)
  (unless (codemode-object-p context)
    (codemode-images-fail
     (format nil "expects a context object as its second argument, got ~A"
             (codemode-describe-value context))))
  (let ((input (codemode-field context "input")))
    (unless (and (vectorp input) (plusp (length input)))
      (codemode-images-fail
       (format nil "context.input must be a non-empty array of blocks, got ~A"
               (codemode-describe-value input))))
    (loop for block across input
          for index from 0
          unless (or (and (codemode-object-p block)
                          (equal (codemode-field block "type") "text")
                          (stringp (codemode-field block "text")))
                     (and (codemode-object-p block)
                          (equal (codemode-field block "type") "image")
                          (stringp (codemode-field block "data"))
                          (stringp (codemode-field block "mimeType"))))
            do (codemode-images-fail
                (format nil "context.input[~A] must be a text or image block, got ~A"
                        index (codemode-describe-value block)))))
  context)

(defun codemode-as-hash (value)
  (cond
    ((hash-table-p value) value)
    ((cadr-ai::json-object-pairs-p value)
     (let ((table (cadr-ai::json-object)))
       (loop for (key item) on (cdr value) by #'cddr
             when (stringp key)
               do (setf (gethash key table) (codemode-as-hash item)))
       table))
    ((vectorp value) (map 'vector #'codemode-as-hash value))
    (t value)))

(defun codemode-content-block (block)
  (let ((type (codemode-field block "type")))
    (cond
      ((equal type "image")
       (cadr-ai:make-image-content
        :data (codemode-field block "data")
        :mime-type (codemode-field block "mimeType")))
      (t (cadr-ai:make-text-content :text (or (codemode-field block "text") ""))))))

(defun codemode-stop-name (reason)
  (cond ((or (eq reason :stop) (equal reason "stop")) "stop")
        ((or (eq reason :aborted) (equal reason "aborted")) "aborted")
        (t "error")))

(defun codemode-classifier-error (model message)
  (cadr-ai::json-object
   "api" (codemode-resolved-model-api model)
   "provider" (codemode-resolved-model-provider model)
   "model" (codemode-resolved-model-id model)
   "answers" (cadr-ai::json-object)
   "stopReason" "error"
   "errorMessage" message))

(defun codemode-image-error (model message)
  (cadr-ai::json-object
   "api" (codemode-resolved-model-api model)
   "provider" (codemode-resolved-model-provider model)
   "model" (codemode-resolved-model-id model)
   "output" #()
   "stopReason" "error"
   "errorMessage" message))

(defun codemode-classifier-json (result)
  (let ((object (cadr-ai::json-object
                 "api" (codemode-wire-name (cadr-ai::classifier-result-api result))
                 "provider" (codemode-wire-name (cadr-ai::classifier-result-provider result))
                 "model" (cadr-ai::classifier-result-model result)
                 "answers" (cadr-ai::classifier-result-answers result)
                 "stopReason" (codemode-stop-name
                               (cadr-ai::classifier-result-stop-reason result)))))
    (when (cadr-ai::classifier-result-error-message result)
      (setf (gethash "errorMessage" object)
            (cadr-ai::classifier-result-error-message result)))
    object))

(defun codemode-image-json (result)
  (let ((object (cadr-ai::json-object
                 "api" (codemode-wire-name (cadr-ai::assistant-images-api result))
                 "provider" (codemode-wire-name (cadr-ai::assistant-images-provider result))
                 "model" (cadr-ai::assistant-images-model result)
                 "output" (coerce
                           (mapcar #'codemode-output-block
                                   (cadr-ai::assistant-images-output result))
                           'vector)
                 "stopReason" (codemode-stop-name
                               (cadr-ai::assistant-images-stop-reason result)))))
    (when (cadr-ai::assistant-images-error-message result)
      (setf (gethash "errorMessage" object)
            (cadr-ai::assistant-images-error-message result)))
    object))

(defun codemode-output-block (block)
  (cond
    ((typep block 'cadr-ai:image-content)
     (cadr-ai::json-object
      "type" "image"
      "data" (cadr-ai:image-content-data block)
      "mimeType" (cadr-ai:image-content-mime-type block)))
    ((typep block 'cadr-ai:text-content)
     (cadr-ai::json-object "type" "text" "text" (cadr-ai:text-content-text block)))
    ((hash-table-p block) block)
    (t (cadr-ai::json-object "type" "text" "text" (princ-to-string block)))))

(defun codemode-has-classifier-images-p (context)
  (let ((images (codemode-field context "images")))
    (and (vectorp images) (plusp (length images)))))

(defun codemode-invoke-classify (model context)
  (when (and (codemode-has-classifier-images-p context)
             (not (member "image" (codemode-resolved-model-input model)
                          :test #'string=)))
    (return-from codemode-invoke-classify
      (codemode-classifier-error
       model
       (format nil "Model ~A/~A does not accept image input"
               (codemode-resolved-model-provider model)
               (codemode-resolved-model-id model)))))
  (let ((backend *codemode-model-runtime*))
    (cond
      ((and (typep backend 'codemode-model-backend)
            (codemode-model-backend-classify-function backend))
       (funcall (codemode-model-backend-classify-function backend) model context))
      ((typep (codemode-resolved-model-source model) 'cadr-ai:classifier-model)
       (handler-case
           (codemode-classifier-json
            (cadr-ai:classify-model
             (codemode-resolved-model-source model)
             (cadr-ai:make-classifier-context
              :state (codemode-as-hash (codemode-field context "state"))
              :questions (codemode-as-hash (codemode-field context "questions"))
              :images (let ((images (codemode-field context "images")))
                        (if (vectorp images)
                            (loop for block across images
                                  collect (codemode-content-block block))
                            nil)))))
         (error (condition)
           (codemode-classifier-error model (princ-to-string condition)))))
      (t (codemode-classifier-error
          model
          (format nil "Provider ~A does not support classification"
                  (codemode-resolved-model-provider model)))))))

(defun codemode-invoke-images (model context)
  (let ((backend *codemode-model-runtime*))
    (cond
      ((and (typep backend 'codemode-model-backend)
            (codemode-model-backend-images-function backend))
       (funcall (codemode-model-backend-images-function backend) model context))
      ((typep (codemode-resolved-model-source model) 'cadr-ai:image-model)
       (handler-case
           (codemode-image-json
            (cadr-ai:generate-images
             (codemode-resolved-model-source model)
             (cadr-ai:make-images-context
              :input (loop for block across (codemode-field context "input")
                           collect (codemode-content-block block)))))
         (error (condition)
           (codemode-image-error model (princ-to-string condition)))))
      (t (codemode-image-error
          model
          (format nil "Provider ~A does not support image generation"
                  (codemode-resolved-model-provider model)))))))

(defun codemode-truncate-text (text max)
  (if (or (not (stringp text)) (<= (length text) max))
      text
      (concatenate 'string (subseq text 0 (- max 3)) "...")))

(defun codemode-model-status (value)
  (if (hash-table-p value)
      (let ((reason (gethash "stopReason" value)))
        (cond ((equal reason "stop") "ok")
              ((equal reason "aborted") "cancelled")
              (t "error")))
      "ok"))

(defun codemode-model-call (name arguments)
  (cond
    ((string= name "models.getModelsOfType")
     (let ((type (codemode-to-model-type (codemode-arg arguments 0)))
           (provider (codemode-arg arguments 1)))
       (unless (or (eq provider :codemode-absent)
                   (codemode-json-null-p provider)
                   (stringp provider))
         (error "provider must be a string"))
       (map 'vector #'codemode-model-info
            (codemode-models-of-type
             type (if (stringp provider) provider nil)))))
    ((string= name "models.getAvailableOfType")
     (let ((type (codemode-to-model-type (codemode-arg arguments 0)))
           (provider (codemode-arg arguments 1)))
       (unless (or (eq provider :codemode-absent)
                   (codemode-json-null-p provider)
                   (stringp provider))
         (error "provider must be a string"))
       (map 'vector #'codemode-model-info
            (remove-if-not
             (lambda (model)
               (codemode-provider-available-p
                (codemode-resolved-model-provider model)))
             (codemode-models-of-type
              type (if (stringp provider) provider nil))))))
    ((string= name "models.getModelOfType")
     (let ((type (codemode-to-model-type (codemode-arg arguments 0)))
           (provider (codemode-arg arguments 1))
           (id (codemode-arg arguments 2)))
       (unless (and (stringp provider) (stringp id))
         (error "models.getModelOfType(type, provider, id) expects three strings, got (~A). The provider and the id are separate arguments, for example models.getModelOfType(\"classifier\", \"typesafe\", \"jev-latest\")."
                (codemode-describe-args arguments)))
       (let ((model (codemode-find-model type provider id)))
         (if model (codemode-model-info model) :codemode-undefined))))
    ((or (string= name "models.classify") (string= name "models.generateImages"))
     (let* ((type (if (string= name "models.classify") "classifier" "image"))
            (resolved (codemode-require-model
                       name type (codemode-arg arguments 0)))
            (context (if (string= type "classifier")
                         (codemode-check-classifier-context (codemode-arg arguments 1))
                         (codemode-check-images-context (codemode-arg arguments 1)))))
       (codemode-with-model-slot
        (lambda ()
          (if (string= type "classifier")
              (codemode-invoke-classify resolved context)
              (codemode-invoke-images resolved context))))))
    (t (error "Unknown model type. Use \"chat\", \"image\", or \"classifier\"."))))

(defun codemode-globals-json ()
  (cadr-ai::stringify-json
   (vector (cadr-ai::json-object "name" "searchTools" "spread" t)
           (cadr-ai::json-object "name" "describeTool" "spread" t)
           (cadr-ai::json-object "name" "describeNamespace" "spread" t)
           (cadr-ai::json-object "name" "models.getModelsOfType" "spread" t)
           (cadr-ai::json-object "name" "models.getAvailableOfType" "spread" t)
           (cadr-ai::json-object "name" "models.getModelOfType" "spread" t)
           (cadr-ai::json-object "name" "models.classify" "spread" t)
           (cadr-ai::json-object "name" "models.generateImages" "spread" t))))

(defun codemode-tools-json (tools)
  (cadr-ai::stringify-json
   (coerce
    (mapcar (lambda (tool)
              (cadr-ai::json-object
               "name" (cadr-ai:tool-name tool)
               "jsName" (codemode-identifier (cadr-ai:tool-name tool))
               "description" (codemode-tool-sample
                              (cadr-ai:tool-name tool)
                              (cadr-ai:tool-description tool)
                              (cadr-ai:tool-parameters tool))))
            tools)
    'vector)))

(defun codemode-split (text separator)
  (let ((parts nil)
        (start 0)
        (width (length separator)))
    (loop for pos = (search separator text :start2 start)
          do (push (subseq text start (or pos (length text))) parts)
             (unless pos (return (nreverse parts)))
             (setf start (+ pos width)))))

(defun codemode-implied-namespace (tool-name)
  (let ((parts (codemode-split tool-name "__")))
    (when (and (>= (length parts) 3)
               (string= (first parts) "mcp")
               (plusp (length (second parts))))
      (make-codemode-namespace
       :name (format nil "mcp__~A" (second parts))
       :aliases (list (second parts))))))

(defun codemode-tool-namespace (tool-name)
  (or (find-if (lambda (namespace)
                 (member tool-name (codemode-namespace-tool-names namespace)
                         :test #'string=))
               *codemode-tool-namespaces*)
      (codemode-implied-namespace tool-name)))

(defun codemode-namespace-named-p (namespace query)
  (some (lambda (name)
          (or (string= name query)
              (string= (codemode-identifier name) (codemode-identifier query))))
        (cons (codemode-namespace-name namespace)
              (codemode-namespace-aliases namespace))))

(defun codemode-namespace-payload (namespace names)
  (let ((pairs (list "name" (codemode-namespace-name namespace))))
    (when (and (stringp (codemode-namespace-description namespace))
               (plusp (length (codemode-namespace-description namespace))))
      (setf pairs (append pairs
                          (list "description"
                                (codemode-namespace-description namespace)))))
    (when (and (stringp (codemode-namespace-instructions namespace))
               (plusp (length (codemode-namespace-instructions namespace))))
      (setf pairs (append pairs
                          (list "instructions"
                                (codemode-namespace-instructions namespace)))))
    (apply #'cadr-ai::json-object
           (append pairs (list "tools" (coerce names 'vector))))))

(defun codemode-search-limit (options)
  (let ((limit (codemode-field options "limit")))
    (cond ((or (eq limit :codemode-absent) (codemode-json-null-p limit))
           +codemode-search-limit+)
          ((and (integerp limit) (plusp limit)) limit)
          (t (error "searchTools() limit must be a positive integer")))))

(defun codemode-search-namespace (options)
  (let ((namespace (codemode-field options "namespace")))
    (cond ((or (eq namespace :codemode-absent) (codemode-json-null-p namespace))
           nil)
          ((not (stringp namespace))
           (error "searchTools() namespace must be a string"))
          ((zerop (length namespace)) nil)
          (t namespace))))

(defun codemode-discovery (tools name arguments)
  (let ((args (codemode-arguments arguments)))
    (cond
      ((string= name "describeTool")
       (let ((wanted (if (plusp (length args)) (aref args 0) :codemode-absent)))
         (unless (stringp wanted)
           (error "describeTool() expects a tool name"))
         (let ((tool (find-if (lambda (tool)
                                (or (string= (cadr-ai:tool-name tool) wanted)
                                    (string= (codemode-identifier
                                              (cadr-ai:tool-name tool))
                                             wanted)))
                              tools)))
           (if tool
               (codemode-tool-sample (cadr-ai:tool-name tool)
                                     (cadr-ai:tool-description tool)
                                     (cadr-ai:tool-parameters tool))
               :codemode-undefined))))
      ((string= name "searchTools")
       (let ((query (if (plusp (length args)) (aref args 0) :codemode-absent)))
         (unless (stringp query)
           (error "searchTools() expects a query string"))
         (let* ((options (if (> (length args) 1) (aref args 1) nil))
                (limit (codemode-search-limit options))
                (namespace (codemode-search-namespace options))
                (pool (if namespace
                          (remove-if-not
                           (lambda (tool)
                             (let ((tool-namespace
                                     (codemode-tool-namespace
                                      (cadr-ai:tool-name tool))))
                               (and tool-namespace
                                    (codemode-namespace-named-p
                                     tool-namespace namespace))))
                           tools)
                          tools))
                (documents
                  (mapcar
                   (lambda (tool)
                     (cadr-agent:tool-search-document
                      (list :name (cadr-ai:tool-name tool)
                            :description (cadr-ai:tool-description tool)
                            :parameters (cadr-ai:tool-parameters tool))
                      (let ((tool-namespace
                              (codemode-tool-namespace (cadr-ai:tool-name tool))))
                        (when tool-namespace
                          (list :name (codemode-namespace-name tool-namespace)
                                :description (or (codemode-namespace-description
                                                  tool-namespace)
                                                 "")
                                :instructions (or (codemode-namespace-instructions
                                                   tool-namespace)
                                                  ""))))))
                   pool))
                (ranked (cadr-agent:tool-search-rank query documents limit)))
           (map 'vector
                (lambda (match)
                  (let ((tool (find (cadr-agent:tool-search-match-name match)
                                    pool :key #'cadr-ai:tool-name :test #'string=)))
                    (cadr-ai::json-object
                     "name" (codemode-identifier (cadr-ai:tool-name tool))
                     "description" (codemode-tool-sample
                                    (cadr-ai:tool-name tool)
                                    (cadr-ai:tool-description tool)
                                    (cadr-ai:tool-parameters tool)))))
                ranked))))
      ((string= name "describeNamespace")
       (let ((wanted (if (plusp (length args)) (aref args 0) :codemode-absent)))
         (unless (stringp wanted)
           (error "describeNamespace() expects a namespace name"))
         (let ((namespace nil)
               (names nil))
           (dolist (tool tools)
             (let ((tool-namespace (codemode-tool-namespace (cadr-ai:tool-name tool))))
               (when (and tool-namespace
                          (codemode-namespace-named-p tool-namespace wanted))
                 (unless namespace (setf namespace tool-namespace))
                 (push (codemode-identifier (cadr-ai:tool-name tool)) names))))
           (if namespace
               (codemode-namespace-payload namespace (nreverse names))
               :codemode-undefined))))
      (t (error "Unknown global \"~A\"" name)))))

(defun codemode-image-extension (mime)
  (or (cdr (assoc mime '(("image/png" . ".png")
                         ("image/jpeg" . ".jpg")
                         ("image/gif" . ".gif")
                         ("image/webp" . ".webp"))
                  :test #'equal))
      (error "No file extension for image type ~A" mime)))

(defun codemode-image-label (data mime labels)
  (or (gethash data labels)
      (let* ((bytes (decode-base64-bytes data))
             (kind (format nil "~A, ~A"
                           mime
                           (cadr-agent:format-size (if bytes (length bytes) 0))))
             (extension (codemode-image-extension mime))
             (label (handler-case
                        (progn
                          (unless bytes (error "invalid base64 image data"))
                          (format nil "[Image saved to ~A (~A)]"
                                  (write-output-file "pi-codemode" extension bytes)
                                  kind))
                      (error (condition)
                        (format nil "[Image (~A) could not be saved: ~A]"
                                kind (princ-to-string condition))))))
        (setf (gethash data labels) label))))

(defun codemode-save-images (blocks)
  (let ((labels (make-hash-table :test #'equal)))
    (loop for block in blocks
          append (if (and (consp block) (eq (first block) :image))
                     (list (cadr-ai:make-text-content
                            :text (codemode-image-label
                                   (second block) (third block) labels))
                           (cadr-ai:make-image-content
                            :data (second block)
                            :mime-type (or (third block) "")))
                     (list block)))))

(defun codemode-format-output (items)
  (let* ((texts (count-if (lambda (item) (eq (first item) :text)) items))
         (index 0)
         (console nil)
         (blocks nil))
    (dolist (item items)
      (case (first item)
        (:text
         (incf index)
         (push (cadr-ai:make-text-content
                :text (if (> texts 1)
                          (format nil "==> text ~A/~A <==~%~A" index texts (second item))
                          (second item)))
               blocks))
        (:console (push (second item) console))
        (:image (push item blocks))))
    (when console
      (push (cadr-ai:make-text-content
             :text (format nil "<console_output>~%~{~A~%~}</console_output>"
                           (nreverse console)))
            blocks))
    (nreverse blocks)))

(defun codemode-join-text (blocks)
  (let ((parts nil)
        (joined nil)
        (last ""))
    (labels ((flush ()
               (when parts
                 (push (cadr-ai:make-text-content
                        :text (format nil "~{~A~}" (nreverse parts)))
                       joined)
                 (setf parts nil last ""))))
      (dolist (block blocks)
        (if (typep block 'cadr-ai:text-content)
            (let ((text (cadr-ai:text-content-text block)))
              (when (and (plusp (length last))
                         (not (char= (char last (1- (length last))) #\Newline)))
                (push (string #\Newline) parts)
                (setf last (string #\Newline)))
              (push text parts)
              (when (plusp (length text)) (setf last text)))
            (progn (flush) (push block joined))))
      (flush))
    (nreverse joined)))

(defun codemode-truncate (blocks max-tokens)
  (let* ((texts (loop for block in blocks
                      when (typep block 'cadr-ai:text-content)
                      collect (cadr-ai:text-content-text block)))
         (combined (format nil "~{~A~^~%~}" texts))
         (budget (* max-tokens +codemode-chars-per-token+)))
    (if (or (null texts) (<= (length combined) budget))
        blocks
        (let* ((head-chars (floor budget 2))
               (tail-chars (- budget head-chars))
               (removed (- (length combined) head-chars tail-chars))
               (text (format nil "Warning: truncated output (original token count: ~A)~%Total output lines: ~A~%~%~A…~A tokens truncated…~A"
                             (ceiling (length combined) +codemode-chars-per-token+)
                             (1+ (count #\Newline combined))
                             (subseq combined 0 head-chars)
                             (ceiling removed +codemode-chars-per-token+)
                             (if (plusp tail-chars)
                                 (subseq combined (- (length combined) tail-chars))
                                 "")))
               (suffix (handler-case
                           (format nil "~%~%[Full output: ~A (read with offset/limit)]"
                                   (write-output-file "pi-codemode" ".txt" combined))
                         (error (condition)
                           (format nil "~%~%[Could not save the full output: ~A]"
                                   condition)))))
          (cons (cadr-ai:make-text-content :text (concatenate 'string text suffix))
                (remove-if (lambda (block)
                             (typep block 'cadr-ai:text-content))
                           blocks))))))

(defun codemode-wall-time (started)
  (format nil "~,1F" (max 0d0 (/ (- (get-internal-real-time) started)
                                 internal-time-units-per-second))))

(defun codemode-failure (started detail calls)
  (values
   (list (cadr-ai:make-text-content
          :text (format nil "Script failed~%Wall time ~A seconds~%Output:~%"
                        (codemode-wall-time started)))
         (cadr-ai:make-text-content :text detail))
   (cadr-ai::json-object "calls" (coerce calls 'vector))
   nil nil nil t))

(defun codemode-error-text (kind message calls)
  (let ((head (case kind
                (:timeout (format nil "Script timed out: ~A" message))
                (:aborted (format nil "Script aborted: ~A" message))
                (:sandbox (format nil "Script sandbox failed: ~A" message))
                (t (or message "Error"))))
        (summary (if calls
                     (format nil "Tool calls made before the failure (they are not undone): ~{~A~^, ~}"
                             (mapcar (lambda (call)
                                       (format nil "~A (~A)"
                                               (cadr-ai::json-get call "name")
                                               (cadr-ai::json-get call "status")))
                                     calls))
                     "No tool calls were made.")))
    (format nil "~A~%~%~A" head summary)))

(defun codemode-host-arguments (name args-json)
  (unless args-json
    (return-from codemode-host-arguments nil))
  (if (or (and (stringp name) (eql 0 (search "models." name)))
          (member name '("searchTools" "describeTool" "describeNamespace")
                  :test #'string=))
      (codemode-parse-ordered args-json)
      (cadr-ai::parse-json args-json)))

(defun codemode-handle-call (context tools call generated)
  (destructuring-bind (kind id target name args-json) call
    (declare (ignore kind id))
    (handler-case
        (let ((arguments (codemode-host-arguments name args-json)))
          (cond
            ((string= target "tool")
             (let* ((tool (find name tools :key #'cadr-ai:tool-name :test #'string=))
                    (value (cond
                             ((and context tool)
                              (codemode-execute-named-tool context tool arguments))
                             ((and tool (cadr-ai:tool-executor tool))
                              (codemode-executor-value tool arguments))
                             (t (error "Unknown tool \"~A\"" name)))))
               (list t (codemode-payload value))))
            ((and (stringp name) (eql 0 (search "models." name)))
             (let ((value (codemode-model-call name arguments)))
               (when (and (string= name "models.generateImages")
                          (hash-table-p value))
                 (let ((output (gethash "output" value)))
                   (when (vectorp output)
                     (incf (car generated)
                           (count-if (lambda (block)
                                       (and (hash-table-p block)
                                            (string= (gethash "type" block) "image")))
                                     output)))))
               (if (member name '("models.classify" "models.generateImages")
                           :test #'string=)
                   (list t (codemode-payload value)
                         (codemode-model-status value)
                         (and (hash-table-p value)
                              (codemode-truncate-text
                               (gethash "errorMessage" value) 500)))
                   (list t (codemode-payload value)))))
            (t (list t (codemode-payload (codemode-discovery tools name arguments))))))
      (error (condition)
        (list nil (princ-to-string condition))))))

(defun codemode-aborted-p (signal)
  (and signal
       (typep signal 'cadr-agent:extension-cancellation-signal)
       (cadr-agent:extension-cancellation-aborted-p signal)))

(defun execute-codemode (api call-id arguments signal update context)
  (declare (ignore call-id update))
  (let ((started (get-internal-real-time))
        (code-text (and (hash-table-p arguments) (gethash "code" arguments))))
    (unless (stringp code-text)
      (codemode-source-error
       "Expected JavaScript source text (non-empty). Provide JS only, optionally with a first line `// @options: {\"max_output_tokens\": 1000}`."))
    (multiple-value-bind (code options) (codemode-parse-source code-text)
      (let* ((timeout (getf options :timeout-ms))
             (wait-ms (if timeout
                          (min timeout +codemode-worker-wait-ms+)
                          +codemode-worker-wait-ms+))
             (aborted (lambda () (codemode-aborted-p signal)))
             (admission (codemode-reserve-worker wait-ms aborted)))
        (unless (eq admission :reserved)
          (let ((reason (if (eq admission :aborted)
                            "Script aborted: Execution aborted"
                            (if (and timeout (<= timeout +codemode-worker-wait-ms+))
                                (format nil "Script timed out: Execution timed out after ~A ms while waiting for a free codemode worker"
                                        timeout)
                                (format nil "No codemode worker became free within ~A seconds. All ~A workers, shared by every session in this process, are held by other scripts. Retry after they finish."
                                        (floor +codemode-worker-wait-ms+ 1000)
                                        (codemode-max-workers))))))
            (return-from execute-codemode
              (codemode-failure
               started
               (format nil "Script error:~%~A~%~%The script did not start." reason)
               nil))))
        (let ((calls nil)
              (generated (list 0)))
          (unwind-protect
               (handler-case
                   (let* ((tools (or (when context
                                       (remove "codemode"
                                               (cadr-agent::agent-callable-tools
                                                (cadr-agent:extension-context-agent context))
                                               :key #'cadr-ai:tool-name :test #'string=))
                                     *codemode-script-tools*))
                          (waited (round (* 1000 (/ (- (get-internal-real-time) started)
                                                    internal-time-units-per-second))))
                          (remaining (when timeout (max 1 (- timeout waited)))))
                     (codemode-ensure-wasm)
                     (multiple-value-bind
                           (ok value writes output error-text kind)
                         (codemode-run-vm
                          code (codemode-tools-json (or tools nil))
                          (codemode-globals-json)
                          (codemode-store-json context)
                          :timeout-ms remaining
                          :aborted-p aborted
                          :on-call (lambda (call)
                                     (let ((record (cadr-ai::json-object
                                                    "name" (fourth call)
                                                    "status" "running")))
                                       (push record calls)
                                       (let ((result (codemode-handle-call
                                                      context (or tools nil) call generated)))
                                         (setf (gethash "status" record)
                                               (or (third result)
                                                   (if (first result) "ok" "error")))
                                         (when (fourth result)
                                           (setf (gethash "error" record)
                                                 (fourth result)))
                                         result))))
                       (codemode-finish-script
                        started ok value writes output error-text kind
                        (nreverse calls) (car generated) api
                        (or (getf options :max-output-tokens) 10000))))
                 (error (condition)
                   (let ((loaded *codemode-wasm-ready*))
                     (codemode-failure
                      started
                      (format nil "Script error:~%Script sandbox failed: ~A~%~%No tool calls were made."
                              (if loaded
                                  condition
                                  (format nil "Failed to load QuickJS: ~A" condition)))
                      nil))))
            (codemode-release-worker)))))))

(defun codemode-script-error-head (kind value error-text)
  (cond
    ((eq kind :timeout) (format nil "Script timed out: ~A" error-text))
    ((eq kind :aborted) (format nil "Script aborted: ~A" error-text))
    ((eq kind :sandbox) (format nil "Script sandbox failed: ~A" error-text))
    (t (or (and value
                (handler-case
                    (let ((parsed (cadr-ai::parse-json value)))
                      (when (hash-table-p parsed)
                        (or (gethash "stack" parsed)
                            (gethash "message" parsed))))
                  (error () nil)))
           value
           error-text
           "Error"))))

(defun codemode-finish-script (started ok value writes output error-text kind calls images api max-tokens)
  (let ((items (codemode-format-output output)))
    (if ok
        (progn
          (when writes
            (multiple-value-bind (set deleted) (codemode-parse-writes writes)
              (codemode-append-store api set deleted)))
          (let ((extra (codemode-value-text value)))
            (when extra
              (setf items (append items (list (cadr-ai:make-text-content :text extra)))))))
        (setf items
              (append items
                      (list (cadr-ai:make-text-content
                             :text (format nil "Script error:~%~A"
                                           (codemode-error-text
                                            nil
                                            (codemode-script-error-head kind value error-text)
                                            calls)))))))
    (when (and (plusp images)
               (not (some (lambda (item) (eq (first item) :image)) output)))
      (setf items
            (append items
                    (list (cadr-ai:make-text-content
                           :text (format nil "Note: models.generateImages() returned ~A image~A that the script did not show. Show each image block of result.output with image(block)."
                                         images (if (= images 1) "" "s")))))))
    (let ((body (codemode-join-text
                 (codemode-save-images
                  (codemode-truncate items max-tokens)))))
      (values
       (cons (cadr-ai:make-text-content
              :text (format nil "Script ~A~%Wall time ~A seconds~%Output:~%"
                            (if ok "completed" "failed")
                            (codemode-wall-time started)))
             body)
       (cadr-ai::json-object "calls" (coerce calls 'vector))
       nil nil nil (not ok)))))

(defun codemode-value-text (json)
  (when json
    (let ((value (cadr-ai::parse-json json)))
      (if (stringp value) value (cadr-ai::stringify-json value)))))

(defun codemode-load-failure (condition)
  (error "Failed to load QuickJS: ~A" condition))
