;;; tinyscript lexer in GNU Guile
;;; Tokenizes Tinyscript source code into a list of tokens

(define-module (tinyscript lexer)
  #:use-module (srfi srfi-1)
  #:export (lex lex-string lex-file keyword?))

(define keywords
  '(let fun if else for while return true false null in
    import export class new this and or not))

(define (keyword? str)
  "Check if a string is a Tinyscript keyword"
  (member (string->symbol str) keywords))

(define (make-token type value line col)
  (list (cons 'type type) (cons 'value value) (cons 'line line) (cons 'col col)))

(define (advance port)
  (read-char port))

(define (peek port)
  (peek-char port))

(define (lex-port port)
  "Read all tokens from a port"
  (let loop ((tokens '()) (line 1) (col 1))
    (let ((ch (read-char port)))
      (cond
       ((eof-object? ch)
        (reverse (cons (make-token 'eof #f line col) tokens)))

       ((char=? ch #\newline)
        (loop tokens (1+ line) 1))

       ((or (char=? ch #\space) (char=? ch #\tab) (char=? ch #\return))
        (loop tokens line (1+ col)))

       ;; Single-line comments //
       ((and (char=? ch #\/) (eq? (peek-char port) #\/))
        (let skip ()
          (let ((c (read-char port)))
            (unless (or (eof-object? c) (char=? c #\newline))
              (skip))))
        (loop tokens (1+ line) 1))

       ;; Multi-line comments /* */
       ((and (char=? ch #\/) (eq? (peek-char port) #\*))
        (read-char port) ;; skip *
        (let skip ((l line) (c (1+ col)))
          (let ((c1 (read-char port)))
            (cond
             ((eof-object? c1) (loop tokens l c))
             ((and (char=? c1 #\*) (eq? (peek-char port) #\/))
              (read-char port)
              (loop tokens l (1+ c)))
             (else
              (if (char=? c1 #\newline)
                  (skip (1+ l) 1)
                  (skip l (1+ c))))))))

       ;; Numbers
       ((char-set-contains? char-set:digit ch)
        (let ((start-col col))
          (let gather ((num (list ch)) (saw-dot #f))
            (let ((next (peek-char port)))
              (cond
               ((and (char? next) (char-set-contains? char-set:digit next))
                (read-char port)
                (gather (cons next num) saw-dot))
               ((and (char? next) (char=? next #\.) (not saw-dot))
                ;; Check if next-next char is another dot (.. operator)
                (begin
                  (read-char port) ;; consume the dot
                  (let ((after-dot (peek-char port)))
                    (if (and (char? after-dot) (char=? after-dot #\.))
                        ;; This is .. operator, put back the dot and stop
                        (let* ((str (list->string (reverse num)))
                               (val (string->number str)))
                          (unread-char #\. port)
                          (loop (cons (make-token 'number val line start-col) tokens)
                                line (+ start-col (string-length str))))
                        ;; This is a decimal point in a number
                        (gather (cons #\. num) #t)))))
               (else
                (let* ((str (list->string (reverse num)))
                       (val (string->number str)))
                  (loop (cons (make-token 'number val line start-col) tokens)
                        line (+ start-col (string-length str))))))))))

       ;; Strings
       ((or (char=? ch #\") (char=? ch #\'))
        (let* ((delim ch)
               (start-col col)
               (chars (read-string-chars port delim)))
          (loop (cons (make-token 'string (list->string (reverse chars)) line start-col) tokens)
                line (+ start-col (length chars) 2))))

       ;; Identifiers and keywords
       ((char-set-contains? char-set:letter ch)
        (let ((start-col col))
          (let gather ((chars (list ch)))
            (let ((next (peek-char port)))
              (if (and (char? next)
                       (or (char-set-contains? char-set:letter next)
                           (char-set-contains? char-set:digit next)
                           (char=? next #\_)
                           (char=? next #\$)))
                  (begin
                    (read-char port)
                    (gather (cons next chars)))
                  (let* ((id (list->string (reverse chars)))
                         (type (if (keyword? id) 'keyword 'identifier)))
                    (loop (cons (make-token type id line start-col) tokens)
                          line (+ start-col (string-length id)))))))))

       ;; Multi-char operators
       ((or (char=? ch #\=) (char=? ch #\!) (char=? ch #\<)
            (char=? ch #\>) (char=? ch #\&) (char=? ch #\|)
            (char=? ch #\.) (char=? ch #\-))
        (let ((next (peek-char port)))
          (if (and (char? next)
                   (member (string ch next)
                           '("==" "!=" "<=" ">=" "&&" "||" ".." "->")
                           string=?))
              (begin
                (read-char port)
                (loop (cons (make-token 'op (string ch next) line col) tokens)
                      line (1+ col)))
              (loop (cons (make-token 'op (string ch) line col) tokens)
                    line (1+ col)))))

       ;; Single-char operators and punctuation
       ((char-set-contains? (string->char-set "+-*/%=<>!&|.,;:(){}[]@#") ch)
        (loop (cons (make-token 'op (string ch) line col) tokens)
              line (1+ col)))

       ;; Skip unknown
       (else
        (loop tokens line (1+ col)))))))

(define (read-string-chars port delim)
  "Read characters until delimiter, handling escapes. Returns reversed list."
  (let loop ((chars '()))
    (let ((next (read-char port)))
      (cond
       ((eof-object? next)
        (error "Unterminated string"))
       ((char=? next delim)
        chars)
       ((char=? next #\\)
        (let ((esc (read-char port)))
          (let ((ch (case esc
                      ((#\n) #\newline)
                      ((#\t) #\tab)
                      ((#\r) #\return)
                      ((#\") #\")
                      ((#\') #\')
                      ((#\\) #\\)
                      (else esc))))
            (loop (cons ch chars)))))
       (else
        (loop (cons next chars)))))))

(define (lex-string str)
  (lex-port (open-input-string str)))

(define (lex-file filename)
  (call-with-input-file filename lex-port))
