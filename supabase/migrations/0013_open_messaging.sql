-- =====================================================================
-- 0013 — Everyone can message everyone about a load.
-- SAFE FORWARD MIGRATION: only redefines get_or_create_conversation().
-- No table, policy or data is changed or deleted. Idempotent.
--
-- Before: a non-owner could open a chat about a load only if their role
-- was carrier / driver / admin ("only_carriers_can_contact"). Now loads
-- can be posted by every role, so ANY signed-in user (cargo owner too)
-- may start a chat with the poster. Kept protections:
--   * you can't open a chat with yourself;
--   * one chat per (load, person) — repeat taps reuse it;
--   * the poster is always taken from the load, never from the client;
--   * accounts blocked by an admin still can't start chats (0012).
-- =====================================================================

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
  v_other uuid;
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
    -- the poster opens a chat with a specific person (e.g. from an offer)
    v_other := coalesce(
      p_carrier_user_id,
      (select user_id from public.carriers where id = p_carrier_id)
    );
    if v_other is null or v_other = v_owner then
      raise exception 'carrier_required' using errcode = '22023';
    end if;
  else
    -- anyone else (any role) writing about this load
    v_other := auth.uid();
  end if;

  insert into public.conversations (cargo_id, cargo_owner_id, carrier_user_id)
  values (p_cargo_id, v_owner, v_other)
  on conflict (cargo_id, carrier_user_id) do nothing;

  select * into v_conv
  from public.conversations
  where cargo_id = p_cargo_id and carrier_user_id = v_other;

  return v_conv;
end;
$$;

grant execute on function public.get_or_create_conversation(uuid, uuid, uuid) to authenticated;
