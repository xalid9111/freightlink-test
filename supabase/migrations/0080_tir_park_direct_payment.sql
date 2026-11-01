-- =====================================================================
-- 0080 — TIR park booking: direct bank transfer to the park (owner,
-- 01.11.2026). Replaces the card checkout of 0079 for bookings.
--
-- FreightLink takes NO money and asks NO card data from the driver; it
-- only connects the park and the driver and keeps the booking status:
--
-- 1. The park's approved manager enters the park's own payment details
--    (holder, bank, IBAN / account, card number for transfers, note) —
--    tir_park_pay_details. Not on the park card, not readable by anybody
--    but the manager and admins.
-- 2. A driver books (space held 60 minutes) and only then sees the
--    details of THAT park (tir_park_booking_pay_details, own booking).
-- 3. He transfers the money himself and uploads the receipt picture
--    (private bucket tirpark-receipts, own folder) →
--    tir_park_booking_receipt → status 'payment_review' ("Ödəniş
--    yoxlanılır"); the space stays held.
-- 4. The manager checks his account and presses "Ödənişi təsdiqlə"
--    (tir_park_booking_confirm_payment) → 'confirmed', booking number +
--    a random one-time entry code (QR in the app). "Rədd et"
--    (tir_park_booking_reject_payment) sends it back to the driver to
--    upload again (a new 60-minute hold).
--
-- The 0079 card checkout for bookings is closed
-- (tir_park_booking_payment_create → 'payments_disabled'); no other
-- payment (ads, VIP, promotions) changes. A booking is open only when its
-- park has payment details.
--
-- Safe: forward-only, re-runnable. One new table, one private bucket,
-- new nullable columns, a wider status list, functions re-created. No row
-- is deleted. Needs 0079.
-- =====================================================================

begin;

-- 1) The park's payment details (manager / admin only) --------------------
create table if not exists public.tir_park_pay_details (
  park_id uuid primary key references public.tir_parks(id) on delete cascade,
  holder text not null check (char_length(btrim(holder)) between 2 and 120),
  bank text check (bank is null or char_length(bank) <= 120),
  account text check (account is null or char_length(account) <= 64),
  card text check (card is null or card ~ '^[0-9 ]{12,23}$'),
  note text check (note is null or char_length(note) <= 300),
  updated_at timestamptz not null default now(),
  updated_by uuid references public.users(id) on delete set null,
  check (account is not null or card is not null)
);
alter table public.tir_park_pay_details enable row level security;
revoke all on public.tir_park_pay_details from anon, authenticated;
-- Read and written only through the functions below.

create or replace function public.tir_park_set_pay_details(
  p_park uuid, p_holder text, p_bank text, p_account text, p_card text, p_note text default null)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_card text := nullif(regexp_replace(coalesce(p_card, ''), '[^0-9]', '', 'g'), '');
  v_acc text := nullif(upper(regexp_replace(coalesce(p_account, ''), '\s', '', 'g')), '');
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if not exists (select 1 from tir_parks where id = p_park and manager_id = auth.uid() and manager_status = 'approved')
     and not public.is_admin() then
    raise exception 'not_allowed' using errcode = '42501';
  end if;
  if p_holder is null or char_length(btrim(p_holder)) not between 2 and 120
     or (v_card is null and v_acc is null)
     or (v_card is not null and length(v_card) not between 12 and 19)
     or (v_acc is not null and (length(v_acc) > 64 or v_acc !~ '^[A-Z0-9]+$'))
     or (p_bank is not null and char_length(p_bank) > 120)
     or (p_note is not null and char_length(p_note) > 300) then
    raise exception 'invalid_argument' using errcode = '22023';
  end if;
  insert into tir_park_pay_details (park_id, holder, bank, account, card, note, updated_at, updated_by)
  values (p_park, btrim(p_holder), nullif(btrim(coalesce(p_bank, '')), ''), v_acc,
          case when v_card is null then null else regexp_replace(v_card, '(\d{4})(?=\d)', '\1 ', 'g') end,
          nullif(btrim(coalesce(p_note, '')), ''), now(), auth.uid())
  on conflict (park_id) do update
    set holder = excluded.holder, bank = excluded.bank, account = excluded.account, card = excluded.card,
        note = excluded.note, updated_at = now(), updated_by = auth.uid();
end $$;
revoke all on function public.tir_park_set_pay_details(uuid, text, text, text, text, text) from public, anon;
grant execute on function public.tir_park_set_pay_details(uuid, text, text, text, text, text) to authenticated;

create or replace function public.tir_park_get_pay_details(p_park uuid)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null or not public.is_tir_park_manager(p_park) then raise exception 'not_allowed' using errcode = '42501'; end if;
  return (select to_jsonb(d) - 'updated_by' from tir_park_pay_details d where park_id = p_park);
end $$;
revoke all on function public.tir_park_get_pay_details(uuid) from public, anon;
grant execute on function public.tir_park_get_pay_details(uuid) to authenticated;

-- 2) Bookings: "Ödəniş yoxlanılır", receipt, transfer -------------------------
alter table public.tir_park_bookings add column if not exists receipt_path text;
alter table public.tir_park_bookings add column if not exists receipt_at timestamptz;
alter table public.tir_park_bookings add column if not exists paid_confirmed_by uuid references public.users(id) on delete set null;
alter table public.tir_park_bookings add column if not exists reject_note text;
alter table public.tir_park_bookings drop constraint if exists tir_park_bookings_status_check;
alter table public.tir_park_bookings add constraint tir_park_bookings_status_check check (status in
  ('pending_payment', 'payment_review', 'confirmed', 'checked_in', 'completed', 'cancelled', 'expired', 'refund_pending', 'refunded'));
alter table public.tir_park_bookings drop constraint if exists tir_park_bookings_paid_mode_check;
alter table public.tir_park_bookings add constraint tir_park_bookings_paid_mode_check
  check (paid_mode is null or paid_mode in ('test', 'live', 'transfer'));
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'tir_park_bookings_extra_check') then
    alter table public.tir_park_bookings add constraint tir_park_bookings_extra_check check (
          (receipt_path is null or char_length(receipt_path) <= 300)
      and (reject_note is null or char_length(reject_note) <= 200));
  end if;
end $$;

-- Open for booking now also needs the park's payment details.
create or replace function public.tir_park_bookable(p tir_parks)
returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select p.status = 'approved' and p.manager_status = 'approved' and p.booking_open
     and coalesce(p.price, 0) > 0 and p.price_unit is not null and coalesce(p.bookable, 0) > 0
     and exists (select 1 from tir_park_pay_details d where d.park_id = p.id);
$$;

-- A booking whose receipt is being checked keeps its space.
create or replace function public._tir_park_used(p_park uuid, p_from timestamptz, p_to timestamptz, p_except uuid default null)
returns integer language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(sum(trucks), 0)::int from tir_park_bookings
   where park_id = p_park and start_at < p_to and end_at > p_from
     and (p_except is null or id <> p_except)
     and (status in ('confirmed', 'checked_in', 'payment_review') or (status = 'pending_payment' and hold_until > now()));
$$;
revoke all on function public._tir_park_used(uuid, timestamptz, timestamptz, uuid) from public, anon, authenticated;

-- 0079's booking with a 60-minute hold (time for a bank transfer).
create or replace function public.tir_park_booking_create(p_park uuid, p_from timestamptz, p_to timestamptz, p_trucks integer)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_uid uuid := auth.uid();
  p tir_parks;
  v_units integer;
  v_secs double precision;
  v_b tir_park_bookings;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if public.is_blocked(v_uid) then raise exception 'blocked' using errcode = '42501'; end if;
  if p_trucks is null or p_trucks not between 1 and 50 then raise exception 'invalid_argument' using errcode = '22023'; end if;
  if p_from is null or p_to is null or p_to <= p_from or p_from < now() - interval '15 minutes'
     or p_to - p_from > interval '30 days' then
    raise exception 'invalid_time' using errcode = '22023';
  end if;
  select * into p from tir_parks where id = p_park for update;
  if p.id is null or not public.tir_park_bookable(p) then raise exception 'not_bookable' using errcode = '22023'; end if;
  if p.manager_id = v_uid then raise exception 'own_park' using errcode = '22023'; end if;
  if (select count(*) from tir_park_bookings where user_id = v_uid and status = 'pending_payment' and hold_until > now()) >= 3 then
    raise exception 'too_many' using errcode = '54000';
  end if;
  perform public._tir_park_expire_holds(p_park);
  if p.bookable - public._tir_park_used(p_park, p_from, p_to) < p_trucks then
    raise exception 'no_space' using errcode = '23P01';
  end if;
  v_secs := extract(epoch from (p_to - p_from));
  v_units := greatest(1, ceil(v_secs / case when p.price_unit = 'hour' then 3600 else 86400 end)::int);
  insert into tir_park_bookings (booking_no, park_id, user_id, trucks, start_at, end_at, units, unit, price, amount, currency,
                                 status, hold_until)
  values ('TP' || to_char(now(), 'YYMMDD') || '-' || upper(substr(md5(gen_random_uuid()::text), 1, 6)),
          p_park, v_uid, p_trucks, p_from, p_to, v_units, p.price_unit, p.price,
          round(p.price * v_units * p_trucks, 2), p.currency, 'pending_payment', now() + interval '60 minutes')
  returning * into v_b;
  return to_jsonb(v_b) - 'code';
end $$;
revoke all on function public.tir_park_booking_create(uuid, timestamptz, timestamptz, integer) from public, anon;
grant execute on function public.tir_park_booking_create(uuid, timestamptz, timestamptz, integer) to authenticated;

-- The details to pay to: only the driver of this booking, only while it
-- waits for (or checks) his payment.
create or replace function public.tir_park_booking_pay_details(p_booking uuid)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_b tir_park_bookings;
begin
  select * into v_b from tir_park_bookings where id = p_booking;
  if v_b.id is null or v_b.user_id is distinct from auth.uid() then raise exception 'not_found' using errcode = 'P0002'; end if;
  if v_b.status not in ('pending_payment', 'payment_review') then raise exception 'not_payable' using errcode = '22023'; end if;
  return (select jsonb_build_object('holder', d.holder, 'bank', d.bank, 'account', d.account, 'card', d.card, 'note', d.note,
                                    'park', p.name, 'phone', p.phone, 'amount', v_b.amount, 'currency', v_b.currency,
                                    'booking_no', v_b.booking_no, 'hold_until', v_b.hold_until)
            from tir_park_pay_details d join tir_parks p on p.id = d.park_id where d.park_id = v_b.park_id);
end $$;
revoke all on function public.tir_park_booking_pay_details(uuid) from public, anon;
grant execute on function public.tir_park_booking_pay_details(uuid) to authenticated;

-- 3) Receipts: private bucket, folder = <driver id>/<booking id>/ ----------
insert into storage.buckets (id, name, public, file_size_limit)
values ('tirpark-receipts', 'tirpark-receipts', false, 10485760)
on conflict (id) do nothing;

create or replace function public.is_own_tir_park_booking(p_booking text)
returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select exists (select 1 from tir_park_bookings where id::text = p_booking and user_id = auth.uid());
$$;
revoke all on function public.is_own_tir_park_booking(text) from public, anon;
grant execute on function public.is_own_tir_park_booking(text) to authenticated;

-- The park's manager (or an admin) may look at a receipt of his park.
create or replace function public.can_see_tir_park_receipt(p_booking text)
returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select exists (select 1 from tir_park_bookings b
                  where b.id::text = p_booking
                    and (b.user_id = auth.uid() or public.is_tir_park_manager(b.park_id)));
$$;
revoke all on function public.can_see_tir_park_receipt(text) from public, anon;
grant execute on function public.can_see_tir_park_receipt(text) to authenticated;

drop policy if exists "tirpark_receipts_insert_own" on storage.objects;
create policy "tirpark_receipts_insert_own" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'tirpark-receipts'
              and (storage.foldername(name))[1] = auth.uid()::text
              and public.is_own_tir_park_booking((storage.foldername(name))[2]));
drop policy if exists "tirpark_receipts_read" on storage.objects;
create policy "tirpark_receipts_read" on storage.objects
  for select to authenticated
  using (bucket_id = 'tirpark-receipts' and public.can_see_tir_park_receipt((storage.foldername(name))[2]));

-- The driver attaches his receipt → "Ödəniş yoxlanılır" (nothing is paid
-- by FreightLink; the manager decides).
create or replace function public.tir_park_booking_receipt(p_booking uuid, p_path text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_b tir_park_bookings;
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if p_path is null or p_path not like auth.uid()::text || '/' || p_booking::text || '/%' or p_path like '%..%'
     or char_length(p_path) > 300 then
    raise exception 'invalid_path' using errcode = '22023';
  end if;
  select * into v_b from tir_park_bookings where id = p_booking for update;
  if v_b.id is null or v_b.user_id is distinct from auth.uid() then raise exception 'not_found' using errcode = 'P0002'; end if;
  if not (v_b.status = 'pending_payment' and v_b.hold_until > now()) and v_b.status <> 'payment_review' then
    raise exception 'not_payable' using errcode = '22023';
  end if;
  update tir_park_bookings set receipt_path = p_path, receipt_at = now(), status = 'payment_review', hold_until = null,
                               reject_note = null, updated_at = now()
   where id = p_booking;
end $$;
revoke all on function public.tir_park_booking_receipt(uuid, text) from public, anon;
grant execute on function public.tir_park_booking_receipt(uuid, text) to authenticated;

-- 4) The manager confirms the money is on his account → code -------------------
create or replace function public.tir_park_booking_confirm_payment(p_booking uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_b tir_park_bookings;
  v_code text;
begin
  select * into v_b from tir_park_bookings where id = p_booking;
  if v_b.id is null or not public.is_tir_park_manager(v_b.park_id) then raise exception 'not_allowed' using errcode = '42501'; end if;
  perform 1 from tir_parks where id = v_b.park_id for update;   -- the same lock as booking
  select * into v_b from tir_park_bookings where id = p_booking for update;
  if v_b.status <> 'payment_review' then raise exception 'not_in_review' using errcode = '22023'; end if;
  loop
    v_code := public._tir_park_new_code();
    exit when not exists (select 1 from tir_park_bookings where code = v_code);
  end loop;
  update tir_park_bookings
     set status = 'confirmed', paid_mode = 'transfer', code = v_code, confirmed_at = now(), paid_confirmed_by = auth.uid(),
         hold_until = null, updated_at = now()
   where id = p_booking returning * into v_b;
  return to_jsonb(v_b) - 'code';
end $$;
revoke all on function public.tir_park_booking_confirm_payment(uuid) from public, anon;
grant execute on function public.tir_park_booking_confirm_payment(uuid) to authenticated;

-- The money did not come: back to the driver (upload again, 60 minutes).
create or replace function public.tir_park_booking_reject_payment(p_booking uuid, p_note text default null)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_b tir_park_bookings;
begin
  select * into v_b from tir_park_bookings where id = p_booking for update;
  if v_b.id is null or not public.is_tir_park_manager(v_b.park_id) then raise exception 'not_allowed' using errcode = '42501'; end if;
  if v_b.status <> 'payment_review' then raise exception 'not_in_review' using errcode = '22023'; end if;
  update tir_park_bookings
     set status = 'pending_payment', hold_until = now() + interval '60 minutes',
         reject_note = left(nullif(btrim(coalesce(p_note, '')), ''), 200), updated_at = now()
   where id = p_booking;
end $$;
revoke all on function public.tir_park_booking_reject_payment(uuid, text) from public, anon;
grant execute on function public.tir_park_booking_reject_payment(uuid, text) to authenticated;

-- The driver may cancel while nothing is confirmed, or before arrival.
create or replace function public.tir_park_booking_cancel(p_booking uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_b tir_park_bookings;
begin
  select * into v_b from tir_park_bookings where id = p_booking for update;
  if v_b.id is null or v_b.user_id is distinct from auth.uid() then raise exception 'not_found' using errcode = 'P0002'; end if;
  if v_b.status not in ('pending_payment', 'payment_review', 'confirmed') then raise exception 'not_cancellable' using errcode = '22023'; end if;
  update tir_park_bookings set status = 'cancelled', cancelled_at = now(), cancel_reason = 'driver', hold_until = null, updated_at = now()
   where id = p_booking;
end $$;
revoke all on function public.tir_park_booking_cancel(uuid) from public, anon;
grant execute on function public.tir_park_booking_cancel(uuid) to authenticated;

-- The manager's list now carries the receipt path (to open it) and the note.
create or replace function public.tir_park_manager_bookings(p_park uuid)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null or not public.is_tir_park_manager(p_park) then raise exception 'not_allowed' using errcode = '42501'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', b.id, 'booking_no', b.booking_no, 'trucks', b.trucks, 'start_at', b.start_at, 'end_at', b.end_at,
      'status', case when b.status = 'pending_payment' and b.hold_until <= now() then 'expired' else b.status end,
      'amount', b.amount, 'currency', b.currency, 'paid_mode', b.paid_mode,
      'receipt_path', b.receipt_path, 'receipt_at', b.receipt_at,
      'checked_in_at', b.checked_in_at, 'checked_out_at', b.checked_out_at,
      'driver', u.full_name)
      order by (b.status = 'payment_review') desc, b.start_at desc)
      from (select * from tir_park_bookings where park_id = p_park order by start_at desc limit 300) b
      left join users u on u.id = b.user_id), '[]'::jsonb);
end $$;
revoke all on function public.tir_park_manager_bookings(uuid) from public, anon;
grant execute on function public.tir_park_manager_bookings(uuid) to authenticated;

-- The admin may also set "Ödəniş yoxlanılır".
create or replace function public.admin_tir_park_booking_set_status(p_booking uuid, p_status text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_b tir_park_bookings;
begin
  perform public._require_admin();
  if p_status not in ('payment_review', 'confirmed', 'checked_in', 'completed', 'cancelled', 'expired') then
    raise exception 'invalid_argument' using errcode = '22023';
  end if;
  select * into v_b from tir_park_bookings where id = p_booking for update;
  if v_b.id is null then raise exception 'not_found' using errcode = 'P0002'; end if;
  if p_status in ('confirmed', 'checked_in') and v_b.code is null then raise exception 'not_paid' using errcode = '22023'; end if;
  update tir_park_bookings
     set status = p_status, updated_at = now(),
         checked_in_at = case when p_status = 'checked_in' then coalesce(checked_in_at, now()) else checked_in_at end,
         checked_out_at = case when p_status = 'completed' then coalesce(checked_out_at, now()) else checked_out_at end,
         cancelled_at = case when p_status = 'cancelled' then coalesce(cancelled_at, now()) else cancelled_at end,
         cancel_reason = case when p_status = 'cancelled' then coalesce(cancel_reason, 'admin') else cancel_reason end
   where id = p_booking;
  perform public._admin_log('tir_park.booking_' || p_status, 'tir_park_bookings', p_booking::text,
    jsonb_build_object('status', v_b.status), jsonb_build_object('status', p_status, 'booking_no', v_b.booking_no));
end $$;
revoke all on function public.admin_tir_park_booking_set_status(uuid, text) from public, anon;
grant execute on function public.admin_tir_park_booking_set_status(uuid, text) to authenticated;

-- 5) The 0079 card checkout for bookings is closed: FreightLink takes no
-- money for parks. (Ads, VIP and promotions keep their checkout.)
create or replace function public.tir_park_booking_payment_create(p_booking uuid, p_method text, p_key text)
returns public.ad_payments language plpgsql security definer set search_path = public, pg_temp as $$
begin
  raise exception 'payments_disabled' using errcode = '42501';
end $$;
revoke all on function public.tir_park_booking_payment_create(uuid, text, text) from public, anon;
grant execute on function public.tir_park_booking_payment_create(uuid, text, text) to authenticated;

-- Final check: everything in place.
do $$
begin
  if to_regclass('public.tir_park_pay_details') is null
     or not exists (select 1 from storage.buckets where id = 'tirpark-receipts')
     or to_regprocedure('public.tir_park_set_pay_details(uuid, text, text, text, text, text)') is null
     or to_regprocedure('public.tir_park_booking_pay_details(uuid)') is null
     or to_regprocedure('public.tir_park_booking_receipt(uuid, text)') is null
     or to_regprocedure('public.tir_park_booking_confirm_payment(uuid)') is null
     or to_regprocedure('public.tir_park_booking_reject_payment(uuid, text)') is null then
    raise exception '0080: final check failed — nothing changed';
  end if;
end $$;

commit;
