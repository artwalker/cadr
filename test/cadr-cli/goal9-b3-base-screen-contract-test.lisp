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
              "Second concise answer."))))
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

(test goal9-b3-every-base-screen-state-has-an-exact-full-virtual-terminal-snapshot
  (let ((expected
          '(("cold-start" . "5102494F404ADB0CC36AEB3940AAE85830DD0CC5FE66127ECCDE0FE09202D23E")
            ("single-turn" . "77F4369AD0FD44A501A96F821867B62BAD01D5245E50BE4044E43B6343F465B5")
            ("multi-turn" . "92B70B0A5AEC03E479070C28FF7EAC3115525E1F1D02E3B7D47F1674747E7CF2")
            ("thinking" . "EF82D0A6E08641DB6F5FE3CDD386C7779C0046CB3E4C5BFFE52322EF5C1B97A6")
            ("tool-collapsed" . "469F3BAE304DAC110474BFF5CB01483B72E4992C22E4B5EF7777B06018EF7343")
            ("tool-expanded" . "DF40154B2A6E7B7F5E4E986B8498278881EF24CC7E98554509B2D84E23A5D0CC")
            ("active-status" . "22FB2A4E820335552735EA74D439FE697102732E4AD6EF2684D1115868828DD3")
            ("above-widget" . "723E9B4B442AC85D881479D6642FF7D90019AABE92593D604F5447A96885690A")
            ("below-widget" . "27DFC8E6EE6549CB326C15258E4E870CE16A6855A4D7100F04AF04CB34189BCB")
            ("overflow-scrolled-to-top" . "D15615BBF1F0A2F18155DAF639EAD4A2F49DAF29DA38ABF2D95A170242A5BEFD")
            ("narrow-width" . "A417E912682A61AEB48FD0653D9E2CF1BBECF46D34ED09F44F64896619948596"))))
    (dolist (case (goal9-b3-base-screen-cases))
      (is
       (string=
        (cdr (assoc (car case) expected :test #'string=))
        (goal9-b3-base-screen-sha256 case))))))
