(in-package #:cadr-ai)

(defun opencode-host-p (provider base-url)
  (opencode-target-p provider base-url))

(defun opencode-request-headers
    (&key provider base-url session-id)
  ;; Session routing only. x-opencode-client is attribution and is added
  ;; with the client identity, including when there is no session.
  (opencode-session-headers provider base-url session-id))
