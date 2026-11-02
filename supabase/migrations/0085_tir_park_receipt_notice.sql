-- =====================================================================
-- 0085 — TIR park booking: the manager is told about a receipt
-- (owner, 03.11.2026).
--
-- Run AFTER 0079 … 0084.
--
-- 1. When a driver uploads his receipt ("Ödəniş yoxlanılır"), the park's
--    manager is told (the owner chose "Profil + Mesajlar"):
--      * a row in the existing notifications table (type
--        'tirpark_payment_review', once per receipt) — the app shows the
--        count on Profil → "TIR parkı idarə edirəm";
--      * a message from the driver in the existing Mesajlar (the direct
--        chat between the two): truck, dates, amount, where to confirm.
--    Telling never blocks the receipt: if a notice cannot be written the
--    receipt still goes through.
--    tir_park_manager_pending(): how many receipts wait for the signed-in
--    manager (his approved parks only).
-- (Days only — the owner's second ask — is done in the app: drivers pick
-- a day, managers set a price per day; the server rules stay as they are,
-- so bookings already made by the hour keep working.)
--
-- Safe: forward-only, re-runnable. Functions created / re-created only.
-- No table, column or row is dropped or rewritten.
-- =====================================================================

begin;

do $$
begin
  if to_regprocedure('public.tir_park_booking_receipt(uuid, text)') is null
     or to_regclass('public.notifications_dedupe_key') is null
     or to_regprocedure('public.tir_park_booking_create(uuid, timestamptz, timestamptz, integer, text)') is null then
    raise exception '0085: run 0069 and 0079 … 0082 first — nothing changed';
  end if;
end $$;

-- 1) Receipt → "Ödəniş yoxlanılır" + the manager is told.
create or replace function public.tir_park_booking_receipt(p_booking uuid, p_path text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_b tir_park_bookings;
  v_p tir_parks;
  v_first boolean;
  v_conv conversations;
  v_text text;
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
  v_first := v_b.status = 'pending_payment';
  update tir_park_bookings set receipt_path = p_path, receipt_at = now(), status = 'payment_review', hold_until = null,
                               reject_note = null, updated_at = now()
   where id = p_booking returning * into v_b;

  select * into v_p from tir_parks where id = v_b.park_id;
  if v_p.manager_id is null or v_p.manager_status is distinct from 'approved' or v_p.manager_id = v_b.user_id then
    return;
  end if;
  v_text := 'Ödəniş etdim, qəbz yükləndi.'
    || E'\nPark: ' || v_p.name
    || coalesce(E'\nMaşın: ' || v_b.plate, '')
    || E'\nTarix: ' || to_char(v_b.start_at at time zone 'Asia/Baku', 'DD.MM.YYYY')
    || ' – ' || to_char(v_b.end_at at time zone 'Asia/Baku', 'DD.MM.YYYY')
    || ' (' || v_b.units || ' ' || case when v_b.unit = 'day' then 'gün' else 'saat' end || ', ' || v_b.trucks || ' TIR)'
    || E'\nMəbləğ: ' || to_char(v_b.amount, 'FM999999990.00') || ' ' || v_b.currency
    || E'\nTəsdiq: Profil → TIR parkı idarə edirəm → Ödənişi təsdiqlə';

  -- The notice (once per receipt).
  begin
    insert into notifications (user_id, type, title, body, data)
    values (v_p.manager_id, 'tirpark_payment_review',
            'Yeni ödəniş: ' || coalesce(v_b.plate, v_b.booking_no),
            v_p.name || ' · ' || to_char(v_b.amount, 'FM999999990.00') || ' ' || v_b.currency,
            jsonb_build_object('booking_id', v_b.id, 'park_id', v_b.park_id,
                               'dedupe', 'tpr:' || v_b.id || ':' || extract(epoch from v_b.receipt_at)::bigint))
    on conflict ((data ->> 'dedupe')) where data ? 'dedupe' do nothing;
  exception when others then
    null;   -- a notice never stops the receipt
  end;

  -- The message in Mesajlar (when the receipt first comes in).
  if v_first then
    begin
      v_conv := public.get_or_create_direct_conversation(v_p.manager_id);
      insert into messages (conversation_id, sender_id, receiver_id, message)
      values (v_conv.id, v_b.user_id, v_p.manager_id, v_text);
    exception when others then
      null;   -- e.g. one of them blocked: the receipt still goes through
    end;
  end if;
end $$;
revoke all on function public.tir_park_booking_receipt(uuid, text) from public, anon;
grant execute on function public.tir_park_booking_receipt(uuid, text) to authenticated;

-- How many receipts wait for the signed-in manager.
create or replace function public.tir_park_manager_pending()
returns integer language sql stable security definer set search_path = public, pg_temp as $$
  select count(*)::int
    from tir_park_bookings b
    join tir_parks p on p.id = b.park_id
   where p.manager_id = auth.uid() and p.manager_status = 'approved' and b.status = 'payment_review';
$$;
revoke all on function public.tir_park_manager_pending() from public, anon;
grant execute on function public.tir_park_manager_pending() to authenticated;

-- Final check.
do $$
begin
  if to_regprocedure('public.tir_park_manager_pending()') is null then
    raise exception '0085: final check failed — nothing changed';
  end if;
end $$;

commit;
