(load (merge-pathnames "../support.lisp"
                       (uiop:pathname-directory-pathname *load-truename*)))

(defparameter *dynamic-resource-directory*
  (uiop:pathname-directory-pathname *load-truename*))

(cadr-agent:define-event-hook
 :resources-discover
 :handler
 (lambda (event context)
   (declare (ignore event context))
   (list
    :skill-paths
    (list (namestring (merge-pathnames "SKILL.md" *dynamic-resource-directory*)))
    :prompt-paths
    (list (namestring (merge-pathnames "dynamic.md" *dynamic-resource-directory*)))
    :theme-paths
    (list (namestring (merge-pathnames "dynamic.json" *dynamic-resource-directory*))))))
