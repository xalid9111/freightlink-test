-- =====================================================================
-- 0127 — "Telefon nömrəmi gizlət" hides the e-mail too (owner, 17.11.2026:
-- "gizli funksiyanı aktiv edən istifadəçinin həm telefonu, həm də e-mail
-- ünvanı gizlədilsin. Sadəcə mesaj aktiv olsun").
--
-- While users.phone_hidden is on, the contact functions give no e-mail to
-- others: the load page (get_cargo_contact) and the public profile
-- (get_user_contact). The account's owner and the Baş admin (is_chief_admin)
-- still see it, exactly as with the hidden number (0123). Mesajlar stays.
-- Turning the switch off shows the e-mail again (nothing is moved or
-- deleted; users.email is never changed — it is the sign-in address).
--
-- Safe: forward-only, re-runnable; two functions replaced with the 0123
-- bodies + the e-mail rule. No table or data changes.
-- =====================================================================

begin;

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
    'email',         case when v_show then v_u.email end,   -- 0127: hidden with the phone
    'phone_hidden',  not v_show,
    'contact_phone', case when v_show then coalesce(
                       (select k.phone from public.cargo_contacts k where k.cargo_id = p_cargo),
                       (select h.phone from public.hidden_ad_phones h where h.kind = 'cargo' and h.ad_id = p_cargo)) end);
end;
$$;
revoke execute on function public.get_cargo_contact(uuid) from public, anon;
grant execute on function public.get_cargo_contact(uuid) to authenticated, service_role;

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
    -- 0127: a user who hid his phone hides his e-mail too — only he and the
    -- Baş admin see it (plain admins / unlocked carriers no more).
    'email',     case when v_full and (not coalesce(v_u.phone_hidden, false)
                        or p_user = v_me or public.is_chief_admin()) then v_u.email end,
    'reason',    v_reason);
end;
$$;
revoke execute on function public.get_user_contact(uuid) from public, anon;
grant execute on function public.get_user_contact(uuid) to authenticated, service_role;

commit;

notify pgrst, 'reload schema';
