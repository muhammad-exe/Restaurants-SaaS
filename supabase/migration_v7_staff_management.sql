-- ============================================================
-- Migration: staff management screen support (v7)
-- ------------------------------------------------------------
-- Adds the functions powering the new "Staff" panel on the owner
-- dashboard — add, remove, and list staff without touching Supabase's
-- Table Editor directly. Run this if you already ran schema.sql
-- before this update. Safe to run more than once.
-- ============================================================

-- ---------- Staff management (add/remove/list) ----------
-- Never returns pin — only id/name/role. The dashboard PIN gate is the
-- access control here (only owner/manager PINs reach this screen at
-- the app level); these functions themselves don't re-check role,
-- consistent with how the rest of the dashboard's read functions work.

create or replace function list_staff(p_restaurant_id uuid)
returns table (id uuid, name text, role text, created_at timestamptz)
language plpgsql security definer as $$
begin
  return query
    select s.id, s.name, s.role, s.created_at
    from staff s
    where s.restaurant_id = p_restaurant_id
    order by s.created_at asc;
end;
$$;

create or replace function add_staff(p_restaurant_id uuid, p_name text, p_pin text, p_role text)
returns table (id uuid, name text, role text)
language plpgsql security definer as $$
declare
  v_existing int;
begin
  if p_pin !~ '^[0-9]{4}$' then
    raise exception 'PIN must be exactly 4 digits';
  end if;
  if p_role not in ('owner', 'manager', 'cashier', 'waiter') then
    raise exception 'Invalid role';
  end if;

  select count(*) into v_existing from staff s where s.restaurant_id = p_restaurant_id and s.pin = p_pin;
  if v_existing > 0 then
    raise exception 'That PIN is already in use — pick a different one';
  end if;

  return query
    insert into staff (restaurant_id, name, pin, role)
    values (p_restaurant_id, p_name, p_pin, p_role)
    returning staff.id, staff.name, staff.role;
end;
$$;

create or replace function remove_staff(p_staff_id uuid)
returns void
language plpgsql security definer as $$
begin
  update orders set staff_id = null where staff_id = p_staff_id;
  delete from staff where id = p_staff_id;
end;
$$;

grant execute on function list_staff to anon;
grant execute on function add_staff to anon;
grant execute on function remove_staff to anon;
