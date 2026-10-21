-- =====================================================================
-- 0048 — Founder deletes a message without a trace (owner, 21.10.2026)
--
-- When the founder (0045) deletes his own message "for everyone", it
-- disappears on both sides: no "This message was deleted" line. Anyone
-- else keeps the 0031 behaviour (the line stays).
--
--   messages.deleted_silent / group_messages.deleted_silent — set only by
--   delete_message() for the founder; the app hides such messages. A
--   silently deleted direct message also counts as read, so no unread
--   badge is left behind for the other person.
--
-- Safe: forward-only, re-runnable. Two new columns (default false), one
-- guard trigger per table; my_chat_activity() skips silent messages;
-- delete_message() keeps its signature and its
-- checks (signed in, own message, member of the chat). Old deleted
-- messages are not touched.
-- =====================================================================

alter table public.messages add column if not exists deleted_silent boolean not null default false;
alter table public.group_messages add column if not exists deleted_silent boolean not null default false;

-- Nobody sets the flag directly (only delete_message below, admins and the
-- server). Runs after guard_message_update (name order), so the read mark
-- of a silent delete is kept.
create or replace function public.zz_guard_message_silent()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if current_setting('app.msg_delete_silent', true) = 'on' then
    new.deleted_silent := true;
    if tg_table_name = 'messages' then
      new.read_at := coalesce(old.read_at, now());
    end if;
    return new;
  end if;
  if auth.uid() is not null and not public.is_admin() then
    new.deleted_silent := old.deleted_silent;
  end if;
  return new;
end $$;
revoke all on function public.zz_guard_message_silent() from public, anon, authenticated;
drop trigger if exists zz_guard_message_silent on public.messages;
create trigger zz_guard_message_silent before update on public.messages
  for each row execute function public.zz_guard_message_silent();
drop trigger if exists zz_guard_message_silent on public.group_messages;
create trigger zz_guard_message_silent before update on public.group_messages
  for each row execute function public.zz_guard_message_silent();

-- delete_message: p_kind 'direct' | 'group', p_scope 'me' | 'everyone'
-- (same as 0031; the founder's "everyone" is silent).
create or replace function public.delete_message(p_message uuid, p_kind text, p_scope text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_uid uuid := auth.uid();
  v_sender uuid;
  v_ok boolean;
  v_silent boolean;
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
  v_silent := public.is_founder(v_uid);
  perform set_config('app.msg_delete_silent', case when v_silent then 'on' else 'off' end, true);
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
  perform set_config('app.msg_delete_silent', 'off', true);
end $$;
revoke all on function public.delete_message(uuid, text, text) from public, anon;
grant execute on function public.delete_message(uuid, text, text) to authenticated;

-- Chat list order (0031): a silently deleted message does not move a
-- chat to the top.
create or replace function public.my_chat_activity()
returns table (conversation_id uuid, last_message_at timestamptz)
language sql stable security definer set search_path = public, pg_temp as $$
  select m.conversation_id, max(m.created_at)
    from public.messages m
    join public.conversations c on c.id = m.conversation_id
   where (c.cargo_owner_id = auth.uid() or c.carrier_user_id = auth.uid())
     and not m.deleted_silent
     and not exists (select 1 from public.message_hidden h where h.user_id = auth.uid() and h.message_id = m.id)
   group by m.conversation_id;
$$;
revoke all on function public.my_chat_activity() from public, anon;
grant execute on function public.my_chat_activity() to authenticated;

notify pgrst, 'reload schema';
