(in-package #:cadr-agent)

(defun notify-extension-failure
    (host definition phase condition)
  (funcall
   (extension-host-notify-function host)
   (format nil "~A ~A failed in ~A: ~A"
           phase
           (extension-definition-origin definition)
           (typecase definition
             (extension-tool-definition
              (extension-tool-definition-name definition))
             (extension-command-definition
              (extension-command-definition-name definition))
             (extension-hook-definition
              (extension-hook-definition-event definition))
             (extension-template-definition
              (extension-template-definition-name definition))
             (extension-provider-definition
              (extension-provider-id definition))
             (extension-shortcut-definition
              (extension-shortcut-definition-key definition))
             (extension-flag-definition
              (extension-flag-definition-name definition))
             (extension-renderer-definition
              (extension-renderer-definition-custom-type
               definition))
             (extension-markdown-transformer-definition
              :markdown)
             (extension-tool-renderer-definition
              (extension-tool-renderer-definition-tool-name
               definition)))
           condition)
   :error))

(defun extension-host-current-snapshot (host)
  (sb-thread:with-mutex
      ((extension-host-lock host))
    (extension-host-snapshot host)))

(defun extension-host-conflicts (host)
  (copy-list
   (extension-snapshot-conflicts
    (extension-host-current-snapshot host))))

(defun extension-host-shortcuts (host)
  (copy-list
   (extension-snapshot-shortcuts
    (extension-host-current-snapshot host))))

(defun extension-host-flags (host)
  (copy-list
   (extension-snapshot-flags
    (extension-host-current-snapshot host))))

(defun find-extension-renderer
    (host custom-type accessor)
  (find
   custom-type
   (funcall
    accessor
    (extension-host-current-snapshot host))
   :key #'extension-renderer-definition-custom-type
   :test #'string=))

(defun find-extension-message-renderer
    (host custom-type)
  (find-extension-renderer
   host custom-type
   #'extension-snapshot-message-renderers))

(defun extension-host-markdown-transformers (host)
  (copy-list
   (extension-snapshot-markdown-transformers
    (extension-host-current-snapshot host))))

(defun transform-extension-markdown
    (host markdown context)
  (let* ((snapshot
           (extension-host-current-snapshot host))
         (current markdown))
    (acquire-extension-snapshot host snapshot)
    (unwind-protect
         (dolist
             (definition
              (extension-snapshot-markdown-transformers
               snapshot)
              current)
           (handler-case
               (let ((transformed
                       (funcall
                        (extension-markdown-transformer-definition-transformer
                         definition)
                        current
                        (copy-list context))))
                 (when (stringp transformed)
                   (setf current transformed)))
             (condition (condition)
               (notify-extension-failure
                host definition
                "Markdown transformer"
                condition))))
      (release-acquired-extension-snapshot
       host snapshot))))

(defun find-extension-entry-renderer
    (host custom-type)
  (find-extension-renderer
   host custom-type
   #'extension-snapshot-entry-renderers))

(defun find-extension-tool-renderer
    (host tool-name)
  (find
   tool-name
   (extension-snapshot-tool-renderers
    (extension-host-current-snapshot host))
   :key
   #'extension-tool-renderer-definition-tool-name
   :test #'string=))

(defun call-extension-renderer
    (host definition phase function arguments)
  (let ((snapshot
          (extension-host-current-snapshot host)))
    (acquire-extension-snapshot host snapshot)
    (unwind-protect
         (handler-case
             (values
              (apply function arguments)
              t)
           (condition (condition)
             (notify-extension-failure
              host definition phase condition)
             (values nil nil)))
      (release-acquired-extension-snapshot
       host snapshot))))

(defun render-extension-named
    (host definition phase payload options theme)
  (if definition
      (call-extension-renderer
       host definition phase
       (extension-renderer-definition-renderer
        definition)
       (if (extension-renderer-definition-component-p
            definition)
           (list payload options theme)
           (list payload options)))
      (values nil nil)))

(defun render-extension-message
    (host custom-type message options &optional theme)
  (render-extension-named
   host
   (find-extension-message-renderer host custom-type)
   "Message renderer"
   message options theme))

(defun render-extension-entry
    (host custom-type entry options &optional theme)
  (render-extension-named
   host
   (find-extension-entry-renderer host custom-type)
   "Entry renderer"
   entry options theme))

(defun render-extension-tool-call
    (host tool-name arguments context)
  (let* ((definition
           (find-extension-tool-renderer
            host tool-name))
         (function
           (and
            definition
            (extension-tool-renderer-definition-call
             definition)))
         (rich-definition
           (and (null function)
                (find tool-name
                      (extension-snapshot-tools
                       (extension-host-current-snapshot host))
                      :key #'extension-tool-definition-name
                      :test #'string=)))
         (rich-function
           (and rich-definition
                (extension-tool-definition-render-call rich-definition))))
    (cond
      (function
        (call-extension-renderer
         host definition "Tool call renderer"
         function (list arguments context)))
      (rich-function
       (call-extension-renderer
        host rich-definition "Rich tool call renderer"
        rich-function
        (list arguments (getf context :theme) context)))
      (t (values nil nil)))))

(defun render-extension-tool-result
    (host tool-name result options context)
  (let* ((definition
           (find-extension-tool-renderer
            host tool-name))
         (function
           (and
            definition
             (extension-tool-renderer-definition-result
              definition)))
         (rich-definition
           (and (null function)
                (find tool-name
                      (extension-snapshot-tools
                       (extension-host-current-snapshot host))
                      :key #'extension-tool-definition-name
                      :test #'string=)))
         (rich-function
           (and rich-definition
                (extension-tool-definition-render-result rich-definition))))
    (cond
      (function
        (call-extension-renderer
         host definition "Tool result renderer"
         function
         (list result options context)))
      (rich-function
       (call-extension-renderer
        host rich-definition "Rich tool result renderer"
        rich-function
        (list result options (getf context :theme) context)))
      (t (values nil nil)))))

(defun invoke-extension-shortcut
    (host key)
  (let* ((snapshot
           (extension-host-current-snapshot host))
         (definition
           (find
            key
            (extension-snapshot-shortcuts snapshot)
            :key #'extension-shortcut-definition-key
            :test #'string-equal)))
    (unless definition
      (return-from invoke-extension-shortcut nil))
    (handler-case
        (call-with-extension-definition
         host snapshot definition
         (lambda (context)
           (funcall
            (extension-shortcut-definition-handler
             definition)
            context)))
      (condition (condition)
        (notify-extension-failure
         host definition "Shortcut" condition)))
    t))
