-- 0128: "Bildirişlər" — a new offer → the load owner, accepted / rejected →
-- the carrier, a new booking → the park manager; once each; own rows only.
-- Rolled back.
\set owner   '''a0000000-0000-4000-8000-000000000021'''
\set drv     '''a0000000-0000-4000-8000-000000000011'''
\set cargo   '''c0000000-0000-4000-8000-0000000004d1'''
\set park    '''7a000000-0000-4000-8000-0000000004d1'''

begin;
reset role;
insert into public.cargo (id, owner_id, pickup_country, pickup_city, destination_country, destination_city, weight_kg, offered_price, pickup_date)
values (:cargo, :owner, 'Azerbaijan', 'Bakı', 'Russia', 'Sankt-Peterburq', 22000, 5100, current_date);
insert into public.carriers (user_id) select :drv where not exists (select 1 from public.carriers where user_id = :drv);
insert into public.tir_parks (id, name, lat, lng, status, manager_id, manager_status)
values (:park, 'Notice Park', 40.4, 49.9, 'approved', :owner, 'approved');

set role authenticated;
select tests.login(:drv);
insert into public.offers (id, cargo_id, carrier_id, offered_price, currency)
values ('0f000000-0000-4000-8000-0000000004d1', :cargo, public.current_carrier_id(), 6000, 'USD');
reset role;
select tests.check((select count(*) = 1 and bool_and(title = 'Yükünüzə yeni təklif: 6000 USD' and body = 'Bakı → Sankt-Peterburq'
                           and data ->> 'cargo_id' = 'c0000000-0000-4000-8000-0000000004d1')
                    from public.notifications where user_id = :owner and type = 'cargo_offer_new'), 'N1 a new offer → the load owner');
select tests.check(not exists (select 1 from public.notifications where user_id = :drv and type like 'cargo_offer%'),
  'N2 the carrier gets no notice of his own offer');

update public.offers set status = 'rejected' where id = '0f000000-0000-4000-8000-0000000004d1';
update public.offers set status = 'rejected' where id = '0f000000-0000-4000-8000-0000000004d1';
select tests.check((select count(*) = 1 and bool_and(title = 'Təklifiniz rədd edildi: 6000 USD')
                    from public.notifications where user_id = :drv and type = 'cargo_offer_rejected'), 'N3 rejected → the carrier, once');

set role authenticated;
select tests.login(:drv);
insert into public.offers (id, cargo_id, carrier_id, offered_price, currency, created_at)
values ('0f000000-0000-4000-8000-0000000004d2', :cargo, public.current_carrier_id(), 5500.50, 'USD', now() + interval '1 second');
reset role;
update public.offers set status = 'accepted' where id = '0f000000-0000-4000-8000-0000000004d2';
select tests.check((select count(*) = 1 and bool_and(title = 'Təklifiniz qəbul edildi: 5500.5 USD')
                    from public.notifications where user_id = :drv and type = 'cargo_offer_accepted'), 'N4 accepted → the carrier');

-- A booking → the park's approved manager (not to the driver himself).
insert into public.tir_park_bookings (id, booking_no, park_id, user_id, trucks, start_at, end_at, units, unit, price, amount)
values ('7b000000-0000-4000-8000-0000000004d1', 'NTC-0001', :park, :drv, 1,
        now() + interval '1 day', now() + interval '2 days', 1, 'day', 3, 3);
select tests.check((select count(*) = 1 and bool_and(title = 'Yeni rezervasiya: NTC-0001' and body = 'Notice Park')
                    from public.notifications where user_id = :owner and type = 'tirpark_booking'), 'N5 a booking → the manager');
select tests.check(not exists (select 1 from public.notifications where user_id = :drv and type = 'tirpark_booking'), 'N6 not to the driver');

-- Only one's own notices are seen and marked read.
set role authenticated;
select tests.login(:drv);
select tests.check((select count(*) = 0 from public.notifications where user_id = :owner), 'N7 nobody reads another person''s notices');
update public.notifications set is_read = true where user_id = :owner;
select tests.login(:owner);
select tests.check((select count(*) >= 2 from public.notifications where not is_read), 'N8 … nor marks them read');
update public.notifications set is_read = true where not is_read;
select tests.check(not exists (select 1 from public.notifications where not is_read), 'N9 the owner marks his own read');
select tests.check(tests.err($$ select public._notice_on_offer() $$) is not null, 'N10 the trigger function is not callable');
reset role;

select tests.summary('BİLDİRİŞLƏR (0128)');
rollback;
