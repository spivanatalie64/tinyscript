;;; tinyscript runtime in GNU Guile
;;; Built-in functions and native method tables for Tinyscript

(define-module (tinyscript runtime)
  #:use-module (ice-9 match)
  #:use-module (ice-9 hash-table)
  #:use-module (tinyscript env)
  #:export (install-runtime
            lookup-native apply-native
            make-ts-value ts-type ts-val
            ts-number ts-string ts-boolean ts-null))

(define (make-ts-value type val)
  (vector type val))

(define (ts-type v) (vector-ref v 0))
(define (ts-val v) (vector-ref v 1))

(define (ts-number n)  (make-ts-value 'number n))
(define (ts-string s)  (make-ts-value 'string s))
(define (ts-boolean b) (make-ts-value 'boolean b))
(define ts-null (make-ts-value 'null #f))

;; Native method table for object.method() calls
(define *native-methods* (make-hash-table))

(define (register-native type name proc)
  (let ((by-type (hash-ref *native-methods* type)))
    (if by-type
        (hash-set! by-type name proc)
        (let ((new-table (make-hash-table)))
          (hash-set! new-table name proc)
          (hash-set! *native-methods* type new-table)))))

(define (lookup-native name obj)
  (let* ((type (ts-type obj))
         (by-type (hash-ref *native-methods* type #f)))
    (if by-type
        (hash-ref by-type name #f)
        #f)))

(define (apply-native name obj args)
  (let ((proc (lookup-native name obj)))
    (if proc
        (apply proc obj args)
        (error "No such method: " name))))

;; --- Built-in functions ---

(define (ts-print . args)
  (for-each (lambda (a)
              (display (ts-val a))
              (display " "))
            args)
  (newline)
  ts-null)

(define (ts-typeof val)
  (ts-string (symbol->string (ts-type val))))

(define (ts-str val)
  (ts-string (format #f "~a" (ts-val val))))

(define (ts-num val)
  (ts-number (string->number (ts-val val))))

(define (ts-len val)
  (let ((t (ts-type val)))
    (cond
     ((eq? t 'string) (ts-number (string-length (ts-val val))))
     ((eq? t 'array) (ts-number (vector-length (ts-val val))))
     (else (error "len() not supported for type")))))

;; --- Array methods ---

(define (ts-array-push arr val)
  (let ((v (ts-val arr)))
    (let ((len (vector-length v))
          (newv (make-vector (1+ (vector-length v)))))
      (do ((i 0 (1+ i))) ((= i len))
        (vector-set! newv i (vector-ref v i)))
      (vector-set! newv len val)
      (make-ts-value 'array newv))))

(define (ts-array-get arr idx)
  (vector-ref (ts-val arr) (ts-val idx)))

;; --- Install runtime into an environment ---

(define (install-runtime env)
  (define (def name proc)
    (env-define! env name (make-ts-value 'native proc)))
  (def "print"  ts-print)
  (def "typeof" ts-typeof)
  (def "str"    ts-str)
  (def "num"    ts-num)
  (def "len"    ts-len))

;; Register native methods for types

(register-native 'string 'length
  (lambda (self)
    (ts-number (string-length (ts-val self)))))

(register-native 'string 'upper
  (lambda (self)
    (ts-string (string-upcase (ts-val self)))))

(register-native 'string 'lower
  (lambda (self)
    (ts-string (string-downcase (ts-val self)))))

(register-native 'string 'slice
  (lambda (self start . end)
    (let ((s (ts-val self))
          (st (ts-val start)))
      (if (pair? end)
          (ts-string (substring s st (ts-val (car end))))
          (ts-string (substring s st))))))

(register-native 'array 'push
  (lambda (self val)
    (ts-array-push self val)))

(register-native 'array 'length
  (lambda (self)
    (ts-number (vector-length (ts-val self)))))

(register-native 'array 'get
  (lambda (self idx)
    (ts-array-get self idx)))
