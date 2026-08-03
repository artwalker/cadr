#!/usr/bin/env -S sbcl --script

(require :asdf)

(let ((setup
        (or (uiop:getenv "QUICKLISP_SETUP")
            (namestring
             (merge-pathnames "quicklisp/setup.lisp"
                              (user-homedir-pathname))))))
  (unless (probe-file setup)
    (error "Quicklisp setup not found: ~A" setup))
  (load setup))

(defparameter *codex-probe-root*
  (uiop:pathname-parent-directory-pathname
   (uiop:pathname-directory-pathname
    (truename *load-truename*))))

(asdf:load-asd
 (truename (merge-pathnames "cadr-core.asd" *codex-probe-root*)))
(asdf:load-asd
 (truename (merge-pathnames "cadr-ai.asd" *codex-probe-root*)))
(asdf:load-system "cadr-ai")

(defconstant +codex-probe-default-turns+ 20)
(defconstant +codex-probe-default-max-tokens+ 64)

(defun codex-probe-required (arguments index flag)
  (or (nth index arguments)
      (error "Missing value for ~A" flag)))

(defun codex-probe-positive-integer (value flag)
  (let ((parsed (parse-integer value :junk-allowed t)))
    (unless (and parsed (plusp parsed)
                 (string= value (write-to-string parsed)))
      (error "Invalid ~A: ~A" flag value))
    parsed))

(defun codex-probe-print-help ()
  (write-line "Usage: scripts/codex-websocket-cached-probe.lisp [options]")
  (terpri)
  (write-line "Options:")
  (format t "  --turns <n>          Number of user turns. Default: ~D~%"
          +codex-probe-default-turns+)
  (write-line
   "  --transport <mode>   sse | websocket | websocket-cached | auto. Default: websocket-cached")
  (write-line
   "  --reasoning <level>  minimal | low | medium | high | xhigh | max. Default: low")
  (format t "  --max-tokens <n>     Max output tokens per model request. Default: ~D~%"
          +codex-probe-default-max-tokens+)
  (write-line "  --session-id <id>    Session id for websocket/cache state"))

(defun codex-probe-parse-arguments (arguments)
  (let ((turns +codex-probe-default-turns+)
        (transport :websocket-cached)
        (max-tokens +codex-probe-default-max-tokens+)
        (reasoning :low)
        (session-id
          (format nil "cadr-ai-codex-ws-cached-probe-~D"
                  (cadr-ai::unix-milliseconds))))
    (loop with index = 0
          while (< index (length arguments))
          for argument = (nth index arguments)
          do
          (cond
            ((string= argument "--help")
             (codex-probe-print-help)
             (uiop:quit 0))
            ((string= argument "--turns")
             (incf index)
             (setf turns
                   (codex-probe-positive-integer
                    (codex-probe-required arguments index argument)
                    argument)))
            ((string= argument "--transport")
             (incf index)
             (let ((value (codex-probe-required arguments index argument)))
               (unless (member value '("sse" "websocket" "websocket-cached" "auto")
                               :test #'string=)
                 (error "Invalid --transport: ~A" value))
               (setf transport
                     (intern (string-upcase value) :keyword))))
            ((string= argument "--reasoning")
             (incf index)
             (let ((value (codex-probe-required arguments index argument)))
               (unless (member value
                               '("minimal" "low" "medium" "high" "xhigh" "max")
                               :test #'string=)
                 (error "Invalid --reasoning: ~A" value))
               (setf reasoning (intern (string-upcase value) :keyword))))
            ((string= argument "--max-tokens")
             (incf index)
             (setf max-tokens
                   (codex-probe-positive-integer
                    (codex-probe-required arguments index argument)
                    argument)))
            ((string= argument "--session-id")
             (incf index)
             (setf session-id
                   (codex-probe-required arguments index argument)))
            (t (error "Unknown argument: ~A" argument)))
          (incf index))
    (list :turns turns :transport transport :max-tokens max-tokens
          :reasoning reasoning :session-id session-id)))

(defun codex-probe-build-prompt (turn)
  (let ((marker
          (format nil "TURN-~2,'0D-MARKER-~D"
                  turn (mod (+ (* turn 17) 13) 97))))
    (values
     (with-output-to-string (output)
       (format output
               "This is an automated OpenAI Codex Responses websocket cache probe.~%Task for turn ~D: call deterministic_probe exactly once before your final answer.~%Use tool arguments: turn=~D, marker=~A~%After the tool result arrives, reply exactly: TURN ~D OK ~A~%The following repeated block is intentional benchmark padding.~%"
               turn turn marker turn marker)
       (loop for index from 1 to 180
             do (format output
                        "Turn ~D synthetic record ~3,'0D: alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron pi rho sigma tau upsilon phi chi psi omega.~%"
                        turn index)))
     marker)))

(defun codex-probe-tool ()
  (cadr-ai:make-tool
   :name "deterministic_probe"
   :description
   "Mandatory benchmark tool. Call exactly once with the turn and marker from the user prompt."
   :parameters
   (cadr-ai::json-object
    "type" "object"
    "properties"
    (cadr-ai::json-object
     "turn" (cadr-ai::json-object "type" "number")
     "marker" (cadr-ai::json-object "type" "string"))
    "required" (vector "turn" "marker")
    "additionalProperties" nil)))

(defun codex-probe-tool-result (call)
  (cadr-ai:make-tool-result-message
   :tool-call-id (cadr-ai:tool-call-id call)
   :tool-name (cadr-ai:tool-call-name call)
   :content
   (list
    (cadr-ai:make-text-content
     :text
     (format nil "deterministic_probe_result ~A fixed=OK"
             (cadr-ai::stringify-json
              (cadr-ai:tool-call-arguments call)))))
   :details '(:fixed "OK")
   :is-error nil))

(defun codex-probe-average (values)
  (/ (reduce #'+ values :initial-value 0d0)
     (max 1 (length values))))

(defun codex-probe-percentile (values percentile)
  (if (null values)
      0d0
      (let* ((sorted (sort (copy-list values) #'<))
             (index
               (min (1- (length sorted))
                    (max 0 (1- (ceiling (* (/ percentile 100d0)
                                           (length sorted))))))))
        (nth index sorted))))

(defun codex-probe-stat-delta (after before key)
  (- (getf after key 0) (getf before key 0)))

(defun codex-probe-auth-credential ()
  (let ((path
          (merge-pathnames ".cadr/auth.json" (user-homedir-pathname))))
    (unless (probe-file path)
      (error "No cadr auth storage found at ~A" path))
    (cadr-ai:resolve-oauth-credential
     path :openai-codex #'cadr-ai:refresh-openai-oauth-credential)))

(defun codex-probe-main ()
  (let* ((options
           (codex-probe-parse-arguments
            (uiop:command-line-arguments)))
         (turns (getf options :turns))
         (transport (getf options :transport))
         (max-tokens (getf options :max-tokens))
         (reasoning (getf options :reasoning))
         (session-id (getf options :session-id))
         (credential (codex-probe-auth-credential))
         (metadata (cadr-ai:find-model-metadata :openai-codex "gpt-5.5"))
         (model (cadr-ai::model-from-metadata metadata))
         (provider
           (cadr-ai:make-openai-codex-provider
            :oauth-access-token (cadr-ai:oauth-credential-access credential)
            :oauth-account-id (cadr-ai:oauth-credential-account-id credential)))
         (context
           (cadr-ai:make-context
            :system-prompt
            "You are participating in a benchmark. For each benchmark turn, call deterministic_probe exactly once before the final answer. Keep final answers minimal."
            :tools (list (codex-probe-tool))))
         (elapsed nil))
    (setf (cadr-ai:model-max-tokens model) max-tokens)
    (cadr-ai:reset-openai-codex-websocket-debug-stats session-id)
    (format t "provider openai-codex, model gpt-5.5~%sessionId ~A~%turns ~D, transport ~A, reasoning ~A, maxTokens ~D~%~%"
            session-id turns (string-downcase (symbol-name transport))
            (string-downcase (symbol-name reasoning)) max-tokens)
    (unwind-protect
         (loop for turn from 1 to turns
               do
               (multiple-value-bind (prompt marker)
                   (codex-probe-build-prompt turn)
                 (declare (ignore marker))
                 (setf (cadr-ai:context-messages context)
                       (append (cadr-ai:context-messages context)
                               (list (cadr-ai:make-user-message :content prompt))))
                 (let ((before
                         (or
                          (cadr-ai:get-openai-codex-websocket-debug-stats
                           session-id)
                          nil))
                       (started (get-internal-real-time))
                       (requests 0)
                       (assistant-count 0)
                       (tool-results 0)
                       (final-text "")
                       (turn-input 0)
                       (turn-output 0)
                       (turn-cache-read 0)
                       (turn-cache-write 0))
                   (loop
                     (incf requests)
                     (let* ((message
                              (cadr-ai:stream-chat
                               provider model context
                               (lambda (event) (declare (ignore event)))
                               :session-id session-id
                               :transport transport
                               :reasoning reasoning
                               :max-tokens max-tokens))
                            (usage (cadr-ai:assistant-message-usage message))
                            (calls
                              (remove-if-not
                               (lambda (block) (typep block 'cadr-ai:tool-call))
                               (cadr-ai:assistant-message-content message))))
                       (incf assistant-count)
                       (push message (cdr (last (cadr-ai:context-messages context))))
                       (incf turn-input (cadr-ai:usage-input usage))
                       (incf turn-output (cadr-ai:usage-output usage))
                       (incf turn-cache-read (cadr-ai:usage-cache-read usage))
                       (incf turn-cache-write (cadr-ai:usage-cache-write usage))
                       (format t
                               "turn ~2,'0D.~D | stop ~A | in ~D | out ~D | cache ~D/~D | tools ~D~%"
                               turn requests
                               (string-downcase
                                (symbol-name
                                 (cadr-ai:assistant-message-stop-reason message)))
                               (cadr-ai:usage-input usage)
                               (cadr-ai:usage-output usage)
                               (cadr-ai:usage-cache-read usage)
                               (cadr-ai:usage-cache-write usage)
                               (length calls))
                       (when (member (cadr-ai:assistant-message-stop-reason message)
                                     '(:error :aborted))
                         (error "~A"
                                (or (cadr-ai:assistant-message-error-message message)
                                    "Codex probe request failed")))
                       (if (null calls)
                           (progn
                             (setf final-text
                                   (string-trim
                                    '(#\Space #\Tab #\Return #\Newline)
                                    (cadr-ai:content-text
                                     (cadr-ai:assistant-message-content message))))
                             (return))
                           (dolist (call calls)
                             (setf (cadr-ai:context-messages context)
                                   (append
                                    (cadr-ai:context-messages context)
                                    (list (codex-probe-tool-result call))))
                             (incf tool-results)))
                       (when (> requests 4)
                         (error "Too many requests for turn ~D" turn))))
                   (let* ((elapsed-ms
                            (* 1000d0
                               (/ (- (get-internal-real-time) started)
                                  internal-time-units-per-second)))
                          (after
                            (or
                             (cadr-ai:get-openai-codex-websocket-debug-stats
                              session-id)
                             nil)))
                     (push elapsed-ms elapsed)
                     (format t
                             "turn ~2,'0D agg | elapsed ~,1Fs | assistant ~D | toolResults ~D | in ~D | out ~D | cache ~D/~D | ws requests ~D | new/reused ~D/~D | cached ~D | store ~D | full/delta ~D/~D | final ~S~%"
                             turn (/ elapsed-ms 1000d0) assistant-count tool-results
                             turn-input turn-output turn-cache-read turn-cache-write
                             (codex-probe-stat-delta after before :requests)
                             (codex-probe-stat-delta after before :connections-created)
                             (codex-probe-stat-delta after before :connections-reused)
                             (codex-probe-stat-delta after before :cached-context-requests)
                             (codex-probe-stat-delta after before :store-true-requests)
                             (codex-probe-stat-delta after before :full-context-requests)
                             (codex-probe-stat-delta after before :delta-requests)
                             (subseq final-text 0 (min 80 (length final-text))))))))
      (cadr-ai:close-openai-codex-websocket-sessions session-id))
    (setf elapsed (nreverse elapsed))
    (let ((stats
            (cadr-ai:get-openai-codex-websocket-debug-stats session-id)))
      (format t
              "~%timing | turns ~D | total ~,1Fs | avg ~,2Fs | p50 ~,2Fs | p95 ~,2Fs | max ~,2Fs~%"
              (length elapsed) (/ (reduce #'+ elapsed) 1000d0)
              (/ (codex-probe-average elapsed) 1000d0)
              (/ (codex-probe-percentile elapsed 50) 1000d0)
              (/ (codex-probe-percentile elapsed 95) 1000d0)
              (/ (reduce #'max elapsed) 1000d0))
      (format t
              "transport summary | requested ~A | observed ~A | storeTrue ~D/~D | full/delta ~D/~D | connections created/reused ~D/~D | lastPreviousResponseId ~A~%"
              (string-downcase (symbol-name transport))
              (if (and stats (plusp (getf stats :requests 0)))
                  "websocket" "sse/no-websocket")
              (getf stats :store-true-requests 0) (getf stats :requests 0)
              (getf stats :full-context-requests 0)
              (getf stats :delta-requests 0)
              (getf stats :connections-created 0)
              (getf stats :connections-reused 0)
              (or (getf stats :last-previous-response-id) "n/a")))))

(handler-case
    (codex-probe-main)
  (error (condition)
    (format *error-output* "~A~%" condition)
    (uiop:quit 1)))
