(in-package #:cadr-ai)

;;; HTTP proxy environment resolution

(defparameter +unsupported-proxy-protocol-message+
  "Unsupported proxy protocol. SOCKS and PAC proxy URLs are not supported; use an HTTP or HTTPS proxy URL.")

(defun proxy-environment-value (name environment)
  (or (cdr (assoc name environment :test #'string-equal))
      (uiop:getenv (string-downcase name))
      (uiop:getenv (string-upcase name))))

(defun target-url-parts (url)
  (let* ((scheme-end (search "://" url))
         (scheme (and scheme-end (string-downcase (subseq url 0 scheme-end))))
         (authority-start (and scheme-end (+ scheme-end 3)))
         (authority-end (and authority-start
                             (or (position #\/ url :start authority-start)
                                 (length url))))
         (authority (and authority-start (subseq url authority-start authority-end)))
         (colon (and authority (position #\: authority :from-end t)))
         (host (and authority (if colon (subseq authority 0 colon) authority)))
         (port (and colon (parse-integer authority :start (1+ colon) :junk-allowed t))))
    (values scheme host
            (or port (cdr (assoc scheme '(("ftp" . 21) ("gopher" . 70)
                                          ("http" . 80) ("https" . 443)
                                          ("ws" . 80) ("wss" . 443))
                                :test #'string=))))))

(defun no-proxy-match-p (host port no-proxy)
  (when (string= no-proxy "*")
    (return-from no-proxy-match-p t))
  (some
   (lambda (entry)
     (let* ((entry (string-downcase entry))
            (colon (position #\: entry :from-end t))
            (entry-port (and colon
                             (parse-integer entry :start (1+ colon)
                                            :junk-allowed t)))
            (pattern (if colon (subseq entry 0 colon) entry)))
       (and (plusp (length pattern))
            (or (null entry-port) (= entry-port port))
            (if (or (char= (char pattern 0) #\.)
                    (char= (char pattern 0) #\*))
                (uiop:string-suffix-p
                 host
                 (if (char= (char pattern 0) #\*)
                     (subseq pattern 1)
                     pattern))
                (string= pattern host)))))
   (uiop:split-string no-proxy :separator '(#\, #\Space #\Tab #\Newline))))

(defun resolve-http-proxy-url-for-target (target-url &optional environment)
  (multiple-value-bind (scheme host port)
      (target-url-parts target-url)
    (unless (and scheme host port)
      (return-from resolve-http-proxy-url-for-target nil))
    (let ((no-proxy
            (string-downcase
             (or (proxy-environment-value "NO_PROXY" environment) ""))))
      (when (and (plusp (length no-proxy))
                 (no-proxy-match-p (string-downcase host) port no-proxy))
        (return-from resolve-http-proxy-url-for-target nil)))
    (let ((proxy
            (or (proxy-environment-value
                 (format nil "~A_PROXY" (string-upcase scheme)) environment)
                (proxy-environment-value "ALL_PROXY" environment))))
      (unless (and proxy (plusp (length proxy)))
        (return-from resolve-http-proxy-url-for-target nil))
      (unless (search "://" proxy)
        (setf proxy (format nil "~A://~A" scheme proxy)))
      (let ((proxy-scheme
              (string-downcase (subseq proxy 0 (or (search "://" proxy) 0)))))
        (unless (member proxy-scheme '("http" "https") :test #'string=)
          (error "~A Got ~A:" +unsupported-proxy-protocol-message+
                 proxy-scheme)))
      proxy)))
