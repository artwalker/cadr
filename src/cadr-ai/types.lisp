(in-package #:cadr-ai)

(defun replace-all (source needle replacement)
  (if (zerop (length needle))
      source
      (with-output-to-string (output)
        (loop with start = 0
              for position = (search needle source
                                     :start2 start)
              do
              (if position
                  (progn
                    (write-string source output
                                  :start start
                                  :end position)
                    (write-string replacement output)
                    (setf start
                          (+ position
                             (length needle))))
                  (progn
                    (write-string source output
                                  :start start)
                    (return)))))))

(defun redact-secrets (text secrets)
  (reduce
   (lambda (result secret)
     (if (and (stringp secret)
              (plusp (length secret)))
         (replace-all result secret "[REDACTED]")
         result))
   secrets
   :initial-value text))

(defun unix-milliseconds ()
  (* 1000 (- (get-universal-time) 2208988800)))

(defstruct model
  (id "" :type string)
  (name "" :type string)
  (provider nil :type symbol)
  (api nil :type symbol)
  (base-url "" :type string)
  (max-tokens 4096 :type (integer 1 *))
  (context-window 0 :type (integer 0 *))
  (supports-images-p nil :type boolean)
  (supports-tools-p t :type boolean)
  (reasoning-p nil :type boolean)
  (thinking-level-map nil :type list)
  (headers nil :type list)
  (compat nil :type list))

(defstruct text-content
  (text "" :type string)
  (signature nil :type (or null string)))

(defstruct thinking-content
  (thinking "" :type string)
  (signature nil :type (or null string))
  (redacted-p nil :type boolean))

(defstruct image-content
  (mime-type "image/png" :type string)
  (data "" :type string))

(defstruct tool-call
  (id "" :type string)
  (name "" :type string)
  (arguments (make-hash-table :test #'equal) :type hash-table)
  (thought-signature nil :type (or null string)))

(defstruct (cost
            (:constructor make-cost
                (&key (input 0d0) (output 0d0)
                      (cache-read 0d0) (cache-write 0d0)
                      (total 0d0))))
  (input 0d0 :type double-float)
  (output 0d0 :type double-float)
  (cache-read 0d0 :type double-float)
  (cache-write 0d0 :type double-float)
  (total 0d0 :type double-float))

(defstruct (usage
            (:constructor %make-usage
                (&key input output cache-read cache-write reasoning total cost)))
  (input 0 :type (integer 0 *))
  (output 0 :type (integer 0 *))
  (cache-read 0 :type (integer 0 *))
  (cache-write 0 :type (integer 0 *))
  (reasoning nil :type (or null (integer 0 *)))
  (total 0 :type (integer 0 *))
  (cost (make-cost) :type cost))

(defun make-usage (&key
                         (input 0)
                         (output 0)
                         (cache-read 0)
                         (cache-write 0)
                         reasoning
                         total
                         (cost (make-cost)))
  (%make-usage :input input
               :output output
               :cache-read cache-read
               :cache-write cache-write
               :reasoning reasoning
               :total (or total
                          (+ input output cache-read cache-write))
               :cost cost))

(defstruct user-message
  (content "" :type (or string list vector))
  (timestamp (unix-milliseconds) :type integer))

(defstruct (assistant-message
            (:constructor %make-assistant-message
                (&key content api provider model response-id usage stop-reason
                      error-message raw-stop-reason timestamp)))
  (content nil :type list)
  (api nil :type symbol)
  (provider nil :type symbol)
  (model "" :type string)
  (response-id nil :type (or null string))
  (usage (make-usage) :type usage)
  (stop-reason :pending :type symbol)
  (error-message nil :type (or null string))
  (raw-stop-reason nil :type (or null string))
  (timestamp (unix-milliseconds) :type integer))

(defun make-assistant-message (&key
                                    (content nil)
                                    api
                                    provider
                                    (model "")
                                    response-id
                                    (usage (make-usage))
                                    (stop-reason :pending)
                                    error-message
                                    raw-stop-reason
                                    (timestamp (unix-milliseconds)))
  (%make-assistant-message
   :content content
   :api api
   :provider provider
   :model model
   :response-id response-id
   :usage usage
   :stop-reason stop-reason
   :error-message error-message
   :raw-stop-reason raw-stop-reason
   :timestamp timestamp))

(defstruct tool-result-message
  (tool-call-id "" :type string)
  (tool-name "" :type string)
  (content nil :type list)
  details
  (is-error nil :type boolean)
  (timestamp (unix-milliseconds) :type integer))

(defstruct tool
  (name "" :type string)
  (description "" :type string)
  (parameters (make-hash-table :test #'equal) :type hash-table)
  (constrained-sampling nil :type list)
  (execution-mode :parallel :type symbol)
  (executor nil :type (or null function)))

(defstruct context
  (system-prompt nil :type (or null string))
  (messages nil :type list)
  (tools nil :type list))

(defstruct stream-event
  (type nil :type symbol)
  (content-index nil :type (or null (integer 0 *)))
  (delta nil :type (or null string))
  (content nil :type (or null string))
  (tool-call nil :type (or null tool-call))
  (message nil :type (or null assistant-message))
  (reason nil :type (or null symbol)))
