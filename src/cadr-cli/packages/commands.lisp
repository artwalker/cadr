(in-package #:cadr-cli)

(defstruct package-command-options
  command
  source
  (local-p nil :type boolean)
  (force-p nil :type boolean)
  (offline-p nil :type boolean)
  project-trust-override
  (project-trust-override-supplied-p
   nil :type boolean)
  update-target
  (help-p nil :type boolean))

(defun parse-package-command (arguments)
  (let* ((name (first arguments))
         (command
           (cond
             ((string= name "uninstall") :remove)
             ((member name
                      '("install" "remove" "update"
                        "list" "config")
                      :test #'string=)
              (intern
               (string-upcase name)
               :keyword))
             (t nil))))
    (unless command
      (return-from parse-package-command nil))
    (let ((options
            (make-package-command-options
             :command command))
          (rest (rest arguments))
          (targets nil))
      (labels
          ((invalid (format-control &rest values)
             (error
              'cadr-ai:configuration-error
              :message
              (apply #'format nil
                     format-control values)))
           (set-trust (value)
             (when
                 (and
                  (package-command-options-project-trust-override-supplied-p
                   options)
                  (not
                   (eq
                    value
                    (package-command-options-project-trust-override
                     options))))
               (invalid
                "--approve and --no-approve cannot be combined"))
             (setf
              (package-command-options-project-trust-override
               options)
              value
              (package-command-options-project-trust-override-supplied-p
               options)
              t)))
        (loop while rest
              for argument = (pop rest)
              do
              (cond
                ((member argument '("-h" "--help")
                         :test #'string=)
                 (setf
                  (package-command-options-help-p options)
                  t))
                ((member argument '("-l" "--local")
                         :test #'string=)
                 (unless
                     (member command
                             '(:install :remove :config))
                   (invalid
                    "Unknown ~A option: ~A"
                    (string-downcase
                     (symbol-name command))
                    argument))
                 (setf
                  (package-command-options-local-p
                   options)
                  t))
                ((member argument '("-a" "--approve")
                         :test #'string=)
                 (set-trust t))
                ((member argument '("-na" "--no-approve")
                         :test #'string=)
                 (set-trust nil))
                ((string= argument "--force")
                 (unless (eq command :update)
                   (invalid
                    "Unknown ~A option: --force"
                    (string-downcase
                     (symbol-name command))))
                 (setf
                  (package-command-options-force-p options)
                  t))
                ((string= argument "--offline")
                 (setf
                  (package-command-options-offline-p
                   options)
                  t))
                ((and (eq command :update)
                      (member
                       argument
                       '("--self" "--extensions"
                         "--models" "--all")
                       :test #'string=))
                 (push
                  (intern
                   (string-upcase
                    (subseq argument 2))
                   :keyword)
                  targets))
                ((and (eq command :update)
                      (string= argument
                               "--extension"))
                 (unless rest
                   (invalid
                    "--extension requires a value"))
                 (push
                  (list :extensions
                        (pop rest))
                  targets))
                ((cli-string-prefix-p "-" argument)
                 (invalid
                  "Unknown ~A option: ~A"
                  (string-downcase
                   (symbol-name command))
                  argument))
                ((package-command-options-source options)
                 (invalid
                  "Unexpected argument ~A"
                  argument))
                (t
                 (setf
                  (package-command-options-source options)
                  argument)))))
      (when (> (length targets) 1)
        (error
         'cadr-ai:configuration-error
         :message
         "Update target options cannot be combined"))
      (when targets
        (let ((target (first targets)))
          (setf
           (package-command-options-update-target options)
           (if (listp target)
               target
               (list target)))))
      (when
          (and
           (member command '(:install :remove))
           (not
            (package-command-options-help-p options))
           (null
            (package-command-options-source options)))
        (error
         'cadr-ai:configuration-error
         :message
         (format nil
                 "Missing ~A source"
                 (string-downcase
                  (symbol-name command)))))
      (when
          (and
           (eq command :update)
           (package-command-options-source options)
           targets)
        (error
         'cadr-ai:configuration-error
         :message
         "An update source cannot be combined with an update target option"))
      (when
          (and
           (eq command :update)
           (null
            (package-command-options-update-target
             options)))
        (setf
         (package-command-options-update-target options)
         (if
             (package-command-options-source options)
             (list
              :extensions
              (package-command-options-source
               options))
             '(:self))))
      options)))

(defun package-command-usage
    (command)
  (ecase command
    (:install
     "cadr install <source> [-l] [--approve|--no-approve]")
    (:remove
     "cadr remove <source> [-l] [--approve|--no-approve]")
    (:update
     "cadr update [source] [--self|--extensions|--models|--all] [--extension <source>] [--force]")
    (:list
     "cadr list [--approve|--no-approve]")
    (:config
     "cadr config [-l] [--approve|--no-approve]")))

(defun print-package-command-help
    (command &optional
               (stream *standard-output*))
  (format stream "Usage:~%  ~A~%~%"
          (package-command-usage command))
  (ecase command
    (:install
     (format stream
             "Install a Common Lisp extension/resource package and add it to settings.~%"))
    (:remove
     (format stream
             "Remove a configured package. Alias: cadr uninstall.~%"))
    (:update
     (format stream
             "Update installed Git packages. Self updates follow the Lisp build/install method.~%"))
    (:list
     (format stream
             "List configured user and project packages.~%"))
    (:config
     (format stream
             "Show the active resource configuration paths.~%")))
  (finish-output stream))

;; `cadr config` is a standalone, non-alt-screen selector, matching Pi's
;; public ConfigSelector instead of reducing the command to path diagnostics.
(defstruct config-resource-item
  path type scope base-directory display-name
  (origin :top-level)
  (source "auto" :type string)
  (enabled-p t :type boolean))

(defstruct (config-selector-state
            (:constructor %make-config-selector-state))
  settings-manager cwd agent-directory
  (project-mode-available-p t :type boolean)
  (write-scope :global)
  (global-items nil :type list)
  (project-items nil :type list)
  (query "" :type string)
  (flat-items nil :type list)
  (selected 0 :type (integer 0 *))
  (max-visible 16 :type (integer 1 *))
  (project-overrides
    (make-hash-table :test #'equal)
    :type hash-table)
  (inherited-enabled
    (make-hash-table :test #'equal)
    :type hash-table))

(defparameter +config-resource-specifications+
  '((:extensions "extensions/" "lisp" nil)
    (:skills "skills/" nil "SKILL.md")
    (:prompts "prompts/" "md" nil)
    (:themes "themes/" "json" nil)))

(defun config-resource-type-label (type)
  (ecase type
    (:extensions "Extensions")
    (:skills "Skills")
    (:prompts "Prompts")
    (:themes "Themes")))

(defun config-directory-files-recursively (directory)
  (when (uiop:directory-exists-p directory)
    (append
     (uiop:directory-files directory)
     (mapcan
      #'config-directory-files-recursively
      (uiop:subdirectories directory)))))

(defun config-resource-file-p (path extension basename)
  (and
   (or (null extension)
       (string-equal (or (pathname-type path) "") extension))
   (or (null basename)
       (string= (file-namestring path) basename))))

(defun config-resource-display-name (path type)
  (if (and (eq type :skills)
           (string= (file-namestring path) "SKILL.md"))
      (princ-to-string
       (car
        (last
         (pathname-directory
          (uiop:pathname-directory-pathname path)))))
      (file-namestring path)))

(defun discover-config-resource-items (base scope)
  (let ((base (uiop:ensure-directory-pathname base))
        (items nil))
    (dolist (spec +config-resource-specifications+)
      (destructuring-bind
          (type relative extension basename) spec
        (dolist
            (path
             (sort
              (remove-if-not
               (lambda (candidate)
                 (config-resource-file-p
                  candidate extension basename))
               (config-directory-files-recursively
                (merge-pathnames relative base)))
              #'string< :key #'namestring))
          (push
           (make-config-resource-item
            :path path :type type :scope scope
            :base-directory base
            :origin :top-level :source "auto"
            :display-name
            (config-resource-display-name path type))
           items))))
    (nreverse items)))

(defun config-resource-item-key (item)
  (format
   nil "~(~A~):~A"
   (config-resource-item-type item)
   (canonical-file-name
    (config-resource-item-path item))))

(defun config-settings-array (object key)
  (let ((value (cadr-ai::json-get object key #())))
    (cond
      ((vectorp value) (coerce value 'list))
      ((listp value) (copy-list value))
      (t nil))))

(defun config-resource-specification (type)
  (or
   (find type +config-resource-specifications+
         :key #'first)
   (error "Unknown config resource type: ~S" type)))

(defun config-resource-files-at-path (path type)
  (let* ((spec (config-resource-specification type))
         (extension (third spec))
         (basename (fourth spec))
         (resolved (pathname path)))
    (cond
      ((uiop:directory-exists-p resolved)
       (sort
        (remove-if-not
         (lambda (candidate)
           (config-resource-file-p
            candidate extension basename))
         (config-directory-files-recursively resolved))
        #'string< :key #'namestring))
      ((and (probe-file resolved)
            (config-resource-file-p
             resolved extension basename))
       (list (truename resolved)))
      (t nil))))

(defun config-normalize-pattern-path (value)
  (let ((normalized
          (substitute #\/ #\\ value)))
    (if (uiop:string-prefix-p "./" normalized)
        (subseq normalized 2)
        normalized)))

(defun config-glob-regex (pattern)
  (with-output-to-string (stream)
    (write-char #\^ stream)
    (loop for character across
          (config-normalize-pattern-path pattern)
          do
          (case character
            (#\* (write-string "[^/]*" stream))
            (#\? (write-string "[^/]" stream))
            ((#\. #\+ #\( #\) #\[ #\] #\{ #\}
              #\^ #\$ #\| #\\)
             (write-char #\\ stream)
             (write-char character stream))
            (otherwise
             (write-char character stream))))
    (write-char #\$ stream)))

(defun config-pattern-candidates (path base-directory)
  (let* ((absolute
           (config-normalize-pattern-path
            (namestring path)))
         (relative
           (config-normalize-pattern-path
            (enough-namestring path base-directory)))
         (name (file-namestring path))
         (skill-p (string= name "SKILL.md"))
         (parent
           (and skill-p
                (uiop:pathname-directory-pathname path))))
    (remove-duplicates
     (append
      (list relative name absolute)
      (and parent
           (list
            (config-normalize-pattern-path
             (string-right-trim
              "/" (enough-namestring parent base-directory)))
            (princ-to-string
             (car (last (pathname-directory parent))))
            (config-normalize-pattern-path
             (string-right-trim "/" (namestring parent))))))
     :test #'string=)))

(defun config-pattern-matches-p
    (path pattern base-directory &key exact-p)
  (let ((normalized
          (config-normalize-pattern-path pattern)))
    (some
     (lambda (candidate)
       (if exact-p
           (string= normalized candidate)
           (not
            (null
             (cl-ppcre:scan
              (config-glob-regex normalized)
              candidate)))))
     (config-pattern-candidates path base-directory))))

(defun config-enabled-by-patterns-p
    (path patterns base-directory &key (default t))
  (let ((includes nil)
        (excludes nil)
        (loads nil)
        (unloads nil))
    (dolist (pattern patterns)
      (when (and (stringp pattern)
                 (plusp (length pattern)))
        (case (char pattern 0)
          (#\+ (push (subseq pattern 1) loads))
          (#\- (push (subseq pattern 1) unloads))
          (#\! (push (subseq pattern 1) excludes))
          (otherwise (push pattern includes)))))
    (let ((enabled
            (if includes
                (some
                 (lambda (pattern)
                   (config-pattern-matches-p
                    path pattern base-directory))
                 includes)
                default)))
      (when
          (some
           (lambda (pattern)
             (config-pattern-matches-p
              path pattern base-directory))
           excludes)
        (setf enabled nil))
      (when
          (some
           (lambda (pattern)
             (config-pattern-matches-p
              path pattern base-directory :exact-p t))
           loads)
        (setf enabled t))
      (when
          (some
           (lambda (pattern)
             (config-pattern-matches-p
              path pattern base-directory :exact-p t))
           unloads)
        (setf enabled nil))
      (not (null enabled)))))

(defun config-package-entry-autoload-disabled-p (entry)
  (and
   (hash-table-p entry)
   (multiple-value-bind (value found-p)
       (gethash "autoload" entry)
     (and found-p (null value)))))

(defun config-package-entry-filter (entry type)
  (when (hash-table-p entry)
    (multiple-value-bind (value found-p)
        (gethash
         (string-downcase (symbol-name type)) entry)
      (when found-p
        (values
         (cond
           ((vectorp value) (coerce value 'list))
           ((listp value) (copy-list value))
           (t nil))
         t)))))

(defun config-package-setting-record
    (entry scope base-directory install-root)
  (let ((source (package-entry-source entry)))
    (when source
      (let* ((parsed (parse-package-source source))
             (path
               (case (package-source-type parsed)
                 (:local
                  (uiop:ensure-absolute-pathname
                   (merge-pathnames
                    (pathname (package-source-path parsed))
                    (uiop:ensure-directory-pathname
                     base-directory))))
                 (:git
                  (package-git-install-path parsed install-root))
                 (otherwise nil))))
        (list
         :entry entry :scope scope :source source
         :base base-directory :parsed parsed :path path
         :identity
         (package-source-identity source base-directory)
         :autoload-disabled-p
         (config-package-entry-autoload-disabled-p entry))))))

(defun config-package-setting-records
    (manager cwd agent-directory include-project-p)
  (let* ((project-base
           (merge-pathnames
            ".cadr/" (uiop:ensure-directory-pathname cwd)))
         (global-base
           (uiop:ensure-directory-pathname agent-directory))
         (global-root (merge-pathnames "packages/" global-base))
         (project-root (merge-pathnames "packages/" project-base))
         (global
           (remove
            nil
            (mapcar
             (lambda (entry)
               (config-package-setting-record
                entry :user global-base global-root))
             (settings-package-entries manager :global))))
         (project
           (and include-project-p
                (remove
                 nil
                 (mapcar
                  (lambda (entry)
                    (config-package-setting-record
                     entry :project project-base project-root))
                  (settings-package-entries manager :project)))))
         (result nil)
         (consumed-global
           (make-hash-table :test #'equal)))
    (dolist (record project)
      (let* ((identity (getf record :identity))
             (global-record
               (find identity global :test #'equal
                     :key (lambda (item)
                            (getf item :identity)))))
        (if (getf record :autoload-disabled-p)
            (progn
              (when global-record
                (setf
                 (getf record :path)
                 (getf global-record :path)
                 (gethash identity consumed-global) t))
              (push record result)
              (when global-record
                (push global-record result)))
            (progn
              (push record result)
              (when global-record
                (setf (gethash identity consumed-global) t))))))
    (dolist (record global)
      (unless (gethash (getf record :identity)
                       consumed-global)
        (push record result)))
    (nreverse result)))

(defun config-package-resource-files (root type)
  (unless (and root (probe-file root))
    (return-from config-package-resource-files nil))
  (multiple-value-bind (manifest manifest-p)
      (read-package-pi-manifest root)
    (if manifest-p
        (remove-duplicates
         (mapcan
          (lambda (relative)
            (let ((path
                    (package-manifest-path root relative)))
              (and path
                   (config-resource-files-at-path path type))))
          (getf manifest type))
         :test #'equal)
        (if (eq type :extensions)
            (let ((extension
                    (merge-pathnames
                     "extension.lisp"
                     (uiop:ensure-directory-pathname root))))
              (and (probe-file extension)
                   (list (truename extension))))
            (config-resource-files-at-path
             (merge-pathnames
              (second (config-resource-specification type))
              (uiop:ensure-directory-pathname root))
             type)))))

(defun config-package-delta-resource-state
    (path patterns root)
  (let ((matched-p nil)
        (enabled-p nil))
    (dolist (pattern patterns)
      (when (and (stringp pattern)
                 (plusp (length pattern)))
        (let* ((prefix (char pattern 0))
               (override-p (find prefix "!+-"))
               (target
                 (if override-p
                     (subseq pattern 1)
                     pattern)))
          (when
              (config-pattern-matches-p
               path target root
               :exact-p (not
                         (null
                          (find prefix "+-"))))
            (setf matched-p t
                  enabled-p
                  (not
                   (null
                    (and (not (char= prefix #\-))
                         (not (char= prefix #\!))))))))))
    (values enabled-p matched-p)))

(defun config-resolve-package-items
    (manager cwd agent-directory include-project-p)
  (let ((items nil)
        (seen (make-hash-table :test #'equal)))
    (dolist
        (record
         (config-package-setting-records
          manager cwd agent-directory include-project-p))
      (let ((root (getf record :path))
            (entry (getf record :entry)))
        (dolist (type '(:extensions :skills :prompts :themes))
          (multiple-value-bind (patterns supplied-p)
              (config-package-entry-filter entry type)
            (dolist (path (config-package-resource-files root type))
              (let ((key
                      (format
                       nil "~(~A~):~A" type
                       (canonical-file-name path))))
                (unless (gethash key seen)
                  (multiple-value-bind
                        (enabled-p include-p)
                      (if (getf record :autoload-disabled-p)
                          (if (and supplied-p patterns)
                              (config-package-delta-resource-state
                               path patterns root)
                              (values nil nil))
                          (values
                           (if supplied-p
                               (and patterns
                                    (config-enabled-by-patterns-p
                                     path patterns root :default t))
                               t)
                           t))
                    (when include-p
                      (setf (gethash key seen) t)
                      (push
                       (make-config-resource-item
                        :path path :type type
                        :scope (getf record :scope)
                        :base-directory root
                        :origin :package
                        :source (getf record :source)
                        :display-name
                        (config-resource-display-name path type)
                        :enabled-p (not (null enabled-p)))
                       items))))))))))
    (nreverse items)))

(defun config-top-level-items-for-scope
    (object base-directory scope)
  (let ((items nil)
        (seen (make-hash-table :test #'equal))
        (base (uiop:ensure-directory-pathname base-directory)))
    (dolist (type '(:extensions :skills :prompts :themes))
      (let* ((key (string-downcase (symbol-name type)))
             (entries (config-settings-array object key))
             (plain
               (remove-if
                (lambda (entry)
                  (and
                   (stringp entry)
                   (or
                    (and (plusp (length entry))
                         (find (char entry 0) "!+-"))
                    (find #\* entry)
                    (find #\? entry))))
                entries))
             (overrides
               (remove-if-not
                (lambda (entry)
                  (and (stringp entry)
                       (plusp (length entry))
                       (find (char entry 0) "!+-")))
                entries)))
        (labels
            ((add (path source enabled-p)
               (let ((item-key
                       (format
                        nil "~(~A~):~A" type
                        (canonical-file-name path))))
                 (unless (gethash item-key seen)
                   (setf (gethash item-key seen) t)
                   (push
                    (make-config-resource-item
                     :path path :type type :scope scope
                     :base-directory base
                     :origin :top-level :source source
                     :display-name
                     (config-resource-display-name path type)
                     :enabled-p enabled-p)
                    items)))))
          (dolist (entry plain)
            (when (stringp entry)
              (dolist
                  (path
                   (config-resource-files-at-path
                    (merge-pathnames (pathname entry) base)
                    type))
                (add
                 path "local"
                 (config-enabled-by-patterns-p
                  path overrides base :default t)))))
          (dolist
              (path
               (config-resource-files-at-path
                (merge-pathnames
                 (second (config-resource-specification type))
                 base)
                type))
            (add
             path "auto"
             (config-enabled-by-patterns-p
              path overrides base :default t))))))
    (nreverse items)))

(defun config-resolve-top-level-items
    (manager cwd agent-directory include-project-p)
  (let* ((global
           (config-top-level-items-for-scope
            (settings-manager-global manager)
            agent-directory :user))
         (project
           (and include-project-p
                (config-top-level-items-for-scope
                 (settings-manager-project manager)
                 (merge-pathnames
                  ".cadr/"
                  (uiop:ensure-directory-pathname cwd))
                 :project)))
         (seen (make-hash-table :test #'equal))
         (result nil))
    (dolist (item (append project global))
      (let ((key (config-resource-item-key item)))
        (unless (gethash key seen)
          (setf (gethash key seen) t)
          (push item result))))
    (nreverse result)))

(defun config-resolved-resource-items
    (manager cwd agent-directory include-project-p)
  (append
   (config-resolve-package-items
    manager cwd agent-directory include-project-p)
   (config-resolve-top-level-items
    manager cwd agent-directory include-project-p)))

(defun config-selector-items (state)
  (if (eq :project
          (config-selector-state-write-scope state))
      (copy-list
       (config-selector-state-project-items state))
      (copy-list
       (config-selector-state-global-items state))))

(defun config-selector-item-matches-p (item query)
  (or
   (zerop (length query))
   (search query
           (config-resource-item-display-name item)
           :test #'char-equal)
   (search query
           (namestring (config-resource-item-path item))
           :test #'char-equal)
   (search query
           (symbol-name (config-resource-item-type item))
           :test #'char-equal)))

(defun config-resource-group-key (item)
  (format
   nil "~(~A~):~(~A~):~A:~A"
   (config-resource-item-origin item)
   (config-resource-item-scope item)
   (config-resource-item-source item)
   (canonical-file-name
    (config-resource-item-base-directory item))))

(defun config-resource-group-label (state item)
  (if (eq :package (config-resource-item-origin item))
      (format
       nil "~A (~(~A~))"
       (config-resource-item-source item)
       (config-resource-item-scope item))
      (cond
        ((string= "local"
                  (config-resource-item-source item))
         (if (eq :user (config-resource-item-scope item))
             "User settings" "Project settings"))
        ((eq :user (config-resource-item-scope item))
         (format
          nil "User (~A)"
          (cadr-tui:shortened-home-path
           (namestring
            (config-selector-state-agent-directory state)))))
        (t "Project (.cadr/)"))))

(defun config-resource-group-less-p (left right)
  (let ((left-item (getf left :item))
        (right-item (getf right :item)))
    (cond
      ((not
        (eq (config-resource-item-origin left-item)
            (config-resource-item-origin right-item)))
       (eq :package
           (config-resource-item-origin left-item)))
      ((not
        (eq (config-resource-item-scope left-item)
            (config-resource-item-scope right-item)))
       (eq :user
           (config-resource-item-scope left-item)))
      (t
       (string<
        (config-resource-item-source left-item)
        (config-resource-item-source right-item))))))

(defun config-selector-rebuild (state)
  (let ((flat nil)
        (groups nil)
        (groups-by-key (make-hash-table :test #'equal))
        (query (config-selector-state-query state)))
    (dolist
        (item
         (remove-if-not
          (lambda (candidate)
            (config-selector-item-matches-p candidate query))
          (config-selector-items state)))
      (let* ((key (config-resource-group-key item))
             (group (gethash key groups-by-key)))
        (unless group
          (setf
           group
           (list :key key :item item :items nil)
           (gethash key groups-by-key) group)
          (push group groups))
        (push item (getf group :items))))
    (setf groups
          (stable-sort groups #'config-resource-group-less-p))
    (dolist (group groups)
      (let* ((representative (getf group :item))
             (scope
               (config-resource-item-scope representative))
             (items (nreverse (getf group :items))))
        (push
         (list
          :kind :group :scope scope
          :label
          (config-resource-group-label
           state representative))
         flat)
        (dolist (type '(:extensions :skills :prompts :themes))
          (let ((typed
                  (sort
                   (remove-if-not
                    (lambda (item)
                      (eq type
                          (config-resource-item-type item)))
                    items)
                   #'string<
                   :key #'config-resource-item-display-name)))
            (when typed
              (push
               (list :kind :subgroup :scope scope
                     :label (config-resource-type-label type))
               flat)
              (dolist (item typed)
                (push (list :kind :item :item item) flat)))))))
    (setf flat (nreverse flat))
    (setf
     (config-selector-state-flat-items state) flat
     (config-selector-state-selected state)
     (or
      (position
       :item flat
       :key (lambda (entry) (getf entry :kind)))
      0)))
  state)

(defun config-selector-project-package-entry
    (state item)
  (let* ((manager
           (config-selector-state-settings-manager state))
         (project-base
           (merge-pathnames
            ".cadr/"
            (config-selector-state-cwd state)))
         (source-base
           (if (eq :project
                   (config-resource-item-scope item))
               project-base
               (config-selector-state-agent-directory state)))
         (identity
           (package-source-identity
            (config-resource-item-source item)
            source-base)))
    (find
     identity
     (settings-package-entries manager :project)
     :test #'equal
     :key
     (lambda (entry)
       (let ((source (package-entry-source entry)))
         (and source
              (package-source-identity
               source project-base)))))))

(defun config-selector-project-package-state
    (state item)
  (let ((entry
          (config-selector-project-package-entry
           state item)))
    (unless (hash-table-p entry)
      (return-from
          config-selector-project-package-state
        :inherit))
    (multiple-value-bind (patterns supplied-p)
        (config-package-entry-filter
         entry (config-resource-item-type item))
      (unless supplied-p
        (return-from
            config-selector-project-package-state
          :inherit))
      (when (and (null patterns)
                 (not
                  (config-package-entry-autoload-disabled-p
                   entry)))
        (return-from
            config-selector-project-package-state
          :unload))
      (let ((result :inherit))
        (dolist (pattern patterns)
          (when (and (stringp pattern)
                     (plusp (length pattern)))
            (let* ((prefix (char pattern 0))
                   (target
                     (if (find prefix "!+-")
                         (subseq pattern 1)
                         pattern)))
              (when
                  (config-pattern-matches-p
                   (config-resource-item-path item)
                   target
                   (config-resource-item-base-directory item)
                   :exact-p t)
                (setf
                 result
                 (if (find prefix "!-")
                     :unload :load))))))
        result))))

(defun config-selector-project-top-level-state
    (state item)
  (let* ((manager
           (config-selector-state-settings-manager state))
         (project-base
           (merge-pathnames
            ".cadr/"
            (config-selector-state-cwd state)))
         (entries
           (config-selector-settings-values
            manager :project
            (string-downcase
             (symbol-name
              (config-resource-item-type item)))))
         (result :inherit))
    (dolist (entry entries)
      (when (and (stringp entry)
                 (plusp (length entry)))
        (let* ((prefix (char entry 0))
               (target
                 (if (find prefix "!+-")
                     (subseq entry 1)
                     entry)))
          (when
              (or
               (config-pattern-matches-p
                (config-resource-item-path item)
                target project-base :exact-p t)
               (config-pattern-matches-p
                (config-resource-item-path item)
                target
                (config-resource-item-base-directory item)
                :exact-p t))
            (setf
             result
             (if (find prefix "!-")
                 :unload :load))))))
    result))

(defun config-selector-derived-project-state
    (state item)
  (if (eq :package
          (config-resource-item-origin item))
      (config-selector-project-package-state
       state item)
      (config-selector-project-top-level-state
       state item)))

(defun make-config-selector-state
    (settings-manager cwd agent-directory terminal-height
     &key (write-scope :global)
       (project-mode-available-p t))
  (let* ((global-items
           (config-resolved-resource-items
            settings-manager cwd agent-directory nil))
         (project-items
           (and
            project-mode-available-p
            (config-resolved-resource-items
             settings-manager cwd agent-directory t)))
         (state
          (%make-config-selector-state
           :settings-manager settings-manager
           :cwd (uiop:ensure-directory-pathname cwd)
           :agent-directory
           (uiop:ensure-directory-pathname agent-directory)
           :project-mode-available-p project-mode-available-p
           :write-scope write-scope
           :global-items global-items
           :project-items project-items
           :max-visible (max 5 (- terminal-height 8)))))
    (dolist (item (config-selector-state-global-items state))
      (setf
       (gethash
        (config-resource-item-key item)
        (config-selector-state-inherited-enabled state))
       (config-resource-item-enabled-p item)))
    (dolist (item (config-selector-state-project-items state))
      (let ((override
              (config-selector-derived-project-state
               state item)))
        (unless (eq override :inherit)
          (setf
           (gethash
            (config-resource-item-key item)
            (config-selector-state-project-overrides state))
           override))))
    (config-selector-rebuild state)))

(defun config-selector-selected-entry (state)
  (nth
   (config-selector-state-selected state)
   (config-selector-state-flat-items state)))

(defun config-selector-find-item-index
    (entries start direction)
  (loop
    for index = (+ start direction)
      then (+ index direction)
    while (< -1 index (length entries))
    when (eq :item (getf (nth index entries) :kind))
      do (return index)
    finally (return start)))

(defun config-selector-move (state delta)
  (let ((entries (config-selector-state-flat-items state))
        (selected (config-selector-state-selected state))
        (direction (if (minusp delta) -1 1)))
    (loop repeat (abs delta)
      do
      (setf selected
            (config-selector-find-item-index
             entries selected direction)))
    (setf (config-selector-state-selected state) selected))
  state)

(defun config-selector-settings-values
    (manager scope key)
  (let* ((object
           (ecase scope
             (:global (settings-manager-global manager))
             (:project (settings-manager-project manager))))
         (value (cadr-ai::json-get object key #())))
    (cond
      ((vectorp value) (coerce value 'list))
      ((and (listp value) (every #'stringp value))
       (copy-list value))
      (t nil))))

(defun config-selector-resource-key (item)
  (string-downcase
   (symbol-name (config-resource-item-type item))))

(defun config-selector-relative-pattern (item)
  (enough-namestring
   (config-resource-item-path item)
   (config-resource-item-base-directory item)))

(defun config-selector-entry-target (entry)
  (if (and (plusp (length entry))
           (find (char entry 0) "!+-"))
      (subseq entry 1)
      entry))

(defun config-selector-replace-pattern
    (entries pattern override &key include-source-p)
  (let ((updated
          (remove
           pattern entries
           :key #'config-selector-entry-target
           :test #'string=)))
    (when (and include-source-p
               (not (member pattern updated :test #'string=)))
      (setf updated (append updated (list pattern))))
    (if override
        (append
         updated
         (list
          (concatenate
           'string
           (if (eq override :load) "+" "-")
           pattern)))
        updated)))

(defun config-selector-project-state (state item)
  (gethash
   (config-resource-item-key item)
   (config-selector-state-project-overrides state)
   :inherit))

(defun config-selector-inherited-enabled-p (state item)
  (gethash
   (config-resource-item-key item)
   (config-selector-state-inherited-enabled state)
   (config-resource-item-enabled-p item)))

(defun config-selector-next-project-state (state item)
  (let ((current (config-selector-project-state state item))
        (inherited-enabled-p
          (config-selector-inherited-enabled-p state item)))
    (ecase current
      (:inherit
       (if inherited-enabled-p :unload :load))
      (:unload
       (if inherited-enabled-p :load :inherit))
      (:load
       (if inherited-enabled-p :inherit :unload)))))

(defun config-selector-scope-base (state scope)
  (ecase scope
    (:global
     (config-selector-state-agent-directory state))
    (:project
     (merge-pathnames
      ".cadr/" (config-selector-state-cwd state)))))

(defun config-selector-item-source-base (state item)
  (config-selector-scope-base
   state
   (if (eq :project
           (config-resource-item-scope item))
       :project :global)))

(defun config-selector-package-entry-index
    (state item packages scope)
  (let ((item-identity
          (package-source-identity
           (config-resource-item-source item)
           (config-selector-item-source-base state item)))
        (base (config-selector-scope-base state scope)))
    (position
     item-identity packages
     :test #'equal
     :key
     (lambda (entry)
       (let ((source (package-entry-source entry)))
         (and source
              (package-source-identity source base)))))))

(defun config-selector-package-override-source
    (state item scope)
  (let ((source
          (config-resource-item-source item)))
    (if (eq :local
            (package-source-type
             (parse-package-source source)))
        (enough-namestring
         (config-resource-item-base-directory item)
         (config-selector-scope-base state scope))
        source)))

(defun config-selector-package-resource-pattern (item)
  (enough-namestring
   (config-resource-item-path item)
   (config-resource-item-base-directory item)))

(defun config-selector-package-entry-has-filters-p (entry)
  (some
   (lambda (type)
     (nth-value
      1
      (gethash
       (string-downcase (symbol-name type))
       entry)))
   '(:extensions :skills :prompts :themes)))

(defun config-selector-set-package-state
    (state item scope next)
  (let* ((manager
           (config-selector-state-settings-manager state))
         (object
           (ecase scope
             (:global (settings-manager-global manager))
             (:project (settings-manager-project manager))))
         (packages
           (copy-list
            (sequence-list
             (cadr-ai::json-get object "packages" #()))))
         (index
           (config-selector-package-entry-index
            state item packages scope)))
    (when (and (null index) (eq next :inherit))
      (return-from config-selector-set-package-state nil))
    (unless index
      (setf packages
            (append
             packages
             (list
              (cadr-ai::json-object
               "source"
               (config-selector-package-override-source
                state item scope)
               "autoload"
               (if (eq scope :project) nil t))))
            index (1- (length packages))))
    (let* ((raw (nth index packages))
           (entry
             (if (hash-table-p raw)
                 (copy-json-object raw)
                 (cadr-ai::json-object "source" raw)))
           (key (config-selector-resource-key item))
           (pattern
             (config-selector-package-resource-pattern item))
           (current
             (config-settings-array entry key))
           (updated
             (remove
              pattern current
              :key #'config-selector-entry-target
              :test #'string=)))
      (if (eq next :inherit)
          (remhash key entry)
          (progn
            (setf updated
                  (append
                   updated
                   (list
                    (concatenate
                     'string
                     (if (eq next :load) "+" "-")
                     pattern))))
            (cadr-ai::json-put
             entry key (coerce updated 'vector))))
      (if (and (eq scope :project)
               (config-package-entry-autoload-disabled-p entry)
               (not
                (config-selector-package-entry-has-filters-p
                 entry)))
          (setf packages
                (append
                 (subseq packages 0 index)
                 (nthcdr (1+ index) packages)))
          (setf (nth index packages)
                (if (and
                     (not
                      (config-selector-package-entry-has-filters-p
                       entry))
                     (not
                      (config-package-entry-autoload-disabled-p
                       entry)))
                    (package-entry-source entry)
                    entry)))
      (settings-set
       manager "packages" (coerce packages 'vector)
       :scope scope)
      t)))

(defun config-selector-set-top-level-project-state
    (state item next)
  (let* ((manager
           (config-selector-state-settings-manager state))
         (key (config-selector-resource-key item))
         (values
           (config-selector-settings-values
            manager :project key))
         (project-base
           (config-selector-scope-base state :project))
         (inherited-p
           (not
            (null
             (gethash
              (config-resource-item-key item)
              (config-selector-state-inherited-enabled state)))))
         (pattern
           (if inherited-p
               (namestring (config-resource-item-path item))
               (enough-namestring
                (config-resource-item-path item)
                project-base)))
         (updated
           (remove-if
            (lambda (entry)
              (let ((target
                      (config-selector-entry-target entry)))
                (or
                 (config-pattern-matches-p
                  (config-resource-item-path item)
                  target project-base :exact-p t)
                 (config-pattern-matches-p
                  (config-resource-item-path item)
                  target
                  (config-resource-item-base-directory item)
                  :exact-p t))))
            values)))
    (unless (eq next :inherit)
      (when inherited-p
        (setf updated (append updated (list pattern))))
      (setf updated
            (append
             updated
             (list
              (concatenate
               'string
               (if (eq next :load) "+" "-")
               pattern)))))
    (settings-set
     manager key (coerce updated 'vector)
     :scope :project)))

(defun config-selector-toggle-selected (state)
  (let* ((entry (config-selector-selected-entry state))
         (item
           (and (eq :item (getf entry :kind))
                (getf entry :item))))
    (unless item
      (return-from config-selector-toggle-selected state))
    (let* ((manager
             (config-selector-state-settings-manager state))
           (key (config-selector-resource-key item)))
      (if (eq :project
              (config-selector-state-write-scope state))
          (let ((next
                  (config-selector-next-project-state
                   state item)))
            (if (eq next :inherit)
                (remhash
                 (config-resource-item-key item)
                 (config-selector-state-project-overrides state))
                (setf
                 (gethash
                  (config-resource-item-key item)
                  (config-selector-state-project-overrides state))
                 next))
            (if (eq :package
                    (config-resource-item-origin item))
                (config-selector-set-package-state
                 state item :project next)
                (config-selector-set-top-level-project-state
                 state item next)))
          (let* ((enabled-p
                   (not
                    (config-resource-item-enabled-p item)))
                 (pattern
                   (config-selector-relative-pattern item))
                 (values
                   (config-selector-settings-values
                    manager :global key)))
            (setf
             (config-resource-item-enabled-p item)
             enabled-p)
            (if (eq :package
                    (config-resource-item-origin item))
                (config-selector-set-package-state
                 state item :global
                 (if enabled-p :load :unload))
                (settings-set
                 manager key
                 (coerce
                  (config-selector-replace-pattern
                   values pattern
                   (if enabled-p :load :unload))
                  'vector)
                 :scope :global))))))
  state)

(defun config-selector-switch-scope (state)
  (when (config-selector-state-project-mode-available-p state)
    (setf
     (config-selector-state-write-scope state)
     (if (eq :global
             (config-selector-state-write-scope state))
         :project :global))
    (config-selector-rebuild state))
  state)

(defun config-selector-handle-event (state event)
  (case (cadr-tui:input-event-kind event)
    (:up (config-selector-move state -1))
    (:down (config-selector-move state 1))
    (:page-up
     (config-selector-move
      state (- (config-selector-state-max-visible state))))
    (:page-down
     (config-selector-move
      state (config-selector-state-max-visible state)))
    (:tab (config-selector-switch-scope state))
    ((:enter :submit)
     (config-selector-toggle-selected state))
    (:backspace
     (let ((query (config-selector-state-query state)))
       (when (plusp (length query))
         (setf
          (config-selector-state-query state)
          (subseq query 0 (1- (length query))))
         (config-selector-rebuild state))))
    (:text
     (let ((text (or (cadr-tui:input-event-text event) "")))
       (if (string= text " ")
           (config-selector-toggle-selected state)
           (progn
             (setf
              (config-selector-state-query state)
              (concatenate
               'string
               (config-selector-state-query state)
               text))
             (config-selector-rebuild state))))))
  state)

(defun config-selector-fit-line (line width &optional ellipsis)
  (cadr-tui:truncate-to-width
   line (max 0 width) (or ellipsis "")))

(defun config-selector-hint (key description)
  (concatenate
   'string
   (cadr-tui:theme-foreground :dim key)
   (cadr-tui:theme-foreground
    :muted (concatenate 'string " " description))))

(defun config-selector-header-lines (state width)
  (let* ((project-p
           (eq :project
               (config-selector-state-write-scope state)))
         (title
           (cadr-tui:theme-bold
            (if project-p
                "Project Local Resources"
                "Global Resources")))
         (separator
           (cadr-tui:theme-foreground :muted " · "))
         (hint
           (concatenate
            'string
            (if
                (config-selector-state-project-mode-available-p state)
                (concatenate
                 'string
                 (config-selector-hint "tab" "switch mode")
                 separator)
                "")
            (config-selector-hint
             "space"
             (if project-p "cycle inherit/+/-" "toggle"))
            separator
            (config-selector-hint "esc" "close")))
         (spacing
           (max
            1
            (- width
               (cadr-tui:visible-width title)
               (cadr-tui:visible-width hint))))
         (scope-hint
           (if project-p
               ".cadr/settings.json · inherited global resources are dimmed"
               (format
                nil "~Asettings.json"
                (cadr-tui:shortened-home-path
                 (namestring
                  (config-selector-state-agent-directory state)))))))
    (list
     (config-selector-fit-line
      (concatenate
       'string title
       (make-string spacing :initial-element #\Space)
       hint)
      width)
     (config-selector-fit-line
      (cadr-tui:theme-foreground :muted scope-hint)
      width))))

(defun config-selector-override-suffix (state item)
  (if (not (eq :project
               (config-selector-state-write-scope state)))
      ""
      (case (config-selector-project-state state item)
        (:load
         (cadr-tui:theme-foreground
          :muted "  project load"))
        (:unload
         (cadr-tui:theme-foreground
          :muted "  project unload"))
        (otherwise
         (if (eq :user (config-resource-item-scope item))
             (cadr-tui:theme-foreground
              :dim "  inherited global")
             "")))))

(defun config-selector-checkbox (state item)
  (if (eq :project
          (config-selector-state-write-scope state))
      (case (config-selector-project-state state item)
        (:load
         (cadr-tui:theme-foreground :success "[+]"))
        (:unload
         (cadr-tui:theme-foreground :warning "[-]"))
        (otherwise
         (cadr-tui:theme-foreground
          :dim
          (if (config-selector-inherited-enabled-p state item)
              "[x]" "[ ]"))))
      (cadr-tui:theme-foreground
       (if (config-resource-item-enabled-p item)
           :success :dim)
       (if (config-resource-item-enabled-p item)
           "[x]" "[ ]"))))

(defun config-selector-render-entry
    (state entry index width)
  (case (getf entry :kind)
    (:group
     (let* ((inherited-p
              (and
               (eq :project
                   (config-selector-state-write-scope state))
               (eq :user (getf entry :scope))))
            (label
              (concatenate
               'string
               (getf entry :label)
               (if inherited-p
                   " · inherited global" ""))))
       (config-selector-fit-line
        (concatenate
         'string "  "
         (cadr-tui:theme-bold
          (cadr-tui:theme-foreground
           (if inherited-p :dim :accent) label)))
        width)))
    (:subgroup
     (let ((inherited-p
             (and
              (eq :project
                  (config-selector-state-write-scope state))
              (eq :user (getf entry :scope)))))
       (config-selector-fit-line
        (concatenate
         'string "    "
         (cadr-tui:theme-foreground
          (if inherited-p :dim :muted)
          (getf entry :label)))
        width)))
    (:item
     (let* ((item (getf entry :item))
            (selected-p
              (= index
                 (config-selector-state-selected state)))
            (dimmed-p
              (and
               (eq :project
                   (config-selector-state-write-scope state))
               (eq :user (config-resource-item-scope item))
               (eq :inherit
                   (config-selector-project-state state item))))
            (name
              (if selected-p
                  (cadr-tui:theme-bold
                   (config-resource-item-display-name item))
                  (config-resource-item-display-name item)))
            (name
              (if dimmed-p
                  (cadr-tui:theme-foreground :dim name)
                  name)))
       (config-selector-fit-line
        (concatenate
         'string
         (if selected-p "> " "  ")
         "    "
         (config-selector-checkbox state item)
         " " name
         (config-selector-override-suffix state item))
        width "...")))))

(defun config-selector-visible-range (state)
  (let* ((count
           (length (config-selector-state-flat-items state)))
         (maximum (config-selector-state-max-visible state))
         (selected (config-selector-state-selected state))
         (start
           (max
            0
            (min
             (- selected (floor maximum 2))
             (- count maximum))))
         (end (min count (+ start maximum))))
    (values start end count)))

(defun config-selector-item-ordinal (state)
  (1+
   (count
    :item
    (subseq
     (config-selector-state-flat-items state)
     0 (config-selector-state-selected state))
    :key (lambda (entry) (getf entry :kind)))))

(defun render-config-selector-state (state width)
  (let* ((border
         (cadr-tui:theme-foreground
            :border
            (make-string
             (max 0 width) :initial-element #\─)))
         (header (config-selector-header-lines state width))
         (input
           (cadr-tui:make-single-line-input
            :value (config-selector-state-query state)
            :prompt "> "))
         (input-lines nil)
         (input-row 0)
         (input-column 0))
    (multiple-value-setq
        (input-lines input-row input-column)
      (cadr-tui:render-single-line-input input width))
    (multiple-value-bind (start end count)
        (config-selector-visible-range state)
      (let ((viewport
              (if (zerop count)
                  (list
                   (cadr-tui:theme-foreground
                    :muted "  No resources found"))
                  (loop
                    for index from start below end
                    collect
                    (config-selector-render-entry
                     state
                     (nth index
                          (config-selector-state-flat-items state))
                     index width)))))
        (when (and (plusp count)
                   (or (plusp start) (< end count)))
          (setf
           viewport
           (append
            viewport
            (list
             (cadr-tui:theme-foreground
              :dim
              (format
               nil "  (~D/~D)"
               (config-selector-item-ordinal state)
               (count
                :item
                (config-selector-state-flat-items state)
                :key (lambda (entry) (getf entry :kind)))))))))
        (values
         (append
          (list "" border "") header
          (list "") input-lines (list "")
          viewport (list "" border))
         (+ 6 input-row)
         input-column)))))

(defun run-config-selector
    (settings-manager cwd agent-directory output
     &key (write-scope :global)
       (project-mode-available-p t))
  (let* ((terminal
           (cadr-tui:make-process-terminal
            :input *standard-input* :output output))
         (renderer
           (cadr-tui:make-terminal-renderer
            terminal :alt-p nil :mouse-p nil))
         (decoder (cadr-tui:make-input-decoder))
         (state
           (make-config-selector-state
            settings-manager cwd agent-directory
            (cadr-tui:terminal-rows terminal)
            :write-scope write-scope
            :project-mode-available-p
            project-mode-available-p))
         (done-p nil))
    (labels
        ((render ()
           (multiple-value-bind (lines row column)
               (render-config-selector-state
                state (cadr-tui:terminal-columns terminal))
             (cadr-tui:render-frame
              renderer lines
              :cursor-row row :cursor-column column)))
         (handle-event (event)
           (case (cadr-tui:input-event-kind event)
             ((:escape :cancel :interrupt)
              (setf done-p t))
             (otherwise
              (config-selector-handle-event state event)))))
      (cadr-tui:call-with-terminal
       terminal
       (lambda ()
         (render)
         (loop until done-p
               do
               (when (cadr-tui:terminal-resized-p terminal)
                 (setf
                  (config-selector-state-max-visible state)
                  (max
                   5
                   (- (cadr-tui:terminal-rows terminal) 8)))
                 (cadr-tui:invalidate-renderer renderer))
               (let ((input
                       (cadr-tui:terminal-read-input terminal)))
                 (dolist
                     (event
                      (if (plusp (length input))
                          (cadr-tui:feed-input decoder input)
                          (cadr-tui:flush-input decoder)))
                   (handle-event event)))
               (render)
               (sleep 0.005d0)))
       :before-start
       (lambda () (cadr-tui:renderer-start renderer))
       :before-stop
       (lambda () (cadr-tui:renderer-before-stop renderer))
       :after-stop
       (lambda () (cadr-tui:renderer-after-stop renderer))))
  nil))

(defun package-root-has-resources-p (root)
  (let ((directory
          (uiop:ensure-directory-pathname
           root)))
    (or
     (probe-file
      (merge-pathnames
       "extension.lisp" directory))
     (some
      (lambda (name)
        (uiop:directory-exists-p
         (merge-pathnames name directory)))
      '("skills/" "prompts/" "themes/")))))

(defun install-git-package
    (source install-root
     &key
       (runner #'default-git-clone-runner))
  (let* ((destination
           (package-git-install-path
            source install-root))
         (staging
           (make-extension-staging-directory
            (uiop:pathname-directory-pathname
             destination)))
         (repo
           (package-source-repo source))
         (ref
           (package-source-ref source)))
    (ensure-directories-exist
     (merge-pathnames
      "anchor"
      (uiop:pathname-directory-pathname
       destination)))
    (when (probe-file destination)
      (error
       'cadr-ai:configuration-error
       :message
       (format nil
               "Package destination already exists: ~A"
               (namestring destination))))
    (unwind-protect
         (progn
           (funcall
            runner
            (append
             (list "git" "clone")
             (when ref
               (list "--branch" ref
                     "--single-branch"))
             (list "--" repo
                   (namestring staging))))
           (unless
               (package-root-has-resources-p
                staging)
             (error
              'cadr-ai:configuration-error
              :message
              "Installed package has no Lisp extension, skill, prompt, or theme resources"))
           (rename-file staging destination)
           (setf staging nil)
           destination)
      (when (and staging
                 (probe-file staging))
        (uiop:delete-directory-tree
         staging
         :validate t
         :if-does-not-exist
         :ignore)))))

(defun package-record-install-path
    (record global-install-root
     project-install-root)
  (or
   (getf record :path)
   (let ((parsed
           (getf record :parsed)))
     (when (eq :git
               (package-source-type parsed))
       (package-git-install-path
        parsed
        (if (eq :project
                (getf record :scope))
            project-install-root
            global-install-root))))))

(defun package-update-check-group-path ()
  (merge-pathnames
   (format nil "cadr-package-update-~D-~D.pgid"
           (get-universal-time)
           (random most-positive-fixnum))
   (uiop:temporary-directory)))

(defun package-update-check-process-argv
    (argv group-path)
  (if (or (uiop:os-windows-p)
          (not (probe-file "/usr/bin/setsid")))
      argv
      (append
       (list
        "/usr/bin/setsid" "--fork" "--wait"
        "/bin/sh" "-c"
        "group_path=$1; shift; printf '%s' \"$$\" > \"$group_path\"; exec \"$@\""
        "cadr-package-update-check"
        (namestring group-path))
       argv)))

(defun package-update-check-environment ()
  (let ((prompt-prefix "GIT_TERMINAL_PROMPT="))
    (cons
     "GIT_TERMINAL_PROMPT=0"
     (remove-if
      (lambda (entry)
        (uiop:string-prefix-p prompt-prefix entry))
      #+sbcl (sb-ext:posix-environ)
      #-sbcl nil))))

(defun stop-package-update-check-process
    (process group-path)
  (when process
    (let* ((group-id
             (and group-path
                  (probe-file group-path)
                  (ignore-errors
                    (parse-integer
                     (uiop:read-file-string group-path)
                     :junk-allowed t))))
           (pid
             (ignore-errors
               (uiop:process-info-pid process))))
      (if pid
          (kill-process-tree (or group-id pid))
          (ignore-errors
            (uiop:terminate-process process :urgent t))))
    (ignore-errors
      (uiop:wait-process process)))
  nil)

(defun default-package-update-check-runner
    (argv
     &key
       (timeout-seconds 10)
       (clock #'get-internal-real-time))
  (let* ((group-path
           (and (not (uiop:os-windows-p))
                (probe-file "/usr/bin/setsid")
                (package-update-check-group-path)))
         (process
           (uiop:launch-program
            (package-update-check-process-argv
             argv group-path)
            :environment
            (package-update-check-environment)
            :output :stream
            ;; UIOP defines NIL as the platform null device. Keep git and
            ;; transport diagnostics out of every user-visible stream.
            :error-output nil))
         (output-stream
           (uiop:process-info-output process))
         (deadline
           (+ (funcall clock)
              (* timeout-seconds
                 internal-time-units-per-second)))
         (completed-p nil))
    (unwind-protect
         (progn
           (loop while (uiop:process-alive-p process)
                 do
                 (when (>= (funcall clock)
                           deadline)
                   (stop-package-update-check-process
                    process group-path)
                   (error "Package update check timed out"))
                 (sleep 0.01d0))
           (let ((output
                   (with-output-to-string (stream)
                     (loop for line =
                             (read-line output-stream nil nil)
                           while line
                           do (write-line line stream))))
                 (status (uiop:wait-process process)))
             (setf completed-p t)
             (unless (zerop (or status 1))
               (error "Package update check command failed"))
             output))
      (when (and (not completed-p)
                 (ignore-errors
                   (uiop:process-alive-p process)))
        (stop-package-update-check-process
         process group-path))
      (when output-stream
        (ignore-errors
          (close output-stream)))
      (when (and group-path
                 (probe-file group-path))
        (ignore-errors
          (delete-file group-path))))))

(defun package-update-git-output
    (runner path &rest arguments)
  (funcall
   runner
   (append
    (list "git" "-C" (namestring path))
    arguments)))

(defun package-update-remote-ref (runner path)
  (let ((upstream
          (ignore-errors
            (string-trim
             '(#\Space #\Tab #\Newline #\Return)
             (package-update-git-output
              runner path
              "rev-parse" "--abbrev-ref"
              "@{upstream}")))))
    (if (and upstream
             (uiop:string-prefix-p
              "origin/" upstream)
             (> (length upstream)
                (length "origin/")))
        (format nil "refs/heads/~A"
                (subseq upstream
                        (length "origin/")))
        nil)))

(defun package-update-git-object-id (output)
  (let* ((trimmed
           (string-trim
            '(#\Space #\Tab #\Newline #\Return)
            output))
         (end
           (or (position-if
                (lambda (character)
                  (member character
                          '(#\Space #\Tab #\Newline #\Return)))
                trimmed)
               (length trimmed)))
         (object-id (subseq trimmed 0 end)))
    (and (= 40 (length object-id))
         (every
          (lambda (character)
            (digit-char-p character 16))
          object-id)
         (string-downcase object-id))))

(defun package-git-update-available-p
    (record runner)
  (let* ((path (getf record :path))
         (local
           (package-update-git-object-id
            (package-update-git-output
             runner path "rev-parse" "HEAD")))
         (remote-ref
           (package-update-remote-ref runner path))
         (remote
           (or
            (and
             remote-ref
             (package-update-git-object-id
              (package-update-git-output
               runner path
               "ls-remote" "origin" remote-ref)))
            ;; Match Pi's Git update contract: an unavailable, empty, or
            ;; malformed upstream ref falls back to the remote default branch.
            (package-update-git-object-id
             (package-update-git-output
              runner path
              "ls-remote" "origin" "HEAD")))))
    (and local remote
         (not (string= local remote)))))

(defun package-update-records-project-first (records)
  (append
   (remove-if-not
    (lambda (record)
      (eq :project (getf record :scope)))
    records)
   (remove-if
    (lambda (record)
      (eq :project (getf record :scope)))
    records)))

(defun package-update-candidate-record-p (record)
  (let ((source (getf record :parsed))
        (path (getf record :path)))
    (and
     (typep source 'package-source)
     (eq :git (package-source-type source))
     (not (package-source-pinned-p source))
     path
     (probe-file path))))

(defun package-update-record-result (record runner)
  (handler-case
      (when (package-git-update-available-p
             record runner)
        (let ((source (getf record :parsed)))
          (format nil "~A/~A"
                  (package-source-host source)
                  (package-source-path source))))
    (condition () nil)))

(defun run-package-update-checks
    (records runner max-concurrency)
  (let* ((items (coerce records 'vector))
         (count (length items)))
    (when (zerop count)
      (return-from run-package-update-checks nil))
    (let ((results (make-array count :initial-element nil))
          (next-index 0)
          (lock
            (sb-thread:make-mutex
             :name "cadr package update scheduler")))
      (labels
          ((claim-index ()
             (sb-thread:with-mutex (lock)
               (when (< next-index count)
                 (prog1 next-index
                   (incf next-index)))))
           (worker ()
             (loop for index = (claim-index)
                   while index
                   do
                   (setf
                    (aref results index)
                    (package-update-record-result
                     (aref items index) runner)))))
        (let ((threads nil)
              (completed-p nil))
          (unwind-protect
               (progn
                 (setf
                  threads
                  (loop
                    repeat
                    (min count
                         (max 1 max-concurrency))
                    collect
                    (sb-thread:make-thread
                     #'worker
                     :name "cadr package update check")))
                 (dolist (thread threads)
                   (cadr-core:join-active-thread
                    thread
                    :reason
                    "Package update results require every bounded worker to finish"))
                 (setf completed-p t)
                 (loop for result across results
                       when result collect result))
            ;; The TUI owns only the outer update-check thread.  If cleanup
            ;; terminates that owner, unwind its lexically owned workers too;
            ;; otherwise their git subprocesses can outlive the session.
            (unless completed-p
              (dolist (thread threads)
                (cadr-core:stop-thread-for-cleanup
                 thread)))))))))

(defun check-for-available-package-updates
    (records
     &key
       (runner #'default-package-update-check-runner)
       (offline-p (offline-mode-p))
       (max-concurrency 4))
  (when offline-p
    (return-from
        check-for-available-package-updates nil))
  (run-package-update-checks
   (remove-if-not
    #'package-update-candidate-record-p
    (package-update-records-project-first records))
   runner max-concurrency))

(defun print-configured-packages
    (records &optional
               (stream *standard-output*))
  (if (null records)
      (format stream "No packages installed.~%")
      (dolist (scope '(:global :project))
        (let ((selected
                (remove scope records
                        :test-not #'eq
                        :key
                        (lambda (record)
                          (getf record :scope)))))
          (when selected
            (format stream "~:(~A~) packages:~%"
                    scope)
            (dolist (record selected)
              (format stream "  ~A~%"
                      (getf record :source)))))))
  (finish-output stream))

(defun handle-package-command
    (arguments
     &key
       (cwd (uiop:getcwd))
       (agent-directory
         (default-agent-directory))
       (output *standard-output*)
       (error-output *error-output*)
       (offline-p nil)
       (runner #'default-git-clone-runner))
  (let ((options
          (parse-package-command arguments)))
    (unless options
      (return-from handle-package-command
        (values nil nil)))
    (when
        (package-command-options-help-p
         options)
      (print-package-command-help
       (package-command-options-command
        options)
       output)
      (return-from handle-package-command
        (values t 0)))
    (let* ((cwd
             (uiop:ensure-directory-pathname
              cwd))
           (agent
             (uiop:ensure-directory-pathname
              agent-directory))
           (project-config
             (merge-pathnames ".cadr/" cwd))
           (global-settings
             (merge-pathnames
              "settings.json" agent))
           (project-settings
             (merge-pathnames
              "settings.json" project-config))
           (trust-store
             (make-project-trust-store
              (merge-pathnames
               "trust.json" agent)))
           (trusted-p
             (resolve-project-trusted
              trust-store cwd
              :override
              (package-command-options-project-trust-override
               options)
              :override-supplied-p
              (package-command-options-project-trust-override-supplied-p
               options)
              :default :ask
              :has-ui-p nil))
           (settings
             (make-settings-manager
              :global-path global-settings
              :project-path project-settings
              :project-trusted-p trusted-p))
           (records
             (configured-package-records
              settings
              :global-base agent
              :project-base project-config))
           (command
             (package-command-options-command
              options))
           (scope
             (if
                 (package-command-options-local-p
                  options)
                 :project :global))
           (base
             (if (eq scope :project)
                 project-config agent))
           (global-install-root
             (merge-pathnames
              "packages/" agent))
           (project-install-root
             (merge-pathnames
              "packages/" project-config))
           (offline-p
             (or
              offline-p
              (package-command-options-offline-p
               options))))
      (when
          (and
           (eq scope :project)
           (member command '(:install :remove))
           (not trusted-p))
        (error
         'cadr-ai:configuration-error
         :message
         "Project is not trusted. Use --approve to modify local package config."))
      (ecase command
        (:install
         (let* ((source-text
                  (package-command-options-source
                   options))
                (source
                  (parse-package-source
                   source-text)))
           (case
             (package-source-type source)
             (:npm
              (error
               'cadr-ai:configuration-error
               :message
               "npm packages are unavailable in the Common Lisp build; install a Lisp local or Git package"))
             (:local
              (let ((path
                      (uiop:ensure-absolute-pathname
                       (merge-pathnames
                        (pathname
                         (package-source-path
                          source))
                        cwd))))
                (unless
                    (package-root-has-resources-p
                     path)
                  (error
                   'cadr-ai:configuration-error
                   :message
                   "Local package has no Lisp extension, skill, prompt, or theme resources"))))
             (:git
              (when offline-p
                (error
                 'cadr-ai:configuration-error
                 :message
                 "Cannot install a missing Git package while offline"))
              (install-git-package
               source
               (if (eq scope :project)
                   project-install-root
                   global-install-root)
               :runner runner)))
           (persist-package-source
            settings
            (package-command-source-value
             source-text cwd)
            :scope scope
            :base-directory base)
           (format output "Installed ~A~%"
                   source-text)
           (values t 0)))
        (:remove
         (let* ((source
                  (package-command-options-source
                   options))
                (stored-source
                  (package-command-source-value
                   source cwd)))
           (if
               (remove-package-source
                settings stored-source
                :scope scope
                :base-directory base)
               (progn
                 (let ((parsed
                         (parse-package-source
                          source)))
                   (when (eq :git
                             (package-source-type
                              parsed))
                     (let ((path
                             (package-git-install-path
                              parsed
                              (if (eq scope :project)
                                  project-install-root
                                  global-install-root))))
                       (when (probe-file path)
                         (uiop:delete-directory-tree
                          path
                          :validate t
                          :if-does-not-exist
                          :ignore)))))
                 (format output "Removed ~A~%"
                         source)
                 (values t 0))
               (progn
                 (format error-output
                         "No matching package found for ~A~%"
                         source)
                 (values t 1)))))
        (:list
         (print-configured-packages
          records output)
         (values t 0))
        (:config
         (run-config-selector
          settings cwd agent output
          :write-scope scope
          :project-mode-available-p trusted-p)
         (values t 0))
        (:update
         (let ((target
                 (package-command-options-update-target
                  options)))
           (case (first target)
             (:models
              (format output
                      "Model catalogs are bundled with this cadr build.~%"))
             (:self
              (format output
                      "Update cadr through the Common Lisp build/install method.~%"))
             ((:extensions :all)
              (unless offline-p
                (let ((wanted
                        (second target)))
                  (dolist (record records)
                    (when
                        (and
                         (eq :git
                             (package-source-type
                              (getf record
                                    :parsed)))
                         (or
                          (null wanted)
                          (equal
                           (package-source-identity
                            wanted cwd)
                           (package-source-identity
                            (getf record :source)
                            (getf record :base))))
                         (not
                          (package-source-pinned-p
                           (getf record
                                 :parsed))))
                      (let ((path
                              (package-record-install-path
                               record
                               global-install-root
                               project-install-root)))
                        (when (probe-file path)
                          (funcall
                           runner
                           (list
                            "git" "-C"
                            (namestring path)
                            "pull" "--ff-only")))))))))
              (format output
                      "Updated packages~%")))
           (values t 0))))))
