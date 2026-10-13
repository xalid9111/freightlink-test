-- LOCAL TEST FIXTURES (disposable test DB only). Runs as postgres.
-- Users are created through auth.users so the real signup trigger
-- (handle_new_auth_user) builds public.users exactly as in production.
insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data) values
 ('00000000-0000-0000-0000-000000000000','a0000000-0000-4000-8000-000000000001','authenticated','authenticated','admin@t.test',   '{"full_name":"Admin","role":"cargo_owner"}'),
 ('00000000-0000-0000-0000-000000000000','a0000000-0000-4000-8000-000000000011','authenticated','authenticated','owner1@t.test',  '{"full_name":"Owner approved","role":"carrier"}'),
 ('00000000-0000-0000-0000-000000000000','a0000000-0000-4000-8000-000000000012','authenticated','authenticated','owner2@t.test',  '{"full_name":"Owner pending","role":"cargo_owner"}'),
 ('00000000-0000-0000-0000-000000000000','a0000000-0000-4000-8000-000000000013','authenticated','authenticated','owner3@t.test',  '{"full_name":"Owner rejected","role":"driver"}'),
 ('00000000-0000-0000-0000-000000000000','a0000000-0000-4000-8000-000000000014','authenticated','authenticated','owner4@t.test',  '{"full_name":"Owner suspended","role":"cargo_owner"}'),
 ('00000000-0000-0000-0000-000000000000','a0000000-0000-4000-8000-000000000021','authenticated','authenticated','other@t.test',   '{"full_name":"Unrelated user","role":"cargo_owner"}'),
 ('00000000-0000-0000-0000-000000000000','a0000000-0000-4000-8000-000000000031','authenticated','authenticated','blocked@t.test', '{"full_name":"Blocked owner","role":"carrier"}');

update public.users set role = 'admin' where id = 'a0000000-0000-4000-8000-000000000001';
update public.users set is_blocked = true, block_reason = 'internal: suspected fraud'
 where id = 'a0000000-0000-4000-8000-000000000031';

-- Providers inserted as postgres (trusted) so moderation fields stick.
insert into public.service_providers (id, owner_id, name, lat, lng, status, is_verified, added_by_admin, admin_note, categories) values
 ('5e000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000011','Approved Garage',  40.40, 49.86, 'approved',  true,  false, 'NOTE-APPROVED: phone checked', '{engine}'),
 ('5e000000-0000-4000-8000-000000000002','a0000000-0000-4000-8000-000000000012','Pending Garage',   40.41, 49.87, 'pending',   false, false, 'NOTE-PENDING: waiting docs',   '{tyres}'),
 ('5e000000-0000-4000-8000-000000000003','a0000000-0000-4000-8000-000000000013','Rejected Garage',  40.42, 49.88, 'rejected',  false, false, 'NOTE-REJECTED: fake address',  '{tow}'),
 ('5e000000-0000-4000-8000-000000000004','a0000000-0000-4000-8000-000000000014','Suspended Garage', 40.43, 49.89, 'suspended', true,  false, 'NOTE-SUSPENDED: complaints',   '{engine}'),
 ('5e000000-0000-4000-8000-000000000005', null,                                 'Admin Added Tow',  40.44, 49.90, 'approved',  false, true,  'NOTE-ADMIN: from directory',   '{tow}'),
 ('5e000000-0000-4000-8000-000000000006','a0000000-0000-4000-8000-000000000031','Blocked Owner Garage', 40.45, 49.91, 'approved', true, false, 'NOTE-BLOCKED', '{engine}');

insert into public.service_reviews (provider_id, user_id, rating, comment) values
 ('5e000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000021', 4, 'ok');

insert into public.reports (reporter_id, target_type, target_id, reason) values
 ('a0000000-0000-4000-8000-000000000021','cargo',    'x','r'),
 ('a0000000-0000-4000-8000-000000000021','user',     'x','r'),
 ('a0000000-0000-4000-8000-000000000021','message',  'x','r'),
 ('a0000000-0000-4000-8000-000000000021','offer',    'x','r'),
 ('a0000000-0000-4000-8000-000000000021','shipment', 'x','r'),
 ('a0000000-0000-4000-8000-000000000021','service',  '5e000000-0000-4000-8000-000000000001','r'),
 ('a0000000-0000-4000-8000-000000000021','other',    'x','r');
