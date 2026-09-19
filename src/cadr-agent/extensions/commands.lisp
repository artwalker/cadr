(in-package #:cadr-agent)

;;; Commands and prompt templates

(defun extension-command-lookup-name (definition)
  (or (extension-command-definition-invocation-name definition)
      (extension-command-definition-name definition)))

(defun assign-extension-command-invocations (commands)
  (let ((counts (make-hash-table :test #'equal))
        (seen (make-hash-table :test #'equal))
        (taken (make-hash-table :test #'equal)))
    (dolist (command commands)
      (let ((name (extension-command-definition-name command)))
        (setf (gethash name counts)
              (1+ (or (gethash name counts) 0)))))
    (dolist (command commands)
      (let* ((name (extension-command-definition-name command))
             (occurrence (1+ (or (gethash name seen) 0)))
             (invocation name)
             (suffix occurrence))
        (setf (gethash name seen) occurrence)
        (when (> (gethash name counts) 1)
          (setf invocation
                (format nil "~A:~D" name occurrence)))
        (loop while (gethash invocation taken)
              do (incf suffix)
                 (setf invocation
                       (format nil "~A:~D" name suffix)))
        (setf (gethash invocation taken) t)
        (setf (extension-command-definition-invocation-name
               command)
              invocation)))
    commands))

(defun find-extension-command (snapshot name)
  (find name
        (extension-snapshot-commands snapshot)
        :key #'extension-command-lookup-name
        :test #'string=))

(defun invoke-extension-command
    (host name arguments)
  (let* ((snapshot
           (extension-host-current-snapshot host))
         (definition
           (find-extension-command snapshot name)))
    (unless definition
      (return-from invoke-extension-command nil))
    (handler-case
        (call-with-extension-definition
         host snapshot definition
         (lambda (context)
           (funcall
            (extension-command-definition-handler definition)
            arguments context)))
      (condition (condition)
        (notify-extension-failure
         host definition "Command" condition)))
    t))

(defun parse-extension-command-arguments (text)
  (let ((arguments nil)
        (current
          (make-array
           16 :element-type 'character
           :adjustable t :fill-pointer 0))
        (quote nil))
    (labels
        ((finish-current ()
           (when (plusp (fill-pointer current))
             (push (copy-seq current) arguments)
             (setf (fill-pointer current) 0))))
      (loop for character across text
            do
            (cond
              (quote
               (if (char= character quote)
                   (setf quote nil)
                   (vector-push-extend character current)))
              ((or (char= character #\")
                   (char= character #\'))
               (setf quote character))
              ((member character
                       '(#\Space #\Tab #\Newline #\Return))
               (finish-current))
              (t
               (vector-push-extend character current))))
      (finish-current))
    (nreverse arguments)))

(defun join-extension-arguments (arguments)
  (format nil "~{~A~^ ~}" arguments))

(defun extension-argument (arguments index)
  (and
   (plusp index)
   (nth (1- index) arguments)))

(defun parse-positive-index (text)
  (and
   (plusp (length text))
   (every #'digit-char-p text)
   (parse-integer text)))

(defun expand-braced-template-token
    (token arguments)
  (let ((default-position (search ":-" token))
        (slice-prefix-p
          (and
           (>= (length token) 2)
           (char= (char token 0) #\@)
           (char= (char token 1) #\:))))
    (cond
      (default-position
       (let* ((target
                (subseq token 0 default-position))
              (default
                (subseq token (+ default-position 2)))
              (value
                (cond
                  ((or (string= target "@")
                       (string= target "ARGUMENTS"))
                   (join-extension-arguments arguments))
                  (t
                   (let ((index
                           (parse-positive-index target)))
                     (and index
                          (extension-argument
                           arguments index)))))))
         (if (and value (plusp (length value)))
             value
             default)))
      (slice-prefix-p
       (let* ((parts
                (loop with start = 2
                      for position =
                        (position #\: token :start start)
                      collect
                      (subseq token start position)
                      while position
                      do (setf start (1+ position))))
              (start
                (parse-positive-index (first parts)))
              (length-value
                (and (second parts)
                     (parse-positive-index
                      (second parts)))))
         (if start
             (join-extension-arguments
              (if length-value
                  (subseq
                   arguments
                   (min (1- start)
                        (length arguments))
                   (min
                    (+ (1- start) length-value)
                    (length arguments)))
                  (nthcdr
                   (min (1- start)
                        (length arguments))
                   arguments)))
             nil)))
      ((or (string= token "@")
           (string= token "ARGUMENTS"))
       (join-extension-arguments arguments))
      (t
       (let ((index (parse-positive-index token)))
         (and index
              (or
               (extension-argument arguments index)
               "")))))))

(defun expand-simple-template-token
    (template start arguments)
  (cond
    ((and
      (< (1+ start) (length template))
      (char= (char template (1+ start)) #\@))
     (values
      (join-extension-arguments arguments)
      (+ start 2)))
    ((and
      (<= (+ start 10) (length template))
      (string=
       "ARGUMENTS"
       template
       :start2 (1+ start)
       :end2 (+ start 10)))
     (values
      (join-extension-arguments arguments)
      (+ start 10)))
    (t
     (let ((end (1+ start)))
       (loop
         while
         (and
          (< end (length template))
          (digit-char-p (char template end)))
         do (incf end))
       (if (> end (1+ start))
           (values
            (or
             (extension-argument
              arguments
              (parse-integer
               template
               :start (1+ start)
               :end end))
             "")
            end)
           (values "$" (1+ start)))))))

(defun substitute-extension-template
    (template arguments)
  (with-output-to-string (output)
    (loop with index = 0
          while (< index (length template))
          do
          (if (char/= (char template index) #\$)
              (progn
                (write-char (char template index) output)
                (incf index))
              (if
                  (and
                   (< (1+ index) (length template))
                   (char= (char template (1+ index)) #\{))
                  (let ((close
                          (position
                           #\} template
                           :start (+ index 2))))
                    (if close
                        (let ((replacement
                                (expand-braced-template-token
                                 (subseq
                                  template
                                  (+ index 2)
                                  close)
                                 arguments)))
                          (if replacement
                              (write-string replacement output)
                              (write-string
                               (subseq
                                template index
                                (1+ close))
                               output))
                          (setf index (1+ close)))
                        (progn
                          (write-char #\$ output)
                          (incf index))))
                  (multiple-value-bind
                        (replacement next)
                      (expand-simple-template-token
                       template index arguments)
                    (write-string replacement output)
                    (setf index next)))))))

(defun split-slash-invocation (text)
  (unless
      (and
       (plusp (length text))
       (char= (char text 0) #\/))
    (return-from split-slash-invocation
      (values nil nil)))
  (let ((separator
          (position-if
           (lambda (character)
             (member character
                     '(#\Space #\Tab #\Newline #\Return)))
           text
           :start 1)))
    (values
     (subseq text 1 separator)
     (if separator
         (string-left-trim
          '(#\Space #\Tab #\Newline #\Return)
          (subseq text separator))
         ""))))

(defun expand-extension-prompt (host text)
  (multiple-value-bind (name argument-text)
      (split-slash-invocation text)
    (unless name
      (return-from expand-extension-prompt
        (values text nil)))
    (let* ((snapshot
             (extension-host-current-snapshot host))
           (definition
             (find
              name
              (extension-snapshot-templates snapshot)
              :key #'extension-template-definition-name
              :test #'string=)))
      (unless definition
        (return-from expand-extension-prompt
          (values text nil)))
      (let ((arguments
              (parse-extension-command-arguments
               argument-text)))
        (handler-case
            (values
             (if
                 (stringp
                  (extension-template-definition-template
                   definition))
                 (substitute-extension-template
                  (extension-template-definition-template
                   definition)
                  arguments)
                 (call-with-extension-definition
                  host snapshot definition
                  (lambda (context)
                    (let ((expanded
                            (funcall
                             (extension-template-definition-template
                              definition)
                             arguments context)))
                      (unless (stringp expanded)
                        (error
                         "Prompt template returned ~S instead of a string"
                         expanded))
                      expanded))))
             t)
          (condition (condition)
            (notify-extension-failure
             host definition "Prompt template" condition)
            (values text t)))))))
