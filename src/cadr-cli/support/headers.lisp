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
  (let ((defaults
          (when telemetry-p
            (cond
              ((or (eq provider :openrouter)
                   (search "openrouter.ai"
                           (or base-url "")))
               '(("HTTP-Referer" . "https://pi.dev")
                 ("X-OpenRouter-Title" . "pi")
                 ("X-OpenRouter-Categories" . "cli-agent")))
              ((or (eq provider :nvidia)
                   (search "integrate.api.nvidia.com"
                           (or base-url "")))
               '(("X-BILLING-INVOKE-ORIGIN" . "Pi")))
              ((or
                (member provider
                        '(:cloudflare-workers-ai
                          :cloudflare-ai-gateway))
                (search "api.cloudflare.com"
                        (or base-url ""))
                (search "gateway.ai.cloudflare.com"
                        (or base-url "")))
               '(("User-Agent" . "pi-coding-agent"))))))
        (session
          (when
              (and session-id
                   (or
                    (member provider
                            '(:opencode :opencode-go))
                    (search "opencode.ai"
                            (or base-url ""))))
            `(("x-opencode-session" . ,session-id)
              ("x-opencode-client" . "pi")))))
    (merge-header-sources
     session defaults provider-headers
     request-headers)))

(defun merge-stream-settings (settings request)
  (let ((result (copy-list request)))
    (unless (getf result :timeout-ms)
      (setf (getf result :timeout-ms)
            (getf settings
                  :http-idle-timeout-ms)))
    (unless (getf result
                  :websocket-connect-timeout-ms)
      (setf
       (getf result
             :websocket-connect-timeout-ms)
       (getf settings
             :websocket-connect-timeout-ms)))
    (unless (getf result :retry)
      (setf (getf result :retry)
            (getf settings :retry)))
    result))
