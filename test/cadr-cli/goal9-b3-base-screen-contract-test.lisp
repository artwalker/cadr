(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defun goal9-b3-base-screen-state (&key entries startup status
                                        widgets-above widgets-below)
  (let ((state
          (cadr-cli::make-tui-state
           :model "mock-model"
           :provider :faux
           :cwd "/tmp/project"
           :context-window 200000
           :startup-compact-lines startup)))
    (cadr-cli::replace-tui-entries state entries)
    (setf
     (cadr-cli::tui-state-status-message state) status
     (cadr-cli::tui-state-widgets-above state) widgets-above
     (cadr-cli::tui-state-widgets-below state) widgets-below)
    state))

(defun goal9-b3-base-screen-user (text)
  (cadr-cli::make-tui-entry :type :user :text text))

(defun goal9-b3-base-screen-assistant
    (text &optional thinking)
  (cadr-cli::make-tui-entry
   :type :assistant
   :text text
   :content-blocks
   (append
    (and thinking
         (list (cons :assistant-thinking thinking)))
    (list (cons :assistant text)))))

(defun goal9-b3-base-screen-tool (collapsed-p)
  (cadr-cli::make-tui-entry
   :type :tool
   :tool-block
   (cadr-tui:make-tool-block
    :name "bash"
    :summary "printf lines"
    :output
    (format nil "one~%two~%three~%four~%five~%six~%seven")
    :status :complete
    :started-at 10d0
    :ended-at 10.25d0
    :collapsed-p collapsed-p)))

(defun goal9-b3-base-screen-snapshot
    (state &key (width 80) (rows 24) scroll-to-top-p)
  (let* ((editor (cadr-tui:make-multiline-editor))
         (terminal
           (cadr-tui:make-virtual-terminal
            :columns width :rows rows))
         (renderer
           (cadr-tui:make-terminal-renderer
            terminal :alt-p scroll-to-top-p)))
    (when scroll-to-top-p
      (cadr-tui:renderer-start renderer))
    (multiple-value-bind (lines row column)
        (cadr-cli::render-tui-state
         state editor width rows
         :full-document-p scroll-to-top-p
         :now 20d0
         :spinner-frame "⠋")
      (cadr-tui:render-frame
       renderer lines :cursor-row row :cursor-column column)
      (when scroll-to-top-p
        (cadr-tui:renderer-scroll-to-top renderer)
        (cadr-tui:render-frame
         renderer lines :cursor-row row :cursor-column column))
      (cadr-tui:virtual-terminal-snapshot terminal))))

(defun goal9-b3-base-screen-sha256 (case)
  (let ((octets
          (cadr-ai::sha256-bytes
           (cadr-ai::ensure-octets
            (format nil "~{~A~^~%~}"
                    (apply #'goal9-b3-base-screen-snapshot
                           (cdr case)))))))
    (format nil "~{~2,'0X~}" (coerce octets 'list))))

(defun goal9-b3-base-screen-plain-lines
    (state &key (width 80) (rows 24) full-document-p)
  (multiple-value-bind (lines row column)
      (cadr-cli::render-tui-state
       state (cadr-tui:make-multiline-editor)
       width rows :full-document-p full-document-p
       :spinner-frame "⠋")
    (declare (ignore row column))
    (mapcar #'cadr-tui:strip-terminal-sequences lines)))

(defun goal9-b3-base-screen-cases ()
  (let* ((single
           (list
            (goal9-b3-base-screen-user "Give one concise answer.")
            (goal9-b3-base-screen-assistant
             "One concise answer.")))
         (multi
           (append
            single
            (list
             (goal9-b3-base-screen-user
              "Now give a second concise answer.")
             (goal9-b3-base-screen-assistant
              "Second concise answer.")
             (goal9-b3-base-screen-user
              "Finish with a third concise answer.")
             (goal9-b3-base-screen-assistant
              "Third concise answer."))))
         (tool-prefix
           (list
            (goal9-b3-base-screen-user "Run the command.")
            (cadr-cli::make-tui-entry
             :type :assistant
             :has-tool-calls-p t))))
    (list
     (list
      "cold-start"
      (goal9-b3-base-screen-state
       :startup
       '("cadr v0.2.0"
         "escape interrupt · ctrl+c/ctrl+d clear/exit · / commands · ! bash · ctrl+o more"
         "Press ctrl+o to show full startup help and loaded resources."
         ""
         "Cadr can explain its own features and look up its docs.")))
     (list
      "single-turn"
      (goal9-b3-base-screen-state :entries single))
     (list
      "multi-turn"
      (goal9-b3-base-screen-state :entries multi)
      :rows 28)
     (list
      "viewport-exact-fill"
      (goal9-b3-base-screen-state :entries single)
      :rows 13)
     (list
      "viewport-overflow"
      (goal9-b3-base-screen-state :entries multi)
      :rows 14)
     (list
      "thinking"
      (goal9-b3-base-screen-state
       :entries
       (list
        (goal9-b3-base-screen-user "Think, then answer.")
        (goal9-b3-base-screen-assistant
         "The answer is stable."
         "Checking the exact contract."))))
     (list
      "tool-collapsed"
      (goal9-b3-base-screen-state
       :entries
       (append tool-prefix
               (list (goal9-b3-base-screen-tool t)))))
     (list
      "tool-expanded"
      (goal9-b3-base-screen-state
       :entries
       (append tool-prefix
               (list (goal9-b3-base-screen-tool nil)))))
     (list
      "active-status"
      (goal9-b3-base-screen-state
       :entries single :status "Working..."))
     (list
      "above-widget"
      (goal9-b3-base-screen-state
       :entries single
       :widgets-above
       '(("extension" "above editor widget"))))
     (list
      "below-widget"
      (goal9-b3-base-screen-state
       :entries single
       :widgets-below
       '(("extension" "below editor widget"))))
     (list
      "overflow-scrolled-to-top"
      (goal9-b3-base-screen-state
       :entries
       (loop for index from 1 to 16
             collect
             (cadr-cli::make-tui-entry
              :type :notice
              :text (format nil "transcript line ~2,'0D" index))))
      :width 52 :rows 14 :scroll-to-top-p t)
     (list
      "narrow-width"
      (goal9-b3-base-screen-state
       :entries
       (list
        (goal9-b3-base-screen-user
         "A narrow terminal wraps this user message.")
        (goal9-b3-base-screen-assistant
         "The assistant response wraps too.")))
      :width 32 :rows 14))))

(defun goal9-b3-screen-text-lines (lines)
  (mapcar
   (lambda (line)
     (string-right-trim
      " "
      (cadr-tui:strip-terminal-sequences line)))
   lines))

(defun goal9-b3-screen-line-position
    (needle lines &key (start 0))
  (position-if
   (lambda (line) (search needle line))
   lines :start start))

(defun goal9-b3-assert-screen-lines-in-order
    (lines needles)
  (let ((start 0)
        (positions nil))
    (dolist (needle needles)
      (let ((position
              (goal9-b3-screen-line-position
               needle lines :start start)))
        (is (not (null position)))
        (when position
          (push position positions)
          (setf start (1+ position)))))
    (nreverse positions)))

(defun goal9-b3-base-screen-case-text-lines (case)
  (goal9-b3-screen-text-lines
   (apply #'goal9-b3-base-screen-snapshot (cdr case))))

(defun goal9-b3-base-screen-case-natural-lines (case)
  (let ((state (second case))
        (arguments (copy-list (cddr case))))
    (remf arguments :scroll-to-top-p)
    (apply #'goal9-b3-base-screen-plain-lines
           state arguments)))

(test goal9-b3-every-base-screen-sha-has-a-baseline-derived-semantic-oracle
  ;; These invariants are transcribed from pi@74caa2649, not inferred from
  ;; Cadr's hashes: root child order and natural height come from
  ;; interactive-mode.ts:734-746 and tui.ts:235-244; assistant spacing from
  ;; assistant-message.ts:89-169; tool framing/preview from
  ;; tool-execution.ts:63-75 and bash.ts:199,234-310;
  ;; viewport behavior from TuiMainScreen.ts:162-212,354-370 and
  ;; TuiAltScreen.ts:350-389.
  (let* ((cases (goal9-b3-base-screen-cases))
         (names (mapcar #'car cases)))
    ;; A future SHA case cannot land without adding an independent oracle.
    (is
     (equal
      '("cold-start" "single-turn" "multi-turn"
        "viewport-exact-fill" "viewport-overflow" "thinking"
        "tool-collapsed" "tool-expanded" "active-status"
        "above-widget" "below-widget" "overflow-scrolled-to-top"
        "narrow-width")
      names))
    (dolist (case cases)
      (let* ((name (car case))
             (screen
               (goal9-b3-base-screen-case-text-lines case))
             (natural
               (unless (string= name "overflow-scrolled-to-top")
                 (goal9-b3-base-screen-case-natural-lines case))))
        (cond
          ((string= name "cold-start")
           (is (= 1 (goal9-b3-screen-line-position
                     "cadr v0.2.0" screen)))
           (goal9-b3-assert-screen-lines-in-order
            screen
            '("cadr v0.2.0"
              "Cadr can explain its own features"
              "────────────────"
              "/tmp/project"
              "mock-model")))
          ((string= name "single-turn")
           (is (= 1 (goal9-b3-screen-line-position
                     "Give one concise answer." natural)))
           (is (< (length natural) 24))
           (goal9-b3-assert-screen-lines-in-order
            natural
            '("Give one concise answer." "One concise answer."
              "────────────────" "/tmp/project" "mock-model")))
          ((string= name "multi-turn")
           (is (= 1 (goal9-b3-screen-line-position
                     "Give one concise answer." natural)))
           (is (< (length natural) 28))
           (goal9-b3-assert-screen-lines-in-order
            natural
            '("Give one concise answer." "One concise answer."
              "Now give a second concise answer."
              "Second concise answer."
              "Finish with a third concise answer."
              "Third concise answer."
              "────────────────" "/tmp/project" "mock-model")))
          ((string= name "viewport-exact-fill")
           (is (= 13 (length natural)))
           (is (= 1 (goal9-b3-screen-line-position
                     "Give one concise answer." natural)))
           (goal9-b3-assert-screen-lines-in-order
            natural
            '("Give one concise answer." "One concise answer."
              "────────────────" "/tmp/project" "mock-model")))
          ((string= name "viewport-overflow")
           (is (= 14 (length natural)))
           (is (null (goal9-b3-screen-line-position
                      "Give one concise answer." natural)))
           (goal9-b3-assert-screen-lines-in-order
            natural
            '("Finish with a third concise answer."
              "Third concise answer."
              "────────────────" "/tmp/project" "mock-model")))
          ((string= name "thinking")
           (let ((positions
                   (goal9-b3-assert-screen-lines-in-order
                    natural
                    '("Think, then answer."
                      "Checking the exact contract."
                      "The answer is stable."
                      "────────────────"))))
             (is (= 2 (- (third positions)
                         (second positions))))))
          ((string= name "tool-collapsed")
           (goal9-b3-assert-screen-lines-in-order
            natural
            '("Run the command." "$ printf lines"
              "... (2 earlier lines, to expand)"
              "three" "seven" "Took 0.3s"
              "────────────────"))
           (is
            (null
             (find
              "one" natural :test #'string=
              :key (lambda (line) (string-trim " " line)))))
           (is
            (null
             (find
              "two" natural :test #'string=
              :key (lambda (line) (string-trim " " line))))))
          ((string= name "tool-expanded")
           (goal9-b3-assert-screen-lines-in-order
            natural
            '("Run the command." "$ printf lines"
              "one" "two" "three" "seven" "Took 0.3s"
              "────────────────"))
           (is (null
                (goal9-b3-screen-line-position
                 "earlier lines" natural))))
          ((string= name "active-status")
           (let ((positions
                   (goal9-b3-assert-screen-lines-in-order
                    natural
                    '("One concise answer." "Working..."
                      "────────────────" "/tmp/project"))))
             (is (= 2 (- (second positions)
                         (first positions))))))
          ((string= name "above-widget")
           (let ((positions
                   (goal9-b3-assert-screen-lines-in-order
                    natural
                    '("One concise answer." "above editor widget"
                      "────────────────" "/tmp/project"))))
             (is (= 1 (- (third positions)
                         (second positions))))))
          ((string= name "below-widget")
           (let* ((borders
                    (loop for line in natural
                          for index from 0
                          when (and (plusp (length line))
                                    (every
                                     (lambda (character)
                                       (char= character #\─))
                                     line))
                            collect index))
                  (widget
                    (goal9-b3-screen-line-position
                     "below editor widget" natural))
                  (footer
                    (goal9-b3-screen-line-position
                     "/tmp/project" natural)))
             (is (= 2 (length borders)))
             (is (= widget (1+ (second borders))))
             (is (= footer (1+ widget)))))
          ((string= name "overflow-scrolled-to-top")
           (is (= 14 (length screen)))
           (is (= 1 (goal9-b3-screen-line-position
                     "transcript line 01" screen)))
           (is (= 13 (goal9-b3-screen-line-position
                      "transcript line 07" screen)))
           (is (null (goal9-b3-screen-line-position
                      "transcript line 08" screen)))
           (is (null (goal9-b3-screen-line-position
                      "/tmp/project" screen))))
          ((string= name "narrow-width")
           (is (= 14 (length screen)))
           (is
            (every
             (lambda (line)
               (<= (cadr-tui:visible-width line) 32))
             screen))
           (goal9-b3-assert-screen-lines-in-order
            screen
            '("A narrow terminal wraps this"
              "user message."
              "The assistant response wraps"
              "too."
              "────────────────"
              "/tmp/project"
              "mock-model")))
          (t
           (fail "Missing semantic oracle for base screen ~A" name)))))))

(test goal9-b3-base-screen-above-editor-spacer-matches-baseline-composition
  (is
   (equal
    '("")
    (cadr-cli::render-tui-widgets
     nil 40 :spacer-when-empty-p t :leading-spacer-p t)))
  (is
   (equal
    '("" "alpha" "beta")
    (cadr-cli::render-tui-widgets
     '(("b" "beta") ("a" "alpha")) 40
     :spacer-when-empty-p t :leading-spacer-p t)))
  (is
   (null
    (cadr-cli::render-tui-widgets
     nil 40 :spacer-when-empty-p nil :leading-spacer-p nil)))
  (is
   (equal
    '("alpha")
    (cadr-cli::render-tui-widgets
     '(("a" "alpha")) 40
     :spacer-when-empty-p nil :leading-spacer-p nil))))

(test goal9-b3-base-screen-status-widget-editor-footer-order-is-exact
  (let* ((state
           (goal9-b3-base-screen-state
            :entries
            (list
             (goal9-b3-base-screen-assistant "final answer"))
            :status "Working..."
            :widgets-above '(("a" "above widget"))
            :widgets-below '(("b" "below widget"))))
         (plain
           (goal9-b3-base-screen-plain-lines
            state :width 60 :rows 20
            :full-document-p t)))
    (let* ((answer
             (position-if
              (lambda (line) (search "final answer" line))
              plain))
           (editor-top
             (position-if
              (lambda (line)
                (and (plusp (length line))
                     (every (lambda (character)
                              (char= character #\─))
                            line)))
              plain :start (1+ answer)))
           (editor-bottom
             (position-if
              (lambda (line)
                (and (plusp (length line))
                     (every (lambda (character)
                              (char= character #\─))
                            line)))
              plain :start (1+ editor-top))))
      (is
       (equal
        '("" "⠋ Working..." "" "above widget")
        (subseq plain (1+ answer) editor-top)))
      (is (string= "below widget"
                   (nth (1+ editor-bottom) plain)))
      (is
       (search "/tmp/project"
               (nth (+ editor-bottom 2) plain))))))

(test goal9-b3-short-conversation-composition-stacks-from-the-top
  (dolist
      (entry-count '(2 6))
    (let* ((entries
             (subseq
              (list
               (goal9-b3-base-screen-user "First question.")
               (goal9-b3-base-screen-assistant "First answer.")
               (goal9-b3-base-screen-user "Second question.")
               (goal9-b3-base-screen-assistant "Second answer.")
               (goal9-b3-base-screen-user "Third question.")
               (goal9-b3-base-screen-assistant "Third answer."))
              0 entry-count))
           (state
             (goal9-b3-base-screen-state :entries entries))
           (width 80)
           (rows 32))
      (multiple-value-bind (lines cursor-row cursor-column)
          (cadr-cli::render-tui-state
           state (cadr-tui:make-multiline-editor)
           width rows)
        (declare (ignore cursor-column))
        (let* ((plain
                 (mapcar #'cadr-tui:strip-terminal-sequences lines))
               (first-message
                 (position-if
                  (lambda (line)
                    (search "First question." line))
                  plain))
               (editor-top
                 (position-if
                  (lambda (line)
                    (and (plusp (length line))
                         (every
                          (lambda (character)
                            (char= character #\─))
                          line)))
                  plain)))
          ;; User-message output padding is part of the component.  What must
          ;; disappear is the viewport-sized filler before the component.
          (is (= 1 first-message))
          (is (< editor-top (1- rows)))
          (is (< cursor-row (1- rows)))
          (is (< (length lines) rows)))))))

(test goal9-b3-viewport-exact-fill-and-overflow-follow-baseline-scroll-policy
  (let* ((cases (goal9-b3-base-screen-cases))
         (exact (find "viewport-exact-fill" cases
                      :key #'car :test #'string=))
         (overflow (find "viewport-overflow" cases
                         :key #'car :test #'string=))
         (exact-lines
           (apply #'goal9-b3-base-screen-plain-lines
                  (cdr exact)))
         (overflow-lines
           (apply #'goal9-b3-base-screen-plain-lines
                  (cdr overflow))))
    (is (= 13 (length exact-lines)))
    (is (find-if (lambda (line) (search "Give one concise answer." line))
                 exact-lines))
    (is (find-if (lambda (line) (search "One concise answer." line))
                 exact-lines))
    (is (= 14 (length overflow-lines)))
    (is (null
         (find-if (lambda (line) (search "Give one concise answer." line))
                  overflow-lines)))
    (is
     (find-if (lambda (line) (search "Third concise answer." line))
              overflow-lines))))

(test goal9-b3-every-base-screen-state-has-an-exact-full-virtual-terminal-snapshot
  (let ((expected
          '(("cold-start" . "7D6B66412D3734322CB29B8E24C95C5978B4FACC77FB89A811A6D58AB3F27D7B")
            ("single-turn" . "0732A443161016877BD9A9FC46AE593AAE2110B0ACE7F903635EA3CBB3B2A48C")
            ("multi-turn" . "DC4A5F74E3FCB6EFDAAA1A55E3555F34FEF8D686A358F00ADECA00BD00180104")
            ("viewport-exact-fill" . "E0493BAA8CFBBC1DF15E3254EF007840E1571AE163AF3010A04552FC71B59A7F")
            ("viewport-overflow" . "53E1B55B933BEBCE43EDE639DB093965B148044B34191193152C067D1647CBE8")
            ("thinking" . "AB0F8F4025EE9D5E026FF2FDC8AB8ABBF452926F61223944F965CFA8E567E310")
            ("tool-collapsed" . "469F3BAE304DAC110474BFF5CB01483B72E4992C22E4B5EF7777B06018EF7343")
            ("tool-expanded" . "DF40154B2A6E7B7F5E4E986B8498278881EF24CC7E98554509B2D84E23A5D0CC")
            ("active-status" . "5B07189D441990503213180DB156B1106C0FDD95A83109BD6E93C13E84576BA1")
            ("above-widget" . "3AF104FBC8FF61878FF37623FFB539799A28BEE22BE538726F08D2DF277A53D0")
            ("below-widget" . "DC70F236342B1A935721471779EBCFA86DD0EFBE5CD4B9695148D5D33FE794D4")
            ("overflow-scrolled-to-top" . "D15615BBF1F0A2F18155DAF639EAD4A2F49DAF29DA38ABF2D95A170242A5BEFD")
            ("narrow-width" . "A417E912682A61AEB48FD0653D9E2CF1BBECF46D34ED09F44F64896619948596"))))
    (dolist (case (goal9-b3-base-screen-cases))
      (is
       (string=
        (cdr (assoc (car case) expected :test #'string=))
        (goal9-b3-base-screen-sha256 case))))))
