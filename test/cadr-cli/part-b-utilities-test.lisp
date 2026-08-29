(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(test strip-ansi-covers-csi-osc-ris-and-single-byte-sequences
  (is (string=
       "aredlinkz"
       (cadr-cli::strip-ansi
        (format nil
                "a~C[31mred~C[0m~C]8;;https://example.com~Clink~C]8;;~Cz"
                #\Escape #\Escape #\Escape
                (code-char 7) #\Escape (code-char 7)))))
  (is (string= "done"
               (cadr-cli::strip-ansi
                (format nil "~Ccdone" #\Escape))))
  (dolist (character '(#\g #\h #\i #\j #\k #\l #\m
                       #\r #\s #\t))
    (is (string=
         "ok"
         (cadr-cli::strip-ansi
          (format nil "~C~Cok" #\Escape character)))))
  (signals type-error (cadr-cli::strip-ansi 42)))

(test goal16-cli-runtime-flags-use-only-cadr-environment
  (let ((previous-cadr-experimental
          (uiop:getenv "CADR_EXPERIMENTAL"))
        (previous-pi-experimental
          (uiop:getenv "PI_EXPERIMENTAL"))
        (previous-cadr-offline
          (uiop:getenv "CADR_OFFLINE"))
        (previous-pi-offline
          (uiop:getenv "PI_OFFLINE")))
    (unwind-protect
         (progn
           (sb-posix:unsetenv "CADR_EXPERIMENTAL")
           (sb-posix:setenv "PI_EXPERIMENTAL" "1" 1)
           (is (not (cadr-cli::experimental-features-enabled-p)))
           (sb-posix:setenv "CADR_EXPERIMENTAL" "1" 1)
           (is (cadr-cli::experimental-features-enabled-p))
           (sb-posix:unsetenv "CADR_OFFLINE")
           (sb-posix:setenv "PI_OFFLINE" "1" 1)
           (is (not (cadr-cli::offline-mode-p)))
           (sb-posix:setenv "CADR_OFFLINE" "1" 1)
           (is (cadr-cli::offline-mode-p)))
      (dolist (entry
               `(("CADR_EXPERIMENTAL" ,previous-cadr-experimental)
                 ("PI_EXPERIMENTAL" ,previous-pi-experimental)
                 ("CADR_OFFLINE" ,previous-cadr-offline)
                 ("PI_OFFLINE" ,previous-pi-offline)))
        (if (second entry)
            (sb-posix:setenv (first entry) (second entry) 1)
            (sb-posix:unsetenv (first entry)))))))

(test ensure-tool-offline-on-status-emits-warning
  (let ((previous-offline (uiop:getenv "CADR_OFFLINE"))
        (previous-path (uiop:getenv "PATH"))
        (events nil))
    (unwind-protect
         (progn
           (sb-posix:setenv "CADR_OFFLINE" "1" 1)
           (sb-posix:setenv "PATH" "/nonexistent-cadr-tool-path" 1)
           (is (null
                (cadr-cli:ensure-tool
                 :fd
                 :on-status
                 (lambda (type message)
                   (push (cons type message) events)))))
           (is (equal
                '((:warning . "fd not found. Offline mode enabled, skipping download."))
                (reverse events))))
      (if previous-offline
          (sb-posix:setenv "CADR_OFFLINE" previous-offline 1)
          (sb-posix:unsetenv "CADR_OFFLINE"))
      (if previous-path
          (sb-posix:setenv "PATH" previous-path 1)
          (sb-posix:unsetenv "PATH")))))

(test changelog-links-are-tag-pinned-and-canonical
  (let* ((input
           (format nil
                   "[Project](README.md#x)~%[Examples](examples/extensions/)~%[#1](https://github.com/badlogic/pi-mono/issues/1)~%[External](https://example.com/docs)"))
         (output
           (cadr-cli::normalize-changelog-links
            input "0.79.0")))
    (is (search
         "https://github.com/artwalker/cadr/blob/v0.79.0/packages/coding-agent/README.md#x"
         output))
    (is (search
         "https://github.com/artwalker/cadr/tree/v0.79.0/packages/coding-agent/examples/extensions/"
         output))
    (is (search
         "https://github.com/artwalker/cadr/issues/1"
         output))
    (is (search "https://example.com/docs" output))))

(test changelog-parsing-and-share-command-keep-version-and-argv-semantics
  (is (string=
       "https://cadr.dev/session/"
       (cadr-ai::cadr-default-share-viewer-url)))
  (let ((previous-cadr
          (uiop:getenv "CADR_SHARE_VIEWER_URL"))
        (previous-pi
          (uiop:getenv "PI_SHARE_VIEWER_URL")))
    (unwind-protect
         (progn
           (sb-posix:unsetenv "CADR_SHARE_VIEWER_URL")
           (sb-posix:setenv
            "PI_SHARE_VIEWER_URL"
            "https://upstream.invalid/session/" 1)
           (is (string=
                "https://cadr.dev/session/#default"
                (cadr-cli::share-viewer-url "default")))
           (sb-posix:setenv
            "CADR_SHARE_VIEWER_URL"
            "https://viewer.example/session/" 1)
           (is (string=
                "https://viewer.example/session/#override"
                (cadr-cli::share-viewer-url "override"))))
      (if previous-cadr
          (sb-posix:setenv
           "CADR_SHARE_VIEWER_URL" previous-cadr 1)
          (sb-posix:unsetenv "CADR_SHARE_VIEWER_URL"))
      (if previous-pi
          (sb-posix:setenv
           "PI_SHARE_VIEWER_URL" previous-pi 1)
          (sb-posix:unsetenv "PI_SHARE_VIEWER_URL"))))
  (with-test-directory (root)
    (let ((path
            (merge-pathnames "CHANGELOG.md" root)))
      (cadr-cli::write-utf8-file
       path
       (format
        nil
        "# Changelog~%~%## [0.2.0] - 2026-01-02~%~%New.~%~%## malformed~%ignored~%~%## 0.1.0~%~%Old.~%"))
      (let ((entries
              (cadr-cli::parse-changelog path)))
        (is (= 2 (length entries)))
        (is (string= "0.2.0"
                     (getf (first entries)
                           :version)))
        (is (search "## [0.2.0]"
                    (getf (first entries)
                          :content)))
        (is (string= "0.1.0"
                     (getf (second entries)
                           :version)))))
    (let ((session
            (cadr-agent:create-session
             :directory
             (merge-pathnames "sessions/" root)
             :cwd root
             :id "share"))
          (calls nil))
      (cadr-agent:session-append-message
       session
       (cadr-ai:make-assistant-message
        :content
        (list
         (cadr-ai:make-text-content
          :text "share me"))
        :api :openai-responses
        :provider :openai
        :model "mock"
        :stop-reason :stop))
      (multiple-value-bind
            (viewer gist)
          (cadr-cli::share-session-as-gist
           session
           :viewer-base-url
           "https://viewer.invalid/session/"
           :runner
           (lambda (argv)
             (push argv calls)
             (cond
               ((equal argv
                       '("gh" "auth" "status"))
                (values "" "" 0))
               ((and
                 (equal
                  '("gh" "gist" "create"
                    "--public=false")
                  (butlast argv))
                 (probe-file (car (last argv))))
                (values
                 (format nil
                         "https://gist.github.com/me/abc123~%")
                 "" 0))
               (t
                (values "" "unexpected argv" 1)))))
        (is (string=
             "https://viewer.invalid/session/#abc123"
             viewer))
        (is (string=
             "https://gist.github.com/me/abc123"
             gist))
        (is (= 2 (length calls))))
      (multiple-value-bind (agent remaining)
          (cli-faux-agent nil)
        (declare (ignore remaining))
        (setf (cadr-agent:agent-session agent) session
              (cadr-agent:agent-messages agent)
              (cadr-agent:session-messages session))
        (let ((output (make-string-output-stream)))
          (is
           (cadr-cli::handle-session-command
            "/share" agent :output output
            :share-runner
            (lambda (argv)
              (cond
                ((equal argv
                        '("gh" "auth" "status"))
                 (values "" "" 0))
                ((string=
                  "gh"
                  (first argv))
                 (values
                  "https://gist.github.com/me/abc123"
                  "" 0))
                (t
                 (values "" "unexpected argv" 1))))))
          (let ((rendered
                  (get-output-stream-string output)))
            (is (search
                 "Share URL: https://cadr.dev/session/#abc123"
                 rendered))
            (is (search
                 "Gist: https://gist.github.com/me/abc123"
                 rendered))))))))

(test html-export-escapes-attributes-and-sanitizes-urls
  (is (string=
       "&lt;&quot;&amp;&#39;&gt;"
       (cadr-cli::escape-html "<\"&'>")))
  (is (string=
       "https://example.com/a&amp;b"
       (cadr-cli::safe-html-url
        "https://example.com/a&b")))
  (is (null
       (cadr-cli::safe-html-url
        (format nil "java~Cscript:alert(1)"
                (code-char 0)))))
  (is (null
       (cadr-cli::safe-html-url
        "data:text/html;base64,evil")))
  (is (string=
       "data:image/png;base64,AAAA"
       (cadr-cli::safe-html-url
        "data:image/png;base64,AAAA"
        :image-p t))))

(test experimental-resume-user-agent-and-version-utilities
  (is (cadr-cli::experimental-features-enabled-p "1"))
  (is (not (cadr-cli::experimental-features-enabled-p "0")))
  (is (not (cadr-cli::experimental-features-enabled-p nil)))
  (is (string=
       "cadr --session test-session"
       (cadr-cli::format-resume-command
        "test-session"
        :persisted-p t
        :session-file "/tmp/session.jsonl"
        :session-file-exists-p t
        :terminal-p t
        :default-session-directory-p t)))
  (is (string=
       "cadr --session-dir '/tmp/custom pi'\\''s' --session test-session"
       (cadr-cli::format-resume-command
        "test-session"
        :persisted-p t
        :session-file "/tmp/session.jsonl"
        :session-file-exists-p t
        :terminal-p t
        :default-session-directory-p nil
        :session-directory "/tmp/custom pi's")))
  (is (string=
       "cadr --session-dir /tmp/custom --session test-session"
       (cadr-cli::format-resume-command
        "test-session"
        :persisted-p t
        :session-file "/tmp/session.jsonl"
        :session-file-exists-p t
        :terminal-p t
        :default-session-directory-p nil
        :session-directory "/tmp/custom")))
  (is (null
       (cadr-cli::format-resume-command
        "test" :terminal-p nil)))
  (is (null
       (cadr-cli::format-resume-command
        "test"
        :terminal-p t
        :persisted-p nil
        :session-file "/tmp/session.jsonl"
        :session-file-exists-p t)))
  (is (null
       (cadr-cli::format-resume-command
        "test"
        :terminal-p t
        :persisted-p t
        :session-file nil
        :session-file-exists-p t)))
  (is (null
       (cadr-cli::format-resume-command
        "test"
        :terminal-p t
        :persisted-p t
        :session-file "/tmp/missing.jsonl"
        :session-file-exists-p nil)))
  (is (> (cadr-cli::compare-package-versions
          "5.0.0-beta.20" "5.0.0-beta.9")
         0))
  (is (= 0 (cadr-cli::compare-package-versions
            "0.70.5" "0.70.5")))
  (is (string= "cadr" (cadr-ai::cadr-product-slug)))
  (is (string= "Cadr" (cadr-ai::cadr-product-display-name)))
  (is (string=
       "https://github.com/artwalker/cadr"
       (cadr-ai::cadr-canonical-repository-url)))
  (is (search
       "cadr/0.83.0 ("
       (cadr-cli::cadr-user-agent "0.83.0"))))

(test git-source-parser-accepts-supported-forms-and-rejects-traversal
  (let ((https
          (cadr-cli::parse-git-source
           "https://github.com/user/repo@v1.0.0"))
        (ssh
          (cadr-cli::parse-git-source
           "git:git@github.com:user/repo"))
        (short
          (cadr-cli::parse-git-source
           "git:github.com/user/repo")))
    (is (string= "github.com" (getf https :host)))
    (is (string= "user/repo" (getf https :path)))
    (is (string= "v1.0.0" (getf https :ref)))
    (is (string=
         "git@github.com:user/repo"
         (getf ssh :repository)))
    (is (string=
         "https://github.com/user/repo"
         (getf short :repository))))
  (dolist
      (source
       '("git@github.com:user/repo"
         "github.com/user/repo"
         "git:git@evil.example:../../victim/repo"
         "https://evil.example/..%2F..%2Fvictim/repo"
         "git:git@evil.example:/absolute/repo"
         "git:git@evil.example:user\\repo/name"))
    (is (null
         (cadr-cli::parse-git-source source)))))

(test provider-attribution-and-stream-settings-follow-baseline-precedence
  (flet ((header (name headers)
           (cdr (assoc name headers :test #'string-equal))))
    (let ((openrouter
            (cadr-cli::provider-attribution-headers
             :provider :openrouter :telemetry-p t))
          (nvidia
            (cadr-cli::provider-attribution-headers
             :provider :nvidia :telemetry-p t))
          (cloudflare
            (cadr-cli::provider-attribution-headers
             :provider :cloudflare-workers-ai :telemetry-p t))
          (opencode
            (cadr-cli::provider-attribution-headers
             :provider :opencode :session-id "session")))
      (is (string= "https://github.com/artwalker/cadr"
                   (header "HTTP-Referer" openrouter)))
      (is (string= "cadr"
                   (header "X-OpenRouter-Title" openrouter)))
      (is (string= "cadr"
                   (header "X-BILLING-INVOKE-ORIGIN" nvidia)))
      (is (string= "cadr-coding-agent"
                   (header "User-Agent" cloudflare)))
      (is (string= "cadr"
                   (header "x-opencode-client" opencode)))))
  (let ((headers
          (cadr-cli::provider-attribution-headers
           :provider :openrouter
           :base-url "https://openrouter.ai/api/v1"
           :telemetry-p t
           :provider-headers
           '(("HTTP-Referer" . "https://custom.example"))
           :request-headers
           '(("X-Title" . "Custom")))))
    (is (string=
         "https://custom.example"
         (cdr (assoc "HTTP-Referer" headers
                     :test #'string-equal))))
    (is (string=
         "Custom"
         (cdr (assoc "X-Title" headers
                     :test #'string-equal)))))
  (let ((options
          (cadr-cli::merge-stream-settings
           '(:http-idle-timeout-ms 300000
             :websocket-connect-timeout-ms 10000
             :retry (:maximum-retries 3))
           '(:timeout-ms 1000))))
    (is (= 1000 (getf options :timeout-ms)))
    (is (= 10000
           (getf options
                 :websocket-connect-timeout-ms)))
    (is (= 3
           (getf (getf options :retry)
                 :maximum-retries)))))

(test compare-package-versions-walks-tokens-not-nth
  (is (> (cadr-cli::compare-package-versions "5.0.0-beta.20"
                                             "5.0.0-beta.9")
         0))
  (is (< (cadr-cli::compare-package-versions "1.0" "1.0.1")
         0))
  (is (= 0 (cadr-cli::compare-package-versions "1.0" "1.0.0"))))

(test optional-integer-coerces-json-null-to-default
  (let ((arguments (cadr-ai::json-object "limit" 'null)))
    (is (= 500 (cadr-cli::optional-integer arguments "limit" 500))))
  (let ((arguments (cadr-ai::json-object)))
    (is (= 500 (cadr-cli::optional-integer arguments "limit" 500))))
  (let ((arguments (cadr-ai::json-object "limit" 12)))
    (is (= 12 (cadr-cli::optional-integer arguments "limit" 500)))))

(test git-url-prefix-is-case-sensitive
  (is (cadr-cli::string-prefix-p "git:" "git:https://example.com"))
  (is (not (cadr-cli::string-prefix-p
            "git:" "GIT:https://example.com"))))

(test xterm-16-table-is-a-vector
  (is (equal '(0 0 0) (cadr-cli::xterm-color-to-rgb 0)))
  (is (equal '(255 255 255) (cadr-cli::xterm-color-to-rgb 15)))
  (is (equal '(255 0 0) (cadr-cli::xterm-color-to-rgb 9))))

(test llama-positive-number-owns-context-window-guard
  (is (null (cadr-cli::llama-positive-number 0)))
  (is (null (cadr-cli::llama-positive-number "8")))
  (is (= 4096 (cadr-cli::llama-positive-number 4096))))

(test kebab-keyword-to-camel-owns-tool-result-keys
  (is (string= "fullOutputPath"
               (cadr-cli::kebab-keyword-to-camel :full-output-path)))
  (is (string= "diff" (cadr-cli::kebab-keyword-to-camel :diff)))
  (is (string= "resultLimitReached"
               (cadr-cli::kebab-keyword-to-camel :result-limit-reached))))

(test format-key-text-star-matches-string-wrapper
  (is (string=
       (cadr-cli::format-key-text "ctrl+c/escape")
       (cadr-cli::format-key-text* '("ctrl+c" "escape"))))
  (is (string=
       (cadr-cli::format-key-text "alt+enter" :capitalize-p t)
       (cadr-cli::format-key-text* '("alt+enter") :capitalize-p t))))

(test daxnuts-rgb-grid-matches-hex-parse
  (is (equal '(187 186 184) (cadr-cli::daxnuts-rgb-at 0 0)))
  (is (= 16 (length cadr-cli::+daxnuts-image-lines+)))
  (is (search (format nil "~C[38;2;" #\Escape)
              (first cadr-cli::+daxnuts-image-lines+))))

(test llama-gated-approval-text-uses-keyword
  (is (string= "Manual approval is required"
               (cadr-cli::llama-gated-approval-text :manual)))
  (is (string= "Accept the access terms"
               (cadr-cli::llama-gated-approval-text :auto)))
  (is (string= "Accept the access terms"
               (cadr-cli::llama-gated-approval-text "manual"))))

(test wrap-transcript-lines-splices-osc-markers
  (let* ((lines (cadr-cli::wrap-transcript-lines '("one" "two")))
         (start cadr-cli::+osc-133-start+)
         (end (concatenate 'string
                           cadr-cli::+osc-133-end+
                           cadr-cli::+osc-133-final+)))
    (is (eql 0 (search start (first lines))))
    (is (eql 0 (search end (second lines))))
    (is (string= "one" (subseq (first lines) (length start))))
    (is (string= "two" (subseq (second lines) (length end))))))

(test config-resource-kinds-owns-the-four-types
  (is (equal '(:extensions :skills :prompts :themes)
             (cadr-cli::config-resource-kinds)))
  (is (string= "foo"
               (cadr-cli::config-selector-entry-target "foo")))
  (is (string= "bar"
               (cadr-cli::config-selector-entry-target "+bar"))))

(test llama-search-status-text-maps-searching-keyword
  (let ((search (cadr-cli::make-llama-search-state :status :searching)))
    (is (string= "Searching Hugging Face…"
                 (cadr-cli::llama-search-status-text search)))))

(test model-registry-sort-predicate-is-provider-then-id
  (let ((left (cadr-ai:make-model :id "b" :provider :openai))
        (right (cadr-ai:make-model :id "a" :provider :openai))
        (other (cadr-ai:make-model :id "z" :provider :anthropic)))
    (is (cadr-cli::model-registry-sort-predicate other left))
    (is (cadr-cli::model-registry-sort-predicate right left))
    (is (not (cadr-cli::model-registry-sort-predicate left right)))))

(test parse-queue-mode-owns-rpc-mode-strings
  (is (eq :all (cadr-cli::parse-queue-mode "all" "steering")))
  (is (eq :one-at-a-time
          (cadr-cli::parse-queue-mode "one-at-a-time" "follow-up")))
  (signals error
    (cadr-cli::parse-queue-mode "bogus" "steering")))

(test external-editor-is-private-and-failure-preserves-content
  (let ((observed-mode nil)
        (observed-path nil))
    (is
     (string=
      "changed"
      (cadr-cli::edit-in-external-editor
       "original"
       (lambda (path)
         (setf observed-path path
               observed-mode
               (logand
                #o777
                (sb-posix:stat-mode
                 (sb-posix:stat path))))
         (write-text path "changed")
         0))))
    (is (= #o600 observed-mode))
    (is (not (probe-file observed-path))))
  (is
   (string=
    "original"
    (cadr-cli::edit-in-external-editor
     "original"
     (lambda (path)
       (write-text path "ignored")
       1)))))
