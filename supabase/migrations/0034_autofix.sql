-- =====================================================================
-- 0034 — AutoFix: free error tracking + safe, pre-defined recovery
--
-- * app_errors        one row per distinct problem (fingerprint) with a
--                     counter; written ONLY through autofix_report()
--                     (size-limited, rate-limited). Admins read them.
-- * autofix_commands  safe actions an admin sends to every running app
--                     (reconnect chats, refresh data, reload when idle).
--                     Clients read only the newest id + action.
-- * autofix_actions   audit of every "Problemi həll et" press.
-- * autofix_ci_runs   results of the GitHub Actions quality check
--                     (flutter analyze + flutter test), posted with a
--                     secret token whose SHA-256 is stored here.
--
-- Nothing here deletes or changes user data. Recovery actions are a fixed
-- whitelist; each is allowed only for the error kinds it was made for.
--
-- Safe: forward-only, re-runnable. New tables only.
-- =====================================================================

create table if not exists public.app_errors (
  id            uuid primary key default gen_random_uuid(),
  fingerprint   text not null unique check (fingerprint ~ '^[0-9a-z_:.-]{4,120}$'),
  kind          text not null check (kind in ('runtime','api','network','freeze','messaging','navigation','auth')),
  code          text not null default '' check (char_length(code) <= 80),
  message       text not null default '' check (char_length(message) <= 1000),
  file          text check (file is null or char_length(file) <= 200),
  line          integer check (line is null or line between 0 and 1000000),
  stack         text check (stack is null or char_length(stack) <= 4000),
  route         text check (route is null or char_length(route) <= 200),
  breadcrumbs   text check (breadcrumbs is null or char_length(breadcrumbs) <= 2000),
  app_version   text check (app_version is null or char_length(app_version) <= 40),
  user_agent    text check (user_agent is null or char_length(user_agent) <= 300),
  auto_fixed    integer not null default 0 check (auto_fixed >= 0),
  count         integer not null default 1 check (count >= 1),
  users         integer not null default 1 check (users >= 1),
  last_user     uuid,
  status        text not null default 'open' check (status in ('open','fixed','ignored')),
  first_seen_at timestamptz not null default now(),
  last_seen_at  timestamptz not null default now(),
  resolved_at   timestamptz,
  resolved_by   uuid
);
create index if not exists app_errors_status_seen_idx on public.app_errors (status, last_seen_at desc);

-- Per-user rate limit for reports (keeps a buggy client from flooding).
create table if not exists public.app_error_rate (
  user_id     uuid primary key,
  window_from timestamptz not null default now(),
  n           integer not null default 0
);

create table if not exists public.autofix_commands (
  id         bigserial primary key,
  action     text not null check (action in ('reconnect','refresh_data','reload_when_idle')),
  error_id   uuid references public.app_errors (id) on delete set null,
  created_by uuid,
  created_at timestamptz not null default now()
);

create table if not exists public.autofix_actions (
  id          bigserial primary key,
  error_id    uuid references public.app_errors (id) on delete set null,
  action      text not null,
  ok          boolean not null,
  note        text,
  executed_by uuid,
  executed_at timestamptz not null default now()
);

create table if not exists public.autofix_ci_runs (
  id             bigserial primary key,
  created_at     timestamptz not null default now(),
  sha            text check (sha is null or sha ~ '^[0-9a-f]{7,40}$'),
  ok             boolean not null,
  analyze_errors integer not null default 0,
  analyze_warnings integer not null default 0,
  tests_passed   integer not null default 0,
  tests_failed   integer not null default 0,
  details        text check (details is null or char_length(details) <= 20000)
);

create table if not exists public.autofix_settings (
  id            boolean primary key default true check (id),
  ci_token_hash text check (ci_token_hash is null or ci_token_hash ~ '^[0-9a-f]{64}$'),
  updated_at    timestamptz not null default now()
);
-- (its single row is created when the admin first sets the CI token)

alter table public.app_errors enable row level security;
alter table public.app_error_rate enable row level security;
alter table public.autofix_commands enable row level security;
alter table public.autofix_actions enable row level security;
alter table public.autofix_ci_runs enable row level security;
alter table public.autofix_settings enable row level security;
revoke all on public.app_errors, public.app_error_rate, public.autofix_commands, public.autofix_actions,
              public.autofix_ci_runs, public.autofix_settings from public, anon, authenticated;
grant select on public.app_errors, public.autofix_actions, public.autofix_ci_runs to authenticated;
drop policy if exists app_errors_admin on public.app_errors;
create policy app_errors_admin on public.app_errors for select to authenticated using (public.is_admin());
drop policy if exists autofix_actions_admin on public.autofix_actions;
create policy autofix_actions_admin on public.autofix_actions for select to authenticated using (public.is_admin());
drop policy if exists autofix_ci_runs_admin on public.autofix_ci_runs;
create policy autofix_ci_runs_admin on public.autofix_ci_runs for select to authenticated using (public.is_admin());

-- Which pre-tested recovery fits which kind of problem. Anything not in
-- this list has NO automatic fix → the admin panel says so and shows the
-- file / line / logs for a manual fix.
create or replace function public.autofix_action_for(p_kind text)
returns text language sql immutable set search_path = public, pg_temp as $$
  select case p_kind
    when 'messaging' then 'reconnect'
    when 'network'   then 'refresh_data'
    when 'api'       then 'refresh_data'
    when 'auth'      then 'refresh_data'
    when 'freeze'    then 'reload_when_idle'
    else null
  end;
$$;

-- ---- report (any signed-in user) -----------------------------------------
-- p_events: array of {fingerprint, kind, code, message, file, line, stack,
-- route, breadcrumbs, app_version, user_agent, count, auto_fixed}
create or replace function public.autofix_report(p_events jsonb)
returns integer
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_uid uuid := auth.uid();
  e jsonb;
  v_n integer := 0;
  v_rate public.app_error_rate;
  v_kind text;
  v_fp text;
  v_cnt integer;
  v_fixed integer;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if p_events is null or jsonb_typeof(p_events) <> 'array' then raise exception 'invalid_events' using errcode = '22023'; end if;

  insert into app_error_rate (user_id) values (v_uid) on conflict (user_id) do nothing;
  select * into v_rate from app_error_rate where user_id = v_uid for update;
  if v_rate.window_from < now() - interval '10 minutes' then
    update app_error_rate set window_from = now(), n = 0 where user_id = v_uid;
    v_rate.n := 0;
  end if;

  for e in select * from jsonb_array_elements(p_events) limit 20 loop
    exit when v_rate.n + v_n >= 60;           -- max 60 reports / 10 min / user
    if jsonb_typeof(e) <> 'object' then continue; end if;
    v_fp := lower(left(coalesce(e->>'fingerprint', ''), 120));
    v_kind := coalesce(e->>'kind', '');
    if v_fp !~ '^[0-9a-z_:.-]{4,120}$' or v_kind not in ('runtime','api','network','freeze','messaging','navigation','auth') then
      continue;
    end if;
    begin
      v_cnt := least(greatest(coalesce((e->>'count')::integer, 1), 1), 1000);
      v_fixed := least(greatest(coalesce((e->>'auto_fixed')::integer, 0), 0), 1000);
    exception when others then
      v_cnt := 1; v_fixed := 0;
    end;
    insert into app_errors as a (fingerprint, kind, code, message, file, line, stack, route, breadcrumbs,
                                 app_version, user_agent, count, auto_fixed, last_user)
    values (
      v_fp, v_kind,
      left(coalesce(e->>'code', ''), 80),
      left(coalesce(e->>'message', ''), 1000),
      nullif(left(coalesce(e->>'file', ''), 200), ''),
      case when coalesce(e->>'line', '') ~ '^[0-9]{1,6}$' then (e->>'line')::integer end,
      nullif(left(coalesce(e->>'stack', ''), 4000), ''),
      nullif(left(coalesce(e->>'route', ''), 200), ''),
      nullif(left(coalesce(e->>'breadcrumbs', ''), 2000), ''),
      nullif(left(coalesce(e->>'app_version', ''), 40), ''),
      nullif(left(coalesce(e->>'user_agent', ''), 300), ''),
      v_cnt, v_fixed, v_uid)
    on conflict (fingerprint) do update set
      count        = least(a.count + excluded.count, 2000000000),
      auto_fixed   = least(a.auto_fixed + excluded.auto_fixed, 2000000000),
      users        = a.users + case when a.last_user is distinct from excluded.last_user then 1 else 0 end,
      last_user    = excluded.last_user,
      message      = excluded.message,
      stack        = coalesce(excluded.stack, a.stack),
      route        = coalesce(excluded.route, a.route),
      breadcrumbs  = coalesce(excluded.breadcrumbs, a.breadcrumbs),
      app_version  = coalesce(excluded.app_version, a.app_version),
      user_agent   = coalesce(excluded.user_agent, a.user_agent),
      last_seen_at = now(),
      -- A problem marked fixed that comes back is open again.
      status       = case when a.status = 'fixed' then 'open' else a.status end,
      resolved_at  = case when a.status = 'fixed' then null else a.resolved_at end;
    v_n := v_n + 1;
  end loop;
  update app_error_rate set n = n + v_n where user_id = v_uid;
  return v_n;
end;
$$;

-- ---- clients: newest admin command (cheap; polled every few minutes) -----
create or replace function public.autofix_latest_command()
returns table (id bigint, action text, created_at timestamptz)
language sql stable security definer set search_path = public, pg_temp as $$
  select c.id, c.action, c.created_at from autofix_commands c
   where auth.uid() is not null and c.created_at > now() - interval '2 days'
   order by c.id desc limit 1;
$$;

-- ---- admin: "Problemi həll et" -------------------------------------------
create or replace function public.admin_autofix_run(p_error uuid)
returns text
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_err public.app_errors;
  v_action text;
begin
  perform public._require_admin();
  select * into v_err from app_errors where id = p_error;
  if v_err.id is null then raise exception 'not_found' using errcode = 'P0002'; end if;
  v_action := public.autofix_action_for(v_err.kind);
  if v_action is null then
    -- No pre-tested fix for this kind (e.g. a code bug): nothing is run,
    -- the attempt is logged and the app shows "manual fix needed".
    insert into autofix_actions (error_id, action, ok, note, executed_by)
    values (p_error, 'none', false, 'no_safe_fix', auth.uid());
    return 'none';
  end if;
  insert into autofix_commands (action, error_id, created_by) values (v_action, p_error, auth.uid());
  update app_errors set status = 'fixed', resolved_at = now(), resolved_by = auth.uid() where id = p_error;
  insert into autofix_actions (error_id, action, ok, executed_by) values (p_error, v_action, true, auth.uid());
  perform public._admin_log('autofix.run', 'app_error', p_error::text,
    jsonb_build_object('status', v_err.status), jsonb_build_object('action', v_action));
  return v_action;
end;
$$;

-- Admin: mark fixed (after a manual code fix) / ignore / reopen.
create or replace function public.admin_autofix_set_status(p_error uuid, p_status text)
returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform public._require_admin();
  if p_status not in ('open','fixed','ignored') then raise exception 'invalid_status' using errcode = '22023'; end if;
  update app_errors
     set status = p_status,
         resolved_at = case when p_status = 'open' then null else now() end,
         resolved_by = case when p_status = 'open' then null else auth.uid() end
   where id = p_error;
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
  insert into autofix_actions (error_id, action, ok, note, executed_by)
  values (p_error, 'status:' || p_status, true, null, auth.uid());
end;
$$;

-- Admin: set the secret the GitHub Action uses (only its hash is kept).
create or replace function public.admin_autofix_set_ci_token(p_token text)
returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform public._require_admin();
  if p_token is null or char_length(p_token) < 24 or char_length(p_token) > 200 then
    raise exception 'token_too_short' using errcode = '22023';
  end if;
  insert into autofix_settings (id, ci_token_hash, updated_at)
  values (true, encode(sha256(convert_to(p_token, 'UTF8')), 'hex'), now())
  on conflict (id) do update set ci_token_hash = excluded.ci_token_hash, updated_at = now();
end;
$$;

-- GitHub Action → results (anon key + secret token; no user session).
create or replace function public.autofix_ci_report(
  p_token text, p_sha text, p_ok boolean,
  p_analyze_errors integer, p_analyze_warnings integer,
  p_tests_passed integer, p_tests_failed integer, p_details text
)
returns bigint
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_hash text; v_id bigint;
begin
  select ci_token_hash into v_hash from autofix_settings where id;
  if v_hash is null or p_token is null
     or encode(sha256(convert_to(p_token, 'UTF8')), 'hex') <> v_hash then
    raise exception 'invalid_token' using errcode = '28000';
  end if;
  -- Keep the table small: last 200 runs.
  delete from autofix_ci_runs where id in (select id from autofix_ci_runs order by id desc offset 199);
  insert into autofix_ci_runs (sha, ok, analyze_errors, analyze_warnings, tests_passed, tests_failed, details)
  values (case when coalesce(p_sha, '') ~ '^[0-9a-f]{7,40}$' then p_sha end, coalesce(p_ok, false),
          greatest(coalesce(p_analyze_errors, 0), 0), greatest(coalesce(p_analyze_warnings, 0), 0),
          greatest(coalesce(p_tests_passed, 0), 0), greatest(coalesce(p_tests_failed, 0), 0),
          left(p_details, 20000))
  returning id into v_id;
  return v_id;
end;
$$;

revoke all on function public.autofix_report(jsonb) from public, anon;
revoke all on function public.autofix_latest_command() from public, anon;
revoke all on function public.admin_autofix_run(uuid) from public, anon;
revoke all on function public.admin_autofix_set_status(uuid, text) from public, anon;
revoke all on function public.admin_autofix_set_ci_token(text) from public, anon;
revoke all on function public.autofix_ci_report(text, text, boolean, integer, integer, integer, integer, text) from public;
grant execute on function public.autofix_report(jsonb) to authenticated;
grant execute on function public.autofix_latest_command() to authenticated;
grant execute on function public.admin_autofix_run(uuid) to authenticated;
grant execute on function public.admin_autofix_set_status(uuid, text) to authenticated;
grant execute on function public.admin_autofix_set_ci_token(text) to authenticated;
grant execute on function public.autofix_ci_report(text, text, boolean, integer, integer, integer, integer, text) to anon, authenticated;
