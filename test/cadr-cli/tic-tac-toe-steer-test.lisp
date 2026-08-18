(in-package #:cadr-cli/tests)

(in-suite cadr-cli-suite)

(defun tic-tac-toe-steer-mock-model ()
  (cadr-ai:make-model
   :id "mock"
   :provider :openai
   :api :openai-responses
   :base-url "https://example.invalid"
   :max-tokens 1024))

(defun tic-tac-toe-steer-arguments (action)
  (let ((arguments (make-hash-table :test #'equal)))
    (setf (gethash "action" arguments) action)
    arguments))

(defmacro with-tic-tac-toe-extension ((host package) &body body)
  `(let ((root (asdf:system-source-directory "cadr-cli")))
     (with-test-directory (temporary)
       (let* ((output (make-string-output-stream))
              (target
                (merge-pathnames
                 "examples/extensions/tic-tac-toe.lisp" root))
              (manager
                (make-test-extension-manager
                 temporary (merge-pathnames "global/" temporary)
                 output (list target)))
              (report (cadr-cli::reload-cli-extensions manager))
              (,host (cadr-cli::cli-extension-manager-host manager)))
         (is (null (getf report :errors)))
         (setf (cadr-agent::extension-host-action-function ,host)
               (lambda (action arguments)
                 (declare (ignore action arguments))
                 nil))
         (let* ((bundles
                  (cadr-agent::extension-snapshot-bundles
                   (cadr-agent::extension-host-current-snapshot ,host)))
                (bundle
                  (find-if
                   (lambda (candidate)
                     (find "tic_tac_toe"
                           (cadr-agent::extension-bundle-tools candidate)
                           :key #'cadr-agent::extension-tool-definition-name
                           :test #'string=))
                   bundles))
                (,package
                  (and bundle
                       (cadr-agent::extension-bundle-package bundle))))
           (is (not (null bundle)))
           (is (not (null ,package)))
           ,@body)))))

(test tic-tac-toe-busy-trigger-turn-steers
  ;; Baseline agent-session.ts:1452-1457: isStreaming + triggerTurn
  ;; without deliverAs followUp steers. The shipped host used to error
  ;; with DELIVER-AS and leave a half-played board.
  (let* ((host (cadr-agent::make-extension-host))
         (agent
           (cadr-agent:make-agent
            :provider :mock
            :model (tic-tac-toe-steer-mock-model)
            :extension-host host
            :auto-compact-p nil)))
    (setf (cadr-agent:agent-busy-p agent) t)
    (finishes
      (cadr-agent::extension-host-send-message
       host
       (list :custom-type "tic-tac-toe-move"
             :content "Player X played at (row=1, col=1)."
             :display-p t)
       :trigger-turn-p t))
    (is (not (null (cadr-agent::agent-steering-queue agent))))
    (is (null (cadr-agent::agent-follow-up-queue agent)))))

(test tic-tac-toe-busy-trigger-turn-does-not-mention-deliver-as
  (let* ((host (cadr-agent::make-extension-host))
         (agent
           (cadr-agent:make-agent
            :provider :mock
            :model (tic-tac-toe-steer-mock-model)
            :extension-host host
            :auto-compact-p nil))
         (signaled nil))
    (setf (cadr-agent:agent-busy-p agent) t)
    (handler-case
        (cadr-agent::extension-host-send-message
         host
         (list :custom-type "tic-tac-toe-move"
               :content "steer me"
               :display-p t)
         :trigger-turn-p t)
      (error (condition)
        (setf signaled (princ-to-string condition))))
    (is (null signaled))
    (is (null (and signaled (search "DELIVER-AS" signaled))))))

(test tic-tac-toe-failed-send-does-not-leave-half-board
  (with-tic-tac-toe-extension (host package)
    (let* ((make-state
             (find-symbol "MAKE-TIC-TAC-TOE-STATE" package))
           (state-var (find-symbol "*TIC-TAC-TOE-STATE*" package))
           (apply (find-symbol "TIC-TAC-TOE-APPLY-USER-PLAY" package))
           (board-reader
             (find-symbol "TIC-TAC-TOE-STATE-BOARD" package))
           (turn-reader
             (find-symbol "TIC-TAC-TOE-STATE-CURRENT-TURN" package)))
      (setf (symbol-value state-var) (funcall make-state))
      (setf (cadr-agent::extension-host-send-message-function host)
            (lambda (message &key trigger-turn-p deliver-as)
              (declare (ignore message trigger-turn-p deliver-as))
              (error "injected send failure")))
      (signals error
        (funcall apply 1 1))
      (let ((state (symbol-value state-var)))
        (is (char= #\Space (aref (funcall board-reader state) 1 1)))
        (is (char= #\X (funcall turn-reader state)))))))

(test tic-tac-toe-busy-apply-user-play-steers-and-keeps-x
  (with-tic-tac-toe-extension (host package)
    (let* ((make-state
             (find-symbol "MAKE-TIC-TAC-TOE-STATE" package))
           (state-var (find-symbol "*TIC-TAC-TOE-STATE*" package))
           (apply (find-symbol "TIC-TAC-TOE-APPLY-USER-PLAY" package))
           (board-reader
             (find-symbol "TIC-TAC-TOE-STATE-BOARD" package))
           (turn-reader
             (find-symbol "TIC-TAC-TOE-STATE-CURRENT-TURN" package))
           (agent
             (cadr-agent:make-agent
              :provider :mock
              :model (tic-tac-toe-steer-mock-model)
              :auto-compact-p nil)))
      (setf (symbol-value state-var) (funcall make-state))
      (setf (cadr-agent::extension-host-send-message-function host)
            (lambda (message &key trigger-turn-p deliver-as)
              (cadr-agent::extension-host-send-message
               host message
               :trigger-turn-p trigger-turn-p
               :deliver-as deliver-as)))
      (cadr-agent::attach-extension-host host agent)
      (setf (cadr-agent:agent-busy-p agent) t)
      (finishes (funcall apply 1 1))
      (let ((state (symbol-value state-var)))
        (is (char= #\X (aref (funcall board-reader state) 1 1)))
        (is (char= #\O (funcall turn-reader state))))
      (is (not (null (cadr-agent::agent-steering-queue agent)))))))

(test tic-tac-toe-user-play-content-has-cursor-and-this-response
  (with-tic-tac-toe-extension (host package)
    (or host t)
    (let* ((make-state
             (find-symbol "MAKE-TIC-TAC-TOE-STATE" package))
           (state-var (find-symbol "*TIC-TAC-TOE-STATE*" package))
           (content-fn
             (find-symbol "TIC-TAC-TOE-USER-PLAY-CONTENT" package)))
      (setf (symbol-value state-var) (funcall make-state))
      (let ((content (funcall content-fn 1 1)))
        (is (search "Your cursor is at" content))
        (is (search "THIS response" content))
        (is (search "move_*" content))
        (is (search "play" content))))))

(test tic-tac-toe-render-call-is-action-not-json
  (with-tic-tac-toe-extension (host package)
    (or package t)
    (dolist (action '("play" "move_down"))
      (multiple-value-bind (rendered handled-p)
          (cadr-agent::render-extension-tool-call
           host "tic_tac_toe"
           (tic-tac-toe-steer-arguments action)
           (list :state (make-hash-table)))
        (is (not (null handled-p))
            "render-call did not handle ~A" action)
        (is (stringp rendered))
        (is (search (format nil "tic_tac_toe ~A" action) rendered))
        (is (null (search "{\"action\"" rendered)))
        (is (null (search ":play" rendered)))))))

(test tic-tac-toe-see-board-render-result-folds-cursor
  (with-tic-tac-toe-extension (host package)
    (or package t)
    (let ((result
           (cadr-ai:make-tool-result-message
            :tool-call-id "see-1"
            :tool-name "tic_tac_toe_see_board"
            :content
            (list
             (cadr-ai:make-text-content
              :text "Board ASCII would include -----+----- here"))
            :details (list :agent-row 2 :agent-column 1))))
      (multiple-value-bind (rendered handled-p)
          (cadr-agent::render-extension-tool-result
           host "tic_tac_toe_see_board" result
           '(:expanded-p nil)
           (list :state (make-hash-table)))
        (is (not (null handled-p)))
        (is (stringp rendered))
        (is (search "cursor (2,1)" rendered))
        (is (null (search "-----+-----" rendered)))))))

(test tic-tac-toe-overlay-follows-replaced-global-state
  ;; Reconstruct / session-tree replaces *tic-tac-toe-state* with a new
  ;; object. The overlay slot used to keep the old one, so after O's play
  ;; the painted frame still said Turn O / Agent is thinking.
  (with-tic-tac-toe-extension (host package)
    (or host t)
    (let* ((make-state
             (find-symbol "MAKE-TIC-TAC-TOE-STATE" package))
           (state-var (find-symbol "*TIC-TAC-TOE-STATE*" package))
           (comp-var (find-symbol "*TIC-TAC-TOE-COMPONENT*" package))
           (class (find-symbol "TIC-TAC-TOE-BOARD-COMPONENT" package))
           (board-reader
             (find-symbol "TIC-TAC-TOE-STATE-BOARD" package))
           (set-turn
             (fdefinition
              (list 'setf
                    (find-symbol "TIC-TAC-TOE-STATE-CURRENT-TURN"
                                 package))))
           (request
             (find-symbol "TIC-TAC-TOE-REQUEST-RENDER" package))
           (live
             (find-symbol "TIC-TAC-TOE-LIVE-STATE" package))
           (old (funcall make-state))
           (new (funcall make-state)))
      (setf (aref (funcall board-reader old) 1 1) #\X)
      (funcall set-turn #\O old)
      (setf (aref (funcall board-reader new) 1 1) #\X
            (aref (funcall board-reader new) 2 2) #\O)
      (funcall set-turn #\X new)
      (setf (symbol-value state-var) old
            (symbol-value comp-var)
            (make-instance class :state old))
      (setf (symbol-value state-var) new)
      (funcall request)
      (is (eq new (funcall live (symbol-value comp-var))))
      (let ((screen
              (format
               nil "~{~A~^~%~}"
               (cadr-tui:component-render
                (symbol-value comp-var) 80))))
        (is (search (string #\LARGE_CIRCLE) screen))
        (is (search (string #\BOX_DRAWINGS_LIGHT_DIAGONAL_CROSS) screen))
        (is (null (search "Agent is thinking" screen)))))))
