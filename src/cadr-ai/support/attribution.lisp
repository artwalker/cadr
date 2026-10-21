(in-package #:cadr-ai)

(defun opencode-host-p (provider base-url)
  (or (member provider '(:opencode :opencode-go))
      (and (stringp base-url)
           (search "opencode.ai" base-url))))

(defun opencode-request-headers
    (&key provider base-url session-id)
  ;; pi getSessionHeaders / withOpenCodeSessionHeader: no session id
  ;; means no OpenCode routing headers. Do not invent an id.
  (when (and (opencode-host-p provider base-url)
             (non-empty-string-p session-id))
    `(("x-opencode-session" . ,session-id)
      ("x-opencode-client" . ,(cadr-product-slug)))))
