-- RLS coverage (after every migration). Read-only, rolled back.
-- The static check (scripts/validate_sql.py) once reported functions
-- (_ad_v2_creative_for, autofix_action_for, clear_chat_for_me) as tables
-- with policies but no RLS — a false alarm. This proves it on the real
-- database: every public table has RLS on, and no policy sits on a table
-- without RLS (a policy there would be silently ignored).
begin;
select tests.check(not exists (
  select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity),
  'R1 every public table has row level security on');
select tests.check(not exists (
  select 1 from pg_policies p
    join pg_namespace n on n.nspname = p.schemaname
    join pg_class c on c.relnamespace = n.oid and c.relname = p.tablename
   where p.schemaname = 'public' and not c.relrowsecurity),
  'R2 no policy on a table without RLS');
select tests.check((select count(*) = 3 from pg_proc
                     where proname in ('_ad_v2_creative_for', 'autofix_action_for', 'clear_chat_for_me')),
  'R3 the three names the static check flagged are functions, not tables');
select tests.summary('RLS ƏHATƏSİ');
rollback;
