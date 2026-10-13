-- =====================================================================
-- 0030 — WhatsApp phone verification: PROOF OF CONCEPT (isolated)
--
-- Answers one question: when a user sends a prefilled one-time message
-- to FreightLink's WhatsApp Business number, does the Meta webhook give
-- us the sender's real phone number, so it can be matched to the number
-- the user typed in the app?
--
-- Isolation:
--   * Two NEW tables only. No existing table, policy, function, trigger
--     or row is changed. public.users is NOT touched — a "verified"
--     result lives only in wa_verify_challenges and is not copied to the
--     profile.
--   * Rows are written only by the two SECURITY DEFINER functions below,
--     which only service_role (the Edge Functions) may execute.
--   * Signed-in users may read only their own challenge rows, and never
--     the challenge hash.
--
-- Data minimisation:
--   * The raw challenge is never stored — only its SHA-256 hash, cleared
--     (set to NULL) as soon as the challenge is consumed, expires or is
--     replaced.
--   * WhatsApp message text, sender phone numbers and BSUIDs are never
--     stored. The webhook-event table keeps only Meta's message id (for
--     retry de-duplication) and is trimmed to 7 days.
--   * Challenge rows older than 1 day are deleted when the same user
--     starts a new test.
--
-- Forward-only, re-runnable, deletes no existing data.
-- =====================================================================

create table if not exists public.wa_verify_challenges (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references auth.users (id) on delete cascade,
  phone_e164      text not null check (phone_e164 ~ '^\+[1-9][0-9]{6,14}$'),
  -- SHA-256 (hex) of the one-time code; NULL once no longer usable.
  challenge_hash  text unique check (challenge_hash is null or challenge_hash ~ '^[0-9a-f]{64}$'),
  status          text not null default 'pending'
                  check (status in ('pending', 'verified', 'expired', 'locked', 'superseded')),
  -- Outcome of the latest webhook attempt for this challenge.
  last_result     text check (last_result in ('verified', 'no_phone_in_webhook', 'phone_mismatch', 'sender_conflict', 'expired', 'locked')),
  -- What the webhook told us about the sender (no values, only the kind):
  --   phone       messages[].from held a usable phone number
  --   bsuid_only  only a business-scoped user id (no phone number)
  --   conflict    from / contacts[].wa_id disagreed
  --   none        no sender identity at all
  sender_kind     text check (sender_kind in ('phone', 'bsuid_only', 'conflict', 'none')),
  has_bsuid       boolean,
  attempts        int not null default 0,
  created_at      timestamptz not null default now(),
  expires_at      timestamptz not null,
  consumed_at     timestamptz,
  updated_at      timestamptz not null default now()
);

create index if not exists wa_verify_challenges_user_idx on public.wa_verify_challenges (user_id, created_at desc);

create table if not exists public.wa_webhook_events (
  message_id   text primary key check (length(message_id) between 1 and 256),
  received_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Access: users read their own challenges (without the hash); nobody
-- but service_role writes; the event table is service_role only.
-- ---------------------------------------------------------------------
alter table public.wa_verify_challenges enable row level security;
alter table public.wa_webhook_events enable row level security;

revoke all on public.wa_verify_challenges from public, anon, authenticated;
revoke all on public.wa_webhook_events from public, anon, authenticated;
grant select (id, phone_e164, status, last_result, sender_kind, has_bsuid, attempts,
              created_at, expires_at, consumed_at, updated_at)
  on public.wa_verify_challenges to authenticated;
grant all on public.wa_verify_challenges, public.wa_webhook_events to service_role;

drop policy if exists wa_verify_challenges_own_select on public.wa_verify_challenges;
create policy wa_verify_challenges_own_select on public.wa_verify_challenges
  for select to authenticated using (user_id = auth.uid());

-- ---------------------------------------------------------------------
-- wa_poc_start — called by the wa-verify-start Edge Function after it has
-- checked the caller's JWT. Stores only the hash of the new code.
-- ---------------------------------------------------------------------
create or replace function public.wa_poc_start(
  p_user uuid, p_phone text, p_hash text, p_ttl_seconds int default 600, p_require_admin boolean default true
) returns table (id uuid, expires_at timestamptz)
language plpgsql security definer set search_path = public, pg_temp as $$
#variable_conflict use_column
declare
  v_id uuid;
  v_exp timestamptz;
begin
  if p_user is null or not exists (select 1 from auth.users u where u.id = p_user) then
    raise exception 'user_not_found';
  end if;
  if p_require_admin and not exists (select 1 from public.users u where u.id = p_user and u.role = 'admin') then
    raise exception 'admin_only';
  end if;
  if p_phone is null or p_phone !~ '^\+[1-9][0-9]{6,14}$' then
    raise exception 'invalid_phone';
  end if;
  if p_hash is null or p_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'invalid_hash';
  end if;
  if p_ttl_seconds is null or p_ttl_seconds < 60 or p_ttl_seconds > 900 then
    raise exception 'invalid_ttl';
  end if;
  -- Rate limit: 5 new tests per user per 10 minutes.
  if (select count(*) from public.wa_verify_challenges c
       where c.user_id = p_user and c.created_at > now() - interval '10 minutes') >= 5 then
    raise exception 'rate_limited';
  end if;

  -- Housekeeping for this user: old rows go, open ones are replaced.
  delete from public.wa_verify_challenges c where c.user_id = p_user and c.created_at < now() - interval '1 day';
  update public.wa_verify_challenges c
     set status = 'superseded', challenge_hash = null, updated_at = now()
   where c.user_id = p_user and c.status = 'pending';

  insert into public.wa_verify_challenges (user_id, phone_e164, challenge_hash, expires_at)
  values (p_user, p_phone, p_hash, now() + make_interval(secs => p_ttl_seconds))
  returning wa_verify_challenges.id, wa_verify_challenges.expires_at into v_id, v_exp;

  return query select v_id, v_exp;
end $$;

-- ---------------------------------------------------------------------
-- wa_poc_inbound — called by the wa-webhook Edge Function for every
-- incoming text message that contains a FreightLink code. One call is
-- one transaction, so a Meta retry of the same message id is a no-op,
-- and a failed call leaves nothing behind (the retry is processed).
--
-- Returns: duplicate | no_challenge | not_pending | expired | locked |
--          no_phone_in_webhook | sender_conflict | phone_mismatch | verified
-- The challenge is consumed ONLY on 'verified'.
-- ---------------------------------------------------------------------
create or replace function public.wa_poc_inbound(
  p_message_id text, p_hash text, p_sender_kind text, p_sender_digits text, p_has_bsuid boolean
) returns text
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  c public.wa_verify_challenges%rowtype;
  v_inserted int;
  v_result text;
begin
  if p_message_id is null or length(p_message_id) not between 1 and 256 then
    raise exception 'invalid_message_id';
  end if;
  if p_sender_kind is null or p_sender_kind not in ('phone', 'bsuid_only', 'conflict', 'none') then
    raise exception 'invalid_sender_kind';
  end if;

  insert into public.wa_webhook_events (message_id) values (p_message_id) on conflict do nothing;
  get diagnostics v_inserted = row_count;
  if v_inserted = 0 then
    return 'duplicate';
  end if;
  delete from public.wa_webhook_events e where e.received_at < now() - interval '7 days';

  if p_hash is null or p_hash !~ '^[0-9a-f]{64}$' then
    return 'no_challenge';
  end if;

  select * into c from public.wa_verify_challenges w where w.challenge_hash = p_hash for update;
  if not found then
    return 'no_challenge';
  end if;
  if c.status <> 'pending' then
    return 'not_pending';
  end if;
  if c.expires_at <= now() then
    update public.wa_verify_challenges w
       set status = 'expired', last_result = 'expired', challenge_hash = null, updated_at = now()
     where w.id = c.id;
    return 'expired';
  end if;
  if c.attempts >= 5 then
    update public.wa_verify_challenges w
       set status = 'locked', last_result = 'locked', challenge_hash = null, updated_at = now()
     where w.id = c.id;
    return 'locked';
  end if;

  if p_sender_kind = 'conflict' then
    v_result := 'sender_conflict';
  elsif p_sender_kind <> 'phone' or p_sender_digits is null or p_sender_digits !~ '^[1-9][0-9]{6,14}$' then
    -- Only a BSUID (or nothing usable): never treat as verified.
    v_result := 'no_phone_in_webhook';
  elsif '+' || p_sender_digits <> c.phone_e164 then
    v_result := 'phone_mismatch';
  else
    v_result := 'verified';
  end if;

  if v_result = 'verified' then
    update public.wa_verify_challenges w
       set status = 'verified', last_result = 'verified', sender_kind = p_sender_kind, has_bsuid = p_has_bsuid,
           attempts = w.attempts + 1, consumed_at = now(), challenge_hash = null, updated_at = now()
     where w.id = c.id;
  else
    update public.wa_verify_challenges w
       set last_result = v_result, sender_kind = p_sender_kind, has_bsuid = p_has_bsuid,
           attempts = w.attempts + 1, updated_at = now()
     where w.id = c.id;
  end if;
  return v_result;
end $$;

revoke all on function public.wa_poc_start(uuid, text, text, int, boolean) from public, anon, authenticated;
revoke all on function public.wa_poc_inbound(text, text, text, text, boolean) from public, anon, authenticated;
grant execute on function public.wa_poc_start(uuid, text, text, int, boolean) to service_role;
grant execute on function public.wa_poc_inbound(text, text, text, text, boolean) to service_role;
