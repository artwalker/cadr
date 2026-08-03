(in-package #:cadr-cli)

(defparameter +earendil-blog-url+
  "https://mariozechner.at/posts/2026-04-08-ive-sold-out/")

(defun make-earendil-announcement-component ()
  (let ((component (cadr-tui:make-component-container)))
    (cadr-tui:component-add-child
     component
     (make-dynamic-border-component
      :color-function
      (lambda (text)
        (cadr-tui:theme-foreground :accent text))))
    (cadr-tui:component-add-child
     component
     (cadr-tui:make-text-component
      (cadr-tui:theme-bold
       (cadr-tui:theme-foreground
        :accent "pi has joined Earendil"))
      :padding-x 1 :padding-y 0))
    (cadr-tui:component-add-child
     component (cadr-tui:make-spacer-component :lines 1))
    (cadr-tui:component-add-child
     component
     (cadr-tui:make-text-component
      (cadr-tui:theme-foreground :muted "Read the blog post:")
      :padding-x 1 :padding-y 0))
    (cadr-tui:component-add-child
     component
     (cadr-tui:make-text-component
      (cadr-tui:theme-foreground :md-link +earendil-blog-url+)
      :padding-x 1 :padding-y 0))
    (cadr-tui:component-add-child
     component (cadr-tui:make-spacer-component :lines 1))
    (cadr-tui:component-add-child
     component
     (make-dynamic-border-component
      :color-function
      (lambda (text)
        (cadr-tui:theme-foreground :accent text))))
    component))
