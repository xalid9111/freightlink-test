-- TIR BAZARI — 0041: published at once; waiting ads published once by the
-- migration, ads the admin moderated stay with the admin. Rolled back.
-- Run with: psql -v mig41=<path to 0041_market_autopublish.sql>
\set seller '''a0000000-0000-4000-8000-000000000012'''
\set w1 '''aa410000-0000-4000-8000-000000000001'''
\set w2 '''aa410000-0000-4000-8000-000000000002'''

begin;
-- As the database (SQL editor): one waiting ad, one sent back after the admin deactivated it.
insert into public.market_listings (id, owner_id, category, brand, status) values (:w1, :seller, 'truck', 'DAF', 'pending');
insert into public.market_listings (id, owner_id, category, brand, status, admin_note) values (:w2, :seller, 'truck', 'MAN', 'pending', 'duplicate');
\i :mig41
select tests.check((select status = 'active' and published_at is not null from public.market_listings where id = :w1),
  'P1 a waiting ad is published by the migration');
select tests.check((select status = 'pending' and admin_note = 'duplicate' from public.market_listings where id = :w2),
  'P2 an ad the admin moderated stays with the admin');
\i :mig41
select tests.check((select count(*) = 2 from public.market_listings where id in (:w1, :w2)), 'P3 re-run fine, nothing deleted');

set role authenticated;
select tests.login(:seller);
insert into public.market_listings (category, brand, status, is_vip) values ('trailer', 'Krone', 'pending', true);
select tests.check((select status = 'active' and published_at is not null and not is_vip from public.market_listings where brand = 'Krone'),
  'P4 "Elanı dərc et" on a new ad → visible at once, still no self-VIP');
reset role;

select tests.summary('TIR BAZARI AUTOPUBLISH (0041)');
rollback;
