-- ============================================================
-- Migration: order CRUD (edit/void) + waiting-page fix (v13)
-- ------------------------------------------------------------
-- Adds:
--   1. update_order_items() — lets any signed-in staff (cashier,
--      waiter, manager, owner) fix a mistake on an open order by
--      replacing its full item list, recalculating totals.
--   2. void_order() — cancels an order without deleting it (keeps the
--      record for the audit trail, status becomes 'void'). The app
--      restricts this to cashier/manager/owner, matching how
--      closing/payment is already restricted from waiters.
--   3. Fixes a real bug: the customer's "waiting page" only appeared
--      for orders placed via the QR menu — an order a staff member
--      entered on the POS for that table never showed the customer a
--      waiting page when they scanned the QR. Now any active order
--      for the table shows it, regardless of who created it.
--   4. get_open_orders() now also returns each item's real
--      menu_item_id (needed so editing an order can correctly match
--      items back to the live menu).
-- Run this if you already ran schema.sql before this update. Safe to
-- run more than once.
-- ============================================================

-- ---------- Fix: waiting page should show for any active order ----------
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
      and o.status in ('open', 'preparing', 'ready')
    order by o.created_at desc
    limit 1;
end;
$$;
grant execute on function get_active_order_for_table to anon;

-- ---------- get_open_orders now includes menu_item_id per line ----------
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
      (select jsonb_agg(jsonb_build_object('menu_item_id', oi.menu_item_id, 'name', oi.name_snapshot, 'qty', oi.qty, 'price', oi.price_snapshot)) from order_items oi where oi.order_id = o.id)
    from orders o
    left join restaurant_tables t on t.id = o.table_id
    where o.restaurant_id = p_restaurant_id
      and o.status in ('open', 'preparing', 'ready')
    order by o.created_at asc;
end;
$$;
grant execute on function get_open_orders to anon;

-- ---------- Edit an order's items ----------
create or replace function update_order_items(p_order_id uuid, p_items jsonb)
returns table (id uuid, subtotal numeric, tax numeric, total numeric, status text)
language plpgsql security definer as $$
declare
  v_restaurant_id uuid;
  v_tax_rate numeric;
  v_item jsonb;
  v_subtotal numeric;
  v_tax numeric;
begin
  select o.restaurant_id into v_restaurant_id
    from orders o where o.id = p_order_id and o.status in ('open', 'preparing', 'ready');

  if v_restaurant_id is null then
    raise exception 'This order is no longer open for editing';
  end if;

  select tax_rate into v_tax_rate from restaurants where restaurants.id = v_restaurant_id;

  delete from order_items where order_id = p_order_id;

  for v_item in select * from jsonb_array_elements(p_items) loop
    insert into order_items (order_id, menu_item_id, name_snapshot, price_snapshot, qty)
    values (
      p_order_id,
      (v_item->>'menu_item_id')::uuid,
      v_item->>'name',
      (v_item->>'price')::numeric,
      (v_item->>'qty')::int
    );
  end loop;

  select coalesce(sum(oi.price_snapshot * oi.qty), 0) into v_subtotal from order_items oi where oi.order_id = p_order_id;
  v_tax := round(v_subtotal * v_tax_rate);

  update orders
    set subtotal = v_subtotal, tax = v_tax, total = v_subtotal + v_tax
    where orders.id = p_order_id;

  return query select orders.id, orders.subtotal, orders.tax, orders.total, orders.status
    from orders where orders.id = p_order_id;
end;
$$;
grant execute on function update_order_items to anon;

-- ---------- Void an order ----------
create or replace function void_order(p_order_id uuid)
returns void
language plpgsql security definer as $$
begin
  update orders set status = 'void', closed_at = now() where id = p_order_id;
end;
$$;
grant execute on function void_order to anon;
