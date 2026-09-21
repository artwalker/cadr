(in-package #:cadr-cli)

(defun anthropic-input-transformations-diagnostic-p (diagnostic)
  (member
   (cadr-ai:assistant-message-diagnostic-type diagnostic)
   '(:anthropic-input-transformations
     :anthropic_input_transformations)
   :test #'eq))

(defun thinking-dropped-transformation-p (transformation)
  (let ((type (getf transformation :type)))
    (or (and (stringp type) (string= type "thinking_dropped"))
        (eq type :thinking-dropped)
        (eq type :thinking_dropped))))

(defun count-dropped-thinking-blocks (message)
  (unless (typep message 'cadr-ai:assistant-message)
    (return-from count-dropped-thinking-blocks 0))
  (loop for diagnostic in
        (cadr-ai:assistant-message-diagnostics message)
        when (anthropic-input-transformations-diagnostic-p
              diagnostic)
          sum
          (let ((transformations
                  (getf
                   (cadr-ai:assistant-message-diagnostic-details
                    diagnostic)
                   :transformations)))
            (if (listp transformations)
                (count-if
                 #'thinking-dropped-transformation-p
                 transformations)
                0))))

(defun thinking-drop-notice-text (count)
  (format
   nil
   "Anthropic dropped ~D thinking ~A (details in session)"
   count
   (if (= count 1) "block" "blocks")))

(defun maybe-show-thinking-drop-notice (state message)
  (let ((dropped (count-dropped-thinking-blocks message)))
    (when (and (tui-state-show-cache-miss-notices-p state)
               (plusp dropped)
               (> dropped
                  (tui-state-last-thinking-drop-count state)))
      (add-tui-warning
       state
       (thinking-drop-notice-text dropped)))
    (setf (tui-state-last-thinking-drop-count state) dropped))
  state)
