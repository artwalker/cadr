(in-package #:cadr-cli)

(defun format-cwd-for-footer (cwd home)
  (let* ((normalized-home
           (string-right-trim "/" home))
         (normalized-cwd
           (string-right-trim "/" cwd)))
    (cond
      ((string= normalized-cwd
                normalized-home)
       "~")
      ((and
        (uiop:string-prefix-p
         normalized-home normalized-cwd)
        (> (length normalized-cwd)
           (length normalized-home))
        (char=
         (char normalized-cwd
               (length normalized-home))
         #\/))
       (concatenate
        'string "~"
        (subseq normalized-cwd
                (length normalized-home))))
      (t (display-directory-name cwd)))))

(defun fit-footer-text (text width)
  (cadr-tui:truncate-to-width text width))

(defun usage-value (usage key)
  (or (getf usage key) 0))

(defun footer-usage-summary
    (usages &key provider)
  (let ((input 0)
        (output 0)
        (cache-read 0)
        (cache-write 0)
        (cost 0d0))
    (dolist (usage usages)
      (incf input (usage-value usage :input))
      (incf output (usage-value usage :output))
      (incf cache-read
            (usage-value usage :cache-read))
      (incf cache-write
            (usage-value usage :cache-write))
      (incf cost
            (coerce
             (usage-value usage :cost)
             'double-float)))
    (let* ((cache-total
             (+ input cache-read cache-write))
           (hit-rate
             (and (plusp (+ cache-read cache-write))
                  (* 100d0
                     (/ cache-read
                        (max 1 cache-total))))))
      (format
       nil
       "in:~D out:~D~@[ CH~,1F%~] $~,3F~:[~; (sub)~]"
       input output hit-rate cost
       (string-equal
        (or provider "")
        "kimi-coding")))))

(defstruct git-footer-paths
  repo-directory
  common-git-directory
  head-path)

(defun parent-directory-pathname (directory)
  (let* ((normalized
           (uiop:ensure-directory-pathname
            directory))
         (parts
           (pathname-directory normalized)))
    (when (> (length parts) 1)
      (make-pathname
       :directory (butlast parts)
       :defaults normalized))))

(defun find-git-footer-paths (cwd)
  (loop
    with directory =
    (uiop:ensure-directory-pathname
     (uiop:ensure-absolute-pathname cwd))
    for git-path =
    (merge-pathnames ".git" directory)
    do
    (when (probe-file git-path)
      (handler-case
          (if (uiop:directory-pathname-p
               (truename git-path))
              (let* ((git-directory
                       (uiop:ensure-directory-pathname
                        (truename git-path)))
                     (head
                       (merge-pathnames
                        "HEAD" git-directory)))
                (when (probe-file head)
                  (return
                    (make-git-footer-paths
                     :repo-directory directory
                     :common-git-directory
                     git-directory
                     :head-path head))))
              (let* ((content
                       (string-trim
                        '(#\Space #\Tab
                          #\Newline #\Return)
                        (uiop:read-file-string
                         git-path
                         :external-format
                         :utf-8)))
                     (prefix "gitdir: "))
                (when
                    (uiop:string-prefix-p
                     prefix content)
                  (let* ((git-directory
                           (uiop:ensure-directory-pathname
                            (uiop:ensure-absolute-pathname
                             (subseq
                              content
                              (length prefix))
                             directory)))
                         (head
                           (merge-pathnames
                            "HEAD"
                            git-directory))
                         (common-file
                           (merge-pathnames
                            "commondir"
                            git-directory))
                         (common-directory
                           (if
                               (probe-file
                                common-file)
                               (uiop:ensure-directory-pathname
                                (uiop:ensure-absolute-pathname
                                 (string-trim
                                  '(#\Space #\Tab
                                    #\Newline #\Return)
                                  (uiop:read-file-string
                                   common-file
                                   :external-format
                                   :utf-8))
                                 git-directory))
                               git-directory)))
                    (when (probe-file head)
                      (return
                        (make-git-footer-paths
                         :repo-directory directory
                         :common-git-directory
                         common-directory
                         :head-path head)))))))
        (condition ()
          (return nil))))
    (let ((parent
            (parent-directory-pathname
             directory)))
      (unless parent
        (return nil))
      (setf directory parent))))

(defun run-git-symbolic-branch (repo-directory)
  (handler-case
      (let ((output
              (uiop:run-program
               '("git"
                 "--no-optional-locks"
                 "symbolic-ref"
                 "--quiet"
                 "--short"
                 "HEAD")
               :directory repo-directory
               :output :string
               :error-output nil
               :ignore-error-status t)))
        (let ((branch
                (string-trim
                 '(#\Space #\Tab
                   #\Newline #\Return)
                 (or output ""))))
          (and
           (plusp (length branch))
           branch)))
    (condition () nil)))

(defparameter *git-symbolic-branch-function*
  #'run-git-symbolic-branch)

(defun git-symbolic-branch (repo-directory)
  (funcall *git-symbolic-branch-function*
           repo-directory))

(defun resolve-git-footer-branch (paths)
  (handler-case
      (let* ((content
               (string-trim
                '(#\Space #\Tab
                  #\Newline #\Return)
                (uiop:read-file-string
                 (git-footer-paths-head-path
                  paths)
                 :external-format :utf-8)))
             (prefix "ref: refs/heads/"))
        (cond
          ((uiop:string-prefix-p
            prefix content)
           (let ((branch
                   (subseq
                    content
                    (length prefix))))
             (if (string= branch ".invalid")
                 (or
                  (git-symbolic-branch
                   (git-footer-paths-repo-directory
                    paths))
                  "detached")
                 branch)))
          (t "detached")))
    (condition () :unavailable)))

(defstruct (footer-data-provider
            (:constructor
                %make-footer-data-provider))
  cwd
  git-paths
  (cached-branch :uninitialized)
  (observed-source-signature :uninitialized)
  (pending-source-signature :none)
  (pending-source-since 0
                        :type integer)
  (%statuses nil :type list)
  (available-provider-count 0
                            :type (integer 0 *))
  (callbacks nil :type list)
  (poll-seconds 0.5d0
                :type real)
  (debounce-seconds 0.5d0
                    :type real)
  (clock-function #'get-internal-real-time
                  :type function)
  stop-semaphore
  thread
  (lock
    (sb-thread:make-mutex
     :name "cadr footer data"))
  (disposed-p nil :type boolean))

(defun binary-file-signature (path)
  (when (probe-file path)
    (with-open-file
        (input path
               :direction :input
               :element-type '(unsigned-byte 8))
      (let ((checksum 0)
            (length 0))
        (loop for byte = (read-byte input nil :eof)
              until (eq byte :eof)
              do
              (setf checksum
                    (logand
                     #xffffffff
                     (+ (* checksum 33)
                        byte)))
              (incf length))
        (list
         (file-write-date path)
         length checksum)))))

(defun footer-source-signature (paths)
  (handler-case
      (let* ((head-path
               (git-footer-paths-head-path paths))
             (head
               (string-trim
                '(#\Space #\Tab
                  #\Newline #\Return)
                (uiop:read-file-string
                 head-path
                 :external-format :utf-8)))
             (reftable-directory
               (merge-pathnames
                "reftable/"
                (git-footer-paths-common-git-directory
                 paths))))
        (list
         head
         (when
             (and
              (string=
               head "ref: refs/heads/.invalid")
              (uiop:directory-exists-p
               reftable-directory))
           (loop
             for path in
             (sort
              (copy-list
               (uiop:directory-files
                reftable-directory))
              #'string<
              :key #'namestring)
             collect
             (list
              (file-namestring path)
              (binary-file-signature
               path))))))
    (condition () :unavailable)))

(defun refresh-footer-data-provider (provider)
  (let* ((paths
           (footer-data-provider-git-paths
            provider))
         (resolved
           (and paths
                (resolve-git-footer-branch
                 paths))))
    (unless (eq resolved :unavailable)
      (let ((callbacks nil))
        (sb-thread:with-mutex
            ((footer-data-provider-lock
              provider))
          (let ((previous
                  (footer-data-provider-cached-branch
                   provider)))
            (setf
             (footer-data-provider-cached-branch
              provider)
             resolved)
            (when
                (and
                 (not
                  (eq previous :uninitialized))
                 (not (equal previous resolved)))
              (setf callbacks
                    (copy-list
                     (footer-data-provider-callbacks
                      provider))))))
        (dolist (callback callbacks)
          (funcall callback)))))
  provider)

(defun footer-debounce-elapsed-p (provider)
  (>=
   (-
    (funcall
     (footer-data-provider-clock-function provider))
    (footer-data-provider-pending-source-since
     provider))
   (round
    (*
     (footer-data-provider-debounce-seconds
      provider)
     internal-time-units-per-second))))

(defun poll-footer-data-provider (provider)
  (let* ((paths
           (footer-data-provider-git-paths
            provider))
         (signature
           (and paths
                (footer-source-signature
                 paths))))
    (unless (eq signature :unavailable)
      (cond
        ((equal
          signature
          (footer-data-provider-observed-source-signature
           provider))
         (setf
          (footer-data-provider-pending-source-signature
           provider)
          :none))
        ((not
          (equal
           signature
           (footer-data-provider-pending-source-signature
            provider)))
         (setf
          (footer-data-provider-pending-source-signature
           provider)
          signature
          (footer-data-provider-pending-source-since
           provider)
          (funcall
           (footer-data-provider-clock-function provider))))
        ((footer-debounce-elapsed-p provider)
         (refresh-footer-data-provider
          provider)
         (setf
          (footer-data-provider-observed-source-signature
           provider)
          signature
          (footer-data-provider-pending-source-signature
           provider)
          :none)))))
  provider)

(defun make-footer-data-provider
    (cwd &key
           (poll-seconds 0.5d0)
           (debounce-seconds 0.5d0)
           (clock-function #'get-internal-real-time))
  (let* ((provider
           (%make-footer-data-provider
            :cwd
            (uiop:ensure-directory-pathname
             cwd)
            :git-paths
            (find-git-footer-paths cwd)
            :poll-seconds poll-seconds
            :debounce-seconds
            debounce-seconds
            :clock-function clock-function
            :stop-semaphore
            (sb-thread:make-semaphore
             :count 0)))
         (symbolic-branch-function
           *git-symbolic-branch-function*))
    (refresh-footer-data-provider provider)
    (when
        (footer-data-provider-git-paths
         provider)
      (setf
       (footer-data-provider-observed-source-signature
        provider)
       (footer-source-signature
        (footer-data-provider-git-paths
         provider))))
    (when
        (footer-data-provider-git-paths
         provider)
      (setf
       (footer-data-provider-thread provider)
       (sb-thread:make-thread
        (lambda ()
          (let ((*git-symbolic-branch-function*
                  symbolic-branch-function))
            (loop
              until
              (sb-thread:wait-on-semaphore
               (footer-data-provider-stop-semaphore
                provider)
               :timeout
               (footer-data-provider-poll-seconds
                provider))
              do
              (poll-footer-data-provider
               provider))))
        :name "cadr footer git watcher")))
    provider))

(defun footer-data-provider-git-branch
    (provider)
  (sb-thread:with-mutex
      ((footer-data-provider-lock provider))
    (let ((branch
            (footer-data-provider-cached-branch
             provider)))
      (unless (eq branch :uninitialized)
        branch))))

(defun footer-data-provider-on-branch-change
    (provider callback)
  (sb-thread:with-mutex
      ((footer-data-provider-lock provider))
    (pushnew
     callback
     (footer-data-provider-callbacks
      provider)))
  (lambda ()
    (sb-thread:with-mutex
        ((footer-data-provider-lock provider))
      (setf
       (footer-data-provider-callbacks provider)
       (delete
        callback
        (footer-data-provider-callbacks
         provider))))))

(defun footer-data-provider-set-status
    (provider key text)
  (sb-thread:with-mutex
      ((footer-data-provider-lock provider))
    (setf
     (footer-data-provider-%statuses provider)
     (if text
         (acons
          key text
          (remove
           key
           (footer-data-provider-%statuses
            provider)
           :key #'car
           :test #'string=))
         (remove
          key
          (footer-data-provider-%statuses
           provider)
          :key #'car
          :test #'string=))))
  text)

(defun footer-data-provider-statuses
    (provider)
  (sb-thread:with-mutex
      ((footer-data-provider-lock provider))
    (copy-tree
     (footer-data-provider-%statuses
      provider))))

(defun footer-data-provider-dispose
    (provider)
  (let ((thread nil))
    (sb-thread:with-mutex
        ((footer-data-provider-lock provider))
      (unless
          (footer-data-provider-disposed-p
           provider)
        (setf
         (footer-data-provider-disposed-p
          provider)
         t
         thread
         (footer-data-provider-thread
          provider)
         (footer-data-provider-callbacks
          provider)
         nil)
        (sb-thread:signal-semaphore
         (footer-data-provider-stop-semaphore
          provider))))
    (when thread
      (stop-thread-for-cleanup thread)))
  nil)
