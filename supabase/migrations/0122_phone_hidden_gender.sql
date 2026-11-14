-- =====================================================================
-- 0122 — "Telefon nömrəmi gizlət" and Kişi / Qadın (owner, 14.11.2026).
--
-- 1) users.phone_hidden: the user hides his number. While it is on:
--    * the numbers in his TIR Bazarı ads, his service / shop page and his
--      empty truck ads are moved into hidden_ad_phones (nobody reads it but
--      the server) and the ad's own columns are emptied — so no direct read
--      can show them; new / edited ads keep them hidden the same way
--      (a last BEFORE trigger on each table);
--    * get_cargo_contact (loads) and get_user_contact (profile, chat) give
--      no number to others (the owner himself and the admins still see it).
--    Turning it off puts every moved number back where it was (a number the
--    user typed meanwhile is kept). Nothing is lost; TIR parks keep their
--    business phone (owner, 14.11.2026).
--    user_phone_privacy (id, phone_hidden) tells the app to show "Nömrə gizlidir".
-- 2) users.gender ('male' | 'female' | empty): private like the birth date —
--    only the user himself (users_select_own) and the admins read it.
-- Both are written only through my_set_phone_hidden / my_set_gender.
--
-- Safe: forward-only, re-runnable; two columns, one table, functions and
-- triggers. No ad or user row is deleted.
-- =====================================================================

begin;

alter table public.users add column if not exists phone_hidden boolean not null default false;
alter table public.users add column if not exists gender text;
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'users_gender_check') then
    alter table public.users add constraint users_gender_check check (gender is null or gender in ('male', 'female'));
  end if;
end $$;

-- The moved numbers (server only).
create table if not exists public.hidden_ad_phones (
  kind text not null check (kind in ('market', 'service', 'empty_truck')),
  ad_id uuid not null,
  owner_id uuid not null references public.users(id) on delete cascade,
  phone text,
  whatsapp text,
  hidden_at timestamptz not null default now(),
  primary key (kind, ad_id)
);
alter table public.hidden_ad_phones enable row level security;
revoke all on public.hidden_ad_phones from anon, authenticated;

create or replace function public._phone_is_hidden(p_user uuid)
returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce((select phone_hidden from users where id = p_user), false);
$$;
revoke all on function public._phone_is_hidden(uuid) from public, anon, authenticated;

-- 1a) A new / saved ad of a user with a hidden number: the number goes to the store.
create or replace function public._hide_ad_phone()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_kind text := tg_argv[0];
  v_wa text;
begin
  if new.owner_id is null or not public._phone_is_hidden(new.owner_id) then return new; end if;
  if v_kind <> 'market' then   -- TIR Bazarı ads have no WhatsApp column
    v_wa := nullif(btrim(coalesce(new.whatsapp::text, '')), '');
  end if;
  if nullif(btrim(coalesce(new.phone, '')), '') is null and v_wa is null then return new; end if;
  insert into hidden_ad_phones (kind, ad_id, owner_id, phone, whatsapp)
  values (v_kind, new.id, new.owner_id, nullif(btrim(coalesce(new.phone, '')), ''), v_wa)
  on conflict (kind, ad_id) do update set
    phone = coalesce(excluded.phone, hidden_ad_phones.phone),
    whatsapp = coalesce(excluded.whatsapp, hidden_ad_phones.whatsapp),
    hidden_at = now();
  new.phone := null;
  if v_kind <> 'market' then
    new.whatsapp := null;
  end if;
  return new;
end;
$$;
revoke all on function public._hide_ad_phone() from public, anon, authenticated;

drop trigger if exists zzz_hide_phone on public.market_listings;
create trigger zzz_hide_phone before insert or update on public.market_listings
  for each row execute function public._hide_ad_phone('market');
drop trigger if exists zzz_hide_phone on public.service_providers;
create trigger zzz_hide_phone before insert or update on public.service_providers
  for each row execute function public._hide_ad_phone('service');
drop trigger if exists zzz_hide_phone on public.empty_truck_ads;
create trigger zzz_hide_phone before insert or update on public.empty_truck_ads
  for each row execute function public._hide_ad_phone('empty_truck');

-- 1b) The switch.
create or replace function public.my_set_phone_hidden(p_hidden boolean)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if p_hidden is null then raise exception 'invalid_argument' using errcode = '22023'; end if;
  update users set phone_hidden = p_hidden, updated_at = now() where id = v_uid;
  perform set_config('app.market_trusted', '1', true);
  if p_hidden then
    -- Touching the rows lets the trigger above move the numbers.
    update market_listings set phone = phone where owner_id = v_uid and phone is not null;
    update service_providers set phone = phone where owner_id = v_uid and (phone is not null or whatsapp is not null);
    update empty_truck_ads set phone = phone where owner_id = v_uid and (phone is not null or whatsapp is not null);
  else
    update market_listings m set phone = coalesce(m.phone, h.phone)
      from hidden_ad_phones h where h.kind = 'market' and h.ad_id = m.id and h.owner_id = v_uid;
    update service_providers s set phone = coalesce(s.phone, h.phone), whatsapp = coalesce(s.whatsapp, h.whatsapp)
      from hidden_ad_phones h where h.kind = 'service' and h.ad_id = s.id and h.owner_id = v_uid;
    update empty_truck_ads e set phone = coalesce(e.phone, h.phone), whatsapp = coalesce(e.whatsapp, h.whatsapp)
      from hidden_ad_phones h where h.kind = 'empty_truck' and h.ad_id = e.id and h.owner_id = v_uid;
    delete from hidden_ad_phones where owner_id = v_uid;
  end if;
end;
$$;
revoke all on function public.my_set_phone_hidden(boolean) from public, anon;
grant execute on function public.my_set_phone_hidden(boolean) to authenticated;

create or replace function public.my_set_gender(p_gender text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if p_gender is not null and p_gender not in ('male', 'female') then
    raise exception 'invalid_argument' using errcode = '22023';
  end if;
  update users set gender = p_gender, updated_at = now() where id = auth.uid();
end;
$$;
revoke all on function public.my_set_gender(text) from public, anon;
grant execute on function public.my_set_gender(text) to authenticated;

-- 1c) Loads: no number for others while hidden (0060 + this check).
create or replace function public.get_cargo_contact(p_cargo uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := auth.uid();
  v_c public.cargo;
  v_u public.users;
  v_show boolean;
begin
  if v_me is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  select * into v_c from public.cargo where id = p_cargo;
  if not found then
    return null;
  end if;
  if not (not v_c.is_hidden or v_c.owner_id = v_me or public.is_admin()
          or public.can_see_hidden_cargo(p_cargo)) then
    return null;                               -- caller cannot see this load
  end if;
  if v_c.owner_id <> v_me and not public.is_admin() and public.is_blocked(v_me) then
    return null;
  end if;
  select * into v_u from public.users where id = v_c.owner_id;
  v_show := not coalesce(v_u.phone_hidden, false) or v_c.owner_id = v_me or public.is_admin();
  return jsonb_build_object(
    'owner_id',      v_c.owner_id,
    'full_name',     v_u.full_name,
    'phone',         case when v_show then v_u.phone end,
    'email',         v_u.email,
    'phone_hidden',  not v_show,
    'contact_phone', case when v_show then (select k.phone from public.cargo_contacts k where k.cargo_id = p_cargo) end);
end;
$$;
revoke execute on function public.get_cargo_contact(uuid) from public, anon;
grant execute on function public.get_cargo_contact(uuid) to authenticated, service_role;

-- 1d) Profile / chat contact (0019 + the hidden check).
create or replace function public.get_user_contact(p_user uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := auth.uid();
  v_u public.users;
  v_reason text;
  v_full boolean := false;
begin
  if v_me is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  select * into v_u from public.users where id = p_user;
  if not found then
    return null;
  end if;

  if p_user = v_me then
    v_reason := 'self'; v_full := true;
  elsif public.is_admin() then
    v_reason := 'admin'; v_full := true;
  elsif public.is_blocked(v_me) then
    v_reason := null;
  elsif exists (
      select 1 from public.contact_unlocks cu
      join public.cargo c on c.id = cu.cargo_id
      where cu.carrier_id = public.current_carrier_id() and c.owner_id = p_user) then
    v_reason := 'unlocked'; v_full := true;
  elsif exists (
      select 1 from public.messages m
      where m.sender_id = p_user and m.receiver_id = v_me) then
    v_reason := 'messaged_you';
  elsif exists (
      select 1 from public.ads a
      where a.advertiser_id = p_user and a.is_active
        and now() >= a.starts_at and now() < a.ends_at) then
    v_reason := 'advertiser';
  elsif exists (
      select 1 from public.cargo c
      where c.owner_id = p_user and c.status = 'new' and not c.is_hidden) then
    -- has a published, open load: the phone is already shown on that
    -- load (get_cargo_contact), so the profile's call button may show it
    v_reason := 'open_load';
  end if;

  -- 0122: a hidden number is shown only to its owner and the admins.
  if coalesce(v_u.phone_hidden, false) and v_reason not in ('self', 'admin') then
    v_reason := null;
  end if;

  return jsonb_build_object(
    'full_name', v_u.full_name,
    'phone',     case when v_reason is not null then v_u.phone end,
    'email',     case when v_full then v_u.email end,
    'reason',    v_reason);
end;
$$;

revoke execute on function public.get_user_contact(uuid) from public, anon;
grant execute on function public.get_user_contact(uuid) to authenticated, service_role;

-- 1e) The app shows "Nömrə gizlidir": only a yes / no per user, never the number
-- (a view of its own; user_profiles stays exactly as 0105 left it).
create or replace view public.user_phone_privacy
with (security_barrier = true) as
  select u.id, u.phone_hidden from public.users u;
revoke all on public.user_phone_privacy from public, anon, authenticated;
grant select on public.user_phone_privacy to authenticated, anon, service_role;

commit;

notify pgrst, 'reload schema';
