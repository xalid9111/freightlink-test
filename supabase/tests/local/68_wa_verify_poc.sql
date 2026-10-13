-- WHATSAPP VERIFY PoC — 0030. Rolled back at the end.
\set admin   '''a0000000-0000-4000-8000-000000000001'''
\set other   '''a0000000-0000-4000-8000-000000000021'''
\set h1 '''1111111111111111111111111111111111111111111111111111111111111111'''
\set h2 '''2222222222222222222222222222222222222222222222222222222222222222'''
\set h3 '''3333333333333333333333333333333333333333333333333333333333333333'''
\set h4 '''4444444444444444444444444444444444444444444444444444444444444444'''

begin;

-- ---- clients cannot call the functions or write the tables ----------
set role authenticated;
select tests.login(:admin);
select tests.check(tests.err(format($$ select public.wa_poc_start(%L, '+994501234567', %L) $$, :admin, :h1)) like '%permission denied%',
  'W1 a signed-in user cannot call wa_poc_start directly');
select tests.check(tests.err(format($$ select public.wa_poc_inbound('wamid.x', %L, 'phone', '994501234567', false) $$, :h1)) like '%permission denied%',
  'W2 a signed-in user cannot call wa_poc_inbound');
select tests.check(tests.err(format($$ insert into public.wa_verify_challenges (user_id, phone_e164, expires_at) values (%L, '+994501234567', now()) $$, :admin)) like '%permission denied%',
  'W3 a signed-in user cannot insert challenges');
select tests.check(tests.err($$ select count(*) from public.wa_webhook_events $$) like '%permission denied%',
  'W4 the webhook-event table is not readable by users');
set role anon;
select tests.login(null);
select tests.check(tests.err($$ select count(*) from public.wa_verify_challenges $$) like '%permission denied%',
  'W5 anonymous visitors cannot read challenges');
reset role;

-- ---- start (service_role, as the Edge Function) ----------------------
set role service_role;
select tests.check(tests.err(format($$ select public.wa_poc_start(%L, '+994501234567', %L) $$, :other, :h1)) like '%admin_only%',
  'W6 PoC is admin-only by default');
select tests.check(tests.err(format($$ select public.wa_poc_start(%L, '0501234567', %L) $$, :admin, :h1)) like '%invalid_phone%',
  'W7 number must be E.164');
select tests.check(tests.err(format($$ select public.wa_poc_start(%L, '+994501234567', 'FL-RAWCODE') $$, :admin)) like '%invalid_hash%',
  'W8 only a SHA-256 hash is accepted, never a raw code');
create temp table t1 as select * from public.wa_poc_start(:admin, '+994501234567', :h1);
select tests.check((select count(*) = 1 from t1), 'W9 admin starts a test');
select tests.check((select status = 'pending' and expires_at between now() + interval '9 minutes' and now() + interval '11 minutes'
                    from public.wa_verify_challenges where id = (select id from t1)), 'W10 pending, expires in ~10 minutes');

-- ---- inbound outcomes ------------------------------------------------
select tests.check(public.wa_poc_inbound('wamid.A', :h1, 'bsuid_only', null, true) = 'no_phone_in_webhook',
  'W11 BSUID-only sender is never verified');
select tests.check((select status = 'pending' and consumed_at is null and challenge_hash is not null and sender_kind = 'bsuid_only' and has_bsuid
                    from public.wa_verify_challenges where id = (select id from t1)), 'W12 …and the challenge is not consumed');
select tests.check(public.wa_poc_inbound('wamid.A', :h1, 'phone', '994501234567', true) = 'duplicate',
  'W13 a Meta retry of the same message id is ignored');
select tests.check(public.wa_poc_inbound('wamid.B', :h1, 'phone', '994551112233', true) = 'phone_mismatch',
  'W14 a different sender number does not match');
select tests.check(public.wa_poc_inbound('wamid.C', :h1, 'conflict', null, true) = 'sender_conflict',
  'W15 conflicting sender ids are rejected');
select tests.check(public.wa_poc_inbound('wamid.D', repeat('9', 64), 'phone', '994501234567', false) = 'no_challenge',
  'W16 unknown code → no_challenge');
select tests.check(public.wa_poc_inbound('wamid.E', :h1, 'phone', '994501234567', true) = 'verified',
  'W17 matching phone + code → verified');
select tests.check((select status = 'verified' and consumed_at is not null and challenge_hash is null and attempts = 4
                    from public.wa_verify_challenges where id = (select id from t1)), 'W18 consumed once, hash cleared');
select tests.check(public.wa_poc_inbound('wamid.F', :h1, 'phone', '994501234567', true) = 'no_challenge',
  'W19 a used code cannot be used again');

-- expiry
create temp table t2 as select * from public.wa_poc_start(:admin, '+994501234567', :h2);
update public.wa_verify_challenges set expires_at = now() - interval '1 second' where id = (select id from t2);
select tests.check(public.wa_poc_inbound('wamid.G', :h2, 'phone', '994501234567', false) = 'expired', 'W21 expired code is refused');
select tests.check((select status = 'expired' and challenge_hash is null from public.wa_verify_challenges where id = (select id from t2)),
  'W22 expired challenge is closed and its hash cleared');

-- lock after 5 failed attempts
create temp table t3 as select * from public.wa_poc_start(:admin, '+994501234567', :h3);
select public.wa_poc_inbound('wamid.L' || g, :h3, 'phone', '994000000000', false) from generate_series(1, 5) g;
select tests.check(public.wa_poc_inbound('wamid.L6', :h3, 'phone', '994501234567', false) = 'locked',
  'W23 after 5 failed attempts the code is locked, even for the right number');

-- a new start replaces an open one
create temp table t4 as select * from public.wa_poc_start(:admin, '+994501234567', :h4);
create temp table t5 as select * from public.wa_poc_start(:admin, '+994501234567', :h2);
select tests.check((select status = 'superseded' and challenge_hash is null from public.wa_verify_challenges where id = (select id from t4)),
  'W24 starting again replaces the previous open code');
select tests.check(tests.err(format($$ select public.wa_poc_start(%L, '+994501234567', %L) $$, :admin, :h1)) like '%rate_limited%',
  'W25 more than 5 starts in 10 minutes is rate-limited');
select tests.check(tests.err(format($$ select public.wa_poc_start(%L, '+994501234567', %L, 600, false) $$, :other, :h1)) is null,
  'W26 with admin-only switched off, any signed-in user may test');
grant select on t1 to authenticated;
reset role;

-- ---- users see only their own rows, never the hash -------------------
set role authenticated;
select tests.login(:other);
select tests.check((select count(*) = 1 from public.wa_verify_challenges), 'W27 a user sees only their own challenge');
select tests.check(tests.err($$ select challenge_hash from public.wa_verify_challenges $$) like '%permission denied%',
  'W28 the challenge hash column is not readable');
select tests.login(:admin);
select tests.check((select count(*) = 5 from public.wa_verify_challenges), 'W29 admin sees only own rows');
reset role;

select tests.summary('wa_verify_poc');
rollback;
