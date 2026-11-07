-- =====================================================================
-- 0106 — "Bəyəndiklərim" everywhere (owner, 07.11.2026).
--
-- Loads (cargo_favorites, 0058) and TIR Bazarı ads (market_favorites,
-- 0040) keep their own tables, unchanged. New here, in one table:
--   * 'chat'    — a chat with a person (the Mesajlar row of that person;
--                 target = the other user): only someone I have a chat with;
--   * 'user'    — a person's profile page;
--   * 'service' — a service / shop page (approved);
--   * 'park'    — a TIR park page (approved).
-- Only the owner reads them; writes go through favorite_set (checks what
-- the target is), so nobody fakes or sees anybody else's list. Removing a
-- favourite deletes only that one own row (never the chat / profile).
--
-- Safe: forward-only, re-runnable; one new table, two functions. No other
-- row is changed.
-- =====================================================================

begin;

create table if not exists public.user_favorites (
  user_id uuid not null references public.users(id) on delete cascade,
  kind text not null check (kind in ('chat', 'user', 'service', 'park')),
  target_id uuid not null,
  created_at timestamptz not null default now(),
  primary key (user_id, kind, target_id)
);
create index if not exists user_favorites_user_idx on public.user_favorites (user_id, created_at desc);
alter table public.user_favorites enable row level security;
revoke all on public.user_favorites from anon, authenticated;
grant select on public.user_favorites to authenticated;
drop policy if exists "user_favorites_own" on public.user_favorites;
create policy "user_favorites_own" on public.user_favorites for select to authenticated
  using (user_id = (select auth.uid()));

-- Heart on / off (true = now a favourite).
create or replace function public.favorite_set(p_kind text, p_id uuid, p_on boolean)
returns boolean language plpgsql security definer set search_path = public, pg_temp as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if p_kind is null or p_kind not in ('chat', 'user', 'service', 'park') or p_id is null or p_on is null then
    raise exception 'invalid_argument' using errcode = '22023';
  end if;
  if not p_on then
    delete from user_favorites where user_id = v_uid and kind = p_kind and target_id = p_id;
    return false;
  end if;
  if p_kind = 'chat' and not exists (
       select 1 from conversations c
        where (c.cargo_owner_id = v_uid and c.carrier_user_id = p_id)
           or (c.carrier_user_id = v_uid and c.cargo_owner_id = p_id)) then
    raise exception 'not_found' using errcode = 'P0002';
  elsif p_kind = 'user' and (p_id = v_uid or not exists (select 1 from users u where u.id = p_id)) then
    raise exception 'not_found' using errcode = 'P0002';
  elsif p_kind = 'service' and not exists (select 1 from service_providers s where s.id = p_id and s.status = 'approved') then
    raise exception 'not_found' using errcode = 'P0002';
  elsif p_kind = 'park' and not exists (select 1 from tir_parks t where t.id = p_id and t.status = 'approved') then
    raise exception 'not_found' using errcode = 'P0002';
  end if;
  insert into user_favorites (user_id, kind, target_id) values (v_uid, p_kind, p_id)
  on conflict (user_id, kind, target_id) do nothing;
  return true;
end $$;
revoke all on function public.favorite_set(text, uuid, boolean) from public, anon;
grant execute on function public.favorite_set(text, uuid, boolean) to authenticated;

commit;

notify pgrst, 'reload schema';
