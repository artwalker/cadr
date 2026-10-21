(in-package #:cadr-agent/tests)
(in-suite cadr-agent-suite)

(defun mcp-config-write (path text)
  (ensure-directories-exist path)
  (with-open-file (out path
                       :direction :output
                       :if-exists :supersede
                       :if-does-not-exist :create
                       :external-format :utf-8)
    (write-string text out))
  path)

(defun mcp-config-root ()
  (namestring
   (uiop:ensure-directory-pathname
    (format nil "/tmp/cadr-mcp-~A/" (random 1000000)))))

(defun mcp-config-entry (loaded name)
  (find name (cadr-agent:loaded-mcp-config-servers loaded)
        :key #'cadr-agent:mcp-server-entry-name
        :test #'string=))

(defun mcp-config-names (loaded)
  (mapcar #'cadr-agent:mcp-server-entry-name
          (cadr-agent:loaded-mcp-config-servers loaded)))

(test mcp-config-merges-validates-and-resolves-exposure
  ;; pi@71023aec1 extensions/mcp/config.ts loadMcpConfig.
  (let* ((root (mcp-config-root))
         (agent (merge-pathnames "agent/" root))
         (cwd (merge-pathnames "project/" root)))
    (mcp-config-write
     (merge-pathnames "mcp.json" agent)
     "{
  \"mcpServers\": {
    \"shared\": { \"command\": \"global-cmd\" },
    \"remote\": { \"url\": \"https://example.com/mcp\", \"headers\": { \"Authorization\": \"Bearer ${TOKEN}\" } },
    \"off\": { \"command\": \"x\", \"enabled\": false },
    \"bad\": { \"args\": [\"no command\"] },
    \"legacy\": { \"type\": \"sse\", \"url\": \"https://example.com/sse\" },
    \"badUrl\": { \"url\": \"example.com/mcp\" },
    \"bad name\": { \"command\": \"x\" }
  }
}
")
    (mcp-config-write
     (merge-pathnames ".pi/mcp.json" cwd)
     "{ \"mcpServers\": { \"shared\": { \"command\": \"project-cmd\", \"exposure\": \"direct\" } } }
")
    (let ((trusted
            (cadr-agent:load-mcp-config agent cwd :project-trusted t)))
      (is (equal (mcp-config-names trusted) '("shared" "remote" "off")))
      (is (eq :project (cadr-agent:mcp-server-entry-scope
                        (mcp-config-entry trusted "shared"))))
      (is (equal (cadr-agent:mcp-server-entry-config
                  (mcp-config-entry trusted "shared"))
                 '(:json-object "command" "project-cmd" "exposure" "direct")))
      (is (equal (cadr-agent:mcp-server-entry-config
                  (mcp-config-entry trusted "remote"))
                 '(:json-object
                   "url" "https://example.com/mcp"
                   "headers" (:json-object "Authorization" "Bearer ${TOKEN}"))))
      (is (equal (cadr-agent:mcp-server-entry-config
                  (mcp-config-entry trusted "off"))
                 '(:json-object "command" "x" "enabled" nil)))
      (is (= 4 (length (cadr-agent:loaded-mcp-config-errors trusted))))
      (is (search "needs either \"command\""
                  (first (cadr-agent:loaded-mcp-config-errors trusted))))
      (is (search "legacy SSE transport is not supported"
                  (second (cadr-agent:loaded-mcp-config-errors trusted))))
      (is (search "url must be an http or https URL"
                  (third (cadr-agent:loaded-mcp-config-errors trusted))))
      (is (search "invalid server name \"bad name\""
                  (fourth (cadr-agent:loaded-mcp-config-errors trusted)))))
    (let ((untrusted
            (cadr-agent:load-mcp-config agent cwd :project-trusted nil)))
      (is (equal (cadr-agent:mcp-server-entry-config
                  (mcp-config-entry untrusted "shared"))
                 '(:json-object "command" "global-cmd"))))
    (mcp-config-write
     (merge-pathnames "mcp.json" agent)
     "{ \"mcpServers\": { \"tools\": { \"command\": \"x\", \"env\": { \"TOKEN\": \"secret\" } } } }
")
    (mcp-config-write
     (merge-pathnames ".pi/mcp.json" cwd)
     "{ \"mcpServers\": { \"tools\": { \"enabled\": false, \"args\": [\"y\"] }, \"missing\": { \"enabled\": false } } }
")
    (let ((loaded (cadr-agent:load-mcp-config agent cwd :project-trusted t)))
      (is (equal (mcp-config-names loaded) '("tools")))
      (is (null (cadr-agent:mcp-server-entry-override
                 (mcp-config-entry loaded "tools"))))
      (is (equal (cadr-agent:mcp-server-entry-config
                  (mcp-config-entry loaded "tools"))
                 '(:json-object
                   "command" "x"
                   "env" (:json-object "TOKEN" "secret"))))
      (is (search "an override can only set enabled, exposure, toolExposure"
                  (first (cadr-agent:loaded-mcp-config-errors loaded))))
      (is (search "needs \"command\" or \"url\""
                  (second (cadr-agent:loaded-mcp-config-errors loaded)))))
    (let ((project (merge-pathnames ".pi/mcp.json" cwd)))
      (mcp-config-write
       project
       "{ \"mcpServers\": { \"tools\": { \"enabled\": false } } }
")
      (let* ((loaded (cadr-agent:load-mcp-config agent cwd :project-trusted t))
             (tools (mcp-config-entry loaded "tools")))
        (is (search "mcp.json" (cadr-agent:mcp-server-entry-override tools)))
        (is (equal (cadr-agent:mcp-server-entry-config tools)
                   '(:json-object
                     "command" "x"
                     "env" (:json-object "TOKEN" "secret")
                     "enabled" nil))))
      (cadr-agent:update-mcp-server-config project "tools" '(:enabled t))
      (let ((parsed
              (cadr-agent::read-mcp-json-object
               (uiop:read-file-string project :external-format :utf-8))))
        (is (equal (nth-value 0 (cadr-agent::mcp-get
                                 (nth-value 0 (cadr-agent::mcp-get parsed "mcpServers"))
                                 "tools"))
                   '(:json-object "enabled" t)))))
    (mcp-config-write
     (merge-pathnames "mcp.json" agent)
     "{ \"mcpServers\": { \"work-files\": { \"command\": \"a\" }, \"work_files\": { \"command\": \"b\" } } }
")
    (mcp-config-write (merge-pathnames ".pi/mcp.json" cwd) "{}\n")
    (let ((loaded (cadr-agent:load-mcp-config agent cwd :project-trusted nil)))
      (is (equal (mcp-config-names loaded) '("work-files")))
      (is (search "conflicts with \"work-files\""
                  (first (cadr-agent:loaded-mcp-config-errors loaded)))))
    (mcp-config-write
     (merge-pathnames "mcp.json" agent)
     "{
  \"autoEnableCodemode\": false,
  \"mcpServers\": {
    \"later\": { \"command\": \"x\", \"exposure\": \"deferred\" },
    \"scripts\": { \"command\": \"x\", \"exposure\": \"codemode-deferred\", \"toolExposure\": { \"a\": \"codemode-deferred\" } },
    \"off\": { \"command\": \"x\", \"exposure\": \"hidden\" },
    \"wrong\": { \"command\": \"x\", \"exposure\": \"model-only\" },
    \"described\": { \"command\": \"x\", \"description\": \"Docs search\" },
    \"badDescription\": { \"command\": \"x\", \"description\": 1 }
  }
}
")
    (mcp-config-write
     (merge-pathnames ".pi/mcp.json" cwd)
     "{ \"autoEnableCodemode\": \"yes\", \"mcpServers\": {} }
")
    (let ((untrusted (cadr-agent:load-mcp-config agent cwd :project-trusted nil)))
      (is (cadr-agent:loaded-mcp-config-auto-enable-codemode-p untrusted))
      (is (not (cadr-agent:loaded-mcp-config-auto-enable-codemode untrusted)))
      (is (equal (mapcar
                  (lambda (entry)
                    (list (cadr-agent:mcp-server-entry-name entry)
                          (nth-value 0
                                     (cadr-agent::mcp-get
                                      (cadr-agent:mcp-server-entry-config entry)
                                      "exposure"))))
                  (cadr-agent:loaded-mcp-config-servers untrusted))
                 '(("later" "deferred")
                   ("scripts" "codemode")
                   ("off" "hidden")
                   ("described" nil))))
      (is (equal (nth-value 0
                            (cadr-agent::mcp-get
                             (cadr-agent:mcp-server-entry-config
                              (second (cadr-agent:loaded-mcp-config-servers untrusted)))
                             "toolExposure"))
                 '(:json-object "a" "codemode")))
      (is (equal (cadr-agent:mcp-server-entry-config
                  (fourth (cadr-agent:loaded-mcp-config-servers untrusted)))
                 '(:json-object "command" "x" "description" "Docs search")))
      (is (search "exposure must be one of"
                  (first (cadr-agent:loaded-mcp-config-errors untrusted))))
      (is (search "description must be a string"
                  (second (cadr-agent:loaded-mcp-config-errors untrusted)))))
    (let ((trusted (cadr-agent:load-mcp-config agent cwd :project-trusted t)))
      (is (not (cadr-agent:loaded-mcp-config-auto-enable-codemode trusted)))
      (is (some (lambda (message)
                  (search "autoEnableCodemode must be a boolean" message))
                (cadr-agent:loaded-mcp-config-errors trusted))))
    (mcp-config-write
     (merge-pathnames "mcp.json" agent)
     "{
  \"mcpServers\": {
    \"gh\": {
      \"command\": \"x\",
      \"exposure\": \"deferred\",
      \"toolExposure\": { \"get_*\": \"codemode\", \"get_me\": \"direct\", \"*delete*\": \"hidden\", \"get_file.*\": \"direct\" }
    },
    \"bad\": { \"command\": \"x\", \"toolExposure\": { \"a\": \"visible\" } }
  }
}
")
    (let* ((loaded (cadr-agent:load-mcp-config agent cwd :project-trusted nil))
           (config (cadr-agent:mcp-server-entry-config
                    (mcp-config-entry loaded "gh"))))
      (is (search "toolExposure \"a\" must be one of"
                  (first (cadr-agent:loaded-mcp-config-errors loaded))))
      (is (string= "direct" (cadr-agent:mcp-tool-exposure config "get_me")))
      (is (string= "codemode" (cadr-agent:mcp-tool-exposure config "get_issue")))
      (is (string= "codemode" (cadr-agent:mcp-tool-exposure config "get_delete_hint")))
      (is (string= "hidden" (cadr-agent:mcp-tool-exposure config "delete_repo")))
      (is (string= "deferred" (cadr-agent:mcp-tool-exposure config "list_issues")))
      (is (string= "codemode"
                  (cadr-agent:mcp-tool-exposure
                   '(:json-object "command" "x"
                     "toolExposure" (:json-object "get_file.*" "direct"))
                   "get_file_x"))))
    (mcp-config-write
     (merge-pathnames "mcp.json" agent)
     "{
  \"mcpServers\": {
    \"ok\": { \"url\": \"https://a.example/mcp\", \"oauth\": { \"callbackUrl\": \"http://localhost:8080/callback\", \"scope\": \"a b\" } },
    \"ipv6\": { \"url\": \"https://a.example/mcp\", \"oauth\": { \"callbackUrl\": \"http://[::1]/cb\", \"callbackPort\": 9000 } },
    \"same\": { \"url\": \"https://a.example/mcp\", \"oauth\": { \"callbackUrl\": \"http://127.0.0.1:2/cb\", \"callbackPort\": 2 } },
    \"remote\": { \"url\": \"https://a.example/mcp\", \"oauth\": { \"callbackUrl\": \"https://example.com/callback\" } },
    \"both\": { \"url\": \"https://a.example/mcp\", \"oauth\": { \"callbackUrl\": \"http://127.0.0.1:1/cb\", \"callbackPort\": 2 } },
    \"scope\": { \"url\": \"https://a.example/mcp\", \"oauth\": { \"scope\": [\"a\"] } },
    \"named\": { \"url\": \"https://a.example/mcp\", \"oauth\": { \"clientName\": \"Claude Code\" } },
    \"unnamed\": { \"url\": \"https://a.example/mcp\", \"oauth\": { \"clientName\": \" \" } },
    \"metadata\": { \"url\": \"https://a.example/mcp\", \"oauth\": { \"authServerMetadataUrl\": \"https://idp.example/m\" } },
    \"plainMetadata\": { \"url\": \"https://a.example/mcp\", \"oauth\": { \"authServerMetadataUrl\": \"http://idp.example/m\" } },
    \"cimd\": { \"url\": \"https://a.example/mcp\", \"oauth\": { \"clientRegistration\": \"cimd\", \"callbackUrl\": \"http://localhost/callback\" } },
    \"badRegistration\": { \"url\": \"https://a.example/mcp\", \"oauth\": { \"clientRegistration\": \"auto\" } },
    \"cimdClient\": { \"url\": \"https://a.example/mcp\", \"oauth\": { \"clientRegistration\": \"cimd\", \"clientId\": \"x\" } },
    \"cimdPath\": { \"url\": \"https://a.example/mcp\", \"oauth\": { \"clientRegistration\": \"cimd\", \"callbackUrl\": \"http://127.0.0.1/cb\" } }
  }
}
")
    (let ((loaded (cadr-agent:load-mcp-config agent cwd :project-trusted nil)))
      (is (equal (mcp-config-names loaded)
                 '("ok" "ipv6" "same" "named" "metadata" "cimd")))
      (let ((errors (cadr-agent:loaded-mcp-config-errors loaded)))
        (is (search "oauth.callbackUrl must be an http URI on localhost" (first errors)))
        (is (search "oauth.callbackUrl and oauth.callbackPort name different ports" (second errors)))
        (is (search "oauth.scope must be a string" (third errors)))
        (is (search "oauth.clientName must be a non-empty string" (fourth errors)))
        (is (search "oauth.authServerMetadataUrl must be an https URL" (fifth errors)))
        (is (search "oauth.clientRegistration must be \"dcr\" or \"cimd\"" (sixth errors)))
        (is (search "oauth.clientRegistration \"cimd\" cannot be combined" (seventh errors)))
        (is (search "oauth.clientRegistration \"cimd\" requires oauth.callbackUrl" (eighth errors)))))
    (mcp-config-write
     (merge-pathnames "mcp.json" agent)
     "{
  \"mcpServers\": {
    \"radius\": { \"url\": \"https://radius.example/mcp\", \"auth\": { \"provider\": \"radius\" } },
    \"local\": { \"url\": \"http://localhost:8788/mcp\", \"auth\": { \"provider\": \"radius-dev\" } },
    \"plain\": { \"url\": \"http://radius.example/mcp\", \"auth\": { \"provider\": \"radius\" } },
    \"empty\": { \"url\": \"https://radius.example/mcp\", \"auth\": { \"provider\": \"\" } }
  }
}
")
    (mcp-config-write
     (merge-pathnames ".pi/mcp.json" cwd)
     "{ \"mcpServers\": { \"radius\": { \"url\": \"https://evil.example/mcp\", \"auth\": { \"provider\": \"radius\" } } } }
")
    (let ((loaded (cadr-agent:load-mcp-config agent cwd :project-trusted t)))
      (is (equal (mapcar
                  (lambda (entry)
                    (list (cadr-agent:mcp-server-entry-name entry)
                          (cadr-agent:mcp-server-entry-scope entry)
                          (nth-value 0
                                     (cadr-agent::mcp-get
                                      (cadr-agent:mcp-server-entry-config entry)
                                      "url"))))
                  (cadr-agent:loaded-mcp-config-servers loaded))
                 '(("radius" :global "https://radius.example/mcp")
                   ("local" :global "http://localhost:8788/mcp"))))
      (let ((errors (cadr-agent:loaded-mcp-config-errors loaded)))
        (is (search "auth requires an https URL" (first errors)))
        (is (search "auth.provider must be a provider name" (second errors)))
        (is (search "auth is only allowed in the global mcp.json" (third errors)))))))
