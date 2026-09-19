(in-package #:cadr-cli/tests)

(defmacro with-test-directory ((directory) &body body)
  `(uiop:with-temporary-file
       (:pathname marker :keep t)
     (delete-file marker)
     (let ((,directory
             (uiop:ensure-directory-pathname
              (pathname (format nil "~A-dir/"
                                (namestring marker))))))
       (ensure-directories-exist
        (merge-pathnames "anchor" ,directory))
       (unwind-protect
            (progn ,@body)
         (when (probe-file ,directory)
           (uiop:delete-directory-tree
            ,directory :validate t :if-does-not-exist :ignore))))))

(defun write-text (path text)
  (ensure-directories-exist path)
  (with-open-file (stream path
                          :direction :output
                          :if-exists :supersede
                          :if-does-not-exist :create
                          :external-format :utf-8)
    (write-string text stream)))

(defun read-text (path)
  (uiop:read-file-string path :external-format :utf-8))

(defun make-fake-fd-program (directory paths)
  (let ((program (merge-pathnames "fd" directory)))
    (with-open-file
        (stream program
                :direction :output
                :if-exists :supersede
                :if-does-not-exist :create)
      (write-line "#!/bin/sh" stream)
      (dolist (path paths)
        (format stream "printf '%s\\n' '~A'~%" path)))
    (uiop:run-program
     (list "chmod" "+x" (namestring program)))
    program))

(defmacro with-test-path-prefix ((directory) &body body)
  `(let ((previous-path (uiop:getenv "PATH")))
     (unwind-protect
          (progn
            (setf (uiop:getenv "PATH")
                  (format nil "~A~@[:~A~]"
                          (namestring ,directory)
                          previous-path))
            ,@body)
       (setf (uiop:getenv "PATH") previous-path))))

(defun args (&rest pairs)
  (apply #'cadr-ai::json-object pairs))

(defun invoke-tool (tool arguments &optional cwd)
  (let ((cadr-agent:*tool-call-cwd* cwd))
    (funcall (cadr-ai:tool-executor tool) "test-call" arguments)))

(defun result-text (content)
  (cadr-ai:text-content-text (first content)))

(defun count-substring (needle haystack)
  (loop with start = 0
        for position = (search needle haystack :start2 start)
        while position
        count position
        do (setf start (+ position (length needle)))))

(defclass notifying-string-output-stream
    (trivial-gray-streams:fundamental-character-output-stream)
  ((delegate
    :initform (make-string-output-stream)
    :reader notifying-output-delegate)
   (notification
    :initform (sb-thread:make-semaphore :count 0)
    :reader notifying-output-notification)
   (lock
    :initform (sb-thread:make-mutex
               :name "cadr test notifying output")
    :reader notifying-output-lock)))

(defmethod trivial-gray-streams:stream-write-char
    ((stream notifying-string-output-stream) character)
  (sb-thread:with-mutex ((notifying-output-lock stream))
    (write-char character (notifying-output-delegate stream)))
  (when (char= character #\Newline)
    (sb-thread:signal-semaphore
     (notifying-output-notification stream)))
  character)

(defmethod trivial-gray-streams:stream-write-string
    ((stream notifying-string-output-stream) string
     &optional (start 0) end)
  (let ((end (or end (length string))))
    (sb-thread:with-mutex ((notifying-output-lock stream))
      (write-string
       string (notifying-output-delegate stream)
       :start start :end end))
    (loop for index from start below end
          when (char= (char string index) #\Newline)
            do
            (sb-thread:signal-semaphore
             (notifying-output-notification stream))))
  string)

(defun notifying-output-string (stream)
  (sb-thread:with-mutex ((notifying-output-lock stream))
    (get-output-stream-string
     (notifying-output-delegate stream))))

(defun join-rpc-prompt-worker (state)
  (let ((thread
          (sb-thread:with-mutex
              ((cadr-cli::rpc-state-activity-lock state))
            (cadr-cli::rpc-state-prompt-thread state))))
    (when thread
      (sb-thread:join-thread thread))))
