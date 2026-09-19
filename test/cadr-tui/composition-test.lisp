(in-package #:cadr-tui/tests)

(in-suite cadr-tui-suite)

(defclass goal12-probe-component (cadr-tui:component)
  ((lines
    :initarg :lines
    :accessor goal12-probe-lines)
   (invalidations
    :initform 0
    :accessor goal12-probe-invalidations)
   (events
    :initform nil
    :accessor goal12-probe-events)))

(defmethod cadr-tui:component-render
    ((component goal12-probe-component) width &key focused-p)
  (declare (ignore width focused-p))
  (copy-list (goal12-probe-lines component)))

(defmethod cadr-tui:component-invalidate
    ((component goal12-probe-component))
  (incf (goal12-probe-invalidations component))
  component)

(defmethod cadr-tui:component-handle-event
    ((component goal12-probe-component) event)
  (push (cadr-tui:input-event-kind event)
        (goal12-probe-events component))
  (values nil nil))

(test goal12-tui-component-container-and-box-match-baseline-contract
  (let* ((first
           (make-instance 'goal12-probe-component
                          :lines '("alpha")))
         (second
           (make-instance 'goal12-probe-component
                          :lines '("beta")))
         (container
           (cadr-tui:make-component-container first)))
    (is (equal '("alpha")
               (cadr-tui:component-render container 20)))
    (cadr-tui:component-add-child container second)
    (is (equal '("alpha" "beta")
               (cadr-tui:component-render container 20)))
    (cadr-tui:component-invalidate container)
    (is (= 1 (goal12-probe-invalidations first)))
    (is (= 1 (goal12-probe-invalidations second)))
    (cadr-tui:component-remove-child container first)
    (is (equal '("beta")
               (cadr-tui:component-render container 20)))
    (cadr-tui:component-clear container)
    (is (null (cadr-tui:component-render container 20))))
  (let* ((child
           (cadr-tui:make-text-component
            "x" :padding-x 0 :padding-y 0))
         (box
           (cadr-tui:make-box-component
            :padding-x 1 :padding-y 1)))
    (cadr-tui:component-add-child box child)
    (is (equal '("      " " x    " "      ")
               (cadr-tui:component-render box 6)))
    (cadr-tui:text-component-set-text child "y")
    (is (search "y" (second
                     (cadr-tui:component-render box 6))))))

(test goal12-tui-text-spacer-and-truncated-components-match-baseline
  (let ((text
          (cadr-tui:make-text-component
           (format nil "a~Cb" #\Tab)
           :padding-x 1 :padding-y 1)))
    (is (equal '("        " " a   b  " "        ")
               (cadr-tui:component-render text 8)))
    (cadr-tui:text-component-set-text text "   ")
    (is (null (cadr-tui:component-render text 8))))
  (let ((spacer (cadr-tui:make-spacer-component :lines 2)))
    (is (equal '("" "")
               (cadr-tui:component-render spacer 80)))
    (cadr-tui:spacer-component-set-lines spacer 0)
    (is (null (cadr-tui:component-render spacer 80))))
  (let ((truncated
          (cadr-tui:make-truncated-text-component
           (format nil "abcdefghij~%ignored")
           :padding-x 1 :padding-y 1)))
    (let ((lines (cadr-tui:component-render truncated 8)))
      (is (= 3 (length lines)))
      (is (search "..." (second lines)))
      (is (null (search "ignored" (second lines)))))))

(test goal12-tui-markdown-component-caches-and-invalidates-transform
  (let* ((calls 0)
        (component
          (cadr-tui:make-markdown-component
           "alpha" :padding-x 1 :padding-y 0
           :transform-function
           (lambda (text width)
             (incf calls)
             (format nil "~A/~D" text width)))))
    (is (search "alpha/18"
                (first (cadr-tui:component-render component 20))))
    (cadr-tui:component-render component 20)
    (is (= 1 calls))
    (cadr-tui:markdown-component-set-text component "beta")
    (is (search "beta/18"
                (first (cadr-tui:component-render component 20))))
    (is (= 2 calls))))

(test goal12-tui-image-component-retains-id-and-width-cache
  (let* ((caps
           (cadr-tui:make-terminal-capabilities
            :images :kitty :true-color-p t
            :hyperlinks-p nil))
         (component
           (cadr-tui:make-image-component
            "YWJj" "image/png"
            :dimensions '(100 100)
            :capabilities caps
            :max-width-cells 10
            :max-height-cells 3)))
    (let ((first (cadr-tui:component-render component 20))
          (id (cadr-tui:image-component-id component)))
      (is (= 3 (length first)))
      (is (plusp id))
      (is (eq first
              (cadr-tui:component-render component 20)))
      (cadr-tui:component-invalidate component)
      (is (not (eq first
                   (cadr-tui:component-render component 20))))
      (is (= id (cadr-tui:image-component-id component))))))

(test goal12-tui-loader-and-cancellable-loader-have-deterministic-lifecycle
  (let* ((renders 0)
        (ui (cadr-tui:make-tui-root
             :render-function
             (lambda (lines)
               (declare (ignore lines))
               (incf renders)))))
    (let ((loader
            (cadr-tui:make-loader-component
             ui #'identity #'identity
             :message "Loading..."
             :indicator-frames '("a" "b")
             :start-p nil)))
      (is (search "a Loading..."
                  (second
                   (cadr-tui:component-render loader 30))))
      (cadr-tui:loader-component-step loader)
      (is (search "b Loading..."
                  (second
                   (cadr-tui:component-render loader 30))))
      (is (= 1 renders))
      (cadr-tui:loader-component-set-message loader "Working")
      (is (search "Working"
                  (second
                   (cadr-tui:component-render loader 30))))
      (cadr-tui:component-dispose loader))
    (let ((aborts 0)
          (loader
            (cadr-tui:make-cancellable-loader-component
             ui #'identity #'identity
             :start-p nil)))
      (cadr-tui:cancellable-loader-set-on-abort
       loader (lambda () (incf aborts)))
      (cadr-tui:component-handle-event
       loader (cadr-tui:make-input-event :kind :escape))
      (cadr-tui:component-handle-event
       loader (cadr-tui:make-input-event :kind :escape))
      (is (cadr-tui:cancellation-token-aborted-p
           (cadr-tui:cancellable-loader-token loader)))
      (is (= 1 aborts))
      (cadr-tui:component-dispose loader))))

(test goal12-tui-settings-list-supports-search-cycle-submenu-and-cancel
  (let* ((changes nil)
        (cancelled 0)
        (submenu-done nil)
        (component
          (cadr-tui:make-settings-list-component
           (list
            (cadr-tui:make-setting-item
             :id "bool" :label "Boolean"
             :current-value "false"
             :values '("false" "true")
             :description "Toggle value")
            (cadr-tui:make-setting-item
             :id "choice" :label "Choice"
             :current-value "one"
             :submenu
             (lambda (current done)
               (declare (ignore current))
               (setf submenu-done done)
               (cadr-tui:make-text-component
                "submenu" :padding-x 0 :padding-y 0))))
           5
           :search-enabled-p t
           :on-change
           (lambda (id value)
             (push (list id value) changes))
           :on-cancel (lambda () (incf cancelled)))))
    (is (search "> " (first
                     (cadr-tui:component-render component 50))))
    (cadr-tui:component-handle-event
     component (cadr-tui:make-input-event :kind :enter))
    (is (equal '("bool" "true") (first changes)))
    (cadr-tui:settings-list-component-update-value
     component "bool" "false")
    (cadr-tui:component-handle-event
     component (cadr-tui:make-input-event :kind :down))
    (cadr-tui:component-handle-event
     component (cadr-tui:make-input-event :kind :enter))
    (is (search "submenu"
                (first
                 (cadr-tui:component-render component 50))))
    (funcall submenu-done "two")
    (is (equal '("choice" "two") (first changes)))
    (cadr-tui:component-handle-event
     component (cadr-tui:make-input-event :kind :text :text "Bool"))
    (is (search "Boolean"
                (format nil "~{~A~^~%~}"
                        (cadr-tui:component-render component 50))))
    (cadr-tui:component-handle-event
     component (cadr-tui:make-input-event :kind :escape))
    (is (= 1 cancelled))))

(test settings-list-space-is-search-text-when-query-is-nonempty
  ;; Baseline settings-list.ts:187. Empty query: space still
  ;; activates. Nonempty query: space is a search character.
  ;; Paste keeps spaces (no strip).
  (let ((changes nil)
        (items
          (list
           (cadr-tui:make-setting-item
            :id "apple" :label "Apple Terminal"
            :current-value "off"
            :values '("off" "on"))
           (cadr-tui:make-setting-item
            :id "other" :label "Other"
            :current-value "off"
            :values '("off" "on")))))
    (let ((component
            (cadr-tui:make-settings-list-component
             items 5
             :search-enabled-p t
             :on-change
             (lambda (id value)
               (push (list id value) changes)))))
      (cadr-tui:component-handle-event
       component (cadr-tui:make-input-event :kind :text :text " "))
      (is (equal '(("apple" "on")) changes))
      (cadr-tui:component-handle-event
       component (cadr-tui:make-input-event :kind :text :text "Apple"))
      (setf changes nil)
      (cadr-tui:component-handle-event
       component (cadr-tui:make-input-event :kind :text :text " "))
      (is (null changes))
      (is (string=
           "Apple "
           (cadr-tui:single-line-input-value
            (cadr-tui::settings-list-component-search-input
             component)))))
    (let ((paster
            (cadr-tui:make-settings-list-component
             items 5 :search-enabled-p t)))
      (cadr-tui:component-handle-event
       paster
       (cadr-tui:make-input-event :kind :text :text "Apple Terminal"))
      (is (string=
           "Apple Terminal"
           (cadr-tui:single-line-input-value
            (cadr-tui::settings-list-component-search-input
             paster))))
      (is (search
           "Apple Terminal"
           (format nil "~{~A~^~%~}"
                   (cadr-tui:component-render paster 50)))))))

(test goal12-tui-editor-component-protocol-covers-both-editors
  (dolist (editor
           (list (cadr-tui:make-multiline-editor :text "multi")
                 (cadr-tui:make-single-line-input :value "single")))
    (is (stringp (cadr-tui:editor-component-text editor)))
    (cadr-tui:editor-component-set-text editor "changed")
    (is (string= "changed"
                 (cadr-tui:editor-component-text editor)))
    (is (listp
         (cadr-tui:component-render editor 40 :focused-p t)))
    (cadr-tui:component-handle-event
     editor (cadr-tui:make-input-event :kind :text :text "!"))
    (is (search "!" (cadr-tui:editor-component-text editor)))))

(test goal12-tui-root-composes-focus-input-and-overlays
  (let* ((terminal (cadr-tui:make-virtual-terminal
                    :columns 12 :rows 6))
         (base
           (make-instance 'goal12-probe-component
                          :lines '("base")))
         (overlay
           (make-instance 'goal12-probe-component
                          :lines '("OVER")))
         (frames nil)
         (root
           (cadr-tui:make-tui-root
            :terminal terminal
            :render-function
            (lambda (lines) (push lines frames)))))
    (is (string= cadr-tui:+cursor-marker+
                 (format nil "~A" cadr-tui:+cursor-marker+)))
    (cadr-tui:component-add-child root base)
    (cadr-tui:tui-set-focus root base)
    (cadr-tui:tui-handle-input root (string #\a))
    (is (equal '(:text) (goal12-probe-events base)))
    (let ((handle
            (cadr-tui:tui-show-overlay
             root overlay :width 6 :row 1 :col 2)))
      (is (cadr-tui:tui-has-overlay-p root))
      (cadr-tui:tui-handle-input root (string #\b))
      (is (equal '(:text) (goal12-probe-events overlay)))
      (let ((rendered (cadr-tui:component-render root 12)))
        (is (search "OVER" (second rendered))))
      (cadr-tui:tui-overlay-set-hidden root handle t)
      (is (not (cadr-tui:tui-has-overlay-p root)))
      (cadr-tui:tui-overlay-set-hidden root handle nil)
      (cadr-tui:tui-overlay-unfocus root handle :target base)
      (cadr-tui:tui-overlay-focus root handle)
      (cadr-tui:tui-overlay-hide root handle)
      (is (not (cadr-tui:tui-has-overlay-p root))))
    (setf frames nil)
    (cadr-tui:tui-request-render root)
    (is (= 1 (length frames)))
    (cadr-tui:component-dispose root)))

(test protocol-generics-documented
  (dolist (name '(cadr-tui:component-render
                  cadr-tui:component-handle-event
                  cadr-tui:component-invalidate
                  cadr-tui:component-dispose
                  cadr-tui:component-wants-key-release-p
                  cadr-tui:component-focusable-p))
    (is (documentation name 'function))))

(test loader-defaults-one-owner
  (is (equal cadr-tui::+loader-default-frames+
             (cadr-tui::loader-frames nil)))
  (is (= 0.08d0 (cadr-tui::loader-interval-seconds nil)))
  (is (= 0.2d0 (cadr-tui::loader-interval-seconds 0.2d0))))

(test select-list-height-default
  (is (= 5 (cadr-tui::select-list-height
            (cadr-tui:make-select-list)))))

(test settings-hover-does-not-move-the-centered-selection
  (dolist (row '(0 4))
    (let* ((changes nil)
           (list
             (cadr-tui:make-settings-list-component
              (loop for index below 12
                    collect
                    (cadr-tui:make-setting-item
                     :id (format nil "item-~D" index)
                     :label (format nil "Item ~D" index)
                     :current-value "off"
                     :values '("off" "on")))
              5
              :search-enabled-p t
              :cursor "> "
              :on-change
              (lambda (id value)
                (push (list id value) changes)))))
      (setf (cadr-tui:settings-list-component-selected-index list) 5)
      (is (eq :scroll
              (cadr-tui:settings-list-handle-mouse
               list :type :wheel :wheel-delta 1 :y (+ row 2))))
      (let ((before (cadr-tui:component-render list 80)))
        (is (some (lambda (line)
                    (and (uiop:string-prefix-p "> " line)
                         (search "Item 6" line)))
                  before))
        (dolist (y '(0 1 2 3 4))
          (is (null
               (cadr-tui:settings-list-handle-mouse
                list :type :move :button :none :y (+ y 2))))
          (is (equal before (cadr-tui:component-render list 80))))
        (is (null changes))
        (cadr-tui:settings-list-handle-mouse
         list :type :press :button :left :y (+ row 2))
        (is (eq :click
                (cadr-tui:settings-list-handle-mouse
                 list :type :click :button :left :y (+ row 2))))
        (is (equal (list (list (format nil "item-~D" (+ 4 row)) "on"))
                   changes))))))
