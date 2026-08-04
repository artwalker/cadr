(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defun cache-message
    (&key (model "test")
       (input 0)
       (cache-read 0)
       (cache-write 0)
       (cache-read-cost 0d0)
       (cache-write-cost 0d0)
       (timestamp 0))
  (cadr-ai:make-assistant-message
   :content nil
   :api :anthropic-messages
   :provider :test
   :model model
   :usage
   (cadr-ai:make-usage
    :input input
    :output 10
    :cache-read cache-read
    :cache-write cache-write
    :cost
    (cadr-ai:make-cost
     :cache-read cache-read-cost
     :cache-write cache-write-cost
     :total
     (+ cache-read-cost
        cache-write-cost)))
   :stop-reason :stop
   :timestamp timestamp))

(test cache-waste-detects-misses-model-switches-idle-and-resets
  (let* ((turn-one
           (cache-message
            :cache-write 100000
            :cache-write-cost 0.375d0
            :timestamp 0))
         (turn-two
           (cache-message
            :cache-read 100000
            :cache-write 5000
            :cache-read-cost 0.03d0
            :cache-write-cost 0.019d0
            :timestamp 60000))
         (turn-three
           (cache-message
            :cache-write 110000
            :cache-write-cost 0.4125d0
            :timestamp 600000))
         (price
           (lambda (provider model)
             (declare (ignore provider model))
             0.3d0))
         (miss
           (cadr-cli:detect-cache-miss
            (list turn-one turn-two)
            turn-three
            :model-price-function price))
         (totals
           (cadr-cli:compute-cache-waste
            (list turn-one turn-two
                  turn-three)
            :model-price-function price)))
    (is (= 105000
           (cadr-cli:cache-miss-missed-tokens
            miss)))
    (is (<
         (abs
          (-
           (cadr-cli:cache-miss-missed-cost
            miss)
           0.36225d0))
         0.000001d0))
    (is (= 540000
           (cadr-cli:cache-miss-idle-milliseconds
            miss)))
    (is (not
         (cadr-cli:cache-miss-model-changed-p
          miss)))
    (is (= 1
           (cadr-cli:cache-waste-miss-count
            totals)))
    (is (= 105000
           (cadr-cli:cache-waste-missed-tokens
            totals)))
    (let ((switched
            (cache-message
             :model "other"
             :cache-write 110000
             :cache-write-cost 0.4125d0
             :timestamp 120000)))
      (is
       (cadr-cli:cache-miss-model-changed-p
        (cadr-cli:detect-cache-miss
         (list turn-one turn-two)
         switched
         :model-price-function price))))
    (is (= 0
           (cadr-cli:cache-waste-miss-count
            (cadr-cli:compute-cache-waste
             (list turn-one :compaction
                   turn-three)
             :model-price-function price))))
    (is (null
         (cadr-cli:detect-cache-miss
          nil turn-one
          :model-price-function price)))))

(test first-time-setup-and-analytics-are-opt-in-and-stable
  (with-test-directory (root)
    (let ((path
            (merge-pathnames
             "settings.json" root)))
      (is
       (cadr-cli:should-run-first-time-setup-p
        path :experimental-value "1"))
      (is (not
           (cadr-cli:should-run-first-time-setup-p
            path :experimental-value nil)))
      (is (not
           (cadr-cli:should-run-first-time-setup-p
            path :experimental-value "1"
            :custom-agent-directory-p t)))
      (write-json path (args))
      (is (not
           (cadr-cli:should-run-first-time-setup-p
            path :experimental-value "1")))))
  (let ((manager
          (cadr-cli::make-memory-settings-manager)))
    (is (not
         (cadr-cli:settings-analytics-enabled-p
          manager)))
    (is (null
         (cadr-cli:settings-tracking-id
          manager)))
    (cadr-cli:settings-set-analytics
     manager t)
    (let ((tracking
            (cadr-cli:settings-tracking-id
             manager)))
      (is (= 36 (length tracking)))
      (cadr-cli:settings-set-analytics
       manager nil)
      (cadr-cli:settings-set-analytics
       manager t)
      (is (string=
           tracking
           (cadr-cli:settings-tracking-id
            manager))))))

(test proxy-environment-restoration-version-and-thinking-helpers
  (let ((environment
          '(("HTTP_PROXY" . "existing"))))
    (setf environment
          (cadr-cli:apply-http-proxy-setting
           "http://settings:7890"
           environment))
    (is (string=
         "existing"
         (cdr
          (assoc "HTTP_PROXY" environment
                 :test #'string=))))
    (is (string=
         "http://settings:7890"
         (cdr
          (assoc "HTTPS_PROXY" environment
                 :test #'string=)))))
  (is (equal
       '(("FOO" . "bar")
         ("BAZ" . "qux"))
       (cadr-cli:parse-null-environment
        (format nil "FOO=bar~CBAZ=qux~C"
                (code-char 0)
                (code-char 0)))))
  (let ((request
          (cadr-cli:version-check-request
           "1.2.3")))
    (is (string=
         "https://pi.dev/api/latest-version"
         (getf request :url)))
    (is (search
         "cadr/1.2.3"
         (cdr
          (assoc
           "User-Agent"
           (getf request :headers)
           :test #'string=)))))
  (let ((release
          (args
           "version" "1.2.4"
           "packageName" "@new/pi"
           "note" " **Read this** ")))
    (is (null
         (cadr-cli:newer-release
          "1.2.3" release
          :automatic-p t
          :skip-value "1")))
    (let ((newer
            (cadr-cli:newer-release
             "1.2.3" release)))
      (is (string=
           "**Read this**"
           (cadr-ai::json-get
            newer "note")))))
  (is (cadr-cli:valid-thinking-level-p
       "max"))
  (let ((theme
          (args
           "colors"
           (args
            "thinkingXhigh" "#abc"))))
    (is (string=
         "#abc"
         (cadr-cli:thinking-theme-color-name
          theme :max)))))

(test version-check-fetches-valid-release-and-keeps-automatic-skip-local
  (let* ((requests nil)
        (cadr-cli::*version-check-http-function*
          (lambda (url &key method headers
                    connect-timeout read-timeout
                    force-string
                    &allow-other-keys)
            (push
             (list :url url
                   :method method
                   :headers headers
                   :connect-timeout connect-timeout
                   :read-timeout read-timeout
                   :force-string force-string)
             requests)
            (values
             "{\"packageName\":\" @new/pi \",\"version\":\" 1.2.4 \",\"note\":\" **Read this** \"}"
             200 nil))))
    (let ((release
            (cadr-cli:get-latest-pi-release
             "1.2.3"
             :timeout-milliseconds 2500
             :offline-value nil)))
      (is (string=
           "1.2.4"
           (cadr-ai::json-get release "version")))
      (is (string=
           "@new/pi"
           (cadr-ai::json-get
            release "packageName")))
      (is (string=
           "**Read this**"
           (cadr-ai::json-get release "note"))))
    (let ((request (first requests)))
      (is (string=
           "https://pi.dev/api/latest-version"
           (getf request :url)))
      (is (eq :get (getf request :method)))
      (is (= 2.5d0
             (getf request :connect-timeout)))
      (is (= 2.5d0
             (getf request :read-timeout)))
      (is (getf request :force-string))
      (is (search
           "cadr/1.2.3"
           (cdr
            (assoc
             "User-Agent"
             (getf request :headers)
             :test #'string-equal)))))
    (is (null
         (cadr-cli:check-for-new-pi-version
          "1.2.3"
          :skip-value "1")))
    (is (= 1 (length requests)))
    (is (string=
         "1.2.4"
         (cadr-cli:get-latest-pi-version
          "1.2.3"
          :offline-value nil)))
    (is (= 2 (length requests)))
    (is (null
         (cadr-cli:get-latest-pi-release
          "1.2.3"
          :offline-value "1")))
    (is (= 2 (length requests)))))

(test version-check-validates-responses-and-swallows-automatic-errors
  (let ((cadr-cli::*version-check-http-function*
          (lambda (&rest arguments)
            (declare (ignore arguments))
            (values "{\"version\":\"\"}"
                    200 nil))))
    (is (null
         (cadr-cli:get-latest-pi-release
          "1.2.3"
          :offline-value nil))))
  (let ((cadr-cli::*version-check-http-function*
          (lambda (&rest arguments)
            (declare (ignore arguments))
            (values "{\"version\":\"9.9.9\"}"
                    503 nil))))
    (is (null
         (cadr-cli:get-latest-pi-release
          "1.2.3"
          :offline-value nil))))
  (let ((cadr-cli::*version-check-http-function*
          (lambda (&rest arguments)
            (declare (ignore arguments))
            (error "offline"))))
    (signals error
      (cadr-cli:get-latest-pi-version
       "1.2.3"
       :offline-value nil))
    (is (null
         (cadr-cli:check-for-new-pi-version
          "1.2.3"
          :skip-value nil
          :offline-value nil))))
  (let ((cadr-cli::*version-check-http-function*
          (lambda (&rest arguments)
            (declare (ignore arguments))
            (values "{\"version\":\"1.2.3\"}"
                    200 nil))))
    (is (null
         (cadr-cli:check-for-new-pi-version
          "1.2.3"
          :skip-value nil
          :offline-value nil)))))

(test system-prompt-lists-only-described-tools-and-dedupes-guidelines
  (let ((prompt
          (cadr-cli:build-system-prompt
           :selected-tools
           '("read" "dynamic" "undescribed")
           :tool-snippets
           '(("read" . "Read file contents")
             ("dynamic" . "Run dynamic behavior"))
           :prompt-guidelines
           '("Use dynamic."
             "  Use dynamic.  "
             "  ")
           :cwd "/tmp/project"
           :docs-directory "/opt/pi/docs"
           :examples-directory
           "/opt/pi/examples")))
    (is (search
         "- read: Read file contents"
         prompt))
    (is (search
         "- dynamic: Run dynamic behavior"
         prompt))
    (is (not
         (search "undescribed" prompt)))
    (is (= 1
           (count-substring
            "- Use dynamic." prompt)))
    (is (search
         "Show file paths clearly"
         prompt))
    (is (search
         "- Additional docs: /opt/pi/docs"
         prompt)))
  (is (search
       "Available tools:"
       (cadr-cli:build-system-prompt
        :selected-tools nil
        :tool-snippets nil)))
  (is (search
       "(none)"
       (cadr-cli:build-system-prompt
        :selected-tools nil
        :tool-snippets nil)))
  (with-test-directory (root)
    (let ((context
            (merge-pathnames "AGENTS.md" root))
          (skill
            (cadr-agent:make-skill
             :name "review"
             :description "Review code"
             :file-path "/tmp/review/SKILL.md")))
      (write-text context "Project rules")
      (let ((prompt
              (cadr-cli:build-system-prompt
               :custom-prompt "Custom"
               :append-system-prompt "Append"
               :selected-tools '("read")
               :context-files (list context)
               :skills (list skill)
               :cwd "/tmp/project")))
        (is (search "Custom" prompt))
        (is (search "Append" prompt))
        (is (search "<project_context>" prompt))
        (is (search "Project rules" prompt))
        (is (search "review" prompt))
        (is (search
             "Current working directory: /tmp/project"
             prompt))))))

(test provider-lifecycle-extension-hooks-run-on-the-real-stream-surface
  (let ((request-payload nil)
        (request-headers nil)
        (response-payload nil)
        (seen nil))
    (let* ((bundle
             (let ((bundle
                     (cadr-agent::make-extension-bundle
                      :id "provider-hooks"
                      :path
                      "/tmp/provider-hooks.lisp")))
               (cadr-agent::call-with-extension-registration
                bundle
                (lambda ()
                (cadr-agent:define-event-hook
                 :before-provider-request
                 :handler
                 (lambda (event context)
                   (declare (ignore context))
                   (push :before-provider-request seen)
                   (let ((payload
                           (getf
                            (cadr-agent:extension-event-payload
                             event)
                            :payload)))
                     (setf (getf payload :trace)
                           "request")
                     payload)))
                (cadr-agent:define-event-hook
                 :before-provider-headers
                 :handler
                 (lambda (event context)
                   (declare (ignore context))
                   (push :before-provider-headers seen)
                   (setf
                    (gethash
                     "X-Extension"
                     (getf
                      (cadr-agent:extension-event-payload
                       event)
                      :headers))
                    "headers")
                   nil))
                (cadr-agent:define-event-hook
                 :after-provider-response
                 :handler
                 (lambda (event context)
                   (declare (ignore context))
                   (push :after-provider-response seen)
                   (setf response-payload
                         (cadr-agent:extension-event-payload
                          event))
                   nil))))
               bundle))
           (host
             (cadr-agent::make-extension-host))
           (stream
             (cadr-cli::make-extension-aware-stream-function
              host
              :stream-function
              (lambda
                  (provider model context on-event
                   &key on-payload transform-headers
                     on-response &allow-other-keys)
                (declare
                 (ignore provider context on-event))
                (setf request-payload
                      (funcall on-payload
                               (list :original t)
                               model)
                      request-headers
                      (funcall transform-headers
                               '(("Original" . "yes"))))
                (funcall
                 on-response
                 (list
                  :status 204
                  :headers
                  '(("X-Response" . "ok")))
                 model)
                :streamed))))
      (cadr-agent::replace-extension-bundles
       host (list bundle))
      (is (eq :streamed
              (funcall
               stream nil
               (cadr-ai:make-model
                :id "mock"
                :provider :openai
                :api :openai-responses)
               (cadr-ai:make-context)
               (lambda (event)
                 (declare (ignore event))))))
      (dolist (event '(:before-provider-request
                       :before-provider-headers
                       :after-provider-response))
        (is (member event seen)))
      (is (string=
           "request"
           (getf request-payload :trace)))
      (is (string=
           "headers"
           (cdr
            (assoc "X-Extension"
                   request-headers
                   :test #'string-equal))))
      (is (= 204
             (getf response-payload
                   :status))))))
