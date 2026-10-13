#!/usr/bin/env bash
# =====================================================================
# search_path scenarios for 0018 / 0019 (disposable test DB only).
#   A) production-like: 0001–0017 + 0019 WITHOUT 0018 (the reported error)
#      plus hand-made SECURITY DEFINER functions with unusual paths
#   B) then 0018, then 0019 again (order / idempotency)
#   C) the self-check still REJECTS an unsafe function it cannot fix
# =====================================================================
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
MIG="$HERE/../../migrations"
DB="${TEST_DB:-freightlink_test}"
[[ "$DB" == *test* ]] || { echo "Refusing: TEST_DB must contain 'test'"; exit 2; }
export PGOPTIONS="-c client_min_messages=warning"
PSQL=(psql -X -v ON_ERROR_STOP=1 -q -d "$DB")
fail=0
ok()  { echo "PASS  $1"; }
bad() { echo "FAIL  $1"; fail=1; }
q()   { "${PSQL[@]}" -At -c "$1"; }
sp()  { q "select coalesce((select substr(c,13) from unnest(proconfig) c where c like 'search_path=%'),'<none>') from pg_proc where oid = to_regprocedure('$1')"; }

"${PSQL[@]}" -d postgres -c "drop database if exists $DB" -c "create database $DB"
"${PSQL[@]}" -f "$HERE/00_supabase_stub.sql" 2>/dev/null
for f in "$MIG"/0*.sql; do n="$(basename "$f" | cut -c1-4)"; [[ "$n" > "0017" ]] && continue; "${PSQL[@]}" -f "$f" >/dev/null; done
"${PSQL[@]}" -f "$HERE/10_fixtures.sql" >/dev/null

# hand-made functions as they might exist on production
"${PSQL[@]}" <<'SQL'
create function public.zz_empty()  returns int language sql security definer set search_path = '' as 'select 1';
create function public.zz_ext()    returns text language sql security definer set search_path = public, extensions as 'select current_setting(''search_path'')';
create function public.zz_first()  returns int language sql security definer set search_path = pg_temp, public as 'select 1';
create function public.zz_user()   returns int language sql security definer set search_path = "$user", public as 'select 1';
create function public.zz_none()   returns int language sql security definer as 'select 1';
create function public.zz_invoker() returns int language sql as 'select 1';   -- not definer: must be untouched
create table public.zz_bodies as
  select p.oid::regprocedure::text as sig, md5(p.prosrc) as h from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public';
SQL

echo "== A) 0019 on a database WITHOUT 0018"
if out=$("${PSQL[@]}" -1 -f "$MIG/0019_package1b_security.sql" 2>&1); then ok "A1 0019 applies without 0018 (reported error fixed)"; else bad "A1 0019 failed: $out"; fi
grep -q "0018 has NOT been applied" <<<"$out" && ok "A2 0019 warns that 0018 is missing" || bad "A2 no warning about missing 0018"
[[ "$(sp 'public.is_admin()')" == "public, extensions, pg_temp" ]] && ok "A3 is_admin(): <none> -> public, extensions, pg_temp" || bad "A3 is_admin(): $(sp 'public.is_admin()')"
[[ "$(sp 'public.unlock_contact(uuid)')" == "public, pg_temp" ]] && ok "A4 0006 function: public -> public, pg_temp" || bad "A4 $(sp 'public.unlock_contact(uuid)')"
[[ "$(sp 'public.zz_empty()')" == '""' ]] && ok "A5 empty search_path kept (strictest)" || bad "A5 $(sp 'public.zz_empty()')"
[[ "$(sp 'public.zz_ext()')" == "public, extensions, pg_temp" ]] && ok "A6 extra schema kept, pg_temp appended" || bad "A6 $(sp 'public.zz_ext()')"
[[ "$(sp 'public.zz_first()')" == "public, pg_temp" ]] && ok "A7 pg_temp moved from first to last" || bad "A7 $(sp 'public.zz_first()')"
[[ "$(sp 'public.zz_user()')" == '"$user", public, pg_temp' ]] && ok 'A8 quoted "$user" kept' || bad "A8 $(sp 'public.zz_user()')"
[[ "$(sp 'public.zz_none()')" == "public, extensions, pg_temp" ]] && ok "A9 function without path fixed" || bad "A9 $(sp 'public.zz_none()')"
[[ "$(sp 'public.zz_invoker()')" == "<none>" ]] && ok "A10 SECURITY INVOKER functions untouched" || bad "A10 $(sp 'public.zz_invoker()')"
[[ "$(q "select current_user; " >/dev/null; q "select public.zz_ext()")" == "public, extensions, pg_temp" ]] && ok "A11 function still runs with its schemas" || bad "A11"
changed=$(q "select string_agg(b.sig, ', ') from public.zz_bodies b join pg_proc p on p.oid = to_regprocedure(b.sig)
             where md5(p.prosrc) <> b.h
               and b.sig not in ('handle_new_auth_user()','guard_user_protected_columns()')")
[[ -z "$changed" ]] && ok "A12 no function body changed except the two 0019 intentionally redefines" || bad "A12 bodies changed: $changed"

echo "== B) then 0018, then 0019 again"
"${PSQL[@]}" -1 -f "$MIG/0018_package1_security.sql" >/dev/null 2>&1 && ok "B1 0018 applies after 0019" || bad "B1 0018 failed"
"${PSQL[@]}" -1 -f "$MIG/0019_package1b_security.sql" >/dev/null 2>&1 && ok "B2 0019 re-applies cleanly" || bad "B2 0019 re-apply failed"
[[ "$(sp 'public.zz_ext()')" == "public, extensions, pg_temp" && "$(sp 'public.zz_empty()')" == '""' ]] && ok "B3 0018 also preserves custom paths" || bad "B3 $(sp 'public.zz_ext()') / $(sp 'public.zz_empty()')"

echo "== C) the check still rejects what it cannot fix"
# Extract 0019's self-check block and run it against a deliberately unsafe
# function (the normalization step is NOT run here, as for a function owned
# by a role the migration cannot ALTER).
python3 -I - "$MIG/0019_package1b_security.sql" > /tmp/claude-sp-check.sql <<'PY'
import sys; s=open(sys.argv[1]).read()
a=s.index('-- 5) Self-checks'); b=s.index('do $$', a); e=s.index('end $$;', b)+len('end $$;')
print(s[b:e])
PY
"${PSQL[@]}" -c "alter function public.zz_none() set search_path = public"
if out=$("${PSQL[@]}" -f /tmp/claude-sp-check.sql 2>&1); then bad "C1 unsafe path was accepted"; else
  grep -q "zz_none() \[owner postgres, search_path=public\]" <<<"$out" && ok "C1 unsafe path rejected and named: ${out#*: }" || bad "C1 wrong message: $out"; fi
"${PSQL[@]}" -c "alter function public.zz_none() reset search_path"
"${PSQL[@]}" -f /tmp/claude-sp-check.sql >/dev/null 2>&1 && bad "C2 missing path accepted" || ok "C2 missing search_path rejected"

exit $fail
