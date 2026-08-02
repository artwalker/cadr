(in-package #:cadr-cli/tests)

(in-suite cadr-cli-suite)

(defclass goal12-extension-component (cadr-tui:component)
  ((text
    :initarg :text
    :reader goal12-extension-component-text)
   (done-function
    :initarg :done-function
    :initform nil
    :reader goal12-extension-component-done-function)
   (disposed-p
    :initform nil
    :accessor goal12-extension-component-disposed-p)))

(defmethod cadr-tui:component-render
    ((component goal12-extension-component) width &key focused-p)
  (declare (ignore width focused-p))
  (list (goal12-extension-component-text component)))

(defmethod cadr-tui:component-handle-event
    ((component goal12-extension-component) event)
  (when (and (member (cadr-tui:input-event-kind event)
                     '(:escape :enter))
             (goal12-extension-component-done-function component))
    (funcall (goal12-extension-component-done-function component)
             :closed))
  (values nil nil))

(defmethod cadr-tui:component-dispose
    ((component goal12-extension-component))
  (setf (goal12-extension-component-disposed-p component) t)
  component)

(test goal12-custom-message-and-entry-renderers-own-real-component-lifecycles
  (let ((message-components nil)
        (entry-components nil))
    (let* ((host (cadr-agent::make-extension-host :mode :tui))
           (bundle
             (cadr-agent::make-extension-bundle
              :id "transcript-components"
              :path "/tmp/transcript-components.lisp"
              :scope :project :rank 1 :order 0))
           (register
             (lambda ()
                (cadr-agent:define-component-message-renderer
                 "status"
                 :renderer
                 (lambda (message options theme)
                   (is (functionp (getf theme :fg)))
                   (let ((component
                           (make-instance
                            'goal12-extension-component
                            :text
                            (format nil "message:~A/~A"
                                    (getf message :content)
                                    (getf options :output-pad)))))
                     (push component message-components)
                     component)))
                (cadr-agent:define-component-entry-renderer
                 "card"
                 :renderer
                 (lambda (entry options theme)
                   (declare (ignore theme))
                   (let ((component
                           (make-instance
                            'goal12-extension-component
                            :text
                            (format nil "entry:~A/~A"
                                    (getf (getf entry :data) :value)
                                    (getf options :expanded-p)))))
                     (push component entry-components)
                     component)))))
           (message
             (cadr-cli::make-tui-entry
              :type :custom-message
              :custom-type "status"
              :custom-payload '(:content "ready")
              :custom-options '(:expanded-p nil :output-pad 1)))
           (entry
             (cadr-cli::make-tui-entry
              :type :custom-entry
              :custom-type "card"
              :custom-payload '(:data (:value 7))
              :custom-options '(:expanded-p nil))))
      (cadr-agent::call-with-extension-load
       host bundle
       (lambda ()
         (funcall register)))
      (cadr-agent::replace-extension-bundles host (list bundle))
      (is (equal '("message:ready/1")
                 (cadr-cli::render-tui-entry
                  message 80 :extension-host host)))
      (is (equal '("entry:7/NIL")
                 (cadr-cli::render-tui-entry
                  entry 80 :extension-host host)))
      (is (= 1 (length message-components)))
      (is (= 1 (length entry-components)))
      (setf (getf (cadr-cli::tui-entry-custom-options entry)
                  :expanded-p)
            t)
      (cadr-cli::invalidate-tui-entry-render-cache entry)
      (is (equal '("entry:7/T")
                 (cadr-cli::render-tui-entry
                  entry 80 :extension-host host)))
      (is (= 2 (length entry-components)))
      (is (goal12-extension-component-disposed-p
           (second entry-components)))
      (let ((state (cadr-cli::%make-tui-state)))
        (cadr-cli::append-tui-entry state message)
        (cadr-cli::append-tui-entry state entry)
        (cadr-cli::replace-tui-entries state nil)
        (is (goal12-extension-component-disposed-p
             (first message-components)))
        (is (goal12-extension-component-disposed-p
             (first entry-components)))))))

(test goal12-coding-agent-keybinding-hints-and-dynamic-border-match-baseline
  (let ((manager
          (cadr-tui:make-keybindings-manager
           :user-bindings
           '(("tui.select.cancel" . ("ctrl+c"))))))
    (cadr-tui:set-keybindings manager)
    (unwind-protect
         (progn
           (is (string= "alt+enter/ctrl+j"
                        (cadr-cli:format-key-text
                         "alt+enter/ctrl+j")))
           (is (string= "Ctrl+C"
                        (cadr-cli:key-display-text
                         "tui.select.cancel")))
           (is (search "ctrl+c cancel"
                       (cadr-tui:strip-terminal-sequences
                        (cadr-cli:key-hint
                         "tui.select.cancel" "cancel"))))
           (is (search "alt+x action"
                       (cadr-tui:strip-terminal-sequences
                        (cadr-cli:raw-key-hint
                         "alt+x" "action")))))
      (cadr-tui:set-keybindings
       (cadr-tui:make-keybindings-manager))))
  (let ((border
          (cadr-cli:make-dynamic-border-component
           :color-function #'string-upcase)))
    (is (equal (list (make-string 5 :initial-element #\─))
               (cadr-tui:component-render border 5)))))

(test goal12-coding-agent-bordered-loader-reuses-composition-and-cancels
  (let* ((ui (cadr-tui:make-tui-root))
         (loader
           (cadr-cli:make-bordered-loader-component
            ui "Working" :cancellable-p t :start-p nil))
         (aborted 0))
    (cadr-cli:bordered-loader-set-on-abort
     loader (lambda () (incf aborted)))
    (let ((plain
            (mapcar #'cadr-tui:strip-terminal-sequences
                    (cadr-tui:component-render loader 30))))
      (is (char= #\─ (char (first plain) 0)))
      (is (find-if (lambda (line) (search "Working" line)) plain))
      (is (find-if (lambda (line) (search "cancel" line)) plain))
      (is (char= #\─ (char (car (last plain)) 0))))
    (cadr-tui:component-handle-event
     loader (cadr-tui:make-input-event :kind :escape))
    (is (cadr-tui:cancellation-token-aborted-p
         (cadr-cli:bordered-loader-signal loader)))
    (is (= 1 aborted))
    (cadr-tui:component-dispose loader)))

(test goal12-coding-agent-countdown-has-explicit-deterministic-ticks
  (let* ((ticks nil)
        (expired 0)
        (timer
          (cadr-cli:make-countdown-timer
           2100 nil
           (lambda (seconds) (push seconds ticks))
           (lambda () (incf expired))
           :start-p nil)))
    (is (equal '(3) ticks))
    (cadr-cli:countdown-timer-tick timer)
    (cadr-cli:countdown-timer-tick timer)
    (cadr-cli:countdown-timer-tick timer)
    (is (equal '(0 1 2 3) ticks))
    (is (= 1 expired))
    (cadr-tui:component-dispose timer)))

(test goal12-coding-agent-armin-and-daxnuts-animation-components-are-driven-without-sleeps
  (let* ((renders 0)
         (ui (cadr-tui:make-tui-root
              :render-function
              (lambda (lines)
                (declare (ignore lines))
                (incf renders))))
         (armin
           (cadr-cli:make-armin-component
            ui :effect :scanline :start-p nil))
         (dax
           (cadr-cli:make-daxnuts-component
            ui :start-p nil)))
    (is (= 19 (length (cadr-tui:component-render armin 40))))
    (is (search "ARMIN SAYS HI"
                (car (last
                      (cadr-tui:component-render armin 40)))))
    (cadr-cli:armin-component-tick armin)
    (is (plusp renders))
    (is (= 24 (length (cadr-tui:component-render dax 50))))
    (cadr-cli:daxnuts-component-tick dax)
    (is (>= renders 2))
    (cadr-tui:component-dispose armin)
    (cadr-tui:component-dispose dax)))

(test goal12-coding-agent-earendil-announcement-and-component-barrel-are-complete
  (let* ((announcement
           (cadr-cli:make-earendil-announcement-component))
         (plain
           (mapcar #'cadr-tui:strip-terminal-sequences
                   (cadr-tui:component-render announcement 60)))
         (joined (format nil "~{~A~^~%~}" plain)))
    (is (search "pi has joined Earendil" joined))
    (is (search "https://mariozechner.at/posts/2026-04-08-ive-sold-out/"
                joined))
    (is (char= #\─ (char (first plain) 0)))
    (is (char= #\─ (char (car (last plain)) 0))))
  (dolist (name '("MAKE-ARMIN-COMPONENT"
                  "MAKE-BORDERED-LOADER-COMPONENT"
                  "MAKE-COUNTDOWN-TIMER"
                  "MAKE-DAXNUTS-COMPONENT"
                  "MAKE-DYNAMIC-BORDER-COMPONENT"
                  "MAKE-EARENDIL-ANNOUNCEMENT-COMPONENT"
                  "FORMAT-KEY-TEXT"
                  "KEY-HINT"))
    (multiple-value-bind (symbol status)
        (find-symbol name :cadr-cli)
      (is (not (null symbol)))
      (is (eq :external status)))))

(test goal12-custom-overlay-options-and-handle-visibility-are-instance-local
  (let* ((state (cadr-cli::make-tui-state :model "mock"))
         (editor (cadr-tui:make-multiline-editor))
         (component
           (make-instance 'goal12-extension-component
                          :text "overlay-body"))
         (handle
           (cadr-tui:overlay-stack-show
            (cadr-tui:make-overlay-stack
             :focused-component editor)
            component nil))
         (overlay
           (cadr-cli::make-extension-custom-ui-state
            :component component
            :overlay-p t
            :overlay-options
            '(:width 20 :anchor :top-right :margin 1)
            :handle handle)))
    (multiple-value-bind (lines row column)
        (cadr-cli::render-tui-state
         state editor 50 12 :overlay overlay)
      (declare (ignore row column))
      (is (find "overlay-body" lines :test #'search)))
    (cadr-tui:overlay-handle-set-hidden handle t)
    (multiple-value-bind (lines row column)
        (cadr-cli::render-tui-state
         state editor 50 12 :overlay overlay)
      (declare (ignore row column))
      (is (not (find "overlay-body" lines :test #'search))))
    (cadr-tui:overlay-handle-set-hidden handle nil)
    (setf
     (cadr-cli::extension-custom-ui-state-overlay-options overlay)
     '(:width 20 :visible nil))
    (multiple-value-bind (lines row column)
        (cadr-cli::render-tui-state
         state editor 50 12 :overlay overlay)
      (declare (ignore row column))
      (is (not (find "overlay-body" lines :test #'search))))))

(test goal12-header-footer-working-and-hidden-thinking-components-compose-with-default-state
  (let* ((state
           (cadr-cli::make-tui-state
            :model "mock" :hide-thinking-block-p t))
         (editor (cadr-tui:make-multiline-editor)))
    (setf
     (cadr-cli::tui-state-header-component state)
     (cadr-tui:make-text-component
      "extension-header" :padding-x 0 :padding-y 0)
     (cadr-cli::tui-state-footer-component state)
     (cadr-tui:make-text-component
      "extension-footer" :padding-x 0 :padding-y 0)
     (cadr-cli::tui-state-working-message state) "Indexing"
     (cadr-cli::tui-state-working-indicator-frames state) '("A" "B")
     (cadr-cli::tui-state-working-indicator-interval-ms state) 100
     (cadr-cli::tui-state-hidden-thinking-label state) "Reasoning hidden")
    (cadr-cli::replace-tui-entries
     state
     (list
      (cadr-cli::make-tui-entry
       :type :assistant
       :content-blocks
       (list (cons :assistant-thinking "private chain")))))
    (multiple-value-bind (lines row column)
        (cadr-cli::render-tui-state
         state editor 60 16 :busy-p t :now 0d0)
      (declare (ignore row column))
      (let ((plain (mapcar #'cadr-tui:strip-terminal-sequences lines)))
        (is (find "extension-header" plain :test #'search))
        (is (find "extension-footer" plain :test #'search))
        (is (find "Indexing" plain :test #'search))
        (is (find "Reasoning hidden" plain :test #'search))
        (is (not (find "private chain" plain :test #'search)))))))
