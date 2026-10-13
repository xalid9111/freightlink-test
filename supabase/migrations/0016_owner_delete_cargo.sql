-- =====================================================================
-- 0016 — Owners can DELETE their own load ("Elanı sil").
-- SAFE FORWARD MIGRATION: adds one function. No table/policy changes.
--
-- * Only the load's owner (or an admin) may call it.
-- * Refused once a shipment exists (a carrier already took the job —
--   that history must stay; the admin can still act).
-- * Chats about the load are NOT lost: they are detached from the load
--   (cargo_id = null) and continue as normal person-to-person chats.
-- * Offers, map points etc. go with the load (existing ON DELETE CASCADE).
-- =====================================================================
create or replace function public.delete_my_cargo(p_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare v_owner uuid;
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  select owner_id into v_owner from cargo where id = p_id;
  if v_owner is null then raise exception 'not_found' using errcode = 'P0002'; end if;
  if v_owner <> auth.uid() and not public.is_admin() then
    raise exception 'not_owner' using errcode = '42501';
  end if;
  if exists (select 1 from shipments where cargo_id = p_id) then
    raise exception 'cargo_has_shipment' using errcode = '23503';
  end if;
  update conversations set cargo_id = null where cargo_id = p_id;
  delete from cargo where id = p_id;
end;
$$;
grant execute on function public.delete_my_cargo(uuid) to authenticated;
