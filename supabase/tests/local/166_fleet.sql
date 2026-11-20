-- 0130 "Maşınlarım": trucks, jobs, expenses, the driver's code; own rows
-- only; the driver's expense waits for the owner; nothing really deleted.
-- Rolled back.
\set owner   '''a0000000-0000-4000-8000-000000000021'''
\set drv     '''a0000000-0000-4000-8000-000000000011'''
\set other   '''a0000000-0000-4000-8000-000000000012'''

begin;
create temp table ids (k text primary key, id uuid) on commit drop;
create temp table codes (k text primary key, code text) on commit drop;
grant all on ids, codes to authenticated;
set role authenticated;

-- A truck.
select tests.login(:owner);
insert into ids select 't1', public.fleet_truck_save(null, 'Volvo FH 2022', '99-ac-981', 'Rəşad Məmmədov');
select tests.check((select name = 'Volvo FH 2022' and plate = '99-AC-981' and driver_name = 'Rəşad Məmmədov'
                    from public.fleet_trucks where id = (select id from ids where k = 't1')), 'F1 a truck: name, plate (upper case), driver');
select tests.check(tests.err($$ select public.fleet_truck_save(null, '   ', null, null) $$) like '%name_required%', 'F2 a name is required');

-- A job (already started = active) and the owner's own expense.
insert into ids select 'j1', public.fleet_job_save(null, (select id from ids where k = 't1'), now() - interval '1 hour', 'Bakı', 'Gəncə', 4500, 'usd', null);
select tests.check((select status = 'active' and price = 4500 and currency = 'USD' from public.fleet_jobs where id = (select id from ids where k = 'j1')),
  'F3 a job: started = active, currency checked');
select tests.check(tests.err(format($$ select public.fleet_job_save(null, %L, now(), 'A', 'B', 10, 'GBP', null) $$, (select id from ids where k = 't1'))) like '%invalid_currency%',
  'F4 only AZN · USD · EUR · RUB · TRY');
select tests.check((public.fleet_expense_add((select id from ids where k = 't1'), 'Ay-24', 30, 'USD', 'k-1') ->> 'status') = 'approved',
  'F5 the owner''s own expense counts at once');
select tests.check((public.fleet_expense_add((select id from ids where k = 't1'), 'Ay-24', 30, 'USD', 'k-1') ->> 'status') = 'approved'
                   and (select count(*) = 1 from public.fleet_expenses where client_key = 'k-1'), 'F6 a double tap adds once');

-- A stranger sees and changes nothing.
select tests.login(:other);
select tests.check((select count(*) = 0 from public.fleet_trucks), 'F7 a stranger sees no truck');
select tests.check((select count(*) = 0 from public.fleet_jobs) and (select count(*) = 0 from public.fleet_expenses), 'F8 …no job, no expense');
select tests.check(tests.err(format($$ select public.fleet_truck_save(%L, 'Hack', null, null) $$, (select id from ids where k = 't1'))) like '%not_owner%',
  'F9 …and cannot change the truck');
select tests.check(tests.err(format($$ select public.fleet_expense_add(%L, 'X', 5, 'AZN', null) $$, (select id from ids where k = 't1'))) like '%not_allowed%',
  'F10 …nor add an expense');
select tests.check(tests.err($$ insert into public.fleet_trucks (owner_id, name) values (auth.uid(), 'Direct') $$) is not null, 'F11 no direct writes');

-- The driver joins with the code.
select tests.login(:owner);
insert into codes select 'c', public.fleet_invite_create((select id from ids where k = 't1')) ->> 'code';
select tests.check(tests.err(format($$ select public.fleet_driver_join(%L) $$, (select code from codes))) like '%own_truck%', 'F12 the owner is not his own driver');
select tests.login(:drv);
select tests.check((public.fleet_driver_join((select code from codes)) ->> 'name') = 'Volvo FH 2022', 'F13 the driver joins with the code');
select tests.check(tests.err(format($$ select public.fleet_driver_join(%L) $$, (select code from codes))) like '%invalid_code%', 'F14 a code works once');
select tests.check((select count(*) = 1 from public.fleet_trucks where driver_id = auth.uid()), 'F15 the driver sees his truck');
select tests.check((select count(*) = 0 from public.fleet_jobs), 'F16 …but not the jobs table (prices)');
select tests.check(jsonb_array_length(public.fleet_driver_jobs()) = 1 and not (public.fleet_driver_jobs() -> 0 ? 'price'),
  'F17 his jobs come without the price');
select tests.check((select count(*) = 0 from public.fleet_expenses), 'F18 he does not see the owner''s expenses');

-- The driver's expense waits; the owner is told.
insert into ids select 'e1', (public.fleet_expense_add((select id from ids where k = 't1'), 'Ay-25', 450, 'AZN', 'd-1') ->> 'id')::uuid;
select tests.check((select status = 'pending' from public.fleet_expenses where id = (select id from ids where k = 'e1')), 'F19 the driver''s expense waits');
select tests.check(tests.err(format($$ select public.fleet_expense_decide(%L, true) $$, (select id from ids where k = 'e1'))) like '%not_owner%',
  'F20 the driver cannot approve it');
reset role;
select tests.check((select count(*) = 1 and bool_and(title = 'Rasxod təsdiq gözləyir: Ay-25' and data ->> 'truck_id' = (select id::text from ids where k = 't1'))
                    from public.notifications where user_id = :owner and type = 'fleet_expense'), 'F21 the owner gets a notice');
set role authenticated;

-- The owner approves.
select tests.login(:owner);
select public.fleet_expense_decide((select id from ids where k = 'e1'), true);
select tests.check((select status = 'approved' and decided_by = auth.uid() from public.fleet_expenses where id = (select id from ids where k = 'e1')),
  'F22 the owner approves');
select tests.check(tests.err(format($$ select public.fleet_expense_decide(%L, false) $$, (select id from ids where k = 'e1'))) like '%already_decided%',
  'F23 decided once');
-- Edit, then "Sil": kept, only marked.
select public.fleet_expense_update((select id from ids where k = 'e1'), 'Ay-25 yanacaq', 460, 'AZN');
select tests.check((select name = 'Ay-25 yanacaq' and amount = 460 from public.fleet_expenses where id = (select id from ids where k = 'e1')), 'F24 the owner edits');
select public.fleet_expense_remove((select id from ids where k = 'e1'));
select tests.check((select deleted_at is not null from public.fleet_expenses where id = (select id from ids where k = 'e1')), 'F25 "Sil" keeps the row (deleted_at)');
select public.fleet_job_set_status((select id from ids where k = 'j1'), 'done');
select tests.check((select status = 'done' from public.fleet_jobs where id = (select id from ids where k = 'j1')), 'F26 a job is finished');
select public.fleet_driver_unlink((select id from ids where k = 't1'));
select tests.login(:drv);
select tests.check((select count(*) = 0 from public.fleet_trucks), 'F27 an unlinked driver no longer sees the truck');
select tests.login(:owner);
select public.fleet_truck_remove((select id from ids where k = 't1'));
reset role;
select tests.check((select deleted_at is not null from public.fleet_trucks where id = (select id from ids where k = 't1')), 'F28 a removed truck is kept, marked');

select tests.summary('MAŞINLARIM (0130)');
rollback;
