(in-package #:cadr-ai)

(defun opencode-host-p (provider base-url)
  (or (member provider '(:opencode :opencode-go))
      (and (stringp base-url)
           (search "opencode.ai" base-url))))

(defun opencode-request-headers
    (&key provider base-url session-id)
  ;; Baseline getSessionHeaders / withOpenCodeSessionHeader: no fabricate.
  (when (and (opencode-host-p provider base-url)
             (non-empty-string-p session-id))
    `(("x-opencode-session" . ,session-id)
      ("x-opencode-client" . ,(cadr-product-slug)))))
