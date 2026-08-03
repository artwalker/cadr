(in-package #:cadr-agent)

;;; Registration model

(defstruct extension-bundle
  (id "" :type string)
  (path "" :type string)
  (scope :global :type symbol)
  (rank 0 :type integer)
  (order 0 :type integer)
  package
  (tools nil :type list)
  (commands nil :type list)
  (hooks nil :type list)
  (templates nil :type list)
  (providers nil :type list)
  (native-providers nil :type list)
  (shortcuts nil :type list)
  (flags nil :type list)
  (message-renderers nil :type list)
  markdown-transformer
  (entry-renderers nil :type list)
  (tool-renderers nil :type list)
  (hidden-p nil :type boolean)
  (snapshot-references 0 :type (integer 0 *)))

(defstruct extension-tool-definition
  name
  label
  description
  prompt-snippet
  (prompt-guidelines nil :type list)
  parameters
  constrained-sampling
  render-shell
  prepare-arguments
  execution-mode
  (full-handler-p nil :type boolean)
  handler
  render-call
  render-result
  bundle)

(defstruct extension-command-definition
  name
  description
  argument-hint
  handler
  bundle)

(defstruct extension-hook-definition
  event
  priority
  handler
  bundle
  order)

(defstruct extension-template-definition
  name
  description
  argument-hint
  template
  bundle)

(defstruct extension-provider-definition
  definition
  (models nil :type list)
  bundle)

(defstruct extension-native-provider-definition
  provider
  bundle)

(defstruct extension-shortcut-definition
  key
  description
  handler
  bundle)

(defstruct extension-flag-definition
  name
  description
  type
  default
  bundle)

(defstruct extension-renderer-definition
  custom-type
  renderer
  (component-p nil :type boolean)
  bundle)

(defstruct extension-markdown-transformer-definition
  transformer
  bundle)

(defstruct extension-tool-renderer-definition
  tool-name
  call
  result
  bundle)

(defun extension-api-registered-flag-p
    (bundle name)
  (find
   name
   (extension-bundle-flags bundle)
   :key #'extension-flag-definition-name
   :test #'string=))

(defun call-with-extension-registration (bundle function)
  (let ((*extension-registration-bundle* bundle))
    (funcall function)))

(defun call-with-extension-load (host bundle function)
  (let ((*extension-registration-bundle* bundle)
        (*extension-registration-api*
          (%make-extension-api
           :host host
           :bundle bundle
           :attachment-generation
           (extension-host-attachment-generation host))))
    (funcall function)))

(defun current-extension-api ()
  (or
   *extension-registration-api*
   (error
    'extension-registration-error
    :message
    "CURRENT-EXTENSION-API is only available while loading an extension")))

(defun require-extension-registration-bundle ()
  (or
   *extension-registration-bundle*
   (error
    'extension-registration-error
    :message
    "Extension definitions are only valid while loading an extension")))

(defun valid-extension-resource-name-p (name)
  (and
   (stringp name)
   (plusp (length name))
   (every
    (lambda (character)
      (or
       (and (char>= character #\a)
            (char<= character #\z))
       (and (char>= character #\A)
            (char<= character #\Z))
       (digit-char-p character)
       (member character '(#\- #\_ #\:))))
    name)))

(defun validate-extension-resource-name (kind name)
  (unless (valid-extension-resource-name-p name)
    (error
     'extension-registration-error
     :message
     (format nil
             "Invalid ~A name ~S; use ASCII letters, digits, -, _, or :"
             kind name)))
  name)

(defun validate-extension-schema (name schema)
  (unless (hash-table-p schema)
    (error
     'extension-registration-error
     :message
     (format nil "Tool ~A parameters must be a JSON Schema hash-table"
             name)))
  (handler-case
      (validate-json-schema-definition schema)
    (error (condition)
      (error
       'extension-registration-error
       :cause condition
       :message
       (format nil "Tool ~A has an invalid JSON Schema: ~A"
               name condition))))
  schema)

(defun ensure-unique-extension-definition
    (definitions name key kind)
  (when (find name definitions :key key :test #'string=)
    (error
     'extension-registration-error
     :message
     (format nil "~A ~A is registered more than once in the same extension"
             kind name))))

(defun register-extension-tool
    (name description parameters execution-mode handler)
  (let ((bundle (require-extension-registration-bundle)))
    (validate-extension-resource-name "tool" name)
    (unless (stringp description)
      (error
       'extension-registration-error
       :message (format nil "Tool ~A description must be a string"
                        name)))
    (validate-extension-schema name parameters)
    (unless (member execution-mode '(:parallel :sequential))
      (error
       'extension-registration-error
       :message
       (format nil "Tool ~A execution mode must be :parallel or :sequential"
               name)))
    (unless (functionp handler)
      (error
       'extension-registration-error
       :message (format nil "Tool ~A handler must be a function"
                        name)))
    (ensure-unique-extension-definition
     (extension-bundle-tools bundle)
     name
     #'extension-tool-definition-name
     "Tool")
    (setf
     (extension-bundle-tools bundle)
     (nconc
      (extension-bundle-tools bundle)
      (list
       (make-extension-tool-definition
        :name name
        :label name
        :description description
        :parameters parameters
        :execution-mode execution-mode
        :handler handler
        :bundle bundle)))))
  name)

(defun register-rich-extension-tool
    (name &key label description prompt-snippet prompt-guidelines
            parameters constrained-sampling render-shell
            prepare-arguments (execution-mode :parallel)
            handler render-call render-result)
  (let ((bundle (require-extension-registration-bundle)))
    (validate-extension-resource-name "tool" name)
    (unless (and (stringp label) (plusp (length label)))
      (error 'extension-registration-error
             :message (format nil "Tool ~A label must be a non-empty string" name)))
    (unless (stringp description)
      (error 'extension-registration-error
             :message (format nil "Tool ~A description must be a string" name)))
    (unless (or (null prompt-snippet) (stringp prompt-snippet))
      (error 'extension-registration-error
             :message (format nil "Tool ~A prompt snippet must be a string or NIL" name)))
    (unless (and (listp prompt-guidelines) (every #'stringp prompt-guidelines))
      (error 'extension-registration-error
             :message (format nil "Tool ~A prompt guidelines must be strings" name)))
    (validate-extension-schema name parameters)
    (unless (or (null constrained-sampling) (listp constrained-sampling))
      (error 'extension-registration-error
             :message (format nil "Tool ~A constrained sampling must be a plist or NIL" name)))
    (unless (member render-shell '(nil :default :self))
      (error 'extension-registration-error
             :message (format nil "Tool ~A render shell must be :DEFAULT, :SELF, or NIL" name)))
    (unless (or (null prepare-arguments) (functionp prepare-arguments))
      (error 'extension-registration-error
             :message (format nil "Tool ~A prepare-arguments must be a function or NIL" name)))
    (unless (member execution-mode '(:parallel :sequential))
      (error 'extension-registration-error
             :message (format nil "Tool ~A execution mode must be :PARALLEL or :SEQUENTIAL" name)))
    (unless (functionp handler)
      (error 'extension-registration-error
             :message (format nil "Tool ~A handler must be a function" name)))
    (unless (and (or (null render-call) (functionp render-call))
                 (or (null render-result) (functionp render-result)))
      (error 'extension-registration-error
             :message (format nil "Tool ~A renderers must be functions or NIL" name)))
    (ensure-unique-extension-definition
     (extension-bundle-tools bundle) name
     #'extension-tool-definition-name "Tool")
    (setf
     (extension-bundle-tools bundle)
     (nconc
      (extension-bundle-tools bundle)
      (list
       (make-extension-tool-definition
        :name name :label label :description description
        :prompt-snippet prompt-snippet
        :prompt-guidelines (copy-list prompt-guidelines)
        :parameters parameters
        :constrained-sampling (copy-tree constrained-sampling)
        :render-shell render-shell
        :prepare-arguments prepare-arguments
        :execution-mode execution-mode :full-handler-p t
        :handler handler :render-call render-call :render-result render-result
        :bundle bundle)))))
  name)

(defun register-extension-command
    (name description argument-hint handler)
  (let ((bundle (require-extension-registration-bundle)))
    (validate-extension-resource-name "command" name)
    (unless (or (null description) (stringp description))
      (error
       'extension-registration-error
       :message
       (format nil "Command ~A description must be a string or NIL"
               name)))
    (unless (or (null argument-hint) (stringp argument-hint))
      (error
       'extension-registration-error
       :message
       (format nil "Command ~A argument hint must be a string or NIL"
               name)))
    (unless (functionp handler)
      (error
       'extension-registration-error
       :message
       (format nil "Command ~A handler must be a function"
               name)))
    (ensure-unique-extension-definition
     (extension-bundle-commands bundle)
     name
     #'extension-command-definition-name
     "Command")
    (setf
     (extension-bundle-commands bundle)
     (nconc
      (extension-bundle-commands bundle)
      (list
       (make-extension-command-definition
        :name name
        :description description
        :argument-hint argument-hint
        :handler handler
        :bundle bundle)))))
  name)

(defparameter +extension-hook-events+
  '(:turn-start
    :turn-end
    :tool-call-before
    :tool-call-after
    :tool-call-error
    :session-start
    :session-info-changed
    :session-before-switch
    :session-before-fork
    :session-before-compact
    :session-compact
    :session-shutdown
    :session-before-tree
    :session-tree
    :context
    :before-agent-start
    :agent-start
    :agent-end
    :agent-settled
    :message-start
    :message-update
    :message-end
    :input
    :tool-execution-start
    :tool-execution-update
    :tool-execution-end
    :model-select
    :thinking-level-select
    :project-trust
    :resources-discover
    :before-provider-request
    :before-provider-headers
    :after-provider-response
    :user-bash))

(defun register-extension-hook
    (event priority handler)
  (let ((bundle (require-extension-registration-bundle)))
    (unless (member event +extension-hook-events+)
      (error
       'extension-registration-error
       :message
       (format nil "Unsupported extension hook event: ~S"
               event)))
    (unless (integerp priority)
      (error
       'extension-registration-error
       :message "Extension hook priority must be an integer"))
    (unless (functionp handler)
      (error
       'extension-registration-error
       :message "Extension hook handler must be a function"))
    (setf
     (extension-bundle-hooks bundle)
     (nconc
      (extension-bundle-hooks bundle)
      (list
       (make-extension-hook-definition
        :event event
        :priority priority
        :handler handler
        :bundle bundle
        :order (length (extension-bundle-hooks bundle)))))))
  event)

(defun register-extension-template
    (name description argument-hint template)
  (let ((bundle (require-extension-registration-bundle)))
    (validate-extension-resource-name "prompt template" name)
    (unless (or (null description) (stringp description))
      (error
       'extension-registration-error
       :message
       (format nil "Prompt template ~A description must be a string or NIL"
               name)))
    (unless (or (null argument-hint) (stringp argument-hint))
      (error
       'extension-registration-error
       :message
       (format nil "Prompt template ~A argument hint must be a string or NIL"
               name)))
    (unless (or (stringp template) (functionp template))
      (error
       'extension-registration-error
       :message
       (format nil "Prompt template ~A must be a string or function"
               name)))
    (ensure-unique-extension-definition
     (extension-bundle-templates bundle)
     name
     #'extension-template-definition-name
     "Prompt template")
    (setf
     (extension-bundle-templates bundle)
     (nconc
      (extension-bundle-templates bundle)
      (list
       (make-extension-template-definition
        :name name
        :description description
        :argument-hint argument-hint
        :template template
        :bundle bundle)))))
  name)

(defun validate-extension-provider
    (definition models)
  (unless (typep definition 'cadr-ai:provider-definition)
    (error
     'extension-registration-error
     :message
     "Provider definition must be a CADR-AI:PROVIDER-DEFINITION"))
  (unless
      (and
       (listp models)
       (every
        (lambda (model)
          (and
           (typep model 'cadr-ai:model-metadata)
           (eq
            (cadr-ai:model-metadata-provider model)
            (cadr-ai:provider-definition-id definition))))
        models))
    (error
     'extension-registration-error
     :message
     "Provider models must be a list of matching CADR-AI:MODEL-METADATA values"))
  definition)

(defun extension-provider-id (entry)
  (cadr-ai:provider-definition-id
   (extension-provider-definition-definition entry)))

(defun register-extension-provider
    (definition models)
  (let ((bundle (require-extension-registration-bundle)))
    (validate-extension-provider definition models)
    (let ((existing
            (find
             (cadr-ai:provider-definition-id definition)
             (extension-bundle-providers bundle)
             :key #'extension-provider-id)))
      (if existing
          (setf
           (extension-provider-definition-definition existing)
           definition
           (extension-provider-definition-models existing)
           (copy-list models))
          (setf
           (extension-bundle-providers bundle)
           (nconc
            (extension-bundle-providers bundle)
            (list
             (make-extension-provider-definition
              :definition definition
              :models (copy-list models)
              :bundle bundle)))))))
  definition)

(defun register-extension-native-provider (provider)
  (unless (typep provider 'cadr-ai:runtime-provider)
    (error
     'extension-registration-error
     :message
     "Native provider must be a CADR-AI:RUNTIME-PROVIDER"))
  (let* ((bundle (require-extension-registration-bundle))
         (id (cadr-ai:runtime-provider-id provider))
         (existing
           (find
            id
            (extension-bundle-native-providers bundle)
            :key
            (lambda (entry)
              (cadr-ai:runtime-provider-id
               (extension-native-provider-definition-provider
                entry))))))
    (unless (keywordp id)
      (error
       'extension-registration-error
       :message "Native provider ID must be a keyword"))
    (when existing
      (error
       'extension-registration-error
       :message
       (format nil
               "Native provider ~A is registered more than once in the same extension"
               id)))
    (setf
     (extension-bundle-native-providers bundle)
     (nconc
      (extension-bundle-native-providers bundle)
      (list
       (make-extension-native-provider-definition
        :provider provider
        :bundle bundle)))))
  provider)

(defun validate-extension-renderer-type
    (kind custom-type)
  (unless
      (and (stringp custom-type)
           (plusp (length custom-type)))
    (error
     'extension-registration-error
     :message
     (format nil "~A type must be a non-empty string"
             kind)))
  custom-type)

(defun register-extension-shortcut
    (key description handler)
  (let ((bundle (require-extension-registration-bundle)))
    (unless
        (and (stringp key)
             (plusp (length key)))
      (error
       'extension-registration-error
       :message
       "Shortcut key must be a non-empty string"))
    (unless (or (null description)
                (stringp description))
      (error
       'extension-registration-error
       :message
       "Shortcut description must be a string or NIL"))
    (unless (functionp handler)
      (error
       'extension-registration-error
       :message "Shortcut handler must be a function"))
    (let ((definition
            (make-extension-shortcut-definition
             :key (string-downcase key)
             :description description
             :handler handler
             :bundle bundle)))
      (setf
       (extension-bundle-shortcuts bundle)
       (nconc
        (remove
         key
         (extension-bundle-shortcuts bundle)
         :key #'extension-shortcut-definition-key
         :test #'string-equal)
        (list definition)))))
  key)

(defun valid-extension-flag-default-p
    (type default)
  (ecase type
    (:boolean
     (or (null default) (eq default t)))
    (:string
     (or (null default) (stringp default)))))

(defun register-extension-flag
    (name description type default)
  (let ((bundle (require-extension-registration-bundle)))
    (validate-extension-resource-name "flag" name)
    (unless (or (null description)
                (stringp description))
      (error
       'extension-registration-error
       :message
       (format nil "Flag ~A description must be a string or NIL"
               name)))
    (unless (member type '(:boolean :string))
      (error
       'extension-registration-error
       :message
       (format nil "Flag ~A type must be :BOOLEAN or :STRING"
               name)))
    (unless (valid-extension-flag-default-p type default)
      (error
       'extension-registration-error
       :message
       (format nil "Flag ~A default does not match type ~S"
               name type)))
    (let ((definition
            (make-extension-flag-definition
             :name name
             :description description
             :type type
             :default default
             :bundle bundle)))
      (setf
       (extension-bundle-flags bundle)
       (nconc
        (remove
         name
         (extension-bundle-flags bundle)
         :key #'extension-flag-definition-name
         :test #'string=)
        (list definition)))))
  name)

(defun register-extension-renderer
    (kind custom-type renderer &key component-p)
  (let ((bundle (require-extension-registration-bundle)))
    (validate-extension-renderer-type kind custom-type)
    (unless (functionp renderer)
      (error
       'extension-registration-error
       :message
       (format nil "~A renderer must be a function"
               kind)))
    (let* ((accessor
             (ecase kind
               (:message
                #'extension-bundle-message-renderers)
               (:entry
                #'extension-bundle-entry-renderers)))
           (definitions (funcall accessor bundle))
           (definition
             (make-extension-renderer-definition
              :custom-type custom-type
              :renderer renderer
              :component-p (not (null component-p))
              :bundle bundle))
           (updated
             (nconc
              (remove
               custom-type definitions
               :key
               #'extension-renderer-definition-custom-type
               :test #'string=)
              (list definition))))
      (ecase kind
        (:message
         (setf
          (extension-bundle-message-renderers bundle)
          updated))
        (:entry
         (setf
          (extension-bundle-entry-renderers bundle)
          updated)))))
  custom-type)

(defun register-extension-markdown-transformer
    (transformer)
  (let ((bundle (require-extension-registration-bundle)))
    (unless (functionp transformer)
      (error
       'extension-registration-error
       :message
       "Markdown transformer must be a function"))
    (setf
     (extension-bundle-markdown-transformer bundle)
     (make-extension-markdown-transformer-definition
      :transformer transformer
      :bundle bundle)))
  transformer)

(defun register-extension-tool-renderer
    (tool-name call result)
  (let ((bundle (require-extension-registration-bundle)))
    (validate-extension-resource-name
     "tool renderer" tool-name)
    (unless
        (and
         (or (null call) (functionp call))
         (or (null result) (functionp result))
         (or call result))
      (error
       'extension-registration-error
       :message
       "Tool renderer requires at least one function-valued :CALL or :RESULT"))
    (let ((existing
            (find
             tool-name
             (extension-bundle-tool-renderers bundle)
             :key
             #'extension-tool-renderer-definition-tool-name
             :test #'string=)))
      (if existing
          (setf
           (extension-tool-renderer-definition-call
            existing)
           (or call
               (extension-tool-renderer-definition-call
                existing))
           (extension-tool-renderer-definition-result
            existing)
           (or result
               (extension-tool-renderer-definition-result
                existing)))
          (setf
           (extension-bundle-tool-renderers bundle)
           (nconc
            (extension-bundle-tool-renderers bundle)
            (list
             (make-extension-tool-renderer-definition
              :tool-name tool-name
              :call call
              :result result
              :bundle bundle)))))))
  tool-name)

(defmacro define-tool
    (name &key description parameters
                 (execution-mode :parallel)
                 handler)
  `(register-extension-tool
    ,name ,description ,parameters ,execution-mode ,handler))

(defmacro define-rich-tool
    (name &key label description prompt-snippet prompt-guidelines
               parameters constrained-sampling render-shell
               prepare-arguments (execution-mode :parallel)
               handler render-call render-result)
  `(register-rich-extension-tool
    ,name :label ,label :description ,description
    :prompt-snippet ,prompt-snippet
    :prompt-guidelines ,prompt-guidelines
    :parameters ,parameters
    :constrained-sampling ,constrained-sampling
    :render-shell ,render-shell
    :prepare-arguments ,prepare-arguments
    :execution-mode ,execution-mode
    :handler ,handler :render-call ,render-call :render-result ,render-result))

(defmacro define-command
    (name &key description argument-hint handler)
  `(register-extension-command
    ,name ,description ,argument-hint ,handler))

(defmacro define-event-hook
    (event &key (priority 0) handler)
  `(register-extension-hook ,event ,priority ,handler))

(defmacro define-prompt-template
    (name &key description argument-hint template)
  `(register-extension-template
    ,name ,description ,argument-hint ,template))

(defmacro define-provider (definition &key models)
  `(register-extension-provider ,definition ,models))

(defmacro define-native-provider (provider)
  `(register-extension-native-provider ,provider))

(defmacro define-shortcut
    (key &key description handler)
  `(register-extension-shortcut
    ,key ,description ,handler))

(defmacro define-flag
    (name &key description type default)
  `(register-extension-flag
    ,name ,description ,type ,default))

(defmacro define-message-renderer
    (custom-type &key renderer)
  `(register-extension-renderer
    :message ,custom-type ,renderer))

(defmacro define-component-message-renderer
    (custom-type &key renderer)
  `(register-extension-renderer
    :message ,custom-type ,renderer :component-p t))

(defmacro define-markdown-transformer (transformer)
  `(register-extension-markdown-transformer
    ,transformer))

(defmacro define-entry-renderer
    (custom-type &key renderer)
  `(register-extension-renderer
    :entry ,custom-type ,renderer))

(defmacro define-component-entry-renderer
    (custom-type &key renderer)
  `(register-extension-renderer
    :entry ,custom-type ,renderer :component-p t))

(defmacro define-tool-renderer
    (tool-name &key call result)
  `(register-extension-tool-renderer
    ,tool-name ,call ,result))
