/* Tinyscript Runtime — Libre JavaScript Replacement
   Implements the Tinyscript interpreter for Firefox
   (mirrors the GNU Guile implementation) */

"use strict";

class TinyLexer {
  static keywords = new Set([
    "let","fun","if","else","for","while","return",
    "true","false","null","in","import","export",
    "class","new","this","and","or","not"
  ]);

  static lex(source) {
    const tokens = [];
    let i = 0, line = 1, col = 1;

    const push = (type, value) => tokens.push({ type, value, line, col });

    while (i < source.length) {
      const ch = source[i];

      if (ch === '\n') { line++; col = 1; i++; continue; }
      if (ch === ' ' || ch === '\t' || ch === '\r') { col++; i++; continue; }

      if (ch === '/' && source[i + 1] === '/') {
        while (i < source.length && source[i] !== '\n') i++;
        continue;
      }

      if (ch === '/' && source[i + 1] === '*') {
        i += 2;
        while (i < source.length && !(source[i] === '*' && source[i + 1] === '/')) {
          if (source[i] === '\n') { line++; col = 1; }
          else col++;
          i++;
        }
        i += 2; col += 2;
        continue;
      }

      if (/[0-9]/.test(ch)) {
        const startCol = col;
        let num = '';
        let sawDot = false;
        while (i < source.length) {
          if (/[0-9]/.test(source[i])) {
            num += source[i]; i++; col++;
          } else if (source[i] === '.' && !sawDot && source[i + 1] !== '.') {
            sawDot = true;
            num += source[i]; i++; col++;
          } else break;
        }
        push('number', parseFloat(num));
        continue;
      }

      if (ch === '"' || ch === "'") {
        const quote = ch;
        let str = '';
        i++; col++;
        while (i < source.length && source[i] !== quote) {
          if (source[i] === '\\') {
            i++; col++;
            const esc = { n: '\n', t: '\t', r: '\r', '"': '"', "'": "'", '\\': '\\' };
            str += esc[source[i]] || source[i];
          } else {
            str += source[i];
          }
          i++; col++;
        }
        i++; col++;
        push('string', str);
        continue;
      }

      if (/[a-zA-Z_$]/.test(ch)) {
        let id = '';
        while (i < source.length && /[a-zA-Z0-9_$]/.test(source[i])) {
          id += source[i]; i++; col++;
        }
        const type = TinyLexer.keywords.has(id) ? 'keyword' : 'identifier';
        push(type, id);
        continue;
      }

      const twoChar = source.slice(i, i + 2);
      const opMap = { '==': 1, '!=': 1, '<=': 1, '>=': 1, '&&': 1, '||': 1, '..': 1, '->': 1 };
      if (twoChar in opMap) {
        push('op', twoChar);
        i += 2; col += 2;
        continue;
      }

      if ('+-*/%=<>!&|.,;:(){}[]@#'.includes(ch)) {
        push('op', ch);
        i++; col++;
        continue;
      }

      i++; col++;
    }

    push('eof', null);
    return tokens;
  }
}

class TinyParser {
  constructor(tokens) {
    this.tokens = tokens;
    this.pos = 0;
  }

  current() { return this.tokens[this.pos]; }
  advance() { const t = this.current(); this.pos++; return t; }
  peek(n = 0) { return this.tokens[this.pos + n]; }

  expect(type, val) {
    const tok = this.current();
    if (tok.type !== type) throw new Error(`Expected ${type} at ${tok.line}:${tok.col}`);
    if (val !== undefined && tok.value !== val) throw new Error(`Expected '${val}' at ${tok.line}:${tok.col}`);
    return this.advance().value;
  }

  match(type, val) {
    const tok = this.current();
    return tok.type === type && (val === undefined || tok.value === val);
  }

  tryConsume(type, val) {
    if (this.match(type, val)) { this.advance(); return true; }
    return false;
  }

  // AST constructors
  prog(stmts)        { return ['program', ...stmts]; }
  letStmt(name, init)  { return ['let', name, init]; }
  assignStmt(name, val){ return ['assign', name, val]; }
  ifStmt(cond, th, el) { return el ? ['if', cond, th, el] : ['if', cond, th]; }
  whileStmt(cond, b)   { return ['while', cond, b]; }
  forStmt(init, cond, step, b) { return ['for', init, cond, step, b]; }
  funStmt(name, par, b){ return ['fun', name, par, b]; }
  returnStmt(v)       { return ['return', v]; }
  binary(op, l, r)   { return ['binary', op, l, r]; }
  unary(op, v)        { return ['unary', op, v]; }
  literal(v)          { return ['literal', v]; }
  varRef(name)        { return ['var', name]; }
  block(s)            { return ['block', ...s]; }
  array(e)            { return ['array', ...e]; }
  obj(p)              { return ['object', ...p]; }
  index(obj, key)     { return ['index', obj, key]; }
  member(obj, key)    { return ['member', obj, key]; }
  callExpr(fn, args)  { return ['call', fn, args]; }
  importStmt(p)       { return ['import', p]; }
  exportStmt(v)       { return ['export', v]; }

  parse() {
    const stmts = [];
    while (!this.match('eof')) stmts.push(this.statement());
    return this.prog(stmts);
  }

  statement() {
    if (this.match('keyword', 'let'))    return this.parseLet();
    if (this.match('keyword', 'fun'))    return this.parseFun();
    if (this.match('keyword', 'if'))     return this.parseIf();
    if (this.match('keyword', 'while'))  return this.parseWhile();
    if (this.match('keyword', 'for'))    return this.parseFor();
    if (this.match('keyword', 'return')) return this.parseReturn();
    if (this.match('keyword', 'import')) return this.parseImport();
    if (this.match('keyword', 'export')) return this.parseExport();
    if (this.match('op', '{'))           return this.parseBlock();
    return this.exprStmt();
  }

  parseBlock() {
    this.expect('op', '{');
    const stmts = [];
    while (!this.tryConsume('op', '}')) stmts.push(this.statement());
    return this.block(stmts);
  }

  parseLet() {
    this.expect('keyword', 'let');
    const name = this.expect('identifier');
    let init = null;
    if (this.tryConsume('op', '=')) init = this.expression();
    return this.letStmt(name, init);
  }

  parseFun() {
    this.expect('keyword', 'fun');
    const name = this.expect('identifier');
    this.expect('op', '(');
    const params = this.parseParamList();
    this.expect('op', ')');
    const body = this.parseBlock();
    return this.funStmt(name, params, body);
  }

  parseParamList() {
    const params = [];
    if (this.match('identifier')) {
      params.push(this.expect('identifier'));
      while (this.tryConsume('op', ',')) params.push(this.expect('identifier'));
    }
    return params;
  }

  parseIf() {
    this.expect('keyword', 'if');
    const cond = this.expression();
    const then = this.statement();
    let els = null;
    if (this.tryConsume('keyword', 'else')) els = this.statement();
    return this.ifStmt(cond, then, els);
  }

  parseWhile() {
    this.expect('keyword', 'while');
    const cond = this.expression();
    const body = this.statement();
    return this.whileStmt(cond, body);
  }

  parseFor() {
    this.expect('keyword', 'for');
    if (this.tryConsume('keyword', 'let')) {
      const v = this.expect('identifier');
      if (this.tryConsume('keyword', 'in')) {
        const iter = this.expression();
        const body = this.statement();
        return ['for-in', v, iter, body];
      }
      this.expect('op', '=');
      const init = this.expression();
      this.expect('op', ';');
      const cond = this.expression();
      this.expect('op', ';');
      const step = this.expression();
      const body = this.statement();
      return this.forStmt(this.letStmt(v, init), cond, step, body);
    }
    const v = this.expect('identifier');
    this.expect('keyword', 'in');
    const iter = this.expression();
    const body = this.statement();
    return ['for-in', v, iter, body];
  }

  parseReturn() {
    this.expect('keyword', 'return');
    const val = this.expression();
    return this.returnStmt(val);
  }

  parseImport() {
    this.expect('keyword', 'import');
    const path = this.expression();
    return this.importStmt(path);
  }

  parseExport() {
    this.expect('keyword', 'export');
    const val = this.expression();
    return this.exportStmt(val);
  }

  exprStmt() { return this.expression(); }

  expression() { return this.assign(); }

  range() {
    let left = this.or();
    if (this.match('op', '..')) {
      this.advance();
      left = this.binary('..', left, this.assign());
    }
    return left;
  }

  assign() {
    let left = this.range();
    if (this.match('op', '=')) {
      this.advance();
      const val = this.assign();
      if (left[0] === 'var') return this.assignStmt(left[1], val);
      return this.assignStmt(left, val);
    }
    return left;
  }

  or() {
    let left = this.and();
    while (this.match('op', '||')) { this.advance(); left = this.binary('||', left, this.and()); }
    return left;
  }

  and() {
    let left = this.equality();
    while (this.match('op', '&&')) { this.advance(); left = this.binary('&&', left, this.equality()); }
    return left;
  }

  equality() {
    let left = this.comparison();
    while (this.match('op') && ['==', '!='].includes(this.current().value)) {
      const op = this.advance().value;
      left = this.binary(op, left, this.comparison());
    }
    return left;
  }

  comparison() {
    let left = this.term();
    while (this.match('op') && ['<', '>', '<=', '>='].includes(this.current().value)) {
      const op = this.advance().value;
      left = this.binary(op, left, this.term());
    }
    return left;
  }

  term() {
    let left = this.factor();
    while (this.match('op') && ['+', '-'].includes(this.current().value)) {
      const op = this.advance().value;
      left = this.binary(op, left, this.factor());
    }
    return left;
  }

  factor() {
    let left = this.unary();
    while (this.match('op') && ['*', '/', '%'].includes(this.current().value)) {
      const op = this.advance().value;
      left = this.binary(op, left, this.unary());
    }
    return left;
  }

  unary() {
    if (this.match('op') && ['-', '!', 'not'].includes(this.current().value)) {
      const op = this.advance().value;
      return this.unary(op, this.unary());
    }
    return this.call();
  }

  call() {
    let left = this.primary();
    while (true) {
      if (this.match('op', '(')) {
        this.advance();
        const args = this.argList();
        this.expect('op', ')');
        left = this.callExpr(left, args);
      } else if (this.match('op', '[')) {
        this.advance();
        const idx = this.expression();
        this.expect('op', ']');
        left = this.index(left, idx);
      } else if (this.match('op', '.')) {
        this.advance();
        const name = this.expect('identifier');
        left = this.member(left, name);
      } else break;
    }
    return left;
  }

  argList() {
    const args = [];
    if (!this.match('op', ')')) {
      args.push(this.expression());
      while (this.tryConsume('op', ',')) args.push(this.expression());
    }
    return args;
  }

  primary() {
    if (this.match('number')) return this.literal(this.advance().value);
    if (this.match('string')) return this.literal(this.advance().value);
    if (this.match('keyword', 'true'))  { this.advance(); return this.literal(true); }
    if (this.match('keyword', 'false')) { this.advance(); return this.literal(false); }
    if (this.match('keyword', 'null'))  { this.advance(); return this.literal(null); }
    if (this.match('identifier')) return this.varRef(this.advance().value);

    if (this.match('op', '(')) {
      this.advance();
      const expr = this.expression();
      this.expect('op', ')');
      return expr;
    }

    if (this.match('op', '[')) {
      this.advance();
      const elems = [];
      if (!this.match('op', ']')) {
        elems.push(this.expression());
        while (this.tryConsume('op', ',')) elems.push(this.expression());
      }
      this.expect('op', ']');
      return this.array(elems);
    }

    if (this.match('op', '{')) {
      this.advance();
      const pairs = [];
      if (!this.match('op', '}')) {
        const key = this.match('string') ? this.advance().value : this.expect('identifier');
        this.expect('op', ':');
        pairs.push([key, this.expression()]);
        while (this.tryConsume('op', ',')) {
          const k = this.match('string') ? this.advance().value : this.expect('identifier');
          this.expect('op', ':');
          pairs.push([k, this.expression()]);
        }
      }
      this.expect('op', '}');
      return this.obj(pairs);
    }

    if (this.match('keyword', 'fun')) {
      this.advance();
      this.expect('op', '(');
      const params = this.parseParamList();
      this.expect('op', ')');
      const body = this.parseBlock();
      return this.funStmt(null, params, body);
    }

    throw new Error(`Unexpected token '${this.current().value}' at ${this.current().line}:${this.current().col}`);
  }
}

/* --- Evaluator --- */

function tsNumber(n)  { return ['number', n]; }
function tsString(s)  { return ['string', s]; }
function tsBool(b)    { return ['boolean', b]; }
function tsNull()     { return ['null', null]; }
function tsArray(a)   { return ['array', ...a]; }
function tsObj(o)     { return ['object', o]; }
function tsFun(f)     { return ['function', f]; }
function tsNative(f)  { return ['native', f]; }

function tsType(v)  { return v[0]; }
function tsVal(v)   { return v[1]; }

function isTruthy(v) {
  const t = tsType(v);
  if (t === 'boolean') return tsVal(v);
  if (t === 'null') return false;
  if (t === 'number') return tsVal(v) !== 0;
  if (t === 'string') return tsVal(v) !== '';
  return true;
}

class TinyEnv {
  constructor(parent = null) {
    this.parent = parent;
    this.bindings = {};
  }

  define(name, val) { this.bindings[name] = val; }
  set(name, val) {
    if (name in this.bindings) { this.bindings[name] = val; return; }
    if (this.parent) { this.parent.set(name, val); return; }
    throw new Error(`Undefined variable: ${name}`);
  }
  lookup(name) {
    if (name in this.bindings) return this.bindings[name];
    if (this.parent) return this.parent.lookup(name);
    throw new Error(`Undefined variable: ${name}`);
  }
}

class TinyEvaluator {
  constructor() {
    this.env = new TinyEnv();
    this.installRuntime();
  }

  installRuntime() {
    this.env.define('print', tsNative((...args) => {
      const str = args.map(a => {
        const v = tsVal(a);
        return v === null ? 'null' : String(v);
      }).join(' ');
      console.log(str);
      // Also inject into DOM if available
      if (typeof document !== 'undefined') {
        const el = document.createElement('div');
        el.style.display = 'none';
        document.body.appendChild(el);
      }
      return tsNull();
    }));
    this.env.define('typeof', tsNative((v) => tsString(tsType(v))));
    this.env.define('len', tsNative((v) => {
      if (tsType(v) === 'string') return tsNumber(tsVal(v).length);
      if (tsType(v) === 'array') return tsNumber(tsVal(v).length);
      throw new Error('len() not supported');
    }));
    this.env.define('str', tsNative((v) => tsString(String(tsVal(v)))));
    this.env.define('num', tsNative((v) => tsNumber(Number(tsVal(v)))));
  }

  evaluate(ast) {
    return this.evalProg(ast);
  }

  evalProg(ast) {
    let result = tsNull();
    for (let i = 1; i < ast.length; i++) {
      result = this.evalStmt(ast[i]);
    }
    return result;
  }

  evalStmt(stmt) {
    if (!Array.isArray(stmt)) return this.evalExpr(stmt);
    const [type, ...rest] = stmt;
    switch (type) {
      case 'let': {
        const [name, init] = rest;
        this.env.define(name, init ? this.evalExpr(init) : tsNull());
        return tsNull();
      }
      case 'assign': {
        const [target, val] = rest;
        const value = this.evalExpr(val);
        if (typeof target === 'string') {
          this.env.set(target, value);
        } else if (target[0] === 'index') {
          const obj = this.evalExpr(target[1]);
          const idx = this.evalExpr(target[2]);
          tsVal(obj)[tsVal(idx)] = value;
        }
        return tsNull();
      }
      case 'if': {
        const [cond, thenB, elseB] = rest;
        if (isTruthy(this.evalExpr(cond))) return this.evalStmt(thenB);
        if (elseB) return this.evalStmt(elseB);
        return tsNull();
      }
      case 'while': {
        const [cond, body] = rest;
        let result = tsNull();
        while (isTruthy(this.evalExpr(cond))) result = this.evalStmt(body);
        return result;
      }
      case 'for': {
        const [init, cond, step, body] = rest;
        this.evalStmt(init);
        let result = tsNull();
        while (isTruthy(this.evalExpr(cond))) {
          result = this.evalStmt(body);
          this.evalExpr(step);
        }
        return result;
      }
      case 'for-in': {
        const [varName, iterable, body] = rest;
        const iter = this.evalExpr(iterable);
        const arr = tsVal(iter);
        let result = tsNull();
        for (let i = 0; i < arr.length; i++) {
          this.env.define(varName, arr[i]);
          result = this.evalStmt(body);
        }
        return result;
      }
      case 'return': {
        throw { type: 'return', value: rest[0] ? this.evalExpr(rest[0]) : tsNull() };
      }
      case 'block': {
        const subEnv = new TinyEnv(this.env);
        const oldEnv = this.env;
        this.env = subEnv;
        try {
          let result = tsNull();
          for (const s of rest) result = this.evalStmt(s);
          return result;
        } finally {
          this.env = oldEnv;
        }
      }
      default: return this.evalExpr(stmt);
    }
  }

  evalExpr(expr) {
    if (!Array.isArray(expr)) throw new Error(`Invalid expr: ${expr}`);
    const [type, ...rest] = expr;
    switch (type) {
      case 'literal': {
        const v = rest[0];
        if (v === null) return tsNull();
        if (typeof v === 'number') return tsNumber(v);
        if (typeof v === 'string') return tsString(v);
        if (typeof v === 'boolean') return tsBool(v);
        return tsString(String(v));
      }
      case 'var': return this.env.lookup(rest[0]);
      case 'binary': {
        const [op, l, r] = rest;
        const lv = this.evalExpr(l), rv = this.evalExpr(r);
        return this.evalBinary(op, lv, rv);
      }
      case 'unary': {
        const [op, v] = rest;
        const val = this.evalExpr(v);
        if (op === '-') return tsNumber(-tsVal(val));
        if (op === '!' || op === 'not') return tsBool(!isTruthy(val));
        throw new Error(`Unknown unary: ${op}`);
      }
      case 'call': {
        const [callee, args] = rest;
        const fn = this.evalExpr(callee);
        const argVals = args.map(a => this.evalExpr(a));
        return this.evalCall(fn, argVals);
      }
      case 'fun': {
        const [name, params, body] = rest;
        const closure = (callArgs) => {
          const subEnv = new TinyEnv(this.env);
          params.forEach((p, i) => subEnv.define(p, callArgs[i]));
          const oldEnv = this.env;
          this.env = subEnv;
          try {
            return this.evalStmt(body);
          } catch (e) {
            if (e && e.type === 'return') return e.value;
            throw e;
          } finally {
            this.env = oldEnv;
          }
        };
        const fnVal = tsFun(closure);
        if (name) this.env.define(name, fnVal);
        return fnVal;
      }
      case 'array': return tsArray(rest.map(e => this.evalExpr(e)));
      case 'object': return tsObj(rest.map(([k, v]) => [k, this.evalExpr(v)]));
      case 'index': {
        const [obj, idx] = rest;
        const o = this.evalExpr(obj);
        const i = this.evalExpr(idx);
        const t = tsType(o);
        if (t === 'array') return tsVal(o)[tsVal(i)];
        if (t === 'object') {
          const key = tsType(i) === 'string' ? tsVal(i) : tsVal(i);
          const found = tsVal(o).find(([k]) => k === key);
          return found ? found[1] : tsNull();
        }
        throw new Error('Cannot index');
      }
      case 'member': {
        const [obj, key] = rest;
        const o = this.evalExpr(obj);
        if (tsType(o) === 'object') {
          const found = tsVal(o).find(([k]) => k === key);
          if (found) return found[1];
        }
        // Check native methods
        const method = TinyEvaluator.nativeMethods[tsType(o)]?.[key];
        if (method) return tsNative((...args) => method(o, ...args));
        return tsNull();
      }
      default: throw new Error(`Unknown expr: ${type}`);
    }
  }

  evalBinary(op, l, r) {
    const numOp = (fn) => {
      if (tsType(l) !== 'number' || tsType(r) !== 'number')
        throw new Error('Numeric operation on non-numbers');
      return tsNumber(fn(tsVal(l), tsVal(r)));
    };
    switch (op) {
      case '+': {
        if (tsType(l) === 'string' && tsType(r) === 'string')
          return tsString(tsVal(l) + tsVal(r));
        return numOp((a, b) => a + b);
      }
      case '-': return numOp((a, b) => a - b);
      case '*': return numOp((a, b) => a * b);
      case '/': return numOp((a, b) => a / b);
      case '%': return numOp((a, b) => a % b);
      case '==': return tsBool(tsVal(l) === tsVal(r));
      case '!=': return tsBool(tsVal(l) !== tsVal(r));
      case '<':  return tsBool(tsType(l) === 'number' && tsType(r) === 'number' && tsVal(l) < tsVal(r));
      case '>':  return tsBool(tsType(l) === 'number' && tsType(r) === 'number' && tsVal(l) > tsVal(r));
      case '<=': return tsBool(tsType(l) === 'number' && tsType(r) === 'number' && tsVal(l) <= tsVal(r));
      case '>=': return tsBool(tsType(l) === 'number' && tsType(r) === 'number' && tsVal(l) >= tsVal(r));
      case '&&': return tsBool(isTruthy(l) && isTruthy(r));
      case '||': return tsBool(isTruthy(l) || isTruthy(r));
      case '..': {
        const arr = [];
        for (let i = tsVal(l); i <= tsVal(r); i++) arr.push(tsNumber(i));
        return tsArray(arr);
      }
      default: throw new Error(`Unknown op: ${op}`);
    }
  }

  evalCall(fn, args) {
    const t = tsType(fn);
    if (t === 'function') return tsVal(fn)(args);
    if (t === 'native') return tsVal(fn)(...args);
    throw new Error('Cannot call non-function');
  }

  static nativeMethods = {
    string: {
      length(s) { return tsNumber(tsVal(s).length); },
      upper(s) { return tsString(tsVal(s).toUpperCase()); },
      lower(s) { return tsString(tsVal(s).toLowerCase()); },
      slice(s, start, end) {
        const str = tsVal(s);
        const st = tsVal(start);
        return tsString(end ? str.slice(st, tsVal(end)) : str.slice(st));
      }
    },
    array: {
      length(a) { return tsNumber(tsVal(a).length); },
      push(a, val) { tsVal(a).push(val); return tsVal(a).length; },
      get(a, idx) { return tsVal(a)[tsVal(idx)]; }
    }
  };
}

/* --- Main compile function --- */

function tinyscriptCompile(source) {
  const tokens = TinyLexer.lex(source);
  const parser = new TinyParser(tokens);
  const ast = parser.parse();
  return ast;
}

function tinyscriptRun(source, env) {
  const ast = tinyscriptCompile(source);
  const evaluator = new TinyEvaluator();
  if (env) evaluator.env = env;
  return evaluator.evaluate(ast);
}

/* Export for module systems */
if (typeof module !== 'undefined' && module.exports) {
  module.exports = { TinyLexer, TinyParser, TinyEvaluator, tinyscriptCompile, tinyscriptRun };
}
