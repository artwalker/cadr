(in-package #:cadr-agent/tests)
(in-suite cadr-agent-suite)

(test harness-resources-load-format-and-preserve-source
  (with-session-directories (sessions cwd other-cwd)
    (values sessions other-cwd)
    (let ((prompts (merge-pathnames "prompts/" cwd))
          (skills (merge-pathnames "skills/" cwd)))
      (ensure-directories-exist
       (merge-pathnames "nested/anchor" prompts))
      (ensure-directories-exist
       (merge-pathnames "example/anchor" skills))
      (with-open-file
          (stream (merge-pathnames "review.md" prompts)
                  :direction :output
                  :if-exists :supersede
                  :if-does-not-exist :create
                  :external-format :utf-8)
        (format
         stream
         "---~%description: Review files~%---~%Review $1 with ${@:2} and $ARGUMENTS"))
      (with-open-file
          (stream
            (merge-pathnames "nested/ignored.md" prompts)
                  :direction :output
                  :if-exists :supersede
                  :if-does-not-exist :create
                  :external-format :utf-8)
        (write-string "ignored" stream))
      (with-open-file
          (stream
            (merge-pathnames "example/SKILL.md" skills)
                  :direction :output
                  :if-exists :supersede
                  :if-does-not-exist :create
                  :external-format :utf-8)
        (format
         stream
         "---~%name: example~%description: Example skill~%disable-model-invocation: false~%---~%Use this skill."))
      (multiple-value-bind (templates diagnostics)
          (cadr-agent::load-prompt-templates
           (list prompts))
        (is (null diagnostics))
        (is (= 1 (length templates)))
        (let ((template (first templates)))
          (is (string=
               "review"
               (cadr-agent::prompt-template-name
                template)))
          (is
           (string=
            "Review a.ts with care now and a.ts care now"
            (cadr-agent::format-prompt-template-invocation
             template
             '("a.ts" "care" "now"))))))
      (multiple-value-bind (loaded diagnostics)
          (cadr-agent::load-sourced-skills
           (list
            (list :path skills
                  :source '(:type :project))))
        (is (null diagnostics))
        (is (= 1 (length loaded)))
        (let* ((item (first loaded))
               (skill (getf item :skill)))
          (is (equal '(:type :project)
                     (getf item :source)))
          (is (string=
               "example"
               (cadr-agent::skill-name skill)))
          (is
           (string=
            (format
             nil
             "<skill name=\"example\" location=\"~A\">~%References are relative to ~A.~%~%Use this skill.~%</skill>~%~%Check errors."
             (cadr-agent::skill-file-path skill)
             (string-right-trim
              "/"
              (namestring
               (uiop:pathname-directory-pathname
                (pathname
                 (cadr-agent::skill-file-path
                  skill))))))
            (cadr-agent::format-skill-invocation
             skill "Check errors.")))))
      (multiple-value-bind (loaded diagnostics)
          (cadr-agent::load-sourced-skills
           (list
            (list
             :path
             (merge-pathnames "missing/" cwd)
             :source '(:type :user))))
        (is (null loaded))
        (is (null diagnostics))))))

(test harness-skill-system-prompt-is-ordered-filtered-and-escaped
  (let* ((visible
           (cadr-agent::make-skill
            :name "a&b"
            :description "Use <this> & \"that\""
            :content "visible"
            :file-path "/skills/<a>/SKILL.md"))
         (hidden
           (cadr-agent::make-skill
            :name "hidden"
            :description "Hidden"
            :content "hidden"
            :file-path "/skills/hidden/SKILL.md"
            :disable-model-invocation-p t))
         (formatted
           (cadr-agent::format-skills-for-system-prompt
            (list visible hidden))))
    (is (search "<name>a&amp;b</name>" formatted))
    (is
     (search
      "<description>Use &lt;this&gt; &amp; &quot;that&quot;</description>"
      formatted))
    (is
     (search
      "<location>/skills/&lt;a&gt;/SKILL.md</location>"
      formatted))
    (is (not (search "hidden" formatted)))
    (is
     (string=
      ""
      (cadr-agent::format-skills-for-system-prompt
       (list hidden))))))

(test harness-resource-diagnostics-reject-invalid-metadata
  (with-session-directories (sessions cwd other-cwd)
    (values sessions other-cwd)
    (let ((skill-dir
            (merge-pathnames "skills/Broken_Name/" cwd)))
      (ensure-directories-exist
       (merge-pathnames "anchor" skill-dir))
      (with-open-file
          (stream (merge-pathnames "SKILL.md" skill-dir)
                  :direction :output
                  :if-exists :supersede
                  :if-does-not-exist :create
                  :external-format :utf-8)
        (format stream "---~%name: wrong~%---~%Body"))
      (multiple-value-bind (skills diagnostics)
          (cadr-agent::load-skills
           (merge-pathnames "skills/" cwd))
        (is (null skills))
        (is
         (member
         :invalid-metadata diagnostics
          :key #'cadr-agent::resource-diagnostic-code))))))

(test frontmatter-and-prompt-expansion-match-reference-edge-cases
  (multiple-value-bind (metadata body error)
      (cadr-agent::parse-resource-frontmatter
       (format nil
               "---~C~Cname: \"review\"~C~Cdescription: |~C~C  Line one~C~C  Line two~C~C---~C~C~C~CBody"
               #\Return #\Newline
               #\Return #\Newline
               #\Return #\Newline
               #\Return #\Newline
               #\Return #\Newline
               #\Return #\Newline
               #\Return #\Newline))
    (is (null error))
    (is (string= "review" (getf metadata :name)))
    (is (string=
         (format nil "Line one~%Line two~%")
         (getf metadata :description)))
    (is (string= "Body" body)))
  (multiple-value-bind (metadata body error)
      (cadr-agent::parse-resource-frontmatter
       (format nil "---~%foo: [bar~%---~%Body"))
    (declare (ignore metadata body))
    (is (search "line 1" error)))
  (is
   (string=
    "3 brief 3  a $1 $ARGUMENTS b c a  a"
    (cadr-agent::substitute-prompt-arguments
     "${1:-7} ${2:-brief} $ARGUMENTS ${3:-$ARGUMENTS} ${@:2:2}"
     '("3" "" "a" "$1" "$ARGUMENTS" "b" "c"))))
  (is
   (string=
    "$1 $ARGUMENTS"
    (cadr-agent::substitute-prompt-arguments
     "$ARGUMENTS"
     '("$1" "$ARGUMENTS"))))
  (is
   (string=
    "b c d"
    (cadr-agent::substitute-prompt-arguments
     "${@:2}" '("a" "b" "c" "d"))))
  (is
   (string=
    "a b  "
    (cadr-agent::substitute-prompt-arguments
     "$1 $2 $3 $4" '("a" "b")))))

(test skills-prompt-header-matches-baseline-core-formatter
  ;; Baseline packages/coding-agent/src/core/skills.ts:343-346, the
  ;; formatter that buildSystemPrompt actually imports — goal 20 found
  ;; cadr had transcribed the unused harness variant (no leading blank
  ;; line, and "Read the full skill file" instead of naming the read
  ;; tool).
  (let* ((skill
           (cadr-agent::make-skill
            :name "demo"
            :description "Demo skill"
            :content "x"
            :file-path "/skills/demo/SKILL.md"))
         (formatted
           (cadr-agent::format-skills-for-system-prompt (list skill)))
         (expected
           (format
            nil
            "~%~%The following skills provide specialized instructions for specific tasks.~%Use the read tool to load a skill's file when the task matches its description.~%When a skill file references a relative path, resolve it against the skill directory (parent of SKILL.md / dirname of the path) and use that absolute path in tool commands.~%~%<available_skills>~%  <skill>~%    <name>demo</name>~%    <description>Demo skill</description>~%    <location>/skills/demo/SKILL.md</location>~%  </skill>~%</available_skills>")))
    (is (string= expected formatted))))
