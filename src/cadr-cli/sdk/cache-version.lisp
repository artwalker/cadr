(in-package #:cadr-cli)

(defstruct cache-miss
  (missed-tokens 0 :type (integer 0 *))
  (missed-cost 0d0 :type double-float)
  (idle-milliseconds 0 :type integer)
  (model-changed-p nil :type boolean)
  message)

(defstruct cache-waste
  (missed-tokens 0 :type (integer 0 *))
  (missed-cost 0d0 :type double-float)
  (miss-count 0 :type (integer 0 *))
  (misses nil :type list))

(defun assistant-cache-usage (message)
  (let ((usage
          (cadr-ai:assistant-message-usage
           message)))
    (values
     (cadr-ai:usage-input usage)
     (cadr-ai:usage-cache-read usage)
     (cadr-ai:usage-cache-write usage)
     (cadr-ai:cost-cache-read
      (cadr-ai:usage-cost usage))
     (cadr-ai:cost-cache-write
      (cadr-ai:usage-cost usage)))))

(defun assistant-prompt-tokens (message)
  (multiple-value-bind
        (input cache-read cache-write
         ignored-read-cost ignored-write-cost)
      (assistant-cache-usage message)
    (declare (ignore ignored-read-cost ignored-write-cost))
    (+ input cache-read cache-write)))

(defun assistant-reported-cache-p (message)
  (multiple-value-bind
        (ignored-input cache-read cache-write
         ignored-read-cost ignored-write-cost)
      (assistant-cache-usage message)
    (declare
     (ignore ignored-input ignored-read-cost ignored-write-cost))
    (plusp (+ cache-read cache-write))))

(defun cache-read-price-per-million
    (message model-price-function)
  (or
   (and model-price-function
        (funcall
         model-price-function
         (cadr-ai:assistant-message-provider
          message)
         (cadr-ai:assistant-message-model
          message)))
   0d0))

(defun detect-cache-miss
    (prior-messages current-message
     &key model-price-function)
  (let ((previous
          (find-if
           (lambda (item)
             (typep item
                    'cadr-ai:assistant-message))
           prior-messages
           :from-end t)))
    (unless previous
      (return-from detect-cache-miss nil))
    (multiple-value-bind
          (current-input current-read current-write
           current-read-cost current-write-cost)
        (assistant-cache-usage current-message)
      (let* ((prompt-tokens
               (+ current-input current-read current-write))
             (reported-cache-p
               (or
                (some #'assistant-reported-cache-p
                      prior-messages)
                (plusp (+ current-read current-write)))))
        (unless
            (and
             (plusp prompt-tokens)
             (or reported-cache-p
                 (plusp (+ current-read current-write))))
          (return-from detect-cache-miss nil))
        (let ((missed-tokens
                (-
                 (min
                  (assistant-prompt-tokens previous)
                  prompt-tokens)
                 current-read)))
          (when (<= missed-tokens 1024)
            (return-from detect-cache-miss nil))
          (let* ((paid-tokens (+ current-input current-write))
                 (cost
                   (cadr-ai:usage-cost
                    (cadr-ai:assistant-message-usage
                     current-message)))
                 (paid-per-token
                   (if (plusp paid-tokens)
                       (/ (+ (cadr-ai:cost-input cost)
                             current-write-cost)
                          paid-tokens)
                       0d0))
                 (read-per-token
                   (if (plusp current-read)
                       (/ current-read-cost current-read)
                       (/
                        (cache-read-price-per-million
                         current-message model-price-function)
                        1000000d0)))
                 (missed-cost
                   (* missed-tokens
                      (max 0d0
                           (- paid-per-token
                              read-per-token)))))
            (make-cache-miss
             :missed-tokens missed-tokens
             :missed-cost missed-cost
             :idle-milliseconds
             (max
              0
              (-
               (cadr-ai:assistant-message-timestamp
                current-message)
               (cadr-ai:assistant-message-timestamp
                previous)))
             :model-changed-p
             (not
              (and
               (eq
                (cadr-ai:assistant-message-provider
                 previous)
                (cadr-ai:assistant-message-provider
                 current-message))
               (string=
                (cadr-ai:assistant-message-model previous)
                (cadr-ai:assistant-message-model
                 current-message))))
             :message current-message)))))))

(defun compute-cache-waste
    (items &key model-price-function)
  (let ((prior nil)
        (misses nil))
    (dolist (item items)
      (cond
        ((or
          (member item '(:compaction :branch-summary))
          (and
           (typep item 'cadr-agent:session-entry)
           (member
            (cadr-agent:session-entry-type item)
            '(:compaction :branch-summary))))
         (setf prior nil))
        (t
         (let ((message
                 (if (typep item 'cadr-agent:session-entry)
                     (cadr-agent:session-entry-message item)
                     item)))
           (when (typep message 'cadr-ai:assistant-message)
             (let ((miss
                     (detect-cache-miss
                      prior message
                      :model-price-function
                      model-price-function)))
               (when miss
                 (push miss misses)))
             (setf prior
                   (append prior (list message))))))))
    (setf misses (nreverse misses))
    (make-cache-waste
     :missed-tokens
     (loop for miss in misses
           sum (cache-miss-missed-tokens miss))
     :missed-cost
     (coerce
      (loop for miss in misses
            sum (cache-miss-missed-cost miss))
      'double-float)
     :miss-count (length misses)
     :misses misses)))

(defun should-run-first-time-setup-p
    (settings-path
     &key experimental-value
       custom-agent-directory-p
       forked-package-p)
  (and
   (experimental-features-enabled-p
    experimental-value)
   (not custom-agent-directory-p)
   (not forked-package-p)
   (not (probe-file settings-path))))

(defun settings-analytics-enabled-p (manager)
  (eq t
      (settings-value
       manager "enableAnalytics" nil)))

(defun settings-tracking-id (manager)
  (settings-value manager "trackingId"))

(defun settings-set-analytics
    (manager enabled-p)
  (when
      (and enabled-p
           (null
            (settings-tracking-id manager)))
    (settings-set
     manager "trackingId"
     (cadr-ai:uuid-v7)))
  (settings-set
   manager "enableAnalytics"
   (not (null enabled-p)))
  enabled-p)

(defun apply-http-proxy-setting
    (proxy &optional environment)
  (let ((trimmed
          (and proxy
               (string-trim
                '(#\Space #\Tab #\Newline #\Return)
                proxy))))
    (when (and trimmed
               (plusp (length trimmed)))
      (if environment
          (dolist (name
                   '("HTTP_PROXY" "HTTPS_PROXY"))
            (unless
                (assoc name environment
                       :test #'string=)
              (setf environment
                    (acons name trimmed
                           environment))))
          (dolist (name
                   '("HTTP_PROXY" "HTTPS_PROXY"))
            (unless (uiop:getenv name)
              (sb-posix:setenv
               name trimmed 0))))))
  environment)

(defun parse-null-environment (contents)
  (let ((environment nil))
    (dolist
        (entry
         (uiop:split-string
          contents :separator
          (list (code-char 0))))
      (let ((equals (position #\= entry)))
        (when (and equals
                   (plusp equals))
          (push
           (cons
            (subseq entry 0 equals)
            (subseq entry (1+ equals)))
           environment))))
    (nreverse environment)))

(defun restore-empty-sandbox-environment
    (&key bun-p environment
       (environ-path #p"/proc/self/environ"))
  (if (or (not bun-p)
          environment
          (not (probe-file environ-path)))
      environment
      (parse-null-environment
       (uiop:read-file-string
        environ-path
        :external-format :latin-1))))

(defun version-check-request (version)
  (list
   :url "https://pi.dev/api/latest-version"
   :headers
   `(("User-Agent" . ,(pi-user-agent version))
     ("Accept" . "application/json"))))

(defparameter *version-check-http-function* nil)

(defun nonempty-environment-value-p (value)
  (and (stringp value)
       (plusp (length value))))

(defun release-string-field (release key)
  (let ((value
          (and
           (hash-table-p release)
           (cadr-ai::json-get release key))))
    (when (stringp value)
      (let ((trimmed
              (string-trim
               '(#\Space #\Tab #\Newline #\Return)
               value)))
        (and (plusp (length trimmed))
             trimmed)))))

(defun normalize-latest-pi-release (release)
  (let ((version
          (release-string-field
           release "version")))
    (when version
      (let ((normalized
              (make-hash-table :test #'equal))
            (package-name
              (release-string-field
               release "packageName"))
            (note
              (release-string-field
               release "note")))
        (cadr-ai::json-put
         normalized "version" version)
        (when package-name
          (cadr-ai::json-put
           normalized "packageName"
           package-name))
        (when note
          (cadr-ai::json-put
           normalized "note" note))
        normalized))))

(defun get-latest-pi-release
    (current-version
     &key
       (timeout-milliseconds 10000)
       (offline-value
         (uiop:getenv "PI_OFFLINE")))
  (when (nonempty-environment-value-p
         offline-value)
    (return-from get-latest-pi-release
      nil))
  (let* ((request
           (version-check-request
            current-version))
         (timeout-seconds
           (/ timeout-milliseconds
              1000d0))
         (http-function
           (or *version-check-http-function*
               cadr-ai:*http-request-function*)))
    (multiple-value-bind
          (body status headers)
        (funcall
         http-function
         (getf request :url)
         :method :get
         :headers (getf request :headers)
         :connect-timeout timeout-seconds
         :read-timeout timeout-seconds
         :want-stream nil
         :force-string t)
      (declare (ignore headers))
      (when (and
             (integerp status)
             (<= 200 status 299))
        (normalize-latest-pi-release
         (cadr-ai::parse-json body))))))

(defun get-latest-pi-version
    (current-version
     &rest options
     &key &allow-other-keys)
  (let ((release
          (apply #'get-latest-pi-release
                 current-version
                 options)))
    (and release
         (cadr-ai::json-get
          release "version"))))

(defun newer-package-version-p
    (candidate current)
  (let ((comparison
          (compare-package-versions
           candidate current)))
    (if (numberp comparison)
        (plusp comparison)
        (not
         (string=
          (string-trim
           '(#\Space #\Tab #\Newline #\Return)
           candidate)
          (string-trim
           '(#\Space #\Tab #\Newline #\Return)
           current))))))

(defun check-for-new-pi-version
    (current-version
     &key
       (skip-value
         (uiop:getenv
          "PI_SKIP_VERSION_CHECK"))
       (offline-value
         (uiop:getenv "PI_OFFLINE"))
       (timeout-milliseconds 10000))
  (when (nonempty-environment-value-p
         skip-value)
    (return-from check-for-new-pi-version
      nil))
  (handler-case
      (let ((release
              (get-latest-pi-release
               current-version
               :offline-value offline-value
               :timeout-milliseconds
               timeout-milliseconds)))
        (and
         release
         (newer-package-version-p
          (cadr-ai::json-get
           release "version")
          current-version)
         release))
    (condition () nil)))

(defun newer-release (current release
                      &key automatic-p
                        skip-value)
  (when (and
         (or (not automatic-p)
             (not
              (nonempty-environment-value-p
               skip-value)))
         (hash-table-p release)
         (stringp
          (cadr-ai::json-get release "version"))
         (plusp
          (compare-package-versions
           (cadr-ai::json-get release
                              "version")
           current)))
    (let ((copy
            (cadr-ai::copy-json-value
             release)))
      (let ((note
              (cadr-ai::json-get copy "note")))
        (when (stringp note)
          (cadr-ai::json-put
           copy "note"
           (string-trim
            '(#\Space #\Tab #\Newline #\Return)
            note))))
      copy)))

(defun valid-thinking-level-p (value)
  (not
   (null
    (member
     (string-downcase value)
     +thinking-level-names+
     :test #'string=))))

(defun thinking-theme-color-name
    (theme level)
  (let* ((colors
           (cadr-ai::json-get theme "colors"))
         (name
           (format nil
                   "thinking~:(~A~)"
                   (string-downcase
                    (etypecase level
                      (symbol (symbol-name level))
                      (string level))))))
    (or
     (cadr-ai::json-get colors name)
     (and
      (string-equal
       (etypecase level
         (symbol (symbol-name level))
         (string level))
       "max")
      (cadr-ai::json-get
       colors "thinkingXhigh")))))
