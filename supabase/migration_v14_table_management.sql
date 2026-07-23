-- ============================================================
-- Migration: owner table management (v14)
-- ------------------------------------------------------------
-- Adds list_tables(), add_table(), and remove_table() — powers the
-- new "Tables" panel on the owner dashboard, so adding a table (and
-- getting it a real, unique QR code automatically) no longer needs
-- Supabase's Table Editor at all.
-- Run this if you already ran schema.sql before this update. Safe to
-- run more than once.
-- ============================================================

create or replace function list_tables(p_restaurant_id uuid)
returns table (id uuid, label text, qr_token text)
language plpgsql security definer as $$
begin
  return query
    select t.id, t.label, t.qr_token
    from restaurant_tables t
    where t.restaurant_id = p_restaurant_id
    order by t.label asc;
end;
$$;
grant execute on function list_tables to anon;

create or replace function add_table(p_restaurant_id uuid, p_label text)
returns table (id uuid, label text, qr_token text)
language plpgsql security definer as $$
declare
  v_token text;
begin
  v_token := lower(regexp_replace(p_restaurant_id::text, '-.*', '')) || '-' || replace(gen_random_uuid()::text, '-', '');
  v_token := substr(v_token, 1, 20);

  return query
    insert into restaurant_tables (restaurant_id, label, qr_token)
    values (p_restaurant_id, p_label, v_token)
    returning restaurant_tables.id, restaurant_tables.label, restaurant_tables.qr_token;
end;
$$;
grant execute on function add_table to anon;

create or replace function remove_table(p_table_id uuid)
returns void
language plpgsql security definer as $$
begin
  update orders set table_id = null where table_id = p_table_id;
  delete from restaurant_tables where id = p_table_id;
end;
$$;
grant execute on function remove_table to anon;
