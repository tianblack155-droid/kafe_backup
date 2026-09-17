-- TerasKayuManis cash-only schema. For a NEW empty public schema only.
-- Deliberately no customer/staff direct Data API write policies.
create schema if not exists tkm;
create table public.profiles(id uuid primary key,full_name text,role text not null check(role in ('admin','manager','cashier','owner')),created_at timestamptz not null default now());
create table public.categories(id uuid primary key default gen_random_uuid(),name text not null,slug text not null unique,sort_order int not null default 0,is_active boolean not null default true);
create table public.products(id uuid primary key default gen_random_uuid(),category_id uuid not null references public.categories(id),name text not null,slug text not null unique,description text,price bigint not null check(price>=0 and price<=100000000),image_url text,is_available boolean not null default true,is_featured boolean not null default false,is_best_seller boolean not null default false,is_new boolean not null default false,created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create table public.product_variants(id uuid primary key default gen_random_uuid(),product_id uuid not null references public.products(id) on delete cascade,group_name text not null default 'Pilihan',name text not null,price_modifier bigint not null default 0 check(price_modifier>=0 and price_modifier<=100000000),is_default boolean not null default false,is_available boolean not null default true,sort_order int not null default 0);
create table public.addons(id uuid primary key default gen_random_uuid(),name text not null,price bigint not null check(price>=0 and price<=100000000),is_available boolean not null default true);
create table public.product_addons(product_id uuid references public.products(id) on delete cascade,addon_id uuid references public.addons(id) on delete cascade,primary key(product_id,addon_id));
create table public.tables(id uuid primary key default gen_random_uuid(),number int not null unique,qr_token text not null unique default replace(gen_random_uuid()::text,'-',''),is_active boolean not null default true,created_at timestamptz not null default now());
create table public.settings(id int primary key check(id=1),brand_name text not null default 'TerasKayuManis',tagline text default '',logo_url text,tax_pct numeric(5,2) not null default 0 check(tax_pct between 0 and 100),service_pct numeric(5,2) not null default 0 check(service_pct between 0 and 100),require_customer_name boolean not null default false);
insert into public.settings(id) values(1);
create sequence tkm.order_number_seq start 101;
create table public.orders(id uuid primary key default gen_random_uuid(),order_number text not null unique default ('A'||nextval('tkm.order_number_seq')),table_id uuid not null references public.tables(id),customer_name text,status text not null default 'pending' check(status in ('pending','confirmed','completed','cancelled')),subtotal bigint not null default 0,discount bigint not null default 0,service_charge bigint not null default 0,tax bigint not null default 0,total bigint not null default 0 check(total>=0),payment_status text not null default 'unpaid' check(payment_status in ('unpaid','paid')),payment_method text not null default 'cash' check(payment_method='cash'),version int not null default 1,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),check(status not in ('confirmed','completed') or payment_status='paid'));
create table public.order_items(id uuid primary key default gen_random_uuid(),order_id uuid not null references public.orders(id) on delete cascade,product_id uuid references public.products(id),product_name text not null,variant_name text,quantity int not null check(quantity between 1 and 50),unit_price bigint not null,addons_total bigint not null default 0,subtotal bigint not null,notes text);
create table public.order_item_addons(id uuid primary key default gen_random_uuid(),order_item_id uuid not null references public.order_items(id) on delete cascade,addon_id uuid references public.addons(id),addon_name text not null,price bigint not null);
create table public.order_status_history(id uuid primary key default gen_random_uuid(),order_id uuid not null references public.orders(id) on delete cascade,old_status text,new_status text not null,changed_by uuid references public.profiles(id),created_at timestamptz not null default now());
create table public.payments(id uuid primary key default gen_random_uuid(),order_id uuid not null unique references public.orders(id),method text not null check(method='cash'),amount_rp bigint not null,received_rp bigint not null,change_rp bigint not null check(change_rp>=0),cashier_id uuid not null references public.profiles(id),created_at timestamptz not null default now());
create table tkm.checkout_keys(key text primary key,payload jsonb not null,access_hash text not null,order_id uuid references public.orders(id));
create table tkm.outbox_events(id uuid primary key default gen_random_uuid(),order_id uuid not null references public.orders(id),event_type text not null,order_version int not null,created_at timestamptz not null default now(),published_at timestamptz,unique(order_id,order_version));
create index orders_status_created on public.orders(status,created_at);
create index order_items_order on public.order_items(order_id);
create index outbox_pending on tkm.outbox_events(created_at) where published_at is null;
-- No anon/authenticated policies: server authority only. Explicit grants are added
-- to a restricted direct-DB runtime role during credential provisioning.
do $$declare t text;begin
 foreach t in array array['profiles','categories','products','product_variants','addons','product_addons','tables','settings','orders','order_items','order_item_addons','order_status_history','payments'] loop
 execute format('alter table public.%I enable row level security',t);
 end loop;
end $$;

create function tkm.order_json(oid uuid) returns jsonb language sql stable set search_path='' as $$
 select to_jsonb(o)||jsonb_build_object('tables',jsonb_build_object('number',t.number),'order_items',coalesce((select jsonb_agg(to_jsonb(i)||jsonb_build_object('order_item_addons',coalesce((select jsonb_agg(to_jsonb(a)) from public.order_item_addons a where a.order_item_id=i.id),'[]'::jsonb))) from public.order_items i where i.order_id=o.id),'[]'::jsonb))
 from public.orders o join public.tables t on t.id=o.table_id where o.id=oid
$$;

create function tkm.checkout(k text,access_token text,payload jsonb) returns jsonb language plpgsql set search_path='' as $$
declare existing tkm.checkout_keys; tab public.tables; cfg public.settings; item jsonb; prod public.products; var public.product_variants; ad public.addons; oid uuid;iid uuid; qty int; unit bigint; extra bigint; v_subtotal bigint:=0; names text; count_variants int; choice uuid; groups text[];
begin
 if k is null or access_token is null or length(k)<16 or length(k)>128 or length(access_token)<24 or length(access_token)>256 then raise check_violation using message='Invalid checkout identity';end if;
 if payload->>'payment_method' is distinct from 'cash' then raise check_violation using message='Cash only';end if;
 if jsonb_typeof(payload->'items') is distinct from 'array' then raise check_violation using message='Invalid items';end if;
 if jsonb_array_length(payload->'items') not between 1 and 50 then raise check_violation using message='Invalid item count';end if;
 insert into tkm.checkout_keys(key,payload,access_hash) values(k,payload,encode(sha256(convert_to(access_token,'UTF8')),'hex')) on conflict do nothing;
 select * into existing from tkm.checkout_keys where key=k for update;
 if existing.payload<>payload or existing.access_hash<>encode(sha256(convert_to(access_token,'UTF8')),'hex') then raise check_violation using message='Idempotency conflict';end if;
 if existing.order_id is not null then return tkm.order_json(existing.order_id);end if;
 select * into tab from public.tables where qr_token=payload->>'table_token' and is_active;
 if not found then raise check_violation using message='Invalid table';end if;
 select * into strict cfg from public.settings where id=1;
 if cfg.require_customer_name and nullif(trim(payload->>'customer_name'),'') is null then raise check_violation using message='Customer name required';end if;
 insert into public.orders(table_id,customer_name) values(tab.id,left(payload->>'customer_name',100)) returning id into oid;
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
  insert into public.order_items(order_id,product_id,product_name,variant_name,quantity,unit_price,subtotal,notes) values(oid,prod.id,prod.name,nullif(names,''),qty,unit,0,left(item->>'notes',200)) returning id into iid;
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

create function tkm.confirm_cash(oid uuid,actor uuid,received bigint) returns jsonb language plpgsql set search_path='' as $$
declare o public.orders;p public.payments;
begin
 if not exists(select 1 from public.profiles where id=actor and role in ('admin','manager','cashier','owner')) then raise insufficient_privilege using message='Staff required';end if;
 select * into o from public.orders where id=oid for update;
 if not found then raise no_data_found;end if;
 select * into p from public.payments where order_id=oid;
 if found then
  if p.received_rp<>received then raise check_violation using message='Payment retry conflict';end if;
  return tkm.order_json(oid)||jsonb_build_object('change_rp',p.change_rp);
 end if;
 if o.status<>'pending' or o.payment_status<>'unpaid' then raise check_violation using message='Order not payable';end if;
 if received is null or received<o.total or received>1000000000000 then raise check_violation using message='Insufficient or invalid cash';end if;
 insert into public.payments(order_id,method,amount_rp,received_rp,change_rp,cashier_id) values(oid,'cash',o.total,received,received-o.total,actor);
 update public.orders set status='confirmed',payment_status='paid',version=version+1,updated_at=now() where id=oid;
 insert into public.order_status_history(order_id,old_status,new_status,changed_by) values(oid,'pending','confirmed',actor);
 insert into tkm.outbox_events(order_id,event_type,order_version) values(oid,'ORDER_PAYMENT_CONFIRMED',o.version+1);
 return tkm.order_json(oid)||jsonb_build_object('change_rp',received-o.total);
end $$;

create function tkm.complete_order(oid uuid,actor uuid) returns jsonb language plpgsql set search_path='' as $$
declare o public.orders;
begin
 if not exists(select 1 from public.profiles where id=actor and role in ('admin','manager','cashier','owner')) then raise insufficient_privilege;end if;
 select * into o from public.orders where id=oid for update;
 if not found then raise no_data_found;end if;
 if o.status='completed' and o.payment_status='paid' then return tkm.order_json(oid);end if;
 if o.status<>'confirmed' or o.payment_status<>'paid' then raise check_violation using message='Paid confirmed order required';end if;
 update public.orders set status='completed',version=version+1,updated_at=now() where id=oid;
 insert into public.order_status_history(order_id,old_status,new_status,changed_by) values(oid,'confirmed','completed',actor);
 insert into tkm.outbox_events(order_id,event_type,order_version) values(oid,'ORDER_COMPLETED',o.version+1);
 return tkm.order_json(oid);
end $$;

revoke all on schema tkm from public;
revoke all on all functions in schema tkm from public;
