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
  ;; Pin theme + capabilities so earlier suite tests cannot leak paint
  ;; into the SHA oracle (theme-keyed invent caches).
  (let ((original-theme (cadr-tui:current-theme))
        (original-capabilities
          (cadr-tui:get-terminal-capabilities))
        (caps
          (cadr-tui:make-terminal-capabilities
           :true-color-p t)))
    (cadr-tui:set-terminal-capabilities caps)
    (cadr-tui:set-current-theme :dark :capabilities caps)
    (unwind-protect
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
              renderer lines
              :cursor-row row :cursor-column column)
             (when scroll-to-top-p
               (cadr-tui:renderer-scroll-to-top renderer)
               (cadr-tui:render-frame
                renderer lines
                :cursor-row row :cursor-column column))
             (cadr-tui:virtual-terminal-snapshot terminal)))
      (cadr-tui:set-terminal-capabilities original-capabilities)
      (cadr-tui:set-current-theme original-theme))))

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
      :rows 11)
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
  ;; These invariants are transcribed from pi@13cbf77df, not inferred from
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
           (is (= 11 (length natural)))
           (is (= 1 (goal9-b3-screen-line-position
                     "Give one concise answer." natural)))
           (goal9-b3-assert-screen-lines-in-order
            natural
            '("Give one concise answer." "One concise answer."
              "────────────────" "/tmp/project" "mock-model")))
          ((string= name "viewport-overflow")
           ;; pi@13cbf77df root composition retains the complete natural
           ;; document; TuiMainScreen owns the bottom viewport.  These two
           ;; assertions deliberately prove both halves independently.
           (is (= 23 (length natural)))
           (is (= 1 (goal9-b3-screen-line-position
                     "Give one concise answer." natural)))
           (goal9-b3-assert-screen-lines-in-order
            natural
            '("Give one concise answer."
              "Finish with a third concise answer."
              "Third concise answer."
              "────────────────" "/tmp/project" "mock-model"))
           (is (= 14 (length screen)))
           (is (null (goal9-b3-screen-line-position
                      "Give one concise answer." screen)))
           (goal9-b3-assert-screen-lines-in-order
            screen
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
              "... (2 earlier lines, ctrl+o to expand)"
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
                         (first positions))))
             ;; Status shares the editor top border, not a free line.
             (is (find #\─ (nth (second positions) natural)))))
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
  ;; pi@13cbf77df setActiveStatusIndicator: session status embeds in the
  ;; editor top border when embedWorkingStatus is on, so widgets-above sit
  ;; directly above that border rather than below a free-standing status line.
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
                (and (search "Working..." line)
                     (find #\─ line)))
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
        '("" "above widget")
        (subseq plain (1+ answer) editor-top)))
      (is (search "── ⠋ Working..." (nth editor-top plain)))
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
                  (cdr overflow)))
         (overflow-screen
           (apply #'goal9-b3-base-screen-snapshot
                  (cdr overflow)))
         (overflow-screen-plain
           (goal9-b3-screen-text-lines overflow-screen)))
    (is (= 11 (length exact-lines)))
    (is (find-if (lambda (line) (search "Give one concise answer." line))
                 exact-lines))
    (is (find-if (lambda (line) (search "One concise answer." line))
                 exact-lines))
    (is (= 23 (length overflow-lines)))
    (is
     (find-if (lambda (line) (search "Give one concise answer." line))
              overflow-lines))
    (is
     (find-if (lambda (line) (search "Third concise answer." line))
              overflow-lines))
    (is (= 14 (length overflow-screen-plain)))
    (is (null
         (find-if (lambda (line) (search "Give one concise answer." line))
                  overflow-screen-plain)))
    (is
     (find-if (lambda (line) (search "Third concise answer." line))
              overflow-screen-plain))))

(test goal9-b3-every-base-screen-state-has-an-exact-full-virtual-terminal-snapshot
  (let ((expected
          '(("cold-start" . "9733E04F6DE7672AEEE75764D149C02DB371BBC574E60D8799993675E6A1330A")
            ("single-turn" . "82D3A3D1162A88AEC7639414079F536E60D3E59B2A5FE04945EE6DC8557BF0B7")
            ("multi-turn" . "99FC5B3F2A8F5F8D854064D8C0EB5890174DAD09F0C346BA8D048BFF4CB2012F")
            ("viewport-exact-fill" . "FE62F046A32FEAF0196939D9EDD4EE7B22F43205DD2307660C9951A7C9D74531")
            ("viewport-overflow" . "6FD90AA56FB8F791B62D1A1ACE1560C443CC8A10CCFF01B603E21179019761AA")
            ("thinking" . "029DB78936CC5F7F1A549ADBF4F6DA50F9968AD81F1398C6FD1672ED96BACD4F")
            ("tool-collapsed" . "A8341C5D2224C729E2677BB66550C9CF9165850CDA7DA87CE454DAC40F91B557")
            ("tool-expanded" . "200859C6BA14DE80DD2C7F432BEDD659C66B7A9B58EE5A50410A6E6AC59E03AF")
            ("active-status" . "BA6B9926CB43D750C8250862C5D3602AD4D087F98FAD5715BCBADC9402762B23")
            ("above-widget" . "1B2E5A37C04D1A3621244D7F2E094C5C7340772CB0C39A15F05D38A5B9A6C406")
            ("below-widget" . "D6303174613AA56EACF5A0F79927B771449EDCB93CBCED5F5B66AC124C537A40")
            ("overflow-scrolled-to-top" . "B18C207459A71545C6C17E34D3F7A5D7CFD14B379BF8D0FA6E9DBFFD24B0CE3E")
            ("narrow-width" . "3879C2A71C2BF04C357276800FEC1C848F9FE13453A84C9E8579F25A569F6539"))))
    (dolist (case (goal9-b3-base-screen-cases))
      (is
       (string=
        (cdr (assoc (car case) expected :test #'string=))
        (goal9-b3-base-screen-sha256 case))))))
