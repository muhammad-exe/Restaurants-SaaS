-- ============================================================
-- Migration: WhatsApp manual order entry + accurate order_type (v16)
-- ------------------------------------------------------------
-- Two fixes, both needed for the new "WhatsApp" toggle on the POS
-- order panel:
--
-- 1. create_order() now actually SETS order_type. Before this it was
--    always left at its column default of 'dine-in' — even for
--    takeaway orders placed from a table-less QR scan or from the
--    POS with no table selected. Now it's 'takeaway' whenever there's
--    no table, 'dine-in' otherwise, unless the app explicitly passes
--    one in via the new p_order_type parameter.
--
-- 2. 'whatsapp' becomes a normal value for the source column, right
--    alongside 'pos' and 'qr'. No schema change needed — source was
--    always free text — this just documents that it's now expected
--    and updates the one function that inserts it.
--
-- Run this if you already ran schema.sql before this update. Safe to
-- run more than once.
-- ============================================================

-- Drop the old 7-argument version first — CREATE OR REPLACE does not
-- replace a function when the parameter list changes, it would just
-- add a second overload and leave the old one callable.
drop function if exists create_order(uuid, uuid, text, jsonb, text, uuid, boolean);

create or replace function create_order(
  p_restaurant_id uuid,
  p_table_id uuid,
  p_source text,
  p_items jsonb,          -- [{menu_item_id, name, price, qty}, ...]
  p_customer_phone text,
  p_staff_id uuid,
  p_marketing_opt_in boolean default true,
  p_order_type text default null   -- 'dine-in' | 'takeaway' | 'delivery'; auto-detected from p_table_id if omitted
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
  v_order_type text;
begin
  select tax_rate into v_tax_rate from restaurants where restaurants.id = p_restaurant_id;

  select sum((elem->>'price')::numeric * (elem->>'qty')::int)
    into v_subtotal
    from jsonb_array_elements(p_items) as elem;

  v_tax := round(v_subtotal * v_tax_rate);

  v_order_type := coalesce(p_order_type, case when p_table_id is null then 'takeaway' else 'dine-in' end);

  if p_customer_phone is not null and length(p_customer_phone) > 0 then
    insert into customers (restaurant_id, phone, marketing_opt_in)
    values (p_restaurant_id, p_customer_phone, p_marketing_opt_in)
    on conflict (restaurant_id, phone) do update set marketing_opt_in = p_marketing_opt_in
    returning customers.id into v_customer_id;
  end if;

  insert into orders (restaurant_id, table_id, order_type, source, status, subtotal, tax, total, customer_id, staff_id)
  values (p_restaurant_id, p_table_id, v_order_type, p_source, 'open', v_subtotal, v_tax, v_subtotal + v_tax, v_customer_id, p_staff_id)
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
grant execute on function create_order to anon;

-- One-time cleanup for rows already in your database: any past order
-- with no table was almost certainly a takeaway, not dine-in — fixes
-- the mislabeling described above for orders placed before this migration.
update orders set order_type = 'takeaway' where table_id is null and order_type = 'dine-in';
