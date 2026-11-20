-- 0131 Maşınlarım: the driver chosen from the registered users — search
-- (names only, never oneself / a blocked account), the invitation waits for
-- the driver's own yes (bell notice), no = nothing linked. Rolled back.
\set owner   '''a0000000-0000-4000-8000-000000000021'''
\set drv     '''a0000000-0000-4000-8000-000000000011'''
\set other   '''a0000000-0000-4000-8000-000000000012'''
\set blk     '''a0000000-0000-4000-8000-000000000014'''

begin;
create temp table ids (k text primary key, id uuid) on commit drop;
grant all on ids to authenticated;
update public.users set is_blocked = true, blocked_until = null where id = :blk;
set role authenticated;

-- Search: the name, no contact data, never oneself, never a blocked one.
select tests.login(:owner);
select tests.check((select count(*) >= 2 from public.fleet_driver_search('owner')), 'D1 the typed name finds registered accounts');
select tests.check((select bool_and(id <> :blk) from public.fleet_driver_search('owner')), 'D2 a blocked account is not offered');
select tests.check((select count(*) = 0 from public.fleet_driver_search('unrelated')), 'D3 never oneself');
select tests.check((select count(*) = 0 from public.fleet_driver_search('o')), 'D4 at least 2 letters');
select tests.check((select count(*) = 0 from public.fleet_driver_search('%%')), 'D5 % is a letter, not "everything"');
select tests.check(not exists (select 1 from information_schema.parameters
                                where specific_name like 'fleet_driver_search%' and parameter_mode = 'OUT'
                                  and parameter_name in ('email', 'phone')), 'D7 no e-mail, no phone');

-- The invitation.
insert into ids select 't1', public.fleet_truck_save(null, 'Volvo FH 2022', '99-ac-981', null);
select tests.check((public.fleet_driver_invite_user((select id from ids where k = 't1'), :drv) ->> 'status') = 'pending', 'D8 the owner picks the driver');
select tests.check((select pending_driver_id = :drv and driver_id is null and driver_name = 'Owner approved'
                    from public.fleet_trucks where id = (select id from ids where k = 't1')), 'D9 the truck waits, the name is filled in');
select tests.check((public.fleet_driver_invite_user((select id from ids where k = 't1'), :drv) ->> 'status') = 'pending', 'D10 a double tap…');
select tests.check(tests.err(format($$ select public.fleet_driver_invite_user(%L, %L) $$, (select id from ids where k = 't1'), :owner)) like '%invalid_argument%',
  'D11 not himself');
select tests.check(tests.err(format($$ select public.fleet_driver_invite_user(%L, %L) $$, (select id from ids where k = 't1'), :blk)) like '%not_found%',
  'D12 not a blocked account');
reset role;
select tests.check((select count(*) = 1 from public.fleet_driver_invites where invited_user = :drv), 'D10b …invites once');
insert into ids select 'i1', (select id from public.fleet_driver_invites where invited_user = :drv);
select tests.check((select count(*) = 1 and bool_and(type = 'fleet_driver_invite' and title like '%sizi sürücü kimi əlavə edir'
                                                 and data ->> 'invite_id' = (select id::text from ids where k = 'i1'))
                    from public.notifications where user_id = :drv and type = 'fleet_driver_invite'), 'D13 the driver gets the bell notice');
set role authenticated;

-- A stranger cannot answer; a code never opens a personal invitation.
select tests.login(:other);
select tests.check(tests.err(format($$ select public.fleet_driver_answer(%L, true) $$, (select id from ids where k = 'i1'))) like '%not_found%',
  'D14 only the invited account answers');
select tests.check(tests.err(format($$ select public.fleet_driver_invite_user(%L, %L) $$, (select id from ids where k = 't1'), :other)) like '%not_owner%',
  'D16 nobody else invites for the truck');

-- The driver sees it as open, says yes → linked.
select tests.login(:drv);
select tests.check((select array_agg(x) = array[(select id from ids where k = 'i1')] from public.fleet_my_driver_invites() x), 'D17 his open invitation');
select tests.check((select count(*) = 0 from public.fleet_trucks), 'D18 before his yes he sees no truck');
select tests.check((public.fleet_driver_answer((select id from ids where k = 'i1'), true) ->> 'name') = 'Volvo FH 2022', 'D19 he accepts');
select tests.check((select count(*) = 1 from public.fleet_trucks where driver_id = auth.uid() and pending_driver_id is null), 'D20 …and drives the truck');
select tests.check((select count(*) = 0 from public.fleet_my_driver_invites()), 'D21 the invitation is closed');
select tests.check(tests.err(format($$ select public.fleet_driver_answer(%L, false) $$, (select id from ids where k = 'i1'))) like '%invite_closed%', 'D22 answered once');
reset role;
select tests.check(exists (select 1 from public.notifications where user_id = :owner and type = 'fleet_driver_answer' and (data ->> 'accepted')::boolean),
  'D23 the owner is told');
set role authenticated;

-- A second truck: the driver says no → nothing linked; the owner takes one back.
select tests.login(:owner);
insert into ids select 't2', public.fleet_truck_save(null, 'MAN TGX', null, null);
select public.fleet_driver_invite_user((select id from ids where k = 't2'), :other);
select public.fleet_invite_create((select id from ids where k = 't2'));
select tests.check((select pending_driver_id = :other from public.fleet_trucks where id = (select id from ids where k = 't2')), 'D24 a code does not cancel the invitation');
select tests.login(:other);
select public.fleet_driver_answer((select x from public.fleet_my_driver_invites() x limit 1), false);
select tests.check((select count(*) = 0 from public.fleet_trucks), 'D25 a no links nothing');
select tests.login(:owner);
select tests.check((select pending_driver_id is null and driver_id is null from public.fleet_trucks where id = (select id from ids where k = 't2')), 'D26 …and the waiting mark goes');
select public.fleet_driver_invite_user((select id from ids where k = 't2'), :drv);
select public.fleet_driver_invite_cancel((select id from ids where k = 't2'));
reset role;
select tests.check((select pending_driver_id is null from public.fleet_trucks where id = (select id from ids where k = 't2'))
                   and (select count(*) = 0 from public.fleet_driver_invites where truck_id = (select id from ids where k = 't2') and invited_user is not null
                          and used_at is null and cancelled_at is null), 'D27 the owner takes the invitation back (✕)');
set role authenticated;
select tests.login(:owner);
select tests.check(tests.err($$ insert into public.fleet_driver_invites (truck_id, code, created_by) values (gen_random_uuid(), 'X', auth.uid()) $$) is not null,
  'D28 no direct writes');
rollback;
