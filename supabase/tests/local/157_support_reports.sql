-- 0120: Təklif və iradlar + payment / VIP problems for the admins. Rolled back.
\set admin   '''a0000000-0000-4000-8000-000000000001'''
\set u1      '''a0000000-0000-4000-8000-000000000021'''
\set u2      '''a0000000-0000-4000-8000-000000000011'''

begin;
reset role;
-- A live VIP payment of u1 for each problem: failed, stuck, paid-but-not-applied, and a good one.
set local app.market_trusted = '1';
insert into public.market_listings (id, owner_id, category, brand, model, price, currency, status)
values ('e0000000-0000-4000-8000-0000000002a1', :u1, 'truck', 'DAF', 'XF', 100, 'AZN', 'active');
set local app.market_trusted = '';
insert into public.market_vip_orders (id, listing_id, user_id, days, amount, currency, status) values
 ('90000000-0000-4000-8000-0000000002a1', 'e0000000-0000-4000-8000-0000000002a1', :u1, 1, 5, 'AZN', 'cancelled'),
 ('90000000-0000-4000-8000-0000000002a2', 'e0000000-0000-4000-8000-0000000002a1', :u1, 1, 5, 'AZN', 'pending_payment'),
 ('90000000-0000-4000-8000-0000000002a3', 'e0000000-0000-4000-8000-0000000002a1', :u1, 1, 5, 'AZN', 'pending_payment'),
 ('90000000-0000-4000-8000-0000000002a4', 'e0000000-0000-4000-8000-0000000002a1', :u1, 1, 5, 'AZN', 'paid');
insert into public.ad_payments (id, market_vip_order_id, user_id, amount, currency, method, provider, mode, idempotency_key, status, created_at, confirmed_at) values
 ('91000000-0000-4000-8000-0000000002a1', '90000000-0000-4000-8000-0000000002a1', :u1, 5, 'AZN', 'card', 'test', 'live', 'sup120-fail-01', 'failed', now() - interval '1 day', null),
 ('91000000-0000-4000-8000-0000000002a2', '90000000-0000-4000-8000-0000000002a2', :u1, 5, 'AZN', 'card', 'test', 'live', 'sup120-stuck-01', 'pending', now() - interval '2 hours', null),
 ('91000000-0000-4000-8000-0000000002a3', '90000000-0000-4000-8000-0000000002a3', :u1, 5, 'AZN', 'card', 'test', 'live', 'sup120-noapp-01', 'succeeded', now() - interval '3 hours', now() - interval '3 hours'),
 ('91000000-0000-4000-8000-0000000002a4', '90000000-0000-4000-8000-0000000002a4', :u1, 5, 'AZN', 'card', 'test', 'live', 'sup120-good-01', 'succeeded', now() - interval '3 hours', now() - interval '3 hours');

-- 1) A user sends a suggestion and a payment problem.
set role authenticated;
select tests.login(:u1);
create temp table t on commit drop as select public.support_report_submit('feedback', 'Xəritədə filtr olsun') id;
grant select on t to authenticated, anon;
select tests.check((select count(*) = 1 from public.support_reports where id = (select id from t)), 'U1 a suggestion is saved');
select public.support_report_submit('payment', 'Pul getdi, VIP olmadı', '91000000-0000-4000-8000-0000000002a3');
select tests.check(tests.err($$ select public.support_report_submit('feedback', ' a ') $$) like '%invalid_message%', 'U2 an empty text is refused');
select tests.check(tests.err($$ select public.support_report_submit('auto_payment', 'xxx yyy') $$) like '%invalid_kind%', 'U3 only feedback / payment / promo');
select tests.check(tests.err($$ select public.support_report_submit('feedback', 'xxxx', 'zz') $$) is not null, 'U4 bad arguments refused');
select tests.check(tests.err($$ select public.admin_support_list() $$) is not null, 'U5 a user cannot read the admins'' list');
select tests.check(public.admin_support_open_count() = 0, 'U6 a user''s count is 0');
reset role;

-- Another user: cannot point at someone else's payment, sees nothing of u1.
set role authenticated;
select tests.login(:u2);
select tests.check(tests.err($$ select public.support_report_submit('payment', 'başqasının ödənişi', '91000000-0000-4000-8000-0000000002a1') $$) like '%not_allowed%',
  'O1 not someone else''s payment');
select tests.check((select count(*) = 0 from public.support_reports), 'O2 nobody reads another user''s reports');
select tests.check(tests.err($$ insert into public.support_reports (kind, message) values ('feedback', 'direct') $$) is not null, 'O3 no direct writes');
reset role;
set role anon;
select tests.check(tests.err($$ select public.support_report_submit('feedback', 'qonaq yazır') $$) is not null, 'O4 visitors cannot');
reset role;

-- 2) The admin: the users' reports + the server's own finds, once each.
set role authenticated;
select tests.login(:admin);
select tests.check(public.admin_support_open_count() >= 5, 'A1 the count: 2 reports + 3 found problems');
create temp table l on commit drop as select jsonb_array_elements(public.admin_support_list()) j;
grant select on l to authenticated;
select tests.check(exists (select 1 from l where j->>'problem' = 'failed' and j->>'payment_id' = '91000000-0000-4000-8000-0000000002a1'), 'A2 a failed live payment');
select tests.check(exists (select 1 from l where j->>'problem' = 'stuck' and j->>'payment_id' = '91000000-0000-4000-8000-0000000002a2'), 'A3 a payment stuck unpaid');
select tests.check(exists (select 1 from l where j->>'problem' = 'not_applied' and j->>'order_kind' = 'market_vip'), 'A4 paid but VIP not applied');
select tests.check(not exists (select 1 from l where j->>'payment_id' = '91000000-0000-4000-8000-0000000002a4' and j->>'kind' = 'auto_payment'), 'A5 a good payment is no problem');
select tests.check(exists (select 1 from l where j->>'kind' = 'feedback' and j->>'user_name' is not null), 'A6 with the user''s name');
select tests.check((select count(*) from public.admin_support_open_count() c) = 1
               and (select count(*) = 3 from public.support_reports where kind = 'auto_payment'), 'A7 found once (no duplicates on re-read)');
select public.admin_support_set_status((select id from t), 'resolved', 'Nəzərə alındı');
select tests.check((select status = 'resolved' and admin_note = 'Nəzərə alındı' and handled_by = :admin from public.support_reports where id = (select id from t)),
  'A8 resolved with a note');
select tests.check(exists (select 1 from public.admin_audit_log where action = 'support.status' and entity_id = (select id::text from t)), 'A9 logged');
select tests.check(tests.err($$ select public.admin_support_set_status(gen_random_uuid(), 'bad') $$) like '%invalid_status%', 'A10 only new / seen / resolved');
reset role;
select tests.check(tests.err($$ set role authenticated; select public._support_sync_payment_problems() $$) is not null, 'A11 the finder is server-only');
reset role;
rollback;
