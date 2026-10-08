-- Run against a disposable copy at migration 0004, before applying 0005.
-- The migration and all fixtures roll back; no shared role attributes are changed.
\set ON_ERROR_STOP on
begin;
create temp table qr_function_security as
 select oid,proacl,prosecdef,proconfig from pg_proc where oid in
 ('tkm.checkout(text,text,jsonb)'::regprocedure,'tkm.order_json(uuid)'::regprocedure,'tkm.review_order(uuid,uuid,integer,jsonb)'::regprocedure);
create temp table qr_legacy(snapshot jsonb,payload jsonb,access_hash text);
insert into public.profiles(id,role) values('af600000-0000-0000-0000-000000000001','cashier');
insert into public.categories(id,name,slug) values('af600000-0000-0000-0000-000000000002','NO TABLE MIGRATION','no-table-migration');
insert into public.products(id,category_id,name,slug,price) values('af600000-0000-0000-0000-000000000003','af600000-0000-0000-0000-000000000002','NO TABLE MIGRATION','no-table-migration',10000);
insert into public.tables(id,number,qr_token) values('af600000-0000-0000-0000-000000000004',99990,'legacy-migration-qr');
do $$
declare p jsonb; o jsonb;
begin
 p:='{"table_token":"legacy-migration-qr","customer_name":"Guest","payment_method":"cash","items":[{"product_id":"af600000-0000-0000-0000-000000000003","quantity":1,"variant_ids":[],"addon_ids":[],"notes":""}]}'::jsonb;
 o:=tkm.checkout('legacy-migration-key','legacy-migration-order-capability',p);
 if o->>'table_id' is distinct from 'af600000-0000-0000-0000-000000000004' then raise exception 'not a real pre-migration table order';end if;
 insert into qr_legacy select o,p,access_hash from tkm.checkout_keys where key='legacy-migration-key';
end $$;
\ir ../migrations/0005_shared_qr_checkout.sql
do $$
begin
 if exists(select 1 from qr_function_security old join pg_proc p using(oid) where p.proacl is distinct from old.proacl or p.prosecdef or p.proconfig is distinct from old.proconfig) then raise exception 'function privileges/security changed';end if;
 if exists(select 1 from public.orders where id=(select (snapshot->>'id')::uuid from qr_legacy) and table_id is null) then raise exception 'historical table cleared';end if;
 if tkm.order_json((select (snapshot->>'id')::uuid from qr_legacy)) is distinct from (select snapshot from qr_legacy) then raise exception 'historical snapshot changed';end if;
end $$;
-- Catalog/name changes must not prevent exact existing-key recovery.
update public.tables set is_active=false where id='af600000-0000-0000-0000-000000000004';
update public.products set is_available=false where id='af600000-0000-0000-0000-000000000003';
update public.settings set require_customer_name=true where id=1;
grant select on qr_legacy to tkm_runtime;
set local role tkm_runtime;
do $$
declare old qr_legacy; o jsonb;
begin
 select * into old from qr_legacy;
 o:=tkm.checkout('legacy-migration-key','legacy-migration-order-capability',old.payload);
 if o is distinct from old.snapshot then raise exception 'legacy retry changed';end if;
 if (select payload from tkm.checkout_keys where key='legacy-migration-key') is distinct from old.payload or (select access_hash from tkm.checkout_keys where key='legacy-migration-key') is distinct from old.access_hash then raise exception 'stored identity rewritten';end if;
 begin perform tkm.checkout('legacy-migration-key','legacy-migration-order-capability',old.payload-'table_token');raise exception 'legacy payload normalization accepted';exception when check_violation then null;end;
 begin perform tkm.checkout('legacy-migration-key','legacy-migration-qr',old.payload);raise exception 'table QR used as capability';exception when check_violation then null;end;
end $$;
reset role;
update public.products set is_available=true where id='af600000-0000-0000-0000-000000000003';
set local role tkm_runtime;
do $$
declare old qr_legacy;o jsonb;n int;
begin
 select * into old from qr_legacy;
 select count(*) into n from public.orders;
 o:=tkm.review_order((old.snapshot->>'id')::uuid,'af600000-0000-0000-0000-000000000001',1,old.payload->'items');
 if o->'tables' is distinct from old.snapshot->'tables' or o->'table_id' is distinct from old.snapshot->'table_id' then raise exception 'review lost historical table';end if;
 if (select count(*) from public.orders)<>n then raise exception 'review staging leaked';end if;
 if (select payload from tkm.checkout_keys where key='legacy-migration-key') is distinct from old.payload then raise exception 'review rewrote original payload';end if;
 if tkm.checkout('legacy-migration-key','legacy-migration-order-capability',old.payload) is distinct from o then raise exception 'post-review recovery failed';end if;
 begin perform tkm.checkout('name-required-no-table-key','name-required-capability-token',old.payload-'customer_name'-'table_token');raise exception 'missing name accepted';exception when check_violation then
 if sqlerrm<>'Customer name required' then raise;end if;end;
 if exists(select 1 from tkm.checkout_keys where key='name-required-no-table-key') then raise exception 'rejected key leaked';end if;
 begin perform tkm.review_order((old.snapshot->>'id')::uuid,gen_random_uuid(),2,old.payload->'items');raise exception 'review auth bypass';exception when insufficient_privilege then null;end;
 raise notice 'PASS legacy pre-migration snapshot/read/retry/review, unchanged payload/hash/grants, name validation, auth, no staging leaks';
end $$;
reset role;
do $$
declare old qr_legacy;
begin
 select * into old from qr_legacy;
 if (select before_order from tkm.order_reviews where order_id=(old.snapshot->>'id')::uuid) is distinct from old.snapshot then raise exception 'review audit lost old snapshot';end if;
end $$;
rollback;
