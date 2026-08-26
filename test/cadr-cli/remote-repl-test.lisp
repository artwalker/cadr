(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sb-bsd-sockets))

(defun remote-repl-condition-message (thunk)
  (handler-case
      (progn (funcall thunk) nil)
    (cadr-ai:configuration-error (condition)
      (cadr-ai:cadr-error-message condition))))

(defvar *remote-repl-probe-value* "before")

(defun remote-repl-probe ()
  *remote-repl-probe-value*)

(defun remote-repl-test-model ()
  (cadr-ai:make-model
   :id "remote-repl-mock"
   :provider :openai
   :api :openai-responses
   :base-url "https://example.invalid"
   :max-tokens 1024))

(defun remote-repl-test-agent (session)
  (let ((responses
          (list
           (cadr-ai:make-assistant-message
            :content
            (list
             (cadr-ai:make-tool-call
              :id "repl-before"
              :name "remote-repl-probe"
              :arguments (cadr-ai::json-object)))
            :api :openai-responses
            :provider :openai
            :model "remote-repl-mock"
            :stop-reason :tool-use)
           (cadr-ai:make-assistant-message
            :content
            (list (cadr-ai:make-text-content :text "first done"))
            :api :openai-responses
            :provider :openai
            :model "remote-repl-mock"
            :stop-reason :stop)
           (cadr-ai:make-assistant-message
            :content
            (list
             (cadr-ai:make-tool-call
              :id "repl-after"
              :name "remote-repl-probe"
              :arguments (cadr-ai::json-object)))
            :api :openai-responses
            :provider :openai
            :model "remote-repl-mock"
            :stop-reason :tool-use)
           (cadr-ai:make-assistant-message
            :content
            (list (cadr-ai:make-text-content :text "second done"))
            :api :openai-responses
            :provider :openai
            :model "remote-repl-mock"
            :stop-reason :stop))))
    (cadr-agent:make-agent
     :provider :mock
     :model (remote-repl-test-model)
     :session session
     :tools
     (list
      (cadr-ai:make-tool
       :name "remote-repl-probe"
       :description "Call the named function binding"
       :parameters (cadr-ai::json-object "type" "object")
       :execution-mode :sequential
       :executor
       (lambda (call-id arguments)
         (declare (ignore call-id arguments))
         (list
          (cadr-ai:make-text-content
           :text (remote-repl-probe))))))
     :stream-function
     (lambda
         (provider model context on-event
          &key max-tokens temperature abort-p)
       (declare
        (ignore provider model context
                max-tokens temperature abort-p))
       (let ((message (pop responses)))
         (funcall
          on-event
          (cadr-ai:make-stream-event
           :type :start :message message))
         message)))))

(defun remote-repl-connect (port)
  (let ((socket
          (make-instance
           'sb-bsd-sockets:inet-socket
           :type :stream
           :protocol :tcp)))
    (sb-bsd-sockets:socket-connect
     socket
     (sb-bsd-sockets:make-inet-address "127.0.0.1")
     port)
    (values
     socket
     (sb-bsd-sockets:socket-make-stream
      socket
      :input t
      :output t
      :element-type '(unsigned-byte 8)
      :buffering :full))))

(defun remote-repl-eval (stream expression id)
  (uiop:symbol-call
   :slynk-rpc :write-message
   (list
    :emacs-rex
    (list
     (find-symbol "EVAL-AND-GRAB-OUTPUT" :slynk)
     expression)
    "COMMON-LISP-USER"
    t
    id)
   (find-package :cl-user)
   stream)
  (loop
    for message =
      (uiop:symbol-call
       :slynk-rpc :read-message
       stream (find-package :cl-user))
    when
      (and (consp message)
           (eq :return (first message))
           (eql id (third message)))
      return (second message)))

(defun remote-repl-tool-result-texts (agent)
  (loop
    for message in (cadr-agent:agent-messages agent)
    when (typep message 'cadr-ai:tool-result-message)
      collect
      (cadr-ai:text-content-text
       (first
        (cadr-ai:tool-result-message-content message)))))

(test goal10-slynk-cli-contract-is-explicit-and-strict
  (let ((arguments
          (cadr-cli::parse-cli-arguments
           '("--slynk" "4005" "--print" "hello"))))
    (is (= 4005
           (cadr-cli::cli-arguments-slynk-port arguments))))
  (is (null
       (cadr-cli::cli-arguments-slynk-port
        (cadr-cli::parse-cli-arguments nil))))
  (dolist
      (case
       '(("--slynk")
         ("--slynk" "nope")
         ("--slynk" "0")
         ("--slynk" "65536")
         ("--slynk" "+4005")
         ("--slynk" " 4005")))
    (is-true
     (remote-repl-condition-message
      (lambda ()
        (cadr-cli::parse-cli-arguments case)))))
  ;; --slynk remains a cadr-only flag and is parsed as before; the
  ;; baseline-aligned help text no longer advertises it (README does).
  (is-true
   (cadr-cli::cli-arguments-slynk-port
    (cadr-cli::parse-cli-arguments '("--slynk" "4005")))))

(test goal10-slynk-runtime-is-loopback-scoped-and-cleans-up
  ;; Let the kernel allocate the listening port inside Slynk's bind call.
  ;; Probing and releasing an ephemeral port before create-server races every
  ;; other process on the host and made this test fail deterministically under
  ;; parallel load with ADDRESS-IN-USE-ERROR.
  (let ((port nil))
    (with-test-directory (directory)
      (let* ((session
               (cadr-agent:create-session
                :directory directory
                :cwd directory
                :id "slynk-session"))
             (agent (remote-repl-test-agent session))
             (original-function
               (symbol-function 'remote-repl-probe)))
        (unwind-protect
             (progn
               (is (null (cadr-cli:active-agent)))
               (cadr-cli::call-with-remote-repl
                agent 0
                (lambda (started-port)
                  (setf port started-port)
                  (is-true (and (integerp port) (plusp port)))
                  (is (eq agent (cadr-cli:active-agent)))
                  (cadr-agent:agent-prompt agent "first")
                  (cadr-agent:agent-wait-for-idle agent)
                  (multiple-value-bind (socket stream)
                      (remote-repl-connect port)
                    (unwind-protect
                         (progn
                           (let ((address
                                   (nth-value
                                    0
                                    (sb-bsd-sockets:socket-peername
                                     socket))))
                             (is
                              (equalp
                               (sb-bsd-sockets:make-inet-address
                                "127.0.0.1")
                               address)))
                           (let ((result
                                   (remote-repl-eval
                                    stream
                                    "(cadr-agent:session-id (cadr-agent:agent-session (cadr-cli:active-agent)))"
                                    1)))
                             (is (eq :ok (first result)))
                             (is
                              (search
                               "slynk-session"
                               (princ-to-string result))))
                           (let ((result
                                   (remote-repl-eval
                                    stream
                                    "(setf (symbol-function 'cadr-cli/tests::remote-repl-probe) (lambda () \"after\"))"
                                    2)))
                             (is (eq :ok (first result)))))
                      (close stream)
                      (ignore-errors
                        (sb-bsd-sockets:socket-close socket))))
                  (cadr-agent:agent-prompt agent "second")
                  (cadr-agent:agent-wait-for-idle agent)
                  (is (eq agent (cadr-cli:active-agent)))
                  (is
                   (equal
                    '("before" "after")
                    (remote-repl-tool-result-texts agent)))
                  (is (string= "slynk-session"
                               (cadr-agent:session-id
                                (cadr-agent:agent-session agent))))))
               (is (null (cadr-cli:active-agent)))
               (let ((bound nil))
                 (dotimes (attempt 20)
                   (let ((socket
                           (make-instance
                            'sb-bsd-sockets:inet-socket
                            :type :stream
                            :protocol :tcp)))
                     (unwind-protect
                          (handler-case
                              (progn
                                (setf
                                 (sb-bsd-sockets:sockopt-reuse-address
                                  socket)
                                 t)
                                (sb-bsd-sockets:socket-bind
                                 socket
                                 (sb-bsd-sockets:make-inet-address
                                  "127.0.0.1")
                                 port)
                                (setf bound t)
                                (return))
                            (sb-bsd-sockets:address-in-use-error ()
                              (sleep 0.05)))
                       (sb-bsd-sockets:socket-close socket))))
                 (is-true bound
                          "Slynk still held 127.0.0.1:~D after stop-server"
                          port)))
          (setf
           (symbol-function 'remote-repl-probe)
           original-function))))))

(test goal10-slynk-bind-conflict-is-fatal
  (let ((port (unused-loopback-port))
        (socket
          (make-instance
           'sb-bsd-sockets:inet-socket
           :type :stream
           :protocol :tcp)))
    (unwind-protect
         (progn
           (sb-bsd-sockets:socket-bind
            socket
            (sb-bsd-sockets:make-inet-address "127.0.0.1")
            port)
           (sb-bsd-sockets:socket-listen socket 1)
           (signals cadr-ai:configuration-error
             (cadr-cli::call-with-remote-repl
              nil port (lambda (started-port)
                         (declare (ignore started-port))))))
      (sb-bsd-sockets:socket-close socket))))

(test goal10-slynk-init-is-isolated-from-the-build-users-home
  (let* ((root (asdf:system-source-directory "cadr-cli"))
         (test-script
           (uiop:read-file-string
            (merge-pathnames "scripts/test-cl-fiveam.sh" root)))
         (build-script
           (uiop:read-file-string
            (merge-pathnames "build.sh" root))))
    (is
     (search
      "HOME=\"$TEST_HOME\" \"$SBCL_COMMAND\""
      test-script))
    (is
     (search
      "XDG_CACHE_HOME=\"$TEST_HOME/.cache\""
      test-script))
    (is
     (search
      "ASDF_OUTPUT_TRANSLATIONS=\"/:$TEST_HOME/asdf-cache/\""
      test-script))
    (is
     (search
      "HOME=\"$BUILD_HOME\" \"$SBCL_COMMAND\""
      build-script))
    (is
     (search
      "XDG_CACHE_HOME=\"$BUILD_HOME/.cache\""
      build-script))
    (is
     (search
      "ASDF_OUTPUT_TRANSLATIONS=\"/:$BUILD_HOME/asdf-cache/\""
      build-script))
    (dolist (script (list test-script build-script))
      (is
       (search
        "QUICKLISP_SETUP_DIRECTORY=\"$(CDPATH= cd --"
        script)))
    (with-test-directory (directory)
      (let* ((host-home (merge-pathnames "host-home/" directory))
             (isolated-home
               (merge-pathnames "isolated-home/" directory))
             (sentinel (merge-pathnames "slynkrc-loaded" directory))
             (quicklisp
               (or (uiop:getenv "QUICKLISP_SETUP")
                   (namestring
                    (merge-pathnames
                     "quicklisp/setup.lisp"
                     (user-homedir-pathname)))))
             (previous-home (uiop:getenv "HOME")))
        (ensure-directories-exist
         (merge-pathnames "anchor" host-home))
        (ensure-directories-exist
         (merge-pathnames "anchor" isolated-home))
        (write-text
         (merge-pathnames ".slynkrc" host-home)
         (format
          nil
          "(with-open-file (stream ~S :direction :output :if-exists :supersede :if-does-not-exist :create) (write-line \"CADR-SLYNKRC-BUILD-LEAK\" stream))~%"
          (namestring sentinel)))
        (unwind-protect
             (progn
               (setf (uiop:getenv "HOME")
                     (namestring host-home))
               (is
                (zerop
                 (nth-value
                  2
                  (uiop:run-program
                   (list
                    "env"
                    (format nil "HOME=~A"
                            (namestring isolated-home))
                    (format nil "XDG_CACHE_HOME=~A"
                            (namestring
                             (merge-pathnames ".cache/" isolated-home)))
                    (format nil "ASDF_OUTPUT_TRANSLATIONS=/:~A"
                            (namestring
                             (merge-pathnames "asdf-cache/" isolated-home)))
                    "sbcl" "--noinform" "--non-interactive"
                    "--load" quicklisp
                    "--eval"
                    (format
                     nil
                     "(asdf:load-asd (truename ~S))"
                     (namestring
                      (merge-pathnames "cadr-core.asd" root)))
                    "--eval"
                    (format
                     nil
                     "(asdf:load-asd (truename ~S))"
                     (namestring
                      (merge-pathnames "cadr-ai.asd" root)))
                    "--eval"
                    (format
                     nil
                     "(asdf:load-asd (truename ~S))"
                     (namestring
                      (merge-pathnames "cadr-agent.asd" root)))
                    "--eval"
                    (format
                     nil
                     "(asdf:load-asd (truename ~S))"
                     (namestring
                      (merge-pathnames "cadr-tui.asd" root)))
                    "--eval"
                    (format
                     nil
                     "(asdf:load-asd (truename ~S))"
                     (namestring
                      (merge-pathnames "cadr-cli.asd" root)))
                    "--eval" "(asdf:load-system \"slynk/mrepl\")"
                    "--eval" "(asdf:load-system \"cadr-cli\")")
                   :output nil
                   :error-output nil)))))
          (setf (uiop:getenv "HOME") previous-home))
        (is-false (probe-file sentinel))))))
