(in-package #:cadr-cli)

(defstruct package-source
  (type :local :type symbol)
  spec
  name
  version
  repo
  host
  path
  ref
  (pinned-p nil :type boolean))

(defun exact-package-version-p (version)
  (and version
       (cl-ppcre:scan
        "^\\d+\\.\\d+\\.\\d+(?:-[0-9A-Za-z.-]+)?$"
        version)))

(defun parse-npm-package-spec (spec)
  (let* ((start
           (if (and (plusp (length spec))
                    (char= (char spec 0) #\@))
               (1+
                (or (position #\/ spec)
                    (length spec)))
               0))
         (separator
           (position #\@ spec :start start))
         (name
           (if separator
               (subseq spec 0 separator)
               spec))
         (version
           (and separator
                (subseq spec (1+ separator)))))
    (values name version)))

(defun strip-package-git-ref (source)
  (let* ((scp-p
           (cl-ppcre:scan "^git@[^:]+:" source))
         (path-start
           (cond
             (scp-p
              (1+ (position #\: source)))
             ((search "://" source)
              (let ((authority
                      (+ (search "://" source) 3)))
                (or
                 (position #\/ source
                           :start authority)
                 (length source))))
             (t
              (or (position #\/ source)
                  (length source)))))
         (separator
           (position #\@ source
                     :start path-start)))
    (if (and separator
             (< (1+ separator)
                (length source)))
        (values
         (subseq source 0 separator)
         (subseq source (1+ separator)))
        (values source nil))))

(defun parse-package-git-location (source)
  (multiple-value-bind (repo ref)
      (strip-package-git-ref source)
    (let ((host nil)
          (path nil)
          (clone-repo repo))
      (cond
        ((cl-ppcre:scan "^git@[^:]+:" repo)
         (let ((at (position #\@ repo))
               (colon (position #\: repo)))
           (setf host
                 (subseq repo (1+ at) colon)
                 path
                 (subseq repo (1+ colon)))))
        ((search "://" repo)
         (let* ((scheme-end
                  (+ (search "://" repo) 3))
                (slash
                  (position #\/ repo
                            :start scheme-end))
                (authority
                  (and slash
                       (subseq repo
                               scheme-end slash)))
                (at
                  (and authority
                       (position #\@ authority
                                 :from-end t))))
           (setf host
                 (and authority
                      (subseq authority
                              (if at (1+ at) 0)))
                 path
                 (and slash
                      (subseq repo (1+ slash))))))
        (t
         (let ((slash (position #\/ repo)))
           (when slash
             (setf host (subseq repo 0 slash)
                   path (subseq repo (1+ slash))
                   clone-repo
                   (format nil "https://~A"
                           repo))))))
      (when path
        (setf path
              (string-right-trim
               "/"
               (if
                   (uiop:string-suffix-p
                    path ".git")
                   (subseq path
                           0 (- (length path) 4))
                   path))))
      (when
          (or
           (null host)
           (null path)
           (< (count #\/ path) 1)
           (unsafe-git-source-p path)
           (find #\/ host)
           (search ".." host))
        (return-from
            parse-package-git-location nil))
      (make-package-source
       :type :git
       :repo clone-repo
       :host (string-downcase host)
       :path path
       :ref ref
       :pinned-p (not (null ref))))))

(defun explicit-package-git-url-p (source)
  (some
   (lambda (prefix)
     (string-prefix-p prefix source))
   '("https://" "http://" "ssh://"
     "git://")))

(defun parse-package-source (source)
  (let ((trimmed
          (string-trim
           '(#\Space #\Tab #\Newline #\Return)
           source)))
    (cond
      ((string-prefix-p "npm:" trimmed)
       (let ((spec
               (string-trim
                '(#\Space #\Tab)
                (subseq trimmed 4))))
         (multiple-value-bind (name version)
             (parse-npm-package-spec spec)
           (make-package-source
            :type :npm
            :spec spec
            :name name
            :version version
            :pinned-p
            (not
             (null
              (exact-package-version-p
               version)))))))
      ((string-prefix-p "git:" trimmed)
       (or
        (parse-package-git-location
         (string-trim
          '(#\Space #\Tab)
          (subseq trimmed 4)))
        (make-package-source
         :type :local :path trimmed)))
      ((explicit-package-git-url-p trimmed)
       (or
        (parse-package-git-location trimmed)
        (make-package-source
         :type :local :path trimmed)))
      (t
       (make-package-source
        :type :local :path trimmed)))))

(defun package-source-identity
    (source &optional base-directory)
  (let ((parsed
          (etypecase source
            (string
             (parse-package-source source))
            (package-source source))))
    (case (package-source-type parsed)
      (:npm
       (format nil "npm:~A"
               (package-source-name parsed)))
      (:git
       (format nil "git:~A/~A"
               (package-source-host parsed)
               (package-source-path parsed)))
      (:local
       (format
        nil "local:~A"
        (canonical-file-name
         (merge-pathnames
          (pathname
           (package-source-path parsed))
          (uiop:ensure-directory-pathname
           (or base-directory
               (uiop:getcwd))))))))))

(defun ensure-package-path-inside-root
    (root relative)
  (let* ((relative-path (pathname relative))
         (relative-directory
           (pathname-directory relative-path))
         (directory
           (uiop:ensure-directory-pathname root))
         (candidate
           (merge-pathnames
            (uiop:ensure-directory-pathname relative)
            directory))
         (root-name
           (namestring
            (uiop:ensure-absolute-pathname
             directory)))
         (candidate-name
           (namestring
            (uiop:ensure-absolute-pathname
             candidate))))
    (when
        (or
         (uiop:absolute-pathname-p relative-path)
         (member :up relative-directory))
      (error
       'cadr-ai:configuration-error
       :message
       "Package path resolves outside package install root"))
    (unless
        (uiop:string-prefix-p
         root-name candidate-name)
      (error
       'cadr-ai:configuration-error
       :message
       "Package path resolves outside package install root"))
    candidate))

(defun package-git-install-path
    (source root)
  (unless (eq :git
              (package-source-type source))
    (error "Not a git package source"))
  (ensure-package-path-inside-root
   root
   (format nil "~A/~A/"
           (package-source-host source)
           (package-source-path source))))

(defun package-npm-install-argv
    (sources install-root
     &key npm-command
       package-manager)
  (let* ((prefix
           (or npm-command '("npm")))
         (manager
           (string-downcase
            (or package-manager
                (pathname-name
                 (pathname
                  (first prefix)))
                "npm"))))
    (append
     prefix
     (cond
       ((string= manager "bun")
        (append
         (list "install")
         sources
         (list "--cwd"
               (namestring
                (uiop:ensure-directory-pathname
                 install-root))
               "--omit=peer")))
       ((string= manager "pnpm")
        (append
         (list "install")
         sources
         (list "--dir"
               (namestring
                (uiop:ensure-directory-pathname
                 install-root))
               "--strict-peer-dependencies=false")))
       (t
        (append
         (list
          "install"
          "--prefix"
          (namestring
           (uiop:ensure-directory-pathname
            install-root))
          "--no-save"
          "--legacy-peer-deps")
         sources))))))

(defun package-source-with-ref (source)
  (if (package-source-ref source)
      (format nil "~A@~A"
              (package-source-repo source)
              (package-source-ref source))
      (package-source-repo source)))

(defun dedupe-package-sources
    (user-sources project-sources
     &key user-base project-base)
  (let ((result nil)
        (seen (make-hash-table :test #'equal)))
    (dolist (entry
             (append
              (mapcar
               (lambda (source)
                 (list source :user user-base))
               user-sources)
              (mapcar
               (lambda (source)
                 (list source :project project-base))
               project-sources)))
      (destructuring-bind
          (source scope base)
          entry
        (let ((identity
                (package-source-identity
                 source base)))
          (multiple-value-bind (index found-p)
              (gethash identity seen)
            (if found-p
                (when (eq scope :project)
                  (setf (nth index result)
                        (cons scope source)))
                (progn
                  (setf
                   (gethash identity seen)
                   (length result))
                  (setf result
                        (append
                         result
                         (list
                          (cons scope
                                source))))))))))
    result))
