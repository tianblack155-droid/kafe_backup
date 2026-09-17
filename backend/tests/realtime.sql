-- Disposable DB only, after migrations 1-4. All fixtures and changes roll back.
\set ON_ERROR_STOP on
begin;
do $$
declare col record;
begin
 if has_table_privilege('tkm_runtime','tkm.outbox_events','UPDATE') then raise exception 'broad outbox UPDATE';end if;
 for col in select attname from pg_attribute where attrelid='tkm.outbox_events'::regclass and attnum>0 and not attisdropped loop
  if has_column_privilege('tkm_runtime','tkm.outbox_events',col.attname,'UPDATE') is distinct from (col.attname='published_at') then raise exception 'unexpected UPDATE privilege: %',col.attname;end if;
 end loop;
end $$;
insert into public.tables(id,number,qr_token) values('ce231891-2242-4fb3-91a2-030b53000001',99989,'ws-grant-test');
insert into public.orders(id,table_id) values('ce231891-2242-4fb3-91a2-030b53000002','ce231891-2242-4fb3-91a2-030b53000001');
insert into tkm.outbox_events(order_id,event_type,order_version) values('ce231891-2242-4fb3-91a2-030b53000002','ORDER_CREATED',1);
set local role tkm_runtime;
do $$
declare eid uuid;
begin
 select id into strict eid from tkm.outbox_events where order_id='ce231891-2242-4fb3-91a2-030b53000002' and published_at is null for update skip locked;
 update tkm.outbox_events set published_at=clock_timestamp() where id=eid;
 if not exists(select 1 from tkm.outbox_events where id=eid and published_at is not null) then raise exception 'marker not written';end if;
 begin update tkm.outbox_events set event_type='CORRUPTED' where id=eid;raise exception 'event update allowed';exception when insufficient_privilege then null;end;
 begin update tkm.outbox_events set order_version=100 where id=eid;raise exception 'version update allowed';exception when insufficient_privilege then null;end;
 begin update public.profiles set role='owner';raise exception 'profile update allowed';exception when insufficient_privilege then null;end;
 begin update public.products set price=0;raise exception 'catalog update allowed';exception when insufficient_privilege then null;end;
end $$;
select 'realtime_narrow_publication_grant' as test_suite,true as passed;
rollback;
