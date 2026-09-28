(in-package #:cadr-tui)

(defstruct autocomplete-item
  (value "" :type string)
  (label "" :type string)
  description)

(defstruct autocomplete-command
  (name "" :type string)
  description
  argument-hint
  argument-completer)

(defstruct autocomplete-suggestions
  (items nil :type list)
  (prefix "" :type string))

(defstruct (autocomplete-request-signal
            (:constructor make-autocomplete-request-signal
                (&aux
                 (state
                   (cadr-core:make-cancellation-state)))))
  (state (cadr-core:make-cancellation-state)
         :type cadr-core:cancellation-state))

(defun autocomplete-request-abort (signal)
  (when signal
    (cadr-core:abort-cancellation
     (autocomplete-request-signal-state signal)))
  signal)

(defun autocomplete-request-aborted-p (signal)
  (and signal
       (cadr-core:cancellation-aborted-p
        (autocomplete-request-signal-state signal))))

(defstruct (autocomplete-provider
            (:constructor %make-autocomplete-provider))
  (commands nil :type list)
  (command-items nil :type list)
  base-path
  fd-path
  (trigger-characters nil :type list)
  suggestions-function
  apply-completion-function
  should-trigger-file-completion-function)

(defun make-autocomplete-provider
    (&key
       (commands nil)
       (base-path (uiop:getcwd))
       fd-path
       trigger-characters
       suggestions-function
       apply-completion-function
       should-trigger-file-completion-function)
  ;; Bake command autocomplete-items once. Hot slash path
  ;; filters the vector; not mapcar+format each keystroke.
  (%make-autocomplete-provider
   :commands commands
   :command-items
   (mapcar #'command-autocomplete-item commands)
   :base-path base-path
   :fd-path fd-path
   :trigger-characters trigger-characters
   :suggestions-function suggestions-function
   :apply-completion-function apply-completion-function
   :should-trigger-file-completion-function
   should-trigger-file-completion-function))

(defun autocomplete-cjk-punctuation-p (character)
  (find character
        "，．：；！？（）［］｛｝“”‘’…—。、「」『』《》【】"))

(defun autocomplete-separator-p (character)
  (or (member character
              '(#\Space #\Tab #\Newline #\Return #\Page)
              :test #'char=)
      (char= character (code-char #x3000))
      (autocomplete-cjk-punctuation-p character)))

(defun autocomplete-delimiter-p (character)
  (or (member character '(#\" #\' #\=))
      (autocomplete-separator-p character)))

(defun last-autocomplete-delimiter (text)
  (position-if #'autocomplete-delimiter-p
               text :from-end t))

(defun unclosed-double-quote (text)
  (let ((start nil)
        (open-p nil))
    (loop for character across text
          for index from 0
          when (char= character #\")
            do
            (setf open-p (not open-p))
            (when open-p (setf start index)))
    (and open-p start)))

(defun autocomplete-token-start-p (text index)
  (or (zerop index)
      (autocomplete-delimiter-p
       (char text (1- index)))))

(defun quoted-autocomplete-prefix (text)
  (let ((quote (unclosed-double-quote text)))
    (when quote
      (cond
        ((and (plusp quote)
              (char= (char text (1- quote)) #\@)
              (autocomplete-token-start-p
               text (1- quote)))
         (subseq text (1- quote)))
        ((autocomplete-token-start-p text quote)
         (subseq text quote))))))

(defun autocomplete-at-prefix (text)
  (or
   (let ((quoted
           (quoted-autocomplete-prefix text)))
     (and quoted
          (string-prefix-p "@\"" quoted)
          quoted))
   (let* ((delimiter
            (last-autocomplete-delimiter text))
          (start (if delimiter (1+ delimiter) 0)))
     (and (< start (length text))
          (char= (char text start) #\@)
          (subseq text start)))))

(defun autocomplete-path-prefix (text force-p)
  (or
   (quoted-autocomplete-prefix text)
   (let* ((delimiter
            (last-autocomplete-delimiter text))
          (prefix
            (if delimiter
                (subseq text (1+ delimiter))
                text)))
     (cond
       (force-p prefix)
       ((or (find #\/ prefix)
            (string-prefix-p "." prefix)
            (string-prefix-p "~/" prefix))
        prefix)
       ((and (zerop (length prefix))
             (plusp (length text))
             (char= (char text
                          (1- (length text)))
                    #\Space))
        prefix)
       (t nil)))))

(defun parse-autocomplete-path-prefix (prefix)
  (cond
    ((string-prefix-p "@\"" prefix)
     (values (subseq prefix 2) t t))
    ((string-prefix-p "\"" prefix)
     (values (subseq prefix 1) nil t))
    ((string-prefix-p "@" prefix)
     (values (subseq prefix 1) t nil))
    (t (values prefix nil nil))))

(defun autocomplete-display-path (path)
  (substitute #\/ #\\ path))

(defun autocomplete-quote-value
    (path at-prefix-p quoted-p)
  (let* ((needs-quotes-p
           (or quoted-p
               (find-if #'autocomplete-separator-p path)))
         (prefix (if at-prefix-p "@" "")))
    (if needs-quotes-p
        (format nil "~A\"~A\"" prefix path)
        (concatenate 'string prefix path))))

(defun expand-autocomplete-home (path)
  (cond
    ((string-prefix-p "~/" path)
     (merge-pathnames (subseq path 2)
                      (user-homedir-pathname)))
    ((string= path "~")
     (user-homedir-pathname))
    (t path)))

(defun autocomplete-absolute-path-p (path)
  (and (plusp (length path))
       (char= (char path 0) #\/)))

(defun autocomplete-last-slash (path)
  (position #\/ path :from-end t))

(defun autocomplete-basename (path)
  (let* ((trimmed
           (string-right-trim "/" path))
         (slash
           (autocomplete-last-slash trimmed)))
    (if slash
        (subseq trimmed (1+ slash))
        trimmed)))

(defun autocomplete-dirname (path)
  (let ((slash (autocomplete-last-slash path)))
    (cond
      ((null slash) ".")
      ((zerop slash) "/")
      (t (subseq path 0 slash)))))

(defun autocomplete-directory-pathname
    (base raw-directory)
  (let ((expanded
          (expand-autocomplete-home raw-directory)))
    (cond
      ((pathnamep expanded)
       (uiop:ensure-directory-pathname expanded))
      ((autocomplete-absolute-path-p expanded)
       (uiop:ensure-directory-pathname expanded))
      (t
       (uiop:ensure-directory-pathname
        (merge-pathnames expanded
                         (uiop:ensure-directory-pathname
                          base)))))))

(defun directory-entry-dirents (directory)
  ;; Vector of (name . directory-p). One opendir/readdir +
  ;; stat; not UIOP pathname nconc of subdirectories+files.
  (handler-case
      (let* ((dir-path
               (uiop:ensure-directory-pathname directory))
             (dir-native
               (uiop:native-namestring dir-path))
             (dp (sb-posix:opendir dir-native))
             (entries nil))
        (unwind-protect
             (loop
               (let ((entry (sb-posix:readdir dp)))
                 (when (or (null entry)
                           (sb-alien:null-alien entry))
                   (return))
                 (let ((name
                         (copy-seq
                          (sb-posix:dirent-name entry))))
                   (unless (or (string= name ".")
                               (string= name ".."))
                     (let* ((full
                              (concatenate
                               'string dir-native name))
                            (directory-p
                              (handler-case
                                  (sb-posix:s-isdir
                                   (sb-posix:stat-mode
                                    (sb-posix:stat full)))
                                (error () nil))))
                       (push (cons name directory-p)
                             entries))))))
          (sb-posix:closedir dp))
        entries)
    (condition () nil)))

(defun autocomplete-direct-suggestions
    (provider prefix)
  (multiple-value-bind (raw at-prefix-p quoted-p)
      (parse-autocomplete-path-prefix prefix)
    (let* ((root-p
             (or (string= raw "")
                 (member raw
                         '("./" "../" "~" "~/" "/")
                         :test #'string=)))
           (trailing-p
             (and (plusp (length raw))
                  (char= (char raw
                               (1- (length raw)))
                         #\/)))
           (directory-part
             (cond
               (root-p raw)
               (trailing-p raw)
               (t (autocomplete-dirname raw))))
           (search-prefix
             (if (or root-p trailing-p)
                 ""
                 (autocomplete-basename raw)))
           (search-down
             (string-downcase search-prefix))
           (directory
             (autocomplete-directory-pathname
              (autocomplete-provider-base-path provider)
              directory-part))
           (items nil))
      (dolist (entry (directory-entry-dirents directory))
        (let ((name (car entry))
              (directory-p (cdr entry)))
          (when (string-prefix-p
                 search-down
                 (string-downcase name))
            (let* ((display-directory
                     (cond
                       ((or root-p trailing-p)
                        raw)
                       ((and (string= directory-part ".")
                             (string-prefix-p "./" raw))
                        "./")
                       ((string= directory-part ".") "")
                       (t
                        (concatenate
                         'string directory-part "/"))))
                   (display
                     (autocomplete-display-path
                      (concatenate
                       'string display-directory name
                       (if directory-p "/" "")))))
              (push
               (make-autocomplete-item
                :value
                (autocomplete-quote-value
                 display at-prefix-p quoted-p)
                :label
                (concatenate
                 'string name
                 (if directory-p "/" "")))
               items)))))
      (sort items
            (lambda (left right)
              (let ((left-dir-p
                      (string-suffix-p
                       "/" (autocomplete-item-label left)))
                    (right-dir-p
                      (string-suffix-p
                       "/" (autocomplete-item-label right))))
                (if (eq left-dir-p right-dir-p)
                    (string-lessp
                     (autocomplete-item-label left)
                     (autocomplete-item-label right))
                    left-dir-p)))))))

(defun run-fd-autocomplete
    (provider query &key base max-depth)
  (let ((fd (autocomplete-provider-fd-path provider))
        (directory
          (or base
              (autocomplete-provider-base-path
               provider))))
    (unless fd
      (return-from run-fd-autocomplete nil))
    (handler-case
        (let* ((arguments
                 (append
                  (list
                   (namestring fd)
                   "--base-directory"
                   (namestring
                    (uiop:ensure-directory-pathname
                     directory))
                   "--max-results" "100"
                   "--type" "f" "--type" "d"
                   "--follow" "--hidden"
                   "--exclude" ".git")
                  (when max-depth
                    (list "--max-depth"
                          (princ-to-string max-depth)))
                  (when (find #\/ query)
                    '("--full-path"))
                  (when (plusp (length query))
                    (list query))))
               (output
                 (uiop:run-program
                  arguments
                  :output :string
                  :error-output nil
                  :ignore-error-status t)))
          (remove-if
           (lambda (line)
             (or (zerop (length line))
                 (string= line ".git/")
                 (string-prefix-p ".git/" line)
                 (search "/.git/" line)))
           (uiop:split-string
            output :separator '(#\Newline #\Return))))
      (condition () nil))))

(defun autocomplete-scoped-fuzzy-query (provider query)
  (let* ((normalized (autocomplete-display-path query))
         (slash (autocomplete-last-slash normalized)))
    (unless slash
      (return-from autocomplete-scoped-fuzzy-query nil))
    (let* ((display-base (subseq normalized 0 (1+ slash)))
           (scoped-query (subseq normalized (1+ slash)))
           (base-dir
             (autocomplete-directory-pathname
              (autocomplete-provider-base-path provider)
              display-base)))
      (when (uiop:directory-exists-p base-dir)
        (values base-dir scoped-query display-base)))))

(defun autocomplete-merge-fd-paths (direct recursive)
  (let ((seen (make-hash-table :test #'equal)))
    (dolist (path direct)
      (setf (gethash path seen) t))
    (append
     direct
     (remove-if (lambda (path) (gethash path seen))
                recursive))))

(defun autocomplete-entry-score
    (path query directory-p)
  (let* ((filename
           (string-downcase
            (autocomplete-basename path)))
         (query (string-downcase query))
         (score
           (cond
             ((zerop (length query)) 1)
             ((string= filename query) 100)
             ((string-prefix-p query filename) 80)
             ((search query filename) 50)
             ((search query
                      (string-downcase path))
              30)
             (t 0))))
    (+ score
       (if (and directory-p (plusp score))
           10 0))))

(defun autocomplete-fuzzy-file-suggestions
    (provider prefix)
  (multiple-value-bind (query at-prefix-p quoted-p)
      (parse-autocomplete-path-prefix prefix)
    (declare (ignore at-prefix-p))
    (multiple-value-bind (scoped-base scoped-query display-base)
        (autocomplete-scoped-fuzzy-query provider query)
      (let* ((fd-query (or scoped-query query))
             (paths
               (autocomplete-merge-fd-paths
                (run-fd-autocomplete
                 provider fd-query
                 :base scoped-base
                 :max-depth 1)
                (run-fd-autocomplete
                 provider fd-query
                 :base scoped-base)))
             (items nil))
        (dolist (path paths)
          (let* ((directory-p
                   (string-suffix-p "/" path))
                 (score
                   (autocomplete-entry-score
                    path fd-query directory-p))
                 (display
                   (if display-base
                       (concatenate
                        'string
                        (autocomplete-display-path display-base)
                        (autocomplete-display-path path))
                       (autocomplete-display-path path))))
            (when (plusp score)
              (push
               (list
                score
                (make-autocomplete-item
                 :value
                 (autocomplete-quote-value
                  display t quoted-p)
                 :label
                 (concatenate
                  'string
                  (autocomplete-basename display)
                  (if directory-p "/" ""))
                 :description
                 (let ((directory
                         (autocomplete-dirname
                          (string-right-trim
                           "/" display))))
                   (unless (string= directory ".")
                     directory))))
               items))))
        (mapcar
         #'second
         (subseq
          (stable-sort
           items
           (lambda (left right)
             (let ((score-left (first left))
                   (score-right (first right)))
               (cond
                 ((/= score-left score-right)
                  (> score-left score-right))
                 (t
                  (let* ((item-left (second left))
                         (item-right (second right))
                         (path-left
                           (or
                            (autocomplete-item-description
                             item-left)
                            ""))
                         (path-right
                           (or
                            (autocomplete-item-description
                             item-right)
                            ""))
                         (depth-left (count #\/ path-left))
                         (depth-right (count #\/ path-right)))
                    (cond
                      ((/= depth-left depth-right)
                       (< depth-left depth-right))
                      ((/= (length path-left)
                           (length path-right))
                       (< (length path-left)
                          (length path-right)))
                      (t
                       (string-lessp
                        (autocomplete-item-label item-left)
                        (autocomplete-item-label
                         item-right))))))))))
          0 (min 20 (length items))))))))

(defun command-autocomplete-item (command)
  (make-autocomplete-item
   :value (autocomplete-command-name command)
   :label (autocomplete-command-name command)
   :description
   (let ((description
           (or (autocomplete-command-description command)
               ""))
         (hint
           (autocomplete-command-argument-hint command)))
     (cond
       ((and hint (plusp (length description)))
        (format nil "~A — ~A" hint description))
       (hint hint)
       ((plusp (length description)) description)
       (t nil)))))

(defun autocomplete-command-suggestions
    (provider text)
  (let* ((space (position #\Space text))
         (prefix
           (if space
               (subseq text 1 space)
               (subseq text 1))))
    (if (null space)
        (let ((items
                (fuzzy-filter
                 (autocomplete-provider-command-items
                  provider)
                 prefix
                 #'autocomplete-item-value)))
          (and items
               (make-autocomplete-suggestions
                :items items :prefix text)))
        (let* ((command
                 (find
                  prefix
                  (autocomplete-provider-commands
                   provider)
                  :key #'autocomplete-command-name
                  :test #'string=))
               (completer
                 (and command
                      (autocomplete-command-argument-completer
                       command)))
               (argument
                 (subseq text (1+ space)))
               (items (and completer
                           (funcall completer argument))))
          (and (listp items) items
               (make-autocomplete-suggestions
                :items items :prefix argument))))))

(defun editor-line-at (lines index)
  ;; editor-lines is a vector (P.12.2). Tests and extension
  ;; callbacks still pass lists. NTH past the end is NIL; AREF is not.
  (cond
    ((or (not (integerp index)) (minusp index))
     "")
    ((vectorp lines)
     (if (< index (length lines))
         (aref lines index)
         ""))
    (t
     (or (nth index lines) ""))))

(defun autocomplete-get-suggestions
    (provider lines cursor-line cursor-column
     &key force-p)
  (let* ((line (editor-line-at lines cursor-line))
         (before
           (subseq line 0
                   (min cursor-column
                        (length line))))
         (at-prefix
           (autocomplete-at-prefix before)))
    (when at-prefix
      (let ((items
              (autocomplete-fuzzy-file-suggestions
               provider at-prefix)))
        (return-from autocomplete-get-suggestions
          (and items
               (make-autocomplete-suggestions
                :items items :prefix at-prefix)))))
    (when (and (plusp (length before))
               (char= (char before 0) #\/)
               (not force-p))
      (return-from autocomplete-get-suggestions
        (autocomplete-command-suggestions
         provider before)))
    (let ((path-prefix
            (autocomplete-path-prefix before force-p)))
      (when path-prefix
        (let ((items
                (autocomplete-direct-suggestions
                 provider path-prefix)))
          (and items
               (make-autocomplete-suggestions
                :items items :prefix path-prefix)))))))

(defun autocomplete-apply
    (lines cursor-line cursor-column item prefix)
  (let* ((line (editor-line-at lines cursor-line))
         (prefix-start
           (max 0 (- cursor-column
                     (length prefix))))
         (before (subseq line 0 prefix-start))
         (after (subseq line cursor-column))
         (quoted-p
           (or (string-prefix-p "\"" prefix)
               (string-prefix-p "@\"" prefix)))
         (value (autocomplete-item-value item))
         (after
           (if (and quoted-p
                    (string-suffix-p "\"" value)
                    (string-prefix-p "\"" after))
               (subseq after 1)
               after))
         (slash-command-p
           (and (string-prefix-p "/" prefix)
                (zerop
                 (length
                  (string-trim
                   '(#\Space #\Tab) before)))
                (null
                 (find #\/ prefix :start 1))))
         (directory-p
           (string-suffix-p "/"
                            (autocomplete-item-label item)))
         (replacement
           (if slash-command-p
               (concatenate 'string "/" value " ")
               value))
         (suffix
           (if (and
                (string-prefix-p "@" prefix)
                (not directory-p))
               " "
               ""))
         (new-line
           (concatenate
            'string before replacement suffix after))
         (offset
           (if (and directory-p
                    (string-suffix-p "\"" replacement))
               (1- (length replacement))
               (length replacement)))
         (new-lines (copy-seq lines)))
    (setf (elt new-lines cursor-line) new-line)
    (values
     new-lines cursor-line
     (+ (length before) offset
        (length suffix)))))

(defun autocomplete-provider-get-suggestions
    (provider lines cursor-line cursor-column
     &key signal force-p)
  (let ((callback
          (autocomplete-provider-suggestions-function
           provider)))
    (if callback
        (funcall
         callback lines cursor-line cursor-column
         (list
          :signal signal
          :force-p (not (null force-p))
          :cwd (autocomplete-provider-base-path provider)))
        (autocomplete-get-suggestions
         provider lines cursor-line cursor-column
         :force-p force-p))))

(defun autocomplete-provider-apply-completion
    (provider lines cursor-line cursor-column item prefix)
  (let ((callback
          (autocomplete-provider-apply-completion-function
           provider)))
    (if callback
        (funcall callback lines cursor-line cursor-column
                 item prefix)
        (autocomplete-apply
         lines cursor-line cursor-column item prefix))))

(defun autocomplete-provider-should-trigger-file-completion-p
    (provider lines cursor-line cursor-column)
  (let ((callback
          (autocomplete-provider-should-trigger-file-completion-function
           provider)))
    (if callback
        (not
         (null
          (funcall callback lines cursor-line cursor-column)))
        t)))
