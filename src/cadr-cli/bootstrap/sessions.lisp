(in-package #:cadr-cli)

(defun session-argument-path-p (argument)
  (or
   (position #\/ argument)
   (position #\\ argument)
   (uiop:string-suffix-p ".jsonl" argument)))

(defun find-session-by-id-or-prefix
    (argument sessions)
  (or
   (find
    argument sessions
    :key #'cadr-agent:session-id
    :test #'string=)
   (find-if
    (lambda (session)
      (uiop:string-prefix-p
       argument
       (cadr-agent:session-id session)))
    sessions)))

(defun resolve-session-reference
    (argument directory cwd)
  (if (session-argument-path-p argument)
      (cadr-agent:load-session
       (merge-pathnames
        (pathname argument)
        (uiop:ensure-directory-pathname cwd)))
      (or
       (find-session-by-id-or-prefix
        argument
        (cadr-agent:list-sessions
         :directory directory :cwd cwd))
       (find-session-by-id-or-prefix
        argument
        (cadr-agent:list-sessions
         :directory directory))
       (cadr-agent:resume-session
        argument :directory directory))))

(defun resolve-fork-source-session
    (argument directory cwd)
  (resolve-session-reference argument directory cwd))

(defun resolve-cli-session
    (&key
       continue-p
       resume-id
       resume-selector-p
       no-session-p
       session-path
       session-id
       fork-source
       cwd
       (directory (cadr-agent:default-session-directory))
       (output *error-output*))
  (let ((selectors
          (remove
           nil
           (list
            (and continue-p "--continue")
            (and resume-id "--resume")
            (and resume-selector-p "--resume")
            (and session-path "--session")
            (and fork-source "--fork")))))
    (when (> (length selectors) 1)
      (error
       'cadr-ai:configuration-error
       :message
       (format nil "~{~A~^ and ~} are mutually exclusive"
               selectors))))
  (when (and session-id
             (or continue-p resume-id
                 resume-selector-p session-path))
    (error
     'cadr-ai:configuration-error
     :message
     "--session-id cannot be combined with --session, --continue, or --resume"))
  (when (and fork-source no-session-p)
    (error
     'cadr-ai:configuration-error
     :message "--fork cannot be combined with --no-session"))
  (when session-id
    (unless
        (and
         (plusp (length session-id))
         (<= (length session-id) 128)
         (every
          (lambda (character)
            (or
             (alphanumericp character)
             (member character
                     '(#\- #\_ #\.))))
          session-id)
         (not (member session-id
                      '("." "..")
                      :test #'string=)))
      (error
       'cadr-ai:configuration-error
       :message
       (format nil "Invalid session id: ~S"
               session-id))))
  (when no-session-p
    (return-from resolve-cli-session nil))
  (cond
    (fork-source
     (let* ((source
              (resolve-fork-source-session
               fork-source directory cwd))
            (target
              (cadr-agent:create-session
               :directory directory
               :cwd cwd
               :id session-id
               :parent-session
               (cadr-agent:session-id source))))
       (dolist
           (message
            (cadr-agent:session-messages source))
         (cadr-agent:session-append-message
          target message))
       target))
    (session-path
     (resolve-session-reference
      session-path directory cwd))
    (resume-id
     (let ((session
             (cadr-agent:resume-session
              resume-id :directory directory)))
       (unless
           (string=
            (cadr-agent:session-cwd session)
            (cadr-agent::canonical-session-cwd cwd))
         (error
          'cadr-ai:configuration-error
          :message
          (format nil
                  "Session ~A belongs to ~A, not ~A"
                  resume-id
                  (cadr-agent:session-cwd session)
                  (cadr-agent::canonical-session-cwd cwd))))
       session))
    (resume-selector-p
     (first
      (cadr-agent:list-sessions
       :directory directory :cwd cwd)))
    (continue-p
     (or
      (cadr-agent:continue-session
       :directory directory :cwd cwd)
      (progn
        (format output
                "cadr: no previous session for ~A; starting a new session~%"
                (namestring
                 (truename
                  (uiop:ensure-directory-pathname cwd))))
        (finish-output output)
        (cadr-agent:create-session
         :directory directory :cwd cwd))))
    (session-id
     (or
      (find
       session-id
       (cadr-agent:list-sessions
        :directory directory :cwd cwd)
       :key #'cadr-agent:session-id
       :test #'string=)
      (progn
        (format
         output
         "cadr: no project session with id ~A; creating it~%"
         session-id)
        (finish-output output)
        (cadr-agent:create-session
         :directory directory :cwd cwd
         :id session-id))))
    (t
     (cadr-agent:create-session
      :directory directory :cwd cwd))))

(defun split-command (line)
  (let* ((trimmed
           (string-trim
            '(#\Space #\Tab #\Newline #\Return)
            line))
         (separator
           (position-if
            (lambda (character)
              (member character '(#\Space #\Tab)))
            trimmed)))
    (values
     (if separator
         (subseq trimmed 0 separator)
         trimmed)
     (and separator
          (let ((argument
                  (string-trim
                   '(#\Space #\Tab)
                   (subseq trimmed (1+ separator)))))
            (unless (zerop (length argument))
              argument))))))

(defun path-command-argument
    (line command)
  (let ((trimmed
          (string-trim
           '(#\Space #\Tab #\Newline #\Return)
           line)))
    (unless
        (and
         (> (length trimmed) (length command))
         (string=
          command trimmed
          :end2 (length command))
         (member
          (char trimmed (length command))
          '(#\Space #\Tab)))
      (return-from path-command-argument nil))
    (let ((arguments
            (string-left-trim
             '(#\Space #\Tab)
             (subseq
              trimmed
              (1+ (length command))))))
      (when (zerop (length arguments))
        (return-from path-command-argument nil))
      (let ((quote
              (and
               (member
                (char arguments 0)
                '(#\' #\"))
               (char arguments 0))))
        (if quote
            (let ((end
                    (position quote arguments
                              :start 1)))
              (and end
                   (subseq arguments 1 end)))
            (let ((end
                    (position-if
                     (lambda (character)
                       (member character
                               '(#\Space #\Tab)))
                     arguments)))
              (if end
                  (subseq arguments 0 end)
                  arguments)))))))

(defun last-assistant-text (agent)
  (let ((message
          (find-if
           (lambda (candidate)
             (and
              (typep
               candidate
               'cadr-ai:assistant-message)
              (not
               (and
                (eq
                 :aborted
                 (cadr-ai:assistant-message-stop-reason
                  candidate))
                (null
                 (cadr-ai:assistant-message-content
                  candidate))))))
           (cadr-agent:agent-messages agent)
           :from-end t)))
    (when message
      (let ((text
              (format
               nil "~{~A~}"
               (loop
                 for block
                 in
                 (cadr-ai:assistant-message-content
                  message)
                 when
                   (typep block 'cadr-ai:text-content)
                   collect
                   (cadr-ai:text-content-text
                    block)))))
        (let ((trimmed
                (string-trim
                 '(#\Space #\Tab #\Newline #\Return)
                 text)))
          (and
           (plusp (length trimmed))
           trimmed))))))

(defun cli-platform ()
  #+darwin :darwin
  #+win32 :windows
  #-(or darwin win32) :linux)

(defun default-copy-text (text)
  (let ((environment nil))
    (copy-to-clipboard
     text
     :platform (cli-platform)
     :termux-p
     (not
      (null
       (clipboard-environment-value
        environment "TERMUX_VERSION")))
     :wayland-p
     (not
      (null
       (clipboard-wayland-p environment)))
     :wayland-display-p
     (not
      (null
       (clipboard-environment-value
        environment "WAYLAND_DISPLAY")))
     :x11-display-p
     (not
      (null
       (clipboard-environment-value
        environment "DISPLAY")))
     :remote-p
     (not
      (null
       (or
        (clipboard-environment-value
         environment "SSH_CONNECTION")
        (clipboard-environment-value
         environment "SSH_CLIENT")
        (clipboard-environment-value
         environment "MOSH_CONNECTION")))))))

(defun assistant-tool-call-only-p (message)
  (let ((content
          (cadr-ai:assistant-message-content
           message)))
    (and
     (some
      (lambda (block)
        (typep block 'cadr-ai:tool-call))
      content)
     (not
      (some
       (lambda (block)
         (and
          (typep block 'cadr-ai:text-content)
          (plusp
           (length
            (cadr-ai:text-content-text
             block)))))
       content)))))

(defun session-tree-label-timestamps (session)
  (let ((result
          (make-hash-table :test #'equal)))
    (dolist (entry
             (cadr-agent:session-entries session))
      (when
          (eq :label
              (cadr-agent:session-entry-type
               entry))
        (let ((target
                (cadr-agent:session-entry-target-id
                 entry)))
          (if
              (and
               (cadr-agent:session-entry-label entry)
               (plusp
                (length
                 (cadr-agent:session-entry-label
                  entry))))
              (setf
               (gethash target result)
               (cadr-agent::milliseconds-to-iso8601
                (cadr-agent:session-entry-timestamp
                 entry)))
              (remhash target result)))))
    result))

(defun session-tree-tool-calls (session)
  (let ((result
          (make-hash-table :test #'equal)))
    (dolist (entry
             (cadr-agent:session-entries session))
      (let ((message
              (cadr-agent:session-entry-message
               entry)))
        (when
            (typep message
                   'cadr-ai:assistant-message)
          (dolist (block
                   (cadr-ai:assistant-message-content
                    message))
            (when (typep block 'cadr-ai:tool-call)
              (setf
               (gethash (cadr-ai:tool-call-id block)
                        result)
               (list
                :name (cadr-ai:tool-call-name block)
                :arguments
                (cadr-ai:tool-call-arguments
                 block))))))))
    result))

(defun session-entry-tree-selector-data
    (session entry label-timestamps tool-calls)
  (let* ((type
           (cadr-agent:session-entry-type entry))
         (message
           (cadr-agent:session-entry-message entry))
         (role
           (typecase message
             (cadr-ai:user-message :user)
             (cadr-ai:assistant-message :assistant)
             (cadr-ai:tool-result-message
              :tool-result)
             (otherwise nil)))
         (id
           (cadr-agent:session-entry-id entry))
         (tool-call
           (and
            (typep message
                   'cadr-ai:tool-result-message)
            (gethash
             (cadr-ai:tool-result-message-tool-call-id
              message)
             tool-calls))))
    (list
     :id id
     :parent-id
     (cadr-agent:session-entry-parent-id entry)
     :type type
     :role role
     :text
     (cond
       (message
        (session-message-search-text message))
       ((member type
                '(:compaction :branch-summary)
                :test #'eq)
        (or
         (cadr-agent:session-entry-summary entry)
         ""))
       ((eq type :model-change)
        (format
         nil "~A / ~A"
         (cadr-agent:session-entry-provider entry)
         (cadr-agent:session-entry-model-id entry)))
       ((eq type :thinking-level-change)
        (princ-to-string
         (cadr-agent:session-entry-thinking-level
          entry)))
       ((eq type :custom-message)
        (let ((content
                (cadr-agent:session-entry-content
                 entry)))
          (if (stringp content)
              content
              (cadr-ai::content-text content))))
       (t ""))
     :label
     (cadr-agent:session-label session id)
     :label-timestamp
     (gethash id label-timestamps)
     :tool-call-only-p
     (and
      (typep message 'cadr-ai:assistant-message)
      (assistant-tool-call-only-p message))
     :error-p
     (or
      (and
       (typep message 'cadr-ai:assistant-message)
       (member
        (cadr-ai:assistant-message-stop-reason
         message)
        '(:error :aborted)
        :test #'eq))
      (and
       (typep message 'cadr-ai:tool-result-message)
       (cadr-ai:tool-result-message-is-error
        message)))
     :summary
     (cadr-agent:session-entry-summary entry)
     :name
     (cadr-agent:session-entry-name entry)
     :model-id
     (cadr-agent:session-entry-model-id entry)
     :thinking-level
     (cadr-agent:session-entry-thinking-level
      entry)
     :custom-type
     (cadr-agent:session-entry-custom-type
      entry)
     :tool-call-name
     (and
      (typep message 'cadr-ai:tool-result-message)
      (or (getf tool-call :name)
          (cadr-ai:tool-result-message-tool-name
           message)))
     :tool-call-arguments
     (getf tool-call :arguments))))

(defun session-tree-selector-data (session)
  (if (null session)
      (values nil nil)
      (let ((label-timestamps
              (session-tree-label-timestamps
               session))
            (tool-calls
              (session-tree-tool-calls session)))
        (values
         (mapcar
          (lambda (entry)
            (session-entry-tree-selector-data
             session entry label-timestamps
             tool-calls))
          (cadr-agent:session-entries session))
         (cadr-agent:session-leaf-id session)))))

(defun run-session-lifecycle
    (agent event &rest payload)
  (let ((host
          (cadr-agent::agent-extension-host
           agent)))
    (and
     host
     (cadr-agent::run-extension-lifecycle-hooks
     host event :payload payload))))

(defun apply-cli-model-selection
    (agent registry model settings-manager
     &key api-key base-url
       (config-path (default-config-path))
       (auth-path (default-auth-path))
       (source :interactive)
       (thinking-level nil thinking-level-p))
  (let* ((previous-model
           (cadr-agent:agent-model agent))
         (previous-thinking
           (cadr-agent::agent-thinking-level
            agent))
         (config
           (provider-config-for-model
            registry model
            :api-key api-key
            :base-url base-url
            :config-path config-path
            :auth-path auth-path
            :allow-missing-auth-p t))
         (provider
           (provider-config-provider config))
         (selected
           (provider-config-model config))
         (thinking
           (cadr-ai:clamp-thinking-level
            selected
            (if thinking-level-p
                thinking-level
                previous-thinking)))
         (host
           (cadr-agent::agent-extension-host
            agent))
         (session
           (cadr-agent:agent-session agent)))
    (setf
     (cadr-agent:agent-provider agent) provider
     (cadr-agent:agent-model agent) selected
     (cadr-agent::agent-thinking-level agent)
     thinking)
    (when host
      (setf
       (cadr-agent::extension-host-base-agent-provider
        host)
       provider
       (cadr-agent::extension-host-base-agent-model
        host)
       selected))
    (when session
      (cadr-agent:session-append-model-change
       session
       (provider-key
        (cadr-ai:model-provider selected))
       (cadr-ai:model-id selected))
      (unless (eq previous-thinking thinking)
        (cadr-agent:session-append-thinking-level-change
         session
         (string-downcase
          (symbol-name thinking)))))
    (settings-set-default-model-and-provider
     settings-manager
     (provider-key
      (cadr-ai:model-provider selected))
     (cadr-ai:model-id selected))
    (unless
        (cadr-ai:models-equal-p
         previous-model selected)
      (run-session-lifecycle
       agent :model-select
       :model selected
       :previous-model previous-model
       :source source))
    config))

(defun refresh-agent-model-from-registry
    (agent registry
     &key api-key base-url
       (config-path (default-config-path))
       (auth-path (default-auth-path)))
  (let* ((current
           (cadr-agent:agent-model agent))
         (refreshed
           (and
            current
            (model-registry-find
             registry
             (cadr-ai:model-provider current)
             (cadr-ai:model-id current)))))
    (when refreshed
      (let* ((config
               (provider-config-for-model
                registry refreshed
                :api-key api-key
                :base-url base-url
                :config-path config-path
                :auth-path auth-path
                :allow-missing-auth-p t))
             (provider
               (provider-config-provider config))
             (model
               (provider-config-model config))
             (host
               (cadr-agent::agent-extension-host
                agent)))
        (setf
         (cadr-agent:agent-provider agent)
         provider
         (cadr-agent:agent-model agent)
         model
         (cadr-agent::agent-thinking-level
          agent)
         (cadr-ai:clamp-thinking-level
          model
          (cadr-agent::agent-thinking-level
           agent)))
        (when host
          (setf
           (cadr-agent::extension-host-base-agent-provider
            host)
           provider
           (cadr-agent::extension-host-base-agent-model
            host)
           model))
        config))))

(defun session-restored-model
    (session registry available-models)
  (when session
    (let* ((change
             (find
              :model-change
              (cadr-agent:session-entries session)
              :from-end t
              :key #'cadr-agent:session-entry-type))
           (assistant
             (find-if
              (lambda (message)
                (typep
                 message
                 'cadr-ai:assistant-message))
              (cadr-agent:session-messages session)
              :from-end t))
           (provider
             (or
              (and change
                   (cadr-agent:session-entry-provider
                    change))
              (and assistant
                   (cadr-ai:assistant-message-provider
                    assistant))))
           (model-id
             (or
              (and change
                   (cadr-agent:session-entry-model-id
                    change))
              (and assistant
                   (cadr-ai:assistant-message-model
                    assistant))))
           (model
             (and
              provider model-id
              (model-registry-find
               registry provider model-id))))
      (and
       model
       (find model available-models
             :test #'cadr-ai:models-equal-p)))))

(defun clone-agent-session
    (agent directory)
  (let* ((source
           (cadr-agent:agent-session agent))
         (leaf-id
           (and source
                (cadr-agent:session-leaf-id
                 source))))
    (unless leaf-id
      (return-from clone-agent-session nil))
    (let ((before
            (run-session-lifecycle
             agent :session-before-fork
             :entry-id leaf-id
             :position :at)))
      (when (getf before :cancel-p)
        (return-from clone-agent-session
          :cancelled)))
    (let ((clone
            (cadr-agent:create-session
             :directory directory
             :cwd (cadr-agent:session-cwd
                   source)
             :parent-session
             (namestring
              (cadr-agent:session-path
               source)))))
      (dolist
          (entry
           (cadr-agent::session-path-entries
            source leaf-id))
        (cadr-agent::append-session-entry
         clone
         (cadr-agent::copy-session-entry
          entry)))
      (run-session-lifecycle
       agent :session-shutdown
       :reason :fork
       :target-session-file
       (namestring
        (cadr-agent:session-path clone)))
      (let ((previous
              (namestring
               (cadr-agent:session-path source))))
        (switch-agent-session agent clone)
        (run-session-lifecycle
         agent :session-start
         :reason :fork
         :previous-session-file previous))
      clone)))

(defun session-entry-user-text (entry)
  (when
      (and
       (eq :message
           (cadr-agent:session-entry-type entry))
       (typep
        (cadr-agent:session-entry-message entry)
        'cadr-ai:user-message))
    (let ((content
            (cadr-ai:user-message-content
             (cadr-agent:session-entry-message
              entry))))
      (if (stringp content)
          content
          (format
           nil "~{~A~^~%~}"
           (loop for block in content
                 when
                 (typep block 'cadr-ai:text-content)
                   collect
                   (cadr-ai:text-content-text
                    block)))))))

(defun session-user-messages-for-forking (session)
  (loop
    for entry in
    (and session
         (cadr-agent:session-entries session))
    for text = (session-entry-user-text entry)
    when
      (and text
           (plusp
            (length
             (string-trim
              '(#\Space #\Tab #\Newline #\Return)
              text))))
      collect
      (list :entry-id
            (cadr-agent:session-entry-id entry)
            :text text)))

(defun new-agent-session
    (agent directory cwd &key parent-session)
  (let* ((old
           (cadr-agent:agent-session agent))
         (previous
           (and old
                (namestring
                 (cadr-agent:session-path old))))
         (before
           (run-session-lifecycle
            agent :session-before-switch
            :reason :new
            :target-session-file nil)))
    (when (getf before :cancel-p)
      (return-from new-agent-session
        :cancelled))
    (run-session-lifecycle
     agent :session-shutdown
     :reason :new)
    (let ((new
            (cadr-agent:create-session
             :directory directory
             :cwd
             (or
              (and old
                   (cadr-agent:session-cwd old))
              cwd)
             :parent-session parent-session)))
      (switch-agent-session agent new)
      (run-session-lifecycle
       agent :session-start
       :reason :new
       :previous-session-file previous)
      new)))

(defun fork-agent-session
    (agent entry-id directory)
  (let* ((source
           (cadr-agent:agent-session agent))
         (entry
           (and source
                (find
                 entry-id
                 (cadr-agent:session-entries source)
                 :key #'cadr-agent:session-entry-id
                 :test #'string=)))
         (selected-text
           (and entry
                (session-entry-user-text entry))))
    (unless selected-text
      (error
       'cadr-ai:configuration-error
       :message
       "Invalid user message entry for forking"))
    (let ((before
            (run-session-lifecycle
             agent :session-before-fork
             :entry-id entry-id
             :position :before)))
      (when (getf before :cancel-p)
        (return-from fork-agent-session
          (values :cancelled nil))))
    (let* ((previous
             (namestring
              (cadr-agent:session-path source)))
           (new
             (cadr-agent:create-session
              :directory directory
              :cwd
              (cadr-agent:session-cwd source)
              :parent-session previous))
           (target-id
             (cadr-agent:session-entry-parent-id
              entry)))
      (when target-id
        (dolist
            (candidate
             (cadr-agent::session-path-entries
              source target-id))
          (cadr-agent::append-session-entry
           new
           (cadr-agent::copy-session-entry
            candidate))))
      (run-session-lifecycle
       agent :session-shutdown
       :reason :fork
       :target-session-file
       (namestring
        (cadr-agent:session-path new)))
      (switch-agent-session agent new)
      (run-session-lifecycle
       agent :session-start
       :reason :fork
       :previous-session-file previous)
      (values new selected-text))))

(defun session-command-stats (session)
  (let ((user 0)
        (assistant 0)
        (tool-results 0)
        (tool-calls 0)
        (input 0)
        (output 0)
        (cache-read 0)
        (cache-write 0)
        (cost 0d0))
    (labels
        ((add-usage (usage)
           (when usage
             (incf input
                   (cadr-ai:usage-input usage))
             (incf output
                   (cadr-ai:usage-output usage))
             (incf cache-read
                   (cadr-ai:usage-cache-read usage))
             (incf cache-write
                   (cadr-ai:usage-cache-write usage))
             (incf cost
                   (cadr-ai:cost-total
                    (cadr-ai:usage-cost usage))))))
      (dolist
          (entry
           (cadr-agent:session-entries session))
        (let ((type
                (cadr-agent:session-entry-type
                 entry)))
          (when
              (member type
                      '(:compaction :branch-summary))
            (add-usage
             (cadr-agent:session-entry-usage
              entry)))
          (when (eq :message type)
            (let ((message
                    (cadr-agent:session-entry-message
                     entry)))
              (cond
                ((typep
                  message 'cadr-ai:user-message)
                 (incf user))
                ((typep
                  message
                  'cadr-ai:tool-result-message)
                 (incf tool-results))
                ((typep
                  message
                  'cadr-ai:assistant-message)
                 (incf assistant)
                 (incf
                  tool-calls
                  (count-if
                   (lambda (block)
                     (typep block
                            'cadr-ai:tool-call))
                   (cadr-ai:assistant-message-content
                    message)))
                 (add-usage
                  (cadr-ai:assistant-message-usage
                   message)))))))))
    (list
     :user user
     :assistant assistant
     :tool-results tool-results
     :tool-calls tool-calls
     :input input
     :output output
     :cache-read cache-read
     :cache-write cache-write
     :cost cost)))

(defun write-session-command-info
    (session output)
  (let* ((stats
           (session-command-stats session))
         (input
           (+ (getf stats :input)
              (getf stats :cache-read)
              (getf stats :cache-write)))
         (total
           (+ input
              (getf stats :output))))
    (format output "Session Info~%~%")
    (when (cadr-agent:session-name session)
      (format output "Name: ~A~%"
              (cadr-agent:session-name session)))
    (format
     output
     "File: ~A~%ID: ~A~%~%Messages~%Total: ~:D~%User: ~:D~%Assistant: ~:D~%Tools: ~:D calls, ~:D results~%~%Tokens~%Input: ~:D~%"
     (namestring
      (cadr-agent:session-path session))
     (cadr-agent:session-id session)
     (+ (getf stats :user)
        (getf stats :assistant)
        (getf stats :tool-results))
     (getf stats :user)
     (getf stats :assistant)
     (getf stats :tool-calls)
     (getf stats :tool-results)
     input)
    (when
        (plusp
         (+ (getf stats :cache-read)
            (getf stats :cache-write)))
      (format
       output
       "  Cached: ~:D~%  Uncached: ~:D"
       (getf stats :cache-read)
       (+ (getf stats :input)
          (getf stats :cache-write)))
      (when (plusp
             (getf stats :cache-write))
        (format output
                " (~:D written to cache)"
                (getf stats :cache-write)))
      (terpri output))
    (format
     output
     "Output: ~:D~%Total: ~:D~%"
     (getf stats :output)
     total)
    (when
        (plusp (getf stats :cost))
      (format
       output
       "~%Cost~%Total: $~,3F~%"
       (getf stats :cost)))))

(defun default-changelog-path ()
  (or
   (let ((value
           (uiop:getenv
            "CADR_CHANGELOG_PATH")))
     (and value
          (plusp (length value))
          (pathname value)))
   (handler-case
       (asdf:system-relative-pathname
        "cadr-cli" "CHANGELOG.md")
     (condition () nil))
   #p"CHANGELOG.md"))

(defparameter +interactive-hotkey-definitions+
  '(("escape" . "Cancel or abort")
    ("ctrl+c" . "Clear editor; press again to exit")
    ("ctrl+d" . "Exit when the editor is empty")
    ("ctrl+z" . "Suspend to background")
    ("ctrl+o" . "Toggle tool output")
    ("ctrl+v" . "Paste image or text from clipboard")
    ("/" . "Slash commands")
    ("!" . "Run bash command")
    ("!!" . "Run bash command without adding it to context")))

(defun write-hotkeys-command
    (output &optional user-bindings)
  (format output "Keyboard Shortcuts~%~%")
  (dolist (entry
           +interactive-hotkey-definitions+)
    (format output "~A  ~A~%"
            (car entry) (cdr entry)))
  (when user-bindings
    (format output "~%Configured bindings~%")
    (dolist (binding user-bindings)
      (format output "~{~A~^, ~}  ~A~%"
              (cdr binding)
              (car binding)))))

(defun same-session-file-p (left right)
  (and
   (probe-file left)
   (probe-file right)
   (equal
    (namestring (truename left))
    (namestring (truename right)))))

(defun import-agent-session
    (agent input directory cwd)
  (let* ((source
           (resolve-general-path input cwd)))
    (unless (probe-file source)
      (return-from import-agent-session
        (values nil
                (format nil "File not found: ~A"
                        (namestring source)))))
    (let* ((session-directory
             (uiop:ensure-directory-pathname
              directory))
           (destination
             (merge-pathnames
              (file-namestring source)
              session-directory)))
      (ensure-directories-exist
       (merge-pathnames "anchor"
                        session-directory))
      (let ((before
              (run-session-lifecycle
               agent :session-before-switch
               :reason :resume
               :target-session-file
               (namestring destination))))
        (when (getf before :cancel-p)
          (return-from import-agent-session
            (values :cancelled nil))))
      (unless
          (same-session-file-p source destination)
        (cadr-core:atomic-copy-file
         source destination :durability :flush))
      (handler-case
          (let* ((previous
                   (and
                    (cadr-agent:agent-session agent)
                    (namestring
                     (cadr-agent:session-path
                      (cadr-agent:agent-session
                       agent)))))
                 (imported
                   (cadr-agent:load-session
                    destination)))
            (unless
                (probe-file
                 (uiop:ensure-directory-pathname
                  (cadr-agent:session-cwd
                   imported)))
              (error
               "Session working directory does not exist: ~A"
               (cadr-agent:session-cwd imported)))
            (run-session-lifecycle
             agent :session-shutdown
             :reason :resume
             :target-session-file
             (namestring destination))
            (switch-agent-session
             agent imported)
            (run-session-lifecycle
             agent :session-start
             :reason :resume
             :previous-session-file previous)
            (values imported nil))
        (condition (condition)
          (values
           nil
           (format nil "~A" condition)))))))

(defun switch-agent-session (agent session)
  (let ((host
          (cadr-agent::agent-extension-host agent)))
    (when host
      (cadr-agent::invalidate-extension-host-generation
       host)))
  (setf (cadr-agent:agent-session agent) session
        (cadr-agent:agent-messages agent)
        (cadr-agent:session-messages session))
  session)

(defun session-export-basename (session)
  (format
   nil "cadr-session-~A_~A.html"
   (cl-ppcre:regex-replace-all
    "[:.]"
    (cadr-core:milliseconds-to-utc-iso8601
     (cadr-agent:session-timestamp session))
    "-")
   (cadr-agent:session-id session)))

(defun session-export-path (session argument cwd)
  (resolve-general-path
   (or argument (session-export-basename session))
   cwd))

(defun handle-session-command
    (line agent
     &key
       (directory (cadr-agent:default-session-directory))
       (cwd (uiop:getcwd))
       (output *standard-output*)
       (copy-function #'default-copy-text)
       (share-runner
         #'default-share-command-runner)
       changelog-path
       keybindings
       status-function
       export-options-function
       (confirm-function
         (lambda (title message)
           (declare (ignore title message))
           t)))
  (multiple-value-bind (command argument)
      (split-command line)
    (cond
      ((string= command "/name")
       (unless (cadr-agent:agent-session agent)
         (error
          'cadr-ai:configuration-error
          :message "The agent has no persistent session"))
       (let* ((session
                (cadr-agent:agent-session agent))
              (host
                (cadr-agent::agent-extension-host
                 agent)))
         (if argument
             (let ((name
                     (if host
                         (cadr-agent::extension-host-set-session-name
                          host argument)
                         (progn
                           (cadr-agent:session-set-name
                            session argument)
                           (cadr-agent:session-name
                            session)))))
               (format output
                       "Session name set: ~A~%"
                       (or name argument)))
             (if (cadr-agent:session-name session)
                 (format
                  output
                  "Session name: ~A~%"
                  (cadr-agent:session-name session))
                 (format output
                         "Usage: /name <name>~%"))))
       (finish-output output)
       t)
      ((string= command "/session")
       (unless (cadr-agent:agent-session agent)
         (error
          'cadr-ai:configuration-error
          :message "The agent has no persistent session"))
       (write-session-command-info
        (cadr-agent:agent-session agent)
        output)
       (finish-output output)
       t)
      ((string= command "/share")
       (unless (cadr-agent:agent-session agent)
         (error
          'cadr-ai:configuration-error
          :message "The agent has no persistent session"))
       (multiple-value-bind
             (viewer-url gist-url)
           (share-session-as-gist
            (cadr-agent:agent-session agent)
            :runner share-runner)
         (format
          output
          "Share URL: ~A~%Gist: ~A~%"
          viewer-url gist-url))
       (finish-output output)
       t)
      ((string= command "/changelog")
       (let ((entries
               (parse-changelog
                (or changelog-path
                    (default-changelog-path)))))
         (format output "What's New~%~%")
         (if entries
             (loop
               for entry
               in (reverse entries)
               do
               (format
                output "~A~@[~%~]"
                (normalize-changelog-links
                 (getf entry :content)
                 (getf entry :version))
                (not
                 (eq entry
                     (first entries)))))
             (format output
                     "No changelog entries found.~%")))
       (finish-output output)
       t)
      ((string= command "/hotkeys")
       (write-hotkeys-command
        output keybindings)
       (finish-output output)
       t)
      ((string= command "/new")
       (let ((new
               (new-agent-session
                agent directory cwd)))
         (unless (eq new :cancelled)
           (format output
                   "New session started~%")))
       (finish-output output)
       t)
      ((string= command "/compact")
       (unless (cadr-agent:compact-agent
                agent
                :force-p t
                :custom-instructions argument)
         (format output
                 "session> Nothing to compact~%"))
       (finish-output output)
       t)
      ((string= command "/copy")
       (let ((text
               (last-assistant-text agent)))
         (if text
             (handler-case
                 (progn
                   (funcall copy-function text)
                   (format
                    output
                    "Copied last agent message to clipboard~%"))
               (condition (condition)
                 (format output "~A~%"
                         condition)))
             (format
              output
              "No agent messages to copy yet.~%")))
       (finish-output output)
       t)
      ((string= command "/clone")
       (let ((clone
               (clone-agent-session
                agent directory)))
         (cond
           ((null clone)
            (format output
                    "Nothing to clone yet~%"))
           ((eq clone :cancelled)
            nil)
           (t
            (format output
                    "Cloned to new session~%"))))
       (finish-output output)
       t)
      ((string= command "/import")
       (let ((path
               (path-command-argument
                line "/import")))
         (if (null path)
             (format output
                     "Usage: /import <path.jsonl>~%")
             (if
                 (not
                  (funcall
                   confirm-function
                   "Import session"
                   (format
                    nil
                    "Replace current session with ~A?"
                    path)))
                 (format output
                         "Import cancelled~%")
                 (multiple-value-bind
                       (imported error-message)
                     (import-agent-session
                      agent path directory cwd)
                   (cond
                     ((eq imported :cancelled)
                      (format output
                              "Import cancelled~%"))
                     (imported
                      (format
                       output
                       "Session imported from: ~A~%"
                       path))
                     (t
                      (format
                       output
                       "Failed to import session: ~A~%"
                       error-message)))))))
       (finish-output output)
       t)
      ((string= command "/export")
       (unless (cadr-agent:agent-session agent)
         (error
          'cadr-ai:configuration-error
          :message "The agent has no persistent session"))
       (let ((path
               (session-export-path
                (cadr-agent:agent-session agent)
                argument cwd)))
         (apply
          #'cadr-agent:export-session-html
          (cadr-agent:agent-session agent)
          path
          (if export-options-function
              (or (funcall export-options-function)
                  nil)
              nil))
         (let ((message
                 (format nil "Session exported to: ~A"
                         (file-namestring path))))
           (if status-function
               (funcall status-function message)
               (progn
                 (format output "~A~%" message)
                 (finish-output output))))
         t))
      (t nil))))
