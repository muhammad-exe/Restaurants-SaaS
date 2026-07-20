-- ============================================================
-- Migration: order status function for the customer tracker (v4)
-- ------------------------------------------------------------
-- Run this if you already ran schema.sql before this update.
-- Safe to run more than once.
-- ============================================================

drop function if exists get_order_status(uuid);

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

grant execute on function get_order_status to anon;
