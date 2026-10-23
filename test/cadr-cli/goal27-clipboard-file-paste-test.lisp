(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defun goal49-paste (&key paths image-calls text-calls
                          text line column bash-mode-p
                          (reader-error nil))
  (let ((inserted nil)
        (shown nil)
        (images 0)
        (texts 0))
    (cadr-cli::handle-clipboard-paste
     :file-path-reader
     (lambda ()
       (when reader-error
         (error "~A" reader-error))
       paths)
     :image-reader
     (lambda ()
       (incf images)
       nil)
     :text-reader
     (lambda ()
       (incf texts)
       nil)
     :editor-text text
     :editor-line line
     :editor-column column
     :bash-mode-p bash-mode-p
     :insert (lambda (value) (setf inserted value))
     :show-error (lambda (value) (setf shown value)))
    (when image-calls
      (funcall image-calls images))
    (when text-calls
      (funcall text-calls texts))
    (values inserted shown)))

(test finder-file-paths-take-precedence-over-their-icon-image
  ;; pi@4a080252f clipboard-paste-file-paths.test.ts
  (let ((images 0)
        (texts 0))
    (multiple-value-bind (inserted shown)
        (goal49-paste
         :paths '("/tmp/screenshot.png"
                  "/tmp/My Photos/photo.png")
         :text ""
         :line 0
         :column 0
         :image-calls (lambda (count) (setf images count))
         :text-calls (lambda (count) (setf texts count)))
      (is (string=
           (format nil "/tmp/screenshot.png~%/tmp/My Photos/photo.png")
           inserted))
      (is (null shown))
      (is (= 0 images))
      (is (= 0 texts)))))

(test clipboard-file-paths-containing-terminal-controls-are-rejected
  (let ((images 0))
    (multiple-value-bind (inserted shown)
        (goal49-paste
         :paths (list (format nil "/tmp/photo~C]0;unsafe~C.png"
                              #\Escape (code-char 7)))
         :image-calls (lambda (count) (setf images count)))
      (is (null inserted))
      (is (= 0 images))
      (is (string=
           "Failed to paste from clipboard: Clipboard file path contains control characters"
           shown)))))

(test native-file-path-errors-do-not-fall-through-to-the-icon
  (let ((images 0))
    (multiple-value-bind (inserted shown)
        (goal49-paste
         :reader-error "Native clipboard file read failed"
         :image-calls (lambda (count) (setf images count)))
      (is (null inserted))
      (is (= 0 images))
      (is (string=
           "Failed to paste from clipboard: Native clipboard file read failed"
           shown)))))

(test clipboard-file-paths-are-separated-from-preceding-text
  (dolist (case '(("Review:" 7) ("確認" 2)))
    (multiple-value-bind (inserted shown)
        (goal49-paste
         :paths '("/tmp/photo.png")
         :text (first case)
         :line 0
         :column (second case))
      (is (null shown))
      (is (string= " /tmp/photo.png" inserted)))))

(test clipboard-file-paths-skip-a-space-after-javascript-whitespace
  (multiple-value-bind (inserted shown)
      (goal49-paste
       :paths '("/tmp/photo.png")
       :text (format nil "cat~C" #\No-break_space)
       :line 0
       :column 4)
    (is (null shown))
    (is (string= "/tmp/photo.png" inserted))))

(test bash-mode-shell-quotes-file-paths-and-inserts-them-as-arguments
  (multiple-value-bind (inserted shown)
      (goal49-paste
       :paths '("/tmp/My Photos/photo.png"
                "/tmp/$(touch hacked).png"
                "/tmp/plain.png")
       :text "catDEST"
       :line 0
       :column 3
       :bash-mode-p t)
    (is (null shown))
    (is (string=
         " '/tmp/My Photos/photo.png' '/tmp/$(touch hacked).png' /tmp/plain.png "
         inserted))))

(test read-clipboard-file-paths-drops-an-empty-native-list
  (is (null (cadr-cli::read-clipboard-file-paths)))
  (is (null
       (cadr-cli::read-clipboard-file-paths
        :native-getter (lambda () nil))))
  (is (null
       (cadr-cli::read-clipboard-file-paths
        :native-getter (lambda () '()))))
  (is (equal
       '("/tmp/photo.png")
       (cadr-cli::read-clipboard-file-paths
        :native-getter (lambda () #("/tmp/photo.png"))))))

(test paste-image-key-decodes-to-the-clipboard-handler
  (let ((previous (cadr-tui:get-keybindings)))
    (unwind-protect
         (progn
           (cadr-tui:set-keybindings
            (cadr-tui:make-keybindings-manager
             :definitions
             (cadr-tui:default-keybinding-definitions
              :platform "linux" :environment nil)))
           (is (eq :paste-image
                   (cadr-tui::event-kind-for-raw-key
                    (string (code-char 22)))))
           (cadr-tui:set-keybindings
            (cadr-tui:make-keybindings-manager
             :definitions
             (cadr-tui:default-keybinding-definitions
              :platform "win32" :environment nil)))
           (is (eq :paste-image
                   (cadr-tui::event-kind-for-raw-key
                    (format nil "~Cv" #\Escape)))))
      (cadr-tui:set-keybindings previous))))

(defclass goal49-paste-terminal (cadr-tui::virtual-terminal)
  ((inputs
    :initarg :inputs
    :accessor goal49-paste-terminal-inputs)))

(defmethod cadr-tui:terminal-read-input
    ((terminal goal49-paste-terminal))
  (loop
    for next = (first (goal49-paste-terminal-inputs terminal))
    while (functionp next)
    do (if (funcall next terminal)
           (pop (goal49-paste-terminal-inputs terminal))
           (return-from cadr-tui:terminal-read-input "")))
  (or (pop (goal49-paste-terminal-inputs terminal)) ""))

(defun goal49-paste-screen (terminal)
  (format nil "~{~A~^~%~}"
          (mapcar #'cadr-tui:strip-terminal-sequences
                  (cadr-tui:virtual-terminal-snapshot terminal))))

(test ctrl-v-inserts-finder-file-paths-into-the-editor
  (let ((previous (cadr-tui:get-keybindings)))
    (unwind-protect
         (let ((captured nil)
               (terminal nil))
           (cadr-tui:set-keybindings
            (cadr-tui:make-keybindings-manager
             :definitions
             (cadr-tui:default-keybinding-definitions
              :platform "linux" :environment nil)))
           (setf terminal
                 (make-instance
                  'goal49-paste-terminal
                  :columns 80
                  :rows 24
                  :inputs
                  (list
                   (string (code-char 22))
                   (let ((attempts 0))
                     (lambda (term)
                       (let ((screen (goal49-paste-screen term)))
                         (cond
                           ((and (search "/tmp/screenshot.png" screen)
                                 (search "/tmp/My Photos/photo.png" screen))
                            (setf captured screen)
                            t)
                           ((> (incf attempts) 80)
                            (setf captured screen)
                            t)
                           (t nil)))))
                   (string (code-char 3))
                   (string (code-char 3)))))
           (cadr-cli::run-tui
            (lambda (line)
              (error "Unexpected submission: ~A" line))
            :model "faux"
            :terminal terminal
            :clipboard-file-path-getter
            (lambda ()
              '("/tmp/screenshot.png"
                "/tmp/My Photos/photo.png")))
           (is (search "/tmp/screenshot.png" captured))
           (is (search "/tmp/My Photos/photo.png" captured)))
      (cadr-tui:set-keybindings previous))))
