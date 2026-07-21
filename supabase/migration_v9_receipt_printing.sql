-- ============================================================
-- Migration: receipt printing support (v9)
-- ------------------------------------------------------------
-- Expands get_open_orders() to include per-item price and the
-- subtotal/tax breakdown, needed so a real itemized receipt can be
-- printed when a QR order is closed at the counter (previously it
-- only had item names/quantities and a single total, not enough to
-- print a proper receipt). Run this if you already ran schema.sql
-- before this update. Safe to run more than once.
-- ============================================================

drop function if exists get_open_orders(uuid);

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

grant execute on function get_open_orders to anon;
