/**
 * Ask TypeScript what a source file actually depends on, instead of guessing
 * from its spelling.
 *
 * This file exists because two earlier answers to the same question were
 * wrong, each in a way this repository has now written down twice:
 *
 * 1. A comment stripper plus regular expressions REJECTED
 *    `const note = 'do not import "../functions-equipment-identity/src/x"';`
 *    while PASSING `require("../" + "functions-equipment-identity/src/x")`.
 *    Prose read as code, real coupling missed.
 * 2. Its replacement moved to the AST but stayed syntactic: it accepted any
 *    property named `.join`/`.resolve`/`.require`, and treated EVERY call's
 *    constant-foldable arguments as filesystem paths. Measured on the
 *    submitted version -- `console.log("../functions-equipment-identity/…")`,
 *    `foo.join("..", "functions-equipment-identity", "x")`,
 *    `foo.resolve(…)` and `obj.require(…)` were all reported as identity
 *    dependencies. Data read as behaviour: the same defect again, one more
 *    layer down.
 *
 * So the proof is semantic at the SINK, not only at the syntax node. Module
 * specifiers come from the nodes that ARE specifiers. A filesystem path is
 * read only from a call that is actually a filesystem sink -- a method on a
 * binding this file imported from `fs`, or `path.join`/`path.resolve` on a
 * binding this file imported from `path`. An arbitrary object with a
 * `.join()` method is an arbitrary object.
 *
 * Usage (typescript's own module path is passed explicitly, so this does not
 * depend on where node happens to resolve packages from):
 *
 *   node ts_dependency_probe.cjs <typescript-module> specifiers <file...>
 *   node ts_dependency_probe.cjs <typescript-module> extends <tsconfig>
 *
 * Always prints one JSON object. Errors are reported in it, never swallowed:
 * the Python side treats an unparseable file or an unresolved `extends` as a
 * failure, because reporting isolation over a file nothing read would be the
 * broken-instrument result this project keeps recording.
 */
"use strict";

const path = require("path");
const fs = require("fs");

const [, , tsModulePath, mode, ...rest] = process.argv;

function fail(message) {
  process.stdout.write(JSON.stringify({ ok: false, error: message }));
  process.exit(0);
}

if (!tsModulePath || !mode) {
  fail("usage: ts_dependency_probe.cjs <typescript-module> <specifiers|extends> <arg...>");
}

let ts;
try {
  ts = require(tsModulePath);
} catch (err) {
  fail(`cannot load typescript from ${tsModulePath}: ${err.message}`);
}

const PATH_MODULES = new Set([
  "path",
  "node:path",
  "path/posix",
  "path/win32",
  "node:path/posix",
  "node:path/win32",
]);
const FS_MODULES = new Set([
  "fs",
  "node:fs",
  "fs/promises",
  "node:fs/promises",
]);
const PATH_FUNCTIONS = new Set(["join", "resolve"]);

/**
 * Which ARGUMENTS of an `fs` call are pathnames.
 *
 * Not "all of them". Measured on the previous version:
 * `fs.writeFileSync("output.txt", "../functions-equipment-identity/src/x")`
 * was reported as an identity dependency, but the second argument is file
 * CONTENT. Treating every constant argument of every `fs` method as a path
 * is data read as dependency -- this gate's own defect, yet again.
 */
const FS_PATH_ARGUMENTS = new Map([
  ["readFile", [0]], ["readFileSync", [0]],
  ["writeFile", [0]], ["writeFileSync", [0]],
  ["appendFile", [0]], ["appendFileSync", [0]],
  ["open", [0]], ["openSync", [0]],
  ["stat", [0]], ["statSync", [0]], ["lstat", [0]], ["lstatSync", [0]],
  ["access", [0]], ["accessSync", [0]],
  ["readdir", [0]], ["readdirSync", [0]],
  ["mkdir", [0]], ["mkdirSync", [0]],
  ["rm", [0]], ["rmSync", [0]], ["rmdir", [0]], ["rmdirSync", [0]],
  ["unlink", [0]], ["unlinkSync", [0]],
  ["createReadStream", [0]], ["createWriteStream", [0]],
  ["existsSync", [0]],
  ["realpath", [0]], ["realpathSync", [0]],
  ["opendir", [0]], ["opendirSync", [0]],
  ["watch", [0]], ["watchFile", [0]], ["unwatchFile", [0]],
  ["chmod", [0]], ["chmodSync", [0]], ["chown", [0]], ["chownSync", [0]],
  ["truncate", [0]], ["truncateSync", [0]],
  ["readlink", [0]], ["readlinkSync", [0]],
  ["copyFile", [0, 1]], ["copyFileSync", [0, 1]],
  ["cp", [0, 1]], ["cpSync", [0, 1]],
  ["rename", [0, 1]], ["renameSync", [0, 1]],
  ["link", [0, 1]], ["linkSync", [0, 1]],
  ["symlink", [0, 1]], ["symlinkSync", [0, 1]],
]);

//: An `fs` method this table does not list. Node's filesystem API takes the
//: pathname first almost without exception, so index 0 is the conservative
//: reading -- conservative in the direction of noticing a dependency, not in
//: the direction of calling arbitrary data a path.
const FS_UNTABULATED_PATH_ARGUMENTS = [0];

/**
 * Which flavour of node's path algebra a binding speaks.
 *
 * `path/win32` and `path/posix` are explicit. Plain `path` is whatever the
 * runtime is -- and this probe's runtime is not the analysed code's: it runs
 * on Windows while `functions` deploys to nodejs20 on Linux. So plain `path`
 * yields BOTH, and a value that lands inside the identity package under
 * EITHER algebra is a dependency on some platform the code really runs on.
 * That is the fail-closed direction; picking one flavour would silently pick
 * a platform.
 */
function pathFlavours(moduleName, prefix) {
  for (const segment of prefix) {
    if (segment !== "win32" && segment !== "posix") return null;
  }
  const explicit = prefix.find((segment) => segment === "win32" || segment === "posix");
  if (explicit) return [explicit];
  if (/(^|\/)win32$/.test(moduleName)) return ["win32"];
  if (/(^|\/)posix$/.test(moduleName)) return ["posix"];
  return ["win32", "posix"];
}

/**
 * Fold a constant `path.join` / `path.resolve` by ASKING NODE, not by
 * reimplementing it.
 *
 * The previous version hand-rolled the algebra and got Windows wrong in a way
 * that changed the target rather than the spelling. Measured, node against
 * that code:
 *
 *   path.win32.join("D:..", NAME, "package.json")
 *     node       -> "D:..\\<NAME>\\package.json"   (drive-RELATIVE, isAbsolute false)
 *     hand-rolled -> "D:/<NAME>/package.json"      (drive-absolute, a different place)
 *
 * A fully constant, correctly bound dependency read as clean, under a
 * docstring that claimed constant `path.join` as covered. The lesson this
 * gate keeps relearning, applied one level up: the tool is already loaded --
 * stop writing a second, worse copy of it and call the real one.
 */
function foldPathCall(fn, flavour, parts) {
  const mod = path[flavour];
  if (fn === "join") return mod.join(...parts);
  //: `resolve` scans right to left to the last absolute argument. When none
  //: is, node prepends the working directory -- not knowable for code that
  //: runs somewhere else -- so the normalised relative form is emitted and
  //: that limit is named in `verify_deployment_isolation.py`'s docstring.
  let start = 0;
  for (let index = parts.length - 1; index >= 0; index -= 1) {
    if (mod.isAbsolute(parts[index])) {
      start = index;
      break;
    }
  }
  const tail = parts.slice(start);
  if (tail.length === 0) return mod.join();
  return mod.isAbsolute(tail[0]) ? mod.resolve(...tail) : mod.join(...tail);
}

//: `fs` exports that are OBJECTS carrying the same path-taking API, so
//: `fs.promises.readFile(p)` and `import { promises as fsp }` reach a real
//: sink. Named rather than guessed: an unlisted object export is not a sink,
//: which is why `fs.constants` and `fs.Stats` are absent.
const FS_OBJECT_EXPORTS = new Set(["promises"]);

/**
 * `fs` functions that also carry a `.native` variant of themselves.
 *
 * Node really does expose `fs.realpath.native` and `fs.realpathSync.native`
 * as callable functions -- measured, not read off documentation -- and they
 * take the same pathname in the same position as their parents. The round-4
 * chain rule required every intermediate segment to be an OBJECT export, so
 * `realpath` was not one and the whole call was discarded as "not a sink":
 * a false negative introduced by the remediation itself, on an API this very
 * file's argument table already lists.
 *
 * This is deliberately a bounded list of two rather than a rule like "any
 * `.native` member", because the point of the chain model is that an
 * arbitrary `.foo.bar()` is an arbitrary object.
 */
const FS_NATIVE_VARIANTS = new Set(["realpath", "realpathSync"]);

/**
 * What node module, if any, an identifier is bound to AT THIS OCCURRENCE.
 *
 * This is the round-4 correction, and it is a deletion rather than an
 * addition. The previous version accumulated the NAMES bound anywhere in the
 * file into file-global sets, which is not what a binding is. Measured on
 * that version:
 *
 *   import * as fs from "fs";
 *   function inspect(fs: FakeFs) {
 *     return fs.readFileSync("../<NAME>/terms.json");   // REJECTED, wrongly
 *   }
 *
 * -- a parameter shadowing the import, whose method call was read as node's
 * `fs` because the string "fs" was in a set. And in the other direction:
 *
 *   import { promises as fsp } from "fs";
 *   fsp.readFile("../<NAME>/terms.json");               // CLEAN, wrongly
 *
 * -- a name genuinely bound from `fs`, missed because the collector had no
 * model of an object export. Neither belongs to the declared residue "an
 * alias this file does not bind from `fs`": both are bound from `fs`, and
 * the first is not bound from it at all.
 *
 * So the name lookup is gone and TypeScript's own checker answers instead.
 * It knows about parameters, block scope, nested binding patterns and every
 * other scoping rule this file would otherwise have had to reimplement --
 * the same reason `collectExtends` stopped resolving `extends` by hand.
 *
 * Returns `{ module, members }`: `members` is the property path from the
 * module to the bound name, empty for a namespace binding. `null` means the
 * identifier is not bound to any module here, whatever it is called.
 */
function makeBindingResolver(checker) {
  /**
   * Does this declaration create a value that EXISTS AT RUNTIME?
   *
   * Round 6, and the distinction is the whole finding: a declaration is not a
   * binding. `declare function require(name: string): any;` gives the checker
   * a `FunctionDeclaration` symbol and emits no JavaScript at all -- the call
   * that runs is still node's own `require`. Round 5 defined "unbound" as
   * "the checker returned no declarations", which made that ambient
   * declaration look like a runtime shadow. Measured on the round-5 code:
   *
   *   declare function require(name: string): any;
   *   const fs = require("fs");
   *   fs.readFileSync("../<NAME>/terms.json");        -> CLEAN, wrongly
   *   require("../<NAME>/src/index");                 -> CLEAN, wrongly
   *
   * A genuine dependency, through both channels, made invisible by the fix
   * for the opposite defect. The direction matters too: treating something as
   * NOT a shadow means treating the call as node's, which is the fail-closed
   * reading -- a wrong guess there costs a false alarm, the other way round
   * costs a miss.
   */
  const isRuntimeValueDeclaration = (declaration) => {
    if (declaration.getSourceFile().isDeclarationFile) return false;
    if (declaration.flags & ts.NodeFlags.Ambient) return false;
    if (ts.getCombinedModifierFlags(declaration) & ts.ModifierFlags.Ambient) return false;
    //: Types are not values, whatever they are named.
    if (ts.isInterfaceDeclaration(declaration)) return false;
    if (ts.isTypeAliasDeclaration(declaration)) return false;
    if (ts.isTypeParameterDeclaration(declaration)) return false;
    //: Round 7, and a deletion again. This read `declaration.isTypeOnly` on
    //: an `ImportSpecifier` or `ImportClause` -- which is the per-specifier
    //: form (`import { type Foo as require }`) and misses the whole-clause
    //: one, where the SPECIFIER's own flag is false and the CLAUSE's is true.
    //: Measured: `import type * as require from "./types"` resolved to a
    //: `NamespaceImport` this predicate called a runtime value, so a genuine
    //: `require("../<NAME>/src/index")` in the same file read clean, although
    //: `import type` is erased from the emitted JavaScript entirely.
    //:
    //: `ts.isTypeOnlyImportOrExportDeclaration` is TypeScript's own answer to
    //: exactly this question and covers the specifier, the clause and the
    //: namespace form together. Measured on all three before adopting it.
    //:
    //: Worth recording honestly: the two `ImportSpecifier` shapes GPT-PM
    //: predicted were ALREADY rejected correctly, for a reason this code did
    //: not choose -- the checker returns no declarations at all for a
    //: type-only alias used in a VALUE position, so `isUnbound` was true by
    //: default. Only the namespace form was a live miss. Relying on that
    //: accident rather than on the predicate would have been a claim wider
    //: than its check, which is the one thing this gate exists to stop.
    if (ts.isTypeOnlyImportOrExportDeclaration(declaration)) return false;
    return true;
  };

  //: An identifier with no RUNTIME declaration anywhere in this file's scope.
  //: `require` is this, unless the file declares its own -- which is exactly
  //: the case a bare-name test cannot tell apart.
  const isUnbound = (identifier) => {
    const symbol = checker.getSymbolAtLocation(identifier);
    if (!symbol || !symbol.declarations || symbol.declarations.length === 0) return true;
    return !symbol.declarations.some(isRuntimeValueDeclaration);
  };

  const moduleOfRequire = (initializer) => {
    if (!initializer || !ts.isCallExpression(initializer)) return null;
    if (!ts.isIdentifier(initializer.expression)) return null;
    if (initializer.expression.text !== "require") return null;
    //: Round 5. The direct-call path asked the checker whether `require` was
    //: node's; this one only checked the spelling. Measured on that version:
    //:
    //:   function require(n: string) { return { readFileSync: (p) => p }; }
    //:   const fs = require("fs");
    //:   fs.readFileSync("../<NAME>/terms.json");     // REJECTED, wrongly
    //:
    //: A locally declared function, read as node's module loader, binding a
    //: fake object to the real `fs`. The same defect the round-4 note said
    //: had been fixed -- fixed in one of the two places it lived.
    if (!isUnbound(initializer.expression)) return null;
    if (initializer.arguments.length !== 1) return null;
    const argument = initializer.arguments[0];
    return ts.isStringLiteral(argument) ? argument.text : null;
  };

  const describe = (declaration) => {
    if (ts.isNamespaceImport(declaration)) {
      const specifier = declaration.parent.parent.moduleSpecifier;
      if (!ts.isStringLiteral(specifier)) return null;
      return { module: specifier.text, members: [] };
    }
    if (ts.isImportSpecifier(declaration)) {
      const specifier = declaration.parent.parent.parent.moduleSpecifier;
      if (!ts.isStringLiteral(specifier)) return null;
      const imported = declaration.propertyName || declaration.name;
      return { module: specifier.text, members: [imported.text] };
    }
    if (ts.isImportClause(declaration) && declaration.parent.moduleSpecifier) {
      const specifier = declaration.parent.moduleSpecifier;
      if (!ts.isStringLiteral(specifier)) return null;
      //: A default import of a CommonJS module is the module object itself
      //: under `esModuleInterop`, which is how `functions` is compiled.
      return { module: specifier.text, members: [] };
    }
    if (
      ts.isImportEqualsDeclaration(declaration) &&
      declaration.moduleReference &&
      ts.isExternalModuleReference(declaration.moduleReference) &&
      ts.isStringLiteral(declaration.moduleReference.expression)
    ) {
      return { module: declaration.moduleReference.expression.text, members: [] };
    }
    if (ts.isVariableDeclaration(declaration)) {
      const moduleName = moduleOfRequire(declaration.initializer);
      return moduleName === null ? null : { module: moduleName, members: [] };
    }
    if (ts.isBindingElement(declaration)) {
      //: Walk out through however many binding patterns are nested --
      //: `const { promises: { readFile } } = require("fs")` is two deep --
      //: collecting the property path on the way to the declaration that
      //: holds the initializer.
      const members = [];
      let current = declaration;
      while (ts.isBindingElement(current)) {
        const property = current.propertyName || current.name;
        if (!ts.isIdentifier(property)) return null;
        members.unshift(property.text);
        const pattern = current.parent;
        if (!pattern || !ts.isObjectBindingPattern(pattern)) return null;
        current = pattern.parent;
      }
      if (!ts.isVariableDeclaration(current)) return null;
      const moduleName = moduleOfRequire(current.initializer);
      return moduleName === null ? null : { module: moduleName, members };
    }
    return null;
  };

  const resolve = (identifier) => {
    const symbol = checker.getSymbolAtLocation(identifier);
    if (!symbol || !symbol.declarations) return null;
    for (const declaration of symbol.declarations) {
      const described = describe(declaration);
      if (described) return described;
    }
    return null;
  };

  return { resolve, isUnbound };
}

//: The property path from a call's callee down to the called name, plus the
//: identifier it is rooted at. `fs.promises.readFile(x)` -> root `fs`,
//: chain `["promises", "readFile"]`; `readFileSync(x)` -> root, chain `[]`.
function calleeChain(callee) {
  const chain = [];
  let current = callee;
  while (ts.isPropertyAccessExpression(current)) {
    chain.unshift(current.name.text);
    current = current.expression;
  }
  return ts.isIdentifier(current) ? { root: current, chain } : null;
}

//: A fold produces CANDIDATE values, not one value: plain `path` is folded
//: under both algebras. The cap exists so a pathological nest of concatenated
//: joins cannot make this quadratic; it is far above anything real, and the
//: values are deduplicated first so the common case is one or two.
const MAX_FOLD_CANDIDATES = 32;

function crossProduct(left, right) {
  const values = new Set();
  for (const a of left) {
    for (const b of right) {
      values.add(a + b);
      if (values.size > MAX_FOLD_CANDIDATES) return null;
    }
  }
  return [...values];
}

function makeAnalyzer(checker) {
  const bindings = makeBindingResolver(checker);

  /**
   * `path.join(...)` / `path.resolve(...)` reached through a binding actually
   * imported from `path` at this point in the file -- never `anything.join`.
   * Returns the function AND the algebra flavours to fold it under.
   */
  const pathCallKind = (node) => {
    const callee = calleeChain(node.expression);
    if (callee === null) return null;
    const binding = bindings.resolve(callee.root);
    if (binding === null || !PATH_MODULES.has(binding.module)) return null;
    const full = [...binding.members, ...callee.chain];
    if (full.length === 0) return null;
    const fn = full[full.length - 1];
    if (!PATH_FUNCTIONS.has(fn)) return null;
    const flavours = pathFlavours(binding.module, full.slice(0, -1));
    return flavours === null ? null : { fn, flavours };
  };

  /**
   * The argument positions of this call that are PATHNAMES, or null when the
   * call is not a filesystem sink at all.
   *
   * The method is read from the binding plus the property path, so a named
   * import, an alias, a CJS destructuring, `fs.promises.readFile` and
   * `import { promises as fsp }` all arrive at the same answer, and a
   * shadowed local named `fs` arrives at none.
   */
  const fsSinkPathArguments = (node) => {
    const callee = calleeChain(node.expression);
    if (callee === null) return null;
    const binding = bindings.resolve(callee.root);
    if (binding === null || !FS_MODULES.has(binding.module)) return null;
    let full = [...binding.members, ...callee.chain];
    if (full.length === 0) return null;
    //: `fs.realpath.native(p)` is the same sink, in the same position, as
    //: `fs.realpath(p)`.
    if (
      full.length >= 2 &&
      full[full.length - 1] === "native" &&
      FS_NATIVE_VARIANTS.has(full[full.length - 2])
    ) {
      full = full.slice(0, -1);
    }
    const method = full[full.length - 1];
    for (const segment of full.slice(0, -1)) {
      if (!FS_OBJECT_EXPORTS.has(segment)) return null;
    }
    if (FS_OBJECT_EXPORTS.has(method)) return null;
    return FS_PATH_ARGUMENTS.get(method) || FS_UNTABULATED_PATH_ARGUMENTS;
  };

  /** Bare `require(...)` bound to nothing local, never `obj.require(...)`. */
  const isRequireCall = (node) =>
    ts.isIdentifier(node.expression) &&
    node.expression.text === "require" &&
    bindings.isUnbound(node.expression);

  //: Returns an array of candidate constant values, or null when the
  //: expression is not constant-foldable.
  const fold = (node) => {
    if (!node) return null;
    if (ts.isStringLiteral(node) || ts.isNoSubstitutionTemplateLiteral(node)) return [node.text];
    if (ts.isParenthesizedExpression(node)) return fold(node.expression);
    if (ts.isBinaryExpression(node) && node.operatorToken.kind === ts.SyntaxKind.PlusToken) {
      const left = fold(node.left);
      const right = fold(node.right);
      return left === null || right === null ? null : crossProduct(left, right);
    }
    if (ts.isCallExpression(node)) {
      const kind = pathCallKind(node);
      if (kind !== null) {
        const folded = node.arguments.map(fold);
        if (folded.some((part) => part === null)) return null;
        //: One candidate list per argument; fold each combination under each
        //: flavour. Arguments are constants, so this is a small product.
        let combinations = [[]];
        for (const candidates of folded) {
          const next = [];
          for (const prefix of combinations) {
            for (const value of candidates) next.push([...prefix, value]);
          }
          if (next.length > MAX_FOLD_CANDIDATES) return null;
          combinations = next;
        }
        const values = new Set();
        for (const flavour of kind.flavours) {
          for (const parts of combinations) {
            try {
              values.add(foldPathCall(kind.fn, flavour, parts));
            } catch {
              //: node itself refused these arguments; there is no path here
              //: to report, and inventing one would be the invented-evidence
              //: failure this project already recorded.
            }
          }
        }
        return values.size === 0 ? null : [...values];
      }
    }
    return null;
  };

  //: A bare string argument is a pathname as written -- normalising it here
  //: would need a flavour nothing has chosen, and the Python side already
  //: compares by component.
  const foldPath = (node) => fold(node);

  return { pathCallKind, fsSinkPathArguments, isRequireCall, fold, foldPath };
}

/**
 * Read every file through ONE program, so the checker can resolve an
 * identifier to the declaration actually in scope at it.
 *
 * `noResolve`/`noLib` are deliberate: nothing here needs `fs` or `path` to
 * resolve to real type declarations -- only local symbols matter, and loading
 * lib files would make the answer depend on what happens to be installed.
 *
 * `moduleDetection: Force` is not cosmetic and was added in round 5. Without
 * it TypeScript treats a file with no import and no export as a SCRIPT, whose
 * top-level declarations land in the global scope shared by every other
 * script in the program. Measured: a sibling `.ts` containing nothing but
 * `function require(name: string) { ... }` made a genuine
 * `require("../<NAME>/src/index")` in a DIFFERENT file read clean, because
 * the checker resolved that file's `require` to the sibling's declaration.
 * Node runs each file in its own module wrapper; one program over all of them
 * did not, and the isolation answer for one file came to depend on an
 * unrelated one. Forcing module detection restores per-file scope, which is
 * what the runtime actually does.
 */
function collectSpecifiersForProgram(files) {
  const program = ts.createProgram(files, {
    allowJs: true,
    noResolve: true,
    noLib: true,
    target: ts.ScriptTarget.Latest,
    module: ts.ModuleKind.CommonJS,
    moduleDetection: ts.ModuleDetectionKind.Force,
  });
  const checker = program.getTypeChecker();
  const analyzer = makeAnalyzer(checker);

  return files.map((file) => {
    const source = program.getSourceFile(file);
    if (!source) {
      //: Reporting isolation over a file nothing read is the broken-instrument
      //: result this project keeps recording, so it is an error, not a zero.
      throw new Error(`typescript did not read ${file}`);
    }
    const specifiers = [];
    const pathLikes = [];

    const note = (bucket, values, node) => {
      if (values === null || values === undefined) return;
      const { line } = source.getLineAndCharacterOfPosition(node.getStart(source));
      for (const value of values) bucket.push({ value, line: line + 1 });
    };

    const visit = (node) => {
      if ((ts.isImportDeclaration(node) || ts.isExportDeclaration(node)) && node.moduleSpecifier) {
        note(specifiers, analyzer.fold(node.moduleSpecifier), node);
      } else if (
        ts.isImportEqualsDeclaration(node) &&
        node.moduleReference &&
        ts.isExternalModuleReference(node.moduleReference)
      ) {
        note(specifiers, analyzer.fold(node.moduleReference.expression), node);
      } else if (ts.isCallExpression(node)) {
        if (node.expression.kind === ts.SyntaxKind.ImportKeyword || analyzer.isRequireCall(node)) {
          note(specifiers, analyzer.fold(node.arguments[0]), node);
        } else {
          const pathArguments = analyzer.fsSinkPathArguments(node);
          if (pathArguments !== null) {
            // A real filesystem sink, and only the arguments that are PATHS --
            // `writeFileSync(path, content)` has one of each, and reading the
            // content as a path is how an identity-shaped string became a
            // dependency in an earlier version.
            for (const index of pathArguments) {
              note(pathLikes, analyzer.foldPath(node.arguments[index]), node);
            }
          }
        }
      }
      ts.forEachChild(node, visit);
    };

    visit(source);
    return { file, specifiers, pathLikes };
  });
}

/**
 * Diagnostics that say nothing about whether the `extends` chain was READ.
 *
 * This is an exemption list, not an allowlist, and the direction matters. It
 * used to be the other way round -- only 5083 (cannot read file) and 6053
 * (file not found) counted as unresolved, everything else was discarded --
 * and measured on that version:
 *
 *   circular extends      -> 18000  ok:true, unresolved:[]   step 3d: OK
 *   `"extends": 42`       ->  5024  ok:true, unresolved:[]   step 3d: OK
 *
 * Both are configs TypeScript could not follow, reported as configs with
 * nothing to follow. An unread link read as no link, which is the whole
 * subject of this gate.
 *
 * 18003 ("no inputs were found") is exempt because it is about the FILES a
 * config selects, not about the configs it inherits -- every fixture config
 * that lists no sources emits it, and the real `functions/tsconfig.json`
 * emits nothing at all (measured).
 */
const CHAIN_IRRELEVANT_DIAGNOSTICS = new Set([18003]);

/**
 * Every config file TypeScript actually READS to build this project's options.
 *
 * Not resolved by hand. An earlier version walked `extends` itself with node's
 * `require.resolve`, and TypeScript disagreed with it on a real, valid chain:
 * a config package declaring `{"main": "index.js", "tsconfig": "base.json"}`
 * is accepted by tsc, which inherits `base.json`, while `require.resolve`
 * follows `main` and lands on JavaScript. Measured: tsc exits 0 and inherits
 * the option; the hand-rolled resolver reported the chain unreadable. An
 * instrument that fails a valid build is the same defect class as one that
 * passes an invalid one.
 *
 * So TypeScript's own config resolver runs, with `readFile` instrumented: the
 * files it consumes ARE the chain. `--showConfig` cannot answer this, because
 * it prints the resolved options and a config inherited from elsewhere leaves
 * no trace in them.
 */
function collectExtends(entry) {
  const resolved = path.resolve(entry);
  const consumed = [];
  const unresolved = [];

  const host = {
    useCaseSensitiveFileNames: ts.sys.useCaseSensitiveFileNames,
    getCurrentDirectory: () => path.dirname(resolved),
    readDirectory: (...args) => ts.sys.readDirectory(...args),
    fileExists: (file) => ts.sys.fileExists(file),
    readFile: (file) => {
      consumed.push(file);
      return ts.sys.readFile(file);
    },
    onUnRecoverableConfigFileDiagnostic: (diagnostic) => {
      unresolved.push({
        from: resolved,
        specifier: null,
        reason: ts.flattenDiagnosticMessageText(diagnostic.messageText, " "),
      });
    },
  };

  const parsed = ts.getParsedCommandLineOfConfigFile(resolved, {}, host);
  for (const diagnostic of (parsed && parsed.errors) || []) {
    if (CHAIN_IRRELEVANT_DIAGNOSTICS.has(diagnostic.code)) continue;
    unresolved.push({
      from: resolved,
      specifier: null,
      code: diagnostic.code,
      reason: ts.flattenDiagnosticMessageText(diagnostic.messageText, " "),
    });
  }

  const entryKey = fs.existsSync(resolved) ? fs.realpathSync.native(resolved) : resolved;
  const seen = new Set([entryKey]);
  const chain = [];
  for (const file of consumed) {
    // A path TypeScript TRIED to read but that does not exist is reported
    // through `unresolved` above, not counted as an inherited config.
    if (!fs.existsSync(file)) continue;
    const key = fs.realpathSync.native(file);
    if (seen.has(key)) continue;
    seen.add(key);
    chain.push(key);
  }
  return { chain, unresolved };
}

try {
  if (mode === "specifiers") {
    process.stdout.write(
      JSON.stringify({ ok: true, error: null, files: collectSpecifiersForProgram(rest) })
    );
  } else if (mode === "extends") {
    if (rest.length !== 1) fail("extends mode takes exactly one tsconfig path");
    process.stdout.write(JSON.stringify({ ok: true, error: null, ...collectExtends(rest[0]) }));
  } else {
    fail(`unknown mode ${mode}`);
  }
} catch (err) {
  fail(`${err && err.message ? err.message : String(err)}`);
}
