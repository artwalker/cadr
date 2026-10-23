(in-package #:cadr-wasm/tests)

(in-suite cadr-wasm-suite)

(defun decode-module (text)
  (cadr-wasm::decode-base64 text))

(defun spectest-table ()
  (let ((table (make-hash-table :test #'equal)))
    (flet ((func (name params)
             (setf (gethash name table)
                   (make-wasm-extern :kind :func
                                     :value (lambda (&rest args)
                                              (declare (ignore args))
                                              (values))
                                     :type (cadr-wasm::wasi-sig params nil))))
           (global (name type value)
             (setf (gethash name table)
                   (make-wasm-extern :kind :global
                                     :value (make-wasm-gcell :value value)
                                     :type (cons type nil)))))
      (func "print" nil)
      (func "print_i32" '(:i32))
      (func "print_i64" '(:i64))
      (func "print_f32" '(:f32))
      (func "print_f64" '(:f64))
      (func "print_i32_f32" '(:i32 :f32))
      (func "print_f32_f32" '(:f32 :f32))
      (func "print_f64_f64" '(:f64 :f64))
      (func "print_i32_f64" '(:i32 :f64))
      (global "global_i32" :i32 666)
      (global "global_i64" :i64 666)
      (global "global_f32" :f32 1143383654)
      (global "global_f64" :f64 4649074691427585229)
      (setf (gethash "table" table)
            (make-wasm-extern :kind :table
                              :value (cadr-wasm::make-table
                                      (make-wasm-table-type :element :funcref :min 10 :max 20))
                              :type (make-wasm-table-type :element :funcref :min 10 :max 20)))
      (setf (gethash "memory" table)
            (make-wasm-extern :kind :memory
                              :value (cadr-wasm::make-memory
                                      (make-wasm-memory-type :min 1 :max 2))
                              :type (make-wasm-memory-type :min 1 :max 2))))
    table))

(defun registry-imports (registry)
  (let ((flat (make-hash-table :test #'equal)))
    (maphash (lambda (module table)
               (maphash (lambda (name extern)
                          (setf (gethash (cons module name) flat) extern))
                        table))
             registry)
    flat))

(defun export-table (instance)
  (let ((table (make-hash-table :test #'equal)))
    (loop for item across (cadr-wasm::wasm-module-exports
                           (cadr-wasm::wasm-instance-module instance))
          do (setf (gethash (cadr-wasm::wasm-export-name item) table)
                   (get-export instance (cadr-wasm::wasm-export-name item))))
    table))

(defun remember-instance (modules name instance)
  (when name
    (setf (gethash name modules) instance))
  instance)

(defun module-instance (modules current id)
  (if id (gethash id modules) current))

(defun nan-bits (value width)
  (cond ((integerp value) value)
        ((eq value :canonical) (if (= width 32) #x7fc00000 #x7ff8000000000000))
        ((eq value :-canonical) (if (= width 32) #xffc00000 #xfff8000000000000))
        ((eq value :arithmetic) (if (= width 32) #x7fc00001 #x7ff8000000000001))
        ((eq value :-arithmetic) (if (= width 32) #xffc00001 #xfff8000000000001))
        (t value)))

(defun arg-value (arg)
  (destructuring-bind (type value) arg
    (case type
      (:f32 (nan-bits value 32))
      (:f64 (nan-bits value 64))
      (:funcref (if (eq value :null) cadr-wasm::+null-funcref+ value))
      (:externref (if (eq value :null) cadr-wasm::+null-externref+ value))
      (t value))))

(defun run-action (modules current action)
  (destructuring-bind (kind id name &rest args) action
    (let ((instance (module-instance modules current id)))
      (case kind
        (:invoke (apply #'invoke instance name (mapcar #'arg-value args)))
        (:get (list (global-value instance name)))))))

(defun value-matches (expected actual)
  (destructuring-bind (type value) expected
    (case type
      ((:i32 :i64) (= value actual))
      (:f32 (float-matches value actual #x7fc00000 #x80000000 #x7f800000 22))
      (:f64 (float-matches value actual #x7ff8000000000000 #x8000000000000000
                           #x7ff0000000000000 51))
      ((:funcref :externref) (or (and (eq value :null) (cadr-wasm::null-ref-p actual))
                                 (eql value actual))))))

(defun float-matches (expected actual canonical sign-bit exponent-mask payload-bit)
  (cond ((integerp expected) (= expected actual))
        ((eq expected :canonical) (= actual canonical))
        ((eq expected :-canonical) (= actual (logior canonical sign-bit)))
        ((eq expected :arithmetic)
         (and (= (logand actual exponent-mask) exponent-mask)
              (logbitp payload-bit actual)))
        ((eq expected :-arithmetic)
         (and (logbitp (1- (integer-length sign-bit)) actual)
              (= (logand actual exponent-mask) exponent-mask)
              (logbitp payload-bit actual)))
        (t nil)))

(defun failure-text (condition)
  (if (typep condition 'wasm-error)
      (wasm-message condition)
      (princ-to-string condition)))

(defun check-message (condition expected)
  (search expected (failure-text condition)))

(defun run-fixture (path)
  (let* ((commands (with-open-file (stream path) (read stream)))
         (registry (make-hash-table :test #'equal))
         (modules (make-hash-table :test #'equal))
         (current nil)
         (failures nil))
    (setf (gethash "spectest" registry) (spectest-table))
    (loop for command in commands
          for index from 1
          do (handler-case
                 (case (first command)
                   (:module
                    (setf current
                          (remember-instance
                           modules (second command)
                           (instantiate (compile-module (decode-module (third command)))
                                        (registry-imports registry)))))
                   (:assert-return
                    (let ((actual (run-action modules current (second command)))
                          (expected (third command)))
                      (unless (and (= (length actual) (length expected))
                                   (every #'value-matches expected actual))
                        (push (format nil "~A return ~A expected ~A" index actual expected)
                              failures))))
                   ((:assert-trap :assert-exhaustion)
                    (handler-case
                        (progn (run-action modules current (second command))
                               (push (format nil "~A missing trap ~A" index (third command))
                                     failures))
                      (wasm-trap (condition)
                        (unless (check-message condition (third command))
                          (push (format nil "~A trap ~A wanted ~A"
                                        index (wasm-message condition) (third command))
                                failures)))))
                   (:assert-malformed
                    (handler-case
                        (progn (parse-module (decode-module (third command)))
                               (push (format nil "~A missing malformed ~A" index (fourth command))
                                     failures))
                      (wasm-malformed (condition)
                        (unless (check-message condition (fourth command))
                          (push (format nil "~A malformed ~A wanted ~A"
                                        index (wasm-message condition) (fourth command))
                                failures)))))
                   (:assert-malformed-quote
                    (let ((text (map 'string #'code-char (decode-module (second command)))))
                      (handler-case
                          (progn (parse-module-text text)
                                 (push (format nil "~A missing quote malformed ~A"
                                               index (third command))
                                       failures))
                        (wasm-malformed (condition)
                          (unless (check-message condition (third command))
                            (push (format nil "~A quote malformed ~A wanted ~A"
                                          index (wasm-message condition) (third command))
                                  failures))))))
                   (:assert-invalid
                    (handler-case
                        (progn (compile-module (decode-module (third command)))
                               (push (format nil "~A missing invalid ~A" index (fourth command))
                                     failures))
                      ((or wasm-invalid wasm-malformed) (condition)
                        (unless (check-message condition (fourth command))
                          (push (format nil "~A invalid ~A wanted ~A"
                                        index (wasm-message condition) (fourth command))
                                failures)))))
                   (:assert-unlinkable
                    (handler-case
                        (progn (instantiate (compile-module (decode-module (third command)))
                                            (registry-imports registry))
                               (push (format nil "~A missing unlinkable ~A" index (fourth command))
                                     failures))
                      (wasm-unlinkable (condition)
                        (unless (check-message condition (fourth command))
                          (push (format nil "~A unlinkable ~A wanted ~A"
                                        index (wasm-message condition) (fourth command))
                                failures)))))
                   (:assert-trap-module
                    (handler-case
                        (progn (instantiate (compile-module (decode-module (third command)))
                                            (registry-imports registry))
                               (push (format nil "~A missing module trap ~A" index (fourth command))
                                     failures))
                      (wasm-trap (condition)
                        (unless (check-message condition (fourth command))
                          (push (format nil "~A module trap ~A wanted ~A"
                                        index (wasm-message condition) (fourth command))
                                failures)))))
                   (:register
                    (let ((instance (if (third command)
                                        (gethash (third command) modules)
                                        current)))
                      (setf (gethash (second command) registry) (export-table instance))))
                   (:action (run-action modules current (second command)))
                   (:assemble-error
                    (push (format nil "~A assemble ~A" index (second command)) failures)))
               (error (condition)
                 (push (format nil "~A error ~A" index (failure-text condition)) failures))))
    (nreverse failures)))

(defun spec-fixtures ()
  (sort (directory (make-pathname
                    :name :wild :type "lisp"
                    :defaults (merge-pathnames
                               "test/fixtures/wasm-spec/"
                               (asdf:system-source-directory "cadr-wasm"))))
        #'string< :key #'file-namestring))

(defun fixture-commands (name)
  (with-open-file (stream (merge-pathnames
                           (format nil "test/fixtures/wasm-spec/~A" name)
                           (asdf:system-source-directory "cadr-wasm")))
    (read stream)))

(test wasm-2-0-quote-malformed-fixtures-cover-the-empty-files
  (is (= 176 (length (fixture-commands "utf8-invalid-encoding.lisp"))))
  (is (= 11 (length (fixture-commands "obsolete-keywords.lisp"))))
  (is (every (lambda (command)
               (and (eq (first command) :assert-malformed-quote)
                    (string= (third command) "malformed UTF-8 encoding")))
             (fixture-commands "utf8-invalid-encoding.lisp")))
  (is (equal '("unknown operator current_memory"
               "unknown operator grow_memory"
               "unknown operator get_local"
               "unknown operator set_local"
               "unknown operator tee_local"
               "unknown operator anyfunc"
               "unknown operator get_global"
               "unknown operator set_global"
               "unknown operator i32.wrap/i64"
               "unknown operator i32.trunc_s:sat/f32"
               "unknown operator f32x4.convert_s/i32x4")
             (mapcar #'third (fixture-commands "obsolete-keywords.lisp")))))

(test wasm-2-0-quote-malformed-covers-the-non-simd-suite
  "Official wg-2.0 test/core has 581 non-SIMD (module quote) assert_malformed.
The two files that were empty before the review are included in that total."
  (is (= 581
         (loop for path in (spec-fixtures)
               sum (count-if (lambda (command)
                               (and (consp command)
                                    (eq (first command) :assert-malformed-quote)))
                             (with-open-file (stream path) (read stream)))))))

(defun run-fixture-isolated (path)
  "Compile one spec fixture in a fresh default-heap SBCL.
skip-stack-guard-page's compiler temporary alone is about 400MB, and
running every fixture in one image exhausts the 1GB heap."
  (let* ((setup (or (uiop:getenv "QUICKLISP_SETUP")
                    (namestring (merge-pathnames "quicklisp/setup.lisp"
                                                 (user-homedir-pathname)))))
         (output (make-string-output-stream))
         ;; The child reads every --eval form before running any of them, so
         ;; this form cannot mention the test package until load-system has run.
         (form (format nil
                       "(progn ~
                          (asdf:load-asd ~S) ~
                          (asdf:load-system \"cadr-wasm/tests\") ~
                          (let ((fails (funcall (find-symbol \"RUN-FIXTURE\" \"CADR-WASM/TESTS\") ~S))) ~
                            (dolist (item fails) (write-line item)) ~
                            (sb-ext:exit :code (if fails 1 0))))"
                       (namestring (asdf:system-source-file "cadr-wasm"))
                       (namestring path)))
         (process
           (sb-ext:run-program
            (or (uiop:getenv "SBCL") "sbcl")
            (list "--noinform" "--disable-debugger" "--non-interactive"
                  "--load" setup
                  "--eval" form)
            :output output
            :error output
            :search t))
         (text (get-output-stream-string output)))
    (if (zerop (sb-ext:process-exit-code process))
        nil
        (list (format nil "~A ~A"
                      (file-namestring path)
                      (if (> (length text) 600)
                          (subseq text (- (length text) 600))
                          text))))))

(test wasm-2-0-core-suite-except-simd
  (dolist (path (spec-fixtures))
    (let ((fails (run-fixture-isolated path)))
      (is (null fails) "~A" fails))))

(test quickjs-wasm-loads-the-ahead-of-time-image
  (let ((compiled (ensure-compiled (quickjs-wasm-bytes))))
    (is (last-compile-cached-p))
    (is (= 0d0 (last-compile-seconds)))
    (is (= 1698 (length (cadr-wasm::compiled-module-funcs compiled))))
    (is (eq compiled (ensure-compiled (quickjs-wasm-bytes))))))
