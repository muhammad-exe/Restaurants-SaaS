-- ============================================================
-- Migration: kitchen/headwaiter workflow, WhatsApp-to-customer,
-- feedback, and manager/owner permission changes (v16)
-- ------------------------------------------------------------
-- Run this in your Supabase SQL Editor after v2–v15. Safe to run
-- more than once.
--
-- What this adds:
--   1. Staff roles become: owner, manager, cashier, headwaiter,
--      kitchen. Any existing "waiter" rows are renamed to
--      "headwaiter" automatically — nobody's login breaks.
--   2. create_order() now REQUIRES a phone number for orders placed
--      from the customer QR menu (source = 'qr') — this is what lets
--      the receipt reach the customer on WhatsApp. Orders a headwaiter
--      keys in on the POS (source = 'pos') still don't require one,
--      for walk-in customers without a phone.
--   3. get_open_orders() now also returns each order's customer_phone,
--      so staff screens can offer "send receipt on WhatsApp" without
--      a second lookup.
--   4. A new feedback table + submit_feedback()/get_order_feedback() —
--      one rating + comment per order, submitted from the customer's
--      waiting screen once their order is complete.
--   5. get_recent_orders() now also returns each order's feedback
--      rating/comment, so it shows up in order history on the
--      dashboard.
--   6. add_staff()/update_staff() accept the new role list and take
--      an optional p_caller_role — when the caller is a manager (not
--      owner), they can't create or promote anyone to 'owner'.
-- ============================================================

-- ---------- 1. Roles ----------
update staff set role = 'headwaiter' where role = 'waiter';

-- ---------- 2. create_order() requires a phone for QR orders ----------
-- Defensively drop every signature this function has ever had, in case
-- your database has a stray overload left over from schema drift —
-- otherwise "create or replace" only replaces an exact signature match
-- and a leftover overload makes the GRANT below ambiguous.
drop function if exists create_order(uuid, uuid, text, jsonb, text, uuid);
drop function if exists create_order(uuid, uuid, text, jsonb, text, uuid, boolean);
-- This one isn't defined anywhere in these migrations — it must have been
-- added directly in the Supabase SQL editor at some point (possibly an
-- earlier dine-in/takeaway experiment). No current frontend code sends
-- p_order_type, so a live database that still has this overload makes
-- every create_order call ambiguous to PostgREST ("could not choose the
-- best candidate function"), which is what breaks QR ordering entirely.
drop function if exists create_order(uuid, uuid, text, jsonb, text, uuid, boolean, text);
create or replace function create_order(
  p_restaurant_id uuid,
  p_table_id uuid,
  p_source text,
  p_items jsonb,
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
  if p_source = 'qr' and (p_customer_phone is null or length(trim(p_customer_phone)) = 0) then
    raise exception 'A phone number is required to place an order — this is how you receive your receipt on WhatsApp.';
  end if;

  select tax_rate into v_tax_rate from restaurants where restaurants.id = p_restaurant_id;

  select sum((elem->>'price')::numeric * (elem->>'qty')::int)
    into v_subtotal
    from jsonb_array_elements(p_items) as elem;

  v_tax := round(v_subtotal * v_tax_rate);

  if p_customer_phone is not null and length(trim(p_customer_phone)) > 0 then
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
grant execute on function create_order(uuid, uuid, text, jsonb, text, uuid, boolean) to anon;

-- ---------- 3. get_open_orders() now includes customer_phone ----------
drop function if exists get_open_orders(uuid);
create or replace function get_open_orders(p_restaurant_id uuid)
returns table (
  id uuid, table_label text, source text, status text,
  subtotal numeric, tax numeric, total numeric, created_at timestamptz,
  items jsonb, customer_phone text
)
language plpgsql security definer as $$
begin
  return query
    select o.id, t.label, o.source, o.status, o.subtotal, o.tax, o.total, o.created_at,
      (select jsonb_agg(jsonb_build_object('menu_item_id', oi.menu_item_id, 'name', oi.name_snapshot, 'qty', oi.qty, 'price', oi.price_snapshot)) from order_items oi where oi.order_id = o.id),
      c.phone
    from orders o
    left join restaurant_tables t on t.id = o.table_id
    left join customers c on c.id = o.customer_id
    where o.restaurant_id = p_restaurant_id
      and o.status in ('open', 'preparing', 'ready')
    order by o.created_at asc;
end;
$$;
grant execute on function get_open_orders(uuid) to anon;

-- ---------- 4. Feedback ----------
create table if not exists feedback (
  id uuid primary key default uuid_generate_v4(),
  order_id uuid references orders(id) on delete cascade,
  restaurant_id uuid references restaurants(id) on delete cascade,
  rating int not null check (rating between 1 and 5),
  comment text,
  created_at timestamptz default now(),
  unique (order_id)
);
alter table feedback enable row level security;
-- No direct anon policy — goes through submit_feedback()/get_order_feedback() only.

create or replace function submit_feedback(p_order_id uuid, p_rating int, p_comment text default null)
returns table (id uuid, rating int, comment text)
language plpgsql security definer as $$
declare
  v_restaurant_id uuid;
begin
  select restaurant_id into v_restaurant_id from orders where orders.id = p_order_id;
  if v_restaurant_id is null then
    raise exception 'Order not found';
  end if;
  if p_rating < 1 or p_rating > 5 then
    raise exception 'Rating must be between 1 and 5';
  end if;

  return query
    insert into feedback (order_id, restaurant_id, rating, comment)
    values (p_order_id, v_restaurant_id, p_rating, p_comment)
    on conflict (order_id) do update set rating = p_rating, comment = p_comment
    returning feedback.id, feedback.rating, feedback.comment;
end;
$$;
grant execute on function submit_feedback(uuid, int, text) to anon;

create or replace function get_order_feedback(p_order_id uuid)
returns table (rating int, comment text)
language plpgsql security definer as $$
begin
  return query select f.rating, f.comment from feedback f where f.order_id = p_order_id;
end;
$$;
grant execute on function get_order_feedback(uuid) to anon;

-- ---------- 5. get_recent_orders() now includes feedback ----------
drop function if exists get_recent_orders(uuid, timestamptz, int);
create or replace function get_recent_orders(p_restaurant_id uuid, p_since timestamptz, p_limit int default 8)
returns table (
  id uuid, source text, total numeric, created_at timestamptz,
  table_label text, items jsonb, rating int, comment text
)
language plpgsql security definer as $$
begin
  return query
    select o.id, o.source, o.total, o.created_at, t.label,
      (select jsonb_agg(jsonb_build_object('name', oi.name_snapshot, 'qty', oi.qty)) from order_items oi where oi.order_id = o.id),
      f.rating, f.comment
    from orders o
    left join restaurant_tables t on t.id = o.table_id
    left join feedback f on f.order_id = o.id
    where o.restaurant_id = p_restaurant_id and o.status = 'closed' and o.created_at >= p_since
    order by o.created_at desc
    limit p_limit;
end;
$$;
grant execute on function get_recent_orders(uuid, timestamptz, int) to anon;

-- ---------- 6. Roles: add_staff / update_staff ----------
drop function if exists add_staff(uuid, text, text, text);
create or replace function add_staff(p_restaurant_id uuid, p_name text, p_password text, p_role text, p_caller_role text default 'owner')
returns table (id uuid, name text, role text)
language plpgsql security definer as $$
declare
  v_existing boolean;
begin
  if length(p_password) < 6 then
    raise exception 'Password must be at least 6 characters';
  end if;
  if p_role not in ('owner', 'manager', 'cashier', 'headwaiter', 'kitchen') then
    raise exception 'Invalid role';
  end if;
  if p_caller_role = 'manager' and p_role = 'owner' then
    raise exception 'Managers cannot create an owner account';
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
grant execute on function add_staff(uuid, text, text, text, text) to anon;

drop function if exists update_staff(uuid, text, text, text);
create or replace function update_staff(p_staff_id uuid, p_name text, p_password text, p_role text, p_caller_role text default 'owner')
returns table (id uuid, name text, role text)
language plpgsql security definer as $$
declare
  v_existing boolean;
  v_restaurant_id uuid;
begin
  if length(p_password) < 6 then
    raise exception 'Password must be at least 6 characters';
  end if;
  if p_role not in ('owner', 'manager', 'cashier', 'headwaiter', 'kitchen') then
    raise exception 'Invalid role';
  end if;
  if p_caller_role = 'manager' and p_role = 'owner' then
    raise exception 'Managers cannot promote anyone to owner';
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
grant execute on function update_staff(uuid, text, text, text, text) to anon;
