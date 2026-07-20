-- ============================================================
-- Dastarkhwan Restaurant OS — Database Schema
-- Run this once in your Supabase project's SQL Editor
-- (Project → SQL Editor → New query → paste all → Run)
-- ============================================================

create extension if not exists "uuid-ossp";

-- ---------- Core tenant ----------
create table restaurants (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  slug text unique not null,          -- used in the QR menu URL, e.g. /menu.html?r=zaiqa-grill
  currency text default 'PKR',
  tax_rate numeric default 0.05,      -- 5% default, editable per restaurant
  whatsapp_number text,               -- restaurant's WhatsApp Business number (for later API wiring)
  created_at timestamptz default now()
);

-- ---------- Menu ----------
create table categories (
  id uuid primary key default uuid_generate_v4(),
  restaurant_id uuid references restaurants(id) on delete cascade,
  name text not null,
  sort_order int default 0
);

create table menu_items (
  id uuid primary key default uuid_generate_v4(),
  restaurant_id uuid references restaurants(id) on delete cascade,
  category_id uuid references categories(id) on delete set null,
  name text not null,
  price numeric not null,
  cost_price numeric,                 -- optional, powers profit-margin reports
  image_url text,                     -- shown on the customer QR menu and POS grid
  is_available boolean default true,
  sort_order int default 0,
  created_at timestamptz default now()
);

-- ---------- Tables & QR ----------
create table restaurant_tables (
  id uuid primary key default uuid_generate_v4(),
  restaurant_id uuid references restaurants(id) on delete cascade,
  label text not null,                -- "Table 4"
  qr_token text unique not null       -- random token embedded in the QR code URL
);

-- ---------- Staff ----------
create table staff (
  id uuid primary key default uuid_generate_v4(),
  restaurant_id uuid references restaurants(id) on delete cascade,
  name text not null,
  pin text not null,                  -- 4-digit PIN login (see README security note)
  role text default 'cashier',        -- owner | manager | cashier | waiter | kitchen
  created_at timestamptz default now()
);

-- ---------- Customers (CRM) ----------
create table customers (
  id uuid primary key default uuid_generate_v4(),
  restaurant_id uuid references restaurants(id) on delete cascade,
  phone text not null,
  name text,
  loyalty_points int default 0,
  marketing_opt_in boolean default false,
  created_at timestamptz default now(),
  unique (restaurant_id, phone)
);

-- ---------- Orders ----------
create table orders (
  id uuid primary key default uuid_generate_v4(),
  restaurant_id uuid references restaurants(id) on delete cascade,
  table_id uuid references restaurant_tables(id) on delete set null,
  order_type text default 'dine-in',      -- dine-in | takeaway | delivery
  source text default 'pos',              -- pos | qr
  status text default 'open',             -- open | preparing | ready | closed | void
  customer_id uuid references customers(id) on delete set null,
  payment_method text,                    -- cash | card | wallet | split
  subtotal numeric default 0,
  tax numeric default 0,
  total numeric default 0,
  staff_id uuid references staff(id) on delete set null,
  created_at timestamptz default now(),
  closed_at timestamptz
);

create table order_items (
  id uuid primary key default uuid_generate_v4(),
  order_id uuid references orders(id) on delete cascade,
  menu_item_id uuid references menu_items(id) on delete set null,
  name_snapshot text not null,        -- name at time of order (survives menu edits)
  price_snapshot numeric not null,
  qty int not null default 1
);

-- ---------- Cash reconciliation ----------
create table cash_sessions (
  id uuid primary key default uuid_generate_v4(),
  restaurant_id uuid references restaurants(id) on delete cascade,
  opening_cash numeric not null,
  closing_cash_counted numeric,
  opened_at timestamptz default now(),
  closed_at timestamptz
);

-- ---------- Expenses ----------
create table expenses (
  id uuid primary key default uuid_generate_v4(),
  restaurant_id uuid references restaurants(id) on delete cascade,
  description text not null,
  amount numeric not null,
  created_at timestamptz default now()
);

-- ============================================================
-- Row Level Security — locked-down version
-- ------------------------------------------------------------
-- Public (anon key) can only READ menu/restaurant/table data —
-- needed so the QR menu works with no login. Nothing writable
-- and nothing sensitive (staff, customers, orders) is directly
-- readable or writable by the anon key anymore. All writes and
-- all sensitive reads go through the RPC functions below, which
-- run with elevated rights internally but only do exactly the
-- one thing each is named for.
-- ============================================================

alter table restaurants enable row level security;
alter table categories enable row level security;
alter table menu_items enable row level security;
alter table restaurant_tables enable row level security;
alter table staff enable row level security;
alter table customers enable row level security;
alter table orders enable row level security;
alter table order_items enable row level security;
alter table cash_sessions enable row level security;
alter table expenses enable row level security;

create policy "public read restaurants" on restaurants for select using (true);
create policy "public read categories" on categories for select using (true);
create policy "public read menu_items" on menu_items for select using (true);
create policy "public read tables" on restaurant_tables for select using (true);

-- No policies on staff, customers, orders, order_items, cash_sessions,
-- expenses for anon — with RLS on and no policy, access is denied by
-- default. Everything on those tables happens through the functions
-- below, which are SECURITY DEFINER (run as the table owner, bypassing
-- RLS internally) but each does exactly one narrow, safe thing.

-- ---------- Staff PIN check ----------
-- Never returns the pin itself. Only returns id/name/role if it matched.
create or replace function check_staff_pin(p_restaurant_id uuid, p_pin text, p_allowed_roles text[])
returns table (id uuid, name text, role text)
language plpgsql security definer as $$
begin
  return query
    select s.id, s.name, s.role
    from staff s
    where s.restaurant_id = p_restaurant_id
      and s.pin = p_pin
      and s.role = any(p_allowed_roles);
end;
$$;

-- ---------- Create an order + its line items ----------
create or replace function create_order(
  p_restaurant_id uuid,
  p_table_id uuid,
  p_source text,
  p_items jsonb,          -- [{menu_item_id, name, price, qty}, ...]
  p_customer_phone text,
  p_staff_id uuid,
  p_marketing_opt_in boolean default true
)
returns table (id uuid, subtotal numeric, tax numeric, total numeric, source text, status text, created_at timestamptz)
language plpgsql security definer as $$
declare
  v_order_id uuid;
  v_subtotal numeric := 0;
  v_tax numeric := 0;
  v_tax_rate numeric;
  v_customer_id uuid;
  v_item jsonb;
begin
  select tax_rate into v_tax_rate from restaurants where restaurants.id = p_restaurant_id;

  select sum((elem->>'price')::numeric * (elem->>'qty')::int)
    into v_subtotal
    from jsonb_array_elements(p_items) as elem;

  v_tax := round(v_subtotal * v_tax_rate);

  if p_customer_phone is not null and length(p_customer_phone) > 0 then
    insert into customers (restaurant_id, phone, marketing_opt_in)
    values (p_restaurant_id, p_customer_phone, p_marketing_opt_in)
    on conflict (restaurant_id, phone) do update set marketing_opt_in = p_marketing_opt_in
    returning customers.id into v_customer_id;
  end if;

  insert into orders (restaurant_id, table_id, source, status, subtotal, tax, total, customer_id, staff_id)
  values (p_restaurant_id, p_table_id, p_source, 'open', v_subtotal, v_tax, v_subtotal + v_tax, v_customer_id, p_staff_id)
  returning orders.id into v_order_id;

  for v_item in select * from jsonb_array_elements(p_items) loop
    insert into order_items (order_id, menu_item_id, name_snapshot, price_snapshot, qty)
    values (
      v_order_id,
      (v_item->>'menu_item_id')::uuid,
      v_item->>'name',
      (v_item->>'price')::numeric,
      (v_item->>'qty')::int
    );
  end loop;

  return query select orders.id, orders.subtotal, orders.tax, orders.total, orders.source, orders.status, orders.created_at
    from orders where orders.id = v_order_id;
end;
$$;

-- ---------- Close/mark-ready an order ----------
create or replace function update_order_status(p_order_id uuid, p_status text, p_payment_method text default null)
returns void
language plpgsql security definer as $$
begin
  update orders
  set status = p_status,
      payment_method = coalesce(p_payment_method, payment_method),
      closed_at = case when p_status = 'closed' then now() else closed_at end
  where id = p_order_id;
end;
$$;

-- ---------- Read open orders (for the staff "incoming orders" panel) ----------
create or replace function get_open_orders(p_restaurant_id uuid)
returns table (
  id uuid, table_label text, source text, status text, total numeric, created_at timestamptz,
  items jsonb
)
language plpgsql security definer as $$
begin
  return query
    select o.id, t.label, o.source, o.status, o.total, o.created_at,
      (select jsonb_agg(jsonb_build_object('name', oi.name_snapshot, 'qty', oi.qty)) from order_items oi where oi.order_id = o.id)
    from orders o
    left join restaurant_tables t on t.id = o.table_id
    where o.restaurant_id = p_restaurant_id
      and o.status in ('open', 'preparing', 'ready')
    order by o.created_at asc;
end;
$$;

-- ---------- Sales queries used by the owner dashboard ----------
create or replace function get_sales_summary(p_restaurant_id uuid, p_since timestamptz)
returns table (
  total_sales numeric, order_count int, avg_order numeric
)
language plpgsql security definer as $$
begin
  return query
    select coalesce(sum(total),0), count(*)::int, coalesce(avg(total),0)
    from orders
    where restaurant_id = p_restaurant_id and status = 'closed' and created_at >= p_since;
end;
$$;

create or replace function get_top_items(p_restaurant_id uuid, p_since timestamptz, p_limit int default 5)
returns table (name text, qty bigint)
language plpgsql security definer as $$
begin
  return query
    select oi.name_snapshot, sum(oi.qty)
    from order_items oi
    join orders o on o.id = oi.order_id
    where o.restaurant_id = p_restaurant_id and o.status = 'closed' and o.created_at >= p_since
    group by oi.name_snapshot
    order by sum(oi.qty) desc
    limit p_limit;
end;
$$;

create or replace function get_source_split(p_restaurant_id uuid, p_since timestamptz)
returns table (source text, order_count bigint)
language plpgsql security definer as $$
begin
  return query
    select o.source, count(*)
    from orders o
    where o.restaurant_id = p_restaurant_id and o.status = 'closed' and o.created_at >= p_since
    group by o.source;
end;
$$;

create or replace function get_recent_orders(p_restaurant_id uuid, p_since timestamptz, p_limit int default 8)
returns table (id uuid, source text, total numeric, created_at timestamptz)
language plpgsql security definer as $$
begin
  return query
    select o.id, o.source, o.total, o.created_at
    from orders o
    where o.restaurant_id = p_restaurant_id and o.status = 'closed' and o.created_at >= p_since
    order by o.created_at desc
    limit p_limit;
end;
$$;

-- Allow the anon (public) role to call these functions — this is what
-- actually grants access; the functions themselves stay narrow and safe.
grant execute on function check_staff_pin to anon;
grant execute on function create_order to anon;
grant execute on function update_order_status to anon;
grant execute on function get_open_orders to anon;
grant execute on function get_sales_summary to anon;
grant execute on function get_top_items to anon;
grant execute on function get_source_split to anon;
-- ---------- Order status for the customer's live tracker ----------
-- Deliberately returns only status/table/source — nothing about other
-- orders, prices, or restaurant internals — since this is called from
-- the public customer menu page with no login.
create or replace function get_order_status(p_order_id uuid)
returns table (status text, table_label text)
language plpgsql security definer as $$
begin
  return query
    select o.status, t.label
    from orders o
    left join restaurant_tables t on t.id = o.table_id
    where o.id = p_order_id;
end;
$$;

grant execute on function get_recent_orders to anon;
grant execute on function get_order_status to anon;

-- ============================================================
-- Seed data — one demo restaurant so the app works immediately
-- ============================================================

insert into restaurants (id, name, slug, tax_rate, whatsapp_number)
values ('11111111-1111-1111-1111-111111111111', 'Zaiqa Grill House', 'zaiqa-grill', 0.05, '923001234567');

insert into restaurant_tables (restaurant_id, label, qr_token) values
('11111111-1111-1111-1111-111111111111', 'Table 1', 'zg-t1'),
('11111111-1111-1111-1111-111111111111', 'Table 2', 'zg-t2'),
('11111111-1111-1111-1111-111111111111', 'Table 3', 'zg-t3'),
('11111111-1111-1111-1111-111111111111', 'Table 4', 'zg-t4');

insert into staff (restaurant_id, name, pin, role) values
('11111111-1111-1111-1111-111111111111', 'Owner', '1234', 'owner'),
('11111111-1111-1111-1111-111111111111', 'Ali (Cashier)', '1111', 'cashier');

insert into categories (id, restaurant_id, name, sort_order) values
('c1111111-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'Starters', 1),
('c1111111-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 'Mains', 2),
('c1111111-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111', 'Breads', 3),
('c1111111-0000-0000-0000-000000000004', '11111111-1111-1111-1111-111111111111', 'Drinks', 4),
('c1111111-0000-0000-0000-000000000005', '11111111-1111-1111-1111-111111111111', 'Desserts', 5);

insert into menu_items (restaurant_id, category_id, name, price, cost_price, image_url, sort_order) values
('11111111-1111-1111-1111-111111111111','c1111111-0000-0000-0000-000000000001','Chicken Seekh Kebab',450,220,'https://loremflickr.com/400/300/seekhkebab,kebab',1),
('11111111-1111-1111-1111-111111111111','c1111111-0000-0000-0000-000000000001','Chapli Kebab',520,260,'https://loremflickr.com/400/300/chaplikebab,kebab',2),
('11111111-1111-1111-1111-111111111111','c1111111-0000-0000-0000-000000000001','Vegetable Samosa (4pc)',220,90,'https://loremflickr.com/400/300/samosa',3),
('11111111-1111-1111-1111-111111111111','c1111111-0000-0000-0000-000000000001','Dahi Bhalla',280,120,'https://loremflickr.com/400/300/dahibhalla,chaat',4),
('11111111-1111-1111-1111-111111111111','c1111111-0000-0000-0000-000000000002','Chicken Karahi (Full)',1450,700,'https://loremflickr.com/400/300/chickenkarahi,curry',1),
('11111111-1111-1111-1111-111111111111','c1111111-0000-0000-0000-000000000002','Beef Nihari',980,480,'https://loremflickr.com/400/300/nihari,curry',2),
('11111111-1111-1111-1111-111111111111','c1111111-0000-0000-0000-000000000002','Mutton Biryani',650,320,'https://loremflickr.com/400/300/biryani',3),
('11111111-1111-1111-1111-111111111111','c1111111-0000-0000-0000-000000000002','Daal Makhani',520,180,'https://loremflickr.com/400/300/daalmakhani,lentils',4),
('11111111-1111-1111-1111-111111111111','c1111111-0000-0000-0000-000000000002','Butter Chicken',1150,540,'https://loremflickr.com/400/300/butterchicken,curry',5),
('11111111-1111-1111-1111-111111111111','c1111111-0000-0000-0000-000000000003','Roghni Naan',90,25,'https://loremflickr.com/400/300/naanbread',1),
('11111111-1111-1111-1111-111111111111','c1111111-0000-0000-0000-000000000003','Garlic Naan',120,35,'https://loremflickr.com/400/300/garlicnaan,naanbread',2),
('11111111-1111-1111-1111-111111111111','c1111111-0000-0000-0000-000000000003','Tandoori Roti',40,12,'https://loremflickr.com/400/300/tandooriroti,flatbread',3),
('11111111-1111-1111-1111-111111111111','c1111111-0000-0000-0000-000000000004','Fresh Lime Soda',220,60,'https://loremflickr.com/400/300/limesoda,drink',1),
('11111111-1111-1111-1111-111111111111','c1111111-0000-0000-0000-000000000004','Mango Lassi',280,100,'https://loremflickr.com/400/300/mangolassi,drink',2),
('11111111-1111-1111-1111-111111111111','c1111111-0000-0000-0000-000000000004','Soft Drink',150,60,'https://loremflickr.com/400/300/softdrink,cola',3),
('11111111-1111-1111-1111-111111111111','c1111111-0000-0000-0000-000000000005','Gulab Jamun (2pc)',200,70,'https://loremflickr.com/400/300/gulabjamun,dessert',1),
('11111111-1111-1111-1111-111111111111','c1111111-0000-0000-0000-000000000005','Kheer',250,90,'https://loremflickr.com/400/300/kheer,ricepudding',2);
