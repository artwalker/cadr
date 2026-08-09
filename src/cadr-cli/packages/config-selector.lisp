(in-package #:cadr-cli)

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
           (cadr-core:project-config-directory cwd))
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
                 (cadr-core:project-config-directory cwd)
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
        (t (format nil "Project (~A)" cadr-core:+project-config-directory-name+)))))

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
           (cadr-core:project-config-directory (config-selector-state-cwd state)))
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
           (cadr-core:project-config-directory (config-selector-state-cwd state)))
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
     (cadr-core:project-config-directory (config-selector-state-cwd state)))))

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
               (format nil "~Asettings.json · inherited global resources are dimmed" cadr-core:+project-config-directory-name+)
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
              ;; Baseline config-selector.ts: bold only when the row is
              ;; selected and not dimmed; dimmed inherited rows stay
              ;; uniformly dim.
              (if (and selected-p (not dimmed-p))
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
