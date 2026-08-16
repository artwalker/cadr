(in-package #:cadr-ai)

(defparameter +cadr-version+
  (asdf:component-version
   (asdf:find-system "cadr-ai")))

(defparameter +cadr-product-slug+ "cadr")
(defparameter +cadr-product-display-name+ "Cadr")
(defparameter +cadr-canonical-repository-url+
  "https://github.com/artwalker/cadr")
(defparameter +cadr-default-share-viewer-url+
  "https://cadr.dev/session/")

(defun cadr-product-slug ()
  +cadr-product-slug+)

(defun cadr-product-display-name ()
  +cadr-product-display-name+)

(defun cadr-canonical-repository-url ()
  +cadr-canonical-repository-url+)

(defun cadr-default-share-viewer-url ()
  +cadr-default-share-viewer-url+)

(defun cadr-changelog-url ()
  (format nil "~A/blob/main/CHANGELOG.md"
          (cadr-canonical-repository-url)))

(defun cadr-version ()
  +cadr-version+)

(defun cadr-user-agent ()
  ;; Baseline packages/ai/src/utils/pi-user-agent.ts getPiUserAgent, with
  ;; cadr identity.  The baseline guards node:os behind a browser check;
  ;; cadr is always native, so the OS triple is always available.
  (format nil "~A (~A ~A; ~A)"
          (cadr-product-slug)
          (software-type) (software-version) (machine-type)))

(defun read-baseline-anchor ()
  "Goal 18 L2.1: the single owner of the fixed pi baseline is the
BASELINE file at the repository root ('<full-commit> <vX.Y.Z> <distance>');
the release identity derives from it at load time, so a baseline upgrade
never hand-edits version strings.  Returns (values release distance
short-commit)."
  (let* ((root
           (uiop:ensure-directory-pathname
            (asdf:system-source-directory "cadr-ai")))
         (fields
           (uiop:split-string
            (string-trim
             '(#\Space #\Tab #\Newline #\Return)
             (uiop:read-file-string
              (merge-pathnames "BASELINE" root))))))
    (unless (= 3 (length fields))
      (error "BASELINE must be '<full-commit> <vX.Y.Z> <distance>'"))
    (values
     (second fields)
     (parse-integer (third fields))
     (subseq (first fields) 0 9))))

(defun cadr-release-identity ()
  (multiple-value-bind (release distance short-commit)
      (read-baseline-anchor)
    (format
     nil
     "~A ~A · aligned with pi ~A (+~D, ~A)"
     (cadr-product-slug)
     (cadr-version)
     release
     distance
     short-commit)))

(defun cadr-docs-directory ()
  ;; The product docs live in docs/ beside the ASDF source root; the
  ;; deliverable binary keeps the same relative layout.
  (merge-pathnames "docs/"
                   (asdf:system-source-directory "cadr-cli")))

(defun provider-login-help-text ()
  ;; Baseline core/auth-guidance.ts getProviderLoginHelp.
  (format nil
          "Use /login to log into a provider via OAuth or API key. See:~%  ~A~%  ~A"
          (namestring
           (merge-pathnames "providers.md" (cadr-docs-directory)))
          (namestring
           (merge-pathnames "models.md" (cadr-docs-directory)))))

(defun no-api-key-found-message (provider)
  ;; Baseline core/auth-guidance.ts formatNoApiKeyFoundMessage.
  (format nil "No API key found for ~A.~%~%~A"
          (if (string= provider "unknown") "the selected model" provider)
          (provider-login-help-text)))

(defun no-models-available-message ()
  ;; Baseline core/auth-guidance.ts formatNoModelsAvailableMessage.
  (format nil "No models available. ~A" (provider-login-help-text)))

(defun no-model-selected-message ()
  ;; Baseline core/auth-guidance.ts formatNoModelSelectedMessage.
  (format nil
          "No model selected.~%~%~A~%~%Then use /model to select a model."
          (provider-login-help-text)))
