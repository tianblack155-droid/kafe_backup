-- Cafe ordering system: full schema, RLS, RPC, realtime, storage, seed.
-- Idempotent-ish: safe to re-run in Supabase SQL editor.

create extension if not exists pgcrypto;

do $$ begin
  create type staff_role as enum ('admin','manager','kitchen','cashier');
exception when duplicate_object then null; end $$;

do $$ begin
  create type order_status as enum ('pending','preparing','ready','completed','cancelled');
exception when duplicate_object then null; end $$;

do $$ begin
  create type payment_status as enum ('unpaid','pending','paid','failed','refunded');
exception when duplicate_object then null; end $$;

create table if not exists profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  role staff_role not null default 'cashier',
  created_at timestamptz not null default now()
);

create table if not exists categories (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique,
  sort_order int not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists products (
  id uuid primary key default gen_random_uuid(),
  category_id uuid not null references categories(id),
  name text not null,
  slug text not null unique,
  description text,
  price int not null check (price >= 0),
  image_url text,
  is_available boolean not null default true,
  is_featured boolean not null default false,
  is_best_seller boolean not null default false,
  is_new boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists product_variants (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references products(id) on delete cascade,
  group_name text not null default 'Pilihan',
  name text not null,
  price_modifier int not null default 0 check (price_modifier >= 0),
  is_default boolean not null default false,
  is_available boolean not null default true,
  sort_order int not null default 0
);

create table if not exists addons (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  price int not null check (price >= 0),
  is_available boolean not null default true
);

create table if not exists product_addons (
  product_id uuid not null references products(id) on delete cascade,
  addon_id uuid not null references addons(id) on delete cascade,
  primary key (product_id, addon_id)
);

create table if not exists tables (
  id uuid primary key default gen_random_uuid(),
  number int not null unique,
  qr_token text not null unique default encode(gen_random_bytes(18), 'hex'),
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists settings (
  id int primary key default 1 check (id = 1),
  brand_name text not null default 'TerasKayuManis',
  tagline text default '',
  logo_url text,
  tax_pct numeric(5,2) not null default 0,
  service_pct numeric(5,2) not null default 0,
  require_customer_name boolean not null default false
);
insert into settings (id) values (1) on conflict (id) do nothing;

create sequence if not exists order_number_seq start 101;

create table if not exists orders (
  id uuid primary key default gen_random_uuid(),
  order_number text not null unique default ('A' || nextval('order_number_seq')),
  table_id uuid not null references tables(id),
  customer_name text,
  status order_status not null default 'pending',
  subtotal int not null check (subtotal >= 0),
  discount int not null default 0 check (discount >= 0),
  service_charge int not null default 0 check (service_charge >= 0),
  tax int not null default 0 check (tax >= 0),
  total int not null check (total >= 0),
  payment_status payment_status not null default 'unpaid',
  payment_method text not null check (payment_method in ('cash','qris')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references orders(id) on delete cascade,
  product_id uuid references products(id) on delete set null,
  product_name text not null,
  variant_name text,
  quantity int not null check (quantity > 0),
  unit_price int not null check (unit_price >= 0),
  addons_total int not null default 0,
  subtotal int not null check (subtotal >= 0),
  notes text
);

create table if not exists order_item_addons (
  id uuid primary key default gen_random_uuid(),
  order_item_id uuid not null references order_items(id) on delete cascade,
  addon_id uuid references addons(id) on delete set null,
  addon_name text not null,
  price int not null check (price >= 0)
);

create table if not exists order_status_history (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references orders(id) on delete cascade,
  old_status order_status,
  new_status order_status not null,
  changed_by uuid references profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

-- updated_at trigger
create or replace function touch_updated_at() returns trigger as $$
begin
  new.updated_at = now();
  return new;
end $$ language plpgsql;

drop trigger if exists orders_touch on orders;
create trigger orders_touch before update on orders for each row execute function touch_updated_at();
drop trigger if exists products_touch on products;
create trigger products_touch before update on products for each row execute function touch_updated_at();

-- RLS: everything locked down; authenticated staff get full access via is_staff().
-- Customers never touch the DB directly; they go through server routes (service role).
alter table profiles enable row level security;
alter table categories enable row level security;
alter table products enable row level security;
alter table product_variants enable row level security;
alter table addons enable row level security;
alter table product_addons enable row level security;
alter table tables enable row level security;
alter table settings enable row level security;
alter table orders enable row level security;
alter table order_items enable row level security;
alter table order_item_addons enable row level security;
alter table order_status_history enable row level security;

create or replace function is_staff() returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from profiles where id = auth.uid());
$$;

do $$
declare t text;
begin
  foreach t in array array['profiles','categories','products','product_variants','addons','product_addons','tables','settings','orders','order_items','order_item_addons','order_status_history'] loop
    execute format('drop policy if exists "staff_all" on %I', t);
    execute format('create policy "staff_all" on %I for all to authenticated using (is_staff()) with check (is_staff())', t);
  end loop;
end $$;

-- Realtime for kitchen (staff-only via RLS)
do $$ begin
  alter publication supabase_realtime add table orders;
exception when duplicate_object then null; end $$;

-- Storage bucket for product/brand images
insert into storage.buckets (id, name, public)
values ('media', 'media', true)
on conflict (id) do nothing;

drop policy if exists "media_public_read" on storage.objects;
create policy "media_public_read" on storage.objects for select using (bucket_id = 'media');
drop policy if exists "media_staff_write" on storage.objects;
create policy "media_staff_write" on storage.objects for all to authenticated
  using (bucket_id = 'media' and is_staff()) with check (bucket_id = 'media' and is_staff());

-- Server-side order creation: validates availability, snapshots prices, computes totals.
create or replace function create_order(payload jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_table tables%rowtype;
  v_settings settings%rowtype;
  v_order orders;
  v_item jsonb;
  v_product products%rowtype;
  v_variant_name text;
  v_mod int;
  v_count int;
  v_addon addons;
  v_qty int;
  v_unit int;
  v_addons_total int;
  v_items_subtotal int := 0;
  v_order_item order_items;
  v_service int;
  v_tax int;
begin
  select * into v_table from tables where qr_token = payload->>'table_token' and is_active;
  if not found then
    raise exception 'Meja tidak dikenali. Silakan scan ulang QR di meja Anda.';
  end if;

  select * into v_settings from settings where id = 1;

  if jsonb_array_length(coalesce(payload->'items', '[]'::jsonb)) = 0 then
    raise exception 'Keranjang masih kosong.';
  end if;

  if payload->>'payment_method' not in ('cash','qris') then
    raise exception 'Metode pembayaran tidak valid.';
  end if;

  if v_settings.require_customer_name and nullif(trim(payload->>'customer_name'), '') is null then
    raise exception 'Mohon isi nama Anda terlebih dahulu.';
  end if;

  insert into orders (order_number, table_id, customer_name, payment_method, subtotal, total)
  values ('A' || nextval('order_number_seq'), v_table.id,
          nullif(left(payload->>'customer_name', 100), ''), payload->>'payment_method', 0, 0)
  returning * into v_order;

  for v_item in select * from jsonb_array_elements(payload->'items') loop
    v_qty := coalesce((v_item->>'quantity')::int, 0);
    if v_qty is null or v_qty < 1 or v_qty > 50 then
      raise exception 'Jumlah pesanan tidak valid.';
    end if;

    select * into v_product from products where id = (v_item->>'product_id')::uuid;
    if not found or not v_product.is_available then
      raise exception '% tidak tersedia lagi. Silakan hapus dari keranjang.', coalesce(v_product.name, 'Menu ini');
    end if;

    v_unit := v_product.price;
    v_variant_name := null;
    if coalesce(jsonb_array_length(v_item->'variant_ids'), 0) > 0 then
      select coalesce(sum(x.price_modifier), 0), count(*), array_to_string(array_agg(x.name order by x.sort_order), ' · ')
      into v_mod, v_count, v_variant_name
      from (
        select name, price_modifier, sort_order from product_variants
        where product_id = v_product.id and is_available
          and id::text = any (select jsonb_array_elements_text(v_item->'variant_ids'))
      ) x;
      if v_count <> jsonb_array_length(v_item->'variant_ids') then
        raise exception 'Pilihan untuk % tidak tersedia lagi. Silakan pilih yang lain.', v_product.name;
      end if;
      v_unit := v_unit + v_mod;
    end if;

    insert into order_items (order_id, product_id, product_name, variant_name, quantity, unit_price, addons_total, subtotal, notes)
    values (v_order.id, v_product.id, v_product.name, v_variant_name, v_qty, v_unit, 0, 0,
            nullif(left(v_item->>'notes', 200), ''))
    returning * into v_order_item;

    v_addons_total := 0;
    for v_addon in
      select distinct a.* from addons a
      join product_addons pa on pa.addon_id = a.id and pa.product_id = v_product.id
      join jsonb_array_elements_text(coalesce(v_item->'addon_ids', '[]'::jsonb)) as x(aid)
        on x.aid = a.id::text
    loop
      if not v_addon.is_available then
        raise exception '% tidak tersedia lagi. Silakan hapus dari keranjang.', v_addon.name;
      end if;
      insert into order_item_addons (order_item_id, addon_id, addon_name, price)
      values (v_order_item.id, v_addon.id, v_addon.name, v_addon.price);
      v_addons_total := v_addons_total + v_addon.price;
    end loop;

    update order_items
      set addons_total = v_addons_total,
          subtotal = (v_unit + v_addons_total) * v_qty
      where id = v_order_item.id;

    v_items_subtotal := v_items_subtotal + (v_unit + v_addons_total) * v_qty;
  end loop;

  v_service := round(v_items_subtotal * v_settings.service_pct / 100)::int;
  v_tax := round(v_items_subtotal * v_settings.tax_pct / 100)::int;

  update orders
  set subtotal = v_items_subtotal,
      service_charge = v_service,
      tax = v_tax,
      total = v_items_subtotal + v_service + v_tax
  where id = v_order.id;

  return jsonb_build_object('id', v_order.id, 'order_number', v_order.order_number);
end $$;

revoke all on function create_order(jsonb) from public, anon, authenticated;

-- ============ SEED ============
insert into categories (name, slug, sort_order) values
  ('Kopi', 'kopi', 1),
  ('Non Kopi', 'non-kopi', 2),
  ('Makanan', 'makanan', 3),
  ('Snack', 'snack', 4),
  ('Dessert', 'dessert', 5)
on conflict (slug) do nothing;

insert into addons (name, price) values
  ('Extra Shot', 6000),
  ('Extra Cheese', 7000),
  ('Extra Chicken', 10000),
  ('Telur', 5000)
on conflict do nothing;

do $$
declare
  v_coffee uuid := (select id from categories where slug = 'kopi');
  v_noncoffee uuid := (select id from categories where slug = 'non-kopi');
  v_food uuid := (select id from categories where slug = 'makanan');
  v_snack uuid := (select id from categories where slug = 'snack');
  v_dessert uuid := (select id from categories where slug = 'dessert');
  v_p uuid;
  v_shot uuid := (select id from addons where name = 'Extra Shot');
  v_cheese uuid := (select id from addons where name = 'Extra Cheese');
begin
  if not exists (select 1 from products limit 1) then
    insert into products (category_id, name, slug, description, price, is_best_seller, is_new) values
      (v_coffee, 'Kopi Susu', 'kopi-susu', 'Espresso, susu segar, gula aren.', 22000, true, false)
    returning id into v_p;
    insert into product_variants (product_id, group_name, name, price_modifier, is_default, sort_order) values
      (v_p, 'Ukuran', 'Reguler', 0, true, 1), (v_p, 'Ukuran', 'Large', 5000, false, 2),
      (v_p, 'Gula', 'Normal', 0, true, 1), (v_p, 'Gula', 'Less Sugar', 0, false, 2), (v_p, 'Gula', 'No Sugar', 0, false, 3),
      (v_p, 'Es', 'Normal', 0, true, 1), (v_p, 'Es', 'Less Ice', 0, false, 2), (v_p, 'Es', 'No Ice', 0, false, 3);
    insert into product_addons values (v_p, v_shot);

    insert into products (category_id, name, slug, description, price, is_best_seller) values
      (v_coffee, 'Cafe Latte', 'cafe-latte', 'Espresso dengan steamed milk yang lembut.', 26000, true)
    returning id into v_p;
    insert into product_variants (product_id, group_name, name, price_modifier, is_default, sort_order) values
      (v_p, 'Ukuran', 'Reguler', 0, true, 1), (v_p, 'Ukuran', 'Large', 5000, false, 2);
    insert into product_addons values (v_p, v_shot);

    insert into products (category_id, name, slug, description, price) values
      (v_coffee, 'Americano', 'americano', 'Espresso dan air, bold dan sederhana.', 20000);

    insert into products (category_id, name, slug, description, price, is_new) values
      (v_noncoffee, 'Es Teh Lemon', 'es-teh-lemon', 'Teh hitam dingin dengan perasan lemon.', 15000, true);

    insert into products (category_id, name, slug, description, price) values
      (v_noncoffee, 'Cokelat Panas', 'cokelat-panas', 'Cokelat hangat yang creamy.', 24000);

    insert into products (category_id, name, slug, description, price, is_best_seller) values
      (v_food, 'Nasi Goreng Kampung', 'nasi-goreng-kampung', 'Nasi goreng dengan telur dan ayam.', 32000, true)
    returning id into v_p;
    insert into product_addons values (v_p, v_cheese);

    insert into products (category_id, name, slug, description, price) values
      (v_food, 'Spaghetti Carbonara', 'spaghetti-carbonara', 'Pasta creamy dengan smoke beef.', 38000);

    insert into products (category_id, name, slug, description, price) values
      (v_snack, 'Croissant Butter', 'croissant-butter', 'Croissant renyah dengan butter premium.', 18000);

    insert into products (category_id, name, slug, description, price) values
      (v_dessert, 'Cheesecake', 'cheesecake', 'Cheesecake lembut dengan saus buah.', 28000);
  end if;
end $$;

insert into tables (number) select n from generate_series(1, 6) as n
on conflict (number) do nothing;
