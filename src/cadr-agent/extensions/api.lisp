(in-package #:cadr-agent)

(defun active-extension-api-p (api)
  (and
   (typep api 'extension-api)
   (let ((host (%extension-api-host api))
         (bundle (%extension-api-bundle api)))
     (and
      (= (%extension-api-attachment-generation api)
         (extension-host-attachment-generation host))
      (or
       (eq bundle *extension-registration-bundle*)
       (member
        bundle
        (extension-snapshot-bundles
         (extension-host-current-snapshot host))
        :test #'eq))))))

(defun assert-active-extension-api (api)
  (unless (active-extension-api-p api)
    (error
     'stale-extension-context
     :message
     "Extension API is stale after reload, bundle retirement, or session replacement"))
  api)

(defun call-extension-api-action
    (api accessor name &rest arguments)
  (assert-active-extension-api api)
  (let* ((host (%extension-api-host api))
         (function (funcall accessor host)))
    (unless function
      (error
       'extension-execution-error
       :message
       (format nil "Extension action ~A is unavailable in this host"
               name)))
    (apply function arguments)))

(defun extension-api-send-message
    (api message &key (trigger-turn-p nil) deliver-as)
  (assert-extension-deliver-as
   deliver-as
   '(nil :steer :follow-up :next-turn)
   "send-message deliver-as must be :STEER, :FOLLOW-UP, :NEXT-TURN, or NIL")
  (call-extension-api-action
   api #'extension-host-send-message-function
   "send-message" message
   :trigger-turn-p (not (null trigger-turn-p))
   :deliver-as deliver-as))

(defun extension-api-send-user-message
    (api content &key deliver-as)
  (assert-extension-deliver-as
   deliver-as
   '(nil :steer :follow-up)
   "send-user-message deliver-as must be :STEER, :FOLLOW-UP, or NIL")
  (call-extension-api-action
   api #'extension-host-send-user-message-function
   "send-user-message" content
   :deliver-as deliver-as))

(defun extension-api-exec
    (api command arguments
     &key cwd environment timeout-ms)
  (unless
      (and
       (stringp command)
       (plusp (length command))
       (listp arguments)
       (every #'stringp arguments)
       (or (null cwd) (stringp cwd))
       (or
        (null environment)
        (and
         (listp environment)
         (every
          (lambda (entry)
            (and
             (consp entry)
             (stringp (car entry))
             (stringp (cdr entry))))
          environment)))
       (or
        (null timeout-ms)
        (and (integerp timeout-ms)
             (not (minusp timeout-ms)))))
    (error
     'extension-execution-error
     :message
     "exec requires command/argument strings, optional string cwd/environment alist, and non-negative timeout-ms"))
  (call-extension-api-action
   api #'extension-host-exec-function
   "exec" command (copy-list arguments)
   :cwd cwd
   :environment (copy-tree environment)
   :timeout-ms timeout-ms))

(defun extension-http-octets-p (value)
  (typep value '(array (unsigned-byte 8) (*))))

(defun extension-http-headers-p (value)
  (and
   (listp value)
   (every
    (lambda (entry)
      (and (consp entry)
           (stringp (car entry))
           (stringp (cdr entry))))
    value)))

(defun extension-api-http-request
    (api url
     &key (method :get) headers body timeout-ms signal)
  (assert-active-extension-api api)
  (unless
      (and
       (stringp url)
       (or (uiop:string-prefix-p "http://" url)
           (uiop:string-prefix-p "https://" url))
       (member method '(:get :post :put :patch :delete :head))
       (or (null headers) (extension-http-headers-p headers))
       (or (null body) (stringp body)
           (extension-http-octets-p body))
       (or (null timeout-ms)
           (and (integerp timeout-ms)
                (not (minusp timeout-ms))))
       (or (null signal)
           (typep signal 'extension-cancellation-signal)))
    (error
     'extension-execution-error
     :message
     "http-request requires an HTTP(S) URL, supported method, string headers, string/octet body, non-negative timeout-ms, and cancellation signal"))
  (let ((function
          (extension-host-http-request-function
           (%extension-api-host api))))
    (unless function
      (error
       'extension-execution-error
       :message "Extension HTTP request is unavailable in this host"))
    (handler-case
        (let ((result
                (funcall
                 function url
                 :method method
                 :headers (copy-tree headers)
                 :body (if (extension-http-octets-p body)
                           (copy-seq body)
                           body)
                 :timeout-ms timeout-ms
                 :signal signal)))
          (unless
              (and
               (strict-keyword-plist-p result)
               (integerp (getf result :status))
               (extension-http-headers-p
                (getf result :headers))
               (extension-http-octets-p
                (getf result :body)))
            (error "invalid extension HTTP adapter result"))
          (list
           :status (getf result :status)
           :headers (copy-tree (getf result :headers))
           :body (copy-seq (getf result :body))))
      (extension-execution-error (condition)
        (error condition))
      (condition ()
        (error
         'extension-execution-error
         :message
         (if (and signal
                  (extension-cancellation-aborted-p signal))
             "Extension HTTP request was aborted"
             "Extension HTTP request failed"))))))

(defun extension-api-get-flag (api name)
  (assert-active-extension-api api)
  (unless (stringp name)
    (error
     'extension-execution-error
     :message "get-flag requires a string name"))
  (let* ((bundle (%extension-api-bundle api))
         (registered
           (extension-api-registered-flag-p
            bundle name)))
    (unless registered
      (return-from extension-api-get-flag nil))
    (let* ((host (%extension-api-host api))
           (function
             (extension-host-get-flag-function host)))
      (if function
          (funcall function name)
          (gethash name
                   (extension-host-flag-values host))))))

(defun extension-api-get-active-tools (api)
  (copy-list
   (call-extension-api-action
    api #'extension-host-get-active-tools-function
    "get-active-tools")))

(defun extension-api-set-active-tools (api tool-names)
  (unless
      (and
       (listp tool-names)
       (every #'stringp tool-names)
       (= (length tool-names)
          (length
           (remove-duplicates
            tool-names :test #'string=))))
    (error
     'extension-execution-error
     :message
     "set-active-tools requires a list of unique tool-name strings"))
  (call-extension-api-action
   api #'extension-host-set-active-tools-function
   "set-active-tools" (copy-list tool-names)))

(defun extension-api-host-action (api action &rest arguments)
  (assert-active-extension-api api)
  (let* ((host (%extension-api-host api))
         (function (extension-host-action-function host)))
    (unless function
      (error 'extension-execution-error
             :message
             (format nil "Extension action ~(~A~) is unavailable in this host"
                     action)))
    (funcall function action arguments)))

(defun extension-api-get-commands (api)
  (copy-tree (or (extension-api-host-action api :commands) nil)))

(defun extension-api-get-all-tools (api)
  (copy-tree (or (extension-api-host-action api :all-tools) nil)))

(defun extension-api-get-thinking-level (api)
  (extension-api-host-action api :thinking-level))

(defun extension-api-set-thinking-level (api level)
  (extension-api-host-action api :set-thinking-level level))

(defun extension-api-set-model (api model)
  (extension-api-host-action api :set-model model))

(defun extension-api-get-session-name (api)
  (extension-api-host-action api :get-session-name))

(defun extension-api-append-entry (api custom-type &optional data)
  (unless (and (stringp custom-type) (plusp (length custom-type)))
    (error 'extension-execution-error
           :message "append-entry requires a non-empty custom type"))
  (extension-api-host-action api :append-entry custom-type data))

(defun extension-api-set-label (api entry-id label)
  (unless (and (stringp entry-id)
               (or (null label) (stringp label)))
    (error 'extension-execution-error
           :message "set-label requires an entry id and string or NIL label"))
  (extension-api-host-action api :set-label entry-id label))

(defun extension-api-events-on (api name handler)
  (assert-active-extension-api api)
  (unless (and (stringp name) (plusp (length name))
               (functionp handler))
    (error 'extension-execution-error
           :message "events-on requires a non-empty name and handler function"))
  (let ((host (%extension-api-host api)))
    (sb-thread:with-mutex ((extension-host-event-lock host))
      (setf
       (gethash name (extension-host-event-listeners host))
       (nconc
        (gethash name (extension-host-event-listeners host))
        (list
         (make-extension-event-listener
          :name name :handler handler :bundle (%extension-api-bundle api)))))))
  (lambda ()
    (let ((host (%extension-api-host api))
          (bundle (%extension-api-bundle api)))
      (sb-thread:with-mutex ((extension-host-event-lock host))
        (setf
         (gethash name (extension-host-event-listeners host))
         (remove-if
          (lambda (listener)
            (and (eq bundle (extension-event-listener-bundle listener))
                 (eq handler (extension-event-listener-handler listener))))
          (gethash name (extension-host-event-listeners host))))))))

(defun extension-api-events-emit (api name payload)
  (assert-active-extension-api api)
  (unless (and (stringp name) (plusp (length name)))
    (error 'extension-execution-error
           :message "events-emit requires a non-empty name"))
  (let* ((host (%extension-api-host api))
         (active-bundles
           (extension-snapshot-bundles
            (extension-host-current-snapshot host)))
         (listeners
           (sb-thread:with-mutex ((extension-host-event-lock host))
             (let* ((all (gethash name (extension-host-event-listeners host)))
                    (active
                      (remove-if-not
                       (lambda (listener)
                         (member (extension-event-listener-bundle listener)
                                 active-bundles :test #'eq))
                       all)))
               (setf (gethash name (extension-host-event-listeners host)) active)
               (copy-list active)))))
    (dolist (listener listeners)
      (handler-case
          (funcall (extension-event-listener-handler listener)
                   (copy-extension-value payload))
        (condition (condition)
          (funcall (extension-host-notify-function host)
                   (format nil "Extension event ~A failed: ~A" name condition)
                   :error)))))
  nil)

(defun extension-event-type (event)
  (%extension-event-type event))

(defun extension-event-turn-index (event)
  (%extension-event-turn-index event))

(defun extension-event-message (event)
  (%extension-event-message event))

(defun extension-event-tool-call (event)
  (%extension-event-tool-call event))

(defun extension-event-tool-result (event)
  (%extension-event-tool-result event))

(defun extension-event-tool-results (event)
  (%extension-event-tool-results event))

(defun copy-extension-value (value)
  (cond
    ((stringp value)
     (copy-seq value))
    ((hash-table-p value)
     (let ((copy
             (make-hash-table
              :test (hash-table-test value)
              :size (hash-table-size value))))
       (maphash
        (lambda (key item)
          (setf
           (gethash (copy-extension-value key) copy)
           (copy-extension-value item)))
        value)
       copy))
    ((consp value)
     (cons
      (copy-extension-value (car value))
      (copy-extension-value (cdr value))))
    ((vectorp value)
     (map 'vector #'copy-extension-value value))
    (t value)))

(defun extension-event-payload (event)
  (unless (typep event 'extension-event)
    (error
     'extension-execution-error
     :message "Expected an EXTENSION-EVENT"))
  (if (eq :tool-call-error
          (%extension-event-type event))
      (copy-extension-value
       (%extension-event-payload event))
      (copy-tree (%extension-event-payload event))))
