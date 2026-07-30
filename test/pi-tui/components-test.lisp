(in-package #:pi-tui/tests)
(in-suite pi-tui-suite)

(test markdown-renders-incomplete-stream
  (let ((lines
          (pi-tui:render-markdown
           (format nil "# 标题~%~%- one~%> quote~%```lisp~%(+ 1 2)")
           20)))
    (is (search "标题" (first lines)))
    (is (find-if (lambda (line) (search "• one" line)) lines))
    (is (find-if (lambda (line) (search "│ quote" line)) lines))
    (is (find-if (lambda (line) (search "(+ 1 2)" line)) lines))))

(test markdown-consumes-inline-delimiters
  (let ((rendered
          (format nil "~{~A~%~}"
                  (pi-tui:render-markdown
                   "Use **bold** and `code` now."
                   40))))
    (is (search "Use bold and code now." rendered))
    (is (null (search "**" rendered)))
    (is (null (search "`" rendered)))))

(test tool-block-is-collapsible
  (let ((block
          (pi-tui:make-tool-block
           :name "read"
           :summary "{\"path\":\"README.md\"}"
           :output (format nil "line one~%line two")
           :status :complete)))
    (is (= 1 (length (pi-tui:render-tool-block block 40))))
    (pi-tui:toggle-tool-block block)
    (is (> (length (pi-tui:render-tool-block block 40)) 1))
    (is (search "line one"
                (format nil "~{~A~%~}"
                        (pi-tui:render-tool-block block 40))))))

(test status-bar-and-select-list
  (is (search "in:12"
              (pi-tui:render-status-bar
               80 :model "gemini-3.6-flash"
               :input 12 :output 4 :cache 2
               :cost nil :session "abc")))
  (let ((list
          (pi-tui:make-select-list
           :items (list
                   (pi-tui:make-select-item :label "OpenAI / gpt" :value :gpt)
                   (pi-tui:make-select-item :label "Google / gemini" :value :gemini))
           :height 3)))
    (pi-tui:select-list-handle-event
     list (pi-tui:make-input-event :kind :text :text "gem"))
    (is (= 1 (length (pi-tui:select-list-filtered-items list))))
    (multiple-value-bind (action value)
        (pi-tui:select-list-handle-event
         list (pi-tui:make-input-event :kind :enter))
      (is (eq :select action))
      (is (eq :gemini value)))
    (pi-tui:select-list-handle-event
     list (pi-tui:make-input-event :kind :escape))
    (is (string= "gem" (pi-tui:select-list-query list)))))
