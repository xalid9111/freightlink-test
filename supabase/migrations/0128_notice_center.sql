-- 0128: "Bildirişlər" — one bell on every page (owner, 17.11.2026: "mesajdan
-- başqa gələn bütün bildirişlər ora gəlsin, neçə bildiriş varsa kənarına
-- yazılsın").
--
-- The bell reads the EXISTING notifications table (0001; job notices 0069,
-- park receipts 0085, worker requests 0088). This file only adds the events
-- that had no notice yet:
--   * a new offer on a load          → the load's owner   (cargo_offer_new)
--   * an offer accepted / rejected   → the carrier        (cargo_offer_accepted /
--                                                           cargo_offer_rejected)
--   * a new park booking             → the park's approved manager (tirpark_booking)
--
-- Safe: forward-only, re-runnable (create or replace, drop trigger if
-- exists); no table / column changes, nothing deleted or rewritten; each
-- notice once (data.dedupe, the unique index of 0069); a notice NEVER stops
-- the offer or the booking (any error is swallowed). Users still read and
-- mark only their own notices (RLS of 0002).

create or replace function public._notice_on_offer()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_owner uuid;
  v_carrier uuid;
  v_from text;
  v_to text;
  v_amount text;
  v_type text;
  v_title text;
  v_to_user uuid;
begin
  select owner_id, pickup_city, destination_city into v_owner, v_from, v_to
    from cargo where id = new.cargo_id;
  select user_id into v_carrier from carriers where id = new.carrier_id;
  if v_owner is null or v_carrier is null or v_owner = v_carrier then
    return new;
  end if;
  v_amount := rtrim(rtrim(to_char(new.offered_price, 'FM999999990.00'), '0'), '.') || ' ' || coalesce(new.currency, '');

  if tg_op = 'INSERT' then
    if new.status <> 'pending' then return new; end if;
    v_type := 'cargo_offer_new';
    v_title := 'Yükünüzə yeni təklif: ' || v_amount;
    v_to_user := v_owner;
  elsif new.status is distinct from old.status and new.status in ('accepted', 'rejected') then
    v_type := 'cargo_offer_' || new.status;
    v_title := case new.status when 'accepted' then 'Təklifiniz qəbul edildi: ' else 'Təklifiniz rədd edildi: ' end || v_amount;
    v_to_user := v_carrier;
  else
    return new;
  end if;

  insert into notifications (user_id, type, title, body, data)
  values (v_to_user, v_type, v_title, coalesce(v_from, '') || ' → ' || coalesce(v_to, ''),
          jsonb_build_object('cargo_id', new.cargo_id, 'offer_id', new.id,
                             'amount', new.offered_price, 'currency', new.currency,
                             'from', v_from, 'to', v_to,
                             'dedupe', 'cof:' || new.id || ':' || v_type))
  on conflict ((data ->> 'dedupe')) where data ? 'dedupe' do nothing;
  return new;
exception when others then
  raise notice 'notice (offer) skipped: %', sqlerrm;
  return new;
end;
$$;

drop trigger if exists zz_notice_offer on public.offers;
create trigger zz_notice_offer after insert or update of status on public.offers
  for each row execute function public._notice_on_offer();

create or replace function public._notice_on_booking()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_manager uuid;
  v_park text;
begin
  select manager_id, name into v_manager, v_park from tir_parks
   where id = new.park_id and manager_status = 'approved';
  if v_manager is null or v_manager = new.user_id then return new; end if;
  insert into notifications (user_id, type, title, body, data)
  values (v_manager, 'tirpark_booking',
          'Yeni rezervasiya: ' || coalesce(new.plate, new.booking_no),
          v_park,
          jsonb_build_object('booking_id', new.id, 'park_id', new.park_id,
                             'plate', new.plate, 'booking_no', new.booking_no,
                             'dedupe', 'tpb:' || new.id))
  on conflict ((data ->> 'dedupe')) where data ? 'dedupe' do nothing;
  return new;
exception when others then
  raise notice 'notice (booking) skipped: %', sqlerrm;
  return new;
end;
$$;

drop trigger if exists zz_notice_booking on public.tir_park_bookings;
create trigger zz_notice_booking after insert on public.tir_park_bookings
  for each row execute function public._notice_on_booking();

-- The trigger functions are not for direct calls.
revoke all on function public._notice_on_offer() from public, anon, authenticated;
revoke all on function public._notice_on_booking() from public, anon, authenticated;
