-- =====================================================================
-- 0011 — carrier ↔ cargo-owner messaging hardening.
-- SAFE FORWARD MIGRATION. Nothing is deleted. Existing conversations
-- and messages are kept; the only data change is step 6, which corrects
-- receiver_id on legacy messages whose receiver was not the other
-- participant (so both sides can see them). Idempotent.
--
-- Run in Supabase → SQL Editor (after 0009/0010).
-- =====================================================================

-- 1) One atomic, server-side "open or create" ----------------------
-- The client used to (a) SELECT, then (b) INSERT with ids it supplied.
-- Two quick taps could race (second insert hits the unique key and
-- errors), and nothing checked that cargo_owner_id really owns the
-- cargo. This function derives the owner from the cargo itself, takes
-- the carrier from auth.uid() (or, when the OWNER starts the chat, from
-- the given carrier), inserts ON CONFLICT DO NOTHING and returns the
-- single row for (cargo, carrier) — duplicates are impossible.
create or replace function public.get_or_create_conversation(
  p_cargo_id uuid,
  p_carrier_user_id uuid default null,
  p_carrier_id uuid default null
)
returns public.conversations
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid;
  v_carrier uuid;
  v_conv public.conversations;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select owner_id into v_owner from public.cargo where id = p_cargo_id;
  if v_owner is null then
    raise exception 'cargo_not_found' using errcode = 'P0002';
  end if;

  if auth.uid() = v_owner then
    -- owner starts/opens a chat with a specific carrier (e.g. from an offer)
    v_carrier := coalesce(
      p_carrier_user_id,
      (select user_id from public.carriers where id = p_carrier_id)
    );
    if v_carrier is null or v_carrier = v_owner then
      raise exception 'carrier_required' using errcode = '22023';
    end if;
  else
    -- anyone else opening a chat about this cargo is the carrier side
    v_carrier := auth.uid();
    if not exists (select 1 from public.users u where u.id = v_carrier and u.role in ('carrier', 'driver', 'admin')) then
      raise exception 'only_carriers_can_contact' using errcode = '42501';
    end if;
  end if;

  insert into public.conversations (cargo_id, cargo_owner_id, carrier_user_id)
  values (p_cargo_id, v_owner, v_carrier)
  on conflict (cargo_id, carrier_user_id) do nothing;

  select * into v_conv
  from public.conversations
  where cargo_id = p_cargo_id and carrier_user_id = v_carrier;

  return v_conv;
end;
$$;

grant execute on function public.get_or_create_conversation(uuid, uuid, uuid) to authenticated;

-- 2) Direct inserts: owner id must be the cargo's real owner ---------
drop policy if exists "conversations_create" on public.conversations;
create policy "conversations_create" on public.conversations
  for insert to authenticated
  with check (
    (auth.uid() = cargo_owner_id or auth.uid() = carrier_user_id)
    and cargo_owner_id <> carrier_user_id
    and (cargo_id is null or cargo_owner_id = (select c.owner_id from public.cargo c where c.id = cargo_id))
  );

-- 3) Messages: only a conversation participant may send, and only to
-- the OTHER participant (previously any signed-in user could insert
-- into any conversation with any receiver_id).
drop policy if exists "messages_send" on public.messages;
create policy "messages_send" on public.messages
  for insert to authenticated
  with check (
    sender_id = auth.uid()
    and exists (
      select 1 from public.conversations c
      where c.id = conversation_id
        and (
          (c.cargo_owner_id = auth.uid() and receiver_id = c.carrier_user_id)
          or (c.carrier_user_id = auth.uid() and receiver_id = c.cargo_owner_id)
        )
    )
  );

-- Participants see every message of their conversations (in addition to
-- the existing sender/receiver rule), so a mis-addressed legacy row can
-- never hide part of a thread.
drop policy if exists "messages_conversation_participants_select" on public.messages;
create policy "messages_conversation_participants_select" on public.messages
  for select to authenticated
  using (
    exists (
      select 1 from public.conversations c
      where c.id = conversation_id
        and (c.cargo_owner_id = auth.uid() or c.carrier_user_id = auth.uid())
    )
  );

-- 4) "Mark read" may change read_at only (policy messages_mark_read
-- let the receiver update any column, e.g. rewrite the text).
create or replace function public.guard_message_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or public.is_admin() then
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
  return new;
end;
$$;

drop trigger if exists guard_message_update on public.messages;
create trigger guard_message_update
  before update on public.messages
  for each row execute function public.guard_message_update();

-- 5) Realtime for conversations, so a carrier's NEW chat appears in the
-- owner's list instantly (only messages were published before).
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'conversations'
  ) then
    alter publication supabase_realtime add table public.conversations;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'messages'
  ) then
    alter publication supabase_realtime add table public.messages;
  end if;
end $$;

-- 6) Repair legacy mis-addressed messages (no deletion) --------------
update public.messages m
set receiver_id = case when m.sender_id = c.cargo_owner_id then c.carrier_user_id else c.cargo_owner_id end
from public.conversations c
where c.id = m.conversation_id
  and m.sender_id in (c.cargo_owner_id, c.carrier_user_id)
  and m.receiver_id is distinct from
      (case when m.sender_id = c.cargo_owner_id then c.carrier_user_id else c.cargo_owner_id end);
