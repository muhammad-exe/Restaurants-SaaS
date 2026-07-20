-- ============================================================
-- Migration: lock down security (v2)
-- ------------------------------------------------------------
-- Run this ONLY if you already ran the original schema.sql once
-- before (so your tables + demo data already exist). This does
-- NOT recreate any tables — it only replaces the old wide-open
-- access rules with the locked-down functions, and is safe to
-- run more than once.
-- ============================================================

-- Remove the old permissive "anyone can read/write anything" rules
drop policy if exists "anon full access categories" on categories;
drop policy if exists "anon full access menu_items" on menu_items;
drop policy if exists "anon full access tables" on restaurant_tables;
drop policy if exists "anon full access staff" on staff;
drop policy if exists "anon full access customers" on customers;
drop policy if exists "anon full access orders" on orders;
drop policy if exists "anon full access order_items" on order_items;
drop policy if exists "anon full access cash_sessions" on cash_sessions;
drop policy if exists "anon full access expenses" on expenses;
drop policy if exists "anon full access restaurants" on restaurants;
drop policy if exists "public read staff (name/role only in app)" on staff;
drop policy if exists "public read restaurants" on restaurants;
drop policy if exists "public read categories" on categories;
drop policy if exists "public read menu_items" on menu_items;
drop policy if exists "public read tables" on restaurant_tables;

-- Also safe to re-run: drop old versions of these functions in case
-- their signature changed (e.g. create_order gained a new parameter)
drop function if exists check_staff_pin(uuid, text, text[]);
drop function if exists create_order(uuid, uuid, text, jsonb, text, uuid);
drop function if exists create_order(uuid, uuid, text, jsonb, text, uuid, boolean);
drop function if exists update_order_status(uuid, text, text);
drop function if exists get_open_orders(uuid);
drop function if exists get_sales_summary(uuid, timestamptz);
drop function if exists get_top_items(uuid, timestamptz, int);
drop function if exists get_source_split(uuid, timestamptz);
drop function if exists get_recent_orders(uuid, timestamptz, int);

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
  item jsonb;
begin
  select tax_rate into v_tax_rate from restaurants where restaurants.id = p_restaurant_id;

  select sum((item->>'price')::numeric * (item->>'qty')::int)
    into v_subtotal
    from jsonb_array_elements(p_items) as item;

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

  for item in select * from jsonb_array_elements(p_items) loop
    insert into order_items (order_id, menu_item_id, name_snapshot, price_snapshot, qty)
    values (
      v_order_id,
      (item->>'menu_item_id')::uuid,
      item->>'name',
      (item->>'price')::numeric,
      (item->>'qty')::int
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
grant execute on function get_recent_orders to anon;
