;;; tinyscript environment module
;;; Environment management for the Tinyscript interpreter

(define-module (tinyscript env)
  #:export (make-env env-parent env-bindings
            env-define! env-set! env-lookup
            env-parent-set!))

(define (make-env parent)
  (let ((bindings-cell (list '())))
    (vector parent bindings-cell)))

(define (env-parent env) (vector-ref env 0))
(define (env-bindings-cell env) (vector-ref env 1))
(define (env-bindings env) (car (env-bindings-cell env)))

(define (env-parent-set! env parent)
  (vector-set! env 0 parent))

(define (env-define! env name val)
  (let ((cell (env-bindings-cell env)))
    (set-car! cell (cons (cons name val) (car cell)))))

(define (env-set! env name val)
  (let ((bindings (env-bindings env)))
    (let ((existing (assoc name bindings)))
      (if existing
          (set-cdr! existing val)
          (let ((parent (env-parent env)))
            (if parent
                (env-set! parent name val)
                (error "Variable not defined: " name)))))))

(define (env-lookup env name)
  (let ((bindings (env-bindings env)))
    (let ((found (assoc name bindings)))
      (if found
          (cdr found)
          (let ((parent (env-parent env)))
            (if parent
                (env-lookup parent name)
                (error "Undefined variable: " name)))))))
