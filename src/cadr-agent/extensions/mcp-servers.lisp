(in-package #:cadr-agent)

;;; MCP server registrations (pi@71023aec1 mcp-servers.ts).
;;; Core only validates and stores; the extension that handles
;;; mcp_servers_change connects them.

(defstruct (registered-mcp-server
            (:copier nil))
  (name "" :type string)
  config
  (extension-path "" :type string))

(defun copy-registered-mcp-server (server)
  (make-registered-mcp-server
   :name (registered-mcp-server-name server)
   :config (copy-extension-value
            (registered-mcp-server-config server))
   :extension-path
   (registered-mcp-server-extension-path server)))

(defun extension-host-list-mcp-servers (host)
  (sb-thread:with-mutex ((extension-host-mcp-servers-lock host))
    (mapcar
     #'copy-registered-mcp-server
     (loop for name in (extension-host-mcp-server-order host)
           for server =
           (gethash name (extension-host-mcp-servers host))
           when server collect server))))

(defun emit-mcp-servers-change (host)
  (when (extension-host-has-hook-p host :mcp-servers-change)
    (run-extension-lifecycle-hooks
     host :mcp-servers-change
     :payload
     (list :servers (extension-host-list-mcp-servers host))))
  (report-unhandled-mcp-servers host))

(defun report-unhandled-mcp-servers (host)
  ;; pi@71023aec1 reportUnhandledMcpServers: when nothing handles
  ;; mcp_servers_change, registered servers will never connect.
  (when (extension-host-has-hook-p host :mcp-servers-change)
    (return-from report-unhandled-mcp-servers nil))
  (dolist (server (extension-host-list-mcp-servers host))
    (let ((name (registered-mcp-server-name server)))
      (unless (gethash name (extension-host-reported-mcp-servers host))
        (setf (gethash name
                       (extension-host-reported-mcp-servers host))
              t)
        (funcall
         (extension-host-notify-function host)
         (format
          nil
          "MCP server ~S is registered, but no loaded extension connects MCP servers; another extension may have replaced the built-in MCP support"
          name)
         :error)))))

(defun extension-host-register-mcp-server
    (host name config extension-path)
  (unless (and (stringp name) (plusp (length name)))
    (error 'extension-registration-error
           :message "MCP server name must be a non-empty string"))
  (unless (and (stringp extension-path)
               (plusp (length extension-path)))
    (error 'extension-registration-error
           :message "MCP server extension path must be a non-empty string"))
  (let ((server
          (make-registered-mcp-server
           :name name
           :config config
           :extension-path extension-path)))
    (sb-thread:with-mutex ((extension-host-mcp-servers-lock host))
      (unless (gethash name (extension-host-mcp-servers host))
        (setf (extension-host-mcp-server-order host)
              (nconc (extension-host-mcp-server-order host)
                     (list name))))
      (setf (gethash name (extension-host-mcp-servers host))
            server))
    (emit-mcp-servers-change host)
    server))

(defun extension-host-unregister-mcp-server
    (host name extension-path)
  (sb-thread:with-mutex ((extension-host-mcp-servers-lock host))
    (let ((existing
            (gethash name (extension-host-mcp-servers host))))
      (unless
          (and existing
               (string=
                (registered-mcp-server-extension-path existing)
                extension-path))
        (return-from extension-host-unregister-mcp-server nil))
      (remhash name (extension-host-mcp-servers host))
      (setf (extension-host-mcp-server-order host)
            (remove name (extension-host-mcp-server-order host)
                    :test #'string=))))
  (emit-mcp-servers-change host)
  t)

(defun extension-host-find-mcp-server (host name)
  (sb-thread:with-mutex ((extension-host-mcp-servers-lock host))
    (gethash name (extension-host-mcp-servers host))))

(defun extension-api-register-mcp-server (api name config)
  (assert-active-extension-api api)
  (let* ((bundle (%extension-api-bundle api))
         (path (or (extension-bundle-path bundle) ""))
         (host (%extension-api-host api))
         (validated (validate-mcp-server-config name config)))
    (when (stringp validated)
      (error
       'extension-registration-error
       :message
       (format nil
               "Invalid MCP server registered by extension ~S: ~A"
               path validated)))
    (let ((owner
            (let ((existing (extension-host-find-mcp-server host name)))
              (and existing
                   (registered-mcp-server-extension-path existing)))))
      (when (and owner (not (string= owner path)))
        (error
         'extension-registration-error
         :message
         (format nil
                 "MCP server ~S is already registered by extension ~S"
                 name owner))))
    (let ((clash
            (find-if
             (lambda (server)
               (and (not (string=
                          (registered-mcp-server-name server)
                          name))
                    (string=
                     (mcp-namespace
                      (registered-mcp-server-name server))
                     (mcp-namespace name))))
             (extension-host-list-mcp-servers host))))
      (when clash
        (error
         'extension-registration-error
         :message
         (format nil
                 "MCP server ~S conflicts with registered server ~S"
                 name
                 (registered-mcp-server-name clash)))))
    (extension-host-register-mcp-server
     host name validated path))
  nil)

(defun extension-api-unregister-mcp-server (api name)
  (assert-active-extension-api api)
  (let* ((bundle (%extension-api-bundle api))
         (path (or (extension-bundle-path bundle) "")))
    (extension-host-unregister-mcp-server
     (%extension-api-host api) name path))
  nil)

(defun extension-api-get-mcp-servers (api)
  (assert-active-extension-api api)
  (extension-host-list-mcp-servers
   (%extension-api-host api)))
