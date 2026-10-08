-- App-only role: no identity/catalog writes, no schema ownership or RLS bypass.
-- Login/password are provisioned separately, never committed in a migration.
-- Keep provisioning atomic even when the caller does not pass psql -1.
do $$
declare
 tbl text;
 unsafe_schemas text;
 role_existed boolean := exists(select 1 from pg_roles where rolname='tkm_runtime');
begin
 if not role_existed then
  create role tkm_runtime nologin nosuperuser nocreatedb nocreaterole noinherit noreplication nobypassrls connection limit 10;
 end if;
 -- Validate existing roles too, but never silently repair or reprovision them.
 if exists(select 1 from pg_roles where rolname='tkm_runtime'
           and (rolsuper or rolcreatedb or rolcreaterole or rolinherit or rolreplication or rolbypassrls)) then
  raise insufficient_privilege using message='tkm_runtime has unexpected privilege flags',
   hint='Management must inspect the role before provisioning runtime login.';
 end if;
 -- NOINHERIT does not prevent SET ROLE. Reject ALL outgoing memberships,
 -- not management roles that are members OF tkm_runtime.
 if exists(select 1 from pg_auth_members where member='tkm_runtime'::regrole) then
  raise insufficient_privilege using message='tkm_runtime has unexpected role memberships',
   hint='Management must inspect memberships before provisioning runtime login.';
 end if;
 -- NOCREATEDB does not prohibit CREATE SCHEMA; NOINHERIT does not exclude PUBLIC.
 if has_database_privilege('tkm_runtime',current_database(),'CREATE') is distinct from false then
  raise insufficient_privilege using message='tkm_runtime has effective CREATE on current database',
   hint='Management must resolve database ownership/ACLs, including PUBLIC, before provisioning runtime login.';
 end if;
 select string_agg(quote_ident(nspname),', ' order by nspname) into unsafe_schemas
 from pg_namespace
 where nspname !~ '^pg_' and nspname <> 'information_schema'
   and has_schema_privilege('tkm_runtime',oid,'CREATE') is distinct from false;
 if unsafe_schemas is not null then
  raise insufficient_privilege using message='tkm_runtime has effective CREATE on non-system schemas: '||unsafe_schemas,
   hint='Management must resolve schema ownership/ACLs, including PUBLIC, before provisioning runtime login.';
 end if;
 -- Shared PUBLIC ACLs are deliberately left unchanged, even on unsafe targets.
 if role_existed then
  raise exception 'tkm_runtime already exists; inspect role before applying this migration';
 end if;
grant tkm_runtime to current_user;
grant usage on schema public,tkm to tkm_runtime;
grant select on public.categories,public.products,public.product_variants,public.addons,public.product_addons,public.tables,public.settings to tkm_runtime;
grant select(id,role) on public.profiles to tkm_runtime;
grant select,insert,update,delete on public.orders,public.order_items to tkm_runtime;
grant select,insert on public.order_item_addons,public.order_status_history,public.payments to tkm_runtime;
grant select,insert,update,delete on tkm.checkout_keys to tkm_runtime;
grant select,insert,delete on tkm.outbox_events to tkm_runtime;
grant insert on tkm.order_reviews to tkm_runtime;
grant usage,select on sequence tkm.order_number_seq to tkm_runtime;
grant execute on function tkm.checkout(text,text,jsonb),tkm.review_order(uuid,uuid,integer,jsonb),tkm.confirm_cash(uuid,uuid,bigint,integer),tkm.complete_order(uuid,uuid),tkm.order_json(uuid),tkm.expire_one(uuid),tkm.expire_orders() to tkm_runtime;

 foreach tbl in array array['profiles','categories','products','product_variants','addons','product_addons','tables','settings'] loop
  execute format('create policy runtime_read on public.%I for select to tkm_runtime using (true)',tbl);
 end loop;
 foreach tbl in array array['orders','order_items','order_item_addons','order_status_history','payments'] loop
  -- Table/column GRANTs above determine which operations are actually allowed.
  execute format('create policy runtime_transactions on public.%I for all to tkm_runtime using (true) with check (true)',tbl);
 end loop;
 foreach tbl in array array['checkout_keys','outbox_events','order_reviews'] loop
  execute format('alter table tkm.%I enable row level security',tbl);
  execute format('create policy runtime_internal on tkm.%I for all to tkm_runtime using (true) with check (true)',tbl);
 end loop;
alter role tkm_runtime set search_path = '';
alter role tkm_runtime set statement_timeout = '10s';
alter role tkm_runtime set lock_timeout = '5s';
alter role tkm_runtime set idle_in_transaction_session_timeout = '15s';
end $$;
