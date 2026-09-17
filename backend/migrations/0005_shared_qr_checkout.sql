-- Apply after 0004_realtime_publication.sql. Shared QR checkout has no table identity.
-- Preserve historical table references and exact checkout_keys payload/access hashes.
-- CREATE OR REPLACE retains function grants; functions remain invoker with empty search_path.
alter table public.orders alter column table_id drop not null;

create or replace function tkm.order_json(oid uuid) returns jsonb language sql stable set search_path='' as $$
 select to_jsonb(o)||jsonb_build_object('expires_at',o.created_at+interval '15 minutes','tables',case when t.id is null then null else jsonb_build_object('number',t.number) end,'order_items',coalesce((select jsonb_agg(to_jsonb(i)||jsonb_build_object('order_item_addons',coalesce((select jsonb_agg(to_jsonb(a)) from public.order_item_addons a where a.order_item_id=i.id),'[]'::jsonb))) from public.order_items i where i.order_id=o.id),'[]'::jsonb))
 from public.orders o left join public.tables t on t.id=o.table_id where o.id=oid
$$;

-- Legacy table_token remains part of payload equality, but is never resolved or assigned.
create or replace function tkm.checkout(k text,access_token text,payload jsonb) returns jsonb language plpgsql set search_path='' as $$
declare existing tkm.checkout_keys; cfg public.settings; item jsonb; prod public.products; var public.product_variants; ad public.addons; oid uuid;iid uuid; qty int; unit bigint; extra bigint; v_subtotal bigint:=0; names text; count_variants int; choice uuid; groups text[];
begin
 if k is null or access_token is null or length(k)<16 or length(k)>128 or length(access_token)<24 or length(access_token)>256 then raise check_violation using message='Invalid checkout identity';end if;
 if payload->>'payment_method' is distinct from 'cash' then raise check_violation using message='Cash only';end if;
 if jsonb_typeof(payload->'items') is distinct from 'array' then raise check_violation using message='Invalid items';end if;
 if jsonb_array_length(payload->'items') not between 1 and 50 then raise check_violation using message='Invalid item count';end if;
 insert into tkm.checkout_keys(key,payload,access_hash) values(k,payload,encode(sha256(convert_to(access_token,'UTF8')),'hex')) on conflict do nothing;
 select * into existing from tkm.checkout_keys where key=k for update;
 if existing.payload<>payload or existing.access_hash<>encode(sha256(convert_to(access_token,'UTF8')),'hex') then raise check_violation using message='Idempotency conflict';end if;
 if existing.order_id is not null then return tkm.order_json(existing.order_id);end if;
 select * into strict cfg from public.settings where id=1;
 if cfg.require_customer_name and nullif(trim(payload->>'customer_name'),'') is null then raise check_violation using message='Customer name required';end if;
 insert into public.orders(table_id,customer_name) values(NULL,left(payload->>'customer_name',100)) returning id into oid;
 for item in select * from jsonb_array_elements(payload->'items') loop
  if jsonb_typeof(item->'quantity')<>'number' or (item->>'quantity') !~ '^[0-9]+$' then raise check_violation using message='Invalid quantity';end if;
  qty:=(item->>'quantity')::int;
  if qty not between 1 and 50 then raise check_violation using message='Invalid quantity';end if;
  select p.* into prod from public.products p join public.categories c on c.id=p.category_id where p.id=(item->>'product_id')::uuid and p.is_available and c.is_active;
  if not found then raise check_violation using message='Product unavailable';end if;
  unit:=prod.price;extra:=0;names:='';groups:=array[]::text[];
  if jsonb_typeof(item->'variant_ids') is distinct from 'array' or jsonb_typeof(item->'addon_ids') is distinct from 'array' then raise check_violation using message='Invalid choices';end if;
  if jsonb_array_length(item->'variant_ids')>20 or jsonb_array_length(item->'addon_ids')>20 then raise check_violation using message='Too many choices';end if;
  for choice in select value::uuid from jsonb_array_elements_text(item->'variant_ids') loop
   select * into var from public.product_variants where id=choice and product_id=prod.id and is_available;
   if not found or var.group_name=any(groups) then raise check_violation using message='Invalid variant';end if;
   groups:=array_append(groups,var.group_name);unit:=unit+var.price_modifier;names:=concat_ws(' · ',nullif(names,''),var.name);
  end loop;
  if exists(select 1 from public.product_variants where product_id=prod.id and is_available and not(group_name=any(groups))) then raise check_violation using message='Missing variant group';end if;
  if (select count(distinct value) from jsonb_array_elements_text(item->'addon_ids'))<>jsonb_array_length(item->'addon_ids') then raise check_violation using message='Duplicate addon';end if;
  insert into public.order_items(order_id,product_id,product_name,variant_name,quantity,unit_price,subtotal,notes,variant_ids,addon_ids) values(oid,prod.id,prod.name,nullif(names,''),qty,unit,0,left(item->>'notes',200),item->'variant_ids',item->'addon_ids') returning id into iid;
  for choice in select value::uuid from jsonb_array_elements_text(item->'addon_ids') loop
   select a.* into ad from public.addons a join public.product_addons pa on pa.addon_id=a.id where a.id=choice and pa.product_id=prod.id and a.is_available;
   if not found then raise check_violation using message='Invalid addon';end if;
   extra:=extra+ad.price;
   insert into public.order_item_addons(order_item_id,addon_id,addon_name,price) values(iid,ad.id,ad.name,ad.price);
  end loop;
  update public.order_items set addons_total=extra,subtotal=(unit+extra)*qty where id=iid;
  v_subtotal:=v_subtotal+(unit+extra)*qty;
 end loop;
 update public.orders set subtotal=v_subtotal,service_charge=round(v_subtotal*cfg.service_pct/100),tax=round(v_subtotal*cfg.tax_pct/100),total=v_subtotal+round(v_subtotal*cfg.service_pct/100)+round(v_subtotal*cfg.tax_pct/100) where id=oid;
 update tkm.checkout_keys set order_id=oid where key=k;
 insert into public.order_status_history(order_id,new_status) values(oid,'pending');
 insert into tkm.outbox_events(order_id,event_type,order_version) values(oid,'ORDER_CREATED',1);
 return tkm.order_json(oid);
end $$;
create or replace function tkm.review_order(oid uuid,actor uuid,expected_version int,items jsonb) returns jsonb language plpgsql set search_path='' as $$
declare o public.orders; before_data jsonb; staged jsonb; staged_id uuid; nonce text:=gen_random_uuid()::text;payload jsonb;
begin
 if not exists(select 1 from public.profiles where id=actor and role in ('admin','manager','cashier','owner')) then raise insufficient_privilege;end if;
 select * into o from public.orders where id=oid for update;
 if not found then raise no_data_found;end if;
 -- Return conflict as data, so expiry commits instead of rolling back on exception.
 if tkm.expire_one(oid) then return jsonb_build_object('error','expired');end if;
 if o.status<>'pending' or o.payment_status<>'unpaid' or expected_version is distinct from o.version then raise check_violation using message='Stale or non-pending order';end if;
 before_data:=tkm.order_json(oid);
 payload:=jsonb_build_object('customer_name',o.customer_name,'payment_method','cash','items',items);
 -- Reuse authoritative checkout validation/pricing inside this transaction.
 -- This staging order is never committed: move its priced rows, then remove it.
 staged:=tkm.checkout(nonce,nonce||nonce,payload);staged_id:=(staged->>'id')::uuid;
 if tkm.expire_one(oid) then
 delete from tkm.checkout_keys where order_id=staged_id;
 delete from tkm.outbox_events where order_id=staged_id;
 delete from public.orders where id=staged_id;
 return jsonb_build_object('error','expired');
 end if;
 delete from public.order_items where order_id=oid;
 update public.order_items set order_id=oid where order_id=staged_id;
 update public.orders set subtotal=(staged->>'subtotal')::bigint,tax=(staged->>'tax')::bigint,service_charge=(staged->>'service_charge')::bigint,total=(staged->>'total')::bigint,discount=0,version=version+1,reviewed_version=version+1,reviewed_by=actor,updated_at=clock_timestamp() where id=oid;
 delete from tkm.checkout_keys where order_id=staged_id;
 delete from tkm.outbox_events where order_id=staged_id;
 delete from public.orders where id=staged_id;
 insert into tkm.order_reviews(order_id,actor,before_order,after_order) values(oid,actor,before_data,tkm.order_json(oid));
 insert into tkm.outbox_events(order_id,event_type,order_version) values(oid,'ORDER_REVIEWED',o.version+1);
 return tkm.order_json(oid);
end $$;
