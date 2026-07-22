-- ============================================================
-- Migration: item availability toggle + add-on orders (v12)
-- ------------------------------------------------------------
-- Adds:
--   1. set_item_availability() — lets staff (owner/manager/cashier/
--      waiter, i.e. anyone signed into the POS) mark a dish out of
--      stock or back in stock. loadMenu() already filters on
--      is_available, so this instantly disappears from the customer
--      QR menu.
--   2. add_items_to_order() — lets a customer add more items to their
--      already-placed order instead of starting a new one when they
--      rescan the table QR mid-meal.
--
-- (The waiting-room game is handled separately — see
-- migration_v13_game.sql — and doesn't need a database table at all,
-- since it uses Supabase Realtime broadcast/presence instead.)
-- Run this if you already ran schema.sql before this update. Safe to
-- run more than once.
-- ============================================================

-- ---------- Menu item availability (86'ing a dish) ----------
create or replace function set_item_availability(p_item_id uuid, p_is_available boolean)
returns table (id uuid, is_available boolean)
language plpgsql security definer as $$
begin
  return query
    update menu_items
    set is_available = p_is_available
    where menu_items.id = p_item_id
    returning menu_items.id, menu_items.is_available;
end;
$$;
grant execute on function set_item_availability to anon;

-- ---------- Add items to an already-placed order ----------
create or replace function add_items_to_order(p_order_id uuid, p_items jsonb)
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
    raise exception 'This order is no longer open for additions';
  end if;

  select tax_rate into v_tax_rate from restaurants where restaurants.id = v_restaurant_id;

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

  select sum(oi.price_snapshot * oi.qty) into v_subtotal from order_items oi where oi.order_id = p_order_id;
  v_tax := round(v_subtotal * v_tax_rate);

  update orders
    set subtotal = v_subtotal,
        tax = v_tax,
        total = v_subtotal + v_tax,
        status = case when orders.status in ('preparing', 'ready') then 'open' else orders.status end
    where orders.id = p_order_id;

  return query select orders.id, orders.subtotal, orders.tax, orders.total, orders.status
    from orders where orders.id = p_order_id;
end;
$$;
grant execute on function add_items_to_order to anon;
