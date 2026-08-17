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
  (cadr-core:redact-secrets text secrets))

(defun unix-milliseconds ()
  (cadr-core:unix-milliseconds))

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

(cadr-core:define-redacted-print-object (model value stream)
  (format stream "~A/~A :headers [REDACTED]"
          (model-provider value)
          (model-id value)))

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
  (thought-signature nil :type (or null string))
  ;; OpenAI Responses namespace for calls to dynamically loaded or
  ;; namespaced tools.  Wire-level only: like the baseline, the session
  ;; codec does not persist it.
  (namespace nil :type (or null string)))

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
                (&key input output cache-read cache-write cache-write-1h
                      reasoning total cost)))
  (input 0 :type (integer 0 *))
  (output 0 :type (integer 0 *))
  (cache-read 0 :type (integer 0 *))
  (cache-write 0 :type (integer 0 *))
  (cache-write-1h nil :type (or null (integer 0 *)))
  (reasoning nil :type (or null (integer 0 *)))
  (total 0 :type (integer 0 *))
  (cost (make-cost) :type cost))

(defun make-usage (&key
                         (input 0)
                         (output 0)
                         (cache-read 0)
                         (cache-write 0)
                         cache-write-1h
                         reasoning
                         total
                         (cost (make-cost)))
  (%make-usage :input input
               :output output
               :cache-read cache-read
               :cache-write cache-write
               :cache-write-1h cache-write-1h
               :reasoning reasoning
               :total (or total
                          (+ input output cache-read cache-write))
               :cost cost))

(defstruct user-message
  (content "" :type (or string list vector))
  (timestamp (unix-milliseconds) :type integer))

(defstruct assistant-message-diagnostic
  (type nil :type symbol)
  (timestamp (unix-milliseconds) :type integer)
  (details nil :type list)
  (error nil))

(defstruct assistant-message
  (content nil :type list)
  (api nil :type symbol)
  (provider nil :type symbol)
  (model "" :type string)
  (response-model nil :type (or null string))
  (response-id nil :type (or null string))
  (usage (make-usage) :type usage)
  (stop-reason :pending :type symbol)
  (error-message nil :type (or null string))
  (raw-stop-reason nil :type (or null string))
  ;; Provider indication of whether the model explicitly ended its turn.
  ;; Preserved for debugging and does not currently affect agent control
  ;; flow.  Wire-level only: the baseline does not persist it either.
  (end-turn nil :type (or null boolean))
  (diagnostics nil :type list)
  (timestamp (unix-milliseconds) :type integer))

(defstruct tool-result-message
  (tool-call-id "" :type string)
  (tool-name "" :type string)
  (content nil :type list)
  details
  (added-tool-names nil :type list)
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

(defstruct image-model
  (id "" :type string)
  (name "" :type string)
  (api :openrouter-images :type symbol)
  (provider :openrouter :type symbol)
  (base-url "" :type string)
  (input '(:text) :type list)
  (output '(:image) :type list)
  (input-price 0d0 :type double-float)
  (output-price 0d0 :type double-float)
  (cache-read-price 0d0 :type double-float)
  (cache-write-price 0d0 :type double-float)
  (headers nil :type list))

(cadr-core:define-redacted-print-object (image-model value stream)
  (format stream ":provider ~A :id ~S :headers [REDACTED]"
          (image-model-provider value)
          (image-model-id value)))

(defstruct images-context
  (input nil :type list))

(defstruct assistant-images
  (api nil :type symbol)
  (provider nil :type symbol)
  (model "" :type string)
  (output nil :type list)
  (response-id nil :type (or null string))
  (usage nil :type (or null usage))
  (stop-reason :stop :type symbol)
  (error-message nil :type (or null string))
  (timestamp (unix-milliseconds) :type integer))

(defstruct stream-event
  (type nil :type symbol)
  (content-index nil :type (or null (integer 0 *)))
  (delta nil :type (or null string))
  (content nil :type (or null string))
  (tool-call nil :type (or null tool-call))
  (message nil :type (or null assistant-message))
  (reason nil :type (or null symbol)))
