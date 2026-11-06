-- =====================================================================
-- 0100 — (owner, 07.11.2026)
-- 1) Users no longer add parking spots / parks on the map. The function
--    tir_park_add stays (old app versions get a clear answer) but refuses
--    every call with 'not_available'. Nothing else makes a park: the park
--    owner's request ("Park işlədirəm", tir_park_owner_apply → admin) and
--    the manager application (tir_park_manage_apply → admin) are untouched.
--    Users never had a direct INSERT grant on tir_parks (0077).
-- 2) "Mesaj yaz" on a service / shop page opens a chat that remembers the
--    page: conversations.service_id + the page's name and kind ('service' |
--    'shop'), set only by the server (get_or_create_service_conversation).
--    The receiver is still the page's owner. The person-to-person chat
--    (get_or_create_direct_conversation) never returns a page chat, so
--    existing chats are neither merged nor changed.
-- 3) Google / Apple sign-in: the new account's name is taken from the
--    provider's full_name or name (handle_new_auth_user, as in 0074).
-- Safe: forward-only, re-runnable; three nullable columns, one new
-- function, three replaced functions, one replaced policy. No row is
-- changed or deleted.
-- =====================================================================

-- 1) No more user-added spots.
create or replace function public.tir_park_add(
  p_name text, p_lat double precision, p_lng double precision,
  p_city text default null, p_amenities text[] default '{}', p_note text default null)
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  -- 0100: parking spots are no longer added by users (owner, 07.11.2026).
  raise exception 'not_available' using errcode = '42501';
end $$;
revoke all on function public.tir_park_add(text, double precision, double precision, text, text[], text) from public, anon;
grant execute on function public.tir_park_add(text, double precision, double precision, text, text[], text) to authenticated;

-- 2) The page a chat started from.
alter table public.conversations add column if not exists service_id uuid references public.service_providers(id) on delete set null;
alter table public.conversations add column if not exists service_name text;
alter table public.conversations add column if not exists service_kind text;
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'conversations_service_kind_check') then
    alter table public.conversations add constraint conversations_service_kind_check
      check (service_kind is null or service_kind in ('service', 'shop'));
  end if;
end $$;
create index if not exists idx_conversations_service on public.conversations(service_id) where service_id is not null;

-- A user's own insert never carries a page (only the function below does).
drop policy if exists "conversations_create" on public.conversations;
create policy "conversations_create" on public.conversations
  for insert to authenticated
  with check (
    (auth.uid() = cargo_owner_id or auth.uid() = carrier_user_id)
    and cargo_owner_id <> carrier_user_id
    and (cargo_id is null or cargo_owner_id = (select c.owner_id from public.cargo c where c.id = cargo_id))
    and service_id is null and service_name is null and service_kind is null
  );

-- The person-to-person chat: never a page chat.
create or replace function public.get_or_create_direct_conversation(p_other uuid)
returns public.conversations
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := auth.uid();
  v_conv public.conversations;
begin
  if v_me is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_other is null or p_other = v_me then
    raise exception 'invalid_user' using errcode = '22023';
  end if;
  if not exists (select 1 from public.users where id = p_other) then
    raise exception 'user_not_found' using errcode = 'P0002';
  end if;
  -- one direct chat per pair, even with two simultaneous taps
  perform pg_advisory_xact_lock(hashtext(least(v_me, p_other)::text || greatest(v_me, p_other)::text));

  select * into v_conv from public.conversations c
  where c.cargo_id is null and c.shipment_id is null and c.service_id is null
    and ((c.cargo_owner_id = v_me and c.carrier_user_id = p_other)
      or (c.cargo_owner_id = p_other and c.carrier_user_id = v_me))
  order by c.created_at
  limit 1;

  if v_conv.id is null then
    insert into public.conversations (cargo_id, cargo_owner_id, carrier_user_id)
    values (null, v_me, p_other)
    returning * into v_conv;
  end if;
  return v_conv;
end;
$$;
grant execute on function public.get_or_create_direct_conversation(uuid) to authenticated;

-- "Mesaj yaz" on a service / shop page: one chat per writer and page; the
-- receiver is the page's owner; the page's name and kind are the server's.
create or replace function public.get_or_create_service_conversation(p_service uuid)
returns public.conversations
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := auth.uid();
  v_svc public.service_providers;
  v_kind text;
  v_conv public.conversations;
begin
  if v_me is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  select * into v_svc from public.service_providers where id = p_service;
  if v_svc.id is null or v_svc.owner_id is null
     or (v_svc.status <> 'approved' and v_svc.owner_id <> v_me and not public.is_admin()) then
    raise exception 'not_found' using errcode = 'P0002';
  end if;
  if v_svc.owner_id = v_me then
    raise exception 'invalid_user' using errcode = '22023';   -- one's own page
  end if;
  v_kind := case when 'spare_parts' = any (v_svc.categories)
                  and not exists (select 1 from unnest(v_svc.categories) c where c <> 'spare_parts' and c not like 'shop\_%')
                 then 'shop' else 'service' end;

  perform pg_advisory_xact_lock(hashtext(v_me::text || p_service::text));
  select * into v_conv from public.conversations c
   where c.service_id = p_service and c.cargo_id is null and c.shipment_id is null
     and ((c.cargo_owner_id = v_me and c.carrier_user_id = v_svc.owner_id)
       or (c.cargo_owner_id = v_svc.owner_id and c.carrier_user_id = v_me))
   order by c.created_at
   limit 1;

  if v_conv.id is null then
    insert into public.conversations (cargo_id, cargo_owner_id, carrier_user_id, service_id, service_name, service_kind)
    values (null, v_me, v_svc.owner_id, p_service, v_svc.name, v_kind)
    returning * into v_conv;
  elsif v_conv.service_name is distinct from v_svc.name or v_conv.service_kind is distinct from v_kind then
    update public.conversations set service_name = v_svc.name, service_kind = v_kind
     where id = v_conv.id
     returning * into v_conv;
  end if;
  return v_conv;
end;
$$;
revoke all on function public.get_or_create_service_conversation(uuid) from public, anon;
grant execute on function public.get_or_create_service_conversation(uuid) to authenticated;

-- 3) Google / Apple sign-in (OAuth): the new account's public.users row
-- takes the name from full_name or name (unchanged otherwise, 0074).
create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_role text := new.raw_user_meta_data->>'role';
  v_birth_text text := new.raw_user_meta_data->>'birth_date';
  v_birth date;
begin
  -- Only self-service roles are accepted from signup metadata.
  -- 'admin' (or anything unknown) silently becomes the default role.
  if v_role is null or v_role not in ('cargo_owner', 'carrier', 'driver') then
    v_role := 'cargo_owner';
  end if;
  if v_birth_text ~ '^\d{4}-\d{2}-\d{2}$' then
    begin
      v_birth := v_birth_text::date;
    exception when others then
      v_birth := null;
    end;
    if v_birth > (current_date - interval '16 years')::date
       or v_birth < (current_date - interval '100 years')::date then
      v_birth := null;
    end if;
  end if;
  insert into public.users (id, email, full_name, role, phone, birth_date)
  values (
    new.id,
    new.email,
    -- 0100: Google / Apple give the name as full_name or name.
    coalesce(nullif(new.raw_user_meta_data->>'full_name', ''), nullif(new.raw_user_meta_data->>'name', ''), ''),
    v_role,
    new.raw_user_meta_data->>'phone',
    v_birth
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

notify pgrst, 'reload schema';
