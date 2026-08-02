(in-package #:cadr-cli)

(defstruct extension-source-record
  id
  path
  scope
  rank
  order)

(defvar *extension-generation-counter* 0)
(defvar *extension-generation-lock*
  (sb-thread:make-mutex
   :name "cadr-cli extension generations"))

(defun next-extension-generation ()
  (sb-thread:with-mutex
      (*extension-generation-lock*)
    (incf *extension-generation-counter*)))

(defstruct (cli-extension-manager
            (:constructor %make-cli-extension-manager))
  cwd
  global-directory
  explicit-paths
  (extension-factories nil :type list)
  configured-package-paths
  (no-discovery-p nil :type boolean)
  output
  (secret-function (constantly nil) :type function)
  host
  (last-good (make-hash-table :test #'equal)
             :type hash-table)
  (generation 0 :type (integer 0 *))
  (package-names nil :type list))

(defun default-extension-directory ()
  (merge-pathnames
   ".cadr/extensions/"
   (user-homedir-pathname)))

(defun extension-manager-notify
    (manager message level)
  (format
   (cli-extension-manager-output manager)
   "~&extension[~(~A~)]> ~A~%"
   level
   (cadr-ai:redact-secrets
    message
    (funcall
     (cli-extension-manager-secret-function
      manager))))
  (finish-output
   (cli-extension-manager-output manager)))

(defun extension-http-timeout-condition-p (condition)
  (or (typep condition 'cadr-ai:timeout-error)
      (typep condition 'cadr-ai::native-http-timeout)
      (typep condition 'sb-sys:io-timeout)
      (typep condition 'sb-bsd-sockets:operation-timeout-error)
      (and (typep condition 'cadr-ai:cadr-error)
           (let ((cause (cadr-ai:cadr-error-cause condition)))
             (and cause
                  (not (eq cause condition))
                  (extension-http-timeout-condition-p cause))))))

(defun make-extension-http-request-adapter ()
  (lambda (url &key (method :get) headers body timeout-ms signal)
    (let* ((abort-p
             (and signal
                  (lambda ()
                    (cadr-agent:extension-cancellation-aborted-p
                     signal))))
           (timeout
             (and timeout-ms (/ timeout-ms 1000d0)))
           (options
             (append
              (list
               :method method
               :headers headers
               :content body
               :want-stream nil
               :force-binary t)
              (when timeout
                (list :connect-timeout timeout
                      :read-timeout timeout)))))
      (handler-case
          (let ((cadr-ai::*native-http-abort-p* abort-p))
            (multiple-value-bind (response status response-headers)
                (apply cadr-ai:*http-request-function* url options)
              (list
               :status status
               :headers
               (cond
                 ((null response-headers) nil)
                 ((hash-table-p response-headers)
                  (loop for name being the hash-keys of response-headers
                        using (hash-value value)
                        collect (cons name value)))
                 ((listp response-headers)
                  (copy-tree response-headers))
                 (t (error "invalid HTTP response headers")))
               :body
               (cond
                 ((typep response
                         '(array (unsigned-byte 8) (*)))
                  (coerce response
                          '(simple-array (unsigned-byte 8) (*))))
                 ((stringp response)
                  (sb-ext:string-to-octets
                   response :external-format :utf-8))
                 (t
                  (error "invalid HTTP response body"))))))
        (condition (condition)
          (cond
            ((or (typep condition 'cadr-ai:request-aborted)
                 (and signal
                      (cadr-agent:extension-cancellation-aborted-p
                       signal)))
             (error
              'cadr-agent:extension-execution-error
              :message "Extension HTTP request was aborted"))
            ((extension-http-timeout-condition-p condition)
             (error
              'cadr-agent:extension-execution-error
              :message "Extension HTTP request timed out"))
            (t
             (error
              'cadr-agent:extension-execution-error
              :message "Extension HTTP request failed"))))))))

(defun make-cli-extension-manager
    (&key
       (cwd (uiop:getcwd))
       (global-directory
         (default-extension-directory))
       explicit-paths
       extension-factories
       configured-package-paths
       no-discovery-p
       (output *standard-output*)
       secret-function
       (mode :repl))
  (let ((manager
          (%make-cli-extension-manager
           :cwd
           (uiop:ensure-directory-pathname
            (pathname cwd))
           :global-directory
           (uiop:ensure-directory-pathname
            (pathname global-directory))
           :explicit-paths (copy-list explicit-paths)
           :extension-factories
           (cons
            (list
             :name "llama.cpp"
             :factory #'llama-extension-factory
             :hidden-p t)
            (copy-list extension-factories))
           :configured-package-paths
           (copy-list configured-package-paths)
           :no-discovery-p
           (not (null no-discovery-p))
           :output output
           :secret-function
           (or secret-function
               (constantly nil)))))
    (let ((host
            (cadr-agent::make-extension-host
             :cwd (cli-extension-manager-cwd manager)
             :mode mode
             :notify-function
             (lambda (message level)
               (extension-manager-notify
                manager message level))
             :reload-function
             (lambda ()
               (reload-cli-extensions manager))
             :http-request-function
             (make-extension-http-request-adapter)
             :exec-function
             (lambda (command arguments
                      &key cwd environment timeout-ms)
               (let* ((execution-environment
                        (cadr-agent:make-node-execution-env
                         :cwd
                         (cli-extension-manager-cwd
                          manager)))
                      (shell-command
                        (format
                         nil "~{~A~^ ~}"
                         (mapcar
                          #'shell-quote
                          (cons command arguments)))))
                 (multiple-value-bind (result error)
                     (cadr-agent:execution-env-exec
                      execution-environment
                      shell-command
                      :cwd cwd
                      :environment environment
                      :timeout
                      (and timeout-ms
                           (/ timeout-ms 1000.0)))
                   (when error
                     (error
                      'cadr-agent:extension-execution-error
                      :message
                      (cadr-agent:harness-operation-error-message
                       error)))
                   (list
                    :stdout
                    (cadr-agent:execution-result-stdout
                     result)
                    :stderr
                    (cadr-agent:execution-result-stderr
                     result)
                    :exit-code
                    (cadr-agent:execution-result-exit-code
                     result))))))))
      (setf (cli-extension-manager-host manager) host))
    (setf *native-extension-host*
          (cli-extension-manager-host manager))
    manager))

(defun configure-extension-ui-bridge
    (manager
     &key
       custom-function
       autocomplete-function
       theme-function
       all-themes-function
       get-theme-function
       set-theme-function
       tools-expanded-function
       set-tools-expanded-function)
  (let* ((host
           (cli-extension-manager-host manager))
         (fallback
           (cadr-agent::extension-host-ui-function
            host)))
    (setf
     (cadr-agent::extension-host-ui-function host)
     (lambda (method arguments)
       (case method
         (:custom
          (and
           custom-function
           (funcall
            custom-function
            (getf arguments :factory)
            (getf arguments :overlay-p)
            (getf arguments :overlay-options))))
         (:add-autocomplete-provider
          (when autocomplete-function
            (funcall
             autocomplete-function
             (getf arguments :factory)))
          nil)
         (:theme
          (and theme-function
               (funcall theme-function)))
         (:all-themes
          (and all-themes-function
               (funcall all-themes-function)))
         (:get-theme
          (and get-theme-function
               (funcall
                get-theme-function
                (getf arguments :name))))
         (:set-theme
          (and set-theme-function
               (funcall
                set-theme-function
                (getf arguments :theme))))
         (:tools-expanded-p
          (and tools-expanded-function
               (funcall tools-expanded-function)))
         (:set-tools-expanded
          (when set-tools-expanded-function
            (funcall
             set-tools-expanded-function
             (getf arguments :expanded-p)))
          nil)
         (otherwise
          (and fallback
               (funcall fallback method arguments)))))))
  manager)

(defun extension-directory-id (directory)
  (let ((parts
          (pathname-directory
           (uiop:ensure-directory-pathname directory))))
    (princ-to-string (car (last parts)))))

(defun make-extension-source-record-for-path
    (path scope rank order &optional id)
  (let* ((resolved (truename path))
         (entry
           (if (uiop:directory-pathname-p resolved)
               (merge-pathnames "extension.lisp" resolved)
               resolved)))
    (unless (probe-file entry)
      (error
       'cadr-ai:configuration-error
       :message
       (format nil
               "Extension directory has no extension.lisp: ~A"
               (namestring resolved))))
    (unless
        (and
         (not (uiop:directory-pathname-p entry))
         (string-equal
          "lisp"
          (or (pathname-type entry) "")))
      (error
       'cadr-ai:configuration-error
       :message
       (format nil "Extension entry is not a .lisp file: ~A"
               (namestring entry))))
    (make-extension-source-record
     :id
     (string-downcase
      (or
       id
       (if (uiop:directory-pathname-p resolved)
           (extension-directory-id resolved)
           (pathname-name resolved))))
     :path (namestring (truename entry))
     :scope scope
     :rank rank
     :order order)))

(defun discover-extensions-in-directory
    (directory scope rank)
  (let ((root
          (uiop:ensure-directory-pathname
           (pathname directory)))
        (candidates nil))
    (unless (probe-file root)
      (return-from discover-extensions-in-directory nil))
    (dolist
        (path
         (directory (merge-pathnames "*.lisp" root)))
      (when
          (and
           (not (uiop:directory-pathname-p path))
           (string-equal
            "lisp"
            (or (pathname-type path) "")))
        (push path candidates)))
    (dolist (path (uiop:subdirectories root))
      (when
          (probe-file
           (merge-pathnames "extension.lisp" path))
        (push path candidates)))
    (setf candidates
          (sort candidates
                #'string<
                :key #'namestring))
    (loop for path in candidates
          for order from 0
          collect
          (make-extension-source-record-for-path
           path scope rank order))))

(defun dedupe-extension-sources (sources)
  (let ((seen (make-hash-table :test #'equal))
        (selected nil)
        (errors nil))
    (dolist (source sources)
      (let ((existing
              (gethash
               (extension-source-record-id source)
               seen)))
        (if existing
            (push
             (format nil
                     "Extension id ~S from ~A is shadowed by ~A"
                     (extension-source-record-id source)
                     (extension-source-record-path source)
                     (extension-source-record-path existing))
             errors)
            (progn
              (setf
               (gethash
                (extension-source-record-id source)
                seen)
               source)
              (push source selected)))))
    (values
     (nreverse selected)
     (nreverse errors))))

(defun discover-extension-sources (manager)
  (let ((errors nil)
        (explicit nil)
        (package-project nil)
        (package-global nil))
    (loop
      for path in
      (reverse
       (cli-extension-manager-explicit-paths
        manager))
      for order from 0
      do
      (handler-case
          (push
           (make-extension-source-record-for-path
            (merge-pathnames
             (pathname path)
             (cli-extension-manager-cwd manager))
            :cli 2 order)
           explicit)
        (condition (condition)
          (push (princ-to-string condition) errors))))
    (loop
      for entry in
      (cli-extension-manager-configured-package-paths
       manager)
      for order from 0
      for scope = (car entry)
      for path = (cdr entry)
      do
      (handler-case
          (let ((record
                  (make-extension-source-record-for-path
                   path scope
                   (if (eq scope :project) 1 0)
                   order)))
            (if (eq scope :project)
                (push record package-project)
                (push record package-global)))
        (condition (condition)
          (push (princ-to-string condition) errors))))
    (multiple-value-bind (selected collisions)
        (dedupe-extension-sources
         (nconc
          (nreverse explicit)
          (unless
              (cli-extension-manager-no-discovery-p
               manager)
            (nconc
             (nreverse package-project)
             (discover-extensions-in-directory
              (merge-pathnames
               ".cadr/extensions/"
               (cli-extension-manager-cwd manager))
              :project 1)))
          (unless
              (cli-extension-manager-no-discovery-p
               manager)
            (nconc
             (nreverse package-global)
             (discover-extensions-in-directory
              (cli-extension-manager-global-directory
               manager)
              :global 0)))))
      (values selected
              (nreverse errors)
              collisions))))

(defun extension-package-fragment (text)
  (with-output-to-string (output)
    (loop for character across text
          do
          (write-char
           (if
               (or
                (alphanumericp character)
                (member character '(#\- #\_)))
               (char-upcase character)
               #\-)
           output))))

(defun call-with-extension-output-boundary
    (manager function)
  (let ((diagnostics
          (make-broadcast-stream)))
    (unwind-protect
         (let ((*standard-output*
                 (cli-extension-manager-output manager))
               (*error-output*
                 (cli-extension-manager-output manager))
               (*trace-output* diagnostics)
               (*load-verbose* nil)
               (*load-print* nil)
               (*compile-verbose* nil)
               (*compile-print* nil)
               (asdf:*verbose-out* diagnostics))
           (handler-bind
               ((warning
                  (lambda (condition)
                    (let ((restart
                            (find-restart
                             'muffle-warning condition)))
                      (when restart
                        (invoke-restart restart))))))
             (funcall function)))
      (close diagnostics))))

(defun call-with-infrastructure-output-isolated
    (function)
  (let ((diagnostics
          (make-broadcast-stream)))
    (unwind-protect
         (let ((*standard-output* diagnostics)
               (*error-output* diagnostics)
               (*trace-output* diagnostics)
               (asdf:*verbose-out* diagnostics))
           (funcall function))
      (close diagnostics))))

(defun extension-local-system-name-p (name)
  (and
   (stringp name)
   (plusp (length name))
   (not (member name '("." "..") :test #'string=))
   (loop for character across name
         always
         (or (alphanumericp character)
             (member character '(#\- #\_ #\.))))))

(defun read-extension-local-systems (source)
  (let* ((entry
           (pathname (extension-source-record-path source)))
         (manifest
           (merge-pathnames
            "extension-dependencies.sexp"
            (uiop:pathname-directory-pathname entry))))
    (unless (probe-file manifest)
      (return-from read-extension-local-systems nil))
    (let ((value
            (with-open-file (stream manifest :direction :input)
              (let ((*read-eval* nil))
                (read stream nil :missing)))))
      (unless
          (and
           (listp value)
           (evenp (length value))
           (loop for tail on value by #'cddr
                 always (eq (first tail) :systems))
           (let ((systems (getf value :systems :missing)))
             (and
              (listp systems)
              (every #'extension-local-system-name-p systems)
              (= (length systems)
                 (length (remove-duplicates systems :test #'string-equal))))))
        (error
         'cadr-agent:extension-registration-error
         :message
         (format nil
                 "Invalid extension dependency manifest ~A"
                 (namestring manifest))))
      (copy-list (getf value :systems)))))

(defvar *extension-local-asdf-lock*
  (sb-thread:make-mutex
   :name "cadr extension-local ASDF loader"))

(defun load-extension-local-system
    (directory system asd-path)
  (sb-thread:with-mutex (*extension-local-asdf-lock*)
    (call-with-infrastructure-output-isolated
     (lambda ()
       (let ((asdf/source-registry:*source-registry* nil)
             (asdf/source-registry:*source-registry-parameter*
               `(:source-registry
                 (:directory ,(truename directory))
                 :inherit-configuration)))
         (asdf/source-registry:initialize-source-registry
          asdf/source-registry:*source-registry-parameter*)
         (asdf/session:with-asdf-session
             (:override t
              :override-cache t
              :override-forcing t)
           (handler-bind
               ((warning
                  (lambda (condition)
                    (let ((restart
                            (find-restart 'muffle-warning condition)))
                      (when restart
                        (invoke-restart restart)))))
                (asdf/plan:system-out-of-date
                  (lambda (condition)
                    ;; FIND-SYSTEM deliberately signals this condition before
                    ;; reloading a changed definition.  Its CONTINUE restart
                    ;; is the local, documented path; do not let a surrounding
                    ;; ASDF operation consume the extension's signal.
                    (let ((restart
                            (find-restart 'continue condition)))
                      (when restart
                        (invoke-restart restart))))))
             (asdf:load-asd (truename asd-path))
             (asdf:load-system system))))))))

(defun load-extension-local-systems (source)
  (let* ((entry
           (pathname (extension-source-record-path source)))
         (directory
           (uiop:pathname-directory-pathname entry)))
    (dolist (system (read-extension-local-systems source))
      (let ((asd-path
              (merge-pathnames
               (make-pathname :name system :type "asd")
               directory)))
        (handler-case
            (progn
              (unless (probe-file asd-path)
                (error "Local ASDF definition does not exist: ~A"
                       (namestring asd-path)))
              (load-extension-local-system
               directory system asd-path))
          (condition (condition)
            (error
             'cadr-agent:extension-registration-error
             :cause condition
             :message
             (format nil
                     "Failed to load local system ~A for extension ~A from ~A: ~A"
                     system
                     (extension-source-record-id source)
                     (extension-source-record-path source)
                     condition))))))))

(defun load-extension-source (manager source)
  (let* ((generation
           (next-extension-generation))
         (package-name
           (format nil "CADR-EXTENSION/~A/~D"
                   (extension-package-fragment
                    (extension-source-record-id source))
                   generation))
         (package
           (make-package
            package-name
            :use '(:cl :cadr-agent)))
         (bundle
           (cadr-agent::make-extension-bundle
            :id
            (extension-source-record-id source)
            :path
            (extension-source-record-path source)
            :scope
            (extension-source-record-scope source)
            :rank
            (extension-source-record-rank source)
            :order
            (extension-source-record-order source)
            :package package)))
    (handler-case
        (progn
          (load-extension-local-systems source)
          (let ((*package* package))
            (call-with-extension-output-boundary
             manager
             (lambda ()
               (cadr-agent::call-with-extension-load
                (cli-extension-manager-host manager)
                bundle
                (lambda ()
                  (load
                   (extension-source-record-path source)
                   :verbose nil
                   :print nil))))))
          bundle)
      (error (condition)
        (ignore-errors (delete-package package))
        (error
         'cadr-agent:extension-registration-error
         :cause condition
         :message
         (format nil
                 "Failed to load extension ~A from ~A: ~A"
                 (extension-source-record-id source)
                 (extension-source-record-path source)
                 condition))))))

(defun valid-inline-extension-factory-p (input)
  (or
   (functionp input)
   (and
    (listp input)
    (evenp (length input))
    (loop for (key value) on input by #'cddr
          always
          (case key
            (:name (stringp value))
            (:factory (functionp value))
            (:hidden-p
             (or (null value) (eq value t)))
            (otherwise nil)))
    (stringp (getf input :name))
    (plusp (length (getf input :name)))
    (functionp (getf input :factory)))))

(defun load-inline-extension-factory
    (manager input order anonymous-index)
  (unless (valid-inline-extension-factory-p input)
    (error
     'cadr-agent:extension-registration-error
     :message
     "Inline extension must be a function or (:NAME string :FACTORY function :HIDDEN-P boolean)"))
  (let* ((named-p (not (functionp input)))
         (name
           (if named-p
               (getf input :name)
               (format nil "~D" anonymous-index)))
         (path
           (format nil "<inline:~A>" name))
         (factory
           (if named-p
               (getf input :factory)
               input))
         (bundle
           (cadr-agent::make-extension-bundle
            :id path
            :path path
            :scope :inline
            :rank 3
            :order order
            :hidden-p
            (and named-p
                 (not
                  (null
                   (getf input :hidden-p)))))))
    (call-with-extension-output-boundary
     manager
     (lambda ()
       (cadr-agent::call-with-extension-load
        (cli-extension-manager-host manager)
        bundle
        (lambda ()
          (funcall
           factory
           (cadr-agent:current-extension-api))))))
    bundle))

(defun same-extension-source-p (bundle source)
  (and
   bundle
   (string=
    (cadr-agent::extension-bundle-path bundle)
    (extension-source-record-path source))))

(defun reload-cli-extensions (manager)
  (multiple-value-bind
        (sources discovery-errors discovery-conflicts)
      (discover-extension-sources manager)
    (let ((bundles nil)
          (errors (copy-list discovery-errors))
          (loaded 0)
          (next-last-good
            (make-hash-table :test #'equal)))
      (dolist (source sources)
        (let* ((id (extension-source-record-id source))
               (old
                 (gethash
                  id
                  (cli-extension-manager-last-good
                   manager)))
               (bundle
                 (handler-case
                     (prog1
                         (load-extension-source
                          manager source)
                       (incf loaded))
                   (error (condition)
                     (push (princ-to-string condition)
                           errors)
                     (extension-manager-notify
                      manager
                      (princ-to-string condition)
                      :error)
                     (and
                      (same-extension-source-p
                       old source)
                      old)))))
          (when bundle
            (setf (gethash id next-last-good)
                  bundle)
            (push bundle bundles))))
      (loop
        for input in
        (cli-extension-manager-extension-factories
         manager)
        for order from 1
        with anonymous-index = 0
        do
        (handler-case
            (progn
              (when (functionp input)
                (incf anonymous-index))
              (push
               (load-inline-extension-factory
                manager input order
                anonymous-index)
               bundles)
              (incf loaded))
          (error (condition)
            (push (princ-to-string condition)
                  errors)
            (extension-manager-notify
             manager
             (princ-to-string condition)
             :error))))
      (setf bundles (nreverse bundles)
            (cli-extension-manager-last-good manager)
            next-last-good)
      (let ((conflicts
              (nconc
               discovery-conflicts
               (cadr-agent::replace-extension-bundles
                (cli-extension-manager-host manager)
                bundles))))
        (dolist (conflict conflicts)
          (extension-manager-notify
           manager conflict :warning))
        (dolist (error discovery-errors)
          (extension-manager-notify
           manager error :error))
        (setf
         (cli-extension-manager-package-names manager)
         (loop
           for bundle in bundles
           for package =
             (cadr-agent::extension-bundle-package bundle)
           when package
             collect (package-name package)))
        (list
         :loaded loaded
         :active (length bundles)
         :errors (nreverse errors)
         :conflicts conflicts)))))

(defun split-extension-command (line)
  (let* ((trimmed
           (string-trim
            '(#\Space #\Tab #\Newline #\Return)
            line))
         (separator
           (position-if
            (lambda (character)
              (member character
                      '(#\Space #\Tab #\Newline #\Return)))
            trimmed)))
    (values
     (if separator
         (subseq trimmed 0 separator)
         trimmed)
     (if separator
         (string-left-trim
          '(#\Space #\Tab #\Newline #\Return)
          (subseq trimmed separator))
         ""))))

(defun handle-extension-command (line manager)
  (multiple-value-bind (command arguments)
      (split-extension-command line)
    (cond
      ((string= command "/reload")
       (let ((report
               (reload-cli-extensions manager)))
         (extension-manager-notify
          manager
          (format nil
                  "Reloaded ~D extension~:P; ~D error~:P"
                  (getf report :active)
                  (length (getf report :errors)))
          (if (getf report :errors)
              :warning
              :info)))
       t)
      ((and
        (plusp (length command))
        (char= (char command 0) #\/))
       (cadr-agent::invoke-extension-command
        (cli-extension-manager-host manager)
        (subseq command 1)
        arguments))
      (t nil))))

(defun expand-cli-extension-prompt
    (manager text)
  (cadr-agent::expand-extension-prompt
   (cli-extension-manager-host manager)
   text))

;;; Git package installation

(defun string-prefix-p (prefix value)
  (and
   (<= (length prefix) (length value))
   (string-equal
    prefix value
    :end2 (length prefix))))

(defun split-path-segments (path)
  (let ((segments nil)
        (start 0))
    (loop for separator =
            (position #\/ path :start start)
          do
          (push
           (subseq path start separator)
           segments)
          while separator
          do (setf start (1+ separator)))
    (nreverse segments)))

(defun unsafe-git-source-p (source)
  (or
   (zerop (length source))
   (char= (char source 0) #\-)
   (find #\Null source)
   (find #\\ source)
   (member ".."
           (split-path-segments source)
           :test #'string=)))

(defun strip-git-query-and-ref (path)
  (subseq
   path
   0
   (or
    (position-if
     (lambda (character)
       (member character '(#\? #\#)))
     path)
    (length path))))

(defun git-source-path (source)
  (cond
    ((search "://" source)
     (let* ((scheme-end
              (+ (search "://" source) 3))
            (path-start
              (position #\/ source
                        :start scheme-end)))
       (and path-start
            (subseq source (1+ path-start)))))
    ((and
      (string-prefix-p "git@" source)
      (position #\: source))
     (subseq source
             (1+
              (position #\: source))))
    (t
     (let ((slash (position #\/ source)))
       (and slash (subseq source (1+ slash)))))))

(defun normalize-git-install-source (input)
  (let* ((trimmed
           (string-trim
            '(#\Space #\Tab #\Newline #\Return)
            input))
         (prefixed-p
           (and
            (string-prefix-p "git:" trimmed)
            (not (string-prefix-p "git://" trimmed))))
         (source
           (if prefixed-p
               (string-left-trim
                '(#\Space #\Tab)
                (subseq trimmed 4))
               trimmed))
         (explicit-protocol-p
           (some
            (lambda (prefix)
              (string-prefix-p prefix source))
            '("http://" "https://" "ssh://" "git://"))))
    (when
        (or
         (unsafe-git-source-p source)
         (string-prefix-p "file://" source)
         (and
          (not prefixed-p)
          (not explicit-protocol-p))
         (and
          prefixed-p
          (not
           (or explicit-protocol-p
               (string-prefix-p "git@" source)
               (position #\/ source)))))
      (error
       'cadr-ai:configuration-error
       :message
       (format nil "Invalid git extension URL: ~A"
               input)))
    (let* ((raw-path (git-source-path source))
           (path
             (and raw-path
                  (strip-git-query-and-ref raw-path)))
           (segments
             (and path
                  (remove
                   ""
                   (split-path-segments path)
                   :test #'string=)))
           (last-segment (car (last segments)))
           (name
             (and
              last-segment
              (if
                  (and
                   (> (length last-segment) 4)
                   (string-equal
                    ".git"
                    last-segment
                    :start2
                    (- (length last-segment) 4)))
                  (subseq
                   last-segment
                   0
                   (- (length last-segment) 4))
                  last-segment))))
      (when
          (or
           (null name)
           (not
            (cadr-agent::valid-extension-resource-name-p
             (string-downcase name))))
        (error
         'cadr-ai:configuration-error
         :message
         (format nil
                 "Cannot derive a safe extension name from ~A"
                 input)))
      (values source (string-downcase name)))))

(defun make-extension-staging-directory (root)
  (merge-pathnames
   (format nil ".staging-~36R-~36R/"
           (get-universal-time)
           (random most-positive-fixnum))
   root))

(defun default-git-clone-runner (argv)
  (uiop:run-program
   argv
   :output *standard-output*
   :error-output *error-output*
   :ignore-error-status nil))

(defun install-extension-package
    (manager input
     &key (runner #'default-git-clone-runner))
  (multiple-value-bind (source name)
      (normalize-git-install-source input)
    (let* ((root
             (cli-extension-manager-global-directory
              manager))
           (destination
             (merge-pathnames
              (format nil "~A/" name)
              root))
           (staging
             (make-extension-staging-directory root)))
      (ensure-directories-exist
       (merge-pathnames "anchor" root))
      (when (probe-file destination)
        (error
         'cadr-ai:configuration-error
         :message
         (format nil
                 "Extension destination already exists: ~A"
                 (namestring destination))))
      (unwind-protect
           (progn
             (call-with-infrastructure-output-isolated
              (lambda ()
                (funcall
                 runner
                 (list
                  "git" "clone" "--" source
                  (namestring staging)))))
             (unless
                 (probe-file
                  (merge-pathnames
                   "extension.lisp" staging))
               (error
                'cadr-ai:configuration-error
                :message
                "Installed extension has no top-level extension.lisp"))
             (rename-file staging destination)
             (setf staging nil)
             (reload-cli-extensions manager)
             (extension-manager-notify
              manager
              (format nil "Installed ~A to ~A"
                      source
                      (namestring destination))
              :info)
             destination)
        (when (and staging (probe-file staging))
          (uiop:delete-directory-tree
           staging
           :validate t
           :if-does-not-exist :ignore))))))
