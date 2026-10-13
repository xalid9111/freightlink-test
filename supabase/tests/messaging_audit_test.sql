-- =====================================================================
-- Messaging audit test — 2 cargo owners + 2 carriers, run INSIDE ONE
-- TRANSACTION THAT IS ROLLED BACK at the end: nothing is saved, no real
-- data is touched. Run in Supabase → SQL Editor AFTER migration 0011.
-- Success = the last line prints "ALL MESSAGING TESTS PASSED".
-- Any failure stops with an error naming the test (still rolled back).
-- =====================================================================
begin;

-- ---------- setup (as postgres) -------------------------------------
insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
 ('00000000-0000-4000-8000-0000000000a1','00000000-0000-0000-0000-000000000000','authenticated','authenticated','t_owner1@audit.test',  '{"full_name":"Test Owner 1","role":"cargo_owner","phone":"+994700000901"}', now(), now()),
 ('00000000-0000-4000-8000-0000000000a2','00000000-0000-0000-0000-000000000000','authenticated','authenticated','t_owner2@audit.test',  '{"full_name":"Test Owner 2","role":"cargo_owner","phone":"+994700000902"}', now(), now()),
 ('00000000-0000-4000-8000-0000000000b1','00000000-0000-0000-0000-000000000000','authenticated','authenticated','t_carrier1@audit.test','{"full_name":"Test Carrier 1","role":"carrier","phone":"+994700000903"}', now(), now()),
 ('00000000-0000-4000-8000-0000000000b2','00000000-0000-0000-0000-000000000000','authenticated','authenticated','t_carrier2@audit.test','{"full_name":"Test Carrier 2","role":"carrier","phone":"+994700000904"}', now(), now());

insert into public.cargo (id, owner_id, pickup_country, pickup_city, destination_country, destination_city, weight_kg, pickup_date, offered_price) values
 ('00000000-0000-4000-8000-0000000000c1','00000000-0000-4000-8000-0000000000a1','Azerbaijan','Baku','Georgia','Tbilisi',5000, current_date + 1, 1200),
 ('00000000-0000-4000-8000-0000000000c2','00000000-0000-4000-8000-0000000000a2','Türkiye','Istanbul','Azerbaijan','Baku',8000, current_date + 2, 3000);

set local role authenticated;

-- ---------- T1: carrier1 opens chat on owner1's cargo ----------------
do $$
declare c1 public.conversations; c1b public.conversations;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000b1","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000b1', true);
  c1 := public.get_or_create_conversation('00000000-0000-4000-8000-0000000000c1');
  if c1.cargo_owner_id <> '00000000-0000-4000-8000-0000000000a1' then raise exception 'T1 FAILED: wrong owner'; end if;
  if c1.carrier_user_id <> '00000000-0000-4000-8000-0000000000b1' then raise exception 'T1 FAILED: wrong carrier'; end if;
  c1b := public.get_or_create_conversation('00000000-0000-4000-8000-0000000000c1');
  if c1b.id <> c1.id then raise exception 'T1 FAILED: duplicate conversation created'; end if;
  insert into public.messages (conversation_id, sender_id, receiver_id, message)
  values (c1.id, '00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000a1', 'Salam, yük aktualdır?');
  raise notice 'T1 PASSED: carrier1 → owner1 chat created once, message sent';
end $$;

-- ---------- T2: a message to the WRONG receiver is rejected ----------
do $$
declare cid uuid; blocked boolean := false;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000b1","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000b1', true);
  select id into cid from public.conversations where cargo_id = '00000000-0000-4000-8000-0000000000c1' and carrier_user_id = '00000000-0000-4000-8000-0000000000b1';
  begin
    insert into public.messages (conversation_id, sender_id, receiver_id, message)
    values (cid, '00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000b2', 'wrong receiver');
  exception when others then blocked := true;
  end;
  if not blocked then raise exception 'T2 FAILED: mis-addressed message was accepted'; end if;
  raise notice 'T2 PASSED: mis-addressed message blocked';
end $$;

-- ---------- T3: carrier2 opens its own chats (cargo1 and cargo2) -----
do $$
declare x public.conversations; y public.conversations;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000b2","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000b2', true);
  x := public.get_or_create_conversation('00000000-0000-4000-8000-0000000000c1');
  y := public.get_or_create_conversation('00000000-0000-4000-8000-0000000000c2');
  if x.cargo_owner_id <> '00000000-0000-4000-8000-0000000000a1' or y.cargo_owner_id <> '00000000-0000-4000-8000-0000000000a2' then
    raise exception 'T3 FAILED: chat opened with the wrong owner';
  end if;
  insert into public.messages (conversation_id, sender_id, receiver_id, message)
  values (y.id, '00000000-0000-4000-8000-0000000000b2', '00000000-0000-4000-8000-0000000000a2', 'TR→AZ yükü üçün yazıram');
  -- carrier2 must not see carrier1's conversation or its messages
  if exists (select 1 from public.messages m join public.conversations c on c.id = m.conversation_id
             where c.carrier_user_id = '00000000-0000-4000-8000-0000000000b1') then
    raise exception 'T3 FAILED: carrier2 can read carrier1''s messages';
  end if;
  raise notice 'T3 PASSED: carrier2 chats go to the right owners; other chats invisible';
end $$;

-- ---------- T4: owner1 sees both carriers and replies ----------------
do $$
declare n int; cid uuid;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000a1', true);
  select count(*) into n from public.conversations where cargo_id = '00000000-0000-4000-8000-0000000000c1';
  if n <> 2 then raise exception 'T4 FAILED: owner1 should see 2 chats, sees %', n; end if;
  if exists (select 1 from public.conversations where cargo_owner_id = '00000000-0000-4000-8000-0000000000a2') then
    raise exception 'T4 FAILED: owner1 can see owner2''s chats';
  end if;
  select id into cid from public.conversations where cargo_id = '00000000-0000-4000-8000-0000000000c1' and carrier_user_id = '00000000-0000-4000-8000-0000000000b1';
  select count(*) into n from public.messages where conversation_id = cid;
  if n <> 1 then raise exception 'T4 FAILED: owner1 should see carrier1''s message'; end if;
  insert into public.messages (conversation_id, sender_id, receiver_id, message)
  values (cid, '00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000b1', 'Bəli, aktualdır');
  raise notice 'T4 PASSED: owner1 sees both carriers'' chats only and can reply';
end $$;

-- ---------- T5: owner opens chat from an offer (no duplicate) -------
do $$
declare a public.conversations; n int;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000a1', true);
  a := public.get_or_create_conversation('00000000-0000-4000-8000-0000000000c1', '00000000-0000-4000-8000-0000000000b2');
  if a.carrier_user_id <> '00000000-0000-4000-8000-0000000000b2' then raise exception 'T5 FAILED: wrong carrier'; end if;
  select count(*) into n from public.conversations where cargo_id = '00000000-0000-4000-8000-0000000000c1';
  if n <> 2 then raise exception 'T5 FAILED: duplicate created (% chats)', n; end if;
  raise notice 'T5 PASSED: owner → carrier chat reuses the existing conversation';
end $$;

-- ---------- T6: everyone can write about a load (0013); never to self --
do $$
declare v public.conversations; self_blocked boolean := false;
begin
  -- owner2 (a cargo owner, not a carrier) writes about owner1's load
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000a2', true);
  v := public.get_or_create_conversation('00000000-0000-4000-8000-0000000000c1');
  if v.cargo_owner_id <> '00000000-0000-4000-8000-0000000000a1' or v.carrier_user_id <> '00000000-0000-4000-8000-0000000000a2' then
    raise exception 'T6 FAILED: wrong participants';
  end if;
  insert into public.messages (conversation_id, sender_id, receiver_id, message)
  values (v.id, '00000000-0000-4000-8000-0000000000a2', '00000000-0000-4000-8000-0000000000a1', 'T6 hello');
  -- nobody can open a chat with themselves on their own load
  begin
    perform public.get_or_create_conversation('00000000-0000-4000-8000-0000000000c2');
  exception when others then self_blocked := true;
  end;
  if not self_blocked then raise exception 'T6 FAILED: self chat allowed'; end if;
  raise notice 'T6 PASSED: any role can message a load poster; self-chat refused';
end $$;

-- ---------- T7: carrier1 reads reply; mark-read can't edit text ------
do $$
declare cid uuid; n int; txt text;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000b1","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000000b1', true);
  select id into cid from public.conversations where cargo_id = '00000000-0000-4000-8000-0000000000c1' and carrier_user_id = '00000000-0000-4000-8000-0000000000b1';
  select count(*) into n from public.messages where conversation_id = cid;
  if n <> 2 then raise exception 'T7 FAILED: carrier1 should see 2 messages, sees %', n; end if;
  update public.messages set read_at = now(), message = 'HACKED'
  where conversation_id = cid and receiver_id = '00000000-0000-4000-8000-0000000000b1';
  select message into txt from public.messages where conversation_id = cid and receiver_id = '00000000-0000-4000-8000-0000000000b1';
  if txt <> 'Bəli, aktualdır' then raise exception 'T7 FAILED: receiver could edit message text'; end if;
  if exists (select 1 from public.messages where conversation_id = cid and receiver_id = '00000000-0000-4000-8000-0000000000b1' and read_at is null) then
    raise exception 'T7 FAILED: read_at not set';
  end if;
  raise notice 'T7 PASSED: two-way thread visible; mark-read works; text protected';
end $$;

reset role;
rollback;
-- Reached only if every test above passed:
select 'ALL MESSAGING TESTS PASSED — nothing was saved' as result;
