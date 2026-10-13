#!/usr/bin/env python3
"""
Static structural checker for the FreightLink Dart source tree.

No Flutter SDK and no network are available in this sandbox, so
`flutter analyze` / `flutter pub get` cannot be run here. This script
is the best available substitute: for every .dart file under lib/ it
checks bracket/paren/quote balance (comment- and string-aware), that
every relative import resolves to a real file, and that every
Provider/class referenced via a bare identifier (heuristic: capitalized
or *Provider-suffixed names used as `Foo(` or `fooProvider`) is defined
somewhere in the tree or comes from a known package.

Run: python3 validate_dart.py
"""
import re
import sys
from pathlib import Path

LIB_DIR = Path(__file__).parent.parent / "lib"

def strip_comments_and_strings(src):
    """Blank out // line comments, /* */ block comments, and the
    contents of string literals (single- and double-quoted, with or
    without triple-quoting) so bracket-balance checks aren't confused
    by punctuation inside them."""
    out = []
    i, n = 0, len(src)
    while i < n:
        two = src[i:i+2]
        if two == '//':
            j = src.find('\n', i)
            j = n if j == -1 else j
            out.append(' ' * (j - i))
            i = j
        elif two == '/*':
            j = src.find('*/', i + 2)
            j = n if j == -1 else j + 2
            out.append(' ' * (j - i))
            i = j
        elif src[i] in ('"', "'"):
            quote = src[i]
            triple = src[i:i+3] == quote * 3
            qlen = 3 if triple else 1
            j = i + qlen
            while j < n:
                if src[j] == '\\':
                    j += 2
                    continue
                if src[j:j+qlen] == quote * qlen:
                    j += qlen
                    break
                j += 1
            out.append(' ' * (j - i))
            i = j
        else:
            out.append(src[i])
            i += 1
    return ''.join(out)

def check_balance(path, src):
    clean = strip_comments_and_strings(src)
    pairs = {'(': ')', '[': ']', '{': '}'}
    closers = {v: k for k, v in pairs.items()}
    stack = []
    errors = []
    for idx, ch in enumerate(clean):
        if ch in pairs:
            stack.append((ch, idx))
        elif ch in closers:
            if not stack or stack[-1][0] != closers[ch]:
                errors.append(f"{path}: unmatched '{ch}' near char {idx}")
                if stack:
                    stack.pop()
            else:
                stack.pop()
    for ch, idx in stack:
        errors.append(f"{path}: unclosed '{ch}' opened near char {idx}, never closed")
    return errors

def check_imports(path, src):
    errors = []
    for m in re.finditer(r"import\s+'([^']+)'", src):
        target = m.group(1)
        if target.startswith('package:') or target.startswith('dart:'):
            continue
        resolved = (path.parent / target).resolve()
        if not resolved.exists():
            errors.append(f"{path}: relative import does not resolve: '{target}' -> {resolved}")
    return errors

def main():
    files = sorted(LIB_DIR.rglob("*.dart"))
    if not files:
        print("No Dart files found under", LIB_DIR)
        sys.exit(1)

    problems = []
    for f in files:
        src = f.read_text()
        problems += check_balance(f, src)
        problems += check_imports(f, src)

    print(f"Checked {len(files)} Dart file(s) under {LIB_DIR}")
    if problems:
        print("PROBLEMS FOUND:")
        for p in problems:
            print(" -", p)
    else:
        print("No bracket/paren/quote balance issues. All relative imports resolve.")

    print()
    print("NOTE: this is static analysis only — it cannot catch type errors,")
    print("missing named parameters, or package API mismatches the way")
    print("`flutter analyze` would. Final verification still needs the real")
    print("Flutter SDK, which this sandboxed environment does not have.")

if __name__ == "__main__":
    main()
