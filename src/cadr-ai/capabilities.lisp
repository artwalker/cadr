(in-package #:cadr-ai)

;;; Stable IDs

(defun u32-multiply (left right)
  (logand #xffffffff (* (logand #xffffffff left)
                       (logand #xffffffff right))))

(defun javascript-utf16-code-units (string)
  (loop for character across string
        for code = (char-code character)
        if (<= code #xffff)
          collect code
        else
          append (let ((adjusted (- code #x10000)))
                   (list (+ #xd800 (ash adjusted -10))
                         (+ #xdc00 (logand adjusted #x3ff))))))

(defun unsigned-base36 (value)
  (let ((alphabet "0123456789abcdefghijklmnopqrstuvwxyz")
        (value (logand #xffffffff value)))
    (if (zerop value)
        "0"
        (with-output-to-string (output)
          (labels ((write-digits (number)
                     (multiple-value-bind (quotient remainder)
                         (floor number 36)
                       (when (plusp quotient)
                         (write-digits quotient))
                       (write-char (char alphabet remainder) output))))
            (write-digits value))))))

(defun short-hash (string)
  "Return the fixed-baseline two-word hash over JavaScript UTF-16 code units."
  (let ((h1 #xdeadbeef)
        (h2 #x41c6ce57))
    (dolist (unit (javascript-utf16-code-units string))
      (setf h1 (u32-multiply (logxor h1 unit) 2654435761)
            h2 (u32-multiply (logxor h2 unit) 1597334677)))
    (setf h1
          (logxor
           (u32-multiply (logxor h1 (ash h1 -16)) 2246822507)
           (u32-multiply (logxor h2 (ash h2 -13)) 3266489909)))
    (setf h2
          (logxor
           (u32-multiply (logxor h2 (ash h2 -16)) 2246822507)
           (u32-multiply (logxor h1 (ash h1 -13)) 3266489909)))
    (concatenate 'string
                 (unsigned-base36 h2)
                 (unsigned-base36 h1))))

;;; Repairable and partial JSON

(defun valid-json-escape-character-p (character)
  (and character (find character "\"\\/bfnrtu")))

(defun write-json-control-escape (character output)
  (case character
    (#\Backspace (write-string "\\b" output))
    (#\Page (write-string "\\f" output))
    (#\Newline (write-string "\\n" output))
    (#\Return (write-string "\\r" output))
    (#\Tab (write-string "\\t" output))
    (otherwise
     (format output "\\u~4,'0x" (char-code character)))))

(defun valid-unicode-escape-at-p (json index)
  (and (<= (+ index 5) (1- (length json)))
       (loop for offset from 2 to 5
             always (digit-char-p (char json (+ index offset)) 16))))

(defun repair-json (json)
  (with-output-to-string (output)
    (let ((in-string-p nil)
          (index 0))
      (loop while (< index (length json))
            for character = (char json index)
            do
            (cond
              ((not in-string-p)
               (write-char character output)
               (when (char= character #\")
                 (setf in-string-p t)))
              ((char= character #\")
               (write-char character output)
               (setf in-string-p nil))
              ((char= character #\\)
               (let ((next (and (< (1+ index) (length json))
                                (char json (1+ index)))))
                 (cond
                   ((null next)
                    (write-string "\\\\" output))
                   ((and (char= next #\u)
                         (valid-unicode-escape-at-p json index))
                    (write-string json output :start index :end (+ index 6))
                    (incf index 5))
                   ((valid-json-escape-character-p next)
                    (write-char #\\ output)
                    (write-char next output)
                    (incf index))
                   (t
                    (write-string "\\\\" output)))))
              ((< (char-code character) #x20)
               (write-json-control-escape character output))
              (t
               (write-char character output)))
            (incf index)))))

(defun parse-json-with-repair (json)
  (handler-case
      (parse-json json)
    (sse-protocol-error (original)
      (let ((repaired (repair-json json)))
        (if (string= repaired json)
            (error original)
            (parse-json repaired))))))

(defun complete-json-prefix (prefix)
  (let ((stack nil)
        (in-string-p nil)
        (escaped-p nil))
    (loop for character across prefix
          do
          (cond
            (in-string-p
             (cond
               (escaped-p (setf escaped-p nil))
               ((char= character #\\) (setf escaped-p t))
               ((char= character #\") (setf in-string-p nil))))
            ((char= character #\") (setf in-string-p t))
            ((char= character #\{) (push #\} stack))
            ((char= character #\[) (push #\] stack))
            ((or (char= character #\}) (char= character #\]))
             (unless (and stack (char= character (first stack)))
               (return-from complete-json-prefix nil))
             (pop stack))))
    (with-output-to-string (output)
      (write-string prefix output)
      (when escaped-p
        (write-char #\\ output))
      (when in-string-p
        (write-char #\" output))
      (dolist (closer stack)
        (write-char closer output)))))

(defun parse-streaming-json (partial-json)
  (when (or (null partial-json)
            (zerop (length (string-trim '(#\Space #\Tab #\Return #\Newline)
                                        partial-json))))
    (return-from parse-streaming-json (make-hash-table :test #'equal)))
  (handler-case
      (parse-json-with-repair partial-json)
    (error ()
      (let ((repaired (repair-json partial-json)))
        (loop for end from (length repaired) downto 1
              for candidate = (complete-json-prefix (subseq repaired 0 end))
              when candidate
                do (handler-case
                       (return-from parse-streaming-json
                         (parse-json candidate))
                     (error () nil))))
      (make-hash-table :test #'equal))))

;;; Producer/consumer event streams

(defclass event-stream ()
  ((queue :initform nil :accessor event-stream-queue)
   (done-p :initform nil :accessor event-stream-done-p)
   (result-ready-p :initform nil :accessor event-stream-result-ready-p)
   (result-value :initform nil :accessor event-stream-result-value)
   (complete-p :initarg :complete-p :reader event-stream-complete-p)
   (result-function :initarg :result-function :reader event-stream-result-function)
   (lock :initform (sb-thread:make-mutex :name "cadr event stream")
         :reader event-stream-lock)
   (condition :initform (sb-thread:make-waitqueue :name "cadr event stream")
              :reader event-stream-condition)))

(defun make-event-stream (&key complete-p result-function)
  (make-instance 'event-stream
                 :complete-p (or complete-p (constantly nil))
                 :result-function (or result-function #'identity)))

(defun event-stream-push (stream event)
  (sb-thread:with-mutex ((event-stream-lock stream))
    (unless (event-stream-done-p stream)
      (setf (event-stream-queue stream)
            (nconc (event-stream-queue stream) (list event)))
      (when (funcall (event-stream-complete-p stream) event)
        (setf (event-stream-done-p stream) t
              (event-stream-result-ready-p stream) t
              (event-stream-result-value stream)
              (funcall (event-stream-result-function stream) event)))
      (sb-thread:condition-broadcast (event-stream-condition stream))))
  event)

(defun event-stream-end (stream &optional (result nil result-supplied-p))
  (sb-thread:with-mutex ((event-stream-lock stream))
    (setf (event-stream-done-p stream) t)
    (when result-supplied-p
      (setf (event-stream-result-ready-p stream) t
            (event-stream-result-value stream) result))
    (sb-thread:condition-broadcast (event-stream-condition stream)))
  nil)

(defun event-stream-next (stream)
  (sb-thread:with-mutex ((event-stream-lock stream))
    (loop while (and (null (event-stream-queue stream))
                     (not (event-stream-done-p stream)))
          do (sb-thread:condition-wait
              (event-stream-condition stream)
              (event-stream-lock stream)))
    (if (event-stream-queue stream)
        (values (pop (event-stream-queue stream)) nil)
        (values nil t))))

(defun event-stream-result (stream)
  (sb-thread:with-mutex ((event-stream-lock stream))
    (loop until (event-stream-result-ready-p stream)
          do (sb-thread:condition-wait
              (event-stream-condition stream)
              (event-stream-lock stream)))
    (event-stream-result-value stream)))

;;; Deferred tools and constrained sampling

(defun normalized-tool-name (name normalizer)
  (funcall (or normalizer #'identity) name))

(defun split-deferred-tools (context enabled-p &optional normalizer)
  (let ((unique (make-hash-table :test #'equal))
        (order nil))
    (dolist (tool (context-tools context))
      (let ((name (normalized-tool-name (tool-name tool) normalizer)))
        (unless (gethash name unique)
          (setf order (append order (list name))))
        (setf (gethash name unique) tool)))
    (unless enabled-p
      (return-from split-deferred-tools
        (values (mapcar (lambda (name) (gethash name unique)) order)
                (make-hash-table :test #'equal))))
    (let ((deferred-names (make-hash-table :test #'equal))
          (used-names (make-hash-table :test #'equal)))
      (dolist (message (context-messages context))
        (cond
          ((typep message 'assistant-message)
           (dolist (block (assistant-message-content message))
             (when (typep block 'tool-call)
               (setf (gethash
                      (normalized-tool-name (tool-call-name block) normalizer)
                      used-names)
                     t))))
          ((typep message 'tool-result-message)
           (dolist (name (tool-result-message-added-tool-names message))
             (let ((normalized (normalized-tool-name name normalizer)))
               (unless (gethash normalized used-names)
                 (setf (gethash normalized deferred-names) t)))))))
      (let ((immediate nil)
            (deferred (make-hash-table :test #'equal)))
        (dolist (name order)
          (if (gethash name deferred-names)
              (setf (gethash name deferred) (gethash name unique))
              (setf immediate (append immediate (list (gethash name unique))))))
        (values immediate deferred)))))

(defun sampling-value (sampling key)
  (cond
    ((hash-table-p sampling)
     (or (gethash (string-downcase (symbol-name key)) sampling)
         (gethash key sampling)))
    ((listp sampling) (getf sampling key))
    (t nil)))

(defun sampling-type (sampling)
  (let ((type (sampling-value sampling :type)))
    (etypecase type
      (null nil)
      (keyword type)
      (string (intern (string-upcase (substitute #\- #\_ type)) :keyword)))))

(defun schema-value (schema key)
  (cond
    ((hash-table-p schema) (json-get schema key))
    ((listp schema) (getf schema (intern (string-upcase key) :keyword)))
    (t nil)))

(defun get-grammar-tool-input (tool-name arguments input-property)
  (let ((value (schema-value arguments input-property)))
    (unless (stringp value)
      (error "Grammar tool call ~S requires argument ~S to be a string."
             tool-name input-property))
    value))

(defun resolve-json-schema-strict-sampling (tool supports-strict-mode-p)
  (let ((config (tool-constrained-sampling tool)))
    (unless (eq :json-schema (sampling-type config))
      (return-from resolve-json-schema-strict-sampling nil))
    (cond
      (supports-strict-mode-p t)
      ((eq :require (sampling-value config :strict))
       (error "Tool ~S requires JSON-schema constrained sampling, but strict tools are unsupported."
              (tool-name tool)))
      (t nil))))

(defun infer-grammar-input-property (tool)
  (let* ((schema (tool-parameters tool))
         (required (schema-value schema "required"))
         (properties (schema-value schema "properties")))
    (unless (string= "object" (or (schema-value schema "type") ""))
      (error "grammar constrained sampling requires an object parameter schema"))
    (unless (and (vectorp required)
                 (= 1 (length required))
                 (stringp (aref required 0)))
      (error "grammar constrained sampling requires exactly one required string property"))
    (let* ((name (aref required 0))
           (property (schema-value properties name)))
      (unless property
        (error "grammar constrained sampling requires a properties entry for ~A" name))
      (unless (string= "string" (or (schema-value property "type") ""))
        (error "grammar constrained sampling property ~A must have type string" name))
      name)))

(defun resolve-grammar-constrained-sampling
    (tool supports-openai-grammar-tools-p)
  (let ((config (tool-constrained-sampling tool)))
    (unless (and (eq :grammar (sampling-type config))
                 supports-openai-grammar-tools-p)
      (return-from resolve-grammar-constrained-sampling nil))
    (let* ((variants (sampling-value config :variants))
           (lark (sampling-value variants :openai-lark))
           (regex (sampling-value variants :openai-regex))
           (lark-p (and (stringp lark) (plusp (length (string-trim '(#\Space) lark)))))
           (regex-p (and (stringp regex) (plusp (length (string-trim '(#\Space) regex))))))
      (unless (or lark-p regex-p)
        (error "Tool ~S cannot use grammar constrained sampling: no supported grammar variant was provided."
               (tool-name tool)))
      (handler-case
          (list :format (if lark-p :lark :regex)
                :definition (if lark-p lark regex)
                :input-property (infer-grammar-input-property tool))
        (error (condition)
          (error "Tool ~S cannot use grammar constrained sampling: ~A."
                 (tool-name tool) condition))))))

(defun create-grammar-tool-input-properties
    (tools supports-openai-grammar-tools-p)
  (let ((properties (make-hash-table :test #'equal)))
    (dolist (tool tools)
      (let ((grammar
              (resolve-grammar-constrained-sampling
               tool supports-openai-grammar-tools-p)))
        (when grammar
          (setf (gethash (tool-name tool) properties)
                (getf grammar :input-property)))))
    properties))

;;; Session-owned transport resources

(defparameter *session-resource-cleanups* nil)
(defparameter *session-resource-cleanups-lock*
  (sb-thread:make-mutex :name "cadr session resource cleanup registry"))

(defun register-session-resource-cleanup (cleanup)
  (sb-thread:with-mutex (*session-resource-cleanups-lock*)
    (pushnew cleanup *session-resource-cleanups* :test #'eq))
  (lambda ()
    (sb-thread:with-mutex (*session-resource-cleanups-lock*)
      (setf *session-resource-cleanups*
            (remove cleanup *session-resource-cleanups* :test #'eq)))
    nil))

(defun clear-session-resource-cleanups ()
  (sb-thread:with-mutex (*session-resource-cleanups-lock*)
    (setf *session-resource-cleanups* nil))
  nil)

(defun cleanup-session-resources (&optional session-id)
  (let ((cleanups
          (sb-thread:with-mutex (*session-resource-cleanups-lock*)
            (reverse (copy-list *session-resource-cleanups*))))
        (errors nil))
    (dolist (cleanup cleanups)
      (handler-case (funcall cleanup session-id)
        (error (condition) (push condition errors))))
    (when errors
      (error "Failed to cleanup session resources: ~{~A~^; ~}"
             (nreverse errors))))
  nil)

;;; HTTP proxy environment resolution

(defparameter +unsupported-proxy-protocol-message+
  "Unsupported proxy protocol. SOCKS and PAC proxy URLs are not supported; use an HTTP or HTTPS proxy URL.")

(defun proxy-environment-value (name environment)
  (or (cdr (assoc name environment :test #'string-equal))
      (uiop:getenv (string-downcase name))
      (uiop:getenv (string-upcase name))))

(defun target-url-parts (url)
  (let* ((scheme-end (search "://" url))
         (scheme (and scheme-end (string-downcase (subseq url 0 scheme-end))))
         (authority-start (and scheme-end (+ scheme-end 3)))
         (authority-end (and authority-start
                             (or (position #\/ url :start authority-start)
                                 (length url))))
         (authority (and authority-start (subseq url authority-start authority-end)))
         (colon (and authority (position #\: authority :from-end t)))
         (host (and authority (if colon (subseq authority 0 colon) authority)))
         (port (and colon (parse-integer authority :start (1+ colon) :junk-allowed t))))
    (values scheme host
            (or port (cdr (assoc scheme '(("ftp" . 21) ("gopher" . 70)
                                          ("http" . 80) ("https" . 443)
                                          ("ws" . 80) ("wss" . 443))
                                :test #'string=))))))

(defun no-proxy-match-p (host port no-proxy)
  (when (string= no-proxy "*")
    (return-from no-proxy-match-p t))
  (some
   (lambda (entry)
     (let* ((entry (string-downcase entry))
            (colon (position #\: entry :from-end t))
            (entry-port (and colon
                             (parse-integer entry :start (1+ colon)
                                            :junk-allowed t)))
            (pattern (if colon (subseq entry 0 colon) entry)))
       (and (plusp (length pattern))
            (or (null entry-port) (= entry-port port))
            (if (or (char= (char pattern 0) #\.)
                    (char= (char pattern 0) #\*))
                (uiop:string-suffix-p
                 host
                 (if (char= (char pattern 0) #\*)
                     (subseq pattern 1)
                     pattern))
                (string= pattern host)))))
   (uiop:split-string no-proxy :separator '(#\, #\Space #\Tab #\Newline))))

(defun resolve-http-proxy-url-for-target (target-url &optional environment)
  (multiple-value-bind (scheme host port)
      (target-url-parts target-url)
    (unless (and scheme host port)
      (return-from resolve-http-proxy-url-for-target nil))
    (let ((no-proxy
            (string-downcase
             (or (proxy-environment-value "NO_PROXY" environment) ""))))
      (when (and (plusp (length no-proxy))
                 (no-proxy-match-p (string-downcase host) port no-proxy))
        (return-from resolve-http-proxy-url-for-target nil)))
    (let ((proxy
            (or (proxy-environment-value
                 (format nil "~A_PROXY" (string-upcase scheme)) environment)
                (proxy-environment-value "ALL_PROXY" environment))))
      (unless (and proxy (plusp (length proxy)))
        (return-from resolve-http-proxy-url-for-target nil))
      (unless (search "://" proxy)
        (setf proxy (format nil "~A://~A" scheme proxy)))
      (let ((proxy-scheme
              (string-downcase (subseq proxy 0 (or (search "://" proxy) 0)))))
        (unless (member proxy-scheme '("http" "https") :test #'string=)
          (error "~A Got ~A:" +unsupported-proxy-protocol-message+
                 proxy-scheme)))
      proxy)))

;;; Image-provider runtime

(defstruct images-api-provider
  api generate-function source-id)

(defparameter *images-api-providers* (make-hash-table :test #'eq))

(defun register-images-api-provider (api generate-function &key source-id)
  (setf (gethash api *images-api-providers*)
        (make-images-api-provider
         :api api :generate-function generate-function :source-id source-id))
  nil)

(defun get-images-api-provider (api)
  (gethash api *images-api-providers*))

(defun clear-images-api-providers ()
  (clrhash *images-api-providers*)
  nil)

(defstruct images-provider
  id name (models nil) models-function refresh-function auth-resolver
  generate-function)

(defstruct (images-models (:constructor %make-images-models))
  (provider-table (make-hash-table :test #'eq))
  (provider-order nil)
  credential-store
  environment)

(defun make-images-models (&key credential-store environment)
  (%make-images-models
   :credential-store credential-store
   :environment environment))

(defun images-models-set-provider (runtime provider)
  (unless (gethash (images-provider-id provider) (images-models-provider-table runtime))
    (setf (images-models-provider-order runtime)
          (append (images-models-provider-order runtime)
                  (list (images-provider-id provider)))))
  (setf (gethash (images-provider-id provider) (images-models-provider-table runtime)) provider)
  provider)

(defun images-models-delete-provider (runtime id)
  (remhash id (images-models-provider-table runtime))
  (setf (images-models-provider-order runtime)
        (remove id (images-models-provider-order runtime)))
  nil)

(defun images-models-clear-providers (runtime)
  (clrhash (images-models-provider-table runtime))
  (setf (images-models-provider-order runtime) nil)
  nil)

(defun images-models-provider (runtime id)
  (gethash id (images-models-provider-table runtime)))

(defun images-models-providers (runtime)
  (loop for id in (images-models-provider-order runtime)
        collect (images-models-provider runtime id)))

(defun images-provider-current-models (provider)
  (handler-case
      (copy-list (if (images-provider-models-function provider)
                     (funcall (images-provider-models-function provider))
                     (images-provider-models provider)))
    (error () nil)))

(defun images-models-models (runtime &optional provider-id)
  (if provider-id
      (let ((provider (images-models-provider runtime provider-id)))
        (and provider (images-provider-current-models provider)))
      (loop for id in (images-models-provider-order runtime)
            append (images-provider-current-models
                    (images-models-provider runtime id)))))

(defun images-models-model (runtime provider-id model-id)
  (find model-id (images-models-models runtime provider-id)
        :key #'image-model-id :test #'string=))

(defun images-models-refresh (runtime &optional provider-id)
  (let ((providers
          (if provider-id
              (let ((provider (images-models-provider runtime provider-id)))
                (and provider (list provider)))
              (loop for id in (images-models-provider-order runtime)
                    collect (images-models-provider runtime id))))
        (errors nil))
    (dolist (provider providers)
      (when (images-provider-refresh-function provider)
        (handler-case
            (funcall (images-provider-refresh-function provider))
          (error (condition)
            (if provider-id (error condition) (push condition errors))))))
    (nreverse errors)))

(defun images-models-generate (runtime model context &rest options)
  (handler-case
      (let ((provider (images-models-provider runtime (image-model-provider model))))
        (unless provider
          (error "Unknown provider: ~A" (image-model-provider model)))
        (let ((function
                (or (images-provider-generate-function provider)
                    (let ((api (get-images-api-provider (image-model-api model))))
                      (and api (images-api-provider-generate-function api))))))
          (unless function
            (error "Unknown image API: ~A" (image-model-api model)))
          (funcall function model context options)))
    (error (condition)
      (make-assistant-images
       :api (image-model-api model)
       :provider (image-model-provider model)
       :model (image-model-id model)
       :output nil :stop-reason :error
       :error-message (princ-to-string condition)))))
