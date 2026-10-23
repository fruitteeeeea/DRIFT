-- DRIFT public guestbook schema.
-- Run this once in the Supabase SQL Editor for the selected project.

create table if not exists public.drift_messages (
  id uuid primary key default gen_random_uuid(),
  content text not null check (
    char_length(btrim(content)) between 1 and 120
  ),
  created_at timestamptz not null default now(),
  is_visible boolean not null default true
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
  is_visible = true
  and char_length(btrim(content)) between 1 and 120
);

create index if not exists drift_messages_visible_created_at_idx
on public.drift_messages (created_at desc)
where is_visible = true;

-- Apply as postgres in the Supabase SQL Editor. Transactional and rerunnable.
begin;
create schema if not exists drift_private;
revoke all on schema drift_private from public, anon, authenticated;
create table if not exists drift_private.guestbook_guard (
  singleton boolean primary key default true check (singleton),
  enabled boolean not null default true,
  recent jsonb not null default '[]'::jsonb
);
revoke all on drift_private.guestbook_guard from public, anon, authenticated;
insert into drift_private.guestbook_guard(singleton) values (true)
on conflict do nothing;

create or replace function drift_private.check_guestbook_insert()
returns trigger
language plpgsql volatile security definer
set search_path = pg_catalog
as $$
declare
  guard drift_private.guestbook_guard%rowtype;
  stamp timestamptz;
  history jsonb;
  fingerprint text;
  minute_count integer;
begin
  -- One locked row serializes the quota check AND reservation across requests,
  -- including bulk REST inserts. Failed transactions roll reservations back.
  select * into strict guard from drift_private.guestbook_guard
    where singleton = true for update;
  if not guard.enabled then
    raise sqlstate 'PT503' using message = 'guestbook_paused';
  end if;
  stamp := clock_timestamp();
  new.content := btrim(new.content);
  if new.content is null or char_length(new.content) not between 1 and 120
     or translate(new.content, E'\n\r\t', '') ~ '[[:cntrl:]]'
     or new.content ~ U&'[\200B\200E\200F\202A-\202E\2060-\206F\FEFF]'
     or new.content !~ '[^[:space:]]' then
    raise sqlstate 'PT400' using message = 'invalid_message';
  end if;
  fingerprint := md5(lower(regexp_replace(new.content, '[[:space:]]+', '', 'g')));
  select coalesce(jsonb_agg(item), '[]'::jsonb) into history
    from jsonb_array_elements(guard.recent) item
    where (item->>'at')::timestamptz > stamp - interval '1 hour';
  if exists (select 1 from jsonb_array_elements(history) item
    where item->>'hash' = fingerprint
      and (item->>'at')::timestamptz > stamp - interval '10 minutes') then
    raise sqlstate 'PT429' using message = 'duplicate_message';
  end if;
  select count(*) into minute_count from jsonb_array_elements(history) item
    where (item->>'at')::timestamptz > stamp - interval '1 minute';
  if minute_count >= 10 or jsonb_array_length(history) >= 100 then
    raise sqlstate 'PT429' using message = 'guestbook_rate_limited';
  end if;
  update drift_private.guestbook_guard set recent = history ||
    jsonb_build_array(jsonb_build_object('at', stamp, 'hash', fingerprint))
    where singleton = true;
  -- Clients cannot choose timestamps or visibility; accepted notes stay immediate.
  new.created_at := stamp;
  new.is_visible := true;
  return new;
end;
$$;
revoke all on function drift_private.check_guestbook_insert() from public, anon, authenticated;
drop trigger if exists drift_guestbook_guard on public.drift_messages;
create trigger drift_guestbook_guard before insert on public.drift_messages
for each row execute function drift_private.check_guestbook_insert();
-- Existing installations may still have the previous moderation default.
alter table public.drift_messages alter column is_visible set default true;
commit;
