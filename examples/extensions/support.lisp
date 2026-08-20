(defparameter *example-api* (cadr-agent:current-extension-api))

(defun example-render-diff-harness-p ()
  "True when the official render-diff PTY driver is capturing this process.

   Wall-clock game loops and unseeded RANDOM are forbidden in that
   environment: key sequences are the only input. See AGENTS.md
   (screenEqual vs byte equality) and goal 20 Part D."
  (let ((ready (uiop:getenv "RENDER_DIFF_READY_PATH")))
    (and ready (plusp (length ready)))))

(defun example-object-schema (&rest required-properties)
  (let ((properties (cadr-ai::json-object)))
    (loop for (name type description) on required-properties by #'cdddr
          do
          (cadr-ai::json-put
           properties name
           (cadr-ai::json-object
            "type" type
            "description" description)))
    (cadr-ai::json-object
     "type" "object"
     "properties" properties
     "required"
     (coerce
      (loop for tail on required-properties by #'cdddr
            collect (first tail))
      'vector)
     "additionalProperties" nil)))

(defun example-event-value (event key)
  (getf (cadr-agent:extension-event-payload event) key))

(defun example-exec (program arguments &key cwd timeout-ms environment)
  (cadr-agent:extension-api-exec
   *example-api* program arguments
   :cwd cwd :timeout-ms timeout-ms :environment environment))

(defun example-exec-code (result)
  (or (getf result :exit-code) 0))

(defun example-exec-output (result)
  (or (getf result :stdout) ""))

(defun example-exec-error (result)
  (or (getf result :stderr) ""))

(defun example-http-request
    (url &key (method :get) headers body timeout-ms signal)
  (cadr-agent:extension-api-http-request
   *example-api* url
   :method method :headers headers :body body
   :timeout-ms timeout-ms :signal signal))

(defun example-unix-milliseconds ()
  (* 1000 (- (get-universal-time) 2208988800)))

(defun example-percent-encode (value)
  (with-output-to-string (output)
    (loop for octet across
          (sb-ext:string-to-octets value :external-format :utf-8)
          do
          (cond
            ((or (<= (char-code #\a) octet (char-code #\z))
                 (<= (char-code #\A) octet (char-code #\Z))
                 (<= (char-code #\0) octet (char-code #\9))
                 (member octet
                         (mapcar #'char-code '(#\* #\- #\. #\_))))
             (write-char (code-char octet) output))
            ((= octet (char-code #\Space))
             (write-char #\+ output))
            (t
             (format output "%~2,'0X" octet))))))

(defun example-percent-decode (value)
  (let ((octets
          (make-array 0 :element-type '(unsigned-byte 8)
                        :adjustable t :fill-pointer 0)))
    (loop with index = 0
          while (< index (length value))
          for character = (char value index)
          do
          (cond
            ((char= character #\+)
             (vector-push-extend (char-code #\Space) octets)
             (incf index))
            ((char= character #\%)
             (unless (< (+ index 2) (length value))
               (error "Invalid percent-encoded query value"))
             (let ((high (digit-char-p (char value (1+ index)) 16))
                   (low (digit-char-p (char value (+ index 2)) 16)))
               (unless (and high low)
                 (error "Invalid percent-encoded query value"))
               (vector-push-extend (+ (* high 16) low) octets)
               (incf index 3)))
            (t
             (loop for octet across
                   (sb-ext:string-to-octets
                    (string character) :external-format :utf-8)
                   do (vector-push-extend octet octets))
             (incf index))))
    (sb-ext:octets-to-string octets :external-format :utf-8)))

(defun example-form-encode (pairs)
  (format nil "~{~A~^&~}"
          (mapcar
           (lambda (entry)
             (format nil "~A=~A"
                     (example-percent-encode (car entry))
                     (example-percent-encode (cdr entry))))
           pairs)))

(defun example-http-json
    (url &key (method :post) headers object form timeout-ms signal)
  (let* ((body
           (cond
             (object (cadr-ai::stringify-json object))
             (form (example-form-encode form))
             (t nil)))
         (content-type
           (cond (object "application/json")
                 (form "application/x-www-form-urlencoded")
                 (t nil)))
         (result
           (example-http-request
            url :method method
            :headers
            (append
             (and content-type
                  (list (cons "Content-Type" content-type)))
             headers)
            :body body :timeout-ms timeout-ms :signal signal))
         (status (getf result :status)))
    (unless (<= 200 status 299)
      (error "Extension HTTP request returned status ~D" status))
    (cadr-ai::json-as-hash-table
     (cadr-ai::parse-json
      (sb-ext:octets-to-string
       (getf result :body) :external-format :utf-8)))))

(defun example-query-value (url name)
  (let* ((query-start (position #\? url))
         (query (and query-start (subseq url (1+ query-start)))))
    (when query
      (dolist (entry (uiop:split-string query :separator "&"))
        (let ((equals (position #\= entry)))
          (when (and equals
                     (string=
                      name
                      (example-percent-decode
                       (subseq entry 0 equals))))
            (return
              (example-percent-decode
               (subseq entry (1+ equals))))))))))

(defun example-environment-value (environment name)
  (cdr (assoc name environment :test #'string=)))

(defun example-merge-headers (base override)
  (append
   (mapcar
    (lambda (entry)
      (or (find (car entry) override :key #'car :test #'string-equal)
          entry))
    base)
   (remove-if
    (lambda (entry)
      (find (car entry) base :key #'car :test #'string-equal))
    override)))

(defun example-runtime-stream-options (options required-headers)
  (let* ((original-transform (getf options :transform-headers))
         (filtered
           (loop for (key value) on options by #'cddr
                 unless (member key
                                '(:api-key :headers :environment :auth-type
                                  :transform-headers))
                   append (list key value))))
    (append
     filtered
     (list
      :transform-headers
      (lambda (headers)
        (example-merge-headers
         (if original-transform
             (funcall original-transform headers)
             headers)
         required-headers))))))

(defun example-session-entries (context)
  (let ((session (cadr-agent:extension-context-session context)))
    (and session (cadr-agent:session-entries session))))

(defun example-session-branch (context)
  (let ((session (cadr-agent:extension-context-session context)))
    (and session
         (cadr-agent::session-path-entries session))))

(defun example-entry-role (entry)
  (let ((message (cadr-agent:session-entry-message entry)))
    (cond
      ((typep message 'cadr-ai:user-message) :user)
      ((typep message 'cadr-ai:assistant-message) :assistant)
      ((typep message 'cadr-ai:tool-result-message) :tool-result)
      (t nil))))

(defun example-entry-text (entry)
  (let ((message (cadr-agent:session-entry-message entry)))
    (cond
      ((typep message 'cadr-ai:user-message)
       (cadr-ai:user-message-content message))
      ((typep message 'cadr-ai:assistant-message)
       (with-output-to-string (output)
         (dolist (block (cadr-ai:assistant-message-content message))
           (when (typep block 'cadr-ai:text-content)
             (write-string (cadr-ai:text-content-text block) output)))))
      (t ""))))

(defun example-text-result (text &optional details)
  (values
   (list (cadr-ai:make-text-content :text text))
   details))

(defun example-tool-result-text (result)
  (if (typep result 'cadr-ai:tool-result-message)
      (with-output-to-string (output)
        (dolist (block (cadr-ai:tool-result-message-content result))
          (when (typep block 'cadr-ai:text-content)
            (write-string (cadr-ai:text-content-text block) output))))
      ""))

(defun example-assistant-text (message)
  (if (typep message 'cadr-ai:assistant-message)
      (format nil "~{~A~^~%~}"
              (loop for block in (cadr-ai:assistant-message-content message)
                    when (typep block 'cadr-ai:text-content)
                      collect (cadr-ai:text-content-text block)))
      ""))

(defun example-trim (text)
  (string-trim '(#\Space #\Tab #\Newline #\Return) text))

(defun example-theme-fg (theme token text)
  "Apply the TUI theme-runtime :fg callback, or return TEXT unchanged."
  (let ((fn (and (listp theme) (getf theme :fg))))
    (if (functionp fn)
        (funcall fn token (or text ""))
        (or text ""))))

(defun example-theme-bg (theme token text)
  "Apply the TUI theme-runtime :bg callback, or return TEXT unchanged."
  (let ((fn (and (listp theme) (getf theme :bg))))
    (if (functionp fn)
        (funcall fn token (or text ""))
        (or text ""))))

(defun example-theme-background-function (theme token)
  "A TEXT-COMPONENT :background-function bound to THEME's TOKEN."
  (lambda (text) (example-theme-bg theme token text)))

(defun example-decode-unix-milliseconds (milliseconds)
  (decode-universal-time
   (+ (floor (or milliseconds 0) 1000) 2208988800)))

(defun example-clock-time-string (milliseconds)
  "The baseline examples print Date#toLocaleTimeString here."
  (multiple-value-bind (second minute hour)
      (example-decode-unix-milliseconds milliseconds)
    (multiple-value-bind (display-hour period)
        (cond ((zerop hour) (values 12 "AM"))
              ((< hour 12) (values hour "AM"))
              ((= hour 12) (values 12 "PM"))
              (t (values (- hour 12) "PM")))
      (format nil "~D:~2,'0D:~2,'0D ~A"
              display-hour minute second period))))

(defun example-clock-date-time-string (milliseconds)
  "The baseline examples print Date#toLocaleString here."
  (multiple-value-bind (second minute hour date month year)
      (example-decode-unix-milliseconds milliseconds)
    (declare (ignore second minute hour))
    (format nil "~D/~D/~D, ~A"
            month date year
            (example-clock-time-string milliseconds))))

(defun example-load-support () nil)

(defun example-empty-schema ()
  (cadr-ai::json-object
   "type" "object"
   "properties" (cadr-ai::json-object)
   "additionalProperties" nil))

(defun example-argument (arguments name &optional default)
  (or (and (hash-table-p arguments)
           (gethash name arguments))
      default))

(defun example-boolean (value)
  (not (member value '(nil :false :null) :test #'eq)))

(defun example-lines (&rest lines)
  (remove nil lines))

(defclass example-dialog-component (cadr-tui:component)
  ((title :initarg :title :reader example-dialog-title)
   (lines :initarg :lines :initform nil :accessor example-dialog-lines)
   (options :initarg :options :initform '("Close")
            :reader example-dialog-options)
   (selected :initform 0 :accessor example-dialog-selected)
   (done :initarg :done :reader example-dialog-done)
   (disposed-p :initform nil :accessor example-dialog-disposed-p)))

(defmethod cadr-tui:component-render
    ((component example-dialog-component) width &key focused-p)
  (declare (ignore width focused-p))
  (append
   (list (example-dialog-title component) "")
   (copy-list (example-dialog-lines component))
   (list "")
   (loop for option in (example-dialog-options component)
         for index from 0
         collect
         (format nil "~:[  ~;> ~]~A"
                 (= index (example-dialog-selected component))
                 option))))

(defmethod cadr-tui:component-handle-event
    ((component example-dialog-component) event)
  (let* ((kind (cadr-tui:input-event-kind event))
         (count (length (example-dialog-options component))))
    (case kind
      (:up
       (setf (example-dialog-selected component)
             (mod (1- (example-dialog-selected component)) count)))
      (:down
       (setf (example-dialog-selected component)
             (mod (1+ (example-dialog-selected component)) count)))
      (:enter
       (funcall (example-dialog-done component)
                (nth (example-dialog-selected component)
                     (example-dialog-options component))))
      ((:escape :cancel :interrupt)
       (funcall (example-dialog-done component) nil)))
    (values nil nil)))

(defmethod cadr-tui:component-dispose
    ((component example-dialog-component))
  (setf (example-dialog-disposed-p component) t)
  component)

(defun example-show-dialog
    (context title lines &key (options '("Close")) overlay-options)
  (cadr-agent:extension-context-custom-component
   context
   (lambda (tui theme keybindings done)
     (declare (ignore tui theme keybindings))
     (make-instance
      'example-dialog-component
      :title title :lines lines :options options :done done))
   :overlay-p t
   :overlay-options
   (or overlay-options '(:width 60 :anchor :center :margin 1))))

(defun example-with-loader (context message operation)
  (cadr-agent:extension-context-custom-component
   context
   (lambda (tui theme keybindings done)
     (declare (ignore theme keybindings))
     (let* ((loader
              (cadr-cli:make-bordered-loader-component
               tui message :cancellable-p t))
            (token (cadr-cli:bordered-loader-signal loader))
            (lock (sb-thread:make-mutex :name "cadr example loader"))
            (settled-p nil))
       (labels ((settle (value)
                  (sb-thread:with-mutex (lock)
                    (unless settled-p
                      (setf settled-p t)
                      (funcall done value)))))
         (cadr-cli:bordered-loader-set-on-abort
          loader (lambda () (settle nil)))
         (sb-thread:make-thread
          (lambda ()
            (handler-case
                (let ((value
                        (funcall
                         operation
                         (lambda ()
                           (cadr-tui:cancellation-token-aborted-p token)))))
                  (unless
                      (cadr-tui:cancellation-token-aborted-p token)
                    (settle value)))
              (condition () (settle nil))))
          :name "cadr example loader worker")
         loader)))))

(defun example-program-path (name)
  (let* ((command
           (if (uiop:os-windows-p)
               (list "where" name)
               (list "sh" "-c" "command -v -- \"$1\"" "sh" name)))
         (path
           (ignore-errors
             (example-trim
              (uiop:run-program
               command :output :string :error-output nil
               :ignore-error-status t)))))
    (or (and path (plusp (length path)) path)
        (error "Required host executable ~A is not installed" name))))

(defun example-call-program
    (name arguments &key cwd timeout-ms environment)
  (example-program-path name)
  (example-exec name arguments
                :cwd cwd :timeout-ms timeout-ms
                :environment environment))

(defun example-result (text &key details terminate-p)
  (values text details terminate-p))

(defun example-execute-tool (tool call-id arguments)
  (funcall (cadr-ai:tool-executor tool) call-id arguments))


(defclass example-editor-component (cadr-tui:component)
  ((editor
    :initform (cadr-tui:make-multiline-editor)
    :reader example-editor-inner)
   (label
    :initarg :label :initform "Extension editor"
    :accessor example-editor-label)
   (style-function
    :initarg :style-function :initform #'identity
    :reader example-editor-style-function)
   (disposed-p
    :initform nil :accessor example-editor-disposed-p)))

(defmethod cadr-tui:editor-component-text
    ((component example-editor-component))
  (cadr-tui:editor-text (example-editor-inner component)))

(defmethod cadr-tui:editor-component-set-text
    ((component example-editor-component) text)
  (cadr-tui:editor-set-text (example-editor-inner component) text)
  component)

(defmethod cadr-tui:component-render
    ((component example-editor-component) width &key focused-p)
  (multiple-value-bind (lines row column)
      (cadr-tui:render-editor
       (example-editor-inner component) width :focused-p focused-p)
    (declare (ignore row column))
    (cons
     (funcall (example-editor-style-function component)
              (example-editor-label component))
     lines)))

(defmethod cadr-tui:component-handle-event
    ((component example-editor-component) event)
  (cadr-tui:editor-handle-event (example-editor-inner component) event))

(defmethod cadr-tui:component-dispose
    ((component example-editor-component))
  (setf (example-editor-disposed-p component) t)
  component)
