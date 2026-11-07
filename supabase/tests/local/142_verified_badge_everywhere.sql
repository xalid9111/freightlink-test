-- The blue badge everywhere (user_profiles) for a paid subscription too —
-- 0105. Rolled back.
\set user1   '''a0000000-0000-4000-8000-000000000011'''
\set user2   '''a0000000-0000-4000-8000-000000000012'''
\set other   '''a0000000-0000-4000-8000-000000000021'''

begin;
reset role;
update public.users set is_verified = false where id in (:user1, :user2);
update public.users set is_verified = true where id = :other;
insert into public.verified_subscriptions (user_id, paid_until) values (:user1, now() + interval '20 days')
  on conflict (user_id) do update set paid_until = excluded.paid_until;
insert into public.verified_subscriptions (user_id, paid_until) values (:user2, now() - interval '1 day')
  on conflict (user_id) do update set paid_until = excluded.paid_until;

set role authenticated;
select tests.login(:other);
select tests.check((select is_verified from public.user_profiles where id = :user1), 'B1 a running paid subscription: the badge for everybody');
select tests.check(not (select is_verified from public.user_profiles where id = :user2), 'B2 an ended subscription: no badge');
select tests.check((select is_verified from public.user_profiles where id = :other), 'B3 the Baş admin''s grant: the badge, as before');
select tests.check((select string_agg(column_name, ',' order by ordinal_position) from information_schema.columns
                     where table_schema = 'public' and table_name = 'user_profiles')
                   = 'id,role,full_name,avatar_url,is_verified,is_early_member,last_seen_at,is_active,created_at',
  'B4 the same public columns in the same order (no phone / e-mail)');
select tests.check(tests.err($$ select paid_until from public.verified_subscriptions where user_id = 'a0000000-0000-4000-8000-000000000011' $$) is null
                   and not exists (select 1 from public.verified_subscriptions where user_id = :user1),
  'B5 others still cannot read the subscription itself (only the badge)');
reset role;
select tests.check((select not is_verified from public.users where id = :user1), 'B6 users.is_verified stays the Baş admin''s grant only');
select tests.summary('MAVİ NİŞAN HƏR YERDƏ (0105)');
rollback;
