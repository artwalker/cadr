(load (merge-pathnames "support.lisp" *load-truename*))

(defclass overlay-qa-component (example-dialog-component)
  ((tui :initarg :tui :reader overlay-qa-tui)
   (frame :initform 0 :accessor overlay-qa-frame)
   (animation-p :initarg :animation-p :initform nil
                :reader overlay-qa-animation-p)
   (thread :initform nil :accessor overlay-qa-thread)))

(defmethod initialize-instance :after ((component overlay-qa-component) &key)
  (when (overlay-qa-animation-p component)
    (setf
     (overlay-qa-thread component)
     (sb-thread:make-thread
      (lambda ()
        (loop repeat 120
              until (example-dialog-disposed-p component)
              do (sleep (/ 1.0 30.0))
                 (incf (overlay-qa-frame component))
                 (cadr-tui:tui-request-render (overlay-qa-tui component))))
      :name "cadr overlay animation example"))))

(defmethod cadr-tui:component-render
    ((component overlay-qa-component) width &key focused-p)
  (let ((lines (call-next-method)))
    (if (overlay-qa-animation-p component)
        (append
         (subseq lines 0 2)
         (list
          (let* ((span (max 1 (min 30 (- width 4))))
                 (position (mod (overlay-qa-frame component) span)))
            (concatenate
             'string (make-string position :initial-element #\·)
             "●"
             (make-string (- span position 1) :initial-element #\·))))
         (subseq lines 2))
        lines)))

(defmethod cadr-tui:component-dispose :after
    ((component overlay-qa-component))
  (let ((thread (overlay-qa-thread component)))
    (when (and thread (sb-thread:thread-alive-p thread)
               (not (eq thread sb-thread:*current-thread*)))
      (sb-thread:join-thread thread :default nil :timeout 0.1))))

(defun overlay-qa-show
    (context title lines options &key animation-p on-handle)
  (cadr-agent:extension-context-custom-component
   context
   (lambda (tui theme keybindings done)
     (declare (ignore theme keybindings))
     (make-instance
      'overlay-qa-component :tui tui :title title :lines lines
      :animation-p animation-p :options '("Close") :done done))
   :overlay-p t :overlay-options options :on-handle on-handle))

(defun overlay-qa-register-command
    (name description title lines options &key animation-p handler)
  (cadr-agent::register-extension-command
   name
   :description description
   :argument-hint nil
   :handler
   (or handler
       (lambda (arguments context)
         (declare (ignore arguments))
         (overlay-qa-show
          context title lines options :animation-p animation-p)))))

(overlay-qa-register-command
 "overlay-animation" "Test real-time animation in overlay (~30 FPS)"
 "Overlay Animation" '("Thirty frames per second" "Escape closes")
 '(:anchor :center :width 50 :max-height 20) :animation-p t)

(overlay-qa-register-command
 "overlay-anchors" "Cycle through all anchor positions"
 "Overlay Anchors" '("Nine anchors are supported" "Re-run after choosing an anchor")
 '(:anchor :top-left :width 40))

(overlay-qa-register-command
 "overlay-margins" "Test margin and offset options"
 "Overlay Margins" '("margin: top=3 left=6" "offset: x=2 y=1")
 '(:anchor :top-left :width 35 :margin (:top 3 :left 6)
   :offset-x 2 :offset-y 1))

(overlay-qa-register-command
 "overlay-stack" "Test stacked overlays"
 "Overlay Stack" '("This is the front overlay" "Focus follows stack order")
 '(:anchor :center :width 50 :offset-x 8 :offset-y 4 :max-height 15))

(overlay-qa-register-command
 "overlay-overflow" "Test width overflow with streaming process output"
 "Overlay Overflow" (list (make-string 180 :initial-element #\X)
                            "Long lines are clipped, never fatal")
 '(:anchor :center :width 42 :max-height 14))

(overlay-qa-register-command
 "overlay-edge" "Test overlay positioned at terminal edge"
 "Terminal Edge" '("row=0 col=0" "No off-by-one overflow")
 '(:row 0 :col 0 :width 32 :max-height 8))

(overlay-qa-register-command
 "overlay-percent" "Test percentage-based positioning"
 "Percent Position" '("50% row and column" "Responsive positioning")
 '(:row 0.5 :col 0.5 :width 36 :max-height 9))

(overlay-qa-register-command
 "overlay-maxheight" "Test maxHeight truncation"
 "Maximum Height"
 (loop for index from 1 to 30 collect (format nil "Scrollable row ~D" index))
 '(:anchor :center :width 40 :max-height 10))

(overlay-qa-register-command
 "overlay-sidepanel" "Responsive sidepanel"
 "Responsive Side Panel" '("Visible at 100 columns or wider")
 '(:anchor :right-center :width 38 :max-height 18
   :visible-p (lambda (columns rows) (declare (ignore rows)) (>= columns 100))))

(overlay-qa-register-command
 "overlay-toggle" "Toggle visibility with an overlay handle"
 "Visibility Toggle" '("The handle hides and restores this overlay")
 '(:anchor :center :width 46)
 :handler
 (lambda (arguments context)
   (declare (ignore arguments))
   (let ((handle nil))
     (overlay-qa-show
      context "Visibility Toggle"
      '("The handle was returned before the dialog completed")
      '(:anchor :center :width 46)
      :on-handle (lambda (value) (setf handle value)))
     (when handle
       (cadr-tui:overlay-handle-set-hidden handle nil)))))

(overlay-qa-register-command
 "overlay-passive" "Test a non-capturing information panel"
 "Passive Overlay" '("Input remains with the editor")
 '(:anchor :top-right :width 36 :non-capturing t :focus nil))

(overlay-qa-register-command
 "overlay-focus" "Test focus routing and dismissal order"
 "Overlay Focus" '("Tab/focus behavior uses the overlay stack")
 '(:anchor :center :width 44 :focus t))

(overlay-qa-register-command
 "overlay-streaming" "Test multiple streaming input panels"
 "Streaming Panels" '("Tab cycles focus" "Background panels keep rendering")
 '(:anchor :center :width 52 :max-height 18) :animation-p t)
