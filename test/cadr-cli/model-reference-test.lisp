(in-package #:cadr-cli/tests)
(in-suite cadr-cli-suite)

(defun reference-catalog-model (provider id)
  (cadr-ai:make-model
   :id id
   :name id
   :provider (intern (string-upcase provider) :keyword)
   :api :openai-completions))

(defun reference-catalog ()
  (mapcar
   (lambda (pair)
     (reference-catalog-model (first pair) (second pair)))
   '(("anthropic" "claude-sonnet-4-5")
     ("anthropic" "claude-sonnet-4-5-20250929")
     ("anthropic" "claude-opus-4-8")
     ("anthropic" "exact")
     ("anthropic" "shared-pro")
     ("openai" "gpt-4o")
     ("openrouter" "qwen/qwen3-coder:exacto")
     ("openrouter" "openai/gpt-4o:extended")
     ("gw-a" "shared")
     ("gw-a" "anthropic/future")
     ("gw-a" "anthropic/exact")
     ("gw-a" "anthropic/claude-opus-4.8")
     ("gw-a" "anthropic/claude-opus")
     ("gw-b" "shared")
     ("gw-b" "anthropic/future")
     ("gw-b" "claude-opus-4-8")
     ("gw-b" "gw-b/free")
     ("gw-b" "zz:free"))))

(defun reference-usable (names)
  (lambda (provider)
    (member provider names :test #'string-equal)))

(test model-reference-prefers-usable-providers-over-catalog-order
  ;; pi@4a080252f model-resolver.ts resolveModelReference (#10160).
  (let ((cases
          '((:name "exact id" :text "claude-sonnet-4-5"
             :model "anthropic/claude-sonnet-4-5")
            (:name "case" :text "GPT-4O" :model "openai/gpt-4o")
            (:name "alias" :text "sonnet"
             :model "anthropic/claude-sonnet-4-5")
            (:name "thinking" :text "sonnet:high"
             :model "anthropic/claude-sonnet-4-5" :thinking :high)
            (:name "colon id" :text "qwen/qwen3-coder:exacto"
             :model "openrouter/qwen/qwen3-coder:exacto")
            (:name "prefix thinking"
             :text "openrouter/qwen/qwen3-coder:exacto:high"
             :model "openrouter/qwen/qwen3-coder:exacto"
             :thinking :high)
            (:name "raw colon id" :text "openai/gpt-4o:extended"
             :model "openrouter/openai/gpt-4o:extended")
            (:name "prefix fuzzy" :text "openrouter/qwen"
             :model "openrouter/qwen/qwen3-coder:exacto")
            (:name "strict suffix" :text "gpt-4o:random" :status :not-found)
            (:name "lenient suffix" :text "gpt-4o:random"
             :suffix :lenient :model "openai/gpt-4o"
             :warning "Invalid thinking level \"random\"")
            (:name "lenient discards inner thinking"
             :text "qwen/qwen3-coder:exacto:high:random"
             :suffix :lenient
             :model "openrouter/qwen/qwen3-coder:exacto"
             :warning "Invalid thinking level \"random\"")
            (:name "none" :text "gpt-4o:high" :suffix :none
             :status :not-found)
            (:name "no fuzzy" :text "sonnet" :fuzzy nil
             :status :not-found)
            (:name "blank" :text "  " :status :not-found)
            (:name "sole usable" :text "shared" :usable ("gw-b")
             :model "gw-b/shared")
            (:name "none usable" :text "shared"
             :ambiguous ("gw-a/shared" "gw-b/shared") :usable-count 0)
            (:name "several usable" :text "shared"
             :usable ("gw-a" "gw-b")
             :ambiguous ("gw-a/shared" "gw-b/shared") :usable-count 2)
            (:name "thinking keeps provider" :text "shared:high"
             :usable ("gw-b") :model "gw-b/shared" :thinking :high)
            (:name "thinking stays ambiguous" :text "shared:high"
             :usable ("gw-a" "gw-b")
             :ambiguous ("gw-a/shared" "gw-b/shared")
             :usable-count 2 :thinking :high)
            (:name "prefix falls to usable raw" :text "anthropic/future"
             :usable ("gw-b") :model "gw-b/anthropic/future")
            (:name "usable named wins" :text "anthropic/exact"
             :usable ("anthropic" "gw-a") :model "anthropic/exact")
            (:name "usable raw beats named" :text "anthropic/exact"
             :usable ("gw-a") :model "gw-a/anthropic/exact")
            (:name "unusable named kept" :text "anthropic/exact"
             :model "anthropic/exact")
            (:name "named fuzzy" :text "anthropic/claude-opus"
             :usable ("anthropic") :model "anthropic/claude-opus-4-8")
            (:name "raw beats unusable fuzzy"
             :text "anthropic/claude-opus" :usable ("gw-a")
             :model "gw-a/anthropic/claude-opus")
            (:name "unusable fuzzy kept" :text "anthropic/claude-opus"
             :model "anthropic/claude-opus-4-8")
            (:name "literal beats fuzzy" :text "gw-b/free"
             :model "gw-b/gw-b/free")
            (:name "fuzzy usable" :text "opus" :usable ("gw-a")
             :model "gw-a/anthropic/claude-opus-4.8")
            (:name "fuzzy tie" :text "opus"
             :usable ("anthropic" "gw-a" "gw-b")
             :ambiguous ("anthropic/claude-opus-4-8"
                         "gw-b/claude-opus-4-8")
             :usable-count 2)
            (:name "fuzzy sole usable" :text "opus" :usable ("anthropic")
             :model "anthropic/claude-opus-4-8")
            (:name "provider constraint" :text "shared"
             :provider "gw-a" :usable ("gw-b")
             :model "gw-a/shared")
            (:name "provider prefix" :text "GW-B/shared" :provider "gw-b"
             :model "gw-b/shared")
            (:name "provider fuzzy" :text "4o" :provider "openai"
             :model "openai/gpt-4o")
            (:name "provider stays" :text "gpt-4o" :provider "gw-a"
             :status :not-found))))
    (dolist (catalog (list (reference-catalog)
                           (reverse (reference-catalog))))
      (dolist (case cases)
        (let ((result
                (cadr-cli::resolve-model-reference
                 (getf case :text)
                 catalog
                 :provider (getf case :provider)
                 :thinking-suffix (or (getf case :suffix) :strict)
                 :fuzzy (if (getf case :fuzzy)
                            (getf case :fuzzy)
                            (not (member :fuzzy case)))
                 :usable (reference-usable (getf case :usable)))))
          (cond
            ((getf case :ambiguous)
             (is (eq :ambiguous (getf result :status)))
             (is (equal
                  (getf case :ambiguous)
                  (sort
                   (mapcar #'cadr-cli::canonical-model-id
                           (getf result :candidates))
                   #'string<)))
             (is (= (getf case :usable-count)
                    (getf result :usable-count)))
             (is (eq (getf case :thinking) (getf result :thinking))))
            ((eq (getf case :status) :not-found)
             (is (eq :not-found (getf result :status))))
            (t
             (is (eq :resolved (getf result :status)))
             (is (string=
                  (getf case :model)
                  (cadr-cli::canonical-model-id
                   (getf result :model))))
             (is (eq (getf case :thinking) (getf result :thinking)))
             (if (getf case :warning)
                 (is (search (getf case :warning)
                             (getf result :warning)))
                 (is (null (getf result :warning)))))))))))

(test model-scope-keeps-every-provider-for-an-ambiguous-id
  (let ((registry
          (cadr-cli::%make-model-registry
           :models (reference-catalog))))
    (multiple-value-bind (scoped diagnostics)
        (cadr-cli::resolve-scoped-models-with-diagnostics
         registry '("shared" "sonnet:high" "missing"))
      (is (equal
           '("gw-a/shared" "gw-b/shared")
           (sort
            (mapcar
             (lambda (entry)
               (cadr-cli::canonical-model-id
                (getf entry :model)))
             (remove-if-not
              (lambda (entry)
                (string= "shared"
                         (cadr-ai:model-id
                          (getf entry :model))))
              scoped))
            #'string<)))
      (let ((sonnet
              (find "claude-sonnet-4-5" scoped
                    :key (lambda (entry)
                           (cadr-ai:model-id (getf entry :model)))
                    :test #'string=)))
        (is (eq :high (getf sonnet :thinking))))
      (is (find :ambiguous diagnostics
                :key (lambda (diagnostic) (getf diagnostic :code))))
      (is (find :no-match diagnostics
                :key (lambda (diagnostic) (getf diagnostic :code)))))))

(test cli-model-reports-ambiguity-and-falls-back-to-a-custom-id
  (let ((registry
          (cadr-cli::%make-model-registry
           :models (reference-catalog))))
    (multiple-value-bind (model error thinking warning)
        (cadr-cli::resolve-cli-model registry "shared")
      (is (null model))
      (is (search "ambiguous across providers" error))
      (is (search "gw-a/shared" error))
      (is (search "gw-b/shared" error))
      (is (search "No matching provider is authenticated." error))
      (is (null thinking))
      (is (null warning)))
    (multiple-value-bind (model error thinking warning)
        (cadr-cli::resolve-cli-model
         registry "shared" :inline-api-key-p t)
      (is (null model))
      (is (search "--api-key does not choose a provider." error))
      (is (null thinking))
      (is (null warning)))
    (multiple-value-bind (model error thinking warning)
        (cadr-cli::resolve-cli-model
         registry "not-a-model" :provider "openai")
      (is (null error))
      (is (string= "not-a-model" (cadr-ai:model-id model)))
      (is (eq :openai (cadr-ai:model-provider model)))
      (is (null thinking))
      (is (search "Using custom model id." warning)))
    (multiple-value-bind (model error thinking warning)
        (cadr-cli::resolve-cli-model
         registry "gpt-4o" :provider "nope")
      (declare (ignore model thinking warning))
      (is (search "Unknown provider \"nope\"" error)))))
