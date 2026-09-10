(in-package #:cadr-ai)

(defun opencode-host-p (provider base-url)
  (or (member provider '(:opencode :opencode-go))
      (and (stringp base-url)
           (search "opencode.ai" base-url))))

(defun opencode-request-headers
    (&key provider base-url session-id)
  "OpenCode requires x-opencode-session on every request.
Synthesize a UUID when the caller has no session (ephemeral / --no-session)."
  (when (opencode-host-p provider base-url)
    (let ((id
            (if (non-empty-string-p session-id)
                session-id
                (uuid-v7))))
      `(("x-opencode-session" . ,id)
        ("x-opencode-client" . ,(cadr-product-slug))))))
