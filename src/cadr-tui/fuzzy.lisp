(in-package #:cadr-tui)

(defun fuzzy-boundary-p (text index)
  (or (zerop index)
      (find (char text (1- index))
            " -_./:"
            :test #'char=)))

(defun fuzzy-match-core (query text)
  (let ((normalized-query (string-downcase query))
        (normalized-text (string-downcase text)))
    (when (zerop (length normalized-query))
      (return-from fuzzy-match-core (values t 0d0)))
    (when (> (length normalized-query)
             (length normalized-text))
      (return-from fuzzy-match-core (values nil 0d0)))
    (let ((query-index 0)
          (score 0d0)
          (last-match -1)
          (consecutive 0))
      (loop for index below (length normalized-text)
            while (< query-index
                     (length normalized-query))
            when
              (char=
               (char normalized-text index)
               (char normalized-query query-index))
              do
              (if (= last-match (1- index))
                  (progn
                    (incf consecutive)
                    (decf score (* consecutive 5)))
                  (progn
                    (setf consecutive 0)
                    (when (>= last-match 0)
                      (incf score
                            (* (- index last-match 1)
                               2)))))
              (when (fuzzy-boundary-p normalized-text index)
                (decf score 10))
              (incf score (* index 0.1d0))
              (setf last-match index)
              (incf query-index))
      (when (< query-index (length normalized-query))
        (return-from fuzzy-match-core
          (values nil 0d0)))
      (when (string= normalized-query normalized-text)
        (decf score 100))
      (values t score))))

(defun swapped-alpha-numeric-query (query)
  (multiple-value-bind (matched captures)
      (cl-ppcre:scan-to-strings
       "^([a-z]+)([0-9]+)$"
       (string-downcase query))
    (when matched
      (return-from swapped-alpha-numeric-query
        (concatenate
         'string (aref captures 1)
         (aref captures 0)))))
  (multiple-value-bind (matched captures)
      (cl-ppcre:scan-to-strings
       "^([0-9]+)([a-z]+)$"
       (string-downcase query))
    (when matched
      (concatenate
       'string (aref captures 1)
       (aref captures 0)))))

(defun fuzzy-match (query text)
  (multiple-value-bind (matched-p score)
      (fuzzy-match-core query text)
    (when matched-p
      (return-from fuzzy-match
        (values t score)))
    (let ((swapped
            (swapped-alpha-numeric-query query)))
      (if swapped
          (multiple-value-bind
                (swapped-matched-p swapped-score)
              (fuzzy-match-core swapped text)
            (if swapped-matched-p
                (values t (+ swapped-score 5))
                (values nil 0d0)))
          (values nil 0d0)))))

(defun fuzzy-query-tokens (query)
  (remove
   ""
   (cl-ppcre:split "[\\s/]+" (string-trim
                              '(#\Space #\Tab #\Newline #\Return)
                              query))
   :test #'string=))

(defun fuzzy-filter (items query text-function)
  (let ((tokens (fuzzy-query-tokens query)))
    (when (null tokens)
      (return-from fuzzy-filter (copy-list items)))
    (let ((matches nil))
      (dolist (item items)
        (let ((score 0d0)
              (matched-p t)
              (text (funcall text-function item)))
          (dolist (token tokens)
            (multiple-value-bind
                  (token-matched-p token-score)
                (fuzzy-match token text)
              (unless token-matched-p
                (setf matched-p nil)
                (return))
              (incf score token-score)))
          (when matched-p
            (push (cons item score) matches))))
      (mapcar
       #'car
       (stable-sort
        matches #'< :key #'cdr)))))
