-- =====================================================================
-- 0031 — WhatsApp-style profile + catalog, and deleting messages / chats
--
-- 1) profile_details: cover photo, "about", working hours, address for
--    EVERY user (carrier, cargo owner, service). Readable by signed-in
--    users; each user writes only their own row.
-- 2) profile_catalog_items: "Catalog / my work" photos with a short
--    caption (max 300 chars), max 60 per user. Files live in the public
--    bucket profile-media under the owner's own folder.
-- 3) Deleting:
--    * "Delete for me": a message / a whole chat disappears only from the
--      caller's own view (message_hidden, chat_clears). Nothing is
--      removed from the database, the other person keeps everything.
--    * "Delete for everyone": only the SENDER, only their own message.
--      The text / attachment reference is blanked and deleted_at is set,
--      so both sides see "This message was deleted".
--
-- Forward-only and re-runnable. Existing rows are not changed or deleted.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) Profile details
-- ---------------------------------------------------------------------
create table if not exists public.profile_details (
  user_id     uuid primary key references public.users (id) on delete cascade,
  about       text check (about is null or char_length(about) <= 500),
  work_hours  text check (work_hours is null or char_length(work_hours) <= 120),
  address     text check (address is null or char_length(address) <= 200),
  cover_url   text check (cover_url is null or (char_length(cover_url) <= 1000 and cover_url ~ '^https://[^ ]+/storage/v1/object/public/profile-media/')),
  updated_at  timestamptz not null default now()
);

alter table public.profile_details enable row level security;
revoke all on public.profile_details from public, anon;
grant select, insert, update, delete on public.profile_details to authenticated;

drop policy if exists profile_details_read on public.profile_details;
create policy profile_details_read on public.profile_details
  for select to authenticated using (true);
drop policy if exists profile_details_insert_own on public.profile_details;
create policy profile_details_insert_own on public.profile_details
  for insert to authenticated with check (user_id = auth.uid());
drop policy if exists profile_details_update_own on public.profile_details;
create policy profile_details_update_own on public.profile_details
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists profile_details_delete_own on public.profile_details;
create policy profile_details_delete_own on public.profile_details
  for delete to authenticated using (user_id = auth.uid() or public.is_admin());

-- ---------------------------------------------------------------------
-- 2) Catalog
-- ---------------------------------------------------------------------
create table if not exists public.profile_catalog_items (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.users (id) on delete cascade,
  image_path  text not null check (char_length(image_path) <= 300 and image_path ~ '^[0-9a-f-]{36}/catalog/[A-Za-z0-9._-]+$'),
  caption     text check (caption is null or char_length(caption) <= 300),
  created_at  timestamptz not null default now(),
  check (split_part(image_path, '/', 1) = user_id::text)
);
create index if not exists profile_catalog_items_user_idx on public.profile_catalog_items (user_id, created_at desc);

alter table public.profile_catalog_items enable row level security;
revoke all on public.profile_catalog_items from public, anon;
grant select, insert, update, delete on public.profile_catalog_items to authenticated;

drop policy if exists catalog_read on public.profile_catalog_items;
create policy catalog_read on public.profile_catalog_items
  for select to authenticated using (true);
drop policy if exists catalog_insert_own on public.profile_catalog_items;
create policy catalog_insert_own on public.profile_catalog_items
  for insert to authenticated with check (user_id = auth.uid());
drop policy if exists catalog_update_own on public.profile_catalog_items;
create policy catalog_update_own on public.profile_catalog_items
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists catalog_delete_own on public.profile_catalog_items;
create policy catalog_delete_own on public.profile_catalog_items
  for delete to authenticated using (user_id = auth.uid() or public.is_admin());

-- Max 60 catalog photos per user; the image path cannot be changed later.
create or replace function public.guard_catalog_item()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if tg_op = 'INSERT' then
    if (select count(*) from public.profile_catalog_items c where c.user_id = new.user_id) >= 60 then
      raise exception 'catalog_full';
    end if;
  elsif tg_op = 'UPDATE' then
    new.user_id := old.user_id;
    new.image_path := old.image_path;
    new.created_at := old.created_at;
  end if;
  return new;
end $$;
drop trigger if exists guard_catalog_item on public.profile_catalog_items;
create trigger guard_catalog_item before insert or update on public.profile_catalog_items
  for each row execute function public.guard_catalog_item();

-- Public bucket: anyone with the link can view; only the owner writes
-- into their own folder (<user id>/...). Images only, 5 MB.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('profile-media', 'profile-media', true, 5242880, array['image/jpeg', 'image/png', 'image/webp', 'image/gif'])
on conflict (id) do nothing;

drop policy if exists "profile_media_read" on storage.objects;
create policy "profile_media_read" on storage.objects
  for select using (bucket_id = 'profile-media');
drop policy if exists "profile_media_insert_own" on storage.objects;
create policy "profile_media_insert_own" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'profile-media' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "profile_media_update_own" on storage.objects;
create policy "profile_media_update_own" on storage.objects
  for update to authenticated
  using (bucket_id = 'profile-media' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "profile_media_delete_own" on storage.objects;
create policy "profile_media_delete_own" on storage.objects
  for delete to authenticated
  using (bucket_id = 'profile-media' and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin()));

-- ---------------------------------------------------------------------
-- 3) Deleting messages and chats
-- ---------------------------------------------------------------------
alter table public.messages add column if not exists deleted_at timestamptz;
alter table public.group_messages add column if not exists deleted_at timestamptz;

-- "Delete for me" — per user, per message (direct or group).
create table if not exists public.message_hidden (
  user_id     uuid not null references public.users (id) on delete cascade,
  message_id  uuid not null,
  kind        text not null check (kind in ('direct', 'group')),
  created_at  timestamptz not null default now(),
  primary key (user_id, message_id)
);
-- "Delete chat for me" — everything up to cleared_at disappears for the
-- caller; newer messages show up again (like WhatsApp).
create table if not exists public.chat_clears (
  user_id     uuid not null references public.users (id) on delete cascade,
  chat_id     uuid not null,  -- conversations.id or chat_groups.id
  kind        text not null check (kind in ('direct', 'group')),
  cleared_at  timestamptz not null default now(),
  primary key (user_id, chat_id)
);

alter table public.message_hidden enable row level security;
alter table public.chat_clears enable row level security;
revoke all on public.message_hidden, public.chat_clears from public, anon, authenticated;
grant select on public.message_hidden, public.chat_clears to authenticated;
drop policy if exists message_hidden_own on public.message_hidden;
create policy message_hidden_own on public.message_hidden
  for select to authenticated using (user_id = auth.uid());
drop policy if exists chat_clears_own on public.chat_clears;
create policy chat_clears_own on public.chat_clears
  for select to authenticated using (user_id = auth.uid());

-- The existing guard (0011) lets nobody but admins change a message. The
-- delete-for-everyone function below sets a transaction-local flag, and
-- only then may it blank the content and set deleted_at.
create or replace function public.guard_message_update()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null or public.is_admin() then
    return new;
  end if;
  if current_setting('app.msg_delete_for_everyone', true) = 'on' then
    -- Only content blanking + deleted_at may change here.
    new.conversation_id := old.conversation_id;
    new.shipment_id := old.shipment_id;
    new.sender_id := old.sender_id;
    new.receiver_id := old.receiver_id;
    new.read_at := old.read_at;
    new.created_at := old.created_at;
    return new;
  end if;
  if new.read_at is null and old.read_at is not null then
    new.read_at := old.read_at; -- can't un-read
  end if;
  new.conversation_id := old.conversation_id;
  new.shipment_id := old.shipment_id;
  new.sender_id := old.sender_id;
  new.receiver_id := old.receiver_id;
  new.message := old.message;
  new.attachment_id := old.attachment_id;
  new.attachment_path := old.attachment_path;
  new.attachment_type := old.attachment_type;
  new.attachment_name := old.attachment_name;
  new.attachment_size := old.attachment_size;
  new.audio_duration_ms := old.audio_duration_ms;
  new.created_at := old.created_at;
  new.deleted_at := old.deleted_at;
  return new;
end;
$$;

-- delete_message: p_kind 'direct' | 'group', p_scope 'me' | 'everyone'
create or replace function public.delete_message(p_message uuid, p_kind text, p_scope text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_uid uuid := auth.uid();
  v_sender uuid;
  v_ok boolean;
begin
  if v_uid is null then raise exception 'not_signed_in'; end if;
  if p_kind not in ('direct', 'group') or p_scope not in ('me', 'everyone') then
    raise exception 'invalid_argument';
  end if;

  if p_kind = 'direct' then
    select m.sender_id, (c.cargo_owner_id = v_uid or c.carrier_user_id = v_uid)
      into v_sender, v_ok
      from public.messages m join public.conversations c on c.id = m.conversation_id
     where m.id = p_message;
  else
    select g.sender_id, exists (select 1 from public.chat_group_members gm where gm.group_id = g.group_id and gm.user_id = v_uid)
      into v_sender, v_ok
      from public.group_messages g
     where g.id = p_message;
  end if;
  if not found or not coalesce(v_ok, false) then raise exception 'message_not_found'; end if;

  if p_scope = 'me' then
    insert into public.message_hidden (user_id, message_id, kind) values (v_uid, p_message, p_kind)
    on conflict (user_id, message_id) do nothing;
    return;
  end if;

  if v_sender <> v_uid then raise exception 'not_your_message'; end if;
  if p_kind = 'direct' then
    perform set_config('app.msg_delete_for_everyone', 'on', true);
    update public.messages
       set message = '', attachment_id = null, attachment_path = null, attachment_type = null,
           attachment_name = null, attachment_size = null, audio_duration_ms = null,
           deleted_at = coalesce(deleted_at, now())
     where id = p_message;
    perform set_config('app.msg_delete_for_everyone', 'off', true);
  else
    update public.group_messages
       set message = '', attachment_path = null, attachment_type = null,
           attachment_name = null, attachment_size = null, audio_duration_ms = null,
           deleted_at = coalesce(deleted_at, now())
     where id = p_message;
  end if;
end $$;

-- clear_chat_for_me: p_kind 'direct' → every conversation with person
-- p_target (one row per person in the app); 'group' → group p_target.
create or replace function public.clear_chat_for_me(p_target uuid, p_kind text)
returns int language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_uid uuid := auth.uid();
  v_n int := 0;
begin
  if v_uid is null then raise exception 'not_signed_in'; end if;
  if p_kind = 'direct' then
    insert into public.chat_clears (user_id, chat_id, kind, cleared_at)
    select v_uid, c.id, 'direct', now()
      from public.conversations c
     where (c.cargo_owner_id = v_uid and c.carrier_user_id = p_target)
        or (c.carrier_user_id = v_uid and c.cargo_owner_id = p_target)
    on conflict (user_id, chat_id) do update set cleared_at = excluded.cleared_at;
    get diagnostics v_n = row_count;
  elsif p_kind = 'group' then
    if not exists (select 1 from public.chat_group_members gm where gm.group_id = p_target and gm.user_id = v_uid) then
      raise exception 'group_not_found';
    end if;
    insert into public.chat_clears (user_id, chat_id, kind, cleared_at)
    values (v_uid, p_target, 'group', now())
    on conflict (user_id, chat_id) do update set cleared_at = excluded.cleared_at;
    get diagnostics v_n = row_count;
  else
    raise exception 'invalid_argument';
  end if;
  return v_n;
end $$;

-- Last message time per direct conversation of the caller (to sort the
-- list by activity and to show a cleared chat again when a new message
-- arrives). Messages the caller hid are ignored.
create or replace function public.my_chat_activity()
returns table (conversation_id uuid, last_message_at timestamptz)
language sql stable security definer set search_path = public, pg_temp as $$
  select m.conversation_id, max(m.created_at)
    from public.messages m
    join public.conversations c on c.id = m.conversation_id
   where (c.cargo_owner_id = auth.uid() or c.carrier_user_id = auth.uid())
     and not exists (select 1 from public.message_hidden h where h.user_id = auth.uid() and h.message_id = m.id)
   group by m.conversation_id;
$$;

revoke all on function public.delete_message(uuid, text, text) from public, anon;
revoke all on function public.clear_chat_for_me(uuid, text) from public, anon;
revoke all on function public.my_chat_activity() from public, anon;
grant execute on function public.delete_message(uuid, text, text) to authenticated;
grant execute on function public.clear_chat_for_me(uuid, text) to authenticated;
grant execute on function public.my_chat_activity() to authenticated;
