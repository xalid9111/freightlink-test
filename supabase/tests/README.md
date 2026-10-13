# Database tests

Everything here runs against a **disposable** PostgreSQL (local or the CI
container) — never against the Supabase project. The runners refuse any
database whose name does not contain `test`.

| File | Purpose |
|---|---|
| `local/run_local.sh before` | 0001–0017: reproduces the issues fixed by 0018/0019 |
| `local/run_local.sh after` | 0018–0020, all suites, data-preservation and idempotency checks |
| `local/50_searchpath_scenarios.sh` | 0019 without 0018, custom search_path cases, strictness of the self-check |
| `messaging_audit_test.sql` | messaging regression (also run by `after`) |

```bash
PGHOST=localhost PGPORT=5432 PGUSER=postgres PGPASSWORD=postgres \
  bash supabase/tests/local/run_local.sh after
```
GitHub Actions runs all of them in `.github/workflows/ci.yml`.

`supabase/diagnostics/` contains READ-ONLY queries for the real project;
they are not migrations.
