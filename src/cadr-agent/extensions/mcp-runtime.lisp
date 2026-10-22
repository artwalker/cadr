(in-package #:cadr-agent)

;;; pi@4a080252f extensions/mcp/runtime.ts. Connect one configured
;;; server, list its tools, call them, and forward progress and
;;; cancellation. Resources and OAuth token exchange stay out.

(defparameter +mcp-default-timeout-seconds+ 60)
(defparameter +mcp-connect-retry-delays-ms+ '(250 1000))
(defparameter +mcp-stderr-tail-chars+ 2000)

(defun mcp-expand-home (value)
  (cond
    ((string= value "~") (namestring (user-homedir-pathname)))
    ((uiop:string-prefix-p "~/" value)
     (namestring
      (merge-pathnames (subseq value 2) (user-homedir-pathname))))
    (t value)))

(defun mcp-path-to-file-url (path)
  ;; Node pathToFileURL. Locked against node v1.4.0's url.pathToFileURL.
  (let ((safe "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~!$&'()*+,;=:@/"))
    (with-output-to-string (out)
      (write-string "file://" out)
      (loop for octet across (sb-ext:string-to-octets path :external-format :utf-8)
            for character = (code-char octet)
            do (if (and (< octet 128) (find character safe))
                   (write-char character out)
                   (format out "%~2,'0X" octet))))))

(defun mcp-directory-name (path)
  (let ((trimmed (string-right-trim '(#\/) path)))
    (if (zerop (length trimmed))
        ""
        (let ((slash (position #\/ trimmed :from-end t)))
          (if slash (subseq trimmed (1+ slash)) trimmed)))))

(defun mcp-progress-text (progress)
  (let ((message (mcp-get progress "message")))
    (if (stringp message)
        message
        (let ((total-present (nth-value 1 (mcp-get progress "total"))))
          (format nil "Progress ~A~A"
                  (mcp-get progress "progress")
                  (if total-present
                      (format nil "/~A" (mcp-get progress "total"))
                      ""))))))

(defun mcp-env-lookup (name overlay)
  (let ((value (if (and overlay (nth-value 1 (gethash name overlay)))
                   (gethash name overlay)
                   (uiop:getenv name))))
    (when (and (stringp value) (plusp (length value)))
      value)))

(defun mcp-config-template (text)
  (let ((parts nil)
        (index 0))
    (loop while (< index (length text))
          do (let ((dollar (position #\$ text :start index)))
               (unless dollar
                 (push (cons :literal (subseq text index)) parts)
                 (return))
               (when (< index dollar)
                 (push (cons :literal (subseq text index dollar)) parts))
               (let ((next (and (< (1+ dollar) (length text))
                                (char text (1+ dollar)))))
                 (cond
                   ((member next '(#\$ #\!))
                    (push (cons :literal (string next)) parts)
                    (setf index (+ dollar 2)))
                   ((eql next #\{)
                    (let ((end (position #\} text :start (+ dollar 2))))
                      (if (null end)
                          (progn
                            (push (cons :literal "$") parts)
                            (setf index (1+ dollar)))
                          (let ((name (subseq text (+ dollar 2) end)))
                            (if (and (plusp (length name))
                                     (every (lambda (character)
                                              (or (alpha-char-p character)
                                                  (digit-char-p character)
                                                  (char= character #\_)))
                                            name)
                                     (not (digit-char-p (char name 0))))
                                (push (cons :env name) parts)
                                (push (cons :literal (subseq text dollar (1+ end)))
                                      parts))
                            (setf index (1+ end))))))
                   (t
                    (let ((rest (subseq text (1+ dollar)))
                          (end 0))
                      (loop while (and (< end (length rest))
                                       (or (alpha-char-p (char rest end))
                                           (digit-char-p (char rest end))
                                           (char= (char rest end) #\_)))
                            do (incf end))
                      (if (and (plusp end)
                               (not (digit-char-p (char rest 0))))
                          (progn
                            (push (cons :env (subseq rest 0 end)) parts)
                            (setf index (+ dollar 1 end)))
                          (progn
                            (push (cons :literal "$") parts)
                            (setf index (1+ dollar))))))))))
    (nreverse parts)))

(defun mcp-resolve-config-value (text description &optional overlay)
  (if (and (plusp (length text)) (char= (char text 0) #\!))
      (let* ((command (subseq text 1))
             (output
               (handler-case
                   (multiple-value-bind (out error-output code)
                       (uiop:run-program command
                                         :output :string
                                         :error-output :string
                                         :ignore-error-status t)
                     (declare (ignore error-output))
                     (when (zerop code)
                       (let ((trimmed
                               (string-trim '(#\Space #\Tab #\Newline #\Return)
                                            (or out ""))))
                         (when (plusp (length trimmed))
                           trimmed))))
                 (error () nil))))
        (or output
            (error "Failed to resolve ~A from shell command: ~A"
                   description command)))
      (let ((parts (mcp-config-template text))
            (missing nil)
            (resolved ""))
        (dolist (part parts)
          (if (eq (car part) :literal)
              (setf resolved (concatenate 'string resolved (cdr part)))
              (let ((value (mcp-env-lookup (cdr part) overlay)))
                (if value
                    (setf resolved (concatenate 'string resolved value))
                    (progn
                      (unless (member (cdr part) missing :test #'string=)
                        (push (cdr part) missing))
                      (setf resolved nil))))))
        (cond
          ((null missing) resolved)
          ((= (length missing) 1)
           (error "Failed to resolve ~A from environment variable: ~A"
                  description (first (last missing))))
          (t
           (error "Failed to resolve ~A from environment variables: ~A"
                  description
                  (format nil "~{~A~^, ~}" (reverse missing))))))))

(defun mcp-resolve-headers (headers description)
  (when (mcp-object-p headers)
    (let ((resolved (mcp-obj)))
      (loop for (key value) on (cdr headers) by #'cddr
            do (setf resolved
                     (mcp-put resolved key
                              (mcp-resolve-config-value
                               value
                               (format nil "~A header ~S" description key)))))
      resolved)))

(defun mcp-uses-oauth-p (config)
  (unless (nth-value 1 (mcp-get config "url"))
    (return-from mcp-uses-oauth-p nil))
  (when (nth-value 1 (mcp-get config "auth"))
    (return-from mcp-uses-oauth-p nil))
  (let ((headers (mcp-get config "headers")))
    (not (and (mcp-object-p headers)
              (loop for (key) on (cdr headers) by #'cddr
                    thereis (string-equal key "authorization"))))))

(defun mcp-auth-provider-name (config)
  (let ((auth (mcp-get config "auth")))
    (when (mcp-object-p auth)
      (let ((provider (mcp-get auth "provider")))
        (when (and (stringp provider) (plusp (length provider)))
          provider)))))

(defun mcp-sign-in-message (name config)
  (let ((provider (mcp-auth-provider-name config)))
    (format nil "MCP server ~S requires sign-in. Run ~A to sign in."
            name
            (if provider
                (format nil "/login ~A" provider)
                "/mcp"))))

(defun mcp-transient-connect-error-p (error)
  (cond
    ((typep error 'mcp-http-error)
     (let ((status (mcp-http-error-status error)))
       (or (= status 408)
           (= status 429)
           (and (>= status 500) (/= status 501)))))
    ((typep error 'cadr-ai:network-error) t)
    (t nil)))

(defun mcp-config-string-list (value)
  (when (mcp-json-sequence-p value)
    (coerce value 'list)))

(defun mcp-config-env-plist (config name)
  (let ((env (mcp-get config "env"))
        (pairs nil))
    (when (mcp-object-p env)
      (loop for (key value) on (cdr env) by #'cddr
            do (setf pairs
                     (list* key
                            (mcp-resolve-config-value
                             value
                             (format nil "MCP server ~S env ~S" name key))
                            pairs))))
    (nreverse pairs)))

(defun mcp-create-transport (name config cwd)
  (if (nth-value 1 (mcp-get config "url"))
      (make-mcp-http-transport
       (mcp-get config "url")
       :headers (mcp-resolve-headers
                 (mcp-get config "headers")
                 (format nil "MCP server ~S" name)))
      (let ((command (mcp-expand-home (mcp-get config "command")))
            (args (mapcar #'mcp-expand-home
                          (or (mcp-config-string-list (mcp-get config "args"))
                              nil)))
            (directory
              (namestring
               (merge-pathnames
                (mcp-expand-home (or (mcp-get config "cwd") "."))
                (uiop:ensure-directory-pathname cwd)))))
        (make-mcp-stdio-transport
         :command command
         :args args
         :cwd directory
         :env (mcp-config-env-plist config name)
         :stderr "pipe"))))

(defstruct mcp-server-connection
  (name "" :type string)
  config
  (cwd "" :type string)
  (state "connecting" :type string)
  error
  (tools nil :type list)
  instructions
  ;; Present when initialize advertised resources. Listing waits for a
  ;; resource tool: a large drive can make resources/list slow.
  (has-resources nil :type boolean)
  client
  stderr-tail
  (closed-p nil :type boolean)
  (shutdown (make-mcp-abort)))

(defun mcp-connection-timeout-ms (connection)
  (let ((seconds (mcp-get (mcp-server-connection-config connection) "timeout")))
    (* 1000 (if (numberp seconds) seconds +mcp-default-timeout-seconds+))))

(defun mcp-server-state (connection)
  (mcp-server-connection-state connection))

(defun mcp-server-tools (connection)
  (mcp-server-connection-tools connection))

(defun mcp-server-error (connection)
  (mcp-server-connection-error connection))

(defun mcp-server-instructions (connection)
  (mcp-server-connection-instructions connection))

(defun mcp-connection-needs-sign-in-p (connection error)
  (and (typep error 'mcp-auth-required-error)
       (or (mcp-uses-oauth-p (mcp-server-connection-config connection))
           (mcp-auth-provider-name (mcp-server-connection-config connection)))))

(defun mcp-connection-fail (connection error)
  (when (and (mcp-connection-needs-sign-in-p connection error)
             (not (mcp-server-connection-closed-p connection)))
    (setf (mcp-server-connection-state connection) "needs-auth"
          (mcp-server-connection-error connection) nil)
    (return-from mcp-connection-fail
      (make-condition
       'simple-error
       :format-control "~A"
       :format-arguments
       (list (mcp-sign-in-message
              (mcp-server-connection-name connection)
              (mcp-server-connection-config connection))))))
  (setf (mcp-server-connection-state connection)
        (if (mcp-server-connection-closed-p connection) "closed" "failed"))
  (let ((message (princ-to-string error)))
    (when (mcp-server-connection-stderr-tail connection)
      (setf message
            (format nil "~A~%~A"
                    message
                    (mcp-server-connection-stderr-tail connection))))
    (setf (mcp-server-connection-error connection) message)
    (make-condition
     'simple-error
     :format-control "MCP server ~S failed to connect: ~A"
     :format-arguments
     (list (mcp-server-connection-name connection) message))))

(defun mcp-connection-connect-once (connection on-tools)
  (let* ((client
           (make-mcp-client
            :name "cadr"
            :version (cadr-ai::cadr-version)
            :request-timeout-ms (mcp-connection-timeout-ms connection)
            :roots (list (mcp-obj
                          "uri" (mcp-path-to-file-url
                                 (namestring
                                  (uiop:ensure-directory-pathname
                                   (mcp-server-connection-cwd connection))))
                          "name" (mcp-directory-name
                                  (namestring
                                   (uiop:ensure-directory-pathname
                                    (mcp-server-connection-cwd connection))))))))
         (transport
           (mcp-create-transport
            (mcp-server-connection-name connection)
            (mcp-server-connection-config connection)
            (mcp-server-connection-cwd connection))))
    (when (mcp-abort-aborted-p (mcp-server-connection-shutdown connection))
      (error "shut down while connecting"))
    (handler-case
        (progn
          (mcp-client-connect client transport)
          (mcp-client-on-notification
           client "notifications/tools/list_changed"
           (lambda (params)
             (declare (ignore params))
             (sb-thread:make-thread
              (lambda ()
                (handler-case
                    (let ((tools (mcp-list-tools client)))
                      (when (and (eq (mcp-server-connection-client connection)
                                     client)
                                 (not (mcp-server-connection-closed-p connection)))
                        (setf (mcp-server-connection-tools connection) tools)
                        (when on-tools
                          (funcall on-tools connection))))
                  (error (condition)
                    (setf (mcp-server-connection-error connection)
                          (format nil "Failed to refresh tools: ~A"
                                  condition)))))
              :name "mcp tool refresh")))
          (mcp-client-on-close
           client
           (lambda ()
             (when (and (eq (mcp-server-connection-client connection) client)
                        (not (mcp-server-connection-closed-p connection)))
               (setf (mcp-server-connection-client connection) nil
                     (mcp-server-connection-state connection) "disconnected")
               (let ((stderr
                       (when (typep transport 'mcp-stdio-transport)
                         (let ((text (string-trim
                                      '(#\Space #\Tab #\Newline #\Return)
                                      (mcp-stdio-stderr transport))))
                           (when (plusp (length text))
                             (subseq text
                                     (max 0
                                          (- (length text)
                                             +mcp-stderr-tail-chars+))))))))
                 (setf (mcp-server-connection-error connection)
                       (if stderr
                           (format nil "Connection closed~%~A" stderr)
                           "Connection closed"))))))
          (let ((tools
                  (if (nth-value 1
                                 (mcp-get (mcp-client-server-capabilities client)
                                          "tools"))
                      (mcp-list-tools client)
                      nil)))
            (when (mcp-abort-aborted-p (mcp-server-connection-shutdown connection))
              (error "shut down while connecting"))
            (unless (string= (mcp-client-state client) "connected")
              (error "connection closed during setup"))
            (setf (mcp-server-connection-client connection) client
                  (mcp-server-connection-tools connection) tools)
            (mcp-connection-note-resources connection client)
            (setf (mcp-server-connection-instructions connection)
                  (let ((text (mcp-client-instructions client)))
                    (when (stringp text)
                      (let ((trimmed
                              (string-trim '(#\Space #\Tab #\Newline #\Return)
                                           text)))
                        (when (plusp (length trimmed))
                          trimmed))))
                  (mcp-server-connection-state connection) "connected"
                  (mcp-server-connection-error connection) nil)
            (when on-tools
              (funcall on-tools connection))
            client))
      (error (condition)
        (ignore-errors (mcp-client-close client))
        (when (typep transport 'mcp-stdio-transport)
          (let ((text (string-trim '(#\Space #\Tab #\Newline #\Return)
                                   (mcp-stdio-stderr transport))))
            (when (plusp (length text))
              (setf (mcp-server-connection-stderr-tail connection)
                    (subseq text
                            (max 0
                                 (- (length text) +mcp-stderr-tail-chars+)))))))
        (error condition)))))

(defun open-mcp-server (name config cwd &key on-tools probe)
  ;; pi@4a080252f McpServerConnection.getClient. PROBE keeps the
  ;; connection after a failure so `cadr mcp list` can print its state
  ;; and error. Callers that omit PROBE still receive the condition.
  (let ((connection
          (make-mcp-server-connection
           :name name
           :config config
           :cwd cwd
           :state "connecting")))
    (handler-case
        (let ((retries (if (nth-value 1 (mcp-get config "url"))
                           +mcp-connect-retry-delays-ms+
                           nil)))
          (loop for attempt from 0
                do (handler-case
                       (progn
                         (mcp-connection-connect-once connection on-tools)
                         (return connection))
                     (error (condition)
                       (let ((delay (nth attempt retries)))
                         (when (or (mcp-server-connection-closed-p connection)
                                   (null delay)
                                   (not (mcp-transient-connect-error-p condition)))
                           (error (mcp-connection-fail connection condition))))
                       (sleep (/ (nth attempt retries) 1000.0))
                       (when (mcp-server-connection-closed-p connection)
                         (error (mcp-connection-fail connection condition)))))))
      (error (condition)
        (if probe
            connection
            (error condition))))))

(defun mcp-server-client (connection)
  (when (mcp-server-connection-closed-p connection)
    (error "MCP server ~S is shut down" (mcp-server-connection-name connection)))
  (let ((client (mcp-server-connection-client connection)))
    (if (and client (string= (mcp-client-state client) "connected"))
        client
        (handler-case
            (progn
              (mcp-connection-connect-once connection nil)
              (mcp-server-connection-client connection))
          (error (condition)
            (error (mcp-connection-fail connection condition)))))))

(defun mcp-server-call-tool (connection name arguments
                             &key abort timeout-ms on-progress)
  (let ((client (mcp-server-client connection)))
    (mcp-call-tool client name arguments
                   :abort abort
                   :timeout-ms (or timeout-ms (mcp-connection-timeout-ms connection))
                   :on-progress on-progress)))

(defun mcp-server-has-resources (connection)
  (mcp-server-connection-has-resources connection))

(defun mcp-connection-note-resources (connection client)
  (setf (mcp-server-connection-has-resources connection)
        (and (nth-value 1
                       (mcp-get (mcp-client-server-capabilities client)
                                "resources"))
             t))
  connection)

(defun mcp-call-read-only (thunk)
  ;; pi@4a080252f withClient readOnly. Resource reads and lists retry once
  ;; after a transient HTTP error. Tool calls do not: the server may have
  ;; already run them.
  (loop for attempt from 1
        do (handler-case
               (return (funcall thunk))
             (mcp-http-error (condition)
               (when (or (> attempt 1)
                         (not (mcp-transient-connect-error-p condition)))
                 (error condition))
               (sleep (/ (first +mcp-connect-retry-delays-ms+) 1000.0))))))

(defun mcp-without-templates (thunk empty)
  ;; Servers that do not implement resources/templates/list have no templates.
  (handler-case
      (funcall thunk)
    (mcp-error (condition)
      (if (= (mcp-error-code condition) +mcp-method-not-found+)
          empty
          (error condition)))))

(defun mcp-server-read-resource (connection uri &key abort timeout-ms)
  (mcp-call-read-only
   (lambda ()
     (mcp-read-resource
      (mcp-server-client connection) uri
      :abort abort
      :timeout-ms (or timeout-ms (mcp-connection-timeout-ms connection))))))

(defun mcp-server-resources-page (connection &optional cursor
                                  &key abort timeout-ms)
  (mcp-call-read-only
   (lambda ()
     (mcp-list-resources-page
      (mcp-server-client connection) cursor
      :abort abort
      :timeout-ms (or timeout-ms (mcp-connection-timeout-ms connection))))))

(defun mcp-server-all-resources (connection &key abort timeout-ms)
  (mcp-call-read-only
   (lambda ()
     (mcp-list-resources
      (mcp-server-client connection)
      :abort abort
      :timeout-ms (or timeout-ms (mcp-connection-timeout-ms connection))))))

(defun mcp-server-resource-templates-page
    (connection &optional cursor &key abort timeout-ms)
  (mcp-call-read-only
   (lambda ()
     (mcp-without-templates
      (lambda ()
        (mcp-list-resource-templates-page
         (mcp-server-client connection) cursor
         :abort abort
         :timeout-ms (or timeout-ms (mcp-connection-timeout-ms connection))))
      (mcp-obj "resourceTemplates" #())))))

(defun mcp-server-all-resource-templates (connection &key abort timeout-ms)
  (mcp-call-read-only
   (lambda ()
     (mcp-without-templates
      (lambda ()
        (mcp-list-resource-templates
         (mcp-server-client connection)
         :abort abort
         :timeout-ms (or timeout-ms (mcp-connection-timeout-ms connection))))
      nil))))

(defun mcp-server-close (connection)
  (mcp-abort (mcp-server-connection-shutdown connection))
  (setf (mcp-server-connection-closed-p connection) t
        (mcp-server-connection-state connection) "closed")
  (let ((client (mcp-server-connection-client connection)))
    (setf (mcp-server-connection-client connection) nil)
    (when client
      (ignore-errors (mcp-client-close client))))
  nil)
