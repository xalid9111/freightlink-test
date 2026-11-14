-- =====================================================================
-- 0121 — Web Push: notifications while TırLink is closed (owner, 14.11.2026).
--
-- * push_subscriptions — one row per device (browser / Home Screen app) that
--   switched it on; read only by its owner; written only through
--   push_subscribe / push_unsubscribe. Only the known push services are
--   accepted as endpoints (Apple, Google, Mozilla, Microsoft) — the sender
--   never posts anywhere else.
-- * push_prefs — per account: messages, important, preview (show the first
--   80 characters of a message; off = "Yeni mesajınız var").
-- * push_presence — the chat a user is reading right now (a heartbeat from
--   the open chat): no push for that chat while he reads it.
-- * push_outbox — one row per notification to send (server only; no user
--   reads it). Triggers fill it:
--     messages              → the receiver (private chats);
--     support_reports       → the admins (suggestions, payment / VIP problems);
--     tir_park_bookings     → the park's approved manager (new booking,
--                             receipt uploaded);
--     tir_park_workers      → the manager + the park's admin worker
--                             (a worker's request to join);
--     job_applications      → the other side (application / job offer).
--   Each new row is handed to the Edge Function push-send through pg_net
--   (asynchronous: the original write is never slowed or blocked). The
--   function URL and the shared secret are kept in Supabase Vault (created
--   here with a random value — never written in this file); push-send checks
--   the secret with push_hook_check (service role only).
-- * Signing out removes the device (push_unsubscribe); a deleted / blocked
--   account loses all its devices (trigger on users).
--
-- Safe: forward-only, re-runnable; new tables and functions only. Every
-- trigger is guarded: a push problem can never stop a message, booking or
-- application from being saved.
-- =====================================================================

begin;

-- pg_net (Supabase: schema net). Missing locally / not allowed = no sending,
-- everything else still works.
do $$
begin
  begin
    create extension if not exists pg_net;
  exception when others then
    raise notice 'pg_net not available here: %', sqlerrm;
  end;
end $$;

-- Vault: the push-send URL and a random shared secret (only if missing).
do $$
begin
  if to_regclass('vault.secrets') is not null then
    if not exists (select 1 from vault.secrets where name = 'push_hook_secret') then
      perform vault.create_secret(replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''),
        'push_hook_secret', 'TirLink Web Push: database trigger -> push-send');
    end if;
    if not exists (select 1 from vault.secrets where name = 'push_function_url') then
      perform vault.create_secret('https://jqdqtfmxnqezlsetelpi.supabase.co/functions/v1/push-send',
        'push_function_url', 'TirLink Web Push: the push-send Edge Function');
    end if;
  end if;
exception when others then
  raise notice 'vault not available here: %', sqlerrm;
end $$;

-- 1) Tables ------------------------------------------------------------------
create table if not exists public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  endpoint text not null unique check (char_length(endpoint) between 20 and 1000),
  p256dh text not null check (char_length(p256dh) between 20 and 200),
  auth text not null check (char_length(auth) between 8 and 100),
  platform text check (platform is null or char_length(platform) <= 40),
  user_agent text check (user_agent is null or char_length(user_agent) <= 300),
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);
create index if not exists push_subscriptions_user_idx on public.push_subscriptions (user_id);
alter table public.push_subscriptions enable row level security;
revoke all on public.push_subscriptions from anon, authenticated;
grant select on public.push_subscriptions to authenticated;
drop policy if exists "push_subscriptions_own" on public.push_subscriptions;
create policy "push_subscriptions_own" on public.push_subscriptions for select to authenticated
  using (user_id = (select auth.uid()));

create table if not exists public.push_prefs (
  user_id uuid primary key references public.users(id) on delete cascade,
  messages boolean not null default true,
  important boolean not null default true,
  preview boolean not null default false,
  updated_at timestamptz not null default now()
);
alter table public.push_prefs enable row level security;
revoke all on public.push_prefs from anon, authenticated;

create table if not exists public.push_presence (
  user_id uuid primary key references public.users(id) on delete cascade,
  conversation_id uuid,
  seen_at timestamptz not null default now()
);
alter table public.push_presence enable row level security;
revoke all on public.push_presence from anon, authenticated;

create table if not exists public.push_outbox (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  kind text not null check (kind in ('message', 'admin_report', 'park_booking', 'park_receipt', 'park_worker', 'job_application')),
  title text not null check (char_length(title) <= 120),
  body text not null check (char_length(body) <= 200),
  url text not null check (char_length(url) <= 200),
  tag text not null check (char_length(tag) <= 80),
  status text not null default 'queued' check (status in ('queued', 'sending', 'sent', 'failed', 'no_devices')),
  sent integer not null default 0,
  failed integer not null default 0,
  error text check (error is null or char_length(error) <= 300),
  created_at timestamptz not null default now(),
  processed_at timestamptz
);
create index if not exists push_outbox_user_idx on public.push_outbox (user_id, created_at desc);
alter table public.push_outbox enable row level security;
revoke all on public.push_outbox from anon, authenticated;

-- 2) Helpers -----------------------------------------------------------------
-- Only the real push services (no other address is ever called).
create or replace function public._push_endpoint_ok(p_endpoint text)
returns boolean language sql immutable set search_path = public, pg_temp as $$
  select coalesce(p_endpoint ~ '^https://(fcm\.googleapis\.com|android\.googleapis\.com|updates\.push\.services\.mozilla\.com|push\.services\.mozilla\.com|web\.push\.apple\.com|[a-z0-9-]+\.push\.apple\.com|[a-z0-9.-]+\.notify\.windows\.com)/', false);
$$;

-- The texts in the user's language (az, tr, en, ru, ka; anything else = en).
create or replace function public._push_t(p_lang text, p_key text, p_arg text default '')
returns text language plpgsql immutable set search_path = public, pg_temp as $$
declare
  t jsonb := '{
    "msg_new":         {"az":"Yeni mesajınız var","tr":"Yeni mesajınız var","en":"You have a new message","ru":"У вас новое сообщение","ka":"ახალი შეტყობინება გაქვთ"},
    "admin_feedback":  {"az":"Yeni təklif / irad","tr":"Yeni öneri / şikayet","en":"New suggestion / remark","ru":"Новое предложение / замечание","ka":"ახალი წინადადება / შენიშვნა"},
    "admin_payment":   {"az":"Ödəniş problemi bildirildi","tr":"Ödeme sorunu bildirildi","en":"Payment problem reported","ru":"Сообщение о проблеме с оплатой","ka":"გადახდის პრობლემა"},
    "admin_promo":     {"az":"VIP / reklam problemi bildirildi","tr":"VIP / reklam sorunu bildirildi","en":"VIP / ad problem reported","ru":"Проблема с VIP / рекламой","ka":"VIP / რეკლამის პრობლემა"},
    "park_booking":    {"az":"Yeni rezervasiya: %s","tr":"Yeni rezervasyon: %s","en":"New booking: %s","ru":"Новая бронь: %s","ka":"ახალი ჯავშანი: %s"},
    "park_receipt":    {"az":"Yeni ödəniş qəbzi — yoxlayın: %s","tr":"Yeni ödeme dekontu — kontrol edin: %s","en":"New payment receipt — please check: %s","ru":"Новая квитанция — проверьте: %s","ka":"ახალი ქვითარი — შეამოწმეთ: %s"},
    "park_worker":     {"az":"Yeni işçi müraciəti: %s","tr":"Yeni çalışan başvurusu: %s","en":"New worker request: %s","ru":"Новая заявка работника: %s","ka":"ახალი თანამშრომლის მოთხოვნა: %s"},
    "job_application": {"az":"İş Mərkəzi: yeni müraciət","tr":"İş Merkezi: yeni başvuru","en":"Job Centre: new application","ru":"Центр вакансий: новый отклик","ka":"სამუშაო ცენტრი: ახალი განაცხადი"},
    "job_offer":       {"az":"İş Mərkəzi: yeni iş təklifi","tr":"İş Merkezi: yeni iş teklifi","en":"Job Centre: new job offer","ru":"Центр вакансий: новое предложение работы","ka":"სამუშაო ცენტრი: ახალი სამუშაო შეთავაზება"}
  }';
  v text;
begin
  v := coalesce(t -> p_key ->> coalesce(nullif(p_lang, ''), 'az'), t -> p_key ->> 'en', '');
  return replace(v, '%s', coalesce(p_arg, ''));
end;
$$;

create or replace function public._push_lang(p_user uuid)
returns text language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce((select preferred_lang from users where id = p_user), 'az');
$$;
revoke all on function public._push_lang(uuid) from public, anon, authenticated;

-- Hand one outbox row to push-send (asynchronous; never raises).
create or replace function public._push_dispatch(p_id uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_url text;
  v_secret text;
begin
  if to_regnamespace('net') is null or to_regclass('vault.decrypted_secrets') is null then
    return;
  end if;
  execute 'select decrypted_secret from vault.decrypted_secrets where name = $1' into v_url using 'push_function_url';
  execute 'select decrypted_secret from vault.decrypted_secrets where name = $1' into v_secret using 'push_hook_secret';
  if v_url is null or v_secret is null then return; end if;
  execute 'select net.http_post(url := $1, body := $2, headers := $3, timeout_milliseconds := 8000)'
    using v_url, jsonb_build_object('id', p_id),
          jsonb_build_object('Content-Type', 'application/json', 'x-push-secret', v_secret);
exception when others then
  raise notice 'push dispatch skipped: %', sqlerrm;
end;
$$;
revoke all on function public._push_dispatch(uuid) from public, anon, authenticated;

-- One notification for one user, if he wants it and has a device.
create or replace function public._push_enqueue(
  p_user uuid, p_kind text, p_title text, p_body text, p_url text, p_tag text)
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_prefs push_prefs;
  v_id uuid;
begin
  if p_user is null then return null; end if;
  if not exists (select 1 from push_subscriptions where user_id = p_user) then return null; end if;
  if exists (select 1 from users where id = p_user and (not is_active or is_blocked)) then return null; end if;
  select * into v_prefs from push_prefs where user_id = p_user;
  if p_kind = 'message' and coalesce(v_prefs.messages, true) = false then return null; end if;
  if p_kind <> 'message' and coalesce(v_prefs.important, true) = false then return null; end if;
  insert into push_outbox (user_id, kind, title, body, url, tag)
  values (p_user, p_kind, left(coalesce(nullif(btrim(p_title), ''), 'TırLink'), 120), left(coalesce(p_body, ''), 200),
          left(p_url, 200), left(p_tag, 80))
  returning id into v_id;
  perform public._push_dispatch(v_id);
  return v_id;
end;
$$;
revoke all on function public._push_enqueue(uuid, text, text, text, text, text) from public, anon, authenticated;

-- 3) Triggers ----------------------------------------------------------------
-- A private message → the receiver ("Əli: Yeni mesajınız var"; the first 80
-- characters only if he turned the preview on). Not while he reads that chat;
-- not twice when the same write already sent a "park_receipt".
create or replace function public._push_on_message()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_name text;
  v_body text;
  v_preview boolean;
begin
  if new.receiver_id is null or new.receiver_id = new.sender_id then return new; end if;
  if coalesce(new.deleted_silent, false) or new.deleted_at is not null then return new; end if;
  -- Reading this chat (or another topic with the same person, shown in the
  -- same thread) right now: no push.
  if exists (select 1 from push_presence p left join conversations c on c.id = p.conversation_id
             where p.user_id = new.receiver_id and p.seen_at > now() - interval '40 seconds'
               and (p.conversation_id = new.conversation_id or new.sender_id in (c.cargo_owner_id, c.carrier_user_id))) then
    return new;
  end if;
  if exists (select 1 from push_outbox where user_id = new.receiver_id and kind = 'park_receipt' and created_at = now()) then
    return new;
  end if;
  select coalesce(nullif(btrim(full_name), ''), 'TırLink') into v_name from users where id = new.sender_id;
  select coalesce(preview, false) into v_preview from push_prefs where user_id = new.receiver_id;
  v_body := case when coalesce(v_preview, false) and nullif(btrim(coalesce(new.message, '')), '') is not null
                 then left(regexp_replace(btrim(new.message), '\s+', ' ', 'g'), 80)
                 else public._push_t(public._push_lang(new.receiver_id), 'msg_new') end;
  perform public._push_enqueue(new.receiver_id, 'message', v_name, v_body,
    '/#/chat/' || new.conversation_id, 'chat-' || new.conversation_id);
  return new;
exception when others then
  raise notice 'push (message) skipped: %', sqlerrm;
  return new;
end;
$$;
drop trigger if exists zz_push_message on public.messages;
create trigger zz_push_message after insert on public.messages
  for each row execute function public._push_on_message();

-- A user's suggestion / payment or VIP problem → every active admin.
create or replace function public._push_on_report()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
declare r record;
begin
  if new.kind not in ('feedback', 'payment', 'promo') then return new; end if;
  for r in select id from users where role = 'admin' and is_active and not is_blocked
           and id is distinct from new.user_id loop
    perform public._push_enqueue(r.id, 'admin_report', 'TırLink',
      public._push_t(public._push_lang(r.id), 'admin_' || new.kind), '/#/admin-reports', 'admin-reports');
  end loop;
  return new;
exception when others then
  raise notice 'push (report) skipped: %', sqlerrm;
  return new;
end;
$$;
drop trigger if exists zz_push_report on public.support_reports;
create trigger zz_push_report after insert on public.support_reports
  for each row execute function public._push_on_report();

-- A booking / a receipt → the park's approved manager.
create or replace function public._push_on_booking()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_manager uuid;
  v_park text;
  v_kind text;
begin
  if tg_op = 'INSERT' then
    v_kind := 'park_booking';
  elsif new.receipt_at is not null and new.receipt_at is distinct from old.receipt_at then
    v_kind := 'park_receipt';
  else
    return new;
  end if;
  select manager_id, name into v_manager, v_park from tir_parks
   where id = new.park_id and manager_status = 'approved';
  if v_manager is null or v_manager = new.user_id then return new; end if;
  perform public._push_enqueue(v_manager, v_kind, 'TırLink',
    public._push_t(public._push_lang(v_manager), v_kind, v_park), '/#/tirpark/manage', v_kind || '-' || new.id);
  return new;
exception when others then
  raise notice 'push (booking) skipped: %', sqlerrm;
  return new;
end;
$$;
drop trigger if exists zz_push_booking on public.tir_park_bookings;
create trigger zz_push_booking after insert or update of receipt_at on public.tir_park_bookings
  for each row execute function public._push_on_booking();

-- A worker asks to join → the manager and the park's admin worker.
create or replace function public._push_on_worker()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
declare
  r record;
  v_name text;
begin
  if new.status is distinct from 'pending' then return new; end if;
  if tg_op = 'UPDATE' and old.status is not distinct from 'pending' then return new; end if;
  v_name := coalesce(nullif(btrim(new.full_name), ''), (select full_name from users where id = new.user_id), '');
  for r in
    select manager_id as uid from tir_parks where id = new.park_id and manager_status = 'approved' and manager_id is not null
    union
    select user_id from tir_park_workers where park_id = new.park_id and is_admin and status = 'active' and active
  loop
    if r.uid is distinct from new.user_id then
      perform public._push_enqueue(r.uid, 'park_worker', 'TırLink',
        public._push_t(public._push_lang(r.uid), 'park_worker', v_name), '/#/tirpark/manage', 'park-worker-' || new.park_id);
    end if;
  end loop;
  return new;
exception when others then
  raise notice 'push (worker) skipped: %', sqlerrm;
  return new;
end;
$$;
drop trigger if exists zz_push_worker on public.tir_park_workers;
create trigger zz_push_worker after insert or update of status on public.tir_park_workers
  for each row execute function public._push_on_worker();

-- İş Mərkəzi: an application → the employer; a job offer → the driver.
create or replace function public._push_on_job_application()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_to uuid;
  v_key text;
begin
  if new.initiated_by = 'seeker' then
    v_to := new.employer_id; v_key := 'job_application';
  else
    v_to := new.seeker_id; v_key := 'job_offer';
  end if;
  perform public._push_enqueue(v_to, 'job_application', 'TırLink',
    public._push_t(public._push_lang(v_to), v_key), '/#/jobs/applications', 'job-' || new.id);
  return new;
exception when others then
  raise notice 'push (job) skipped: %', sqlerrm;
  return new;
end;
$$;
drop trigger if exists zz_push_job_application on public.job_applications;
create trigger zz_push_job_application after insert on public.job_applications
  for each row execute function public._push_on_job_application();

-- A deleted / blocked / closed account keeps no devices.
create or replace function public._push_on_user_closed()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if (new.is_blocked and not coalesce(old.is_blocked, false)) or (not new.is_active and coalesce(old.is_active, true)) then
    delete from push_subscriptions where user_id = new.id;
  end if;
  return new;
exception when others then
  return new;
end;
$$;
drop trigger if exists zz_push_user_closed on public.users;
create trigger zz_push_user_closed after update of is_blocked, is_active on public.users
  for each row execute function public._push_on_user_closed();

-- 4) The app's calls -----------------------------------------------------------
create or replace function public.push_subscribe(
  p_endpoint text, p_p256dh text, p_auth text, p_platform text default null, p_user_agent text default null)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if public.is_blocked(v_uid) then raise exception 'blocked' using errcode = '42501'; end if;
  if not public._push_endpoint_ok(p_endpoint) or char_length(coalesce(p_p256dh, '')) < 20 or char_length(coalesce(p_auth, '')) < 8 then
    raise exception 'invalid_subscription' using errcode = '22023';
  end if;
  if (select count(*) from push_subscriptions where user_id = v_uid and endpoint <> p_endpoint) >= 20 then
    raise exception 'too_many' using errcode = '54000';
  end if;
  -- The same device signed in with another account now belongs to this one.
  insert into push_subscriptions (user_id, endpoint, p256dh, auth, platform, user_agent)
  values (v_uid, p_endpoint, p_p256dh, p_auth, left(p_platform, 40), left(p_user_agent, 300))
  on conflict (endpoint) do update set
    user_id = excluded.user_id, p256dh = excluded.p256dh, auth = excluded.auth,
    platform = excluded.platform, user_agent = excluded.user_agent, last_seen_at = now();
end;
$$;
revoke all on function public.push_subscribe(text, text, text, text, text) from public, anon;
grant execute on function public.push_subscribe(text, text, text, text, text) to authenticated;

create or replace function public.push_unsubscribe(p_endpoint text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  delete from push_subscriptions where endpoint = p_endpoint and user_id = auth.uid();
end;
$$;
revoke all on function public.push_unsubscribe(text) from public, anon;
grant execute on function public.push_unsubscribe(text) to authenticated;

create or replace function public.push_prefs_get()
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v push_prefs;
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  select * into v from push_prefs where user_id = auth.uid();
  return jsonb_build_object('messages', coalesce(v.messages, true), 'important', coalesce(v.important, true),
                            'preview', coalesce(v.preview, false));
end;
$$;
revoke all on function public.push_prefs_get() from public, anon;
grant execute on function public.push_prefs_get() to authenticated;

create or replace function public.push_prefs_set(p_messages boolean, p_important boolean, p_preview boolean)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  insert into push_prefs (user_id, messages, important, preview)
  values (auth.uid(), coalesce(p_messages, true), coalesce(p_important, true), coalesce(p_preview, false))
  on conflict (user_id) do update set messages = excluded.messages, important = excluded.important,
    preview = excluded.preview, updated_at = now();
end;
$$;
revoke all on function public.push_prefs_set(boolean, boolean, boolean) from public, anon;
grant execute on function public.push_prefs_set(boolean, boolean, boolean) to authenticated;

-- The open chat (null = none); only a chat he takes part in.
create or replace function public.push_active(p_conversation uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then return; end if;
  if p_conversation is not null and not exists (
       select 1 from messages where conversation_id = p_conversation and (sender_id = v_uid or receiver_id = v_uid) limit 1)
     and not exists (select 1 from conversations c where c.id = p_conversation
                     and v_uid in (c.cargo_owner_id, c.carrier_user_id)) then
    return;
  end if;
  insert into push_presence (user_id, conversation_id, seen_at) values (v_uid, p_conversation, now())
  on conflict (user_id) do update set conversation_id = excluded.conversation_id, seen_at = now();
end;
$$;
revoke all on function public.push_active(uuid) from public, anon;
grant execute on function public.push_active(uuid) to authenticated;

-- 5) push-send's calls (service role only) -------------------------------------
create or replace function public.push_hook_check(p_secret text)
returns boolean language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v text;
begin
  if p_secret is null or char_length(p_secret) < 32 or to_regclass('vault.decrypted_secrets') is null then return false; end if;
  execute 'select decrypted_secret from vault.decrypted_secrets where name = $1' into v using 'push_hook_secret';
  return v is not null and v = p_secret;
end;
$$;
revoke all on function public.push_hook_check(text) from public, anon, authenticated;
grant execute on function public.push_hook_check(text) to service_role;

-- Takes one queued notification (once) with the user's devices.
create or replace function public.push_outbox_take(p_id uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare o push_outbox;
begin
  update push_outbox set status = 'sending' where id = p_id and status = 'queued' returning * into o;
  if o.id is null then return null; end if;
  return jsonb_build_object(
    'id', o.id, 'kind', o.kind, 'title', o.title, 'body', o.body, 'url', o.url, 'tag', o.tag,
    'subscriptions', coalesce((select jsonb_agg(jsonb_build_object('endpoint', s.endpoint, 'p256dh', s.p256dh, 'auth', s.auth))
                               from push_subscriptions s where s.user_id = o.user_id), '[]'::jsonb));
end;
$$;
revoke all on function public.push_outbox_take(uuid) from public, anon, authenticated;
grant execute on function public.push_outbox_take(uuid) to service_role;

-- The result; devices the push service says are gone (404 / 410) are removed.
create or replace function public.push_outbox_done(p_id uuid, p_sent integer, p_failed integer, p_gone text[], p_error text default null)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  update push_outbox set
    status = case when coalesce(p_sent, 0) > 0 then 'sent'
                  when coalesce(p_failed, 0) = 0 then 'no_devices' else 'failed' end,
    sent = coalesce(p_sent, 0), failed = coalesce(p_failed, 0), error = left(p_error, 300), processed_at = now()
  where id = p_id;
  if p_gone is not null and array_length(p_gone, 1) > 0 then
    delete from push_subscriptions where endpoint = any (p_gone);
  end if;
end;
$$;
revoke all on function public.push_outbox_done(uuid, integer, integer, text[], text) from public, anon, authenticated;
grant execute on function public.push_outbox_done(uuid, integer, integer, text[], text) to service_role;

commit;

notify pgrst, 'reload schema';
