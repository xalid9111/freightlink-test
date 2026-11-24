-- =====================================================================
-- 0136 — A block is silent for the blocked one (owner, 24.11.2026: "bloka
-- atılan istifadəçi … bloklanma barəsində bildiriş verilməməlidir").
--
-- 0135 refused a blocked account's message ('user_blocked'), so his app
-- could tell him. Now, like WhatsApp:
-- * messages.blocked_drop: set ONLY by the trigger. A message written TO
--   someone who blocked the sender is saved with blocked_drop = true — the
--   sender sees it sent as usual; the blocker never sees it (the app skips
--   it), it rings nothing (no push, no unread count) and does not move the
--   chat up (my_chat_activity). It stays dropped after an unblock.
-- * The blocker himself still cannot write to the one he blocked (refused,
--   his own app says so and offers "Blokdan çıxar").
-- * Admins write as before.
-- * user_blocked_me_ids(): the accounts that blocked me, so the app shows
--   me their profile empty (no picture, presence, details).
--
-- Safe: forward-only, re-runnable. One new column with a constant default
-- (no row rewritten), one guard trigger, three replaced functions (same answers plus the new
-- rule), one new read function. Nothing is deleted.
-- =====================================================================

begin;

alter table public.messages add column if not exists blocked_drop boolean not null default false;

-- 0135's guard, now silent for the blocked one.
create or replace function public.messages_user_block_guard()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  new.blocked_drop := false;   -- never set by a client
  if new.sender_id is null or new.receiver_id is null or public.is_admin() then
    return new;
  end if;
  if exists (select 1 from user_blocks where blocker_id = new.sender_id and blocked_id = new.receiver_id) then
    raise exception 'user_blocked' using errcode = '42501';   -- the blocker's own app says so
  end if;
  if exists (select 1 from user_blocks where blocker_id = new.receiver_id and blocked_id = new.sender_id) then
    new.blocked_drop := true;                                  -- silent: never reaches the blocker
  end if;
  return new;
end $$;
revoke all on function public.messages_user_block_guard() from public, anon, authenticated;
drop trigger if exists zz_messages_user_block on public.messages;
create trigger zz_messages_user_block before insert on public.messages
  for each row execute function public.messages_user_block_guard();

-- Nobody but an admin changes the mark afterwards.
create or replace function public.messages_blocked_drop_keep()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not public.is_admin() then
    new.blocked_drop := old.blocked_drop;
  end if;
  return new;
end $$;
revoke all on function public.messages_blocked_drop_keep() from public, anon, authenticated;
drop trigger if exists zz_messages_blocked_drop_keep on public.messages;
create trigger zz_messages_blocked_drop_keep before update on public.messages
  for each row execute function public.messages_blocked_drop_keep();

-- 0121's message push + one rule: a dropped message rings nothing.
create or replace function public._push_on_message()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_name text;
  v_body text;
  v_preview boolean;
begin
  if new.receiver_id is null or new.receiver_id = new.sender_id then return new; end if;
  if coalesce(new.deleted_silent, false) or new.deleted_at is not null then return new; end if;
  if coalesce(new.blocked_drop, false) then return new; end if;
  -- Reading this chat (or another topic with the same person, shown in the
  -- same thread) right now: no push.
  if exists (select 1 from push_presence p left join conversations c on c.id = p.conversation_id
             where p.user_id = new.receiver_id and p.seen_at > now() - interval '40 seconds'
               and (p.conversation_id = new.conversation_id or new.sender_id in (c.cargo_owner_id, c.carrier_user_id))) then
    return new;
  end if;
  if exists (select 1 from push_outbox where user_id = new.receiver_id and kind = 'park_receipt' and created_at = now()) then
    return new;
  end if;
  select coalesce(nullif(btrim(full_name), ''), 'TırLink') into v_name from users where id = new.sender_id;
  select coalesce(preview, false) into v_preview from push_prefs where user_id = new.receiver_id;
  v_body := case when coalesce(v_preview, false) and nullif(btrim(coalesce(new.message, '')), '') is not null
                 then left(regexp_replace(btrim(new.message), '\s+', ' ', 'g'), 80)
                 else public._push_t(public._push_lang(new.receiver_id), 'msg_new') end;
  perform public._push_enqueue(new.receiver_id, 'message', v_name, v_body,
    '/#/chat/' || new.conversation_id, 'chat-' || new.conversation_id);
  return new;
exception when others then
  raise notice 'push (message) skipped: %', sqlerrm;
  return new;
end;
$$;

-- 0048's chat order + one rule: a dropped message never moves the
-- blocker's chat up.
create or replace function public.my_chat_activity()
returns table (conversation_id uuid, last_message_at timestamptz)
language sql stable security definer set search_path = public, pg_temp as $$
  select m.conversation_id, max(m.created_at)
    from public.messages m
    join public.conversations c on c.id = m.conversation_id
   where (c.cargo_owner_id = auth.uid() or c.carrier_user_id = auth.uid())
     and not m.deleted_silent
     and not (m.blocked_drop and m.receiver_id = auth.uid())
     and not exists (select 1 from public.message_hidden h where h.user_id = auth.uid() and h.message_id = m.id)
   group by m.conversation_id;
$$;
revoke all on function public.my_chat_activity() from public, anon;
grant execute on function public.my_chat_activity() to authenticated;

-- The accounts that blocked me (one read for the Mesajlar list: their
-- picture and presence are not shown to me). Only my own rows.
create or replace function public.user_blocked_me_ids()
returns uuid[] language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(array_agg(blocker_id), '{}') from user_blocks where blocked_id = auth.uid();
$$;
revoke all on function public.user_blocked_me_ids() from public, anon;
grant execute on function public.user_blocked_me_ids() to authenticated;

-- Final check: everything in place.
do $$
begin
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'messages' and column_name = 'blocked_drop')
     or not exists (select 1 from pg_trigger where tgname = 'zz_messages_user_block')
     or not exists (select 1 from pg_trigger where tgname = 'zz_push_message') then
    raise exception '0136: final check failed — nothing changed';
  end if;
end $$;

commit;

notify pgrst, 'reload schema';
