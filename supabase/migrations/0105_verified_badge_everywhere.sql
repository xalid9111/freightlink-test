-- =====================================================================
-- 0105 — the blue badge everywhere for a paid "Təsdiqlənmiş hesab" too
-- (owner, 07.11.2026).
--
-- 0104 kept the two ways apart (the Baş admin's grant = users.is_verified,
-- the 20 AZN / month subscription = verified_subscriptions). The public
-- profile view (user_profiles, 0019) is what every other screen reads —
-- load cards, the load page, Mesajlar, TIR Bazarı ads, the ad banner — so
-- its is_verified now means: granted by the Baş admin OR a subscription
-- paid (verified LIVE payment) and still running. Nothing else changes:
-- the same columns in the same order, the same rights; users.is_verified
-- itself is untouched (still only the Baş admin's grant).
--
-- Safe: forward-only, re-runnable; one view replaced. No row is changed.
-- =====================================================================

begin;

do $$
begin
  if to_regclass('public.verified_subscriptions') is null or to_regclass('public.user_profiles') is null then
    raise exception '0105: run 0019 and 0104_verified_account.sql first — nothing changed';
  end if;
end $$;

create or replace view public.user_profiles
with (security_barrier = true) as
  select u.id,
         u.role,
         u.full_name,
         u.avatar_url,
         (u.is_verified
          or exists (select 1 from public.verified_subscriptions s
                      where s.user_id = u.id and s.paid_until > now())) as is_verified,
         u.is_early_member,
         u.last_seen_at,
         u.is_active,
         u.created_at
  from public.users u;

comment on view public.user_profiles is
  'Public profile fields of every user (no e-mail, phone, language or moderation data). '
  'is_verified = the Baş admin''s grant or a running paid subscription (0105). '
  'Readable by signed-in users only. Contact data: get_user_contact().';

revoke all on public.user_profiles from public, anon, authenticated;
grant select on public.user_profiles to authenticated;
grant select on public.user_profiles to service_role;

commit;

notify pgrst, 'reload schema';
