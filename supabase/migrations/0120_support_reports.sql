-- =====================================================================
-- 0120 — "Təklif və iradlar" and payment / VIP problems for the admins
-- (owner, 13.11.2026).
--
-- One inbox (support_reports) for the admins:
--   * 'feedback' — a user's suggestion / remark (Profil → Təklif və iradlar);
--   * 'payment' / 'promo' — a user's "Problem bildir" on a payment or an
--     "Önə çıxar" (VIP / Premium) sheet, with the payment when known;
--   * 'auto_payment' — found by the server itself, once per payment and
--     problem: a LIVE payment that failed (30 days), one stuck unpaid for
--     more than 30 minutes (7 days), or one paid whose VIP / Premium /
--     İrəli çək / verified order never became 'paid'.
-- Users write only through support_report_submit (checked, 10 an hour) and
-- read only their own; admins read all and change the status (new → seen
-- → resolved) through admin_support_set_status, logged in the Audit Log.
--
-- Safe: forward-only, re-runnable; one new table and functions. No other
-- row is changed or deleted.
-- =====================================================================

begin;

create table if not exists public.support_reports (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.users(id) on delete set null,
  kind text not null check (kind in ('feedback', 'payment', 'promo', 'auto_payment')),
  message text check (message is null or char_length(message) <= 2000),
  payment_id uuid references public.ad_payments(id) on delete set null,
  problem text check (problem is null or problem in ('failed', 'stuck', 'not_applied')),
  auto_key text unique,
  status text not null default 'new' check (status in ('new', 'seen', 'resolved')),
  admin_note text check (admin_note is null or char_length(admin_note) <= 1000),
  handled_by uuid references public.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists support_reports_status_idx on public.support_reports (status, created_at desc);
create index if not exists support_reports_user_idx on public.support_reports (user_id, created_at desc);
alter table public.support_reports enable row level security;
revoke all on public.support_reports from anon, authenticated;
grant select on public.support_reports to authenticated;
drop policy if exists "support_reports_own_or_admin" on public.support_reports;
create policy "support_reports_own_or_admin" on public.support_reports for select to authenticated
  using (user_id = (select auth.uid()) or public.is_admin());

-- A user's report.
create or replace function public.support_report_submit(
  p_kind text, p_message text, p_payment_id uuid default null)
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_uid uuid := auth.uid();
  v_msg text := btrim(coalesce(p_message, ''));
  v_id uuid;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if public.is_blocked(v_uid) then raise exception 'blocked' using errcode = '42501'; end if;
  if p_kind is null or p_kind not in ('feedback', 'payment', 'promo') then
    raise exception 'invalid_kind' using errcode = '22023';
  end if;
  if char_length(v_msg) < 3 or char_length(v_msg) > 2000 then
    raise exception 'invalid_message' using errcode = '22023';
  end if;
  if p_payment_id is not null and not exists (select 1 from ad_payments where id = p_payment_id and user_id = v_uid) then
    raise exception 'not_allowed' using errcode = '42501';
  end if;
  if (select count(*) from support_reports where user_id = v_uid and created_at > now() - interval '1 hour') >= 10 then
    raise exception 'too_many' using errcode = '54000';
  end if;
  insert into support_reports (user_id, kind, message, payment_id)
  values (v_uid, p_kind, v_msg, p_payment_id)
  returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.support_report_submit(text, text, uuid) from public, anon;
grant execute on function public.support_report_submit(text, text, uuid) to authenticated;

-- The server's own finds (once per payment and problem; re-running adds nothing).
create or replace function public._support_sync_payment_problems()
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  -- Failed live payments (30 days).
  insert into support_reports (user_id, kind, payment_id, problem, auto_key, created_at)
  select p.user_id, 'auto_payment', p.id, 'failed', 'failed:' || p.id, coalesce(p.updated_at, p.created_at)
  from ad_payments p
  where p.mode = 'live' and p.status = 'failed' and p.created_at > now() - interval '30 days'
  on conflict (auto_key) do nothing;
  -- Live payments left unpaid for more than 30 minutes (7 days).
  insert into support_reports (user_id, kind, payment_id, problem, auto_key)
  select p.user_id, 'auto_payment', p.id, 'stuck', 'stuck:' || p.id
  from ad_payments p
  where p.mode = 'live' and p.status in ('created', 'pending')
    and p.created_at < now() - interval '30 minutes' and p.created_at > now() - interval '7 days'
  on conflict (auto_key) do nothing;
  -- Paid, but the VIP / Premium / İrəli çək / verified order is not 'paid'.
  insert into support_reports (user_id, kind, payment_id, problem, auto_key)
  select p.user_id, 'auto_payment', p.id, 'not_applied', 'not_applied:' || p.id
  from ad_payments p
  where p.status = 'succeeded' and p.mode = 'live' and p.created_at > now() - interval '30 days'
    and p.confirmed_at is not null and p.confirmed_at < now() - interval '10 minutes'
    and (
      (p.market_vip_order_id is not null and exists (select 1 from market_vip_orders o where o.id = p.market_vip_order_id and o.status <> 'paid'))
      or (p.cargo_vip_order_id is not null and exists (select 1 from cargo_vip_orders o where o.id = p.cargo_vip_order_id and o.status <> 'paid'))
      or (p.market_promo_order_id is not null and exists (select 1 from market_promo_orders o where o.id = p.market_promo_order_id and o.status <> 'paid'))
      or (p.cargo_promo_order_id is not null and exists (select 1 from cargo_promo_orders o where o.id = p.cargo_promo_order_id and o.status <> 'paid'))
      or (p.place_promo_order_id is not null and exists (select 1 from place_promo_orders o where o.id = p.place_promo_order_id and o.status <> 'paid'))
      or (p.verified_order_id is not null and exists (select 1 from verified_orders o where o.id = p.verified_order_id and o.status <> 'paid'))
    )
  on conflict (auto_key) do nothing;
end;
$$;
revoke all on function public._support_sync_payment_problems() from public, anon, authenticated;

-- How many wait for an admin (0 for everyone else).
create or replace function public.admin_support_open_count()
returns integer language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not public.is_admin() then return 0; end if;
  perform public._support_sync_payment_problems();
  return (select count(*)::int from support_reports where status = 'new');
end;
$$;
revoke all on function public.admin_support_open_count() from public, anon;
grant execute on function public.admin_support_open_count() to authenticated;

-- The admins' list: newest first, with the user and the payment.
create or replace function public.admin_support_list(p_status text default null, p_limit integer default 100)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform public._require_admin();
  perform public._support_sync_payment_problems();
  return coalesce((
    select jsonb_agg(row_to_json(x)::jsonb order by x.created_at desc)
    from (
      select r.id, r.user_id, r.kind, r.message, r.payment_id, r.problem, r.status, r.admin_note,
             r.created_at, r.updated_at, u.full_name as user_name,
             p.amount, p.currency, p.status as payment_status, p.mode as payment_mode, p.failure_reason,
             case
               when p.id is null then null
               when p.verified_order_id is not null then 'verified'
               when p.place_promo_order_id is not null then 'place_promo'
               when p.cargo_promo_order_id is not null then 'cargo_promo'
               when p.market_promo_order_id is not null then 'market_promo'
               when p.cargo_vip_order_id is not null then 'cargo_vip'
               when p.market_vip_order_id is not null then 'market_vip'
               when p.tir_park_booking_id is not null then 'tir_park'
               else 'ad'
             end as order_kind
      from support_reports r
      left join users u on u.id = r.user_id
      left join ad_payments p on p.id = r.payment_id
      where p_status is null or r.status = p_status
      order by r.created_at desc
      limit greatest(1, least(coalesce(p_limit, 100), 300))
    ) x
  ), '[]'::jsonb);
end;
$$;
revoke all on function public.admin_support_list(text, integer) from public, anon;
grant execute on function public.admin_support_list(text, integer) to authenticated;

-- Baxılır / Həll olundu (+ a note); logged.
create or replace function public.admin_support_set_status(p_id uuid, p_status text, p_note text default null)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_old text;
begin
  perform public._require_admin();
  if p_status is null or p_status not in ('new', 'seen', 'resolved') then
    raise exception 'invalid_status' using errcode = '22023';
  end if;
  select status into v_old from support_reports where id = p_id;
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
  update support_reports set
    status = p_status,
    admin_note = coalesce(nullif(btrim(coalesce(p_note, '')), ''), admin_note),
    handled_by = auth.uid(),
    updated_at = now()
  where id = p_id;
  perform public._admin_log('support.status', 'support_report', p_id::text,
    jsonb_build_object('status', v_old), jsonb_build_object('status', p_status), p_note);
end;
$$;
revoke all on function public.admin_support_set_status(uuid, text, text) from public, anon;
grant execute on function public.admin_support_set_status(uuid, text, text) to authenticated;

commit;

notify pgrst, 'reload schema';
