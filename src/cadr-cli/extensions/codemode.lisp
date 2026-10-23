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

(defun codemode-tool-result-value (outcome)
  (let* ((result (cadr-agent::nested-tool-call-outcome-result outcome))
         (structured (and result (cadr-ai:tool-result-message-structured-content result)))
         (text (codemode-text-of (and result (cadr-ai:tool-result-message-content result)))))
    (if (cadr-agent::nested-tool-call-outcome-is-error outcome)
        (error (if (and text (plusp (length text))) text "Tool failed"))
        (or structured text ""))))

(defun codemode-find-tool (agent name)
  (find name (cadr-agent::agent-callable-tools agent)
        :key #'cadr-ai:tool-name :test #'string=))

(defun codemode-execute-named-tool (context name arguments)
  (let ((outcome (cadr-agent:extension-context-execute-tool
                  context name arguments)))
    (codemode-tool-result-value outcome)))

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

(defun codemode-model-call (name arguments)
  (let ((runtime *codemode-model-runtime*))
    (unless runtime
      (error "Unknown model type. Use \"chat\", \"image\", or \"classifier\"."))
    (let ((function (gethash name runtime)))
      (unless function
        (error "Unknown model type. Use \"chat\", \"image\", or \"classifier\"."))
      (if (member name '("classify" "generateImages") :test #'string=)
          (codemode-with-model-slot (lambda () (apply function arguments)))
          (apply function arguments)))))

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

(defun codemode-discovery (tools name arguments)
  (let ((args (if (vectorp arguments) arguments (vector arguments))))
    (cond
      ((string= name "describeTool")
       (let* ((wanted (if (plusp (length args)) (aref args 0) nil))
              (tool (and (stringp wanted)
                         (find-if (lambda (tool)
                                    (or (string= (cadr-ai:tool-name tool) wanted)
                                        (string= (codemode-identifier (cadr-ai:tool-name tool))
                                                 wanted)))
                                  tools))))
         (if tool
             (codemode-tool-sample (cadr-ai:tool-name tool)
                                   (cadr-ai:tool-description tool)
                                   (cadr-ai:tool-parameters tool))
             'null)))
      ((string= name "searchTools")
       (vector))
      ((string= name "describeNamespace")
       'null)
      (t (error "Unknown global \"~A\"" name)))))

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
                                   (write-output-file "cadr-codemode" ".txt" combined))
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

(defun codemode-handle-call (context tools call generated)
  (destructuring-bind (kind id target name args-json) call
    (declare (ignore kind id))
    (handler-case
        (let ((arguments (if args-json (cadr-ai::parse-json args-json) nil)))
          (cond
            ((string= target "tool")
             (let* ((tool (find name tools :key #'cadr-ai:tool-name :test #'string=))
                    (value (cond
                             ((and context tool)
                              (codemode-execute-named-tool context name arguments))
                             ((and tool (cadr-ai:tool-executor tool))
                              (funcall (cadr-ai:tool-executor tool) "codemode" arguments))
                             (t (error "Unknown tool \"~A\"" name)))))
               (list t (if (eq value 'null) "null" (cadr-ai::stringify-json value)))))
            ((eql 0 (search "models." name))
             (let ((value (codemode-model-call (subseq name (length "models."))
                                               (if (vectorp arguments)
                                                   (coerce arguments 'list)
                                                   (list arguments)))))
               (when (and (string= name "models.generateImages")
                          (hash-table-p value))
                 (let ((output (gethash "output" value)))
                   (when (vectorp output)
                     (incf (car generated)
                           (count-if (lambda (block)
                                       (and (hash-table-p block)
                                            (string= (gethash "type" block) "image")))
                                     output)))))
               (list t (if (eq value 'null) "null" (cadr-ai::stringify-json value)))))
            (t (let ((value (codemode-discovery tools name arguments)))
                 (list t (if (eq value 'null) "null" (cadr-ai::stringify-json value)))))))
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
                                               (if (first result) "ok" "error"))
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
    (let ((body (codemode-join-text (codemode-truncate items max-tokens))))
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
