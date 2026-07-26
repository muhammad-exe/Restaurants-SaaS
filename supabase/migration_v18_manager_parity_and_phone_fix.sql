-- Migration: manager/owner parity + drop phone requirement (v18)
--
-- Two independent fixes bundled together:
--   1. Managers now have the same dashboard access and capabilities as
--      owners, including being able to create or promote staff to the
--      "owner" role. (Removes the restriction added in v16.)
--   2. The customer-facing menu no longer asks for a phone number
--      (WhatsApp receipts were removed), so create_order() must no
--      longer REQUIRE one for QR orders — the v16 requirement would
--      otherwise break every QR order from here on.
--
-- Run this after v16 (which originally added both restrictions this
-- migration removes).

-- ---------- 1. create_order(): phone is optional again ----------
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

-- ---------- 2. add_staff / update_staff: manager can create/promote owners ----------

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
