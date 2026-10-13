-- ============================================================
-- FreightLink · Migration 0008 — Fix missing shipments INSERT policy
--
-- BUG FOUND while wiring the "accept offer" flow for the two-phone
-- acceptance test: migration 0002 gave public.shipments SELECT,
-- UPDATE, and admin-ALL policies, but no INSERT policy for a regular
-- user. The app's accept-offer flow (cargo owner accepts a carrier's
-- offer) calls ShipmentRepository.createFromAcceptedOffer(), which
-- INSERTs into public.shipments as the cargo owner — that insert would
-- be rejected outright under RLS, meaning the very last step of the
-- acceptance test ("USER A can see the offer and respond") would
-- appear to work (the offer's status does flip to 'accepted') but
-- silently fail to actually create the shipment, and the Shipments tab
-- would stay empty for both users.
--
-- Fix: a narrowly-scoped INSERT policy — the cargo must belong to the
-- inserting user, AND accepted_offer_id must point at a real offer
-- that is genuinely status = 'accepted'. This isn't just "the owner
-- can insert anything" — a shipment can only ever be created attached
-- to an offer that was legitimately accepted, which is exactly what
-- the one real caller (offer acceptance) does and nothing more.
-- ============================================================

create policy "shipments_owner_insert_on_accept" on public.shipments
  for insert
  with check (
    cargo_id in (select id from public.cargo where owner_id = auth.uid())
    and accepted_offer_id is not null
    and accepted_offer_id in (select id from public.offers where status = 'accepted')
  );

comment on policy "shipments_owner_insert_on_accept" on public.shipments is
  'Allows a cargo owner to create the shipment row that results from '
  'accepting a carrier''s offer on their own cargo — see migration 0008 '
  'header for the bug this fixes. Only carrier-side or admin shipment '
  'creation flows (none exist yet) would need an additional policy.';
