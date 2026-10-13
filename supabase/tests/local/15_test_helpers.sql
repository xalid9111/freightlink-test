-- LOCAL TEST HELPERS (disposable test DB only).
-- tests.login(uid)  : act as that user (null = anonymous), like PostgREST
--                     does from the JWT. Combine with SET ROLE.
-- tests.err(sql)    : run sql as the CURRENT role, return the error
--                     message (null when it succeeded).
-- tests.check(ok,n) : record PASS / FAIL.   tests.summary(): totals,
--                     raises if anything failed.
create schema if not exists tests;
grant usage on schema tests to anon, authenticated, service_role;

create or replace function tests.login(p_uid uuid) returns void language plpgsql as $$
begin
  if p_uid is null then
    perform set_config('request.jwt.claims', '{"role":"anon"}', false);
    perform set_config('request.jwt.claim.sub', '', false);
  else
    perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, false);
    perform set_config('request.jwt.claim.sub', p_uid::text, false);
  end if;
end $$;

create or replace function tests.err(p_sql text) returns text language plpgsql as $$
begin
  execute p_sql;
  return null;
exception when others then
  return sqlerrm;
end $$;

create or replace function tests.check(p_ok boolean, p_name text) returns void language plpgsql as $$
declare k text := case when coalesce(p_ok, false) then 'tests.pass' else 'tests.fail' end;
begin
  perform set_config(k, (coalesce(nullif(current_setting(k, true), ''), '0')::int + 1)::text, false);
  if coalesce(p_ok, false) then
    raise warning 'PASS  %', p_name;
  else
    raise warning 'FAIL  %', p_name;
  end if;
end $$;

create or replace function tests.summary(p_suite text) returns void language plpgsql as $$
declare p int := coalesce(nullif(current_setting('tests.pass', true), ''), '0')::int;
        f int := coalesce(nullif(current_setting('tests.fail', true), ''), '0')::int;
begin
  perform set_config('tests.pass', '0', false);
  perform set_config('tests.fail', '0', false);
  if f > 0 then
    raise exception '% : % passed, % FAILED', p_suite, p, f;
  end if;
  raise warning '% : all % checks passed', p_suite, p;
end $$;

grant execute on all functions in schema tests to anon, authenticated, service_role;
