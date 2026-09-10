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
  (let* ((defaults
           (when telemetry-p
             (cond
               ((or (eq provider :openrouter)
                    (search "openrouter.ai"
                            (or base-url "")))
                `(("HTTP-Referer" .
                   ,(cadr-ai::cadr-canonical-repository-url))
                  ("X-OpenRouter-Title" .
                   ,(cadr-ai::cadr-product-slug))
                  ("X-OpenRouter-Categories" . "cli-agent")))
               ((or (eq provider :nvidia)
                    (search "integrate.api.nvidia.com"
                            (or base-url "")))
                `(("X-BILLING-INVOKE-ORIGIN" .
                   ,(cadr-ai::cadr-product-slug))))
               ((or
                 (member provider
                         '(:cloudflare-workers-ai
                           :cloudflare-ai-gateway))
                 (search "api.cloudflare.com"
                         (or base-url ""))
                 (search "gateway.ai.cloudflare.com"
                         (or base-url "")))
                `(("User-Agent" .
                   ,(format nil "~A-coding-agent"
                            (cadr-ai::cadr-product-slug))))))))
         (opencode-p
           (or (member provider
                       '(:opencode :opencode-go))
               (search "opencode.ai"
                       (or base-url ""))))
         (session
           (when opencode-p
             (let ((id (or session-id
                           (cadr-ai:uuid-v7))))
               `(("x-opencode-session" . ,id)
                 ("x-opencode-client" .
                  ,(cadr-ai::cadr-product-slug)))))))
    (merge-header-sources
     session defaults provider-headers
     request-headers)))

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
