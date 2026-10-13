#!/usr/bin/env python3
"""
Static i18n consistency checker.

1. Confirms all 6 language JSON files (assets/i18n/{az,tr,ru,en,ka,zh}.json
   — zh = Simplified Chinese, zh-CN) have exactly the same set of keys — a missing key in one language
   would silently fall back to showing the raw key string for that
   language only, which is easy to miss without this check.
2. Greps the Dart source for every `.t('some_key')` call (static string
   literals only — this cannot see keys built dynamically) and flags
   any that aren't in the catalog.
3. Reports catalog keys never referenced via `.t(...)` as informational
   (not an error): keys consumed dynamically, e.g. AppStrings.error(code)
   building 'error_$code' at runtime, will show up here even though
   they're genuinely used — this is a hint list to eyeball, not a
   pass/fail signal on its own.

Run: python3 validate_i18n.py
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).parent.parent
I18N_DIR = ROOT / "assets" / "i18n"
LIB_DIR = ROOT / "lib"
LANGS = ["az", "tr", "ru", "en", "ka", "zh"]

def main():
    catalogs = {}
    for lang in LANGS:
        path = I18N_DIR / f"{lang}.json"
        if not path.exists():
            print(f"FAIL: missing {path}")
            sys.exit(1)
        catalogs[lang] = json.loads(path.read_text(encoding="utf-8"))

    key_sets = {lang: set(c.keys()) for lang, c in catalogs.items()}
    all_keys = set.union(*key_sets.values())
    problems = []

    for lang, keys in key_sets.items():
        missing = all_keys - keys
        if missing:
            problems.append(f"{lang}.json is missing keys: {sorted(missing)}")

    for lang, c in catalogs.items():
        empty = [k for k, v in c.items() if not str(v).strip()]
        if empty:
            problems.append(f"{lang}.json has empty values for: {sorted(empty)}")

    # Placeholders ({n}, {name}, …) must be the same in every language,
    # otherwise AppStrings.t(key, params) leaves a raw {x} on screen.
    ph = re.compile(r"\{(\w+)\}")
    base = catalogs["en"]
    for lang, c in catalogs.items():
        bad = sorted(k for k in base if k in c and set(ph.findall(str(base[k]))) != set(ph.findall(str(c[k]))))
        if bad:
            problems.append(f"{lang}.json placeholders differ from en.json for: {bad}")

    # Static usage scan (skip // line comments so doc-comment examples
    # like "call .t('key')" don't get counted as a real usage)
    used_keys = set()
    pattern = re.compile(r"\.t\(\s*'([a-zA-Z0-9_]+)'")
    for f in LIB_DIR.rglob("*.dart"):
        for line in f.read_text(encoding="utf-8").split("\n"):
            code_part = line.split("//", 1)[0]
            for m in pattern.finditer(code_part):
                used_keys.add(m.group(1))

    unknown_used = used_keys - all_keys
    if unknown_used:
        problems.append(f"Dart code calls .t() with keys not in any catalog: {sorted(unknown_used)}")

    unused = all_keys - used_keys
    dynamic_prefixes = ("error_",)
    unused_non_dynamic = sorted(k for k in unused if not k.startswith(dynamic_prefixes))

    print(f"Languages checked: {LANGS}")
    print(f"Total keys: {len(all_keys)}")
    print(f"Keys referenced via static .t('...') calls: {len(used_keys)}")
    print()

    if problems:
        print("PROBLEMS FOUND:")
        for p in problems:
            print(" -", p)
    else:
        print(f"All {len(LANGS)} language files have identical key sets, matching placeholders, "
              "no empty values, and every statically-called .t() key exists in the catalog.")

    if unused_non_dynamic:
        print()
        print("INFO — catalog keys not found via a static .t('...') call")
        print("(expected for keys only used dynamically, e.g. via AppStrings.error();")
        print("worth a manual glance for anything that looks like dead weight):")
        for k in unused_non_dynamic:
            print(" -", k)

    if problems:
        sys.exit(1)

if __name__ == "__main__":
    main()
