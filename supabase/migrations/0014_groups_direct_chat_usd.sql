-- =====================================================================
-- 0014 — Group chats, direct (person-to-person) chats, USD default.
-- SAFE FORWARD MIGRATION: only ADDs tables / functions / policies and
-- changes column DEFAULTS. No existing row is changed or deleted.
-- Idempotent (safe to run twice).
-- =====================================================================

-- 1) Prices in US dollars by default ---------------------------------
-- Only the default for NEW rows changes; existing loads keep the
-- currency they were saved with.
alter table public.cargo     alter column currency set default 'USD';
alter table public.offers    alter column currency set default 'USD';
alter table public.shipments alter column currency set default 'USD';
alter table public.payments  alter column currency set default 'USD';

-- 2) Direct chat with any user (not tied to a load) --------------------
-- Stored as a normal conversation with cargo_id = null, so the existing
-- message, read-receipt, attachment and RLS rules apply unchanged.
create or replace function public.get_or_create_direct_conversation(p_other uuid)
returns public.conversations
language plpgsql
security definer
set search_path = public
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
  where c.cargo_id is null and c.shipment_id is null
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

-- 3) Group chats --------------------------------------------------------
create table if not exists public.chat_groups (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(btrim(name)) between 1 and 80),
  created_by uuid not null references public.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.chat_group_members (
  group_id uuid not null references public.chat_groups(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  is_admin boolean not null default false,
  added_by uuid references public.users(id) on delete set null,
  last_read_at timestamptz not null default now(),
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);
create index if not exists idx_chat_group_members_user on public.chat_group_members(user_id);

create table if not exists public.group_messages (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.chat_groups(id) on delete cascade,
  sender_id uuid not null references public.users(id) on delete cascade,
  message text,
  attachment_path text,
  attachment_type text check (attachment_type is null or attachment_type in ('image','file','audio')),
  attachment_name text,
  attachment_size bigint,
  audio_duration_ms integer,
  created_at timestamptz not null default now(),
  check (message is not null or attachment_path is not null)
);
create index if not exists idx_group_messages_group on public.group_messages(group_id, created_at);

-- membership helpers (SECURITY DEFINER: no RLS recursion)
create or replace function public.is_group_member(p_group uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.chat_group_members m where m.group_id = p_group and m.user_id = auth.uid());
$$;
create or replace function public.is_group_admin(p_group uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.chat_group_members m where m.group_id = p_group and m.user_id = auth.uid() and m.is_admin);
$$;
create or replace function public.is_group_member_text(p_group text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.chat_group_members m where m.group_id::text = p_group and m.user_id = auth.uid());
$$;
grant execute on function public.is_group_member(uuid) to authenticated;
grant execute on function public.is_group_admin(uuid) to authenticated;
grant execute on function public.is_group_member_text(text) to authenticated;

alter table public.chat_groups enable row level security;
alter table public.chat_group_members enable row level security;
alter table public.group_messages enable row level security;

-- Reads: members only (admins of the platform too). All membership
-- WRITES go through the functions below.
drop policy if exists "chat_groups_member_select" on public.chat_groups;
create policy "chat_groups_member_select" on public.chat_groups
  for select to authenticated using (public.is_group_member(id) or public.is_admin());

drop policy if exists "chat_group_members_member_select" on public.chat_group_members;
create policy "chat_group_members_member_select" on public.chat_group_members
  for select to authenticated using (public.is_group_member(group_id) or public.is_admin());

drop policy if exists "group_messages_member_select" on public.group_messages;
create policy "group_messages_member_select" on public.group_messages
  for select to authenticated using (public.is_group_member(group_id) or public.is_admin());

drop policy if exists "group_messages_member_insert" on public.group_messages;
create policy "group_messages_member_insert" on public.group_messages
  for insert to authenticated
  with check (sender_id = auth.uid() and public.is_group_member(group_id));

-- blocked / deactivated accounts can't post in groups either (0012)
drop trigger if exists assert_not_blocked on public.group_messages;
create trigger assert_not_blocked before insert on public.group_messages
  for each row execute function public.assert_not_blocked();

-- Create a group: the creator becomes its admin; chosen people are added.
create or replace function public.create_chat_group(p_name text, p_members uuid[])
returns public.chat_groups
language plpgsql security definer set search_path = public as $$
declare v_group public.chat_groups;
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if public.is_blocked(auth.uid()) then raise exception 'account_blocked' using errcode = '42501'; end if;
  if p_name is null or char_length(btrim(p_name)) = 0 then raise exception 'invalid_name' using errcode = '22023'; end if;
  insert into chat_groups (name, created_by) values (left(btrim(p_name), 80), auth.uid()) returning * into v_group;
  insert into chat_group_members (group_id, user_id, is_admin, added_by)
  values (v_group.id, auth.uid(), true, auth.uid());
  insert into chat_group_members (group_id, user_id, added_by)
  select v_group.id, u.id, auth.uid()
  from users u
  where u.id = any(coalesce(p_members, '{}'::uuid[])) and u.id <> auth.uid()
  on conflict do nothing;
  return v_group;
end;
$$;

-- Add people (group admins only).
create or replace function public.add_chat_group_members(p_group uuid, p_members uuid[])
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_group_admin(p_group) then raise exception 'group_admin_only' using errcode = '42501'; end if;
  insert into chat_group_members (group_id, user_id, added_by)
  select p_group, u.id, auth.uid()
  from users u
  where u.id = any(coalesce(p_members, '{}'::uuid[]))
  on conflict do nothing;
end;
$$;

-- Remove someone (group admins) or leave (yourself). If the last admin
-- leaves, the longest-standing member becomes admin.
create or replace function public.remove_chat_group_member(p_group uuid, p_user uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_user <> auth.uid() and not public.is_group_admin(p_group) then
    raise exception 'group_admin_only' using errcode = '42501';
  end if;
  delete from chat_group_members where group_id = p_group and user_id = p_user;
  if not exists (select 1 from chat_group_members where group_id = p_group and is_admin) then
    update chat_group_members set is_admin = true
    where (group_id, user_id) = (
      select group_id, user_id from chat_group_members where group_id = p_group order by joined_at limit 1
    );
  end if;
end;
$$;

-- Rename (group admins).
create or replace function public.rename_chat_group(p_group uuid, p_name text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_group_admin(p_group) then raise exception 'group_admin_only' using errcode = '42501'; end if;
  if p_name is null or char_length(btrim(p_name)) = 0 then raise exception 'invalid_name' using errcode = '22023'; end if;
  update chat_groups set name = left(btrim(p_name), 80) where id = p_group;
end;
$$;

-- "I've read this group up to now" (unread counters).
create or replace function public.mark_chat_group_read(p_group uuid)
returns void language sql security definer set search_path = public as $$
  update public.chat_group_members set last_read_at = now()
  where group_id = p_group and user_id = auth.uid();
$$;

grant execute on function public.create_chat_group(text, uuid[]) to authenticated;
grant execute on function public.add_chat_group_members(uuid, uuid[]) to authenticated;
grant execute on function public.remove_chat_group_member(uuid, uuid) to authenticated;
grant execute on function public.rename_chat_group(uuid, text) to authenticated;
grant execute on function public.mark_chat_group_read(uuid) to authenticated;

-- 4) Group files in the private chat-files bucket: "g/<group id>/<file>"
drop policy if exists "chat_files_group_read" on storage.objects;
create policy "chat_files_group_read" on storage.objects
  for select to authenticated
  using (bucket_id = 'chat-files' and (storage.foldername(name))[1] = 'g'
         and public.is_group_member_text((storage.foldername(name))[2]));

drop policy if exists "chat_files_group_upload" on storage.objects;
create policy "chat_files_group_upload" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'chat-files' and (storage.foldername(name))[1] = 'g'
              and public.is_group_member_text((storage.foldername(name))[2]));

-- 5) Realtime ------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['chat_groups','chat_group_members','group_messages'] loop
    if not exists (select 1 from pg_publication_tables
                   where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;
