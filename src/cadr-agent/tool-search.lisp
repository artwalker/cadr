(in-package #:cadr-agent)

(defparameter +tool-search-stop-words+
  '("a" "an" "and" "are" "as" "at" "be" "by" "for" "from"
    "in" "is" "it" "of" "on" "or" "that" "the" "this" "to" "with"))

(defparameter +tool-search-description+
  "# Tool discovery

Searches over deferred tool metadata with BM25 and exposes matching tools for the next model call.

Some of the tools, such as tools of MCP servers, may not have been provided to you upfront, and you should use this tool (`tool_search`) to search for the required tools. For MCP tool discovery, always use `tool_search`.")

(defstruct tool-search-match
  name
  (score 0d0 :type double-float))

(defun tool-search-ascii-lower-p (char)
  (char<= #\a char #\z))

(defun tool-search-ascii-upper-p (char)
  (char<= #\A char #\Z))

(defun tool-search-ascii-alnum-p (char)
  (or (tool-search-ascii-lower-p char)
      (digit-char-p char)))

(defun tool-search-insert-camel-spaces (text)
  (with-output-to-string (out)
    (loop for index from 0 below (length text)
          for char = (char text index)
          do (when (and (> index 0)
                        (tool-search-ascii-alnum-p
                         (char text (1- index)))
                        (tool-search-ascii-upper-p char))
               (write-char #\Space out))
             (write-char char out))))

(defun tool-search-split-acronyms (text)
  (with-output-to-string (out)
    (let ((index 0)
          (length (length text)))
      (loop while (< index length)
            do (let ((start index))
                 (loop while (and (< index length)
                                  (tool-search-ascii-upper-p
                                   (char text index)))
                       do (incf index))
                 (let ((upper-end index))
                   (if (and (> (- upper-end start) 1)
                            (< index length)
                            (tool-search-ascii-lower-p
                             (char text index)))
                       (progn
                         (write-string text out
                                       :start start
                                       :end (1- upper-end))
                         (write-char #\Space out)
                         (write-string text out
                                       :start (1- upper-end)
                                       :end upper-end))
                       (write-string text out
                                     :start start
                                     :end upper-end))))
            (loop while (and (< index length)
                             (not (tool-search-ascii-upper-p
                                   (char text index))))
                  do (write-char (char text index) out)
                     (incf index))))))

(defun tool-search-stem (term)
  (cond
    ((and (> (length term) 4)
          (uiop:string-suffix-p term "ies"))
     (concatenate 'string (subseq term 0 (- (length term) 3)) "y"))
    ((and (> (length term) 4)
          (some (lambda (suffix)
                  (uiop:string-suffix-p term suffix))
                '("ches" "shes" "sses" "xes" "zes")))
     (subseq term 0 (- (length term) 2)))
    ((and (> (length term) 3)
          (uiop:string-suffix-p term "s")
          (not (uiop:string-suffix-p term "ss")))
     (subseq term 0 (1- (length term))))
    (t term)))

(defun tool-search-tokenize (text)
  (let ((lower
          (string-downcase
           (tool-search-split-acronyms
            (tool-search-insert-camel-spaces text))))
        (terms nil)
        (start nil))
    (loop for index from 0 to (length lower)
          do (let ((alnum-p
                     (and (< index (length lower))
                          (or (tool-search-ascii-lower-p
                               (char lower index))
                              (digit-char-p (char lower index))))))
               (cond
                 ((and alnum-p (null start))
                  (setf start index))
                 ((and (not alnum-p) start)
                  (push (subseq lower start index) terms)
                  (setf start nil)))))
    (loop for term in (nreverse terms)
          unless (or (zerop (length term))
                     (member term +tool-search-stop-words+
                             :test #'string=))
            collect (tool-search-stem term))))

(defun tool-search-field (record key)
  (cond
    ((hash-table-p record) (gethash key record))
    ((cadr-ai::json-object-pairs-p record)
     (cadr-ai::json-get record key))
    ((consp record)
     (getf record key))
    (t nil)))

(defun tool-search-schema-text (schema parts)
  (unless (or (hash-table-p schema)
              (cadr-ai::json-object-pairs-p schema)
              (and (consp schema) (not (cadr-ai::json-object-pairs-p schema))
                   (keywordp (car schema))))
    (return-from tool-search-schema-text parts))
  (let ((description (tool-search-field schema "description")))
    (when (and (null description) (consp schema) (not (hash-table-p schema))
               (not (cadr-ai::json-object-pairs-p schema)))
      (setf description (getf schema :description)))
    (when (stringp description)
      (push description parts)))
  (let ((properties (or (tool-search-field schema "properties")
                        (and (consp schema)
                             (not (hash-table-p schema))
                             (not (cadr-ai::json-object-pairs-p schema))
                             (getf schema :properties)))))
    (cond
      ((hash-table-p properties)
       (maphash
        (lambda (name property)
          (push name parts)
          (setf parts (tool-search-schema-text property parts)))
        properties))
      ((cadr-ai::json-object-pairs-p properties)
       (loop for (name property) on (cdr properties) by #'cddr
             do (push name parts)
                (setf parts (tool-search-schema-text property parts))))))
  (setf parts
        (tool-search-schema-text
         (or (tool-search-field schema "items")
             (and (consp schema)
                  (not (hash-table-p schema))
                  (not (cadr-ai::json-object-pairs-p schema))
                  (getf schema :items)))
         parts))
  (dolist (key '("anyOf" "oneOf" "allOf"))
    (let ((variants (tool-search-field schema key)))
      (when (and (typep variants 'sequence)
                 (not (stringp variants)))
        (map nil
             (lambda (variant)
               (setf parts (tool-search-schema-text variant parts)))
             variants))))
  parts)

(defun tool-search-document (tool &optional namespace)
  (let* ((name (or (tool-search-field tool :name)
                   (tool-search-field tool "name")
                   ""))
         (description
           (or (tool-search-field tool :description)
               (tool-search-field tool "description")
               ""))
         (parameters
           (or (tool-search-field tool :parameters)
               (tool-search-field tool "parameters")))
         (parts
           (list name
                 (substitute #\Space #\_ name)
                 description)))
    (setf parts
          (append parts
                  (nreverse (tool-search-schema-text parameters nil))))
    (when namespace
      (dolist (key '(:name :description :instructions))
        (let ((value (or (tool-search-field namespace key)
                         (tool-search-field namespace
                                            (string-downcase
                                             (symbol-name key))))))
          (when (stringp value)
            (setf parts (append parts (list value)))))))
    (list :name name
          :text
          (format nil "~{~A~^ ~}"
                  (remove-if
                   (lambda (part)
                     (or (not (stringp part))
                         (zerop (length (string-trim
                                         '(#\Space #\Tab #\Newline #\Return)
                                         part)))))
                   parts)))))

(defun tool-search-unique (terms)
  (let ((seen (make-hash-table :test #'equal))
        (unique nil))
    (dolist (term terms)
      (unless (gethash term seen)
        (setf (gethash term seen) t)
        (push term unique)))
    (nreverse unique)))

(defun tool-search-rank (query documents limit &key (k1 1.2d0) (b 0.75d0))
  (let ((query-terms (tool-search-unique (tool-search-tokenize query))))
    (when (or (null query-terms)
              (null documents)
              (not (plusp limit)))
      (return-from tool-search-rank nil))
    (let* ((term-counts
             (mapcar
              (lambda (document)
                (let ((counts (make-hash-table :test #'equal)))
                  (dolist (term (tool-search-tokenize
                                 (or (getf document :text) "")))
                    (incf (gethash term counts 0)))
                  counts))
              documents))
           (lengths
             (mapcar
              (lambda (counts)
                (let ((sum 0))
                  (maphash (lambda (key count)
                             (declare (ignore key))
                             (incf sum count))
                           counts)
                  sum))
              term-counts))
           (average
             (let ((mean (/ (reduce #'+ lengths) (length documents))))
               (if (plusp mean) mean 1)))
           (idf (make-hash-table :test #'equal))
           (matches nil))
      (dolist (term query-terms)
        (let ((frequency
                (count-if (lambda (counts) (gethash term counts))
                          term-counts)))
          (setf (gethash term idf)
                (log (+ 1d0
                        (/ (+ (- (length documents) frequency) 0.5d0)
                           (+ frequency 0.5d0)))))))
      (loop for document in documents
            for counts in term-counts
            for length in lengths
            for index from 0
            do (let ((score 0d0))
                 (dolist (term query-terms)
                   (let ((count (gethash term counts)))
                     (when count
                       (let ((norm
                               (* k1
                                  (+ (- 1d0 b)
                                     (/ (* b length) average)))))
                         (incf score
                               (* (gethash term idf 0d0)
                                  (/ (* count (+ k1 1d0))
                                     (+ count norm))))))))
                 (when (plusp score)
                   (push (make-tool-search-match
                          :name (getf document :name)
                          :score score)
                         matches))))
      (let ((ordered
              (stable-sort (nreverse matches)
                           #'>
                           :key #'tool-search-match-score)))
        (subseq ordered 0 (min limit (length ordered)))))))

(defun tool-search-exposure (tool)
  (let ((exposure (or (tool-search-field tool :exposure)
                      (tool-search-field tool "exposure")
                      :direct)))
    (cond
      ((stringp exposure)
       (intern (string-upcase exposure) :keyword))
      (t exposure))))

(defun tool-search-positive-limit (limit)
  (cond
    ((null limit) 8)
    ((and (integerp limit) (plusp limit)) limit)
    ((and (floatp limit)
          (plusp limit)
          (= limit (float (floor limit) limit)))
     (floor limit))
    (t (error "limit must be a positive integer"))))

(defun tool-search-load (tools active query &optional (limit 8))
  (let* ((candidates
           (remove-if-not
            (lambda (tool)
              (and (member (tool-search-exposure tool)
                           '(:codemode :deferred))
                   (not (member (tool-search-field tool :name)
                                active :test #'string=))))
            tools))
         (documents
           (mapcar
            (lambda (tool)
              (tool-search-document
               tool
               (or (tool-search-field tool :namespace)
                   (tool-search-field tool "namespace"))))
            candidates))
         (matches (tool-search-rank query documents limit))
         (loaded
           (mapcar
            (lambda (match)
              (let ((tool
                      (find (tool-search-match-name match)
                            candidates
                            :key (lambda (candidate)
                                   (tool-search-field candidate :name))
                            :test #'string=)))
                (list :name (tool-search-match-name match)
                      :description
                      (or (and tool
                               (tool-search-field tool :description))
                          ""))))
            matches)))
    (values loaded
            (if matches
                (append active (mapcar #'tool-search-match-name matches))
                active))))

(defun tool-search-result-text (loaded)
  (if (null loaded)
      "No matching tools found."
      (format nil
              "Loaded ~D tool~A. They are available from your next call:~%~{~A~^~%~}"
              (length loaded)
              (if (= (length loaded) 1) "" "s")
              (mapcar
               (lambda (tool)
                 (let* ((description
                          (string-trim
                           '(#\Space #\Tab #\Newline #\Return)
                           (or (getf tool :description) "")))
                        (line-end
                          (position-if
                           (lambda (char)
                             (member char '(#\Newline #\Return)))
                           description)))
                   (format nil "- ~A: ~A"
                           (getf tool :name)
                           (subseq description
                                   0
                                   (or line-end (length description))))))
               loaded))))

(defun tool-search-argument (arguments key)
  (cond
    ((or (hash-table-p arguments)
         (cadr-ai::json-object-pairs-p arguments))
     (cadr-ai::json-get arguments key))
    ((consp arguments)
     (getf arguments (intern (string-upcase key) :keyword)))
    (t nil)))

(defun agent-tool-search-records (agent)
  (let ((host (agent-extension-host agent)))
    (loop for tool in (merged-agent-tools agent)
          for name = (cadr-ai:tool-name tool)
          collect (list :name name
                        :description (cadr-ai:tool-description tool)
                        :parameters (cadr-ai:tool-parameters tool)
                        :exposure
                        (if host
                            (extension-tool-exposure host name)
                            :direct)))))

(defun agent-tool-search-activate (agent names)
  (let ((host (agent-extension-host agent)))
    (if host
        (extension-host-set-active-tools host names)
        (progn
          (setf (agent-tool-filter-function agent)
                (lambda (candidates)
                  (remove-if-not
                   (lambda (tool)
                     (member (cadr-ai:tool-name tool)
                             names :test #'string=))
                   candidates)))
          (refresh-agent-extension-tools agent)
          names))))

(defun make-tool-search-parameters ()
  (let ((parameters (make-hash-table :test #'equal))
        (properties (make-hash-table :test #'equal))
        (query (make-hash-table :test #'equal))
        (limit (make-hash-table :test #'equal)))
    (setf (gethash "type" query) "string"
          (gethash "description" query)
          "Search query for deferred tools."
          (gethash "type" limit) "number"
          (gethash "description" limit)
          "Maximum number of tools to return. Defaults to 8."
          (gethash "query" properties) query
          (gethash "limit" properties) limit
          (gethash "type" parameters) "object"
          (gethash "properties" parameters) properties
          (gethash "required" parameters)
          (make-array 1 :initial-element "query"))
    parameters))

(defun make-tool-search-tool
    (&key get-tools get-active set-active)
  (cadr-ai:make-tool
   :name "tool_search"
   :description +tool-search-description+
   :parameters (make-tool-search-parameters)
   :execution-mode :parallel
   :executor
   (lambda (call-id arguments)
     (declare (ignore call-id))
     (let* ((query (tool-search-argument arguments "query"))
            (limit (tool-search-positive-limit
                    (tool-search-argument arguments "limit")))
            (agent *tool-search-agent*))
       (unless (and (stringp query)
                    (plusp (length
                            (string-trim
                             '(#\Space #\Tab #\Newline #\Return)
                             query))))
         (error "query must not be empty"))
       (multiple-value-bind (loaded active)
           (tool-search-load
            (cond
              (get-tools (funcall get-tools))
              (agent (agent-tool-search-records agent))
              (t nil))
            (cond
              (get-active (funcall get-active))
              (agent
               (mapcar #'cadr-ai:tool-name
                       (registry-tools (agent-tool-registry agent))))
              (t nil))
            (string-trim '(#\Space #\Tab #\Newline #\Return) query)
            limit)
         (when (and loaded set-active)
           (funcall set-active active))
         (when (and loaded agent (not set-active))
           (agent-tool-search-activate agent active))
         (let ((details (make-hash-table :test #'equal)))
           (setf (gethash "loaded" details)
                 (map 'vector
                      (lambda (tool) (getf tool :name))
                      loaded))
           (values
            (list (cadr-ai:make-text-content
                   :text (tool-search-result-text loaded)))
            details)))))))
