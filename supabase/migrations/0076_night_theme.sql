-- =====================================================================
-- 0076 — Night colours chosen by the admin (owner, 29.10.2026)
--
-- Admin → Dizayn və Rənglər → Gecə rejimi: "Klassik FreightLink", "Bordo
-- Premium" or the admin's own combination. Only night mode — the day
-- colours are in the app and never come from here.
--
-- * night_theme_state (one row): the published colours (null = classic)
--   and the ones published before, for "Əvvəlki temaya qayıt".
-- * night_themes: the admin's named combinations (drafts), e.g.
--   "Bordo Premium 1", "Black Edition".
-- * Colours are a small JSON object: background, card, button, accent,
--   line, text, text_soft as "#RRGGBB" and gradient, glow 0…1. Checked
--   here (night_theme_valid), nothing else is accepted.
-- * Nobody reads or writes the tables directly. Everyone (also before
--   sign-in) reads the published colours with night_theme_current();
--   only an admin saves, publishes, restores (checked on the server,
--   logged in the admin audit log).
--
-- Safe: forward-only, re-runnable. Two new tables, new functions. No
-- existing table or row is changed or deleted. Starts with the classic
-- colours (nothing published).
-- =====================================================================

begin;

create or replace function public.night_theme_valid(p jsonb)
returns boolean language sql immutable set search_path = public, pg_temp as $$
  select p is not null
     and jsonb_typeof(p) = 'object'
     -- only the known keys
     and not exists (
       select 1 from jsonb_object_keys(p) k
        where k not in ('background', 'card', 'button', 'accent', 'line', 'text', 'text_soft', 'gradient', 'glow'))
     -- every colour, as #RRGGBB
     and (select bool_and(coalesce(p ->> k, '') ~ '^#[0-9A-Fa-f]{6}$')
            from unnest(array['background', 'card', 'button', 'accent', 'line', 'text', 'text_soft']) k)
     -- levels 0…1 (optional)
     and (select bool_and(case
                            when not (p ? k) then true
                            when jsonb_typeof(p -> k) <> 'number' then false
                            else (p ->> k)::numeric between 0 and 1
                          end)
            from unnest(array['gradient', 'glow']) k);
$$;

create table if not exists public.night_theme_state (
  id integer primary key default 1 check (id = 1),
  colors jsonb check (colors is null or public.night_theme_valid(colors)),
  name text check (name is null or char_length(name) <= 60),
  previous_colors jsonb check (previous_colors is null or public.night_theme_valid(previous_colors)),
  previous_name text check (previous_name is null or char_length(previous_name) <= 60),
  has_previous boolean not null default false,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.users(id) on delete set null
);
insert into public.night_theme_state (id) values (1) on conflict (id) do nothing;

create table if not exists public.night_themes (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(btrim(name)) between 1 and 60),
  colors jsonb not null check (public.night_theme_valid(colors)),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references public.users(id) on delete set null
);
create unique index if not exists night_themes_name_key on public.night_themes (lower(btrim(name)));

alter table public.night_theme_state enable row level security;
alter table public.night_themes enable row level security;
revoke all on public.night_theme_state from anon, authenticated;
revoke all on public.night_themes from anon, authenticated;

-- The published night colours (everyone, also before sign-in).
create or replace function public.night_theme_current()
returns jsonb language sql stable security definer set search_path = public, pg_temp as $$
  select jsonb_build_object(
           'colors', s.colors,
           'name', s.name,
           'updated_at', s.updated_at,
           'has_previous', coalesce(s.has_previous, false))
    from (select 1) one
    left join public.night_theme_state s on s.id = 1;
$$;
revoke all on function public.night_theme_current() from public;
grant execute on function public.night_theme_current() to anon, authenticated;

-- Admins: the saved combinations.
create or replace function public.admin_night_themes()
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform public._require_admin();
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', t.id, 'name', t.name, 'colors', t.colors, 'updated_at', t.updated_at)
                     order by t.updated_at desc)
      from night_themes t), '[]'::jsonb);
end $$;
revoke all on function public.admin_night_themes() from public, anon;
grant execute on function public.admin_night_themes() to authenticated;

-- Admins: save a combination under a name (the same name is updated).
create or replace function public.admin_night_theme_save(p_name text, p_colors jsonb)
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_name text := btrim(coalesce(p_name, ''));
  v_id uuid;
begin
  perform public._require_admin();
  if char_length(v_name) not between 1 and 60 then raise exception 'invalid_name' using errcode = '22023'; end if;
  if not public.night_theme_valid(p_colors) then raise exception 'invalid_colors' using errcode = '22023'; end if;
  select id into v_id from night_themes where lower(btrim(name)) = lower(v_name);
  if v_id is null then
    insert into night_themes (name, colors, created_by) values (v_name, p_colors, auth.uid()) returning id into v_id;
  else
    update night_themes set name = v_name, colors = p_colors, updated_at = now() where id = v_id;
  end if;
  perform public._admin_log('night_theme.saved', 'night_themes', v_id::text, null, jsonb_build_object('name', v_name, 'colors', p_colors));
  return v_id;
end $$;
revoke all on function public.admin_night_theme_save(text, jsonb) from public, anon;
grant execute on function public.admin_night_theme_save(text, jsonb) to authenticated;

-- Admins: delete a saved combination (the published colours stay).
create or replace function public.admin_night_theme_delete(p_id uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_old night_themes;
begin
  perform public._require_admin();
  delete from night_themes where id = p_id returning * into v_old;
  if v_old.id is not null then
    perform public._admin_log('night_theme.deleted', 'night_themes', p_id::text, jsonb_build_object('name', v_old.name, 'colors', v_old.colors), null);
  end if;
end $$;
revoke all on function public.admin_night_theme_delete(uuid) from public, anon;
grant execute on function public.admin_night_theme_delete(uuid) to authenticated;

-- Admins: publish for everybody (null colours = back to classic). The
-- colours published until now are kept for "Əvvəlki temaya qayıt".
create or replace function public.admin_night_theme_publish(p_colors jsonb, p_name text default null)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_old night_theme_state;
  v_name text := nullif(btrim(coalesce(p_name, '')), '');
begin
  perform public._require_admin();
  if p_colors is not null and not public.night_theme_valid(p_colors) then
    raise exception 'invalid_colors' using errcode = '22023';
  end if;
  if v_name is not null and char_length(v_name) > 60 then raise exception 'invalid_name' using errcode = '22023'; end if;
  select * into v_old from night_theme_state where id = 1;
  update night_theme_state
     set previous_colors = v_old.colors,
         previous_name = v_old.name,
         has_previous = true,
         colors = p_colors,
         name = v_name,
         updated_at = now(),
         updated_by = auth.uid()
   where id = 1;
  perform public._admin_log('night_theme.published', 'night_theme_state', '1',
    jsonb_build_object('colors', v_old.colors, 'name', v_old.name),
    jsonb_build_object('colors', p_colors, 'name', v_name));
  return public.night_theme_current();
end $$;
revoke all on function public.admin_night_theme_publish(jsonb, text) from public, anon;
grant execute on function public.admin_night_theme_publish(jsonb, text) to authenticated;

-- Admins: "Əvvəlki temaya qayıt" — the colours published before come
-- back (and the current ones become "before", so it can be undone too).
create or replace function public.admin_night_theme_restore()
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_old night_theme_state;
begin
  perform public._require_admin();
  select * into v_old from night_theme_state where id = 1;
  if not coalesce(v_old.has_previous, false) then raise exception 'nothing_to_restore' using errcode = '22023'; end if;
  update night_theme_state
     set colors = v_old.previous_colors,
         name = v_old.previous_name,
         previous_colors = v_old.colors,
         previous_name = v_old.name,
         updated_at = now(),
         updated_by = auth.uid()
   where id = 1;
  perform public._admin_log('night_theme.restored', 'night_theme_state', '1',
    jsonb_build_object('colors', v_old.colors, 'name', v_old.name),
    jsonb_build_object('colors', v_old.previous_colors, 'name', v_old.previous_name));
  return public.night_theme_current();
end $$;
revoke all on function public.admin_night_theme_restore() from public, anon;
grant execute on function public.admin_night_theme_restore() to authenticated;

-- Final check: everything in place.
do $$
begin
  if to_regclass('public.night_theme_state') is null
     or to_regclass('public.night_themes') is null
     or to_regprocedure('public.night_theme_current()') is null
     or to_regprocedure('public.admin_night_theme_publish(jsonb, text)') is null
     or to_regprocedure('public.admin_night_theme_restore()') is null
     or not exists (select 1 from public.night_theme_state where id = 1) then
    raise exception '0076: final check failed — nothing changed';
  end if;
end $$;

notify pgrst, 'reload schema';

commit;
