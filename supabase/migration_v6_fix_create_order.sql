-- ============================================================
-- Migration: fix "column reference item is ambiguous" bug (v6)
-- ------------------------------------------------------------
-- The create_order() function used a variable named "item" in two
-- different ways in the same function, which Postgres couldn't tell
-- apart — that's the exact error you saw when placing an order. This
-- replaces the function with a fixed version. Safe to run more than
-- once.
-- ============================================================

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

grant execute on function create_order to anon;
