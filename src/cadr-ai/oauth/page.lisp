(in-package #:cadr-ai)

(defparameter +oauth-logo-svg+
  "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 800 800\" aria-hidden=\"true\"><path fill=\"#fff\" fill-rule=\"evenodd\" d=\"M47.93 165.29 H400.01 V517.37 H47.93 Z M400.01 165.29 H752.09 V517.37 H400.01 Z M165.29 282.65 H282.65 V400.01 H165.29 Z M517.37 282.65 H634.73 V165.29 H752.09 V517.37 H634.73 V400.01 H517.37 Z\"/></svg>")

(defun escape-oauth-html (value)
  (with-output-to-string (output)
    (loop for character across (or value "")
          do
          (case character
            (#\& (write-string "&amp;" output))
            (#\< (write-string "&lt;" output))
            (#\> (write-string "&gt;" output))
            (#\" (write-string "&quot;" output))
            (#\' (write-string "&#39;" output))
            (otherwise (write-char character output))))))

(defun render-oauth-page
    (title heading message &optional details)
  (let ((title (escape-oauth-html title))
        (heading (escape-oauth-html heading))
        (message (escape-oauth-html message))
        (details
          (and details
               (plusp (length details))
               (escape-oauth-html details))))
    (format
     nil
     "<!doctype html>
<html lang=\"en\">
<head>
  <meta charset=\"utf-8\" />
  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />
  <title>~A</title>
  <style>
    :root {
      --text: #fafafa;
      --text-dim: #a1a1aa;
      --page-bg: #09090b;
      --font-sans: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, \"Segoe UI\", Roboto, \"Helvetica Neue\", Arial, \"Noto Sans\", sans-serif, \"Apple Color Emoji\", \"Segoe UI Emoji\", \"Segoe UI Symbol\", \"Noto Color Emoji\";
      --font-mono: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, \"Liberation Mono\", \"Courier New\", monospace;
    }
    * { box-sizing: border-box; }
    html { color-scheme: dark; }
    body {
      margin: 0;
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 24px;
      background: var(--page-bg);
      color: var(--text);
      font-family: var(--font-sans);
      text-align: center;
    }
    main {
      width: 100%;
      max-width: 560px;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
    }
    .logo {
      width: 72px;
      height: 72px;
      display: block;
      margin-bottom: 24px;
    }
    h1 {
      margin: 0 0 10px;
      font-size: 28px;
      line-height: 1.15;
      font-weight: 650;
      color: var(--text);
    }
    p {
      margin: 0;
      line-height: 1.7;
      color: var(--text-dim);
      font-size: 15px;
    }
    .details {
      margin-top: 16px;
      font-family: var(--font-mono);
      font-size: 13px;
      color: var(--text-dim);
      white-space: pre-wrap;
      word-break: break-word;
    }
  </style>
</head>
<body>
  <main>
    <div class=\"logo\">~A</div>
    <h1>~A</h1>
    <p>~A</p>
    ~A
  </main>
</body>
</html>"
     title +oauth-logo-svg+ heading message
     (if details
         (format nil "<div class=\"details\">~A</div>" details)
         ""))))

(defun oauth-success-html (message)
  (render-oauth-page
   "Authentication successful"
   "Authentication successful"
   message))

(defun oauth-error-html (message &optional details)
  (render-oauth-page
   "Authentication failed"
   "Authentication failed"
   message details))

(defun oauth-callback-response-copy
    (provider-name status reason details)
  (declare (ignore status))
  (values
   (case reason
     (:success
      (cond
        ((eq (oauth-callback-provider-key provider-name) :radius)
         "Signed in to Radius. You may now close this page.")
        (t
         (format nil
                 "~A authentication completed. You can close this window."
                 provider-name))))
     (:route-not-found "Callback route not found.")
     (:state-mismatch
      (if (eq (oauth-callback-provider-key provider-name) :radius)
          "OAuth state mismatch."
          "State mismatch."))
     (:provider-error
      (if (eq (oauth-callback-provider-key provider-name) :anthropic)
          "Anthropic authentication did not complete."
          (or details "OAuth authentication did not complete.")))
     (:missing-code-or-state "Missing code or state parameter.")
     (:missing-authorization-code "Missing authorization code.")
     (:internal-error
      "Internal error while processing OAuth callback.")
     (otherwise "OAuth authentication did not complete."))
   (and (eq reason :provider-error)
        (eq (oauth-callback-provider-key provider-name) :anthropic)
        details)))
