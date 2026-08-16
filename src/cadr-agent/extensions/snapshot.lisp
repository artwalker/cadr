(in-package #:cadr-agent)

(defun make-extension-host
    (&key
       (cwd (uiop:getcwd))
       (mode :repl)
       notify-function
       reload-function
       ui-function
       send-message-function
       send-user-message-function
       set-session-name-function
       exec-function
       http-request-function
       action-function
       get-flag-function
       get-active-tools-function
       set-active-tools-function)
  (%make-extension-host
   :cwd
   (uiop:ensure-directory-pathname
    (pathname cwd))
   :mode mode
   :notify-function
   (or
    notify-function
    (lambda (message level)
      (format *error-output*
              "~&extension[~(~A~)]> ~A~%"
              level message)
      (finish-output *error-output*)))
   :reload-function reload-function
   :ui-function ui-function
   :send-message-function send-message-function
   :send-user-message-function send-user-message-function
   :set-session-name-function set-session-name-function
   :exec-function exec-function
   :http-request-function http-request-function
   :action-function action-function
   :get-flag-function get-flag-function
   :get-active-tools-function get-active-tools-function
   :set-active-tools-function set-active-tools-function))

(defun extension-definition-origin (definition)
  (extension-bundle-path
   (etypecase definition
     (extension-tool-definition
      (extension-tool-definition-bundle definition))
     (extension-command-definition
      (extension-command-definition-bundle definition))
     (extension-hook-definition
      (extension-hook-definition-bundle definition))
     (extension-template-definition
      (extension-template-definition-bundle definition))
     (extension-provider-definition
      (extension-provider-definition-bundle definition))
     (extension-native-provider-definition
      (extension-native-provider-definition-bundle
       definition))
     (extension-shortcut-definition
      (extension-shortcut-definition-bundle definition))
     (extension-flag-definition
      (extension-flag-definition-bundle definition))
     (extension-renderer-definition
      (extension-renderer-definition-bundle definition))
     (extension-markdown-transformer-definition
      (extension-markdown-transformer-definition-bundle
       definition))
     (extension-tool-renderer-definition
      (extension-tool-renderer-definition-bundle
       definition)))))

(defun extension-conflict
    (kind name winner loser)
  (format nil
          "~A ~S from ~A conflicts with ~A; using ~A"
          kind name
          (extension-definition-origin loser)
          (extension-definition-origin winner)
          (extension-definition-origin winner)))

(defun add-first-definition
    (table ordered definition key kind conflicts)
  (let* ((name (funcall key definition))
         (winner (gethash name table)))
    (if winner
        (push
         (extension-conflict kind name winner definition)
         (symbol-value conflicts))
        (progn
          (setf (gethash name table) definition)
          (setf (symbol-value ordered)
                (nconc
                 (symbol-value ordered)
                 (list definition)))))))

(defun add-last-definition
    (table ordered definition key kind conflicts)
  (let* ((name (funcall key definition))
         (previous (gethash name table)))
    (when previous
      (push
       (extension-conflict kind name definition previous)
       (symbol-value conflicts))
      (setf
       (symbol-value ordered)
       (remove previous
               (symbol-value ordered)
               :test #'eq)))
    (setf (gethash name table) definition)
    (setf
     (symbol-value ordered)
     (nconc (symbol-value ordered)
            (list definition)))))

(defun make-extension-snapshot-from-bundles (bundles)
  (let ((tool-table (make-hash-table :test #'equal))
        (command-table (make-hash-table :test #'equal))
        (template-table (make-hash-table :test #'equal))
        (native-provider-table
          (make-hash-table :test #'eq))
        (shortcut-table (make-hash-table :test #'equal))
        (flag-table (make-hash-table :test #'equal))
        (message-renderer-table
          (make-hash-table :test #'equal))
        (entry-renderer-table
          (make-hash-table :test #'equal))
        (tool-renderer-table
          (make-hash-table :test #'equal))
        (*tools* nil)
        (*commands* nil)
        (*templates* nil)
        (*native-providers* nil)
        (*shortcuts* nil)
        (*flags* nil)
        (*message-renderers* nil)
        (*markdown-transformers* nil)
        (*entry-renderers* nil)
        (*tool-renderers* nil)
        (*conflicts* nil)
        (hooks (make-hash-table :test #'eq)))
    (declare
     (special *tools* *commands* *templates*
              *native-providers*
              *shortcuts* *flags*
              *message-renderers* *markdown-transformers*
              *entry-renderers*
              *tool-renderers*
              *conflicts*))
    (dolist (bundle bundles)
      (dolist (definition (extension-bundle-tools bundle))
        (add-first-definition
         tool-table '*tools* definition
         #'extension-tool-definition-name
         "Tool" '*conflicts*))
      (dolist (definition (extension-bundle-commands bundle))
        (add-first-definition
         command-table '*commands* definition
         #'extension-command-definition-name
         "Command" '*conflicts*))
      (dolist (definition (extension-bundle-templates bundle))
        (add-first-definition
         template-table '*templates* definition
         #'extension-template-definition-name
         "Prompt template" '*conflicts*))
      (dolist
          (definition
           (extension-bundle-native-providers bundle))
        (add-first-definition
         native-provider-table
         '*native-providers*
         definition
         (lambda (entry)
           (cadr-ai:runtime-provider-id
            (extension-native-provider-definition-provider
             entry)))
         "Native provider" '*conflicts*))
      (dolist (definition
               (extension-bundle-shortcuts bundle))
        (add-last-definition
         shortcut-table '*shortcuts* definition
         #'extension-shortcut-definition-key
         "Shortcut" '*conflicts*))
      (dolist (definition
               (extension-bundle-flags bundle))
        (add-first-definition
         flag-table '*flags* definition
         #'extension-flag-definition-name
         "Flag" '*conflicts*))
      (dolist (definition
               (extension-bundle-message-renderers
                bundle))
        (add-first-definition
         message-renderer-table
         '*message-renderers* definition
         #'extension-renderer-definition-custom-type
         "Message renderer" '*conflicts*))
      (when
          (extension-bundle-markdown-transformer bundle)
        (setf
         *markdown-transformers*
         (nconc
          *markdown-transformers*
          (list
           (extension-bundle-markdown-transformer
            bundle)))))
      (dolist (definition
               (extension-bundle-entry-renderers
                bundle))
        (add-first-definition
         entry-renderer-table
         '*entry-renderers* definition
         #'extension-renderer-definition-custom-type
         "Entry renderer" '*conflicts*))
      (dolist (definition
               (extension-bundle-tool-renderers bundle))
        (add-first-definition
         tool-renderer-table
         '*tool-renderers* definition
         #'extension-tool-renderer-definition-tool-name
         "Tool renderer" '*conflicts*))
      (dolist (definition (extension-bundle-hooks bundle))
        (push definition
              (gethash
               (extension-hook-definition-event definition)
               hooks))))
    (maphash
     (lambda (event definitions)
       (declare (ignore event))
       (setf definitions (nreverse definitions))
       (setf
        (gethash
         (extension-hook-definition-event
          (first definitions))
         hooks)
        (stable-sort
         definitions
         #'<
         :key #'extension-hook-definition-priority)))
     hooks)
    (make-extension-snapshot
     :bundles (copy-list bundles)
     :tools *tools*
     :commands *commands*
     :templates *templates*
     :native-providers *native-providers*
     :shortcuts *shortcuts*
     :flags *flags*
     :message-renderers *message-renderers*
     :markdown-transformers *markdown-transformers*
     :entry-renderers *entry-renderers*
     :tool-renderers *tool-renderers*
     :hooks hooks
     :conflicts (nreverse *conflicts*))))

(defun release-extension-snapshot (snapshot)
  (unless (extension-snapshot-released-p snapshot)
    (setf (extension-snapshot-released-p snapshot) t)
    (dolist (bundle (extension-snapshot-bundles snapshot))
      (decf (extension-bundle-snapshot-references bundle))
      (when
          (and
           (zerop
            (extension-bundle-snapshot-references bundle))
           (extension-bundle-package bundle)
           (find-package
            (package-name
             (extension-bundle-package bundle))))
        (ignore-errors
          (delete-package
           (extension-bundle-package bundle)))))))

(defun maybe-release-extension-snapshot (snapshot)
  (when
      (and
       (extension-snapshot-retired-p snapshot)
       (zerop (extension-snapshot-active-count snapshot)))
    (release-extension-snapshot snapshot)))

(defun replace-extension-bundles (host bundles)
  (let ((snapshot
          (make-extension-snapshot-from-bundles bundles))
        (old nil))
    (sb-thread:with-mutex
        ((extension-host-lock host))
      (dolist (bundle
               (extension-snapshot-bundles snapshot))
        (incf
         (extension-bundle-snapshot-references bundle)))
      (setf old (extension-host-snapshot host)
            (extension-host-snapshot host) snapshot)
      (dolist (flag (extension-snapshot-flags snapshot))
        (multiple-value-bind (value present-p)
            (gethash
             (extension-flag-definition-name flag)
             (extension-host-flag-values host))
          (declare (ignore value))
          (unless present-p
            (setf
             (gethash
              (extension-flag-definition-name flag)
              (extension-host-flag-values host))
             (extension-flag-definition-default flag)))))
      (setf (extension-snapshot-retired-p old) t)
      (maybe-release-extension-snapshot old))
    ;; pi@914cf1472 extensions/loader.ts:205-218,410-424 — invalidating
    ;; stale extension contexts eagerly unsubscribes their event-bus
    ;; listeners; prune every listener whose bundle left the snapshot.
    (let ((live-bundles
            (extension-snapshot-bundles snapshot)))
      (sb-thread:with-mutex
          ((extension-host-event-lock host))
        (loop for name being the hash-keys
                of (extension-host-event-listeners host)
              do
              (setf
               (gethash name
                        (extension-host-event-listeners host))
               (remove-if-not
                (lambda (listener)
                  (let ((bundle
                          (extension-event-listener-bundle
                           listener)))
                    (or
                     (eq bundle
                         *extension-registration-bundle*)
                     (member bundle live-bundles
                             :test #'eq))))
                (gethash name
                         (extension-host-event-listeners
                          host)))))))
    (when (extension-host-agent host)
      (refresh-agent-extension-tools
       (extension-host-agent host))
      (apply-extension-provider-overlays host))
    (copy-list
     (extension-snapshot-conflicts snapshot))))

(defun acquire-extension-snapshot
    (host &optional snapshot)
  (sb-thread:with-mutex
      ((extension-host-lock host))
    (let ((resolved
            (or snapshot
                (extension-host-snapshot host))))
      (incf (extension-snapshot-active-count resolved))
      resolved)))

(defun release-acquired-extension-snapshot
    (host snapshot)
  (sb-thread:with-mutex
      ((extension-host-lock host))
    (decf (extension-snapshot-active-count snapshot))
    (maybe-release-extension-snapshot snapshot)))

(defun call-with-extension-definition
    (host snapshot definition function)
  (let* ((held
           (acquire-extension-snapshot host snapshot))
         (context
           (%make-extension-context
            :host host
            :source-path
            (extension-definition-origin definition)
            :bundle
            (etypecase definition
              (extension-tool-definition
               (extension-tool-definition-bundle definition))
              (extension-command-definition
               (extension-command-definition-bundle definition))
              (extension-hook-definition
               (extension-hook-definition-bundle definition))
              (extension-template-definition
               (extension-template-definition-bundle definition))
              (extension-provider-definition
               (extension-provider-definition-bundle
                definition))
              (extension-shortcut-definition
               (extension-shortcut-definition-bundle
                definition))
              (extension-flag-definition
               (extension-flag-definition-bundle
                definition))
              (extension-renderer-definition
               (extension-renderer-definition-bundle
                definition))
              (extension-tool-renderer-definition
               (extension-tool-renderer-definition-bundle
                definition)))
            :kind
            (etypecase definition
              (extension-tool-definition :tool)
              (extension-command-definition :command)
              (extension-hook-definition :event)
              (extension-template-definition :template)
              (extension-provider-definition :provider)
              (extension-shortcut-definition :shortcut)
              (extension-flag-definition :flag)
              (extension-renderer-definition :renderer)
              (extension-tool-renderer-definition
               :tool-renderer)))))
    (unwind-protect
         (funcall function context)
      (setf (%extension-context-active-p context) nil)
      (release-acquired-extension-snapshot host held))))
