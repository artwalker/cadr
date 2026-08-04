(in-package #:cadr-cli)

(defun format-resume-command
    (session-id
     &key persisted-p session-file
       session-file-exists-p terminal-p
       default-session-directory-p
       session-directory)
  (when
      (and terminal-p persisted-p session-file
           session-file-exists-p)
    (if default-session-directory-p
        (format nil "cadr --session ~A"
                (shell-quote session-id))
        (format nil
                "cadr --session-dir ~A --session ~A"
                (shell-quote session-directory)
                (shell-quote session-id)))))

(defun write-session-resume-hint
    (session session-directory
     &key
       (output *standard-output*)
       terminal-p
       default-session-directory-p)
  (let* ((path (cadr-agent:session-path session))
         (command
           (format-resume-command
            (cadr-agent:session-id session)
            :persisted-p
            (cadr-agent::session-persisted-p session)
            :session-file path
            :session-file-exists-p
            (not (null (and path (probe-file path))))
            :terminal-p terminal-p
            :default-session-directory-p
            default-session-directory-p
            :session-directory
            (display-directory-name session-directory))))
    (when command
      (format
       output "~A ~A~%"
       (cadr-tui:theme-foreground
        :dim "To resume this session:"
        :enabled-p terminal-p)
       command)
      (finish-output output))
    command))

(defun numeric-version-token-p (text)
  (and (plusp (length text))
       (every #'digit-char-p text)))

(defun version-tokens (version)
  (uiop:split-string version
                     :separator '(#\. #\- #\+)))

(defun compare-package-versions (first second)
  (let ((left (version-tokens first))
        (right (version-tokens second)))
    (loop for index below
          (max (length left) (length right))
          for a = (or (nth index left) "0")
          for b = (or (nth index right) "0")
          unless (string= a b)
            do
            (return
              (cond
                ((and (numeric-version-token-p a)
                      (numeric-version-token-p b))
                 (signum
                  (- (parse-integer a)
                     (parse-integer b))))
                ((numeric-version-token-p a) 1)
                ((numeric-version-token-p b) -1)
                (t
                 (if (string< a b) -1 1))))
          finally (return 0))))

(defun cadr-user-agent (version)
  (format nil "~A/~A (~(~A~); sbcl/~A; ~(~A~))"
          (cadr-ai::cadr-product-slug)
          version
          (software-type)
          (lisp-implementation-version)
          (machine-type)))

(defun git-source-safe-part-p (value &key allow-slash-p)
  (handler-case
      (let ((decoded
              (percent-decode-path value)))
        (and
         (not (find (code-char 0) value))
         (not (find #\\ value))
         (not (uiop:string-prefix-p "/" value))
         (not (find (code-char 0) decoded))
         (not (find #\\ decoded))
         (not (uiop:string-prefix-p "/" decoded))
         (or allow-slash-p
             (not (find #\/ decoded)))
         (not
          (member
           ".."
           (uiop:split-string decoded
                              :separator '(#\/))
           :test #'string=))))
    (condition () nil)))

(defun split-git-ref (repository path-start)
  (let ((separator
          (position #\@ repository
                    :start path-start)))
    (if separator
        (values
         (concatenate
          'string
          (subseq repository 0 separator))
         (subseq repository (1+ separator)))
        (values repository nil))))

(defun parse-git-source (source)
  (let* ((trimmed
           (string-trim '(#\Space #\Tab) source))
         (prefixed-p
           (uiop:string-prefix-p "git:" trimmed))
         (value
           (if prefixed-p
               (string-trim
                '(#\Space #\Tab)
                (subseq trimmed 4))
               trimmed)))
    (unless
        (or prefixed-p
            (cl-ppcre:scan
             "^(?i:https?|ssh|git)://"
             value))
      (return-from parse-git-source nil))
    (handler-case
        (multiple-value-bind
              (repository ref)
            (let ((path-start
                    (cond
                      ((uiop:string-prefix-p "git@" value)
                       (1+
                        (or (position #\: value)
                            (length value))))
                      ((search "://" value)
                       (let* ((scheme-end
                                (+ (search "://" value) 3))
                              (slash
                                (position #\/ value
                                          :start scheme-end)))
                         (if slash (1+ slash)
                             (length value))))
                      (t
                       (1+
                        (or (position #\/ value)
                            (length value)))))))
              (split-git-ref value path-start))
          (let (host path normalized-repository)
            (cond
              ((uiop:string-prefix-p "git@" repository)
               (let ((colon (position #\: repository)))
                 (unless colon
                   (return-from parse-git-source nil))
                 (setf host
                       (subseq repository
                               (length "git@") colon)
                       path (subseq repository (1+ colon))
                       normalized-repository repository)))
              ((search "://" repository)
               (let* ((scheme-end
                        (+ (search "://" repository) 3))
                      (slash
                        (position #\/ repository
                                  :start scheme-end)))
                 (unless slash
                   (return-from parse-git-source nil))
                 (let* ((authority
                          (subseq repository
                                  scheme-end slash))
                        (at
                          (position #\@ authority
                                    :from-end t)))
                   (setf host
                         (if at
                             (subseq authority (1+ at))
                             authority)
                         path
                         (subseq repository (1+ slash))
                         normalized-repository
                         repository))))
              (t
               (let ((slash (position #\/ repository)))
                 (unless slash
                   (return-from parse-git-source nil))
                 (setf host (subseq repository 0 slash)
                       path (subseq repository (1+ slash))
                       normalized-repository
                       (format nil "https://~A"
                               repository)))))
            (setf path
                  (if (uiop:string-suffix-p ".git" path)
                      (subseq path 0 (- (length path) 4))
                      path))
            (when
                (and
                 (find #\. host)
                 (>= (length
                      (uiop:split-string path
                                         :separator '(#\/)))
                     2)
                 (git-source-safe-part-p host)
                 (git-source-safe-part-p
                  path :allow-slash-p t)
                 (or (null ref)
                     (git-source-safe-part-p
                      ref :allow-slash-p t)))
              (list
               :type :git
               :repository normalized-repository
               :host host
               :path path
               :ref ref
               :pinned-p (not (null ref))))))
      (condition () nil))))
