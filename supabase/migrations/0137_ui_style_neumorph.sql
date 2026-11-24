-- =====================================================================
-- 0137 — "Neumorf" look for the whole app (owner, 24.11.2026: "bu reng
-- tonlari ve kartla dizayn et … Dizayn və Rənglər bölməsindən aktiv edilə
-- və söndürülə bilsin … gecə və gündüz rejimlərində").
--
-- * ui_style_state (one row): neumorph on / off — the app draws the soft
--   grey neumorphic cards, buttons and fields with the orange accent, at
--   night AND by day. Off (the default) = the app exactly as before.
-- * ui_style_current(): read by everybody (also before sign-in).
-- * admin_ui_style_set(p_neumorph): admins only, logged in the Audit Log.
--
-- Safe: forward-only, re-runnable. One new one-row table, two functions.
-- Nothing else changes; nothing is deleted.
-- =====================================================================

begin;

create table if not exists public.ui_style_state (
  id integer primary key default 1 check (id = 1),
  neumorph boolean not null default false,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.users(id) on delete set null
);
insert into public.ui_style_state (id) values (1) on conflict (id) do nothing;

alter table public.ui_style_state enable row level security;
revoke all on public.ui_style_state from anon, authenticated;

create or replace function public.ui_style_current()
returns jsonb language sql stable security definer set search_path = public, pg_temp as $$
  select jsonb_build_object('neumorph', coalesce(s.neumorph, false), 'updated_at', s.updated_at)
    from (select 1) one
    left join public.ui_style_state s on s.id = 1;
$$;
revoke all on function public.ui_style_current() from public;
grant execute on function public.ui_style_current() to anon, authenticated;

create or replace function public.admin_ui_style_set(p_neumorph boolean)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_old boolean;
begin
  perform public._require_admin();
  if p_neumorph is null then raise exception 'invalid_argument' using errcode = '22023'; end if;
  select neumorph into v_old from ui_style_state where id = 1;
  update ui_style_state set neumorph = p_neumorph, updated_at = now(), updated_by = auth.uid() where id = 1;
  perform public._admin_log('ui_style.neumorph', 'ui_style_state', '1',
    jsonb_build_object('neumorph', v_old), jsonb_build_object('neumorph', p_neumorph));
end $$;
revoke all on function public.admin_ui_style_set(boolean) from public, anon;
grant execute on function public.admin_ui_style_set(boolean) to authenticated;

-- Final check: everything in place.
do $$
begin
  if to_regclass('public.ui_style_state') is null
     or to_regprocedure('public.ui_style_current()') is null
     or to_regprocedure('public.admin_ui_style_set(boolean)') is null
     or not exists (select 1 from public.ui_style_state where id = 1) then
    raise exception '0137: final check failed — nothing changed';
  end if;
end $$;

commit;

notify pgrst, 'reload schema';
