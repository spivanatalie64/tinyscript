# Tinyscript

**A libre JavaScript alternative for Firefox — written in GNU Guile Scheme with a JavaScript re-implementation for browser extension use.**

Tinyscript is a small, libre scripting language designed as a drop-in replacement for JavaScript in Firefox. It reuses JavaScript-like syntax while providing a clean, minimal implementation under the permissive MPL-2.0 license. The core interpreter is written in GNU Guile Scheme, and a JavaScript runtime mirror is provided for Firefox extension integration.

## Quick Start

### Hello World

```tinyscript
print("Hello from Tinyscript!")
```

Save as `hello.ts` and run:

```bash
guile -L src -e main -s src/tinyscript.scm examples/hello.ts
```

Or via piped stdin:

```bash
echo 'print("Hello from Tinyscript!")' | guile -L src -e main -s src/tinyscript.scm -
```

### Full Example

```tinyscript
// Variables
let x = 42
let name = "Tinyscript"

// Conditionals
if x > 10 {
  print("x is big:", x)
} else {
  print("x is small")
}

// While loop
let i = 0
while i < 5 {
  print("Loop:", i)
  i = i + 1
}

// Functions
fun add(a, b) {
  return a + b
}
print("10 + 20 =", add(10, 20))

// Arrays
let arr = [1, 2, 3, 4, 5]
print("Array length:", len(arr))
print("First element:", arr[0])

// Objects
let obj = { name: "tinyscript", version: 0.1 }
print("Object name:", obj["name"])

// Range-based for-in
for i in 0..3 {
  print("Range:", i)
}
```

## Language Features

- **Types**: number, string, boolean, null, array, object, function
- **Variables**: `let` keyword with lexical scoping
- **Control flow**: `if`/`else`, `while`, `for` (C-style and `for...in`)
- **Functions**: `fun` keyword, closures, `return`
- **Arrays**: literal syntax `[1, 2, 3]`, bracket indexing, `len()` built-in
- **Objects**: literal syntax `{ key: val }`, bracket indexing, member access
- **Range operator**: `start..end` generates inclusive numeric arrays
- **Built-ins**: `print()`, `typeof()`, `len()`, `str()`, `num()`
- **Methods**: `string.length`, `string.upper`, `string.lower`, `string.slice`, `array.push`, `array.length`, `array.get`
- **Imports/Exports**: `import`, `export`
- **Comments**: `//` line comments and `/* */` block comments

## Running the CLI Interpreter

### Prerequisites

- [GNU Guile](https://www.gnu.org/software/guile/) 3.0 or later

### Usage

```bash
# Run a .ts file
guile -L src -e main -s src/tinyscript.scm examples/hello.ts

# Run from stdin (use - as filename)
echo 'print("Hello!")' | guile -L src -e main -s src/tinyscript.scm -

# Use the gmake build system
./gmake.scm hello
```

The `-L src` flag adds the `src/` directory to Guile's load path, `-e main` specifies the entry point, and `-s` tells Guile to run the script.

## Running in Node.js

A JavaScript re-implementation of the interpreter lives in `extension/runtime/tinyscript.js`. It mirrors the Guile Scheme implementation exactly.

### Usage

```javascript
import { tinyscriptRun, tinyscriptCompile } from './extension/runtime/tinyscript.js';

// Run source code directly
tinyscriptRun(`
  let x = 42
  print("x =", x)
`);

// Or compile then run
const ast = tinyscriptCompile(`print("hello")`);
```

### CommonJS

```javascript
const { tinyscriptRun } = require('./extension/runtime/tinyscript.cjs');
tinyscriptRun(`print("hello from Node.js!")`);
```

### npm scripts

```bash
npm run example    # runs examples/hello.ts
npm test           # runs test suite
npm run build      # builds the project
```

## Firefox Extension

Tinyscript ships as a Firefox WebExtension that replaces JavaScript with Tinyscript.

### What it does

- Blocks `.js` file requests via `webRequest`
- Executes `<script type="text/tinyscript">` blocks
- Intercepts event handler attributes (`onclick`, etc.) and runs them as Tinyscript
- Offers a toolbar button to toggle full JavaScript blocking

### Loading the extension

1. Open `about:debugging#/runtime/this-firefox`
2. Click **Load Temporary Add-on**
3. Select `src/extension/manifest.json`

### Usage in HTML

```html
<script type="text/tinyscript">
  print("Hello from Tinyscript!")
  fun add(a, b) { return a + b }
  print("5 + 7 =", add(5, 7))
</script>
```

The extension will process these script blocks automatically while blocking standard JavaScript.

### Building the extension

```bash
# Custom Guile-based build system
./gmake.scm bundle
# Creates: build/tinyscript-extension.zip

# Or manually
cd src/extension && zip -r ../../build/tinyscript-extension.zip .
```

## Build System

Tinyscript uses two build systems:

### Custom Guile-based build (gmake.scm + gmakefile)

A Make replacement written entirely in Guile Scheme. It reads a `gmakefile` in the current directory.

```bash
./gmake.scm          # Build default target (all)
./gmake.scm hello    # Run hello.ts example
./gmake.scm bundle   # Create extension zip
./gmake.scm install  # Install interpreter to build/
./gmake.scm check    # Run all tests
./gmake.scm clean    # Remove build artifacts
```

### npm scripts

```bash
npm run example
npm test
npm run build
```

## Language Reference

### Syntax

Tinyscript syntax closely mirrors JavaScript but with some simplifications:

- Semicolons are optional (newlines act as delimiters)
- Blocks are delimited by `{` `}`
- Comments: `//` to end of line, `/* ... */` for multi-line
- Identifiers: alphanumeric + `_` and `$`, starting with a letter

### Types

| Type      | Examples                     |
|-----------|------------------------------|
| number    | `42`, `3.14`                 |
| string    | `"hello"`, `'world'`         |
| boolean   | `true`, `false`              |
| null      | `null`                       |
| array     | `[1, 2, 3]`                  |
| object    | `{ key: "val" }`             |
| function  | `fun (a, b) { return a+b }`  |

### Variables

```tinyscript
let x = 10          // with initializer
let y               // uninitialized (null)
x = 20              // reassignment
```

Variables are lexically scoped with block-level scoping.

### Operators (precedence from low to high)

| Precedence | Operators                    | Associativity |
|------------|------------------------------|---------------|
| 1          | `=`                          | right         |
| 2          | `..`                         | left          |
| 3          | `\|\|`                       | left          |
| 4          | `&&`                         | left          |
| 5          | `==` `!=`                    | left          |
| 6          | `<` `>` `<=` `>=`            | left          |
| 7          | `+` `-`                      | left          |
| 8          | `*` `/` `%`                  | left          |
| 9          | unary `-` `!` `not`          | right         |

**Notes:**
- `+` on strings performs concatenation
- `..` is the range operator (inclusive): `0..3` → `[0, 1, 2, 3]`
- `not` is an alias for `!`
- Equality (`==`/`!=`) compares values, not types
- Logical `&&` and `||` return booleans

### Control Flow

```tinyscript
// if/else
if condition { } else { }

// while
while condition { }

// for (C-style)
for let i = 0; i < 5; i = i + 1 { }

// for-in (range or array)
for i in 0..4 { }
for item in myArray { }
```

### Functions

```tinyscript
// Named function
fun add(a, b) {
  return a + b
}

// Anonymous function (as expression)
let fn = fun (x) { return x * 2 }

// Call
let result = add(10, 20)
```

Functions are closures with lexical scoping. Recursion is supported.

### Arrays

```tinyscript
let arr = [1, 2, 3]
arr[0]           // → 1
len(arr)         // → 3
arr.length()     // → 3
arr.push(4)      // → [1, 2, 3, 4]
arr.get(0)       // → 1
```

### Objects

```tinyscript
let obj = { name: "tinyscript", version: 0.1 }
obj["name"]      // → "tinyscript" (bracket access)
obj.name         // → "tinyscript" (member access)
```

### Built-in Functions

| Function   | Description                            |
|------------|----------------------------------------|
| `print`    | Output values to console               |
| `typeof`   | Return type name as string             |
| `len`      | Return length of string or array       |
| `str`      | Convert value to string                |
| `num`      | Convert value to number                |

### Built-in Methods

**String methods:**

| Method        | Description                |
|---------------|----------------------------|
| `.length()`   | String length              |
| `.upper()`    | Uppercase conversion       |
| `.lower()`    | Lowercase conversion       |
| `.slice(s,e)` | Substring extraction       |

**Array methods:**

| Method        | Description                |
|---------------|----------------------------|
| `.length()`   | Array length               |
| `.push(val)`  | Append element             |
| `.get(idx)`   | Get element by index       |

### Keywords

```
let fun if else for while return true false null in
import export class new this and or not
```

## Architecture

```
src/
├── tinyscript.scm          # Entry point / CLI
├── tinyscript/
│   ├── lexer.scm           # Tokenizer
│   ├── parser.scm          # Recursive descent parser → AST
│   ├── eval.scm            # Tree-walking interpreter
│   ├── env.scm             # Lexical environment (scope chains)
│   └── runtime.scm         # Built-in functions and native methods
extension/
├── manifest.json           # Firefox WebExtension manifest
├── background.js           # Background script (JS blocking)
├── content.js              # Content script (script interception)
├── icons/                  # Extension icons
└── runtime/
    ├── tinyscript.js       # JS re-implementation (ES module)
    └── tinyscript.cjs      # JS re-implementation (CommonJS)
gmake.scm                   # Guile-based build system
gmakefile                   # Build targets
```

## License

Mozilla Public License Version 2.0. See [LICENSE](LICENSE).

## Author

**Natalie Spiva** — AcreetionOS

- GitHub: [@spivanatalie64](https://github.com/spivanatalie64)
- Repository: [github.com/spivanatalie64/tinyscript](https://github.com/spivanatalie64/tinyscript)
