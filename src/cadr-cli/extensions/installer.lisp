(in-package #:cadr-cli)

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
