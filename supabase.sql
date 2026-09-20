-- DRIFT public guestbook schema.
-- Run this once in the Supabase SQL Editor for the selected project.

create table if not exists public.drift_messages (
  id uuid primary key default gen_random_uuid(),
  content text not null check (
    char_length(btrim(content)) between 1 and 120
  ),
  created_at timestamptz not null default now(),
  is_visible boolean not null default false
);

alter table public.drift_messages enable row level security;

revoke all on table public.drift_messages from anon, authenticated;
grant select on table public.drift_messages to anon, authenticated;
grant insert (content) on table public.drift_messages to anon, authenticated;

drop policy if exists "Public can read visible drift messages" on public.drift_messages;
create policy "Public can read visible drift messages"
on public.drift_messages
for select
to anon, authenticated
using (is_visible = true);

drop policy if exists "Public can leave short drift messages" on public.drift_messages;
create policy "Public can leave short drift messages"
on public.drift_messages
for insert
to anon, authenticated
with check (
  is_visible = false
  and char_length(btrim(content)) between 1 and 120
);

create index if not exists drift_messages_visible_created_at_idx
on public.drift_messages (created_at desc)
where is_visible = true;
