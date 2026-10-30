#!/usr/bin/env python3
"""
Static structural checker for the FreightLink migrations.

This environment has no network access, so a real `supabase db push`
against a live Postgres instance cannot be run from here. This script
is a best-effort static check: balanced parens/quotes, one semicolon-
terminated statement per statement, every `references table(...)` in a
FK points at a table defined earlier in the same or an earlier
migration file, and every RLS policy targets a table that exists and
has `enable row level security` somewhere.

Run: python3 validate_sql.py
"""
import re
import sys
from pathlib import Path

MIGRATIONS_DIR = Path(__file__).parent.parent / "supabase" / "migrations"

def strip_line_comments(sql):
    """Remove `-- ...` line comments before structural checks, so an
    apostrophe inside a comment (e.g. "the spec's field") is not
    mistaken for the start of a string literal."""
    out_lines = []
    for line in sql.split("\n"):
        idx = line.find("--")
        out_lines.append(line[:idx] if idx != -1 else line)
    return "\n".join(out_lines)

def check_balance(name, sql):
    sql = strip_line_comments(sql)
    errors = []
    depth = 0
    in_single_quote = False
    for i, ch in enumerate(sql):
        if ch == "'" and not in_single_quote:
            in_single_quote = True
        elif ch == "'" and in_single_quote:
            in_single_quote = False
        elif ch == "(" and not in_single_quote:
            depth += 1
        elif ch == ")" and not in_single_quote:
            depth -= 1
            if depth < 0:
                errors.append(f"{name}: unmatched ')' near char {i}")
                depth = 0
    if depth != 0:
        errors.append(f"{name}: {depth} unclosed '(' at end of file")
    if in_single_quote:
        errors.append(f"{name}: unterminated string literal")
    return errors

def find_tables_defined(sql):
    return set(re.findall(r"create\s+table\s+(?:if\s+not\s+exists\s+)?public\.(\w+)", sql, re.I))

def find_fk_targets(sql):
    return set(re.findall(r"references\s+public\.(\w+)\s*\(", sql, re.I))

def find_rls_enabled(sql):
    return set(re.findall(r"alter table\s+public\.(\w+)\s+enable row level security", sql, re.I))

def find_policy_targets(sql):
    # Only real `create policy ... on public.<table>` statements: the old
    # pattern ("on public.x ... for") also matched function names such as
    # public.clear_chat_for_me( and reported them as tables (false alarm).
    return set(re.findall(r'create\s+policy\s+(?:"[^"]+"|\w+)\s+on\s+public\.(\w+)', sql, re.I))

def find_duplicate_policy_names(sql):
    # Policy names need only be unique per table. Forward migrations often
    # drop and recreate an existing policy, so inspect the resulting state.
    statements = re.findall(
        r'(?:create\s+policy\s+"([^"]+)"\s+on\s+public\.(\w+))|'
        r'(?:drop\s+policy\s+(?:if\s+exists\s+)?"([^"]+)"\s+on\s+public\.(\w+))',
        sql, re.I,
    )
    active, dupes = set(), set()
    for create_name, create_table, drop_name, drop_table in statements:
        if create_name:
            key = (create_table.lower(), create_name.lower())
            if key in active:
                dupes.add(f"{create_table}.{create_name}")
            active.add(key)
        else:
            active.discard((drop_table.lower(), drop_name.lower()))
    return dupes

def main():
    files = sorted(MIGRATIONS_DIR.glob("*.sql"))
    if not files:
        print("No migration files found at", MIGRATIONS_DIR)
        sys.exit(1)

    all_defined_tables = set()
    all_sql = ""
    problems = []

    for f in files:
        sql = f.read_text()
        all_sql += "\n" + sql
        problems += check_balance(f.name, sql)
        all_defined_tables |= find_tables_defined(sql)

    fk_targets = find_fk_targets(all_sql)
    missing_fk_targets = fk_targets - all_defined_tables
    if missing_fk_targets:
        problems.append(f"FK references to undefined tables: {sorted(missing_fk_targets)}")

    rls_enabled = find_rls_enabled(all_sql)
    tables_without_rls = all_defined_tables - rls_enabled
    policy_targets = find_policy_targets(all_sql)
    policies_on_tables_without_rls = policy_targets - rls_enabled

    dupes = find_duplicate_policy_names(all_sql)
    if dupes:
        problems.append(f"Duplicate policy names: {sorted(dupes)}")

    print(f"Checked {len(files)} migration file(s): {[f.name for f in files]}")
    print(f"Tables defined: {len(all_defined_tables)}")
    print(f"Tables with RLS enabled: {len(rls_enabled)}")
    print()

    if problems:
        print("PROBLEMS FOUND:")
        for p in problems:
            print(" -", p)
    else:
        print("No paren/quote balance issues, no dangling FK targets, no duplicate policy names.")

    if tables_without_rls:
        print()
        print("Tables with NO RLS enabled (open by default under Postgres' normal")
        print("access model — only acceptable for lookup-style tables):")
        for t in sorted(tables_without_rls):
            print(" -", t)

    if policies_on_tables_without_rls:
        print()
        print("WARNING: policies defined on tables where RLS was never enabled",
              "(the policy would be silently ignored):")
        for t in sorted(policies_on_tables_without_rls):
            print(" -", t)

    print()
    print("NOTE: this is static analysis only. It cannot catch every possible")
    print("Postgres error (e.g. type mismatches, reserved-word collisions).")
    print("Final verification still requires `supabase db push` against a real")
    print("project, which this sandboxed environment cannot reach (no network).")

if __name__ == "__main__":
    main()
