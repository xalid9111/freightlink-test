-- =====================================================================
-- 0012 — Admin panel backend. SAFE FORWARD MIGRATION: only ADDs
-- columns / tables / functions / policies / triggers, and redefines the
-- 0009 user-guard trigger function so it also protects the new
-- moderation columns, and narrows the cargo SELECT policy so loads an
-- admin hides are really hidden (section 9b). No data is changed or
-- deleted. Idempotent (safe to run twice).
--
-- Security model: admin READS use the existing RLS rules (users,
-- cargo are readable by signed-in users; offers, shipments etc. have
-- "…_admin_full" / is_admin() policies since 0002). Every admin WRITE
-- goes through a SECURITY DEFINER function below that (1) refuses
-- non-admins on the server (public.is_admin() = users.role 'admin')
-- and (2) writes an audit-log row with old and new values. No
-- service-role key is used by the app.
-- =====================================================================

-- 1) Moderation columns ----------------------------------------------
alter table public.users add column if not exists is_blocked boolean not null default false;
alter table public.users add column if not exists blocked_until timestamptz;
alter table public.users add column if not exists block_reason text;
alter table public.users add column if not exists is_active boolean not null default true;
alter table public.cargo add column if not exists is_hidden boolean not null default false;

-- Users may not change their own role / verification / moderation flags.
create or replace function public.guard_user_protected_columns()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or public.is_admin() then
    return new;
  end if;
  new.role := old.role;
  new.is_verified := old.is_verified;
  new.is_early_member := old.is_early_member;
  new.is_blocked := old.is_blocked;
  new.blocked_until := old.blocked_until;
  new.block_reason := old.block_reason;
  new.is_active := old.is_active;
  return new;
end;
$$;

-- Owners may not un-hide a load the admin hid.
create or replace function public.guard_cargo_hidden()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or public.is_admin() then
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.is_hidden := false;
  else
    new.is_hidden := old.is_hidden;
  end if;
  return new;
end;
$$;
drop trigger if exists guard_cargo_hidden on public.cargo;
create trigger guard_cargo_hidden before insert or update on public.cargo
  for each row execute function public.guard_cargo_hidden();

-- 2) Blocking is enforced in the database --------------------------
create or replace function public.is_blocked(p_uid uuid default auth.uid())
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.users u
    where u.id = p_uid
      and (u.is_active = false or (u.is_blocked and (u.blocked_until is null or u.blocked_until > now())))
  );
$$;

create or replace function public.assert_not_blocked()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null and public.is_blocked(auth.uid()) then
    raise exception 'account_blocked' using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists assert_not_blocked on public.cargo;
create trigger assert_not_blocked before insert or update on public.cargo
  for each row execute function public.assert_not_blocked();
drop trigger if exists assert_not_blocked on public.offers;
create trigger assert_not_blocked before insert or update on public.offers
  for each row execute function public.assert_not_blocked();
drop trigger if exists assert_not_blocked on public.conversations;
create trigger assert_not_blocked before insert on public.conversations
  for each row execute function public.assert_not_blocked();
drop trigger if exists assert_not_blocked on public.messages;
create trigger assert_not_blocked before insert on public.messages
  for each row execute function public.assert_not_blocked();

-- 3) Audit log -------------------------------------------------------
create table if not exists public.admin_audit_log (
  id uuid primary key default gen_random_uuid(),
  admin_id uuid references public.users(id) on delete set null,
  action text not null,
  entity_type text not null,
  entity_id text,
  old_value jsonb,
  new_value jsonb,
  note text,
  created_at timestamptz not null default now()
);
create index if not exists idx_admin_audit_created on public.admin_audit_log(created_at desc);
alter table public.admin_audit_log enable row level security;
drop policy if exists "audit_admin_select" on public.admin_audit_log;
create policy "audit_admin_select" on public.admin_audit_log
  for select to authenticated using (public.is_admin());
-- No insert/update/delete policies: rows are written only by the
-- SECURITY DEFINER functions below and cannot be edited from the app.

-- 4) Reports (complaints) --------------------------------------------
create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null default auth.uid() references public.users(id) on delete cascade,
  target_type text not null default 'other' check (target_type in ('cargo','user','message','offer','shipment','other')),
  target_id text,
  reason text not null,
  details text,
  status text not null default 'new' check (status in ('new','reviewing','resolved','rejected')),
  admin_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_reports_status on public.reports(status, created_at desc);
alter table public.reports enable row level security;
drop policy if exists "reports_insert_own" on public.reports;
create policy "reports_insert_own" on public.reports
  for insert to authenticated with check (reporter_id = auth.uid() and status = 'new');
drop policy if exists "reports_select_own_or_admin" on public.reports;
create policy "reports_select_own_or_admin" on public.reports
  for select to authenticated using (reporter_id = auth.uid() or public.is_admin());

-- 5) Helpers ---------------------------------------------------------
create or replace function public._require_admin()
returns void language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then
    raise exception 'admin_only' using errcode = '42501';
  end if;
end;
$$;

create or replace function public._admin_log(
  p_action text, p_entity_type text, p_entity_id text,
  p_old jsonb, p_new jsonb, p_note text default null
) returns void language sql security definer set search_path = public as $$
  insert into public.admin_audit_log (admin_id, action, entity_type, entity_id, old_value, new_value, note)
  values (auth.uid(), p_action, p_entity_type, p_entity_id, p_old, p_new, p_note);
$$;
revoke all on function public._admin_log(text, text, text, jsonb, jsonb, text) from public, anon, authenticated;

-- 6) Dashboard -------------------------------------------------------
create or replace function public.admin_dashboard_stats()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare r jsonb;
begin
  perform public._require_admin();
  select jsonb_build_object(
    'users_total',       (select count(*) from users),
    'owners',            (select count(*) from users where role = 'cargo_owner'),
    'carriers',          (select count(*) from users where role = 'carrier'),
    'drivers',           (select count(*) from users where role = 'driver'),
    'admins',            (select count(*) from users where role = 'admin'),
    'blocked',           (select count(*) from users where is_blocked or not is_active),
    'active_24h',        (select count(*) from users where last_seen_at > now() - interval '24 hours'),
    'active_7d',         (select count(*) from users where last_seen_at > now() - interval '7 days'),
    'users_new_1d',      (select count(*) from users where created_at > now() - interval '1 day'),
    'users_new_7d',      (select count(*) from users where created_at > now() - interval '7 days'),
    'users_new_30d',     (select count(*) from users where created_at > now() - interval '30 days'),
    'cargo_total',       (select count(*) from cargo),
    'cargo_active',      (select count(*) from cargo where status = 'new' and not is_hidden),
    'cargo_in_progress', (select count(*) from cargo where status in ('carrier_found','agreed','loading','in_transit','delivered')),
    'cargo_completed',   (select count(*) from cargo where status = 'completed'),
    'cargo_cancelled',   (select count(*) from cargo where status = 'cancelled'),
    'cargo_hidden',      (select count(*) from cargo where is_hidden),
    'cargo_new_1d',      (select count(*) from cargo where created_at > now() - interval '1 day'),
    'cargo_new_7d',      (select count(*) from cargo where created_at > now() - interval '7 days'),
    'cargo_new_30d',     (select count(*) from cargo where created_at > now() - interval '30 days'),
    'shipments_active',  (select count(*) from shipments where status in ('new','carrier_found','agreed','loading','in_transit','delivered')),
    'shipments_total',   (select count(*) from shipments),
    'offers_total',      (select count(*) from offers),
    'offers_pending',    (select count(*) from offers where status = 'pending'),
    'reports_open',      (select count(*) from reports where status in ('new','reviewing')),
    'messages_7d',       (select count(*) from messages where created_at > now() - interval '7 days'),
    'generated_at',      now()
  ) into r;
  return r;
end;
$$;

-- 7) Cargo -----------------------------------------------------------
create or replace function public.admin_update_cargo(p_id uuid, p_patch jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare v_old public.cargo; v_new public.cargo;
begin
  perform public._require_admin();
  select * into v_old from cargo where id = p_id;
  if not found then raise exception 'not_found'; end if;
  update cargo set
    pickup_country      = coalesce(nullif(p_patch->>'pickup_country',''), pickup_country),
    pickup_city         = coalesce(nullif(p_patch->>'pickup_city',''), pickup_city),
    destination_country = coalesce(nullif(p_patch->>'destination_country',''), destination_country),
    destination_city    = coalesce(nullif(p_patch->>'destination_city',''), destination_city),
    cargo_type          = case when p_patch ? 'cargo_type' then nullif(p_patch->>'cargo_type','') else cargo_type end,
    truck_type          = case when p_patch ? 'truck_type' then nullif(p_patch->>'truck_type','') else truck_type end,
    description         = case when p_patch ? 'description' then nullif(p_patch->>'description','') else description end,
    weight_kg           = coalesce((p_patch->>'weight_kg')::numeric, weight_kg),
    offered_price       = coalesce((p_patch->>'offered_price')::numeric, offered_price),
    currency            = coalesce(nullif(p_patch->>'currency',''), currency),
    pickup_date         = coalesce((nullif(p_patch->>'pickup_date',''))::date, pickup_date),
    status              = coalesce(nullif(p_patch->>'status',''), status),
    updated_at          = now()
  where id = p_id
  returning * into v_new;
  perform public._admin_log('cargo.update', 'cargo', p_id::text, to_jsonb(v_old), to_jsonb(v_new));
end;
$$;

create or replace function public.admin_set_cargo_hidden(p_id uuid, p_hidden boolean)
returns void language plpgsql security definer set search_path = public as $$
declare v_old boolean;
begin
  perform public._require_admin();
  select is_hidden into v_old from cargo where id = p_id;
  if not found then raise exception 'not_found'; end if;
  update cargo set is_hidden = p_hidden, updated_at = now() where id = p_id;
  perform public._admin_log(case when p_hidden then 'cargo.hide' else 'cargo.unhide' end, 'cargo', p_id::text,
    jsonb_build_object('is_hidden', v_old), jsonb_build_object('is_hidden', p_hidden));
end;
$$;

-- Permanent delete. Offers, shipment, chats and messages of this load
-- are removed by the existing ON DELETE CASCADE rules. Refused when a
-- payment record exists (financial history must be kept — hide instead).
-- The full row plus related counts are written to the audit log first.
create or replace function public.admin_delete_cargo(p_id uuid, p_reason text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_old jsonb;
begin
  perform public._require_admin();
  select to_jsonb(c) || jsonb_build_object(
    'related_offers',        (select count(*) from offers o where o.cargo_id = c.id),
    'related_shipments',     (select count(*) from shipments s where s.cargo_id = c.id),
    'related_conversations', (select count(*) from conversations v where v.cargo_id = c.id),
    'related_messages',      (select count(*) from messages m join conversations v on v.id = m.conversation_id where v.cargo_id = c.id)
  ) into v_old from cargo c where c.id = p_id;
  if v_old is null then raise exception 'not_found'; end if;
  if exists (select 1 from payments p join shipments s on s.id = p.shipment_id where s.cargo_id = p_id) then
    raise exception 'cargo_has_payments' using errcode = '23503';
  end if;
  perform public._admin_log('cargo.delete', 'cargo', p_id::text, v_old, null, p_reason);
  delete from cargo where id = p_id;
end;
$$;

-- 8) Users -----------------------------------------------------------
create or replace function public.admin_update_user(p_user uuid, p_patch jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare v_old public.users; v_new public.users;
begin
  perform public._require_admin();
  select * into v_old from users where id = p_user;
  if not found then raise exception 'not_found'; end if;
  if p_patch ? 'role' and (p_patch->>'role') not in ('cargo_owner','carrier','driver','admin') then
    raise exception 'invalid_role';
  end if;
  if p_user = auth.uid() and p_patch ? 'role' and p_patch->>'role' <> 'admin' then
    raise exception 'cannot_demote_self';
  end if;
  update users set
    full_name   = coalesce(nullif(p_patch->>'full_name',''), full_name),
    phone       = case when p_patch ? 'phone' then nullif(p_patch->>'phone','') else phone end,
    role        = coalesce(nullif(p_patch->>'role',''), role),
    is_verified = coalesce((p_patch->>'is_verified')::boolean, is_verified),
    updated_at  = now()
  where id = p_user
  returning * into v_new;
  perform public._admin_log('user.update', 'user', p_user::text,
    jsonb_build_object('full_name', v_old.full_name, 'phone', v_old.phone, 'role', v_old.role, 'is_verified', v_old.is_verified),
    jsonb_build_object('full_name', v_new.full_name, 'phone', v_new.phone, 'role', v_new.role, 'is_verified', v_new.is_verified));
end;
$$;

create or replace function public.admin_set_user_block(p_user uuid, p_blocked boolean, p_until timestamptz default null, p_reason text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_old jsonb;
begin
  perform public._require_admin();
  if p_user = auth.uid() then raise exception 'cannot_block_self'; end if;
  select jsonb_build_object('is_blocked', is_blocked, 'blocked_until', blocked_until, 'block_reason', block_reason)
    into v_old from users where id = p_user;
  if v_old is null then raise exception 'not_found'; end if;
  update users set
    is_blocked = p_blocked,
    blocked_until = case when p_blocked then p_until else null end,
    block_reason = case when p_blocked then p_reason else null end,
    updated_at = now()
  where id = p_user;
  perform public._admin_log(case when p_blocked then 'user.block' else 'user.unblock' end, 'user', p_user::text, v_old,
    jsonb_build_object('is_blocked', p_blocked, 'blocked_until', p_until, 'block_reason', p_reason));
end;
$$;

create or replace function public.admin_set_user_active(p_user uuid, p_active boolean)
returns void language plpgsql security definer set search_path = public as $$
declare v_old boolean;
begin
  perform public._require_admin();
  if p_user = auth.uid() then raise exception 'cannot_deactivate_self'; end if;
  select is_active into v_old from users where id = p_user;
  if not found then raise exception 'not_found'; end if;
  update users set is_active = p_active, updated_at = now() where id = p_user;
  perform public._admin_log(case when p_active then 'user.activate' else 'user.deactivate' end, 'user', p_user::text,
    jsonb_build_object('is_active', v_old), jsonb_build_object('is_active', p_active));
end;
$$;

-- "Delete" = permanent deactivation + anonymisation. Loads, chats and
-- shipments of OTHER users reference this account, so the row is kept
-- (no broken history); personal data is wiped, open loads are hidden
-- and the account can no longer act. The login itself can be removed
-- in Supabase → Authentication → Users if required.
create or replace function public.admin_delete_user(p_user uuid, p_reason text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_old jsonb;
begin
  perform public._require_admin();
  if p_user = auth.uid() then raise exception 'cannot_delete_self'; end if;
  select to_jsonb(u) into v_old from users u where u.id = p_user;
  if v_old is null then raise exception 'not_found'; end if;
  perform public._admin_log('user.delete', 'user', p_user::text, v_old, null, p_reason);
  update users set
    full_name = 'Silinmiş istifadəçi',
    phone = null,
    avatar_url = null,
    is_active = false,
    is_blocked = true,
    block_reason = coalesce(nullif(p_reason,''), 'deleted'),
    updated_at = now()
  where id = p_user;
  update cargo set is_hidden = true where owner_id = p_user and status = 'new';
end;
$$;

-- 9) Shipments / offers / reports ---------------------------------------
create or replace function public.admin_set_shipment_status(p_id uuid, p_status text, p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_old text;
begin
  perform public._require_admin();
  if p_status not in ('new','carrier_found','agreed','loading','in_transit','delivered','completed','cancelled') then
    raise exception 'invalid_status';
  end if;
  select status into v_old from shipments where id = p_id;
  if not found then raise exception 'not_found'; end if;
  update shipments set status = p_status, updated_at = now(),
    delivered_at = case when p_status = 'delivered' and delivered_at is null then now() else delivered_at end
  where id = p_id;
  insert into shipment_status (shipment_id, status, note, changed_by) values (p_id, p_status, coalesce(p_note, 'admin'), auth.uid());
  perform public._admin_log('shipment.status', 'shipment', p_id::text,
    jsonb_build_object('status', v_old), jsonb_build_object('status', p_status), p_note);
end;
$$;

create or replace function public.admin_set_offer_status(p_id uuid, p_status text, p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_old text;
begin
  perform public._require_admin();
  if p_status not in ('pending','accepted','rejected','countered','cancelled') then
    raise exception 'invalid_status';
  end if;
  select status into v_old from offers where id = p_id;
  if not found then raise exception 'not_found'; end if;
  update offers set status = p_status where id = p_id;
  perform public._admin_log('offer.status', 'offer', p_id::text,
    jsonb_build_object('status', v_old), jsonb_build_object('status', p_status), p_note);
end;
$$;

create or replace function public.admin_set_report_status(p_id uuid, p_status text, p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_old jsonb;
begin
  perform public._require_admin();
  if p_status not in ('new','reviewing','resolved','rejected') then raise exception 'invalid_status'; end if;
  select jsonb_build_object('status', status, 'admin_note', admin_note) into v_old from reports where id = p_id;
  if v_old is null then raise exception 'not_found'; end if;
  update reports set status = p_status, admin_note = coalesce(p_note, admin_note), updated_at = now() where id = p_id;
  perform public._admin_log('report.status', 'report', p_id::text, v_old,
    jsonb_build_object('status', p_status, 'admin_note', p_note));
end;
$$;

grant execute on function public.admin_dashboard_stats() to authenticated;
grant execute on function public.admin_update_cargo(uuid, jsonb) to authenticated;
grant execute on function public.admin_set_cargo_hidden(uuid, boolean) to authenticated;
grant execute on function public.admin_delete_cargo(uuid, text) to authenticated;
grant execute on function public.admin_update_user(uuid, jsonb) to authenticated;
grant execute on function public.admin_set_user_block(uuid, boolean, timestamptz, text) to authenticated;
grant execute on function public.admin_set_user_active(uuid, boolean) to authenticated;
grant execute on function public.admin_delete_user(uuid, text) to authenticated;
grant execute on function public.admin_set_shipment_status(uuid, text, text) to authenticated;
grant execute on function public.admin_set_offer_status(uuid, text, text) to authenticated;
grant execute on function public.admin_set_report_status(uuid, text, text) to authenticated;

-- 9b) Hidden loads are really hidden ----------------------------------
-- Before: cargo_select_all = true (everyone sees every load). Now a load
-- hidden by an admin is visible only to its owner, admins, and users
-- that already have an offer, shipment or chat on it (so their history
-- keeps working). The participant check is a SECURITY DEFINER helper so that
-- it does not re-enter the offers/shipments RLS (avoids policy recursion).
create or replace function public.can_see_hidden_cargo(p_cargo uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from offers o where o.cargo_id = p_cargo and o.carrier_id = public.current_carrier_id())
      or exists (select 1 from shipments s where s.cargo_id = p_cargo and s.carrier_id = public.current_carrier_id())
      or exists (select 1 from conversations v where v.cargo_id = p_cargo and (v.carrier_user_id = auth.uid() or v.cargo_owner_id = auth.uid()));
$$;
grant execute on function public.can_see_hidden_cargo(uuid) to authenticated;

drop policy if exists "cargo_select_all" on public.cargo;
create policy "cargo_select_all" on public.cargo
  for select using (
    not is_hidden
    or owner_id = auth.uid()
    or public.is_admin()
    or public.can_see_hidden_cargo(id)
  );

-- 10) Realtime for the admin lists ------------------------------------
do $$
declare t text;
begin
  foreach t in array array['cargo','offers','shipments','users','reports','admin_audit_log'] loop
    if not exists (select 1 from pg_publication_tables
                   where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;

-- =====================================================================
-- After running this file, make your own account an admin (run once,
-- in the SQL editor, with YOUR e-mail):
--   update public.users set role = 'admin' where email = 'you@example.com';
-- =====================================================================
