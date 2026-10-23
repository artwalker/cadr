(in-package #:cadr-cli)

;;; QuickJS host for one codemode script. The guest is the vendored
;;; quickjs-wasi@3.6.2 module (MIT). The prelude is the evaluated
;;; v1.4.0 PRELUDE_SOURCE (packages/codemode/src/runtime/prelude-source.ts).
;;; cadr-wasm is loaded on the first script, not when this file loads.
;;; pi@4a080252f packages/codemode/src/runtime/vm.ts

(defparameter *codemode-prelude-source* nil)

(defun codemode-prelude-source ()
  (or *codemode-prelude-source*
      (setf *codemode-prelude-source*
            (uiop:read-file-string
             (asdf:system-relative-pathname
              "cadr-cli" "src/cadr-cli/extensions/codemode-prelude.js")))))

(defvar *codemode-wasm-ready* nil)
(defvar *codemode-wasm-lock* (sb-thread:make-mutex :name "codemode-wasm"))

(defun codemode-wasm (name)
  (or (find-symbol name "CADR-WASM")
      (error "cadr-wasm does not export ~A" name)))

(defun codemode-ensure-wasm ()
  (sb-thread:with-mutex (*codemode-wasm-lock*)
    (unless *codemode-wasm-ready*
      (asdf:load-asd (asdf:system-relative-pathname "cadr-cli" "cadr-wasm.asd"))
      (asdf:load-system "cadr-wasm")
      (setf (symbol-value (codemode-wasm "*WASM-CALL-LIMIT*"))
            most-positive-fixnum)
      (setf *codemode-wasm-ready* t)))
  t)

(define-condition codemode-js-error (error)
  ((name :initarg :name :reader codemode-js-error-name)
   (message :initarg :message :reader codemode-js-error-message)
   (stack :initarg :stack :reader codemode-js-error-stack))
  (:report (lambda (condition stream)
             (format stream "~A: ~A"
                     (codemode-js-error-name condition)
                     (codemode-js-error-message condition)))))

(defstruct codemode-vm
  instance
  (callbacks (make-hash-table :test #'equal))
  (interrupt (lambda () nil))
  (messages nil)
  api
  settle)

(defun codemode-u32 (value)
  (logand (or value 0) #xffffffff))

(defun codemode-export (vm name &rest args)
  (let ((values (apply (codemode-wasm "INVOKE")
                       (codemode-vm-instance vm) name args)))
    (if values (first values) 0)))

(defun codemode-memory (vm)
  (funcall (codemode-wasm "WASM-EXTERN-VALUE")
           (funcall (codemode-wasm "GET-EXPORT")
                    (codemode-vm-instance vm) "memory")))

(defun codemode-bytes (vm)
  (funcall (codemode-wasm "WASM-MEMORY-BYTES") (codemode-memory vm)))

(defun codemode-store-u32 (vm address value)
  (funcall (codemode-wasm "STORE-LE")
           (codemode-memory vm) (codemode-u32 address) 0 4 value))

(defun codemode-load-u32 (vm address)
  (funcall (codemode-wasm "LOAD-LE")
           (codemode-memory vm) (codemode-u32 address) 0 4))

(defun codemode-write-string (vm text)
  (let* ((octets (sb-ext:string-to-octets text :external-format :utf-8))
         (length (length octets))
         (pointer (codemode-export vm "wasm_malloc" (+ length 1))))
    (when (zerop (codemode-u32 pointer)) (error "wasm_malloc failed"))
    (let ((bytes (codemode-bytes vm))
          (start (codemode-u32 pointer)))
      (replace bytes octets :start1 start)
      (setf (aref bytes (+ start length)) 0))
    (values pointer length)))

(defun codemode-free-bytes (vm pointer)
  (when (and pointer (plusp (codemode-u32 pointer)))
    (codemode-export vm "wasm_free" pointer)))

(defun codemode-free-value (vm pointer)
  (when (and pointer (plusp (codemode-u32 pointer)))
    (codemode-export vm "qjs_free_value" pointer)))

(defun codemode-to-string (vm pointer)
  (let ((length-pointer (codemode-export vm "wasm_malloc" 4)))
    (when (zerop length-pointer) (error "wasm_malloc failed"))
    (unwind-protect
         (let ((cstr (codemode-export vm "qjs_get_string_len"
                                      pointer length-pointer)))
           (if (zerop cstr)
               "<null>"
               (let* ((length (codemode-load-u32 vm length-pointer))
                      (bytes (codemode-bytes vm))
                      (text (sb-ext:octets-to-string
                             (subseq bytes cstr (+ cstr length))
                             :external-format :utf-8)))
                 (codemode-export vm "qjs_free_cstring" cstr)
                 text)))
      (codemode-free-bytes vm length-pointer))))

(defun codemode-new-string (vm text)
  (multiple-value-bind (pointer length) (codemode-write-string vm text)
    (unwind-protect (codemode-export vm "qjs_new_string" pointer length)
      (codemode-free-bytes vm pointer))))

(defun codemode-new-number (vm number)
  (codemode-export vm "qjs_new_number"
                   (funcall (codemode-wasm "F64-TO-BITS")
                            (float number 1.0d0))))

(defun codemode-to-number (vm pointer)
  (funcall (codemode-wasm "BITS-TO-F64")
           (codemode-export vm "qjs_get_float64" pointer)))

(defun codemode-undefined-p (vm pointer)
  (plusp (codemode-export vm "qjs_is_undefined" pointer)))

(defun codemode-exception-p (vm pointer)
  (plusp (codemode-export vm "qjs_is_exception" pointer)))

(defun codemode-get-prop (vm object name)
  (multiple-value-bind (pointer length) (codemode-write-string vm name)
    (declare (ignore length))
    (unwind-protect (codemode-export vm "qjs_get_prop_string" object pointer)
      (codemode-free-bytes vm pointer))))

(defun codemode-set-prop (vm object name value)
  (multiple-value-bind (pointer length) (codemode-write-string vm name)
    (declare (ignore length))
    (unwind-protect
         (codemode-export vm "qjs_set_prop_string" object pointer value)
      (codemode-free-bytes vm pointer))))

(defun codemode-bool (vm pointer)
  (plusp (codemode-export vm "qjs_get_bool" pointer)))

(defun codemode-exception-parts (vm pointer)
  (let ((name (codemode-get-prop vm pointer "name"))
        (message (codemode-get-prop vm pointer "message"))
        (stack (codemode-get-prop vm pointer "stack")))
    (unwind-protect
         (list (if (codemode-undefined-p vm name)
                   "Error"
                   (codemode-to-string vm name))
               (if (codemode-undefined-p vm message)
                   (codemode-to-string vm pointer)
                   (codemode-to-string vm message))
               (if (codemode-undefined-p vm stack)
                   nil
                   (codemode-to-string vm stack)))
      (codemode-free-value vm name)
      (codemode-free-value vm message)
      (codemode-free-value vm stack))))

(defun codemode-signal-exception (vm pointer)
  (destructuring-bind (name message stack)
      (codemode-exception-parts vm pointer)
    (codemode-free-value vm pointer)
    (error 'codemode-js-error :name name :message message :stack stack)))

(defun codemode-check (vm pointer)
  (if (codemode-exception-p vm pointer)
      (progn
        (codemode-free-value vm pointer)
        (codemode-signal-exception
         vm (codemode-export vm "qjs_get_exception")))
      pointer))

(defun codemode-eval (vm code filename)
  (multiple-value-bind (code-pointer code-length)
      (codemode-write-string vm code)
    (multiple-value-bind (file-pointer file-length)
        (codemode-write-string vm filename)
      (declare (ignore file-length))
      (unwind-protect
           (codemode-check
            vm (codemode-export vm "qjs_eval"
                                code-pointer code-length file-pointer 0))
        (codemode-free-bytes vm code-pointer)
        (codemode-free-bytes vm file-pointer)))))

(defun codemode-call (vm function this arguments)
  (let* ((count (length arguments))
         (argv (if (plusp count)
                   (codemode-export vm "wasm_malloc" (* count 4))
                   0)))
    (when (and (plusp count) (zerop argv))
      (error "wasm_malloc failed"))
    (unwind-protect
         (progn
           (loop for argument in arguments
                 for index from 0
                 do (codemode-store-u32
                     vm (+ argv (* index 4)) argument))
           (codemode-check
            vm (codemode-export vm "qjs_call" function this count argv)))
      (when (plusp argv) (codemode-free-bytes vm argv)))))

(defun codemode-throw (vm text)
  (let ((error-pointer (codemode-export vm "qjs_new_error"))
        (message (codemode-new-string vm text)))
    (codemode-set-prop vm error-pointer "message" message)
    (codemode-free-value vm message)
    (codemode-export vm "qjs_throw" error-pointer)
    (codemode-free-value vm error-pointer)
    0))

(defun codemode-read-arguments (vm count argv)
  (loop for index from 0 below count
        collect (codemode-load-u32 vm (+ (codemode-u32 argv) (* index 4)))))

(defun codemode-host-call (vm name-pointer name-length this-pointer count argv)
  (declare (ignore this-pointer))
  (let* ((name (codemode-decode-bytes vm name-pointer name-length))
         (callback (gethash name (codemode-vm-callbacks vm))))
    (unless callback
      (return-from codemode-host-call
        (codemode-throw
         vm (format nil "Host callback \"~A\" is not registered" name))))
    (handler-case
        (let* ((arguments (codemode-read-arguments vm count argv))
               (result (apply callback arguments)))
          (prog1 (codemode-export vm "qjs_dup_value" result)
            (codemode-free-value vm result)))
      (error (condition)
        (codemode-throw vm (princ-to-string condition))))))

(defun codemode-decode-bytes (vm pointer length)
  (let* ((bytes (codemode-bytes vm))
         (start (codemode-u32 pointer))
         (size (codemode-u32 length)))
    (sb-ext:octets-to-string
     (subseq bytes start (+ start size))
     :external-format :utf-8)))

(defun codemode-bind-import (table module name params results function)
  (setf (gethash (cons module name) table)
        (funcall (codemode-wasm "MAKE-WASM-EXTERN")
                 :kind :func
                 :value function
                 :type (cons (coerce params 'vector)
                             (coerce results 'vector)))))

(defun codemode-unix-nanoseconds ()
  (multiple-value-bind (seconds microseconds) (sb-ext:get-time-of-day)
    (+ (* seconds 1000000000) (* microseconds 1000))))

(defun codemode-random-bytes (count)
  (let ((bytes (make-array count :element-type '(unsigned-byte 8))))
    (with-open-file (input "/dev/urandom" :element-type '(unsigned-byte 8))
      (read-sequence bytes input))
    bytes))

(defun codemode-seconds-east (unix-seconds)
  (let* ((universal (+ unix-seconds 2208988800))
         (parts (multiple-value-list (decode-universal-time universal)))
         (as-utc (apply #'encode-universal-time
                        (append (subseq parts 0 6) (list 0)))))
    (- as-utc universal)))

(defun codemode-imports (vm)
  (let ((table (funcall (codemode-wasm "MAKE-WASI-IMPORTS")
                        :discard-output t
                        :clock #'codemode-unix-nanoseconds
                        :random-bytes #'codemode-random-bytes)))
    (codemode-bind-import
     table "env" "host_call" '(:i32 :i32 :i32 :i32 :i32) '(:i32)
     (lambda (name-pointer name-length this-pointer count argv)
       (codemode-host-call vm name-pointer name-length this-pointer count argv)))
    (codemode-bind-import
     table "env" "host_interrupt" '() '(:i32)
     (lambda () (if (funcall (codemode-vm-interrupt vm)) 1 0)))
    (codemode-bind-import
     table "env" "host_promise_rejection" '(:i32 :i32 :i32) '()
     (lambda (promise reason is-handled)
       (declare (ignore promise reason is-handled))
       nil))
    (codemode-bind-import
     table "env" "host_module_normalize" '(:i32 :i32) '(:i32)
     (lambda (base name)
       (declare (ignore base name))
       0))
    (codemode-bind-import
     table "env" "host_module_load" '(:i32 :i32) '(:i32)
     (lambda (name out)
       (declare (ignore name out))
       0))
    (codemode-bind-import
     table "env" "host_get_timezone_offset" '(:i32 :i32) '(:i32)
     (lambda (high low)
       (let* ((seconds (+ (ash (codemode-u32 high) 32) (codemode-u32 low)))
              (east (codemode-seconds-east seconds)))
         (logand east #xffffffff))))
    table))

(defun codemode-make-vm (interrupt)
  (codemode-ensure-wasm)
  (let* ((vm (make-codemode-vm :interrupt interrupt))
         (compiled (funcall (codemode-wasm "ENSURE-COMPILED")
                            (funcall (codemode-wasm "QUICKJS-WASM-BYTES"))))
         (instance (funcall (codemode-wasm "INSTANTIATE")
                            compiled (codemode-imports vm))))
    (setf (codemode-vm-instance vm) instance)
    (funcall (codemode-wasm "INVOKE") instance "_initialize")
    (unless (zerop (codemode-export vm "qjs_init"))
      (error "Failed to initialize QuickJS runtime"))
    (codemode-export vm "qjs_set_interrupt_handler" 1)
    (codemode-export vm "qjs_set_memory_limit" (* 256 1024 1024))
    (codemode-export vm "qjs_set_max_stack_size" (* 512 1024))
    vm))

(defun codemode-register (vm name function)
  (setf (gethash name (codemode-vm-callbacks vm)) function)
  (multiple-value-bind (pointer length) (codemode-write-string vm name)
    (unwind-protect (codemode-export vm "qjs_new_host_function" pointer length 0)
      (codemode-free-bytes vm pointer))))

(defun codemode-take-messages (vm)
  (nreverse (shiftf (codemode-vm-messages vm) nil)))

(defun codemode-bridge (vm kind a b c)
  (let ((kind-name (codemode-to-string vm kind)))
    (cond
      ((or (string= kind-name "call") (string= kind-name "global"))
       (push (list :call
                   (truncate (codemode-to-number vm a))
                   (if (string= kind-name "call") "tool" "global")
                   (codemode-to-string vm b)
                   (if (codemode-undefined-p vm c)
                       nil
                       (codemode-to-string vm c)))
             (codemode-vm-messages vm)))
      ((string= kind-name "output")
       (let ((item-kind (codemode-to-string vm a)))
         (push (list :output
                     (cond
                       ((string= item-kind "image")
                        (list :image (codemode-to-string vm b)
                              (codemode-to-string vm c)))
                       ((string= item-kind "console")
                        (list :console (codemode-to-string vm b)))
                       (t (list :text (codemode-to-string vm b)))))
               (codemode-vm-messages vm))))
      ((string= kind-name "done")
       (push (list :done
                   (codemode-bool vm a)
                   (if (codemode-undefined-p vm b) nil (codemode-to-string vm b))
                   (if (codemode-undefined-p vm c) nil (codemode-to-string vm c)))
             (codemode-vm-messages vm)))))
  (codemode-export vm "qjs_get_undefined"))

(defun codemode-drain (vm stalled api)
  (let ((jobs 0))
    (loop while (plusp (codemode-export vm "qjs_is_job_pending"))
          for code = (funcall (codemode-wasm "I32-SIGNED")
                              (codemode-export vm "qjs_execute_pending_job"))
          do (when (minusp code)
               (error "Promise job failed"))
             (incf jobs)
             (when (and (zerop (mod jobs 50))
                        (funcall (codemode-vm-interrupt vm)))
               (error "Execution interrupted")))
    (when (funcall (codemode-vm-interrupt vm))
      (error "Execution interrupted")))
  (codemode-free-value vm (codemode-call vm stalled api nil)))

(defun codemode-settle (vm id ok payload)
  (let ((id-pointer (codemode-new-number vm id))
        (flag (codemode-export vm (if ok "qjs_get_true" "qjs_get_false")))
        (payload-pointer (if payload
                             (codemode-new-string vm payload)
                             (codemode-export vm "qjs_get_undefined")))
        (properties (codemode-export vm "qjs_get_undefined")))
    (unwind-protect
         (codemode-free-value
          vm (codemode-call vm (codemode-vm-settle vm) (codemode-vm-api vm)
                            (list id-pointer flag payload-pointer properties)))
      (codemode-free-value vm id-pointer)
      (codemode-free-value vm flag)
      (codemode-free-value vm payload-pointer)
      (codemode-free-value vm properties))))

(defun codemode-exception-json (condition)
  (let* ((name (codemode-js-error-name condition))
         (message (codemode-js-error-message condition))
         (stack (codemode-js-error-stack condition))
         (head (if (and message (plusp (length message)))
                   (format nil "~A: ~A" name message)
                   name))
         (object (cadr-ai::json-object
                  "name" name
                  "message" (or message "")
                  "stack" (if stack
                              (format nil "~A~%~A" head (string-right-trim
                                                         '(#\Newline #\Return)
                                                         stack))
                              head))))
    (cadr-ai::stringify-json object)))

(defun codemode-timeout-result (output timeout-ms)
  (values nil nil nil (nreverse output)
          (format nil "Execution timed out after ~A ms" timeout-ms)
          :timeout))

(defun codemode-abort-result (output)
  (values nil nil nil (nreverse output) "Execution aborted" :aborted))

(defun codemode-run-vm (code tools-json globals-json store-json
                        &key timeout-ms on-call aborted-p)
  "Run one script. Returns ok, value-json, writes-json, output, error-text, kind."
  (let* ((flag (list nil))
         (vm (codemode-make-vm
              (lambda ()
                (or (car flag)
                    (and aborted-p (funcall aborted-p))))))
         (timeout-thread nil)
         (output nil)
         (done nil))
    (unwind-protect
         (handler-case
             (let* ((prelude (codemode-eval vm (codemode-prelude-source)
                                            "codemode-prelude.js"))
                    (bridge (codemode-register
                             vm "bridge"
                             (lambda (kind a b c)
                               (codemode-bridge vm kind a b c))))
                    (tools (codemode-new-string vm tools-json))
                    (globals (codemode-new-string vm globals-json))
                    (store (codemode-new-string vm store-json))
                    (undefined (codemode-export vm "qjs_get_undefined"))
                    (api (codemode-call vm prelude undefined
                                        (list bridge tools globals store)))
                    (settle (codemode-get-prop vm api "settle"))
                    (run (codemode-get-prop vm api "run"))
                    (stalled (codemode-get-prop vm api "stalled")))
               (setf (codemode-vm-api vm) api
                     (codemode-vm-settle vm) settle)
               (codemode-free-value vm prelude)
               (codemode-free-value vm tools)
               (codemode-free-value vm globals)
               (codemode-free-value vm store)
               (codemode-free-value vm undefined)
               ;; Start the wall-clock after the prelude so a short timeout
               ;; still covers the user script on a slow host.
               (when timeout-ms
                 (setf timeout-thread
                       (sb-thread:make-thread
                        (lambda ()
                          (sleep (/ timeout-ms 1000d0))
                          (setf (car flag) :timeout))
                        :name "codemode-timeout")))
               (handler-case
                   (let ((function
                           (codemode-eval
                            vm (format nil "(async (tools, console) => {~A~%})" code)
                            "codemode.js")))
                     (codemode-free-value vm (codemode-call vm run api (list function)))
                     (codemode-free-value vm function))
                 (codemode-js-error (condition)
                   (cond
                     ((eq (car flag) :timeout)
                      (return-from codemode-run-vm
                        (codemode-timeout-result output timeout-ms)))
                     ((and aborted-p (funcall aborted-p))
                      (return-from codemode-run-vm
                        (codemode-abort-result output)))
                     (t
                      (push (list :done nil (codemode-exception-json condition) nil)
                            (codemode-vm-messages vm))))))
               (codemode-free-value vm run)
               (loop
                 (codemode-drain vm stalled api)
                 (let ((calls nil))
                   (dolist (message (codemode-take-messages vm))
                     (case (first message)
                       (:output (push (second message) output))
                       (:done (setf done message))
                       (:call (push message calls))))
                   (setf calls (nreverse calls))
                   (cond
                     ((eq (car flag) :timeout)
                      (return-from codemode-run-vm
                        (codemode-timeout-result output timeout-ms)))
                     ((and aborted-p (funcall aborted-p))
                      (return-from codemode-run-vm
                        (codemode-abort-result output)))
                     (done (return))
                     ((null calls)
                      (return-from codemode-run-vm
                        (values nil nil nil (nreverse output)
                                "The script stopped without a result"
                                :sandbox)))
                     (t
                      (let ((results (codemode-run-calls calls on-call)))
                        (loop for call in calls
                              for result in results
                              do (codemode-settle
                                  vm (second call) (first result) (second result))))))))
               (cond
                 ((eq (car flag) :timeout)
                  (codemode-timeout-result output timeout-ms))
                 ((and aborted-p (funcall aborted-p))
                  (codemode-abort-result output))
                 (t
                  (values (second done) (third done) (fourth done)
                          (nreverse output) nil :script))))
           (codemode-js-error (condition)
             (cond
               ((eq (car flag) :timeout)
                (codemode-timeout-result output timeout-ms))
               ((and aborted-p (funcall aborted-p))
                (codemode-abort-result output))
               (t
                (values nil nil nil (nreverse output)
                        (codemode-exception-json condition) :script))))
           (error (condition)
             (let ((reason (princ-to-string condition)))
               (cond
                 ((eq (car flag) :timeout)
                  (codemode-timeout-result output timeout-ms))
                 ((and aborted-p (funcall aborted-p))
                  (codemode-abort-result output))
                 (t
                  (values nil nil nil (nreverse output) reason :sandbox))))))
      (setf (car flag) :done)
      (when (and timeout-thread (sb-thread:thread-alive-p timeout-thread))
        (handler-case (sb-thread:terminate-thread timeout-thread)
          (error () nil))))))

(defun codemode-run-calls (calls on-call)
  (if (< (length calls) 2)
      (mapcar (lambda (call) (funcall on-call call)) calls)
      (let ((results (make-array (length calls) :initial-element nil)))
        (mapc #'sb-thread:join-thread
              (loop for call in calls
                    for index from 0
                    collect (let ((call call) (index index))
                              (sb-thread:make-thread
                               (lambda ()
                                 (setf (aref results index)
                                       (funcall on-call call)))
                               :name "codemode-call"))))
        (coerce results 'list))))
