-- =====================================================================
-- 0123 — a hidden phone is seen only by its owner and the Baş admin
-- (owner, 14.11.2026: "gizli etməyi aktiv seçdikdən sonra məlumatları
-- sadəcə Baş admin görə bilsin").
--
-- 0122 hid the number from other users; admins could still read it
-- (users_admin_full, the ad tables, get_*_contact). Now, while
-- users.phone_hidden is on:
--   * the account's own number (users.phone) moves into hidden_user_phones
--     (no grants, server only); users.phone stays empty, so no admin page,
--     list or search shows it; a number saved meanwhile goes there too, and
--     a number taken there cannot be used by another account (23505);
--   * the load's own number (cargo_contacts) and the İş Mərkəzi phones
--     (job_seeker_profiles, job_vacancies) move into hidden_ad_phones like
--     the other ads (0122);
--   * get_cargo_contact / get_user_contact give the number only to its
--     owner and the Baş admin (is_chief_admin, 0104) — no longer to every
--     admin;
--   * my_phone(): the owner reads his own number (Şəxsi məlumatlarım);
--   * admin_hidden_phones(user): the Baş admin only, every look logged in
--     the Audit Log.
-- Turning hiding off puts every number back (a number typed meanwhile is
-- kept). An account deleting itself frees its number.
--
-- Safe: forward-only, re-runnable; one table, functions and triggers. No
-- user or ad row is deleted; only rows of the private stores move.
-- =====================================================================

begin;

-- The account's own number while hidden (server only).
create table if not exists public.hidden_user_phones (
  user_id uuid primary key references public.users(id) on delete cascade,
  phone text not null unique,
  hidden_at timestamptz not null default now()
);
alter table public.hidden_user_phones enable row level security;
revoke all on public.hidden_user_phones from anon, authenticated;

-- More kinds of ads keep their numbers in the 0122 store.
alter table public.hidden_ad_phones drop constraint if exists hidden_ad_phones_kind_check;
alter table public.hidden_ad_phones add constraint hidden_ad_phones_kind_check
  check (kind in ('market', 'service', 'empty_truck', 'cargo', 'job_seeker', 'job_vacancy'));

-- 1) users.phone while hidden → hidden_user_phones.
create or replace function public._users_hide_phone()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
declare v_phone text := nullif(btrim(coalesce(new.phone, '')), '');
begin
  -- An account that deleted itself frees its number (0119).
  if new.block_reason is not distinct from 'self_deleted' then
    delete from hidden_user_phones where user_id = new.id;
    return new;
  end if;
  -- A number kept hidden by another account is taken.
  if v_phone is not null and exists (select 1 from hidden_user_phones h where h.phone = v_phone and h.user_id <> new.id) then
    raise exception 'phone_taken' using errcode = '23505';
  end if;
  if coalesce(new.phone_hidden, false) then
    if v_phone is not null then
      insert into hidden_user_phones (user_id, phone) values (new.id, v_phone)
      on conflict (user_id) do update set phone = excluded.phone, hidden_at = now();
    end if;
    new.phone := null;
  end if;
  return new;
end;
$$;
revoke all on function public._users_hide_phone() from public, anon, authenticated;
drop trigger if exists zzz_users_hide_phone on public.users;
create trigger zzz_users_hide_phone before insert or update on public.users
  for each row execute function public._users_hide_phone();

-- 2) Every ad table: one generic mover (0122's, now for any owner column
--    and any WhatsApp kind — İş Mərkəzi's WhatsApp is only a yes / no).
create or replace function public._hide_ad_phone()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_kind text := tg_argv[0];
  v_row jsonb := to_jsonb(new);
  v_owner uuid := coalesce(v_row->>'owner_id', v_row->>'user_id')::uuid;
  v_id uuid := coalesce(v_row->>'id', v_row->>'user_id')::uuid;
  v_phone text := nullif(btrim(coalesce(v_row->>'phone', '')), '');
  v_wa text;
begin
  if v_owner is null or not public._phone_is_hidden(v_owner) then return new; end if;
  if jsonb_typeof(v_row->'whatsapp') = 'string' then
    v_wa := nullif(btrim(v_row->>'whatsapp'), '');
  end if;
  if v_phone is null and v_wa is null then return new; end if;
  insert into hidden_ad_phones (kind, ad_id, owner_id, phone, whatsapp)
  values (v_kind, v_id, v_owner, v_phone, v_wa)
  on conflict (kind, ad_id) do update set
    phone = coalesce(excluded.phone, hidden_ad_phones.phone),
    whatsapp = coalesce(excluded.whatsapp, hidden_ad_phones.whatsapp),
    hidden_at = now();
  if v_wa is not null then
    new := jsonb_populate_record(new, jsonb_build_object('phone', null, 'whatsapp', null));
  else
    new := jsonb_populate_record(new, jsonb_build_object('phone', null));
  end if;
  return new;
end;
$$;
revoke all on function public._hide_ad_phone() from public, anon, authenticated;

do $$
begin
  if to_regclass('public.job_seeker_profiles') is not null then
    execute 'drop trigger if exists zzz_hide_phone on public.job_seeker_profiles';
    execute 'create trigger zzz_hide_phone before insert or update on public.job_seeker_profiles
             for each row execute function public._hide_ad_phone(''job_seeker'')';
  end if;
  if to_regclass('public.job_vacancies') is not null then
    execute 'drop trigger if exists zzz_hide_phone on public.job_vacancies';
    execute 'create trigger zzz_hide_phone before insert or update on public.job_vacancies
             for each row execute function public._hide_ad_phone(''job_vacancy'')';
  end if;
end $$;

-- A load's own number (cargo_contacts.phone is required): while hidden the
-- row is kept in the store instead of the table.
create or replace function public._hide_cargo_contact()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
declare v_owner uuid;
begin
  select owner_id into v_owner from cargo where id = new.cargo_id;
  if v_owner is null or not public._phone_is_hidden(v_owner) then return new; end if;
  insert into hidden_ad_phones (kind, ad_id, owner_id, phone)
  values ('cargo', new.cargo_id, v_owner, new.phone)
  on conflict (kind, ad_id) do update set phone = excluded.phone, hidden_at = now();
  if tg_op = 'UPDATE' then
    delete from cargo_contacts where cargo_id = old.cargo_id;
  end if;
  return null;   -- not written to cargo_contacts
end;
$$;
revoke all on function public._hide_cargo_contact() from public, anon, authenticated;
drop trigger if exists zzz_hide_phone on public.cargo_contacts;
create trigger zzz_hide_phone before insert or update on public.cargo_contacts
  for each row execute function public._hide_cargo_contact();

-- 3) The switch (0122 + the account's number, loads and İş Mərkəzi).
create or replace function public.my_set_phone_hidden(p_hidden boolean)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if p_hidden is null then raise exception 'invalid_argument' using errcode = '22023'; end if;
  perform set_config('app.market_trusted', '1', true);
  if p_hidden then
    -- The trigger moves users.phone.
    update users set phone_hidden = true, updated_at = now() where id = v_uid;
    update market_listings set phone = phone where owner_id = v_uid and phone is not null;
    update service_providers set phone = phone where owner_id = v_uid and (phone is not null or whatsapp is not null);
    update empty_truck_ads set phone = phone where owner_id = v_uid and (phone is not null or whatsapp is not null);
    if to_regclass('public.job_seeker_profiles') is not null then
      execute 'update public.job_seeker_profiles set phone = phone where user_id = $1 and phone is not null' using v_uid;
    end if;
    if to_regclass('public.job_vacancies') is not null then
      execute 'update public.job_vacancies set phone = phone where owner_id = $1 and phone is not null' using v_uid;
    end if;
    insert into hidden_ad_phones (kind, ad_id, owner_id, phone)
      select 'cargo', k.cargo_id, v_uid, k.phone
      from cargo_contacts k join cargo c on c.id = k.cargo_id
      where c.owner_id = v_uid
    on conflict (kind, ad_id) do update set phone = excluded.phone, hidden_at = now();
    delete from cargo_contacts k using cargo c where c.id = k.cargo_id and c.owner_id = v_uid;
  else
    update users u set phone_hidden = false, updated_at = now(),
      phone = coalesce(u.phone, (select h.phone from hidden_user_phones h where h.user_id = v_uid))
    where u.id = v_uid;
    delete from hidden_user_phones where user_id = v_uid;
    update market_listings m set phone = coalesce(m.phone, h.phone)
      from hidden_ad_phones h where h.kind = 'market' and h.ad_id = m.id and h.owner_id = v_uid;
    update service_providers s set phone = coalesce(s.phone, h.phone), whatsapp = coalesce(s.whatsapp, h.whatsapp)
      from hidden_ad_phones h where h.kind = 'service' and h.ad_id = s.id and h.owner_id = v_uid;
    update empty_truck_ads e set phone = coalesce(e.phone, h.phone), whatsapp = coalesce(e.whatsapp, h.whatsapp)
      from hidden_ad_phones h where h.kind = 'empty_truck' and h.ad_id = e.id and h.owner_id = v_uid;
    if to_regclass('public.job_seeker_profiles') is not null then
      execute 'update public.job_seeker_profiles j set phone = coalesce(j.phone, h.phone)
               from public.hidden_ad_phones h where h.kind = ''job_seeker'' and h.ad_id = j.user_id and h.owner_id = $1' using v_uid;
    end if;
    if to_regclass('public.job_vacancies') is not null then
      execute 'update public.job_vacancies j set phone = coalesce(j.phone, h.phone)
               from public.hidden_ad_phones h where h.kind = ''job_vacancy'' and h.ad_id = j.id and h.owner_id = $1' using v_uid;
    end if;
    insert into cargo_contacts (cargo_id, phone)
      select h.ad_id, h.phone from hidden_ad_phones h
      where h.kind = 'cargo' and h.owner_id = v_uid and h.phone is not null
        and exists (select 1 from cargo c where c.id = h.ad_id)
    on conflict (cargo_id) do nothing;
    delete from hidden_ad_phones where owner_id = v_uid;
  end if;
end;
$$;
revoke all on function public.my_set_phone_hidden(boolean) from public, anon;
grant execute on function public.my_set_phone_hidden(boolean) to authenticated;

-- 4) The owner's own number (Şəxsi məlumatlarım), hidden or not.
create or replace function public.my_phone()
returns text language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(u.phone, (select h.phone from hidden_user_phones h where h.user_id = u.id))
  from users u where u.id = auth.uid();
$$;
revoke all on function public.my_phone() from public, anon;
grant execute on function public.my_phone() to authenticated;

-- 5) The Baş admin looks at a hidden number (logged).
create or replace function public.admin_hidden_phones(p_user uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v jsonb;
begin
  if not public.is_chief_admin() then raise exception 'chief_admin_only' using errcode = '42501'; end if;
  select jsonb_build_object(
    'phone', (select h.phone from hidden_user_phones h where h.user_id = p_user),
    'ads', coalesce((select jsonb_agg(jsonb_build_object('kind', a.kind, 'ad_id', a.ad_id,
                                                         'phone', a.phone, 'whatsapp', a.whatsapp)
                                      order by a.kind, a.hidden_at)
                     from hidden_ad_phones a where a.owner_id = p_user), '[]'::jsonb))
  into v;
  perform public._admin_log('phone.view_hidden', 'user', p_user::text, null, null, null);
  return v;
end;
$$;
revoke all on function public.admin_hidden_phones(uuid) from public, anon;
grant execute on function public.admin_hidden_phones(uuid) to authenticated;

-- 6) Loads: a hidden number only for its owner and the Baş admin.
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
  v_hidden boolean;
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
  v_hidden := coalesce(v_u.phone_hidden, false);
  v_show := not v_hidden or v_c.owner_id = v_me or public.is_chief_admin();
  return jsonb_build_object(
    'owner_id',      v_c.owner_id,
    'full_name',     v_u.full_name,
    'phone',         case when v_show then coalesce(v_u.phone,
                       (select h.phone from public.hidden_user_phones h where h.user_id = v_u.id)) end,
    'email',         v_u.email,
    'phone_hidden',  not v_show,
    'contact_phone', case when v_show then coalesce(
                       (select k.phone from public.cargo_contacts k where k.cargo_id = p_cargo),
                       (select h.phone from public.hidden_ad_phones h where h.kind = 'cargo' and h.ad_id = p_cargo)) end);
end;
$$;
revoke execute on function public.get_cargo_contact(uuid) from public, anon;
grant execute on function public.get_cargo_contact(uuid) to authenticated, service_role;

-- 7) Profile / chat contact (0122 + only the Baş admin among the admins).
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
    v_reason := 'open_load';
  end if;

  -- A hidden number: only its owner and the Baş admin (0123).
  if coalesce(v_u.phone_hidden, false) and v_reason is not null
     and not (v_reason = 'self' or (v_reason = 'admin' and public.is_chief_admin())) then
    v_reason := null;
  end if;

  return jsonb_build_object(
    'full_name', v_u.full_name,
    'phone',     case when v_reason is not null then coalesce(v_u.phone,
                   (select h.phone from public.hidden_user_phones h where h.user_id = v_u.id)) end,
    'email',     case when v_full then v_u.email end,
    'reason',    v_reason);
end;
$$;
revoke execute on function public.get_user_contact(uuid) from public, anon;
grant execute on function public.get_user_contact(uuid) to authenticated, service_role;

-- 8) Accounts that already hid their number (0122): move it now. Touching
--    the row lets the trigger above do it; the ads were moved by 0122, the
--    loads' and İş Mərkəzi's numbers are moved here.
do $$
declare r record;
begin
  perform set_config('app.market_trusted', '1', true);
  for r in select id from public.users where phone_hidden and phone is not null loop
    update public.users set phone = phone where id = r.id;
  end loop;
  for r in select id from public.users where phone_hidden loop
    insert into public.hidden_ad_phones (kind, ad_id, owner_id, phone)
      select 'cargo', k.cargo_id, r.id, k.phone
      from public.cargo_contacts k join public.cargo c on c.id = k.cargo_id
      where c.owner_id = r.id
    on conflict (kind, ad_id) do update set phone = excluded.phone;
    delete from public.cargo_contacts k using public.cargo c where c.id = k.cargo_id and c.owner_id = r.id;
    if to_regclass('public.job_seeker_profiles') is not null then
      execute 'update public.job_seeker_profiles set phone = phone where user_id = $1 and phone is not null' using r.id;
    end if;
    if to_regclass('public.job_vacancies') is not null then
      execute 'update public.job_vacancies set phone = phone where owner_id = $1 and phone is not null' using r.id;
    end if;
  end loop;
end $$;

commit;

notify pgrst, 'reload schema';
