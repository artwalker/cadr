(in-package #:cadr-ai)

(defstruct context-usage-estimate
  (tokens 0 :type (integer 0 *))
  (usage-tokens 0 :type (integer 0 *))
  (trailing-tokens 0 :type (integer 0 *))
  (last-usage-index nil :type (or null (integer 0 *))))

(defconstant +estimated-image-characters+ 4800)

(defun estimate-text-tokens (text)
  (ceiling (length text) 4))

(defun estimated-content-characters (content)
  (if (stringp content)
      (length content)
      (loop for block in (coerce (or content nil) 'list)
            sum
            (cond
              ((typep block 'text-content)
               (length (text-content-text block)))
              ((typep block 'image-content)
               +estimated-image-characters+)
              (t 0)))))

(defun estimate-content-tokens (content)
  (ceiling (estimated-content-characters content) 4))

(defun safely-stringify (value)
  (handler-case
      (stringify-json value)
    (error () "[unserializable]")))

(defun estimate-message-tokens (message)
  (cond
    ((typep message 'user-message)
     (estimate-content-tokens (user-message-content message)))
    ((typep message 'tool-result-message)
     (estimate-content-tokens (tool-result-message-content message)))
    ((typep message 'assistant-message)
     (ceiling
      (loop for block in (assistant-message-content message)
            sum
            (cond
              ((typep block 'text-content)
               (length (text-content-text block)))
              ((typep block 'thinking-content)
               (length (thinking-content-thinking block)))
              ((typep block 'tool-call)
               (+ (length (tool-call-name block))
                  (length
                   (safely-stringify
                    (tool-call-arguments block)))))
              (t 0)))
      4))
    (t 0)))

(defun message-timestamp (message)
  (etypecase message
    (user-message (user-message-timestamp message))
    (assistant-message (assistant-message-timestamp message))
    (tool-result-message (tool-result-message-timestamp message))))

(defun applicable-usage-info (messages)
  (loop with latest-prefix-timestamp = most-negative-fixnum
        with result = nil
        for message in messages
        for index from 0
        do
        (when (typep message 'assistant-message)
          (let ((usage (assistant-message-usage message)))
            (when (and
                   (>= (assistant-message-timestamp message)
                       latest-prefix-timestamp)
                   (not
                    (member (assistant-message-stop-reason message)
                            '(:aborted :error)))
                   (plusp (usage-total usage)))
              (setf result (cons index usage)))))
        (setf latest-prefix-timestamp
              (max latest-prefix-timestamp
                   (message-timestamp message)))
        finally (return result)))

(defun estimate-message-list (messages)
  (let ((usage-info (applicable-usage-info messages)))
    (if usage-info
        (let* ((index (car usage-info))
               (usage-tokens (usage-total (cdr usage-info)))
               (trailing
                 (loop for message in (nthcdr (1+ index) messages)
                       sum (estimate-message-tokens message))))
          (make-context-usage-estimate
           :tokens (+ usage-tokens trailing)
           :usage-tokens usage-tokens
           :trailing-tokens trailing
           :last-usage-index index))
        (let ((tokens
                (loop for message in messages
                      sum (estimate-message-tokens message))))
          (make-context-usage-estimate
           :tokens tokens
           :trailing-tokens tokens)))))

(defun tool-estimate-object (tool)
  (json-object
   "name" (tool-name tool)
   "description" (tool-description tool)
   "parameters" (tool-parameters tool)))

(defun estimate-tools-tokens (tools)
  (if tools
      (estimate-text-tokens
       (safely-stringify
        (list-json-array
         (mapcar #'tool-estimate-object tools))))
      0))

(defun estimate-context-tokens (context-or-messages)
  (if (typep context-or-messages 'context)
      (let* ((context context-or-messages)
             (messages (context-messages context))
             (estimate (estimate-message-list messages))
             (last-index
               (context-usage-estimate-last-usage-index estimate))
             (prefix-tokens
               (if last-index
                   (let ((names
                           (loop for message in
                                 (nthcdr (1+ last-index) messages)
                                 when
                                 (typep message 'tool-result-message)
                                   append
                                   (tool-result-message-added-tool-names
                                    message))))
                     (estimate-tools-tokens
                      (remove-if-not
                       (lambda (tool)
                         (member (tool-name tool)
                                 names :test #'string=))
                       (context-tools context))))
                   (+
                    (if (context-system-prompt context)
                        (estimate-text-tokens
                         (context-system-prompt context))
                        0)
                    (estimate-tools-tokens
                     (context-tools context))))))
        (incf (context-usage-estimate-tokens estimate)
              prefix-tokens)
        (incf (context-usage-estimate-trailing-tokens estimate)
              prefix-tokens)
        estimate)
      (estimate-message-list context-or-messages)))
