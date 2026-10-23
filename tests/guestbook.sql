-- Disposable PostgreSQL only: psql "$TEST_DATABASE_URL" -v ON_ERROR_STOP=1 -f tests/guestbook.sql
create role anon;
create role authenticated;
\ir ../supabase.sql
-- Rerun migration without resetting enabled/history.
\ir ../supabase/migrations/202610230001_guestbook_guard.sql
begin;
create function pg_temp.expect_rejected(statement text, expected text)
returns void language plpgsql as $$
begin
  begin
    execute statement;
  exception when others then
    if sqlstate = expected then return; end if;
    raise;
  end;
  raise exception 'Expected SQLSTATE %: %', expected, statement;
end $$;
set local role anon;
-- Same SQL role and operation used by direct PostgREST API, no UI checks.
insert into public.drift_messages(content) values (' 正常留言 '), (E'换行\n留言');
select pg_temp.expect_rejected($q$insert into public.drift_messages(content) values ('正常 留言')$q$, 'PT429');
select pg_temp.expect_rejected($q$insert into public.drift_messages(content) values ('   ')$q$, 'PT400');
select pg_temp.expect_rejected($q$insert into public.drift_messages(content) values (repeat('字',121))$q$, 'PT400');
select pg_temp.expect_rejected($q$insert into public.drift_messages(content) values (U&'隐藏\200B字符')$q$, 'PT400');
select pg_temp.expect_rejected($q$update drift_private.guestbook_guard set enabled=false$q$, '42501');
select pg_temp.expect_rejected($q$insert into public.drift_messages(content,is_visible) values ('伪造',false)$q$, '42501');
select pg_temp.expect_rejected($q$insert into public.drift_messages(content) select '批量'||n from generate_series(1,9)n$q$, 'PT429');
-- The rejected bulk transaction must not consume any of the eight remaining slots.
insert into public.drift_messages(content) select '留言'||n from generate_series(1,8) n;
select pg_temp.expect_rejected($q$insert into public.drift_messages(content) values ('超出配额')$q$, 'PT429');
reset role;
-- Hiding/deleting spam must not replenish quota.
delete from public.drift_messages;
set local role authenticated;
select pg_temp.expect_rejected($q$insert into public.drift_messages(content) values ('换角色绕过')$q$, 'PT429');
reset role;
-- Hourly budget and expiry.
update drift_private.guestbook_guard set recent=(select jsonb_agg(jsonb_build_object('at',clock_timestamp()-interval '2 minutes','hash',md5(n::text))) from generate_series(1,100)n);
set local role anon;
select pg_temp.expect_rejected($q$insert into public.drift_messages(content) values ('小时超额')$q$, 'PT429');
reset role;
update drift_private.guestbook_guard set recent='[]',enabled=false;
set local role anon;
select pg_temp.expect_rejected($q$insert into public.drift_messages(content) values ('停写绕过')$q$, 'PT503');
reset role;
update drift_private.guestbook_guard set enabled=true,recent=jsonb_build_array(jsonb_build_object('at',clock_timestamp()-interval '61 minutes','hash',md5('过期')));
set local role anon;
insert into public.drift_messages(content) values ('过期');
reset role;
do $$ begin
 if not exists(select 1 from public.drift_messages where content='过期' and is_visible) then raise exception 'not immediately visible'; end if;
end $$;
rollback;
