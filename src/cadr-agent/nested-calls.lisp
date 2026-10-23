(in-package #:cadr-agent)

(defconstant +nested-call-max-calls+ 256)
(defconstant +nested-call-max-argument-bytes+ 8192)
(defconstant +nested-call-max-argument-bytes-total+ 32768)
(defconstant +nested-call-max-error-chars+ 500)

(defvar *nested-tool-call-runner* nil)
(defvar *nested-tool-caller-id* nil)
(defvar *nested-tool-holds-queue* nil)

(defstruct nested-tool-call-record
  id
  name
  arguments
  arguments-bytes
  (status :unfinished)
  duration-ms
  error
  (started-at 0 :type integer))

(defstruct nested-tool-calls
  (calls nil :type list)
  (complete t :type boolean))

(defstruct nested-call-summary
  calls
  usage)

(defstruct nested-tool-call-outcome
  tool-call
  result
  (is-error nil :type boolean)
  duration-ms)

(defstruct nested-tool-call-runner
  (scopes (make-hash-table :test #'equal) :type hash-table)
  (lock (sb-thread:make-mutex :name "nested-tool-calls"))
  (queue (sb-thread:make-mutex :name "nested-tool-call-queue"))
  tools-function
  run-function
  emit-function
  ;; pi@4a080252f agent-session.ts isSequential: the agent
  ;; toolExecution flag, read at call time.
  sequential-p)

(defstruct nested-call-scope
  records
  (next-id 1 :type integer)
  (complete t :type boolean)
  (argument-bytes 0 :type integer)
  usage)

(defun nested-call-json-bytes (arguments)
  (length
   (sb-ext:string-to-octets
    (cadr-ai::stringify-json (or arguments (cadr-ai::json-object)))
    :external-format :utf-8)))

(defun nested-call-scope (runner caller-id)
  (sb-thread:with-mutex ((nested-tool-call-runner-lock runner))
    (or (gethash caller-id (nested-tool-call-runner-scopes runner))
        (setf (gethash caller-id (nested-tool-call-runner-scopes runner))
              (make-nested-call-scope)))))

(defun nested-call-recorder-start (scope tool-call)
  (when (>= (length (nested-call-scope-records scope))
            +nested-call-max-calls+)
    (setf (nested-call-scope-complete scope) nil)
    (return-from nested-call-recorder-start nil))
  (let* ((arguments (cadr-ai:tool-call-arguments tool-call))
         (bytes (nested-call-json-bytes arguments))
         (record
           (make-nested-tool-call-record
            :id (cadr-ai:tool-call-id tool-call)
            :name (cadr-ai:tool-call-name tool-call)
            :status :unfinished
            :started-at (get-internal-real-time))))
    (if (or (> bytes +nested-call-max-argument-bytes+)
            (> (+ (nested-call-scope-argument-bytes scope) bytes)
               +nested-call-max-argument-bytes-total+))
        (setf (nested-tool-call-record-arguments-bytes record) bytes
              (nested-call-scope-complete scope) nil)
        (setf (nested-tool-call-record-arguments record)
              (cadr-ai::copy-json-value (or arguments (cadr-ai::json-object)))
              (nested-call-scope-argument-bytes scope)
              (+ (nested-call-scope-argument-bytes scope) bytes)))
    (setf (nested-call-scope-records scope)
          (nconc (nested-call-scope-records scope) (list record)))
    record))

(defun nested-call-elapsed-ms (started)
  (max 0
       (round (* 1000 (- (get-internal-real-time) started))
              internal-time-units-per-second)))

(defun nested-call-recorder-finish (record is-error error-text)
  (unless record
    (return-from nested-call-recorder-finish nil))
  (setf (nested-tool-call-record-status record)
        (if is-error :error :ok)
        (nested-tool-call-record-duration-ms record)
        (nested-call-elapsed-ms
         (nested-tool-call-record-started-at record)))
  (when (and is-error (stringp error-text) (plusp (length error-text)))
    (setf (nested-tool-call-record-error record)
          (subseq error-text 0
                  (min +nested-call-max-error-chars+
                       (length error-text)))))
  record)

(defun nested-call-add-usage (scope usage)
  (when usage
    (let ((current (nested-call-scope-usage scope)))
      (setf (nested-call-scope-usage scope)
            (if current
                (cadr-ai:make-usage
                 :input (+ (cadr-ai:usage-input current)
                           (cadr-ai:usage-input usage))
                 :output (+ (cadr-ai:usage-output current)
                            (cadr-ai:usage-output usage))
                 :cache-read (+ (cadr-ai:usage-cache-read current)
                                (cadr-ai:usage-cache-read usage))
                 :cache-write (+ (cadr-ai:usage-cache-write current)
                                 (cadr-ai:usage-cache-write usage))
                 :total (+ (cadr-ai:usage-total current)
                           (cadr-ai:usage-total usage)))
                usage)))))

(defun nested-call-recorder-snapshot (scope)
  (when (and (null (nested-call-scope-records scope))
             (nested-call-scope-complete scope))
    (return-from nested-call-recorder-snapshot nil))
  (let ((calls
          (mapcar #'copy-nested-tool-call-record
                  (nested-call-scope-records scope))))
    (make-nested-tool-calls
     :calls calls
     :complete
     (and (nested-call-scope-complete scope)
          (every (lambda (call)
                   (not (eq (nested-tool-call-record-status call)
                            :unfinished)))
                 calls)))))

(defun nested-tool-call-text (result)
  (when (typep result 'cadr-ai:tool-result-message)
    (with-output-to-string (output)
      (loop with first-p = t
            for block in (cadr-ai:tool-result-message-content result)
            when (typep block 'cadr-ai:text-content)
              do (unless first-p
                   (terpri output))
                 (write-string (cadr-ai:text-content-text block) output)
                 (setf first-p nil)))))

(defun nested-tool-status-name (status)
  (ecase status
    (:ok "ok")
    (:error "error")
    (:unfinished "unfinished")))

(defun nested-tool-call-record-to-json (record)
  (let ((object
          (cadr-ai::json-object
           "id" (nested-tool-call-record-id record)
           "name" (nested-tool-call-record-name record)
           "status" (nested-tool-status-name
                     (nested-tool-call-record-status record)))))
    (when (nested-tool-call-record-arguments record)
      (cadr-ai::json-put
       object "arguments"
       (nested-tool-call-record-arguments record)))
    (when (nested-tool-call-record-arguments-bytes record)
      (cadr-ai::json-put
       object "argumentsBytes"
       (nested-tool-call-record-arguments-bytes record)))
    (when (nested-tool-call-record-duration-ms record)
      (cadr-ai::json-put
       object "durationMs"
       (nested-tool-call-record-duration-ms record)))
    (when (nested-tool-call-record-error record)
      (cadr-ai::json-put
       object "error"
       (nested-tool-call-record-error record)))
    object))

(defun nested-tool-calls-to-json (calls)
  (cadr-ai::json-object
   "calls"
   (map 'vector #'nested-tool-call-record-to-json
        (nested-tool-calls-calls calls))
   "complete" (nested-tool-calls-complete calls)))

(defun nested-tool-status-from-json (value)
  (cond
    ((or (eq value "ok") (string= value "ok")) :ok)
    ((or (eq value "error") (string= value "error")) :error)
    ((or (eq value "unfinished") (string= value "unfinished"))
     :unfinished)
    (t :unfinished)))

(defun nested-tool-call-record-from-json (object)
  (make-nested-tool-call-record
   :id (or (cadr-ai::json-get object "id") "")
   :name (or (cadr-ai::json-get object "name") "")
   :arguments (cadr-ai::json-get object "arguments")
   :arguments-bytes (cadr-ai::json-get object "argumentsBytes")
   :status (nested-tool-status-from-json
            (cadr-ai::json-get object "status"))
   :duration-ms (cadr-ai::json-get object "durationMs")
   :error (cadr-ai::json-get object "error")))

(defun nested-tool-calls-from-json (value)
  (cond
    ((null value) nil)
    ((nested-tool-calls-p value) value)
    ((or (hash-table-p value)
         (cadr-ai::json-object-pairs-p value))
     (let ((calls (cadr-ai::json-get value "calls")))
       (make-nested-tool-calls
        :calls
        (loop for object in (coerce (or calls #()) 'list)
              collect (nested-tool-call-record-from-json object))
        :complete (eq t (cadr-ai::json-get value "complete")))))
    (t nil)))

(defun make-nested-tool-error-outcome (caller-id name text)
  (make-nested-tool-call-outcome
   :tool-call
   (cadr-ai:make-tool-call
    :id (format nil "~A/0" (or caller-id "unavailable"))
    :name (or name "")
    :arguments (cadr-ai::json-object))
   :is-error t
   :result
   (cadr-ai:make-tool-result-message
    :tool-call-id (format nil "~A/0" (or caller-id "unavailable"))
    :tool-name (or name "")
    :content (list (cadr-ai:make-text-content :text text))
    :is-error t)))

(defun nested-tool-exclusive-p (runner name)
  ;; pi@4a080252f nested-tool-calls.ts: the agent toolExecution flag
  ;; or this tool's executionMode sequential, either one, serializes.
  (and (not *nested-tool-holds-queue*)
       (or (and (functionp (nested-tool-call-runner-sequential-p runner))
                (funcall (nested-tool-call-runner-sequential-p runner)))
           (let ((tool
                   (find name
                         (funcall
                          (nested-tool-call-runner-tools-function runner))
                         :key #'cadr-ai:tool-name
                         :test #'string=)))
             (and tool
                  (eq (cadr-ai:tool-execution-mode tool)
                      :sequential))))))

(defun nested-tool-call-runner-execute
    (runner caller-id name arguments &key signal on-update)
  (let* ((scope (nested-call-scope runner caller-id))
         (tool-call
           (cadr-ai:make-tool-call
            :id (format nil "~A/~D"
                        caller-id
                        (nested-call-scope-next-id scope))
            :name name
            :arguments (or arguments (cadr-ai::json-object))))
         (record (nested-call-recorder-start scope tool-call)))
    (incf (nested-call-scope-next-id scope))
    (funcall (nested-tool-call-runner-emit-function runner)
             :tool-execution-start tool-call caller-id nil)
    (labels ((run ()
               (sb-thread:with-mutex
                   ((nested-tool-call-runner-lock runner))
                 (setf (gethash (cadr-ai:tool-call-id tool-call)
                                (nested-tool-call-runner-scopes runner))
                       scope))
               (unwind-protect
                    (funcall (nested-tool-call-runner-run-function runner)
                             tool-call caller-id signal on-update)
                 (sb-thread:with-mutex
                     ((nested-tool-call-runner-lock runner))
                   (remhash (cadr-ai:tool-call-id tool-call)
                            (nested-tool-call-runner-scopes runner))))))
      (let ((outcome
              (if (nested-tool-exclusive-p runner name)
                  (sb-thread:with-mutex
                      ((nested-tool-call-runner-queue runner))
                    (let ((*nested-tool-holds-queue* t))
                      (run)))
                  (run))))
        (nested-call-recorder-finish
         record
         (nested-tool-call-outcome-is-error outcome)
         (nested-tool-call-text
          (nested-tool-call-outcome-result outcome)))
        (nested-call-add-usage
         scope
         (and (nested-tool-call-outcome-result outcome)
              (cadr-ai:tool-result-message-usage
               (nested-tool-call-outcome-result outcome))))
        (funcall (nested-tool-call-runner-emit-function runner)
                 :tool-execution-end tool-call caller-id outcome)
        outcome))))

(defun nested-tool-call-runner-take (runner caller-id)
  (let ((scope
          (sb-thread:with-mutex
              ((nested-tool-call-runner-lock runner))
            (prog1 (gethash caller-id
                            (nested-tool-call-runner-scopes runner))
              (remhash caller-id
                      (nested-tool-call-runner-scopes runner))))))
    (when scope
      (make-nested-call-summary
       :calls (nested-call-recorder-snapshot scope)
       :usage (nested-call-scope-usage scope)))))

(defun extension-context-execute-tool
    (context name arguments &key signal on-update)
  (when context
    (assert-active-extension-context context))
  (let ((runner *nested-tool-call-runner*)
        (caller *nested-tool-caller-id*))
    (unless (and runner caller)
      (return-from extension-context-execute-tool
        (make-nested-tool-error-outcome
         caller name
         "Nested tool calls are not available in this context")))
    (nested-tool-call-runner-execute
     runner caller name arguments
     :signal (or signal (current-tool-cancellation-signal))
     :on-update on-update)))
