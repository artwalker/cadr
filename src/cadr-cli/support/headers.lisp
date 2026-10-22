(in-package #:cadr-cli)

(defun header-put (headers name value)
  (acons
   name value
   (remove name headers
           :key #'car
           :test #'string-equal)))

(defun merge-header-sources (&rest sources)
  (let ((result nil))
    (dolist (source sources result)
      (dolist (header source)
        (setf result
              (header-put result
                          (car header)
                          (cdr header)))))))

(defun provider-attribution-headers
    (&key provider base-url telemetry-p
       session-id provider-headers
       request-headers)
  (declare (ignore telemetry-p))
  ;; OpenRouter, NVIDIA NIM, and OpenCode client attribution are applied
  ;; under these headers by the client identity, after this merge, so an
  ;; extension before_provider_headers hook does not see them.
  (merge-header-sources
   (cadr-ai::opencode-session-headers
    provider base-url session-id)
   provider-headers
   request-headers))

(defun coding-agent-client-identity (telemetry-p)
  (cadr-ai::client-identity
   :user-agent :detailed
   :version (cadr-ai::cadr-version)
   :attribution
   (if telemetry-p
       cadr-ai::+cadr-attribution+
       nil)))

(defparameter +stream-setting-defaults+
  '((:timeout-ms . :http-idle-timeout-ms)
    (:websocket-connect-timeout-ms . :websocket-connect-timeout-ms)
    (:retry . :retry)))

(defun merge-stream-settings (settings request)
  (let ((result (copy-list request)))
    (dolist (pair +stream-setting-defaults+ result)
      (unless (getf result (car pair))
        (setf (getf result (car pair))
              (getf settings (cdr pair)))))))
