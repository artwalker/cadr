(in-package #:cadr-cli)

(defparameter *config-value-cache*
  (make-hash-table :test #'equal))
(defparameter *config-value-cache-lock*
  (sb-thread:make-mutex
   :name "cadr config value cache"))

(defun clear-config-value-cache ()
  (sb-thread:with-mutex
      (*config-value-cache-lock*)
    (clrhash *config-value-cache*))
  nil)

(defun config-environment-value (name environment)
  (or (cdr (assoc name environment :test #'string=))
      (uiop:getenv name)))

(defun config-name-start-p (character)
  (or (alpha-char-p character)
      (char= character #\_)))

(defun config-name-character-p (character)
  (or (config-name-start-p character)
      (digit-char-p character)))

(defun resolve-config-template (config environment)
  (with-output-to-string (output)
    (loop with index = 0
          while (< index (length config))
          for character = (char config index)
          do
          (if (char/= character #\$)
              (progn
                (write-char character output)
                (incf index))
              (let ((next-index (1+ index)))
                (cond
                  ((= next-index (length config))
                   (write-char #\$ output)
                   (incf index))
                  ((member (char config next-index)
                           '(#\$ #\!))
                   (write-char
                    (char config next-index)
                    output)
                   (incf index 2))
                  ((char= (char config next-index)
                          #\{)
                   (let ((end
                           (position #\} config
                                     :start (+ index 2))))
                     (if (null end)
                         (progn
                           (write-char #\$ output)
                           (incf index))
                         (let* ((name
                                  (subseq config
                                          (+ index 2) end))
                                (valid-p
                                  (and
                                   (plusp (length name))
                                   (config-name-start-p
                                    (char name 0))
                                   (every
                                    #'config-name-character-p
                                    name))))
                           (if valid-p
                               (let ((value
                                       (config-environment-value
                                        name environment)))
                                 (unless value
                                   (return-from
                                       resolve-config-template
                                     nil))
                                 (write-string value output))
                               (write-string
                                (subseq config index
                                        (1+ end))
                                output))
                           (setf index (1+ end))))))
                  ((config-name-start-p
                    (char config next-index))
                   (let ((end next-index))
                     (loop while
                           (and
                            (< end (length config))
                            (config-name-character-p
                             (char config end)))
                           do (incf end))
                     (let ((value
                             (config-environment-value
                              (subseq config next-index end)
                              environment)))
                       (unless value
                         (return-from
                             resolve-config-template nil))
                       (write-string value output))
                     (setf index end)))
                  (t
                   (write-char #\$ output)
                   (incf index))))))))

(defun default-config-command (command)
  (multiple-value-bind (output error-output status)
      (uiop:run-program
       (list "/bin/sh" "-c" command)
       :output :string
       :error-output :string
       :ignore-error-status t)
    (declare (ignore error-output))
    (values output status)))

(defun execute-config-command (config command-function)
  (handler-case
      (multiple-value-bind (output status)
          (funcall command-function (subseq config 1))
        (let ((trimmed
                (and output
                     (string-trim
                      '(#\Space #\Tab
                        #\Newline #\Return)
                      output))))
          (and (or (null status)
                   (zerop status))
               trimmed
               (plusp (length trimmed))
               trimmed)))
    (condition () nil)))

(defun resolve-config-value
    (config &key environment
                   (command-function
                     #'default-config-command)
                   uncached-p)
  (if (uiop:string-prefix-p "!" config)
      (if uncached-p
          (execute-config-command
           config command-function)
          (sb-thread:with-mutex
              (*config-value-cache-lock*)
            (multiple-value-bind (value found-p)
                (gethash config
                         *config-value-cache*)
              (if found-p
                  value
                  (setf
                   (gethash config
                            *config-value-cache*)
                   (execute-config-command
                    config command-function))))))
      (resolve-config-template config environment)))

(defun copy-json-object (object)
  (cadr-ai::json-as-hash-table
   (cadr-ai::copy-json-value object)))

(defun empty-json-object ()
  (cadr-ai::json-object))

(defun merge-json-objects (base overrides)
  (let ((result
          (if (cadr-ai::json-object-p base)
              (copy-json-object base)
              (empty-json-object))))
    (when (cadr-ai::json-object-p overrides)
      (cadr-ai::json-map-entries
       overrides
       (lambda (key value)
         (let ((current
                 (cadr-ai::json-get result key)))
           (cadr-ai::json-put
            result key
            (if (and (cadr-ai::json-object-p current)
                     (cadr-ai::json-object-p value))
                (merge-json-objects
                 current value)
                (copy-json-object value)))))))
    result))

(defun read-settings-object (path)
  (if (not (probe-file path))
      (values (empty-json-object) nil)
      (handler-case
          (let ((object
                  (cadr-ai::parse-json
                   (uiop:read-file-string
                    path :external-format :utf-8))))
            (unless (cadr-ai::json-object-p object)
              (error "settings file must contain an object"))
            (values (cadr-ai::json-as-hash-table object) nil))
        (condition (condition)
          (values nil condition)))))

(defun write-settings-object (path object)
  (atomic-write-utf8
   path
   (format nil "~A~%"
           (cadr-ai::stringify-json object))))
