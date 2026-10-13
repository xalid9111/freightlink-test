-- ============================================================
-- FreightLink · Migration 0002 — Row Level Security
-- Every user-facing table gets RLS enabled + explicit policies.
-- Default-deny: a table with RLS on and no matching policy denies
-- the request, so anything not covered here is closed by default.
-- ============================================================

create or replace function public.is_admin() returns boolean as $$
  select exists (select 1 from public.users where id = auth.uid() and role = 'admin');
$$ language sql stable security definer;

create or replace function public.current_carrier_id() returns uuid as $$
  select id from public.carriers where user_id = auth.uid();
$$ language sql stable security definer;

-- ---------------------------------------------------------------
-- USERS
-- ---------------------------------------------------------------
alter table public.users enable row level security;

create policy "users_select_all" on public.users
  for select using (true); -- profiles are semi-public (name/rating shown on cards)

create policy "users_update_self" on public.users
  for update using (auth.uid() = id)
  with check (
    auth.uid() = id
    and role = (select role from public.users u where u.id = auth.uid())
    -- role can never be changed by the user themself, only by an admin (brief §5)
  );

create policy "users_admin_full" on public.users
  for all using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------
-- COMPANIES
-- ---------------------------------------------------------------
alter table public.companies enable row level security;

create policy "companies_select_all" on public.companies for select using (true);
create policy "companies_owner_write" on public.companies
  for all using (auth.uid() = owner_user_id) with check (auth.uid() = owner_user_id);
create policy "companies_admin_full" on public.companies for all using (public.is_admin());

-- ---------------------------------------------------------------
-- CARRIERS / DRIVERS / TRUCKS
-- ---------------------------------------------------------------
alter table public.carriers enable row level security;
alter table public.drivers enable row level security;
alter table public.trucks enable row level security;

create policy "carriers_select_all" on public.carriers for select using (true);
create policy "carriers_owner_write" on public.carriers
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "carriers_admin_full" on public.carriers for all using (public.is_admin());

-- Driver: can read/update only their own driver row; carrier who owns
-- the driver can also manage it (a company adds/edits its drivers).
create policy "drivers_select_all" on public.drivers for select using (true);
create policy "drivers_self_update" on public.drivers
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "drivers_carrier_manage" on public.drivers
  for all using (carrier_id = public.current_carrier_id())
  with check (carrier_id = public.current_carrier_id());
create policy "drivers_admin_full" on public.drivers for all using (public.is_admin());

create policy "trucks_select_all" on public.trucks for select using (true);
create policy "trucks_carrier_write" on public.trucks
  for all using (carrier_id = public.current_carrier_id())
  with check (carrier_id = public.current_carrier_id());
create policy "trucks_admin_full" on public.trucks for all using (public.is_admin());

-- ---------------------------------------------------------------
-- CARGO / CARGO_DOCUMENTS
-- ---------------------------------------------------------------
alter table public.cargo enable row level security;
alter table public.cargo_documents enable row level security;

create policy "cargo_select_all" on public.cargo
  for select using (true); -- open marketplace, per brief §6/§8

create policy "cargo_owner_write" on public.cargo
  for all using (auth.uid() = owner_id) with check (auth.uid() = owner_id);

create policy "cargo_admin_full" on public.cargo for all using (public.is_admin());

create policy "cargo_documents_select" on public.cargo_documents
  for select using (
    cargo_id in (select id from public.cargo where owner_id = auth.uid())
    or cargo_id in (
      select cargo_id from public.offers where carrier_id = public.current_carrier_id()
    )
    or public.is_admin()
  );
create policy "cargo_documents_owner_insert" on public.cargo_documents
  for insert with check (
    cargo_id in (select id from public.cargo where owner_id = auth.uid())
  );

-- ---------------------------------------------------------------
-- OFFERS
-- ---------------------------------------------------------------
alter table public.offers enable row level security;

-- Visible to: the carrier who made the offer, and the owner of the cargo it is on.
create policy "offers_participants_select" on public.offers
  for select using (
    carrier_id = public.current_carrier_id()
    or cargo_id in (select id from public.cargo where owner_id = auth.uid())
    or public.is_admin()
  );

create policy "offers_carrier_insert" on public.offers
  for insert with check (carrier_id = public.current_carrier_id());

-- A carrier can update/cancel their own pending offer; a cargo owner can
-- accept/reject/counter an offer made on their cargo. Both cases are
-- "update", so the WITH CHECK keeps each side inside its own lane.
create policy "offers_carrier_update_own" on public.offers
  for update using (carrier_id = public.current_carrier_id())
  with check (carrier_id = public.current_carrier_id());

create policy "offers_owner_respond" on public.offers
  for update using (cargo_id in (select id from public.cargo where owner_id = auth.uid()))
  with check (cargo_id in (select id from public.cargo where owner_id = auth.uid()));

-- ---------------------------------------------------------------
-- SHIPMENTS / SHIPMENT_STATUS
-- ---------------------------------------------------------------
alter table public.shipments enable row level security;
alter table public.shipment_status enable row level security;

create policy "shipments_participants_select" on public.shipments
  for select using (
    carrier_id = public.current_carrier_id()
    or cargo_id in (select id from public.cargo where owner_id = auth.uid())
    or driver_id in (select id from public.drivers where user_id = auth.uid())
    or public.is_admin()
  );

create policy "shipments_participants_update" on public.shipments
  for update using (
    carrier_id = public.current_carrier_id()
    or cargo_id in (select id from public.cargo where owner_id = auth.uid())
  )
  with check (
    carrier_id = public.current_carrier_id()
    or cargo_id in (select id from public.cargo where owner_id = auth.uid())
  );

create policy "shipments_admin_full" on public.shipments for all using (public.is_admin());

create policy "shipment_status_select" on public.shipment_status
  for select using (
    shipment_id in (
      select id from public.shipments
      where carrier_id = public.current_carrier_id()
         or cargo_id in (select id from public.cargo where owner_id = auth.uid())
    ) or public.is_admin()
  );
create policy "shipment_status_insert" on public.shipment_status
  for insert with check (
    shipment_id in (
      select id from public.shipments
      where carrier_id = public.current_carrier_id()
         or cargo_id in (select id from public.cargo where owner_id = auth.uid())
    )
  );

-- ---------------------------------------------------------------
-- LOCATIONS / ROUTES
-- ---------------------------------------------------------------
alter table public.locations enable row level security;
alter table public.routes enable row level security;

-- Truck location pings: only the owning carrier can write; visible to
-- that carrier and to the cargo owner of any shipment currently using it.
create policy "locations_write_own_truck" on public.locations
  for insert with check (
    truck_id in (select id from public.trucks where carrier_id = public.current_carrier_id())
  );
create policy "locations_select_relevant" on public.locations
  for select using (
    truck_id in (select id from public.trucks where carrier_id = public.current_carrier_id())
    or shipment_id in (
      select id from public.shipments where cargo_id in (
        select id from public.cargo where owner_id = auth.uid()
      )
    )
    or public.is_admin()
  );

create policy "routes_select_participants" on public.routes
  for select using (
    shipment_id in (
      select id from public.shipments
      where carrier_id = public.current_carrier_id()
         or cargo_id in (select id from public.cargo where owner_id = auth.uid())
    ) or public.is_admin()
  );

-- ---------------------------------------------------------------
-- CONVERSATIONS / MESSAGES
-- ---------------------------------------------------------------
alter table public.conversations enable row level security;
alter table public.messages enable row level security;
alter table public.message_attachments enable row level security;

create policy "conversations_participants" on public.conversations
  for select using (auth.uid() = cargo_owner_id or auth.uid() = carrier_user_id or public.is_admin());
create policy "conversations_create" on public.conversations
  for insert with check (auth.uid() = cargo_owner_id or auth.uid() = carrier_user_id);

create policy "messages_participants_select" on public.messages
  for select using (auth.uid() = sender_id or auth.uid() = receiver_id or public.is_admin());
create policy "messages_send" on public.messages
  for insert with check (auth.uid() = sender_id);
create policy "messages_mark_read" on public.messages
  for update using (auth.uid() = receiver_id) with check (auth.uid() = receiver_id);

-- attachments are only reachable via a message row the RLS above already
-- filtered, so a permissive select is safe here (no direct enumeration path).
create policy "message_attachments_select" on public.message_attachments
  for select using (
    id in (select attachment_id from public.messages where attachment_id is not null)
  );
create policy "message_attachments_insert" on public.message_attachments
  for insert with check (auth.uid() is not null);

-- ---------------------------------------------------------------
-- RATINGS
-- ---------------------------------------------------------------
alter table public.ratings enable row level security;

create policy "ratings_select_all" on public.ratings for select using (true);
create policy "ratings_insert_participant" on public.ratings
  for insert with check (
    auth.uid() = reviewer_id
    and shipment_id in (
      select id from public.shipments
      where status = 'completed' and (
        carrier_id = public.current_carrier_id()
        or cargo_id in (select id from public.cargo where owner_id = auth.uid())
      )
    )
  );

-- ---------------------------------------------------------------
-- VERIFICATION DOCUMENTS
-- ---------------------------------------------------------------
alter table public.verification_documents enable row level security;

create policy "verification_owner_select" on public.verification_documents
  for select using (auth.uid() = user_id or public.is_admin());
create policy "verification_owner_insert" on public.verification_documents
  for insert with check (auth.uid() = user_id);
create policy "verification_admin_review" on public.verification_documents
  for update using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------
-- AI MATCHES
-- ---------------------------------------------------------------
alter table public.ai_matches enable row level security;

-- Match results are operational data for the carrier they were
-- computed for, and for the owner of the cargo being matched.
create policy "ai_matches_select" on public.ai_matches
  for select using (
    carrier_id = public.current_carrier_id()
    or cargo_id in (select id from public.cargo where owner_id = auth.uid())
    or public.is_admin()
  );
-- Only the Edge Function (service_role key, which bypasses RLS entirely)
-- writes ai_matches — no client-side insert policy is defined on purpose.

-- ---------------------------------------------------------------
-- PAYMENTS
-- ---------------------------------------------------------------
alter table public.payments enable row level security;

create policy "payments_participants_select" on public.payments
  for select using (auth.uid() = payer_id or auth.uid() = payee_id or public.is_admin());
-- Inserts/updates happen only via a service-role Edge Function (Phase 15),
-- so no client-facing write policy is defined here.

-- ---------------------------------------------------------------
-- NOTIFICATIONS
-- ---------------------------------------------------------------
alter table public.notifications enable row level security;

create policy "notifications_owner_select" on public.notifications
  for select using (auth.uid() = user_id);
create policy "notifications_owner_mark_read" on public.notifications
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ---------------------------------------------------------------
-- PLATFORM SETTINGS — admin only, everyone else has no access at all.
-- ---------------------------------------------------------------
alter table public.platform_settings enable row level security;

create policy "platform_settings_admin_only" on public.platform_settings
  for all using (public.is_admin()) with check (public.is_admin());
