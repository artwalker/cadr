(in-package #:cadr-wasm)

(defparameter *obsolete-wat-operators*
  (let ((table (make-hash-table :test #'equal)))
    (dolist (name '("current_memory" "grow_memory" "get_local" "set_local"
                    "tee_local" "anyfunc" "get_global" "set_global"
                    "i32.wrap/i64" "i32.trunc_s:sat/f32"
                    "f32x4.convert_s/i32x4"))
      (setf (gethash name table) t))
    table))

(defun wat-hex-value (char)
  (let ((code (char-code char)))
    (cond ((<= 48 code 57) (- code 48))
          ((<= 97 code 102) (- code 87))
          ((<= 65 code 70) (- code 55)))))

(defun wat-push-byte (bytes value)
  (vector-push-extend (logand value #xff) bytes))

(defun wat-decode-string (text index)
  "Decode one WAT string starting at a quote. Return the index after it.
Signal wasm-malformed when the decoded bytes are not UTF-8."
  (let ((bytes (make-array 16 :element-type '(unsigned-byte 8)
                           :fill-pointer 0 :adjustable t))
        (length (length text)))
    (incf index)
    (loop
      (when (>= index length)
        (wasm-fail 'wasm-malformed "unexpected end of string"))
      (let ((char (char text index)))
        (cond
          ((char= char #\")
           (incf index)
           (loop for cursor = 0 then (+ cursor width)
                 while (< cursor (length bytes))
                 for width = (nth-value 1 (consume-utf8 bytes cursor)))
           (return index))
          ((char= char #\\)
           (incf index)
           (when (>= index length)
             (wasm-fail 'wasm-malformed "unexpected end of string"))
           (let ((escape (char text index)))
             (incf index)
             (cond
               ((char= escape #\n) (wat-push-byte bytes 10))
               ((char= escape #\t) (wat-push-byte bytes 9))
               ((char= escape #\r) (wat-push-byte bytes 13))
               ((char= escape #\') (wat-push-byte bytes 39))
               ((char= escape #\") (wat-push-byte bytes 34))
               ((char= escape #\\) (wat-push-byte bytes 92))
               ((char= escape #\u)
                (unless (and (< index length) (char= (char text index) #\{))
                  (wasm-fail 'wasm-malformed "malformed UTF-8 encoding"))
                (incf index)
                (let ((code 0)
                      (digits 0))
                  (loop
                    (when (>= index length)
                      (wasm-fail 'wasm-malformed "malformed UTF-8 encoding"))
                    (let ((digit (wat-hex-value (char text index))))
                      (when (null digit) (return))
                      (setf code (+ (* code 16) digit))
                      (incf digits)
                      (incf index)))
                  (unless (and (plusp digits)
                               (< index length)
                               (char= (char text index) #\})
                               (<= code #x10ffff))
                    (wasm-fail 'wasm-malformed "malformed UTF-8 encoding"))
                  (incf index)
                  (let ((encoded (sb-ext:string-to-octets
                                  (string (code-char code))
                                  :external-format :utf-8)))
                    (loop for byte across encoded do (wat-push-byte bytes byte)))))
               (t
                (let ((high (wat-hex-value escape))
                      (low (and (< index length) (wat-hex-value (char text index)))))
                  (unless (and high low)
                    (wasm-fail 'wasm-malformed "malformed UTF-8 encoding"))
                  (incf index)
                  (wat-push-byte bytes (+ (* high 16) low)))))))
          (t
           (let ((code (char-code char)))
             (if (< code 128)
                 (wat-push-byte bytes code)
                 (let ((encoded (sb-ext:string-to-octets
                                 (string char) :external-format :utf-8)))
                   (loop for byte across encoded do (wat-push-byte bytes byte)))))
           (incf index)))))))

(defparameter *wat-keywords*
  (let ((table (make-hash-table :test #'equal)))
    (dolist (name '(
"i32" "i64" "f32" "f64" "v128" "i8x16" "i16x8" "i32x4"
"i64x2" "f32x4" "f64x2" "extern" "externref" "funcref" "mut" "nop"
"unreachable" "drop" "block" "loop" "end" "br" "br_if" "br_table"
"return" "if" "then" "else" "select" "call" "call_indirect" "local.get"
"local.set" "local.tee" "global.get" "global.set" "table.get" "table.set" "table.size" "table.grow"
"table.fill" "table.copy" "table.init" "elem.drop" "memory.size" "memory.grow" "memory.fill" "memory.copy"
"memory.init" "data.drop" "i32.load" "i64.load" "f32.load" "f64.load" "i32.store" "i64.store"
"f32.store" "f64.store" "i32.load8_u" "i32.load8_s" "i32.load16_u" "i32.load16_s" "i64.load8_u" "i64.load8_s"
"i64.load16_u" "i64.load16_s" "i64.load32_u" "i64.load32_s" "i32.store8" "i32.store16" "i64.store8" "i64.store16"
"i64.store32" "v128.load" "v128.store" "v128.load8x8_u" "v128.load8x8_s" "v128.load16x4_u" "v128.load16x4_s" "v128.load32x2_u"
"v128.load32x2_s" "v128.load8_splat" "v128.load16_splat" "v128.load32_splat" "v128.load64_splat" "v128.load32_zero" "v128.load64_zero" "v128.load8_lane"
"v128.load16_lane" "v128.load32_lane" "v128.load64_lane" "v128.store8_lane" "v128.store16_lane" "v128.store32_lane" "v128.store64_lane" "i32.const"
"i64.const" "f32.const" "f64.const" "v128.const" "ref.null" "ref.func" "ref.extern" "ref.is_null"
"i32.clz" "i32.ctz" "i32.popcnt" "i32.extend8_s" "i32.extend16_s" "i64.clz" "i64.ctz" "i64.popcnt"
"i64.extend8_s" "i64.extend16_s" "i64.extend32_s" "f32.neg" "f32.abs" "f32.sqrt" "f32.ceil" "f32.floor"
"f32.trunc" "f32.nearest" "f64.neg" "f64.abs" "f64.sqrt" "f64.ceil" "f64.floor" "f64.trunc"
"f64.nearest" "i32.add" "i32.sub" "i32.mul" "i32.div_u" "i32.div_s" "i32.rem_u" "i32.rem_s"
"i32.and" "i32.or" "i32.xor" "i32.shl" "i32.shr_u" "i32.shr_s" "i32.rotl" "i32.rotr"
"i64.add" "i64.sub" "i64.mul" "i64.div_u" "i64.div_s" "i64.rem_u" "i64.rem_s" "i64.and"
"i64.or" "i64.xor" "i64.shl" "i64.shr_u" "i64.shr_s" "i64.rotl" "i64.rotr" "f32.add"
"f32.sub" "f32.mul" "f32.div" "f32.min" "f32.max" "f32.copysign" "f64.add" "f64.sub"
"f64.mul" "f64.div" "f64.min" "f64.max" "f64.copysign" "i32.eqz" "i64.eqz" "i32.eq"
"i32.ne" "i32.lt_u" "i32.lt_s" "i32.le_u" "i32.le_s" "i32.gt_u" "i32.gt_s" "i32.ge_u"
"i32.ge_s" "i64.eq" "i64.ne" "i64.lt_u" "i64.lt_s" "i64.le_u" "i64.le_s" "i64.gt_u"
"i64.gt_s" "i64.ge_u" "i64.ge_s" "f32.eq" "f32.ne" "f32.lt" "f32.le" "f32.gt"
"f32.ge" "f64.eq" "f64.ne" "f64.lt" "f64.le" "f64.gt" "f64.ge" "i32.wrap_i64"
"i64.extend_i32_s" "i64.extend_i32_u" "f32.demote_f64" "f64.promote_f32" "i32.trunc_f32_u" "i32.trunc_f32_s" "i64.trunc_f32_u" "i64.trunc_f32_s"
"i32.trunc_f64_u" "i32.trunc_f64_s" "i64.trunc_f64_u" "i64.trunc_f64_s" "i32.trunc_sat_f32_u" "i32.trunc_sat_f32_s" "i64.trunc_sat_f32_u" "i64.trunc_sat_f32_s"
"i32.trunc_sat_f64_u" "i32.trunc_sat_f64_s" "i64.trunc_sat_f64_u" "i64.trunc_sat_f64_s" "f32.convert_i32_u" "f32.convert_i32_s" "f64.convert_i32_u" "f64.convert_i32_s"
"f32.convert_i64_u" "f32.convert_i64_s" "f64.convert_i64_u" "f64.convert_i64_s" "f32.reinterpret_i32" "f64.reinterpret_i64" "i32.reinterpret_f32" "i64.reinterpret_f64"
"v128.not" "v128.and" "v128.andnot" "v128.or" "v128.xor" "v128.bitselect" "v128.any_true" "i8x16.neg"
"i16x8.neg" "i32x4.neg" "i64x2.neg" "i8x16.abs" "i16x8.abs" "i32x4.abs" "i64x2.abs" "i8x16.popcnt"
"i8x16.avgr_u" "i16x8.avgr_u" "f32x4.neg" "f64x2.neg" "f32x4.abs" "f64x2.abs" "f32x4.sqrt" "f64x2.sqrt"
"f32x4.ceil" "f64x2.ceil" "f32x4.floor" "f64x2.floor" "f32x4.trunc" "f64x2.trunc" "f32x4.nearest" "f64x2.nearest"
"i32x4.trunc_sat_f32x4_u" "i32x4.trunc_sat_f32x4_s" "i32x4.trunc_sat_f64x2_u_zero" "i32x4.trunc_sat_f64x2_s_zero" "f64x2.promote_low_f32x4" "f32x4.demote_f64x2_zero" "f32x4.convert_i32x4_u" "f32x4.convert_i32x4_s"
"f64x2.convert_low_i32x4_u" "f64x2.convert_low_i32x4_s" "i16x8.extadd_pairwise_i8x16_u" "i16x8.extadd_pairwise_i8x16_s" "i32x4.extadd_pairwise_i16x8_u" "i32x4.extadd_pairwise_i16x8_s" "i8x16.eq" "i16x8.eq"
"i32x4.eq" "i64x2.eq" "i8x16.ne" "i16x8.ne" "i32x4.ne" "i64x2.ne" "i8x16.lt_u" "i8x16.lt_s"
"i16x8.lt_u" "i16x8.lt_s" "i32x4.lt_u" "i32x4.lt_s" "i64x2.lt_s" "i8x16.le_u" "i8x16.le_s" "i16x8.le_u"
"i16x8.le_s" "i32x4.le_u" "i32x4.le_s" "i64x2.le_s" "i8x16.gt_u" "i8x16.gt_s" "i16x8.gt_u" "i16x8.gt_s"
"i32x4.gt_u" "i32x4.gt_s" "i64x2.gt_s" "i8x16.ge_u" "i8x16.ge_s" "i16x8.ge_u" "i16x8.ge_s" "i32x4.ge_u"
"i32x4.ge_s" "i64x2.ge_s" "f32x4.eq" "f64x2.eq" "f32x4.ne" "f64x2.ne" "f32x4.lt" "f64x2.lt"
"f32x4.le" "f64x2.le" "f32x4.gt" "f64x2.gt" "f32x4.ge" "f64x2.ge" "i8x16.swizzle" "i8x16.add"
"i16x8.add" "i32x4.add" "i64x2.add" "i8x16.sub" "i16x8.sub" "i32x4.sub" "i64x2.sub" "i16x8.mul"
"i32x4.mul" "i64x2.mul" "i8x16.add_sat_u" "i8x16.add_sat_s" "i16x8.add_sat_u" "i16x8.add_sat_s" "i8x16.sub_sat_u" "i8x16.sub_sat_s"
"i16x8.sub_sat_u" "i16x8.sub_sat_s" "i32x4.dot_i16x8_s" "i8x16.min_u" "i16x8.min_u" "i32x4.min_u" "i8x16.min_s" "i16x8.min_s"
"i32x4.min_s" "i8x16.max_u" "i16x8.max_u" "i32x4.max_u" "i8x16.max_s" "i16x8.max_s" "i32x4.max_s" "f32x4.add"
"f64x2.add" "f32x4.sub" "f64x2.sub" "f32x4.mul" "f64x2.mul" "f32x4.div" "f64x2.div" "f32x4.min"
"f64x2.min" "f32x4.max" "f64x2.max" "f32x4.pmin" "f64x2.pmin" "f32x4.pmax" "f64x2.pmax" "i16x8.q15mulr_sat_s"
"i8x16.narrow_i16x8_u" "i8x16.narrow_i16x8_s" "i16x8.narrow_i32x4_u" "i16x8.narrow_i32x4_s" "i16x8.extend_low_i8x16_u" "i16x8.extend_low_i8x16_s" "i16x8.extend_high_i8x16_u" "i16x8.extend_high_i8x16_s"
"i32x4.extend_low_i16x8_u" "i32x4.extend_low_i16x8_s" "i32x4.extend_high_i16x8_u" "i32x4.extend_high_i16x8_s" "i64x2.extend_low_i32x4_u" "i64x2.extend_low_i32x4_s" "i64x2.extend_high_i32x4_u" "i64x2.extend_high_i32x4_s"
"i16x8.extmul_low_i8x16_u" "i16x8.extmul_low_i8x16_s" "i16x8.extmul_high_i8x16_u" "i16x8.extmul_high_i8x16_s" "i32x4.extmul_low_i16x8_u" "i32x4.extmul_low_i16x8_s" "i32x4.extmul_high_i16x8_u" "i32x4.extmul_high_i16x8_s"
"i64x2.extmul_low_i32x4_u" "i64x2.extmul_low_i32x4_s" "i64x2.extmul_high_i32x4_u" "i64x2.extmul_high_i32x4_s" "i8x16.all_true" "i16x8.all_true" "i32x4.all_true" "i64x2.all_true"
"i8x16.bitmask" "i16x8.bitmask" "i32x4.bitmask" "i64x2.bitmask" "i8x16.shl" "i16x8.shl" "i32x4.shl" "i64x2.shl"
"i8x16.shr_u" "i8x16.shr_s" "i16x8.shr_u" "i16x8.shr_s" "i32x4.shr_u" "i32x4.shr_s" "i64x2.shr_u" "i64x2.shr_s"
"i8x16.shuffle" "i8x16.splat" "i16x8.splat" "i32x4.splat" "i64x2.splat" "f32x4.splat" "f64x2.splat" "i8x16.extract_lane_u"
"i8x16.extract_lane_s" "i16x8.extract_lane_u" "i16x8.extract_lane_s" "i32x4.extract_lane" "i64x2.extract_lane" "f32x4.extract_lane" "f64x2.extract_lane" "i8x16.replace_lane"
"i16x8.replace_lane" "i32x4.replace_lane" "i64x2.replace_lane" "f32x4.replace_lane" "f64x2.replace_lane" "type" "func" "param"
"result" "start" "local" "global" "table" "memory" "elem" "data"
"declare" "offset" "item" "import" "export" "module" "binary" "quote"
"script" "register" "invoke" "get" "assert_malformed" "assert_invalid" "assert_unlinkable" "assert_return"
"assert_trap" "assert_exhaustion" "nan:canonical" "nan:arithmetic" "input" "output"
))
      (setf (gethash name table) t))
    table))

(defun wat-digit-p (char)
  (char<= #\0 char #\9))

(defun wat-hex-p (char)
  (or (wat-digit-p char)
      (char<= #\a char #\f)
      (char<= #\A char #\F)))

(defun wat-lower-p (char)
  (char<= #\a char #\z))

(defun wat-letter-p (char)
  (or (wat-lower-p char) (char<= #\A char #\Z)))

(defun wat-idchar-p (char)
  (or (wat-letter-p char) (wat-digit-p char) (char= char #\_)
      (find char "+-*/\\^~=<>!?@#$%&|:`.'")))

(defun wat-keyword-char-p (char)
  (or (wat-letter-p char) (wat-digit-p char) (find char "_.:")))

(defstruct wat-tok kind text)

(defun wat-scan-digits (text index hex-p)
  (let ((pred (if hex-p #'wat-hex-p #'wat-digit-p))
        (length (length text)))
    (unless (and (< index length) (funcall pred (char text index)))
      (return-from wat-scan-digits nil))
    (incf index)
    (loop while (< index length) do
      (cond ((and (char= (char text index) #\_)
                  (< (1+ index) length)
                  (funcall pred (char text (1+ index))))
             (incf index 2))
            ((funcall pred (char text index))
             (incf index))
            (t (return))))
    index))

(defun wat-skip-sign (text index)
  (if (and (< index (length text))
           (find (char text index) "+-"))
      (1+ index)
      index))

(defun wat-match-nat (text index)
  (let ((length (length text)))
    (if (and (< (+ index 2) length)
             (char= (char text index) #\0)
             (char-equal (char text (1+ index)) #\x))
        (wat-scan-digits text (+ index 2) t)
        (wat-scan-digits text index nil))))

(defun wat-match-int (text index)
  (let ((signed (wat-skip-sign text index)))
    (when (> signed index)
      (wat-match-nat text signed))))

(defun wat-match-float (text index)
  (let* ((length (length text))
         (start index)
         (body (wat-skip-sign text index))
         (best nil))
    (labels ((consider (end)
               (when (and end (> end start))
                 (setf best (if best (max best end) end)))))
      (cond
        ((and (< body length) (string-equal (subseq text body (min length (+ body 3))) "inf"))
         (consider (+ body 3)))
        ((and (< body length) (string-equal (subseq text body (min length (+ body 3))) "nan"))
         (let ((end (+ body 3)))
           (consider end)
           (when (and (< end length) (char= (char text end) #\:)
                      (< (+ end 3) length)
                      (char= (char text (1+ end)) #\0)
                      (char-equal (char text (+ end 2)) #\x))
             (consider (wat-scan-digits text (+ end 3) t))))))
      (let ((num (wat-scan-digits text body nil)))
        (when num
          (when (and (< num length) (char= (char text num) #\.))
            (let ((frac (or (wat-scan-digits text (1+ num) nil) (1+ num))))
              (consider frac)
              (when (and (< frac length) (find (char text frac) "eE"))
                (let* ((exp (wat-skip-sign text (1+ frac)))
                       (end (wat-scan-digits text exp nil)))
                  (consider end)))))
          (when (and (< num length) (find (char text num) "eE"))
            (let* ((exp (wat-skip-sign text (1+ num)))
                   (end (wat-scan-digits text exp nil)))
              (consider end)))))
      (when (and (< (+ body 2) length)
                 (char= (char text body) #\0)
                 (char-equal (char text (1+ body)) #\x))
        (let ((hex (wat-scan-digits text (+ body 2) t)))
          (when hex
            (when (and (< hex length) (char= (char text hex) #\.))
              (let ((frac (or (wat-scan-digits text (1+ hex) t) (1+ hex))))
                (consider frac)
                (when (and (< frac length) (find (char text frac) "pP"))
                  (let* ((exp (wat-skip-sign text (1+ frac)))
                         (end (wat-scan-digits text exp nil)))
                    (consider end)))))
            (when (and (< hex length) (find (char text hex) "pP"))
              (let* ((exp (wat-skip-sign text (1+ hex)))
                     (end (wat-scan-digits text exp nil)))
                (consider end))))))
      best)))

(defun wat-match-keyword (text index)
  (let ((length (length text)))
    (unless (and (< index length) (wat-lower-p (char text index)))
      (return-from wat-match-keyword nil))
    (incf index)
    (loop while (and (< index length) (wat-keyword-char-p (char text index)))
          do (incf index))
    (when (and (< index length) (wat-idchar-p (char text index)))
      (return-from wat-match-keyword nil))
    index))

(defun wat-match-reserved (text index)
  "The spec reserved token is (idchar | string)+. It beats a shorter keyword,
so data\"a\" is one unknown operator rather than a keyword and a string."
  (let ((length (length text))
        (start index))
    (when (and (< index length) (find (char text index) ",;[]{}"))
      (return-from wat-match-reserved (1+ index)))
    (loop while (< index length) do
      (cond
        ((wat-idchar-p (char text index))
         (incf index))
        ((char= (char text index) #\")
         (setf index (wat-decode-string text index)))
        (t (return))))
    (when (> index start) index)))

(defun wat-match-idchars (text index)
  (let ((length (length text)))
    (unless (and (< index length) (wat-idchar-p (char text index)))
      (return-from wat-match-idchars nil))
    (incf index)
    (loop while (and (< index length) (wat-idchar-p (char text index)))
          do (incf index))
    index))

(defun wat-skip-space (text index)
  (let ((length (length text)))
    (loop
      (cond
        ((>= index length) (return index))
        ((find (char text index) '(#\space #\tab #\newline #\return))
         (incf index))
        ((and (char= (char text index) #\;) (< (1+ index) length)
              (char= (char text (1+ index)) #\;))
         (incf index 2)
         (loop while (and (< index length) (char/= (char text index) #\newline))
               do (incf index)))
        ((and (char= (char text index) #\() (< (1+ index) length)
              (char= (char text (1+ index)) #\;))
         (incf index 2)
         (let ((depth 1))
           (loop while (and (< index length) (plusp depth)) do
             (cond
               ((and (char= (char text index) #\() (< (1+ index) length)
                     (char= (char text (1+ index)) #\;))
                (incf index 2)
                (incf depth))
               ((and (char= (char text index) #\;) (< (1+ index) length)
                     (char= (char text (1+ index)) #\)))
                (incf index 2)
                (decf depth))
               (t (incf index))))))
        (t (return index))))))

(defun wat-lex (text)
  (let ((index 0)
        (length (length text))
        (tokens nil))
    (loop while (< (setf index (wat-skip-space text index)) length) do
      (let ((char (char text index)))
        (cond
          ((char= char #\()
           (push (make-wat-tok :kind :lpar :text "(") tokens)
           (incf index))
          ((char= char #\))
           (push (make-wat-tok :kind :rpar :text ")") tokens)
           (incf index))
          ((char= char #\")
           (let ((reserved (wat-match-reserved text index))
                 (string-end (wat-decode-string text index)))
             ;; "a""b" and "a"$x are one reserved token. A lone string is not.
             (if (and reserved (> reserved string-end))
                 (wasm-fail 'wasm-malformed
                            (format nil "unknown operator ~A"
                                    (subseq text index reserved)))
                 (progn
                   (push (make-wat-tok :kind :str :text "") tokens)
                   (setf index string-end)))))
          (t
           (let* ((nat (wat-match-nat text index))
                  (int (wat-match-int text index))
                  (float (wat-match-float text index))
                  (keyword (wat-match-keyword text index))
                  (id (and (char= char #\$) (wat-match-idchars text (1+ index))))
                  (ident (wat-match-idchars text index))
                  (reserved (wat-match-reserved text index))
                  (align (and (string= (subseq text index (min length (+ index 6))) "align=")
                              (wat-match-nat text (+ index 6))))
                  (offset (and (string= (subseq text index (min length (+ index 7))) "offset=")
                               (wat-match-nat text (+ index 7))))
                  (best 0)
                  (rank 99)
                  (kind nil)
                  (end nil))
             ;; Longest match, then the earlier spec rule. A hex nat and a
             ;; reserved id can cover the same characters; the nat wins.
             (flet ((offer (name at priority)
                      (when (and at (> at index)
                                 (or (> at best)
                                     (and (= at best) (< priority rank))))
                        (setf best at rank priority kind name end at))))
               (offer :nat nat 0)
               (offer :int int 1)
               (offer :float float 2)
               (offer :kw keyword 3)
               (offer :offset offset 4)
               (offer :align align 5)
               (when id (offer :var id 6))
               (offer :reserved (if (and reserved ident) (max reserved ident) (or reserved ident)) 7))
             (unless kind
               (wasm-fail 'wasm-malformed "malformed UTF-8 encoding"))
             (let ((spelling (subseq text index end)))
               (when (eq kind :kw)
                 (unless (gethash spelling *wat-keywords*)
                   (wasm-fail 'wasm-malformed
                              (format nil "unknown operator ~A" spelling))))
               (when (eq kind :reserved)
                 (wasm-fail 'wasm-malformed
                            (format nil "unknown operator ~A" spelling)))
               (push (make-wat-tok :kind kind :text spelling) tokens)
               (setf index end)))))))
    (nreverse tokens)))

(defun wat-forms (tokens)
  (let ((rest tokens))
    (labels ((peek () (car rest))
             (take () (pop rest))
             (form ()
               (let ((tok (take)))
                 (cond
                   ((null tok)
                    (wasm-fail 'wasm-malformed "unexpected token"))
                   ((eq (wat-tok-kind tok) :lpar)
                    (loop for next = (peek)
                          until (and next (eq (wat-tok-kind next) :rpar))
                          collect (form)
                          finally (unless next
                                    (wasm-fail 'wasm-malformed "unexpected token"))
                                  (take)))
                   ((eq (wat-tok-kind tok) :rpar)
                    (wasm-fail 'wasm-malformed "unexpected token"))
                   (t (cons (wat-tok-kind tok) (wat-tok-text tok)))))))
      (loop while rest collect (form)))))

(defun wat-kw-p (form name)
  (and (consp form) (not (consp (cdr form)))
       (eq (car form) :kw) (string= (cdr form) name)))

(defun wat-kind (form)
  (and (consp form) (not (listp (cdr form))) (car form)))

(defun wat-text (form)
  (and (consp form) (not (listp (cdr form))) (cdr form)))

(defun wat-integer (spelling)
  (let ((sign 1)
        (body spelling))
    (when (and (plusp (length body)) (find (char body 0) "+-"))
      (when (char= (char body 0) #\-) (setf sign -1))
      (setf body (subseq body 1)))
    (* sign
       (if (and (>= (length body) 2)
                (char= (char body 0) #\0)
                (char-equal (char body 1) #\x))
           (parse-integer (remove #\_ (subseq body 2)) :radix 16)
           (parse-integer (remove #\_ body))))))

(defun wat-i32-p (value)
  (<= (- (ash 1 31)) value (1- (ash 1 32))))

(defun wat-i64-p (value)
  (<= (- (ash 1 63)) value (1- (ash 1 64))))

(defun wat-power-of-two-p (value)
  (and (plusp value) (zerop (logand value (1- value)))))

(defun wat-valtype-p (form)
  (and (eq (wat-kind form) :kw)
       (member (wat-text form)
               '("i32" "i64" "f32" "f64" "v128" "funcref" "externref")
               :test #'string=)))

(defun wat-check-align (spelling)
  (let ((value (wat-integer (subseq spelling 6))))
    (unless (wat-power-of-two-p value)
      (wasm-fail 'wasm-malformed "alignment must be a power of two"))))

(defun wat-check-offset (spelling)
  (let ((value (wat-integer (subseq spelling 7))))
    (unless (wat-i32-p value)
      (wasm-fail 'wasm-malformed "i32 constant out of range"))))

(defun wat-signless (spelling)
  (if (and (plusp (length spelling)) (find (char spelling 0) "+-"))
      (subseq spelling 1)
      spelling))

(defun wat-hex-float (body)
  (let* ((rest (subseq body 2))
         (mark (position-if (lambda (char) (find char "pP")) rest))
         (mant (subseq rest 0 (or mark (length rest))))
         (dot (position #\. mant))
         (whole (subseq mant 0 (or dot (length mant))))
         (frac (if dot (subseq mant (1+ dot)) ""))
         (exp (if mark (parse-integer (subseq rest (1+ mark))) 0))
         (denom 1)
         (numer (if (string= whole "") 0 (parse-integer whole :radix 16))))
    (loop for char across frac do
      (setf numer (+ (* numer 16) (digit-char-p char 16))
            denom (* denom 16)))
    (* (/ numer denom) (expt 2 exp))))

(defun wat-dec-float (body)
  (let* ((mark (position-if (lambda (char) (find char "eE")) body))
         (mant (subseq body 0 (or mark (length body))))
         (dot (position #\. mant))
         (whole (subseq mant 0 (or dot (length mant))))
         (frac (if dot (subseq mant (1+ dot)) ""))
         (exp (if mark (parse-integer (subseq body (1+ mark))) 0))
         (denom 1)
         (numer (if (string= whole "") 0 (parse-integer whole))))
    (loop for char across frac do
      (setf numer (+ (* numer 10) (digit-char-p char))
            denom (* denom 10)))
    (* (/ numer denom) (expt 10 exp))))

(defun wat-check-float (op spelling)
  (let* ((body (remove #\_ (wat-signless spelling)))
         (limit (if (string= op "f32.const")
                    most-positive-single-float
                    most-positive-double-float)))
    (cond
      ((or (string= body "inf") (string= body "nan")) nil)
      ((and (>= (length body) 6) (string= (subseq body 0 6) "nan:0x"))
       (let* ((payload (parse-integer (subseq body 6) :radix 16))
              (bare (if (string= op "f32.const") #x7f800000 #x7ff0000000000000)))
         (when (or (zerop payload) (logtest payload bare) (minusp payload))
           (wasm-fail 'wasm-malformed "constant out of range"))))
      (t
       (let ((magnitude (if (and (>= (length body) 2)
                                 (char= (char body 0) #\0)
                                 (char-equal (char body 1) #\x))
                            (wat-hex-float body)
                            (wat-dec-float body))))
         (when (> magnitude limit)
           (wasm-fail 'wasm-malformed "constant out of range")))))))

(defun wat-check-const (op immediate)
  (cond
    ((null immediate)
     (wasm-fail 'wasm-malformed "unexpected token"))
    ((not (member (wat-kind immediate) '(:nat :int :float)))
     (wasm-fail 'wasm-malformed "unexpected token"))
    ((member op '("i32.const" "i64.const") :test #'string=)
     (unless (member (wat-kind immediate) '(:nat :int))
       (wasm-fail 'wasm-malformed "unexpected token"))
     (let ((value (wat-integer (wat-text immediate))))
       (unless (if (string= op "i32.const") (wat-i32-p value) (wat-i64-p value))
         (wasm-fail 'wasm-malformed "constant out of range"))))
    ((member op '("f32.const" "f64.const") :test #'string=)
     (wat-check-float op (wat-text immediate)))))

(defun wat-type-parts (form)
  "Return params and results of a (func ...) type, or nil if this is not one."
  (when (and (consp form) (wat-kw-p (car form) "func"))
    (let ((params nil)
          (results nil)
          (phase :param))
      (dolist (child (rest form))
        (cond
          ((and (consp child) (listp (cdr child)) (wat-kw-p (car child) "param"))
           (unless (eq phase :param)
             (wasm-fail 'wasm-malformed "unexpected token"))
           (dolist (item (rest child))
             (cond
               ((eq (wat-kind item) :var)
                (wasm-fail 'wasm-malformed "unexpected token"))
               ((wat-valtype-p item) (push (wat-text item) params))
               (t (wasm-fail 'wasm-malformed "unexpected token")))))
          ((and (consp child) (listp (cdr child)) (wat-kw-p (car child) "result"))
           (setf phase :result)
           (dolist (item (rest child))
             (if (wat-valtype-p item)
                 (push (wat-text item) results)
                 (wasm-fail 'wasm-malformed "unexpected token"))))
          (t (wasm-fail 'wasm-malformed "unexpected token"))))
      (cons (nreverse params) (nreverse results)))))

(defvar *wat-locals* (make-hash-table :test #'equal))

(defun wat-bind (table category name)
  (when (and name (gethash name table))
    (wasm-fail 'wasm-malformed
               (format nil "duplicate ~A ~A" category name)))
  (when name (setf (gethash name table) t)))

(defun wat-check-module-fields (fields)
  (let ((funcs (make-hash-table :test #'equal))
        (globals (make-hash-table :test #'equal))
        (tables (make-hash-table :test #'equal))
        (memories (make-hash-table :test #'equal))
        (types nil)
        (type-names (make-hash-table :test #'equal))
        (saw-func nil)
        (saw-global nil)
        (saw-table nil)
        (saw-memory nil)
        (starts 0))
    (labels ((type-sig (ref)
               (cond
                 ((eq (wat-kind ref) :var)
                  (let ((index (gethash (wat-text ref) type-names)))
                    (unless index
                      (wasm-fail 'wasm-malformed
                                 (format nil "unknown type ~A" (wat-text ref))))
                    (nth index types)))
                 ((member (wat-kind ref) '(:nat :int))
                  (let ((index (wat-integer (wat-text ref))))
                    (unless (and (>= index 0) (< index (length types)))
                      (wasm-fail 'wasm-malformed
                                 (format nil "unknown type ~A" (wat-text ref))))
                    (nth index types)))
                 (t (wasm-fail 'wasm-malformed "unexpected token"))))
             (note-inline (explicit inline-params inline-results saw-inline)
               (when (and explicit saw-inline)
                 (unless (and (equal inline-params (car explicit))
                              (equal inline-results (cdr explicit)))
                   (wasm-fail 'wasm-malformed
                              "inline function type does not match explicit type"))))
             (header (children &key allow-named-param allow-local allow-export)
               (let ((phase :head)
                     (explicit nil)
                     (inline-params nil)
                     (inline-results nil)
                     (saw-inline nil)
                     (body nil)
                     (name nil))
                 (dolist (child children)
                   (cond
                     ((and (eq phase :head) (eq (wat-kind child) :var) (null name))
                      (setf name (wat-text child)))
                     ((and (eq phase :head) allow-export
                           (consp child) (listp (cdr child))
                           (wat-kw-p (car child) "export"))
                      nil)
                     ((and (member phase '(:head))
                           (consp child) (listp (cdr child))
                           (wat-kw-p (car child) "type"))
                      (setf explicit (type-sig (second child))))
                     ((and (member phase '(:head :param))
                           (consp child) (listp (cdr child))
                           (wat-kw-p (car child) "param"))
                      (setf phase :param saw-inline t)
                      (dolist (item (rest child))
                        (cond
                          ((and allow-named-param (eq (wat-kind item) :var))
                           (wat-bind *wat-locals* "local" (wat-text item)))
                          ((wat-valtype-p item)
                           (push (wat-text item) inline-params))
                          (t (wasm-fail 'wasm-malformed "unexpected token")))))
                     ((and (member phase '(:head :param :result))
                           (consp child) (listp (cdr child))
                           (wat-kw-p (car child) "result"))
                      (setf phase :result saw-inline t)
                      (dolist (item (rest child))
                        (if (wat-valtype-p item)
                            (push (wat-text item) inline-results)
                            (wasm-fail 'wasm-malformed "unexpected token"))))
                     ((and allow-local (member phase '(:head :param :result :local))
                           (consp child) (listp (cdr child))
                           (wat-kw-p (car child) "local"))
                      (setf phase :local)
                      (dolist (item (rest child))
                        (cond
                          ((eq (wat-kind item) :var)
                           (wat-bind *wat-locals* "local" (wat-text item)))
                          ((wat-valtype-p item) nil)
                          (t (wasm-fail 'wasm-malformed "unexpected token")))))
                     (t
                      (when (and (consp child) (listp (cdr child))
                                 (member (wat-text (car child))
                                         '("param" "result" "type" "local")
                                         :test #'string=))
                        (wasm-fail 'wasm-malformed "unexpected token"))
                      (setf phase :body)
                      (push child body))))
                 (note-inline explicit (nreverse inline-params)
                              (nreverse inline-results) saw-inline)
                 (values name (nreverse body))))
             (label-ok (name stack)
               (or (null name) (member name stack :test #'equal)))
             (end-label (forms open)
               "Consume an optional end label. A label on an unlabeled block mismatches."
               (if (eq (wat-kind (car forms)) :var)
                   (let ((name (wat-text (car forms))))
                     (unless (equal name open)
                       (wasm-fail 'wasm-malformed "mismatching label"))
                     (cdr forms))
                   forms))
             (check-step (forms stack)
               (let ((form (car forms)))
                 (cond
                   ((null form) nil)
                   ((and (consp form) (listp (cdr form)))
                    (check-folded form stack)
                    (cdr forms))
                   ((eq (wat-kind form) :align)
                    (wat-check-align (wat-text form))
                    (cdr forms))
                   ((eq (wat-kind form) :offset)
                    (wat-check-offset (wat-text form))
                    (cdr forms))
                   ((and (eq (wat-kind form) :kw)
                         (member (wat-text form) '("block" "loop") :test #'string=))
                    (let* ((rest (cdr forms))
                           (open (when (eq (wat-kind (car rest)) :var)
                                   (prog1 (wat-text (car rest)) (setf rest (cdr rest)))))
                           (next (cons open stack)))
                      (loop while rest do
                        (when (and (eq (wat-kind (car rest)) :kw)
                                   (string= (wat-text (car rest)) "end"))
                          (return (end-label (cdr rest) open)))
                        (setf rest (check-step rest next)))))
                   ((and (eq (wat-kind form) :kw) (string= (wat-text form) "if"))
                    (let* ((rest (cdr forms))
                           (open (when (eq (wat-kind (car rest)) :var)
                                   (prog1 (wat-text (car rest)) (setf rest (cdr rest)))))
                           (next (cons open stack)))
                      (loop while rest do
                        (cond
                          ((and (eq (wat-kind (car rest)) :kw)
                                (string= (wat-text (car rest)) "else"))
                           (setf rest (end-label (cdr rest) open)))
                          ((and (eq (wat-kind (car rest)) :kw)
                                (string= (wat-text (car rest)) "end"))
                           (return (end-label (cdr rest) open)))
                          (t (setf rest (check-step rest next)))))))
                   ((and (eq (wat-kind form) :kw) (search ".const" (wat-text form)))
                    (wat-check-const (wat-text form) (second forms))
                    (cddr forms))
                   ((and (eq (wat-kind form) :kw)
                         (member (wat-text form) '("br" "br_if") :test #'string=))
                    (let ((rest (cdr forms)))
                      (when (eq (wat-kind (car rest)) :var)
                        (unless (label-ok (wat-text (car rest)) stack)
                          (wasm-fail 'wasm-malformed
                                     (format nil "unknown label ~A" (wat-text (car rest)))))
                        (setf rest (cdr rest)))
                      rest))
                   ((and (eq (wat-kind form) :kw) (string= (wat-text form) "br_table"))
                    (let ((rest (cdr forms)))
                      (loop while (eq (wat-kind (car rest)) :var) do
                        (unless (label-ok (wat-text (car rest)) stack)
                          (wasm-fail 'wasm-malformed
                                     (format nil "unknown label ~A" (wat-text (car rest)))))
                        (setf rest (cdr rest)))
                      rest))
                   (t (cdr forms)))))
             (check-seq (forms stack)
               (loop while forms do
                 (setf forms (check-step forms stack))))
             (check-folded (form stack)
               (unless (and (consp form) (listp (cdr form)))
                 (return-from check-folded nil))
               (let ((op (wat-text (car form))))
                 (cond
                   ((member op '("block" "loop") :test #'string=)
                    (multiple-value-bind (name body) (header (rest form))
                      (check-seq body (cons name stack))))
                   ((string= op "if")
                    (multiple-value-bind (name body) (header (rest form))
                      (dolist (item body)
                        (unless (and (consp item) (listp (cdr item))
                                     (member (wat-text (car item)) '("then" "else")
                                             :test #'string=))
                          (wasm-fail 'wasm-malformed "unexpected token"))
                        (check-seq (rest item) (cons name stack)))))
                   ((string= op "call_indirect")
                    (multiple-value-bind (name body) (header (rest form))
                      (declare (ignore name))
                      (check-seq body stack)))
                   ((and op (search ".const" op))
                    (wat-check-const op (second form))
                    (check-seq (cddr form) stack))
                   (t
                    (dolist (item (rest form))
                      (cond
                        ((and (eq (wat-kind item) :align))
                         (wat-check-align (wat-text item)))
                        ((and (eq (wat-kind item) :offset))
                         (wat-check-offset (wat-text item)))
                        ((and (member op '("br" "br_if" "br_table") :test #'string=)
                              (eq (wat-kind item) :var)
                              (not (label-ok (wat-text item) stack)))
                         (wasm-fail 'wasm-malformed
                                    (format nil "unknown label ~A" (wat-text item))))
                        (t (check-step (list item) stack))))))))
             (limits (children)
               (dolist (child children)
                 (when (member (wat-kind child) '(:nat :int))
                   (unless (wat-i32-p (wat-integer (wat-text child)))
                     (wasm-fail 'wasm-malformed "i32 constant out of range")))))
             (import-desc (children)
               (find-if (lambda (child)
                          (and (consp child) (listp (cdr child))
                               (member (wat-text (car child))
                                       '("func" "global" "table" "memory")
                                       :test #'string=)))
                        children))
             (field (form)
               (unless (and (consp form) (listp (cdr form)))
                 (return-from field nil))
               (let ((op (wat-text (car form))))
                 (cond
                   ((string= op "type")
                    (let ((name (wat-text (find-if (lambda (c) (eq (wat-kind c) :var))
                                                   (rest form))))
                          (sig (wat-type-parts
                                (find-if (lambda (c)
                                           (and (consp c) (listp (cdr c))
                                                (wat-kw-p (car c) "func")))
                                         (rest form)))))
                      (wat-bind type-names "type" name)
                      (when name (setf (gethash name type-names) (length types)))
                      (setf types (append types (list (or sig (cons nil nil)))))))
                   ((string= op "import")
                    (when saw-func
                      (wasm-fail 'wasm-malformed "import after function definition"))
                    (when saw-global
                      (wasm-fail 'wasm-malformed "import after global definition"))
                    (when saw-table
                      (wasm-fail 'wasm-malformed "import after table definition"))
                    (when saw-memory
                      (wasm-fail 'wasm-malformed "import after memory definition"))
                    (let ((desc (import-desc (rest form))))
                      (when desc
                        (let ((table (cdr (assoc (wat-text (car desc))
                                                 `(("func" . ,funcs)
                                                   ("global" . ,globals)
                                                   ("table" . ,tables)
                                                   ("memory" . ,memories))
                                                 :test #'string=)))
                              (name (wat-text
                                     (find-if (lambda (child)
                                                (eq (wat-kind child) :var))
                                              (rest desc)))))
                          (wat-bind table (wat-text (car desc)) name)))))
                   ((string= op "func")
                    (setf saw-func t)
                    (let ((*wat-locals* (make-hash-table :test #'equal)))
                      (multiple-value-bind (name body)
                          (header (rest form) :allow-named-param t :allow-local t
                                              :allow-export t)
                        (wat-bind funcs "func" name)
                        (check-seq body nil))))
                   ((string= op "global")
                    (setf saw-global t)
                    (wat-bind globals "global"
                              (wat-text (find-if (lambda (c) (eq (wat-kind c) :var))
                                                 (rest form))))
                    (check-seq (rest form) nil))
                   ((string= op "table")
                    (setf saw-table t)
                    (wat-bind tables "table"
                              (wat-text (find-if (lambda (c) (eq (wat-kind c) :var))
                                                 (rest form))))
                    (limits (rest form)))
                   ((string= op "memory")
                    (setf saw-memory t)
                    (wat-bind memories "memory"
                              (wat-text (find-if (lambda (c) (eq (wat-kind c) :var))
                                                 (rest form))))
                    (limits (rest form)))
                   ((string= op "start")
                    (incf starts)
                    (when (> starts 1)
                      (wasm-fail 'wasm-malformed "multiple start sections")))
                   (t
                    (check-seq (rest form) nil))))))
      (dolist (form fields)
        (field form)))))

(defun parse-module-text (text)
  "Reject a WebAssembly text module the way the spec interpreter does.
Quote malformed tests use this. Binary modules stay on parse-module.
The messages are the ones in interpreter/text/lexer.mll and parser.mly
at WebAssembly spec tag wg-2.0."
  (let* ((tokens (wat-lex text))
         (forms (wat-forms tokens))
         (fields (if (and forms (consp (car forms)) (listp (cdar forms))
                          (wat-kw-p (caar forms) "module"))
                     (rest (car forms))
                     forms)))
    (wat-check-module-fields fields))
  nil)
