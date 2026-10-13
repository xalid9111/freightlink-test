#!/usr/bin/env python3
"""AutoFix CI: read `flutter analyze` and `flutter test` output, post a
short summary to the admin panel (RPC autofix_ci_report, migration 0034)
and exit 1 when there are analyzer errors or failing tests.

Usage: autofix_ci_report.py analyze.txt tests.txt [sql.txt] [build.txt]
Env:   SUPABASE_URL, SUPABASE_ANON_KEY, AUTOFIX_CI_TOKEN (optional — without
       it nothing is posted), GITHUB_SHA, GITHUB_REF_NAME, ANALYZE_EXIT,
       TEST_EXIT, SQL_EXIT, BUILD_EXIT, STATIC_EXIT.
Standard library only (free, no extra installs).
"""
import json
import os
import re
import sys
import urllib.request


def read(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return ""


def parse_analyze(text):
    errors, warnings, lines = 0, 0, []
    for line in text.splitlines():
        s = line.strip()
        # "error • Undefined name 'x' • lib/a.dart:12:3 • undefined_identifier"
        m = re.match(r"^(error|warning|info)\s+[•-]\s+(.*)$", s)
        if not m:
            continue
        sev = m.group(1)
        if sev == "error":
            errors += 1
            lines.append(s)
        elif sev == "warning":
            warnings += 1
            lines.append(s)
    return errors, warnings, lines


def parse_tests(text):
    passed, failed = 0, 0
    # flutter test progress lines: "00:05 +12 -1: ..." (last one wins)
    for m in re.finditer(r"\+(\d+)(?:\s+~\d+)?(?:\s+-(\d+))?:", text):
        passed = int(m.group(1))
        failed = int(m.group(2) or 0)
    failing = []
    for line in text.splitlines():
        if "[E]" in line or line.strip().startswith("Expected:") or "Test failed" in line:
            failing.append(line.strip())
    return passed, failed, failing[:40]


def main():
    analyze_txt = read(sys.argv[1]) if len(sys.argv) > 1 else ""
    tests_txt = read(sys.argv[2]) if len(sys.argv) > 2 else ""
    a_err, a_warn, a_lines = parse_analyze(analyze_txt)
    t_pass, t_fail, t_lines = parse_tests(tests_txt)
    test_exit = os.environ.get("TEST_EXIT", "0")
    if test_exit not in ("", "0") and t_fail == 0:
        t_fail = 1  # e.g. compile error before any test ran
        t_lines = [l for l in tests_txt.splitlines() if "Error" in l][:40] or ["flutter test exit code " + test_exit]
    sql_txt = read(sys.argv[3]) if len(sys.argv) > 3 else ""
    build_txt = read(sys.argv[4]) if len(sys.argv) > 4 else ""
    sql_suites = re.findall(r"([^:\n]+ : all \d+ checks passed)", sql_txt)
    # "PASS  C1 ... ERROR: ..." lines are passing negative tests (the error
    # is the expected result), so they are not failures.
    sql_fail = [l.strip() for l in sql_txt.splitlines()
                if ("FAIL" in l or "ERROR:" in l) and not l.lstrip().startswith("PASS")][:40]
    sql_exit = os.environ.get("SQL_EXIT", "")
    build_exit = os.environ.get("BUILD_EXIT", "")
    static_exit = os.environ.get("STATIC_EXIT", "")
    sql_ok = sql_exit in ("", "0") and not sql_fail
    build_ok = build_exit in ("", "0")
    static_ok = static_exit in ("", "0")
    if not sql_ok:
        t_fail += max(1, len(sql_fail))
    ok = a_err == 0 and t_fail == 0 and build_ok and static_ok

    build_lines = [l for l in build_txt.splitlines() if "Error" in l or "error" in l][:30]
    details = ("BRANCH: {}\n\nANALYZE ({} xəta, {} xəbərdarlıq)\n{}\n\nTESTLƏR ({} keçdi, {} uğursuz)\n{}"
               "\n\nSQL / RLS TESTLƏRİ ({})\n{}\n{}\n\nWEB BUILD: {}\n{}\n\nSTATİK YOXLAMALAR: {}").format(
        os.environ.get("GITHUB_REF_NAME", "?"),
        a_err, a_warn, "\n".join(a_lines[:120]) or "—", t_pass, t_fail, "\n".join(t_lines) or "—",
        "keçdi" if sql_ok else "UĞURSUZ", "\n".join(s.strip() for s in sql_suites) or "—", "\n".join(sql_fail),
        "keçdi" if build_ok else "UĞURSUZ", "\n".join(build_lines) if not build_ok else "",
        "keçdi" if static_ok else "UĞURSUZ")
    print(details)

    url = os.environ.get("SUPABASE_URL", "").rstrip("/")
    key = os.environ.get("SUPABASE_ANON_KEY", "")
    token = os.environ.get("AUTOFIX_CI_TOKEN", "")
    if url and key and token:
        body = json.dumps({
            "p_token": token,
            "p_sha": os.environ.get("GITHUB_SHA", "")[:40],
            "p_ok": ok,
            "p_analyze_errors": a_err,
            "p_analyze_warnings": a_warn,
            "p_tests_passed": t_pass,
            "p_tests_failed": t_fail,
            "p_details": details[:20000],
        }).encode("utf-8")
        req = urllib.request.Request(url + "/rest/v1/rpc/autofix_ci_report", data=body, method="POST", headers={
            "apikey": key, "Authorization": "Bearer " + key, "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                print("Admin panelə göndərildi:", r.status)
        except Exception as e:  # never hide the real result because of reporting
            print("Admin panelə göndərmək alınmadı:", e)
    else:
        print("AUTOFIX_CI_TOKEN yoxdur — nəticə yalnız GitHub-da görünür.")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
