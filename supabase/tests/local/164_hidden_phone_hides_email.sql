-- 0127: "Telefon nömrəmi gizlət" hides the e-mail too; owner + Baş admin
-- still see it; turned off = shown again. Rolled back.
\set p       '''f0000000-0000-4000-8000-0000000004c1'''
\set other   '''a0000000-0000-4000-8000-000000000021'''
\set admin   '''a0000000-0000-4000-8000-000000000001'''
\set chief   '''a0000000-0000-4000-8000-0000000000f1'''

begin;
reset role;
insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data) values
 ('00000000-0000-0000-0000-000000000000', :p, 'authenticated', 'authenticated', 'hidden-c1@t.test', '{"full_name":"Gizli Poçt"}');
insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data)
select '00000000-0000-0000-0000-000000000000', :chief, 'authenticated', 'authenticated', 'Xelilov.1881@gmail.com', '{"full_name":"Founder"}'
where not exists (select 1 from auth.users where id = :chief);
update public.users set role = 'admin' where id in (:admin, :chief);
select public.founder_sync();
update public.users set phone = '+994507770031' where id = :p;
insert into public.cargo (id, owner_id, pickup_country, pickup_city, destination_country, destination_city, weight_kg, offered_price, pickup_date)
values ('c0000000-0000-4000-8000-0000000004c1', :p, 'Azerbaijan', 'Baku', 'Georgia', 'Tbilisi', 1000, 100, current_date);

set role authenticated;
select tests.login(:other);
select tests.check(public.get_cargo_contact('c0000000-0000-4000-8000-0000000004c1') ->> 'email' = 'hidden-c1@t.test',
  'E1 not hidden: the load page shows the e-mail as before');

select tests.login(:p);
select public.my_set_phone_hidden(true);

select tests.login(:other);
select tests.check(public.get_cargo_contact('c0000000-0000-4000-8000-0000000004c1') ->> 'email' is null,
  'E2 hidden: no e-mail on the load page');
select tests.check(public.get_user_contact(:p) ->> 'email' is null, 'E3 …nor on the profile');
select tests.login(:admin);
select tests.check(public.get_cargo_contact('c0000000-0000-4000-8000-0000000004c1') ->> 'email' is null
               and public.get_user_contact(:p) ->> 'email' is null, 'E4 a plain admin sees no e-mail either');
select tests.login(:chief);
select tests.check(public.get_cargo_contact('c0000000-0000-4000-8000-0000000004c1') ->> 'email' = 'hidden-c1@t.test'
               and public.get_user_contact(:p) ->> 'email' = 'hidden-c1@t.test', 'E5 the Baş admin sees it');
select tests.login(:p);
select tests.check(public.get_cargo_contact('c0000000-0000-4000-8000-0000000004c1') ->> 'email' = 'hidden-c1@t.test'
               and public.get_user_contact(:p) ->> 'email' = 'hidden-c1@t.test', 'E6 the owner sees his own');

select public.my_set_phone_hidden(false);
select tests.login(:other);
select tests.check(public.get_cargo_contact('c0000000-0000-4000-8000-0000000004c1') ->> 'email' = 'hidden-c1@t.test',
  'E7 turned off: shown again');
reset role;
select tests.check((select email = 'hidden-c1@t.test' from public.users where id = :p), 'E8 the sign-in address never changed');

select tests.summary('GİZLİ NÖMRƏ + E-POÇT (0127)');
rollback;
