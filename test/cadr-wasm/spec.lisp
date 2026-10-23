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

(test wasm-2-0-core-suite-except-simd
  (dolist (path (spec-fixtures))
    (let ((fails (run-fixture path)))
      (is (null fails)
          "~A ~A ~A"
          (file-namestring path)
          (length fails)
          (subseq fails 0 (min 5 (length fails)))))))
