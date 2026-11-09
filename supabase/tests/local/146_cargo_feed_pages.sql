-- Yüklər page by page from the server — 0109. Rolled back.
\set owner '''a0000000-0000-4000-8000-000000000012'''
\set other '''a0000000-0000-4000-8000-000000000021'''

begin;
reset role;
-- Start from a known set: the open loads of earlier tests are put aside
-- (status changed inside this rolled-back transaction only).
update public.cargo set status = 'cancelled' where status = 'new';

-- 12 loads (01 newest): 2 lifted by İrəli çək, 2 VIP, 1 Premium, an
-- expired VIP (plain now), 4 that must never show → 5 plain listed.
insert into public.cargo (id, owner_id, pickup_country, pickup_city, destination_country, destination_city, weight_kg, offered_price,
                          pickup_date, created_at)
select ('c1090000-0000-4000-8000-0000000000' || lpad(i::text, 2, '0'))::uuid, :owner, 'Azerbaijan', 'Baku', 'Georgia', 'Tbilisi',
       1000 + i, 100 + i, current_date + 3, now() - make_interval(hours => i * 10)
  from generate_series(1, 12) i;
-- Promotions are set as the payment service (the only allowed path).
select set_config('request.jwt.claims', '{"role":"service_role"}', true), set_config('request.jwt.claim.sub', '', true);
-- İrəli çək on two old loads: lifted now (they come first among plain loads)
update public.cargo set bump_total = 3, bump_start = now() - interval '1 minute'
 where id in ('c1090000-0000-4000-8000-000000000011', 'c1090000-0000-4000-8000-000000000012');
-- VIP and Premium
update public.cargo set is_featured = true, featured_until = now() + interval '3 days', featured_since = now() - interval '2 hours'
 where id in ('c1090000-0000-4000-8000-000000000003', 'c1090000-0000-4000-8000-000000000007');
update public.cargo set premium_until = now() + interval '2 days', premium_since = now() - interval '1 hour'
 where id = 'c1090000-0000-4000-8000-000000000005';
-- a VIP that ran out: a plain load again
update public.cargo set is_featured = true, featured_until = now() - interval '1 day' where id = 'c1090000-0000-4000-8000-000000000009';
select set_config('request.jwt.claims', '', true);
-- never listed: hidden, switched off, loading day over, not open
update public.cargo set is_hidden = true  where id = 'c1090000-0000-4000-8000-000000000002';
update public.cargo set is_paused = true  where id = 'c1090000-0000-4000-8000-000000000004';
update public.cargo set pickup_date = current_date - 2 where id = 'c1090000-0000-4000-8000-000000000006';
update public.cargo set status = 'agreed' where id = 'c1090000-0000-4000-8000-000000000008';

-- Expected order of the plain loads (the app's order): lift, then newest.
create temp table want as
  select c.id, row_number() over (order by public.cargo_lifted_at(c) desc, c.created_at desc, c.id desc) as n
    from public.cargo c
   where c.id::text like 'c1090000-%' and c.status = 'new' and not c.is_hidden and not c.is_paused and c.pickup_date >= current_date
     and not public.cargo_vip_active(c.is_featured, c.featured_until) and not public.cargo_premium_active(c.premium_until);
grant select on want to anon, authenticated;

create or replace function pg_temp.pages(p_size integer) returns table (id uuid, n bigint) language plpgsql as $$
declare last_id uuid; got integer; k bigint := 0; r record;
begin
  loop
    got := 0;
    for r in select f.id from public.cargo_feed_page(p_size, last_id) f loop
      k := k + 1; got := got + 1; id := r.id; n := k; last_id := r.id; return next;
    end loop;
    exit when got < p_size;
  end loop;
end $$;
grant execute on all functions in schema pg_temp to anon, authenticated;

-- ---- a visitor (0107) -------------------------------------------------------
set role anon;
select tests.login(null);
select tests.check((select count(*) = 5 from want), 'F0 fixture: 5 plain listed loads');
select tests.check((select string_agg(right(id::text, 2), ',' order by created_at desc) from public.cargo_feed_promoted()) = '03,05,07',
  'F1 promoted = the running VIPs and the Premium, newest first');
select tests.check((select public.cargo_feed_count()) = 8, 'F2 the counter = every listed load (5 plain + 3 promoted)');
select tests.check((select count(*) = 5 and bool_and(p.n = w.n) from pg_temp.pages(2) p join want w using (id)),
  'F3 pages of 2 give every plain load once, in the app''s order (lift, newest)');
select tests.check((select count(*) from pg_temp.pages(3)) = (select count(distinct id) from pg_temp.pages(3)), 'F4 no load twice');
select tests.check((select string_agg(right(id::text, 2), ',' order by n) from pg_temp.pages(2) where n <= 2) = '11,12',
  'F5 İrəli çək lifts old loads to the top');
select tests.check(not exists (select 1 from pg_temp.pages(5) where right(id::text, 2) in ('02', '04', '06', '08')),
  'F6 hidden / switched off / day over / not open never come');
select tests.check(exists (select 1 from pg_temp.pages(5) where right(id::text, 2) = '09'), 'F7 a VIP that ran out is a plain load again');
select tests.check((select count(*) from public.cargo_feed_page(500)) = 5, 'F8 a page is never larger than asked (max 100)');
select tests.check((select count(*) from public.cargo_feed_page(0)) = 1, 'F9 at least one per page');
-- the next page also works when the last load is gone (the app's own values)
select tests.check((select count(*) from public.cargo_feed_page(20, 'c1090000-0000-4000-8000-0000000000ff', now() + interval '1 day', now())) = 5,
  'F10 a missing last load falls back to the given times');
select tests.check(tests.err($$ update public.cargo set offered_price = 1 $$) is not null
                   or not exists (select 1 from public.cargo where offered_price = 1), 'F11 visitors still cannot change loads');
reset role;

-- ---- a signed-in stranger and the owner --------------------------------------
set role authenticated;
select tests.login(:other);
select tests.check((select count(*) = 5 and bool_and(p.n = w.n) from pg_temp.pages(3) p join want w using (id)),
  'F12 the same pages for a signed-in user');
select tests.check((select public.cargo_feed_count()) = 8, 'F13 the same counter');
select tests.login(:owner);
select tests.check(not exists (select 1 from pg_temp.pages(20) where right(id::text, 2) = '02'),
  'F14 the owner''s own hidden load stays off the feed (as in the app)');
reset role;

select tests.check((select prosecdef = false from pg_proc where proname = 'cargo_feed_page'), 'F15 runs with the caller''s rights (RLS applies)');
select tests.check(has_function_privilege('anon', 'public.cargo_feed_page(integer, uuid, timestamptz, timestamptz)', 'execute'),
  'F16 visitors may call it');
select tests.summary('YÜKLƏR SƏHİFƏ-SƏHİFƏ (0109)');
rollback;
