;;; tinyscript parser in GNU Guile
;;; Parses tokens into an AST (s-expressions)

(define-module (tinyscript parser)
  #:use-module (tinyscript lexer)
  #:export (parse parse-from-string parse-file))

;; Parser state: a list of tokens with current position
(define (make-parser tokens)
  (vector tokens 0))

(define (parser-pos p)
  (vector-ref p 1))

(define (parser-set-pos! p n)
  (vector-set! p 1 n))

(define (parser-tokens p)
  (vector-ref p 0))

(define (current p)
  (let ((tokens (parser-tokens p))
        (pos (parser-pos p)))
    (list-ref tokens pos)))

(define (advance! p)
  (parser-set-pos! p (1+ (parser-pos p))))

(define (peek p n)
  (let ((tokens (parser-tokens p))
        (pos (parser-pos p)))
    (list-ref tokens (+ pos n))))

(define (token-value tok) (assq-ref tok 'value))
(define (token-type tok) (assq-ref tok 'type))
(define (token-line tok) (assq-ref tok 'line))
(define (token-col tok) (assq-ref tok 'col))

;; Error reporting
(define (parse-error p msg)
  (let ((tok (current p)))
    (error (string-append "Parse error at line "
                          (number->string (token-line tok))
                          ", col "
                          (number->string (token-col tok))
                          ": " msg))))

;; Consume a token of expected type, optionally with expected value
(define (expect p type . val)
  (let ((tok (current p)))
    (if (eq? (token-type tok) type)
        (if (and (pair? val) (not (equal? (token-value tok) (car val))))
            (parse-error p (format #f "Expected '~a' but got '~a'" (car val) (token-value tok)))
            (begin (advance! p) (token-value tok)))
        (parse-error p (format #f "Expected ~a but got ~a" type (token-type tok))))))

;; Check if current token matches
(define (match-token p type . val)
  (let ((tok (current p)))
    (and (eq? (token-type tok) type)
         (or (null? val) (equal? (token-value tok) (car val))))))

;; Try to match-token, consume if matched
(define (try-consume p type . val)
  (if (apply match-token p type val)
      (begin (advance! p) #t)
      #f))

;; --- AST node constructors ---
(define (ast-prog stmts)     `(program ,@stmts))
(define (ast-let name init)  `(let ,name ,init))
(define (ast-assign name val) `(assign ,name ,val))
(define (ast-if cond thn els) `(if ,cond ,thn ,@(if els (list els) '())))
(define (ast-while cond body) `(while ,cond ,body))
(define (ast-for init cond step body) `(for ,init ,cond ,step ,body))
(define (ast-fun name params body) `(fun ,name ,params ,body))
(define (ast-call callee args) `(call ,callee ,args))
(define (ast-return val)     `(return ,val))
(define (ast-binary op l r)  `(binary ,op ,l ,r))
(define (ast-unary op v)     `(unary ,op ,v))
(define (ast-literal v)      `(literal ,v))
(define (ast-var v)          `(var ,v))
(define (ast-block stmts)    `(block ,@stmts))
(define (ast-array elems)    `(array ,@elems))
(define (ast-obj pairs)      `(object ,@pairs))
(define (ast-index obj key)  `(index ,obj ,key))
(define (ast-member obj key) `(member ,obj ,key))
(define (ast-import path)    `(import ,path))
(define (ast-export val)     `(export ,val))

;; --- Recursive descent parser ---

(define (parse-program p)
  (let loop ((stmts '()))
    (if (match-token p 'eof)
        (ast-prog (reverse stmts))
        (loop (cons (parse-stmt p) stmts)))))

(define (parse-stmt p)
  (cond
   ((match-token p 'keyword "let")    (parse-let p))
   ((match-token p 'keyword "fun")    (parse-fun p))
   ((match-token p 'keyword "if")     (parse-if p))
   ((match-token p 'keyword "while")  (parse-while p))
   ((match-token p 'keyword "for")    (parse-for p))
   ((match-token p 'keyword "return") (parse-return p))
   ((match-token p 'keyword "import") (parse-import p))
   ((match-token p 'keyword "export") (parse-export p))
    ((match-token p 'op "{")           (parse-block p))
    (else (parse-expr-stmt p))))

(define (parse-block p)
  (expect p 'op "{")
  (let loop ((stmts '()))
    (if (try-consume p 'op "}")
        (ast-block (reverse stmts))
        (loop (cons (parse-stmt p) stmts)))))

(define (parse-let p)
  (expect p 'keyword "let")
  (let ((name (expect p 'identifier)))
    (if (try-consume p 'op "=")
        (ast-let name (parse-expr p))
        (ast-let name #f))))

(define (parse-fun p)
  (expect p 'keyword "fun")
  (let ((name (expect p 'identifier)))
    (expect p 'op "(")
    (let ((params (parse-param-list p)))
      (expect p 'op ")")
      (let ((body (parse-block p)))
        (ast-fun name params body)))))

(define (parse-param-list p)
  (let loop ((params '()))
    (cond
     ((match-token p 'op ")") (reverse params))
     ((match-token p 'identifier)
      (let ((name (expect p 'identifier)))
        (if (try-consume p 'op ",")
            (loop (cons name params))
            (reverse (cons name params)))))
     (else (reverse params)))))

(define (parse-if p)
  (expect p 'keyword "if")
  (let ((cond (parse-expr p)))
    (let ((then (parse-stmt p)))
      (if (try-consume p 'keyword "else")
          (let ((els (parse-stmt p)))
            (ast-if cond then els))
          (ast-if cond then #f)))))

(define (parse-while p)
  (expect p 'keyword "while")
  (let ((cond (parse-expr p)))
    (let ((body (parse-stmt p)))
      (ast-while cond body))))

(define (parse-for p)
  (expect p 'keyword "for")
  (if (try-consume p 'keyword "let")
      ;; for let i = 0; ... or for let i in ...
      (let ((init-var (expect p 'identifier)))
        (if (try-consume p 'keyword "in")
            (let ((iterable (parse-expr p)))
              (let ((body (parse-stmt p)))
                (list 'for-in init-var iterable body)))
            (begin
              (expect p 'op "=")
              (let ((init-val (parse-expr p)))
                (expect p 'op ";")
                (let ((cond (parse-expr p)))
                  (expect p 'op ";")
                  (let ((step (parse-expr p)))
                    (let ((body (parse-stmt p)))
                      (ast-for (ast-let init-var init-val) cond step body))))))))
      ;; for i in iterable { }
      (let ((init-var (expect p 'identifier)))
        (expect p 'keyword "in")
        (let ((iterable (parse-expr p)))
          (let ((body (parse-stmt p)))
            (list 'for-in init-var iterable body))))))

(define (parse-return p)
  (expect p 'keyword "return")
  (let ((val (parse-expr p)))
    (ast-return val)))

(define (parse-import p)
  (expect p 'keyword "import")
  (let ((path (parse-expr p)))
    (ast-import path)))

(define (parse-export p)
  (expect p 'keyword "export")
  (let ((val (parse-expr p)))
    (ast-export val)))

;; Expression statements
(define (parse-expr-stmt p)
  (let ((expr (parse-expr p)))
    expr))

;; --- Expression parsing (precedence climbing) ---

(define (parse-expr p)
  (parse-assign p))

(define (parse-range p)
  (let ((left (parse-or p)))
    (if (and (match-token p 'op "..") (not (match-token p 'eof)))
        (let ((op (expect p 'op)))
          (ast-binary ".." left (parse-assign p)))
        left)))

(define (parse-assign p)
  (let ((left (parse-range p)))
    (if (match-token p 'op "=")
        (begin
          (advance! p)
          (cond
           ((and (pair? left) (eq? (car left) 'var))
            (ast-assign (cadr left) (parse-assign p)))
           ((and (pair? left) (eq? (car left) 'index))
            (ast-assign left (parse-assign p)))
           ((and (pair? left) (eq? (car left) 'member))
            (ast-assign left (parse-assign p)))
           (else (parse-error p "Invalid assignment target"))))
        left)))

(define (parse-or p)
  (let ((left (parse-and p)))
    (if (and (match-token p 'op "||") (not (match-token p 'eof)))
        (let ((op (expect p 'op)))
          (ast-binary "||" left (parse-and p)))
        left)))

(define (parse-and p)
  (let ((left (parse-equality p)))
    (if (and (match-token p 'op "&&") (not (match-token p 'eof)))
        (let ((op (expect p 'op)))
          (ast-binary "&&" left (parse-equality p)))
        left)))

(define (parse-equality p)
  (let ((left (parse-comparison p)))
    (if (and (match-token p 'op) (member (token-value (current p)) '("==" "!=")))
        (let ((op (expect p 'op)))
          (ast-binary op left (parse-comparison p)))
        left)))

(define (parse-comparison p)
  (let ((left (parse-term p)))
    (if (and (match-token p 'op) (member (token-value (current p)) '("<" ">" "<=" ">=")))
        (let ((op (expect p 'op)))
          (ast-binary op left (parse-term p)))
        left)))

(define (parse-term p)
  (let ((left (parse-factor p)))
    (if (and (match-token p 'op) (member (token-value (current p)) '("+" "-")))
        (let ((op (expect p 'op)))
          (ast-binary op left (parse-factor p)))
        left)))

(define (parse-factor p)
  (let ((left (parse-unary p)))
    (if (and (match-token p 'op) (member (token-value (current p)) '("*" "/" "%")))
        (let ((op (expect p 'op)))
          (ast-binary op left (parse-unary p)))
        left)))

(define (parse-unary p)
  (if (and (match-token p 'op) (member (token-value (current p)) '("-" "!" "not")))
      (let ((op (expect p 'op)))
        (ast-unary op (parse-unary p)))
      (parse-call p)))

(define (parse-call p)
  (let ((left (parse-primary p)))
    (let loop ((left left))
      (cond
       ;; Function call: foo(args)
       ((match-token p 'op "(")
        (advance! p)
        (let ((args (parse-arg-list p)))
          (expect p 'op ")")
          (loop (ast-call left args))))
       ;; Array access: foo[idx]
       ((match-token p 'op "[")
        (advance! p)
        (let ((idx (parse-expr p)))
          (expect p 'op "]")
          (loop (ast-index left idx))))
       ;; Member access: foo.bar
       ((match-token p 'op ".")
        (advance! p)
        (let ((name (expect p 'identifier)))
          (loop (ast-member left name))))
       (else left)))))

(define (parse-arg-list p)
  (let loop ((args '()))
    (cond
     ((match-token p 'op ")") (reverse args))
     ((match-token p 'eof) (reverse args))
     (else
      (let ((expr (parse-expr p)))
        (if (try-consume p 'op ",")
            (loop (cons expr args))
            (reverse (cons expr args))))))))

(define (parse-primary p)
  (cond
   ;; Number literal
   ((match-token p 'number)
    (let ((val (expect p 'number)))
      (ast-literal val)))
   ;; String literal
   ((match-token p 'string)
    (let ((val (expect p 'string)))
      (ast-literal val)))
   ;; Boolean/null keywords
   ((match-token p 'keyword "true")  (advance! p) (ast-literal #t))
   ((match-token p 'keyword "false") (advance! p) (ast-literal #f))
   ((match-token p 'keyword "null")  (advance! p) (ast-literal 'null))
   ;; Identifier
   ((match-token p 'identifier)
    (let ((name (expect p 'identifier)))
      (ast-var name)))
   ;; Parenthesized expression
   ((match-token p 'op "(")
    (advance! p)
    (let ((expr (parse-expr p)))
      (expect p 'op ")")
      expr))
   ;; Array literal
   ((match-token p 'op "[")
    (advance! p)
    (if (try-consume p 'op "]")
        (ast-array '())
        (let ((elems (parse-array-elems p)))
          (expect p 'op "]")
          (ast-array (reverse elems)))))
   ;; Object literal
   ((match-token p 'op "{")
    (advance! p)
    (if (try-consume p 'op "}")
        (ast-obj '())
        (let ((pairs (parse-obj-pairs p)))
          (expect p 'op "}")
          (ast-obj (reverse pairs)))))
   ;; Keyword expression
   ((match-token p 'keyword "fun")
    (expect p 'keyword "fun")
    (let ((name #f) (params #f))
      (set! params (begin (expect p 'op "(")
                          (let ((p2 (parse-param-list p)))
                            (expect p 'op ")")
                            p2)))
      (let ((body (parse-block p)))
        (ast-fun name params body))))
   (else
    (parse-error p (format #f "Unexpected token: ~a" (token-value (current p)))))))

(define (parse-array-elems p)
  (let loop ((elems '()))
    (if (match-token p 'op "]")
        elems
        (let ((expr (parse-expr p)))
          (if (try-consume p 'op ",")
              (loop (cons expr elems))
              (cons expr elems))))))

(define (parse-obj-pairs p)
  (let loop ((pairs '()))
    (if (match-token p 'op "}")
        pairs
        (let ((key (if (match-token p 'string)
                       (expect p 'string)
                       (expect p 'identifier))))
          (expect p 'op ":")
          (let ((val (parse-expr p)))
            (if (try-consume p 'op ",")
                (loop (cons (list key val) pairs))
                (cons (list key val) pairs)))))))

;; Public API
(define (parse tokens)
  (let ((p (make-parser tokens)))
    (parse-program p)))

(define (parse-from-string src)
  (parse (lex-string src)))

(define (parse-file filename)
  (parse (lex-file filename)))
