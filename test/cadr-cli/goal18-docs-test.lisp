(in-package #:cadr-cli/tests)

(in-suite cadr-cli-suite)

;;; Goal 18 Part J: product text that points at repository documentation
;;; must never reference a file that does not exist.  The system prompt
;;; tells the model to read docs/extensions.md etc.; a missing target
;;; turns that promise into a hallucination instruction.

(defun goal18-doc-references (text)
  "All docs/... and examples/... references in TEXT, in order."
  (let ((references nil))
    (dolist (match
             (cl-ppcre:all-matches-as-strings
              "(?:docs|examples)/[A-Za-z0-9._/-]+" text))
      (pushnew (string-right-trim ").,;" match)
               references
               :test #'string=))
    (nreverse references)))

(defun goal18-assert-references-exist (root text source-label)
  (dolist (reference (goal18-doc-references text))
    (is (not (null (probe-file (merge-pathnames reference root))))
        "~A references missing repository path: ~A" source-label reference)))

(test goal18-product-doc-references-resolve
  (let ((root (asdf:system-source-directory "cadr-cli")))
    ;; The system prompt's documentation block.
    (goal18-assert-references-exist
     root
     (cadr-cli:build-system-prompt :cwd "/tmp")
     "system prompt")
    ;; The no-auth / no-models guidance paths.
    (goal18-assert-references-exist
     root
     (cadr-ai::provider-login-help-text)
     "provider login guidance")
    ;; README's own pointers.
    (goal18-assert-references-exist
     root
     (uiop:read-file-string
      (merge-pathnames "README.md" root)
      :external-format :utf-8)
     "README")))

(test goal18-eleven-promised-docs-exist
  ;; pi@4a080252f system-prompt.ts names these documents in the docs
  ;; section. Product name in the surrounding sentence is cadr.
  (let ((root (asdf:system-source-directory "cadr-cli")))
    (dolist (name '("extensions" "themes" "skills" "prompt-templates"
                    "tui" "keybindings" "sdk" "custom-provider" "models"
                    "packages" "environment-variables" "mcp" "codemode"))
      (is (not (null
                (probe-file
                 (merge-pathnames
                  (format nil "docs/~A.md" name) root))))
          "docs/~A.md missing" name))))

(test system-prompt-docs-tail-matches-v140
  ;; pi@4a080252f packages/coding-agent/src/core/system-prompt.ts
  ;; the "When asked about" line. "pi packages" is "cadr packages",
  ;; the same product-name substitution as the rest of that sentence.
  (let ((asked
          "- When asked about: extensions (docs/extensions.md, examples/extensions/), themes (docs/themes.md), skills (docs/skills.md), prompt templates (docs/prompt-templates.md), TUI components (docs/tui.md), keybindings (docs/keybindings.md), SDK integrations (docs/sdk.md), custom providers (docs/custom-provider.md), adding models (docs/models.md), cadr packages (docs/packages.md), environment variables (docs/environment-variables.md), MCP servers (docs/mcp.md), codemode scripts and non-LLM models such as classifiers and image models (docs/codemode.md)"))
    (is (search asked
                (cadr-cli:build-system-prompt :cwd "/tmp")))
    (is (search asked
                (cdr (assoc "docs"
                            (cadr-cli:build-system-prompt-sections
                             :cwd "/tmp")
                            :test #'string=))))
    (is (not (search "docs/codemode.md"
                     (cadr-cli:build-system-prompt
                      :custom-prompt "You are A."
                      :cwd "/tmp"))))
    (is (null (assoc "docs"
                     (cadr-cli:build-system-prompt-sections
                      :custom-prompt "You are A."
                      :cwd "/tmp")
                     :test #'string=)))))

(test goal18-release-identity-derives-from-the-baseline-anchor
  ;; Goal 18 L2.1: the BASELINE file is the single owner of the fixed
  ;; baseline anchor; the product release identity must equal the
  ;; identity recomputed from that file (the verify.sh consistency gate
  ;; covers the scripts/fixtures/README side).
  (let* ((root (asdf:system-source-directory "cadr-cli"))
         (fields
           (uiop:split-string
            (string-trim
             '(#\Space #\Tab #\Newline #\Return)
             (uiop:read-file-string
              (merge-pathnames "BASELINE" root)
              :external-format :utf-8)))))
    (is (= 3 (length fields)))
    (is
     (string=
      (format nil "cadr 0.2.0 · aligned with pi ~A (+~A, ~A)"
              (second fields)
              (third fields)
              (subseq (first fields) 0 9))
      (cadr-ai::cadr-release-identity)))))
