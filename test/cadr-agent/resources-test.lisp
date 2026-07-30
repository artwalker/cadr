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
