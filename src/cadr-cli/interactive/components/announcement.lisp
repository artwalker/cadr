(in-package #:cadr-cli)

(defparameter +earendil-blog-url+
  "https://mariozechner.at/posts/2026-04-08-ive-sold-out/")

(defparameter +earendil-announcement-image-filename+
  "clankolas.png")

(defparameter +earendil-announcement-image-max-width-cells+
  56)

;; The bytes live in assets/interactive/, outside src/. The organization
;; gate reads every file under src/ as UTF-8, and this PNG is not text.
(defparameter +earendil-announcement-image-relative+
  "assets/interactive/clankolas.png")

(defvar *earendil-announcement-image-base64* :unloaded)

(defun read-bundled-interactive-asset-base64 (relative)
  "Standard base64 of a file under the cadr-cli system root, or NIL.
A missing or unreadable file is the same outcome as a failed
readFileSync in the announcement loader."
  (handler-case
      (let ((path
              (asdf:system-relative-pathname
               "cadr-cli" relative)))
        (with-open-file
            (stream path
                    :element-type '(unsigned-byte 8)
                    :if-does-not-exist nil)
          (unless stream
            (return-from
                read-bundled-interactive-asset-base64 nil))
          (let* ((length (file-length stream))
                 (bytes
                   (make-array
                    length
                    :element-type '(unsigned-byte 8)))
                 (read (read-sequence bytes stream)))
            (encode-base64-bytes
             (if (= read length)
                 bytes
                 (subseq bytes 0 read))))))
    (error () nil)))

(defun earendil-announcement-image-base64 ()
  (when (eq *earendil-announcement-image-base64* :unloaded)
    (setf *earendil-announcement-image-base64*
          (read-bundled-interactive-asset-base64
           +earendil-announcement-image-relative+)))
  *earendil-announcement-image-base64*)

(defun make-earendil-announcement-component ()
  (let ((component (cadr-tui:make-component-container))
        (image-base64 (earendil-announcement-image-base64)))
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
    (when image-base64
      (cadr-tui:component-add-child
       component
       (cadr-tui:make-image-component
        image-base64 "image/png"
        :fallback-color-function
        (lambda (text)
          (cadr-tui:theme-foreground :muted text))
        :filename +earendil-announcement-image-filename+
        :max-width-cells
        +earendil-announcement-image-max-width-cells+))
      (cadr-tui:component-add-child
       component (cadr-tui:make-spacer-component :lines 1)))
    (cadr-tui:component-add-child
     component
     (make-dynamic-border-component
      :color-function
      (lambda (text)
        (cadr-tui:theme-foreground :accent text))))
    component))
