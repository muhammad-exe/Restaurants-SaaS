-- ============================================================
-- Migration: call-waiter ring bell + order resume on rescan (v10)
-- ------------------------------------------------------------
-- Adds the table_calls table (customer "call waiter" button, with
-- staff acknowledgment and an urgent/owner-escalation threshold),
-- and a function so a customer who rescans their table's QR code
-- while an order is still in progress gets the live tracker back
-- instead of a fresh menu. Run this if you already ran schema.sql
-- before this update. Safe to run more than once.
-- ============================================================

create table if not exists table_calls (
  id uuid primary key default uuid_generate_v4(),
  restaurant_id uuid references restaurants(id) on delete cascade,
  table_id uuid references restaurant_tables(id) on delete cascade,
  created_at timestamptz default now(),
  acknowledged boolean default false,
  acknowledged_by uuid references staff(id) on delete set null
);

alter table table_calls enable row level security;

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
