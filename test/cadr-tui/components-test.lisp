(in-package #:cadr-tui/tests)
(in-suite cadr-tui-suite)

(test markdown-renders-incomplete-stream
  (let ((lines
          (cadr-tui:render-markdown
           (format nil "# 标题~%~%- one~%> quote~%```lisp~%(+ 1 2)")
           20)))
    (is (search "标题" (first lines)))
    (is (find-if (lambda (line) (search "• one" line)) lines))
    (is (find-if (lambda (line) (search "│ quote" line)) lines))
    (is (find-if (lambda (line) (search "(+ 1 2)" line)) lines))))

(test markdown-consumes-inline-delimiters
  (let ((rendered
          (format nil "~{~A~%~}"
                  (cadr-tui:render-markdown
                   "Use **bold** and `code` now."
                   40))))
    (is (search "Use bold and code now." rendered))
    (is (null (search "**" rendered)))
    (is (null (search "`" rendered)))))

(test tool-block-is-collapsible
  (let ((block
          (cadr-tui:make-tool-block
           :name "read"
           :summary "{\"path\":\"README.md\"}"
           :output (format nil "line one~%line two")
           :status :complete)))
    (is (= 1 (length (cadr-tui:render-tool-block block 40))))
    (cadr-tui:toggle-tool-block block)
    (is (> (length (cadr-tui:render-tool-block block 40)) 1))
    (is (search "line one"
                (format nil "~{~A~%~}"
                        (cadr-tui:render-tool-block block 40))))))

(test tool-block-recomputes-width-on-every-render
  (let ((block
          (cadr-tui:make-tool-block
           :name "bash"
           :summary
           (make-string 200
                        :initial-element #\x)
           :output
           (make-string 200
                        :initial-element #\y)
           :status :complete)))
    (dolist (width '(200 80 60))
      (dolist
          (line
           (cadr-tui:render-tool-block
            block width))
        (is
         (<=
          (cadr-tui:visible-width line)
          width))))))

(test status-bar-and-select-list
  (is (search "in:12"
              (cadr-tui:render-status-bar
               80 :model "gemini-3.6-flash"
               :input 12 :output 4 :cache 2
               :cost nil :session "abc")))
  (let ((list
          (cadr-tui:make-select-list
           :items (list
                   (cadr-tui:make-select-item :label "OpenAI / gpt" :value :gpt)
                   (cadr-tui:make-select-item :label "Google / gemini" :value :gemini))
           :height 3)))
    (cadr-tui:select-list-handle-event
     list (cadr-tui:make-input-event :kind :text :text "gem"))
    (is (= 1 (length (cadr-tui:select-list-filtered-items list))))
    (multiple-value-bind (action value)
        (cadr-tui:select-list-handle-event
         list (cadr-tui:make-input-event :kind :enter))
      (is (eq :select action))
      (is (eq :gemini value)))
    (cadr-tui:select-list-handle-event
     list (cadr-tui:make-input-event :kind :escape))
    (is (string= "gem" (cadr-tui:select-list-query list)))))
