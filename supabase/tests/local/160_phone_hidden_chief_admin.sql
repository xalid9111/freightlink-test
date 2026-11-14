-- 0123: a hidden number is seen only by its owner and the Baş admin. Rolled back.
\set p       '''f0000000-0000-4000-8000-0000000004b1'''
\set q       '''f0000000-0000-4000-8000-0000000004b2'''
\set other   '''a0000000-0000-4000-8000-000000000021'''
\set admin   '''a0000000-0000-4000-8000-000000000001'''
\set chief   '''a0000000-0000-4000-8000-0000000000f1'''

begin;
reset role;
insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data) values
 ('00000000-0000-0000-0000-000000000000', :p, 'authenticated', 'authenticated', 'hidden-b1@t.test', '{"full_name":"Gizli Bir"}'),
 ('00000000-0000-0000-0000-000000000000', :q, 'authenticated', 'authenticated', 'hidden-b2@t.test', '{"full_name":"Başqası"}');
insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data)
select '00000000-0000-0000-0000-000000000000', :chief, 'authenticated', 'authenticated', 'Xelilov.1881@gmail.com', '{"full_name":"Founder"}'
where not exists (select 1 from auth.users where id = :chief);
update public.users set role = 'admin' where id in (:admin, :chief);
select public.founder_sync();
update public.users set phone = '+994507770011' where id = :p;
insert into public.cargo (id, owner_id, pickup_country, pickup_city, destination_country, destination_city, weight_kg, offered_price, pickup_date)
values ('c0000000-0000-4000-8000-0000000004b1', :p, 'Azerbaijan', 'Baku', 'Georgia', 'Tbilisi', 1000, 100, current_date);
insert into public.cargo_contacts (cargo_id, phone) values ('c0000000-0000-4000-8000-0000000004b1', '+994557770022');
insert into public.job_vacancies (id, owner_id, company_name, phone) values ('b0000000-0000-4000-8000-0000000004b1', :p, 'Gizli MMC', '+994507770011');
insert into public.job_seeker_profiles (user_id, full_name, phone) values (:p, 'Gizli Bir', '+994507770011');

-- 1) He hides: his own number, the load's number and İş Mərkəzi phones move.
set role authenticated;
select tests.login(:p);
select public.my_set_phone_hidden(true);
select tests.check(public.my_phone() = '+994507770011', 'C1 he still reads his own number (Şəxsi məlumatlarım)');
select tests.check((select phone is null from public.users where id = :p), 'C2 the users row holds no number now');
reset role;
select tests.check((select count(*) = 0 from public.cargo_contacts where cargo_id = 'c0000000-0000-4000-8000-0000000004b1'), 'C3 the load''s number left the table');
select tests.check((select phone is null from public.job_vacancies where id = 'b0000000-0000-4000-8000-0000000004b1')
               and (select phone is null from public.job_seeker_profiles where user_id = :p), 'C4 İş Mərkəzi phones hidden');
select tests.check((select phone = '+994507770011' from public.hidden_user_phones where user_id = :p), 'C5 kept safe, not lost');

-- 2) A plain admin sees nothing; the Baş admin sees it (logged).
set role authenticated;
select tests.login(:admin);
select tests.check((select phone is null from public.users where id = :p), 'A1 admin: no number on the users row');
select tests.check((select public.get_user_contact(:p) ->> 'phone') is null, 'A2 admin: no number on the profile');
select tests.check((select public.get_cargo_contact('c0000000-0000-4000-8000-0000000004b1') ->> 'contact_phone') is null, 'A3 admin: no number on the load');
select tests.check(tests.err($$ select public.admin_hidden_phones('f0000000-0000-4000-8000-0000000004b1') $$) like '%chief_admin_only%', 'A4 admin cannot open the store');
select tests.check(tests.err($$ select * from public.hidden_user_phones $$) is not null, 'A5 nobody reads the store directly');
reset role;
set role authenticated;
select tests.login(:chief);
select tests.check((select public.get_user_contact(:p) ->> 'phone') = '+994507770011', 'B1 Baş admin sees the profile number');
select tests.check((select public.get_cargo_contact('c0000000-0000-4000-8000-0000000004b1') ->> 'contact_phone') = '+994557770022', 'B2 Baş admin sees the load number');
select tests.check((select (public.admin_hidden_phones(:p) ->> 'phone') = '+994507770011'), 'B3 Baş admin opens the store');
reset role;
select tests.check((select count(*) >= 1 from public.admin_audit_log where action = 'phone.view_hidden' and entity_id = :p::text), 'B4 the look is logged');

-- 3) Others: nothing; nobody can take his number meanwhile.
set role authenticated;
select tests.login(:other);
select tests.check((select public.get_user_contact(:p) ->> 'phone') is null, 'O1 others: no number');
reset role;
select tests.check(tests.err($$ update public.users set phone = '+994507770011' where id = 'f0000000-0000-4000-8000-0000000004b2' $$) like '%phone_taken%', 'O2 the hidden number cannot be taken');

-- 4) A number he saves while hidden goes to the store; a new load number too.
set role authenticated;
select tests.login(:p);
update public.users set phone = '+994507770099' where id = :p;
select tests.check((select public.my_phone()) = '+994507770099', 'N1 a new number is kept (hidden)');
reset role;
select tests.check((select phone is null from public.users where id = :p), 'N2 still not on the row');
insert into public.cargo_contacts (cargo_id, phone) values ('c0000000-0000-4000-8000-0000000004b1', '+994557770033');
select tests.check((select count(*) = 0 from public.cargo_contacts where cargo_id = 'c0000000-0000-4000-8000-0000000004b1')
               and (select phone = '+994557770033' from public.hidden_ad_phones where kind = 'cargo' and ad_id = 'c0000000-0000-4000-8000-0000000004b1'),
  'N3 a load number saved while hidden goes to the store');

-- 5) He shows it again: every number back.
set role authenticated;
select tests.login(:p);
select public.my_set_phone_hidden(false);
reset role;
select tests.check((select phone = '+994507770099' from public.users where id = :p), 'R1 his number back on the row');
select tests.check((select phone = '+994557770033' from public.cargo_contacts where cargo_id = 'c0000000-0000-4000-8000-0000000004b1'), 'R2 the load number back');
select tests.check((select phone = '+994507770011' from public.job_vacancies where id = 'b0000000-0000-4000-8000-0000000004b1')
               and (select phone = '+994507770011' from public.job_seeker_profiles where user_id = :p), 'R3 İş Mərkəzi phones back');
select tests.check((select count(*) = 0 from public.hidden_user_phones where user_id = :p)
               and (select count(*) = 0 from public.hidden_ad_phones where owner_id = :p), 'R4 the stores are empty');
set role authenticated;
select tests.login(:admin);
select tests.check((select public.get_user_contact(:p) ->> 'phone') = '+994507770099', 'R5 not hidden: admins see it as before');
reset role;
rollback;
