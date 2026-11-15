-- 0124: site logos — everybody reads, only the Baş admin changes. Rolled back.
\set admin   '''a0000000-0000-4000-8000-000000000001'''
\set other   '''a0000000-0000-4000-8000-000000000021'''
\set chief   '''a0000000-0000-4000-8000-0000000000f1'''

begin;
reset role;
insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data)
select '00000000-0000-0000-0000-000000000000', :chief, 'authenticated', 'authenticated', 'Xelilov.1881@gmail.com', '{"full_name":"Founder"}'
where not exists (select 1 from auth.users where id = :chief);
update public.users set role = 'admin' where id in (:admin, :chief);
select public.founder_sync();

-- 1) The Baş admin sets a logo; every change is logged.
set role authenticated;
select tests.login(:chief);
select public.admin_site_logo_set('home_logo', 'https://x.supabase.co/storage/v1/object/public/market-photos/a/logo.png');
select public.admin_site_logo_set('app_icon', 'https://x.supabase.co/storage/v1/object/public/market-photos/a/icon.png');
select tests.check((select url like '%/a/logo.png' from public.site_logos where slot = 'home_logo'), 'L1 Baş admin sets the home logo');
select tests.check(tests.err($$ select public.admin_site_logo_set('header', 'https://x/a.png') $$) like '%invalid_slot%', 'L2 only the three places');
select tests.check(tests.err($$ select public.admin_site_logo_set('splash', 'http://x/a.png') $$) like '%invalid_url%', 'L3 only https pictures');
select public.admin_site_logo_set('home_logo', null);
select tests.check((select url is null from public.site_logos where slot = 'home_logo'), 'L4 back to the built-in logo');
reset role;
select tests.check((select count(*) >= 3 from public.admin_audit_log where action = 'site_logo.set'), 'L5 every change in the Audit Log');

-- 2) A plain admin and a user cannot; nobody writes directly.
set role authenticated;
select tests.login(:admin);
select tests.check(tests.err($$ select public.admin_site_logo_set('splash', 'https://x/a.png') $$) like '%chief_admin_only%', 'L6 a plain admin cannot');
select tests.login(:other);
select tests.check(tests.err($$ select public.admin_site_logo_set('splash', 'https://x/a.png') $$) like '%chief_admin_only%', 'L7 a user cannot');
select tests.check(tests.err($$ update public.site_logos set url = 'https://evil/x.png' $$) is not null
                   or (select url like '%/a/icon.png' from public.site_logos where slot = 'app_icon'), 'L8 no direct writes');
select tests.check((select count(*) >= 1 from public.site_logos), 'L9 a signed-in user reads the logos');
reset role;

-- 3) Visitors read them too (the header and the start-up screen).
set role anon;
select tests.login(null);
select tests.check((select url like '%/a/icon.png' from public.site_logos where slot = 'app_icon'), 'L10 a visitor reads the logos');
select tests.check(tests.err($$ select public.admin_site_logo_set('splash', 'https://x/a.png') $$) like '%permission denied%', 'L11 a visitor cannot change them');
reset role;
select tests.summary('SAYT LOQOLARI (0124)');
rollback;
