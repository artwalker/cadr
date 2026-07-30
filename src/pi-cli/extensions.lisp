(in-package #:pi-cli)

(defstruct extension-source-record
  id
  path
  scope
  rank
  order)

(defvar *extension-generation-counter* 0)
(defvar *extension-generation-lock*
  (sb-thread:make-mutex
   :name "pi-cli extension generations"))

(defun next-extension-generation ()
  (sb-thread:with-mutex
      (*extension-generation-lock*)
    (incf *extension-generation-counter*)))

(defstruct (cli-extension-manager
            (:constructor %make-cli-extension-manager))
  cwd
  global-directory
  explicit-paths
  output
  (secret-function (constantly nil) :type function)
  host
  (last-good (make-hash-table :test #'equal)
             :type hash-table)
  (generation 0 :type (integer 0 *))
  (package-names nil :type list))

(defun default-extension-directory ()
  (merge-pathnames
   ".pi-cl/extensions/"
   (user-homedir-pathname)))

(defun extension-manager-notify
    (manager message level)
  (format
   (cli-extension-manager-output manager)
   "~&extension[~(~A~)]> ~A~%"
   level
   (pi-ai:redact-secrets
    message
    (funcall
     (cli-extension-manager-secret-function
      manager))))
  (finish-output
   (cli-extension-manager-output manager)))

(defun make-cli-extension-manager
    (&key
       (cwd (uiop:getcwd))
       (global-directory
         (default-extension-directory))
       explicit-paths
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
           :output output
           :secret-function
           (or secret-function
               (constantly nil)))))
    (let ((host
            (pi-agent::make-extension-host
             :cwd (cli-extension-manager-cwd manager)
             :mode mode
             :notify-function
             (lambda (message level)
               (extension-manager-notify
                manager message level))
             :reload-function
             (lambda ()
               (reload-cli-extensions manager)))))
      (setf (cli-extension-manager-host manager) host))
    manager))

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
       'pi-ai:configuration-error
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
       'pi-ai:configuration-error
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
        (explicit nil))
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
    (multiple-value-bind (selected collisions)
        (dedupe-extension-sources
         (nconc
          (nreverse explicit)
          (discover-extensions-in-directory
           (merge-pathnames
            ".pi-cl/extensions/"
            (cli-extension-manager-cwd manager))
           :project 1)
          (discover-extensions-in-directory
           (cli-extension-manager-global-directory
            manager)
           :global 0)))
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

(defun load-extension-source (manager source)
  (let* ((generation
           (next-extension-generation))
         (package-name
           (format nil "PI-EXTENSION/~A/~D"
                   (extension-package-fragment
                    (extension-source-record-id source))
                   generation))
         (package
           (make-package
            package-name
            :use '(:cl :pi-agent)))
         (bundle
           (pi-agent::make-extension-bundle
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
          (let ((*package* package)
                (*load-verbose* nil)
                (*load-print* nil)
                (*standard-output*
                  (cli-extension-manager-output manager))
                (*error-output*
                  (cli-extension-manager-output manager)))
            (pi-agent::call-with-extension-registration
             bundle
             (lambda ()
               (load
                (extension-source-record-path source)
                :verbose nil
                :print nil))))
          bundle)
      (condition (condition)
        (ignore-errors (delete-package package))
        (error
         'pi-agent:extension-registration-error
         :cause condition
         :message
         (format nil
                 "Failed to load extension ~A from ~A: ~A"
                 (extension-source-record-id source)
                 (extension-source-record-path source)
                 condition))))))

(defun same-extension-source-p (bundle source)
  (and
   bundle
   (string=
    (pi-agent::extension-bundle-path bundle)
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
                   (condition (condition)
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
      (setf bundles (nreverse bundles)
            (cli-extension-manager-last-good manager)
            next-last-good)
      (let ((conflicts
              (nconc
               discovery-conflicts
               (pi-agent::replace-extension-bundles
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
             (pi-agent::extension-bundle-package bundle)
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
      ((string= command "/install")
       (when (zerop (length arguments))
         (error
          'pi-ai:configuration-error
          :message "Usage: /install <git-url>"))
       (install-extension-package manager arguments)
       t)
      ((and
        (plusp (length command))
        (char= (char command 0) #\/))
       (pi-agent::invoke-extension-command
        (cli-extension-manager-host manager)
        (subseq command 1)
        arguments))
      (t nil))))

(defun expand-cli-extension-prompt
    (manager text)
  (pi-agent::expand-extension-prompt
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
       'pi-ai:configuration-error
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
            (pi-agent::valid-extension-resource-name-p
             (string-downcase name))))
        (error
         'pi-ai:configuration-error
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
         'pi-ai:configuration-error
         :message
         (format nil
                 "Extension destination already exists: ~A"
                 (namestring destination))))
      (unwind-protect
           (progn
             (let ((*standard-output*
                     (cli-extension-manager-output
                      manager))
                   (*error-output*
                     (cli-extension-manager-output
                      manager)))
               (funcall
                runner
                (list
                 "git" "clone" "--" source
                 (namestring staging))))
             (unless
                 (probe-file
                  (merge-pathnames
                   "extension.lisp" staging))
               (error
                'pi-ai:configuration-error
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
