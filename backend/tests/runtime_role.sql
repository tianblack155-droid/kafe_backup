-- LOCAL/DISPOSABLE DATABASE ONLY: run as a management superuser after 0001/0002/0003.
-- From backend: psql -X -v ON_ERROR_STOP=1 -d <disposable_db> -f tests/runtime_role.sql
-- Regression cases re-run the actual migration under savepoints, including with
-- temporary PUBLIC CREATE grants and shared-role changes. Everything rolls back;
-- no DROP ROLE, shared ACL repair, or persistent role changes are performed.
-- Expected migration ERROR lines are asserted via SQLSTATE; success requires both
-- test_suite rows to report true and psql to exit 0. Do not run with psql -1:
-- this file manages its own transaction and savepoints.
\set ON_ERROR_STOP on
begin;
do $$
declare tbl text; privilege text; col record;
begin
 if not exists(select 1 from pg_roles where rolname='tkm_runtime' and not rolsuper and not rolcreatedb and not rolcreaterole and not rolinherit and not rolreplication and not rolbypassrls) then raise exception 'Restricted runtime role missing';end if;
 -- Outgoing memberships are forbidden even with NOINHERIT (SET ROLE can use them).
 -- Management being a member OF runtime is intentionally allowed.
 if exists(select 1 from pg_auth_members where member='tkm_runtime'::regrole) then raise exception 'Unexpected runtime role membership';end if;
 foreach tbl in array array['profiles','categories','products','product_variants','addons','product_addons','tables','settings'] loop
  foreach privilege in array array['INSERT','UPDATE','DELETE','TRUNCATE'] loop
   if has_table_privilege('tkm_runtime','public.'||tbl,privilege) is distinct from false then raise exception 'Runtime has % on %',privilege,tbl;end if;
  end loop;
  foreach privilege in array array['INSERT','UPDATE'] loop
   if has_any_column_privilege('tkm_runtime','public.'||tbl,privilege) is distinct from false then raise exception 'Runtime has column % on %',privilege,tbl;end if;
  end loop;
 end loop;
 for col in select attname from pg_attribute where attrelid='public.profiles'::regclass and attnum>0 and not attisdropped loop
  if has_column_privilege('tkm_runtime','public.profiles',col.attname,'SELECT') is distinct from (col.attname in ('id','role')) then raise exception 'Unexpected profile column access: %',col.attname;end if;
 end loop;
 if has_database_privilege('tkm_runtime',current_database(),'CREATE') is distinct from false then raise exception 'Runtime can create schemas';end if;
 if exists(select 1 from pg_namespace where nspname !~ '^pg_' and nspname <> 'information_schema' and has_schema_privilege('tkm_runtime',oid,'CREATE') is distinct from false) then raise exception 'Runtime can create objects';end if;
end $$;
-- Create fixture as management role, never grant those writes to runtime.
insert into public.categories(id,name,slug) values('c22de505-7299-4ca3-a359-6e8a01960001','RUNTIME TEST','runtime-test');
insert into public.products(id,category_id,name,slug,price) values('c22de505-7299-4ca3-a359-6e8a01960002','c22de505-7299-4ca3-a359-6e8a01960001','RUNTIME TEST','runtime-test',18000);
insert into public.tables(id,number,qr_token) values('c22de505-7299-4ca3-a359-6e8a01960003',99994,'runtime-test-table');
insert into public.profiles(id,role) values('c22de505-7299-4ca3-a359-6e8a01960004','cashier');
set local role tkm_runtime;
do $$
declare payload jsonb; o jsonb; oid uuid; ddl text;
begin
 payload:=jsonb_build_object('table_token','runtime-test-table','payment_method','cash','items',jsonb_build_array(jsonb_build_object('product_id','c22de505-7299-4ca3-a359-6e8a01960002','quantity',1,'variant_ids','[]'::jsonb,'addon_ids','[]'::jsonb)));
 o:=tkm.checkout('runtime-checkout-test-key','runtime-test-access-token-unique',payload);oid:=(o->>'id')::uuid;
 if oid is null then raise exception 'runtime checkout order ID missing';end if;
 if (o->>'total')::int is distinct from 18000 then raise exception 'runtime checkout total';end if;
 o:=tkm.review_order(oid,'c22de505-7299-4ca3-a359-6e8a01960004',1,payload->'items');
 o:=tkm.confirm_cash(oid,'c22de505-7299-4ca3-a359-6e8a01960004',20000,2);
 o:=tkm.complete_order(oid,'c22de505-7299-4ca3-a359-6e8a01960004');
 if o->>'status' is distinct from 'completed' then raise exception 'runtime completion';end if;
 perform tkm.expire_orders();
 begin update public.profiles set role='owner' where id='c22de505-7299-4ca3-a359-6e8a01960004';raise exception 'role escalation accepted';exception when insufficient_privilege then null;end;
 begin update public.products set price=0;raise exception 'catalog write accepted';exception when insufficient_privilege then null;end;
 begin perform full_name from public.profiles;raise exception 'private profile read accepted';exception when insufficient_privilege then null;end;
 foreach ddl in array array[
  'create schema runtime_forbidden_schema',
  'create table public.runtime_forbidden_table(id int)',
  'create table tkm.runtime_forbidden_table(id int)',
  'alter table public.products add column runtime_forbidden_column int',
  'drop table public.settings',
  'truncate public.settings'
 ] loop
  begin execute ddl;raise exception 'Forbidden DDL accepted: %',ddl;exception when insufficient_privilege then null;end;
 end loop;
end $$;
reset role;
select 'runtime_role_permissions_and_lifecycle' as test_suite,true as passed;

-- Check the real migration, not a duplicate of its guard. An existing safe role
-- must get the ordinary already-exists error (P0001), but an unsafe role must get
-- insufficient_privilege (42501) BEFORE that error. Unexpected errors fail too.
-- Keep each migration atomic: later statements must not mask its guard SQLSTATE.
create function pg_temp.expect_runtime_guard(state text, scenario text, expected text default '42501') returns void language plpgsql as $$
begin
 if state is distinct from expected then raise exception '%: expected SQLSTATE %, got %',scenario,expected,state;end if;
 raise notice 'PASS: %',scenario;
end $$;

savepoint runtime_guard;
\set ON_ERROR_STOP off
\ir ../migrations/0003_runtime_role.sql
\set guard_state :SQLSTATE
\set ON_ERROR_STOP on
rollback to savepoint runtime_guard;
select pg_temp.expect_runtime_guard(:'guard_state','safe existing role is not reprovisioned','P0001');

savepoint runtime_guard;
do $$begin execute format('grant create on database %I to public',current_database());end $$;
\set ON_ERROR_STOP off
\ir ../migrations/0003_runtime_role.sql
\set guard_state :SQLSTATE
\set ON_ERROR_STOP on
rollback to savepoint runtime_guard;
select pg_temp.expect_runtime_guard(:'guard_state','reject PUBLIC database CREATE');

savepoint runtime_guard;
grant create on schema public to public;
\set ON_ERROR_STOP off
\ir ../migrations/0003_runtime_role.sql
\set guard_state :SQLSTATE
\set ON_ERROR_STOP on
rollback to savepoint runtime_guard;
select pg_temp.expect_runtime_guard(:'guard_state','reject PUBLIC public-schema CREATE');

savepoint runtime_guard;
grant create on schema tkm to public;
\set ON_ERROR_STOP off
\ir ../migrations/0003_runtime_role.sql
\set guard_state :SQLSTATE
\set ON_ERROR_STOP on
rollback to savepoint runtime_guard;
select pg_temp.expect_runtime_guard(:'guard_state','reject PUBLIC tkm-schema CREATE');

savepoint runtime_guard;
create schema runtime_ambient_create;
grant create on schema runtime_ambient_create to public;
\set ON_ERROR_STOP off
\ir ../migrations/0003_runtime_role.sql
\set guard_state :SQLSTATE
\set ON_ERROR_STOP on
rollback to savepoint runtime_guard;
select pg_temp.expect_runtime_guard(:'guard_state','reject PUBLIC CREATE on unrelated schema');

savepoint runtime_guard;
grant pg_read_all_data to tkm_runtime;
\set ON_ERROR_STOP off
\ir ../migrations/0003_runtime_role.sql
\set guard_state :SQLSTATE
\set ON_ERROR_STOP on
rollback to savepoint runtime_guard;
select pg_temp.expect_runtime_guard(:'guard_state','reject outgoing membership despite NOINHERIT');

savepoint runtime_guard;
alter role tkm_runtime replication;
\set ON_ERROR_STOP off
\ir ../migrations/0003_runtime_role.sql
\set guard_state :SQLSTATE
\set ON_ERROR_STOP on
rollback to savepoint runtime_guard;
select pg_temp.expect_runtime_guard(:'guard_state','reject privileged role flag');

select 'runtime_role_fail_closed_migration' as test_suite,true as passed;
rollback;
