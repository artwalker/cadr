(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defparameter +goal9-a2-process-json-text+
  "The exit code was 7 and there are 12 steps and 3 files. 中文🙂")

(defun goal9-a2-process-faux-command (&rest arguments)
  (let* ((root
           (uiop:ensure-directory-pathname
            (asdf:system-source-directory "cadr-cli")))
         (fixture
           (merge-pathnames
            "test/fixtures/goal9-a2-faux-mode-child.lisp"
            root))
         (quicklisp
           (pathname
            (or (uiop:getenv "QUICKLISP_SETUP")
                (namestring
                 (merge-pathnames
                  "quicklisp/setup.lisp"
                  (user-homedir-pathname)))))))
    (append
     (list
      (or (uiop:getenv "SBCL") "sbcl")
      "--noinform"
      "--disable-debugger"
      "--script"
      (namestring fixture)
      (namestring root)
      (namestring quicklisp))
     arguments)))

(defun goal9-a2-run-process-faux-child (&rest arguments)
  (multiple-value-bind (output errors status)
      (uiop:run-program
       (apply #'goal9-a2-process-faux-command arguments)
       :output :string
       :error-output :string
       :ignore-error-status t)
    (values output errors status)))

(defun goal9-a2-process-json-lines (text)
  (loop for line in
          (uiop:split-string text :separator '(#\Newline))
        unless (zerop (length line))
          collect (cadr-ai::parse-json line)))

(defun goal9-a2-process-event-types (records)
  (loop for record in records
        for type = (cadr-ai::json-get record "type")
        unless (string= type "response")
          collect type))

(defun goal9-a2-process-update-types (records)
  (loop for record in records
        when (string=
              "message_update"
              (cadr-ai::json-get record "type"))
          collect
          (cadr-ai::json-get
           (cadr-ai::json-get record "assistantMessageEvent")
           "type")))

(defun goal9-a2-process-final-assistant-text (records)
  (let* ((record
           (find-if
            (lambda (candidate)
              (let ((message
                      (cadr-ai::json-get candidate "message")))
                (and
                 (string=
                  "message_end"
                  (cadr-ai::json-get candidate "type"))
                 (hash-table-p message)
                 (string=
                  "assistant"
                  (cadr-ai::json-get message "role")))))
            records
            :from-end t))
         (message
           (and record
                (cadr-ai::json-get record "message")))
         (content
           (and message
                (cadr-ai::json-get message "content"))))
    (and
     (vectorp content)
     (= 1 (length content))
     (cadr-ai::json-get (aref content 0) "text"))))

(defun goal9-a2-assert-process-faux-event-contract (records expected-text)
  (is
   (equal
    '("agent_start"
      "turn_start"
      "message_start"
      "message_end"
      "message_start"
      "message_update"
      "message_update"
      "message_update"
      "message_end"
      "turn_end"
      "agent_end"
      "agent_settled")
    (goal9-a2-process-event-types records)))
  (is
   (equal
    '("text_start" "text_delta" "text_end")
    (goal9-a2-process-update-types records)))
  (is
   (string=
    expected-text
    (goal9-a2-process-final-assistant-text records))))

(defun goal9-a2-join-thread-or-fail (thread label)
  (multiple-value-bind (value reason)
      (sb-thread:join-thread
       thread :timeout 10 :default :goal9-a2-timeout)
    (when (eq reason :timeout)
      (error "~A timed out without an explicit protocol completion" label))
    value))

(defun goal9-a2-wait-process-or-fail (process)
  (goal9-a2-join-thread-or-fail
   (sb-thread:make-thread
    (lambda () (uiop:wait-process process))
    :name "goal9 A2 faux child wait")
   "Faux mode child process"))

(test goal9-a2-process-faux-print-emits-only-final-text
  (multiple-value-bind (output errors status)
      (goal9-a2-run-process-faux-child
       "--print" "first" "second")
    (is (= 0 status))
    (is (string= (format nil "final-only~%") output))
    (is (string= "" errors))
    (is (not (search "intermediate" output)))
    (is (not (search "session>" output)))))

(test goal9-a2-process-faux-jsonl-preserves-exact-event-sequence
  (multiple-value-bind (output errors status)
      (goal9-a2-run-process-faux-child
       "--mode" "json" "json-prompt")
    (is (= 0 status))
    (is (string= "" errors))
    (let ((records
            (goal9-a2-process-json-lines output)))
      (is (= 12 (length records)))
      (goal9-a2-assert-process-faux-event-contract
       records +goal9-a2-process-json-text+))))

(test goal9-a2-process-faux-rpc-round-trips-request-response-and-events
  (let* ((process
           (uiop:launch-program
            (goal9-a2-process-faux-command "--mode" "rpc")
            :input :stream
            :output :stream
            :error-output :stream))
         (input (uiop:process-info-input process))
         (output (uiop:process-info-output process))
         (error-output
           (uiop:process-info-error-output process))
         (records nil)
         (reader-error nil)
         (settled-p nil)
         (reader nil))
    (unwind-protect
         (progn
           (setf
            reader
            (sb-thread:make-thread
             (lambda ()
               (handler-case
                   (loop
                     for line = (read-line output nil nil)
                     do
                     (unless line
                       (error
                        "Faux RPC child closed stdout before agent_settled"))
                     (let ((record
                             (cadr-ai::parse-json line)))
                       (push record records)
                       (when
                           (string=
                            "agent_settled"
                            (cadr-ai::json-get record "type"))
                         (setf settled-p t)
                         (return))))
                 (error (condition)
                   (setf reader-error condition))))
             :name "goal9 A2 faux RPC reader"))
           (write-line
            "{\"id\":\"state-1\",\"type\":\"get_state\"}"
            input)
           (write-line
            "{\"id\":\"prompt-1\",\"type\":\"prompt\",\"message\":\"rpc-prompt\"}"
            input)
           (finish-output input)
           (goal9-a2-join-thread-or-fail
            reader "Faux RPC agent_settled handshake")
           (when reader-error
             (error "Faux RPC reader failed: ~A" reader-error))
           (is (not (null settled-p)))
           (close input)
           (setf input nil)
           (let ((status
                   (goal9-a2-wait-process-or-fail process))
                 (errors
                   (uiop:slurp-stream-string error-output)))
             (is (= 0 status))
             (is (string= "" errors)))
           (setf records (nreverse records))
           (dolist (id '("state-1" "prompt-1"))
             (let ((responses
                     (remove-if-not
                      (lambda (record)
                        (and
                         (string= "response"
                                  (cadr-ai::json-get record "type"))
                         (string= id
                                  (cadr-ai::json-get record "id"))))
                      records)))
               (is (= 1 (length responses)))
               (is (eq t
                       (cadr-ai::json-get
                        (first responses) "success")))))
           (goal9-a2-assert-process-faux-event-contract
            records "rpc-final"))
      (when input
        (ignore-errors (close input)))
      (when (and process (uiop:process-alive-p process))
        (uiop:terminate-process process))
      (ignore-errors (close output))
      (ignore-errors (close error-output)))))
