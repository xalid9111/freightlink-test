-- =====================================================================
-- 0135 — Users block one another (owner, 24.11.2026: "istifadəçilər bir
-- birlərini blok edə bilsinlər … Mesajlar → ada basılaraq profilə keçilir
-- və sonda Blok et").
--
-- * user_blocks (blocker_id, blocked_id): who blocked whom. Read only by
--   the blocker; written only through user_block_set (no direct writes).
-- * user_block_set(p_user, p_block): on = the row (twice = once), off = the
--   row removed (only one's own block). Never oneself.
-- * user_block_state(p_user): {i_blocked, blocked_me} for the app — the
--   other side only learns "you cannot write", never more.
-- * A trigger on messages: no private message between two accounts where
--   either blocked the other ('user_blocked'). Admins still write (support,
--   moderation). Old messages and chats stay untouched; nothing is deleted.
--
-- Safe: forward-only, re-runnable. One new table, three functions, one
-- trigger. No existing row changes.
-- =====================================================================

begin;

create table if not exists public.user_blocks (
  blocker_id uuid not null references public.users(id) on delete cascade,
  blocked_id uuid not null references public.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint user_blocks_not_self check (blocker_id <> blocked_id)
);
create index if not exists user_blocks_blocked_idx on public.user_blocks (blocked_id);

alter table public.user_blocks enable row level security;
revoke all on public.user_blocks from public, anon, authenticated;
grant select on public.user_blocks to authenticated;
drop policy if exists "user_blocks_own_select" on public.user_blocks;
create policy "user_blocks_own_select" on public.user_blocks
  for select to authenticated using (blocker_id = auth.uid());

-- Is there a block between a and b (either way)?
create or replace function public.users_blocked_between(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select exists (select 1 from user_blocks
                  where (blocker_id = a and blocked_id = b)
                     or (blocker_id = b and blocked_id = a));
$$;
revoke all on function public.users_blocked_between(uuid, uuid) from public, anon, authenticated;

-- Block / unblock somebody.
create or replace function public.user_block_set(p_user uuid, p_block boolean)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_me uuid := auth.uid();
begin
  if v_me is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if p_user is null or p_block is null then raise exception 'invalid_argument' using errcode = '22023'; end if;
  if p_user = v_me then raise exception 'invalid_user' using errcode = '22023'; end if;
  if not exists (select 1 from users where id = p_user) then
    raise exception 'not_found' using errcode = 'P0002';
  end if;
  if p_block then
    insert into user_blocks (blocker_id, blocked_id) values (v_me, p_user)
      on conflict do nothing;
  else
    delete from user_blocks where blocker_id = v_me and blocked_id = p_user;
  end if;
end $$;
revoke all on function public.user_block_set(uuid, boolean) from public, anon;
grant execute on function public.user_block_set(uuid, boolean) to authenticated;

-- What the app shows on a profile / chat.
create or replace function public.user_block_state(p_user uuid)
returns jsonb language sql stable security definer set search_path = public, pg_temp as $$
  select jsonb_build_object(
    'i_blocked', auth.uid() is not null and exists (select 1 from user_blocks
                   where blocker_id = auth.uid() and blocked_id = p_user),
    'blocked_me', auth.uid() is not null and exists (select 1 from user_blocks
                   where blocker_id = p_user and blocked_id = auth.uid()));
$$;
revoke all on function public.user_block_state(uuid) from public, anon;
grant execute on function public.user_block_state(uuid) to authenticated;

-- No private message across a block (admins excepted).
create or replace function public.messages_user_block_guard()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if new.sender_id is not null and new.receiver_id is not null
     and public.users_blocked_between(new.sender_id, new.receiver_id)
     and not public.is_admin() then
    raise exception 'user_blocked' using errcode = '42501';
  end if;
  return new;
end $$;
revoke all on function public.messages_user_block_guard() from public, anon, authenticated;
drop trigger if exists zz_messages_user_block on public.messages;
create trigger zz_messages_user_block before insert on public.messages
  for each row execute function public.messages_user_block_guard();

-- Final check: everything in place.
do $$
begin
  if to_regclass('public.user_blocks') is null
     or to_regprocedure('public.user_block_set(uuid, boolean)') is null
     or to_regprocedure('public.user_block_state(uuid)') is null
     or not exists (select 1 from pg_trigger where tgname = 'zz_messages_user_block') then
    raise exception '0135: final check failed — nothing changed';
  end if;
end $$;

commit;

notify pgrst, 'reload schema';
