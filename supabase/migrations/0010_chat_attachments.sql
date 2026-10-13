-- =====================================================================
-- 0010 — chat attachments: photos, files and voice messages.
-- SAFE FORWARD MIGRATION: only ADDs nullable columns, one helper
-- function, a PRIVATE storage bucket and its policies. No data is
-- changed or deleted; every statement is idempotent.
--
-- Run once in Supabase → SQL Editor → New query → paste → Run
-- (after 0009).
-- =====================================================================

-- 1) Attachment info lives directly on the message row --------------
-- (The older message_attachments table from 0001 is left as is; its
-- RLS makes "insert then reference" awkward, so new code doesn't use it.)
alter table public.messages add column if not exists attachment_path text;   -- object path in bucket chat-files
alter table public.messages add column if not exists attachment_type text;   -- 'image' | 'file' | 'audio'
alter table public.messages add column if not exists attachment_name text;   -- original file name
alter table public.messages add column if not exists attachment_size bigint; -- bytes
alter table public.messages add column if not exists audio_duration_ms integer;

-- 2) Who may touch a conversation's files ---------------------------
-- Files are stored as "<conversation id>/<file>"; only that
-- conversation's two participants may read or upload them.
create or replace function public.is_conversation_participant(conv_id text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.conversations c
    where c.id::text = conv_id
      and (c.cargo_owner_id = auth.uid() or c.carrier_user_id = auth.uid())
  );
$$;

-- 3) PRIVATE bucket (files are served through short-lived signed
-- links, never public URLs). 20 MB per file.
insert into storage.buckets (id, name, public, file_size_limit)
values ('chat-files', 'chat-files', false, 20971520)
on conflict (id) do nothing;

drop policy if exists "chat_files_participants_read" on storage.objects;
create policy "chat_files_participants_read" on storage.objects
  for select to authenticated
  using (bucket_id = 'chat-files' and public.is_conversation_participant((storage.foldername(name))[1]));

drop policy if exists "chat_files_participants_upload" on storage.objects;
create policy "chat_files_participants_upload" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'chat-files' and public.is_conversation_participant((storage.foldername(name))[1]));
