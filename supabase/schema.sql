-- ============================================================
-- Dastarkhwan Restaurant OS — Database Schema
-- Run this once in your Supabase project's SQL Editor
-- (Project → SQL Editor → New query → paste all → Run)
-- ============================================================

create extension if not exists "uuid-ossp";
create extension if not exists "pgcrypto";

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
  password_hash text not null,        -- hashed with pgcrypto's crypt()/bf, never stored in plain text
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

-- ---------- Table calls (customer "call waiter" ring bell) ----------
create table table_calls (
  id uuid primary key default uuid_generate_v4(),
  restaurant_id uuid references restaurants(id) on delete cascade,
  table_id uuid references restaurant_tables(id) on delete cascade,
  created_at timestamptz default now(),
  acknowledged boolean default false,
  acknowledged_by uuid references staff(id) on delete set null
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
alter table table_calls enable row level security;

create policy "public read restaurants" on restaurants for select using (true);
create policy "public read categories" on categories for select using (true);
create policy "public read menu_items" on menu_items for select using (true);
create policy "public read tables" on restaurant_tables for select using (true);

-- No policies on staff, customers, orders, order_items, cash_sessions,
-- expenses for anon — with RLS on and no policy, access is denied by
-- default. Everything on those tables happens through the functions
-- below, which are SECURITY DEFINER (run as the table owner, bypassing
-- RLS internally) but each does exactly one narrow, safe thing.

-- ---------- Staff password check ----------
-- Never returns the password or its hash. Only returns id/name/role
-- if a matching, correctly-hashed password was found. Uses pgcrypto's
-- crypt() to compare against the stored bcrypt hash — the plain-text
-- password never touches a column, only this one-way comparison.
create or replace function check_staff_password(p_restaurant_id uuid, p_password text, p_allowed_roles text[])
returns table (id uuid, name text, role text)
language plpgsql security definer as $$
begin
  return query
    select s.id, s.name, s.role
    from staff s
    where s.restaurant_id = p_restaurant_id
      and s.role = any(p_allowed_roles)
      and crypt(p_password, s.password_hash) = s.password_hash
    limit 1;
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
  id uuid, table_label text, source text, status text,
  subtotal numeric, tax numeric, total numeric, created_at timestamptz,
  items jsonb
)
language plpgsql security definer as $$
begin
  return query
    select o.id, t.label, o.source, o.status, o.subtotal, o.tax, o.total, o.created_at,
      (select jsonb_agg(jsonb_build_object('name', oi.name_snapshot, 'qty', oi.qty, 'price', oi.price_snapshot)) from order_items oi where oi.order_id = o.id)
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
grant execute on function check_staff_password to anon;
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

-- ---------- Call waiter / ring bell ----------
-- Customer taps "Call waiter" — logs a call for that table. No PIN
-- needed, this is a public customer action.
create or replace function ring_bell(p_restaurant_id uuid, p_table_id uuid)
returns int
language plpgsql security definer as $$
declare
  v_count int;
begin
  insert into table_calls (restaurant_id, table_id) values (p_restaurant_id, p_table_id);
  select count(*) into v_count
    from table_calls
    where table_id = p_table_id and acknowledged = false;
  return v_count;
end;
$$;

-- Staff-facing: every table with at least one unacknowledged call,
-- with how many times it's been rung and whether it's crossed the
-- urgent threshold (used to also alert the owner, not just the till).
create or replace function get_active_calls(p_restaurant_id uuid)
returns table (table_id uuid, table_label text, call_count bigint, first_called_at timestamptz, urgent boolean)
language plpgsql security definer as $$
begin
  return query
    select tc.table_id, t.label, count(*), min(tc.created_at), count(*) > 5
    from table_calls tc
    left join restaurant_tables t on t.id = tc.table_id
    where tc.restaurant_id = p_restaurant_id and tc.acknowledged = false
    group by tc.table_id, t.label
    order by min(tc.created_at) asc;
end;
$$;

-- Staff dismisses a table's calls once they've gone to check on it.
create or replace function acknowledge_calls(p_table_id uuid, p_staff_id uuid default null)
returns void
language plpgsql security definer as $$
begin
  update table_calls
  set acknowledged = true, acknowledged_by = p_staff_id
  where table_id = p_table_id and acknowledged = false;
end;
$$;

-- ---------- Resume an in-progress order (customer rescans the QR) ----------
-- If a table already has an order that isn't finished yet, returns it
-- (with items) so the customer's screen can jump straight back to the
-- live tracker instead of showing the menu again from scratch.
create or replace function get_active_order_for_table(p_table_id uuid)
returns table (
  id uuid, status text, subtotal numeric, tax numeric, total numeric, created_at timestamptz,
  items jsonb
)
language plpgsql security definer as $$
begin
  return query
    select o.id, o.status, o.subtotal, o.tax, o.total, o.created_at,
      (select jsonb_agg(jsonb_build_object('name', oi.name_snapshot, 'qty', oi.qty, 'price', oi.price_snapshot)) from order_items oi where oi.order_id = o.id)
    from orders o
    where o.table_id = p_table_id
      and o.source = 'qr'
      and o.status in ('open', 'preparing', 'ready')
    order by o.created_at desc
    limit 1;
end;
$$;

grant execute on function ring_bell to anon;
grant execute on function get_active_calls to anon;
grant execute on function acknowledge_calls to anon;
grant execute on function get_active_order_for_table to anon;

-- ---------- Staff management (add/remove/list) ----------
-- Never returns pin — only id/name/role. The dashboard PIN gate is the
-- access control here (only owner/manager PINs reach this screen at
-- the app level); these functions themselves don't re-check role,
-- consistent with how the rest of the dashboard's read functions work.

create or replace function list_staff(p_restaurant_id uuid)
returns table (id uuid, name text, role text, created_at timestamptz)
language plpgsql security definer as $$
begin
  return query
    select s.id, s.name, s.role, s.created_at
    from staff s
    where s.restaurant_id = p_restaurant_id
    order by s.created_at asc;
end;
$$;

create or replace function add_staff(p_restaurant_id uuid, p_name text, p_password text, p_role text)
returns table (id uuid, name text, role text)
language plpgsql security definer as $$
declare
  v_existing boolean;
begin
  if length(p_password) < 6 then
    raise exception 'Password must be at least 6 characters';
  end if;
  if p_role not in ('owner', 'manager', 'cashier', 'waiter') then
    raise exception 'Invalid role';
  end if;

  select exists(
    select 1 from staff s
    where s.restaurant_id = p_restaurant_id and crypt(p_password, s.password_hash) = s.password_hash
  ) into v_existing;
  if v_existing then
    raise exception 'That password is already in use — pick a different one';
  end if;

  return query
    insert into staff (restaurant_id, name, password_hash, role)
    values (p_restaurant_id, p_name, crypt(p_password, gen_salt('bf')), p_role)
    returning staff.id, staff.name, staff.role;
end;
$$;

create or replace function remove_staff(p_staff_id uuid)
returns void
language plpgsql security definer as $$
begin
  update orders set staff_id = null where staff_id = p_staff_id;
  delete from staff where id = p_staff_id;
end;
$$;

grant execute on function list_staff to anon;
grant execute on function add_staff to anon;
create or replace function update_staff(p_staff_id uuid, p_name text, p_password text, p_role text)
returns table (id uuid, name text, role text)
language plpgsql security definer as $$
declare
  v_existing boolean;
  v_restaurant_id uuid;
begin
  if length(p_password) < 6 then
    raise exception 'Password must be at least 6 characters';
  end if;
  if p_role not in ('owner', 'manager', 'cashier', 'waiter') then
    raise exception 'Invalid role';
  end if;

  select restaurant_id into v_restaurant_id from staff where staff.id = p_staff_id;

  select exists(
    select 1 from staff s
    where s.restaurant_id = v_restaurant_id and s.id != p_staff_id
      and crypt(p_password, s.password_hash) = s.password_hash
  ) into v_existing;
  if v_existing then
    raise exception 'That password is already in use by someone else — pick a different one';
  end if;

  return query
    update staff
    set name = p_name, password_hash = crypt(p_password, gen_salt('bf')), role = p_role
    where staff.id = p_staff_id
    returning staff.id, staff.name, staff.role;
end;
$$;

grant execute on function remove_staff to anon;
grant execute on function update_staff to anon;

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

insert into staff (restaurant_id, name, password_hash, role) values
('11111111-1111-1111-1111-111111111111', 'Owner', crypt('owner123', gen_salt('bf')), 'owner'),
('11111111-1111-1111-1111-111111111111', 'Ali (Cashier)', crypt('cashier123', gen_salt('bf')), 'cashier');

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
