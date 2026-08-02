(load (merge-pathnames "support.lisp" *load-truename*))

(defun questionnaire-sequence-list (value)
  (cond ((vectorp value) (coerce value 'list))
        ((listp value) value)
        (t nil)))

(defun questionnaire-normalize-question (object index)
  (list
   :id (or (cadr-ai::json-get object "id") (format nil "q~D" (1+ index)))
   :label (or (cadr-ai::json-get object "label") (format nil "Q~D" (1+ index)))
   :prompt (or (cadr-ai::json-get object "prompt") "")
   :allow-other-p (not (eq :false (cadr-ai::json-get object "allowOther" t)))
   :options
   (loop for option in
           (questionnaire-sequence-list
            (cadr-ai::json-get object "options" #()))
         collect
         (list :value (or (cadr-ai::json-get option "value") "")
               :label (or (cadr-ai::json-get option "label") "")
               :description (cadr-ai::json-get option "description")))))

(defclass questionnaire-component (cadr-tui:component)
  ((tui :initarg :tui :reader questionnaire-tui)
   (questions :initarg :questions :reader questionnaire-questions)
   (current :initform 0 :accessor questionnaire-current)
   (selected :initform 0 :accessor questionnaire-selected)
   (answers :initform (make-hash-table :test #'equal)
            :reader questionnaire-answers)
   (input-mode-p :initform nil :accessor questionnaire-input-mode-p)
   (editor :initform (cadr-tui:make-multiline-editor)
           :reader questionnaire-editor)
   (done :initarg :done :reader questionnaire-done)))

(defun questionnaire-current-question (component)
  (nth (questionnaire-current component)
       (questionnaire-questions component)))

(defun questionnaire-options (question)
  (append (copy-list (getf question :options))
          (and (getf question :allow-other-p)
               (list (list :value "__other__"
                           :label "Type something."
                           :other-p t)))))

(defun questionnaire-finish (component cancelled-p)
  (funcall
   (questionnaire-done component)
   (list
    :questions (questionnaire-questions component)
    :answers
    (loop for question in (questionnaire-questions component)
          for answer = (gethash (getf question :id)
                                (questionnaire-answers component))
          when answer collect answer)
    :cancelled-p cancelled-p)))

(defmethod cadr-tui:component-render
    ((component questionnaire-component) width &key focused-p)
  (declare (ignore focused-p))
  (let* ((questions (questionnaire-questions component))
         (index (questionnaire-current component))
         (question (questionnaire-current-question component))
         (options (questionnaire-options question))
         (lines
           (list
            (make-string (max 1 width) :initial-element #\─)
            (format nil "~{~:[□~;■~] ~A~^  ~}"
                    (loop for item in questions
                          append
                          (list
                           (not (null
                                 (gethash (getf item :id)
                                          (questionnaire-answers component))))
                           (getf item :label))))
            ""
            (getf question :prompt)
            "")))
    (setf lines
          (append
           lines
           (loop for option in options
                 for option-index from 0
                 collect
                 (format nil "~:[  ~;> ~]~D. ~A~@[ — ~A~]"
                         (= option-index (questionnaire-selected component))
                         (1+ option-index)
                         (getf option :label)
                         (getf option :description)))))
    (when (questionnaire-input-mode-p component)
      (multiple-value-bind (editor-lines row column)
          (cadr-tui:render-editor
           (questionnaire-editor component) (max 1 (- width 2)))
        (declare (ignore row column))
        (setf lines
              (append lines '("" "Your answer:") editor-lines))))
    (append
     lines
     (list ""
           (if (> (length questions) 1)
               "Tab/←→ navigate · ↑↓ select · Enter confirm · Esc cancel"
               "↑↓ navigate · Enter select · Esc cancel")
           (make-string (max 1 width) :initial-element #\─)))))

(defmethod cadr-tui:component-handle-event
    ((component questionnaire-component) event)
  (let ((kind (cadr-tui:input-event-kind event)))
    (cond
      ((questionnaire-input-mode-p component)
       (case kind
         (:escape
          (setf (questionnaire-input-mode-p component) nil)
          (cadr-tui:editor-set-text (questionnaire-editor component) ""))
         (:enter
          (let ((text (example-trim
                       (cadr-tui:editor-text
                        (questionnaire-editor component))))
                (question (questionnaire-current-question component)))
            (setf
             (gethash (getf question :id)
                      (questionnaire-answers component))
             (list :id (getf question :id) :value text :label text
                   :custom-p t))
            (setf (questionnaire-input-mode-p component) nil)
            (if (= (1+ (questionnaire-current component))
                   (length (questionnaire-questions component)))
                (questionnaire-finish component nil)
                (incf (questionnaire-current component)))))
         (otherwise
          (cadr-tui:editor-handle-event
           (questionnaire-editor component) event))))
      (t
       (let* ((question (questionnaire-current-question component))
              (options (questionnaire-options question))
              (count (length options)))
         (case kind
           (:up
            (setf (questionnaire-selected component)
                  (mod (1- (questionnaire-selected component)) count)))
           (:down
            (setf (questionnaire-selected component)
                  (mod (1+ (questionnaire-selected component)) count)))
           ((:left)
            (setf (questionnaire-current component)
                  (mod (1- (questionnaire-current component))
                       (length (questionnaire-questions component)))
                  (questionnaire-selected component) 0))
           ((:right :tab)
            (setf (questionnaire-current component)
                  (mod (1+ (questionnaire-current component))
                       (length (questionnaire-questions component)))
                  (questionnaire-selected component) 0))
           (:enter
            (let ((option (nth (questionnaire-selected component) options)))
              (if (getf option :other-p)
                  (setf (questionnaire-input-mode-p component) t)
                  (progn
                    (setf
                     (gethash (getf question :id)
                              (questionnaire-answers component))
                     (list :id (getf question :id)
                           :value (getf option :value)
                           :label (getf option :label)
                           :custom-p nil
                           :index (1+ (questionnaire-selected component))))
                    (if (= (hash-table-count
                            (questionnaire-answers component))
                           (length (questionnaire-questions component)))
                        (questionnaire-finish component nil)
                        (setf (questionnaire-current component)
                              (mod (1+ (questionnaire-current component))
                                   (length
                                    (questionnaire-questions component)))
                              (questionnaire-selected component) 0))))))
           ((:escape :cancel :interrupt)
            (questionnaire-finish component t))))))
    (cadr-tui:tui-request-render (questionnaire-tui component))
    (values nil nil)))

(defparameter *questionnaire-schema*
  (cadr-ai::json-object
   "type" "object"
   "properties"
   (cadr-ai::json-object
    "questions"
    (cadr-ai::json-object
     "type" "array"
     "items"
     (cadr-ai::json-object
      "type" "object"
      "properties"
      (cadr-ai::json-object
       "id" (cadr-ai::json-object "type" "string")
       "label" (cadr-ai::json-object "type" "string")
       "prompt" (cadr-ai::json-object "type" "string")
       "options" (cadr-ai::json-object "type" "array")
       "allowOther" (cadr-ai::json-object "type" "boolean"))
      "required" #("id" "prompt" "options"))))
   "required" #("questions")
   "additionalProperties" nil))

(cadr-agent:define-rich-tool
 "questionnaire"
 :label "Questionnaire"
 :description "Ask the user one or more option questions in a tabbed interface"
 :parameters *questionnaire-schema*
 :execution-mode :sequential
 :handler
 (lambda (call-id arguments signal on-update context)
   (declare (ignore call-id signal on-update))
   (let* ((raw
            (questionnaire-sequence-list
             (example-argument arguments "questions" #())))
          (questions
            (loop for object in raw for index from 0
                  collect (questionnaire-normalize-question object index))))
     (cond
       ((not (cadr-agent:extension-context-has-ui-p context))
        (example-result
         "Error: UI not available (running in non-interactive mode)"
         :details (list :questions questions :answers nil :cancelled-p t)))
       ((null questions)
        (example-result
         "Error: No questions provided"
         :details (list :questions nil :answers nil :cancelled-p t)))
       (t
        (let ((result
                (cadr-agent:extension-context-custom-component
                 context
                 (lambda (tui theme keybindings done)
                   (declare (ignore theme keybindings))
                   (make-instance 'questionnaire-component
                                  :tui tui :questions questions :done done)))))
          (if (getf result :cancelled-p)
              (example-result "User cancelled the questionnaire" :details result)
              (example-result
               (format nil "~{~A~^~%~}"
                       (mapcar
                        (lambda (answer)
                          (let ((label
                                  (getf
                                   (find (getf answer :id) questions
                                         :key (lambda (question)
                                                (getf question :id))
                                         :test #'string=)
                                   :label)))
                            (if (getf answer :custom-p)
                                (format nil "~A: user wrote: ~A"
                                        label (getf answer :label))
                                (format nil "~A: user selected: ~D. ~A"
                                        label (getf answer :index)
                                        (getf answer :label)))))
                        (getf result :answers)))
               :details result))))))
 :render-call
 (lambda (arguments render-context theme)
   (declare (ignore render-context theme))
   (let ((questions
           (questionnaire-sequence-list
            (example-argument arguments "questions" #()))))
     (format nil "questionnaire ~D question~:P"
             (length questions))))
 :render-result
 (lambda (result options render-context theme)
   (declare (ignore options render-context theme))
   (example-tool-result-text result))))
