(load (merge-pathnames "support.lisp" *load-truename*))

(defclass example-overlay-test-component (cadr-tui:focusable-component)
  ((theme
    :initarg :theme
    :reader example-overlay-test-theme)
   (done
    :initarg :done
    :reader example-overlay-test-done)
   (selected
    :initform 0
    :accessor example-overlay-test-selected)
   (items
    :initform
    (list
     (list :label "Search" :has-input t :text "" :cursor 0)
     (list :label "Run" :has-input t :text "" :cursor 0)
     (list :label "Settings" :has-input nil :text "" :cursor 0)
     (list :label "Cancel" :has-input nil :text "" :cursor 0))
    :accessor example-overlay-test-items)))

(defun example-overlay-pad (text width)
  (concatenate
   'string text
   (make-string
    (max 0 (- width (cadr-tui:visible-width text)))
    :initial-element #\Space)))

(defun example-overlay-row (theme content inner-width)
  (concatenate
   'string
   (example-theme-fg theme :border "│")
   (example-overlay-pad content inner-width)
   (example-theme-fg theme :border "│")))

(defun example-overlay-current-item (component)
  (nth (example-overlay-test-selected component)
       (example-overlay-test-items component)))

(defmethod cadr-tui:component-handle-event
    ((component example-overlay-test-component) event)
  (let* ((kind (cadr-tui:input-event-kind event))
         (text (or (cadr-tui:input-event-text event) ""))
         (item (example-overlay-current-item component))
         (last (1- (length (example-overlay-test-items component)))))
    (cond
      ((member kind '(:escape :cancel :interrupt))
       (funcall (example-overlay-test-done component) nil))
      ((eq kind :enter)
       (funcall
        (example-overlay-test-done component)
        (list
         :action (getf item :label)
         :query (and (getf item :has-input) (getf item :text)))))
      ((eq kind :up)
       (setf (example-overlay-test-selected component)
             (max 0 (1- (example-overlay-test-selected component)))))
      ((eq kind :down)
       (setf (example-overlay-test-selected component)
             (min last (1+ (example-overlay-test-selected component)))))
      ((and (getf item :has-input) (eq kind :backspace))
       (let ((cursor (getf item :cursor))
             (value (getf item :text)))
         (when (plusp cursor)
           (setf (getf item :text)
                 (concatenate
                  'string
                  (subseq value 0 (1- cursor))
                  (subseq value cursor))
                 (getf item :cursor) (1- cursor)))))
      ((and (getf item :has-input) (eq kind :left))
       (setf (getf item :cursor) (max 0 (1- (getf item :cursor)))))
      ((and (getf item :has-input) (eq kind :right))
       (setf (getf item :cursor)
             (min (length (getf item :text))
                  (1+ (getf item :cursor)))))
      ((and (getf item :has-input)
            (eq kind :text)
            (= (length text) 1)
            (>= (char-code (char text 0)) 32))
       (let ((cursor (getf item :cursor))
             (value (getf item :text)))
         (setf (getf item :text)
               (concatenate
                'string
                (subseq value 0 cursor)
                text
                (subseq value cursor))
               (getf item :cursor) (1+ cursor))))))
  (values nil nil))

(defmethod cadr-tui:component-render
    ((component example-overlay-test-component) width &key focused-p)
  (declare (ignore width))
  (let* ((theme (example-overlay-test-theme component))
         (inner-w 68)
         (row (lambda (content)
                (example-overlay-row theme content inner-w)))
         (action-rows nil))
    (dolist (item (example-overlay-test-items component))
      (let* ((selected-p
               (eq item (example-overlay-current-item component)))
             (prefix (if selected-p " ▶ " "   "))
             (content
               (if (getf item :has-input)
                   (let* ((label
                            (example-theme-fg
                             theme (if selected-p :accent :text)
                             (format nil "~A:" (getf item :label))))
                          (value (getf item :text))
                          (cursor (getf item :cursor))
                          (display
                            (if selected-p
                                (let ((before (subseq value 0 cursor))
                                      (ch
                                        (if (< cursor (length value))
                                            (string (char value cursor))
                                            " "))
                                      (after
                                        (if (< cursor (length value))
                                            (subseq value (1+ cursor))
                                            ""))
                                      (marker
                                        (if focused-p
                                            cadr-tui:+cursor-marker+
                                            "")))
                                  (format nil "~A~A~C[7m~A~C[27m~A"
                                          before marker #\Escape ch #\Escape after))
                                value)))
                     (format nil "~A~A ~A" prefix label display))
                   (concatenate
                    'string prefix
                    (example-theme-fg
                     theme (if selected-p :accent :text)
                     (getf item :label))))))
        (setf action-rows (nconc action-rows (list (funcall row content))))))
    (append
     (list
      (example-theme-fg
       theme :border
       (format nil "╭~A╮" (make-string inner-w :initial-element #\─)))
      (funcall row
               (format nil " ~A"
                       (example-theme-fg theme :accent "🧪 Overlay Test")))
      (funcall row "")
      (funcall
       row
       (format nil " ~A"
               (example-theme-fg
                theme :dim "─── Edge Cases (borders should align) ───")))
      (funcall
       row
       (format
        nil " Wide: ~A"
        (example-theme-fg
         theme :warning
         "中文日本語한글テスト漢字繁體简体ひらがなカタカナ가나다라마바")))
      (funcall
       row
       (format
        nil " Styled: ~A ~A ~A ~A ~A ~A ~A"
        (example-theme-fg theme :error "RED")
        (example-theme-fg theme :success "GREEN")
        (example-theme-fg theme :warning "YELLOW")
        (example-theme-fg theme :accent "ACCENT")
        (example-theme-fg theme :dim "DIM")
        (example-theme-fg theme :error "more")
        (example-theme-fg theme :success "colors")))
      (funcall
       row
       " Emoji: 👨‍👩‍👧‍👦 🇯🇵 🚀 💻 🎉 🔥 😀 🎯 🌟 💡 🎨 🔧 📦 🏆 🌈 🎪 🎭 🎬 🎮 🎲")
      (funcall row "")
      (funcall
       row
       (format nil " ~A"
               (example-theme-fg theme :dim "─── Actions ───"))))
     action-rows
     (list
      (funcall row "")
      (funcall
       row
       (format
        nil " ~A"
        (example-theme-fg
         theme :dim
         "↑↓ navigate • type to input • Enter select • Esc cancel")))
      (example-theme-fg
       theme :border
       (format nil "╰~A╯" (make-string inner-w :initial-element #\─)))))))

(cadr-agent:define-command
 "overlay-test"
 :description "Test overlay rendering with edge cases"
 :handler
 (lambda (arguments context)
   (declare (ignore arguments))
   (let ((result
           (cadr-agent:extension-context-custom-component
            context
            (lambda (tui theme keybindings done)
              (declare (ignore tui keybindings))
              (make-instance
               'example-overlay-test-component
               :theme theme :done done))
            :overlay-p t
            :overlay-options '(:width 70 :anchor :center :focus t))))
     (when result
       (let ((query (getf result :query)))
         (cadr-agent:extension-context-notify
          context
          (if (and query (plusp (length query)))
              (format nil "~A: \"~A\"" (getf result :action) query)
              (getf result :action))))))))
