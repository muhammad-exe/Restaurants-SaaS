-- ============================================================
-- Migration: complete staff CRUD with edit support (v8)
-- ------------------------------------------------------------
-- Adds update_staff() so the dashboard's Staff panel can edit an
-- existing staff member's name/PIN/role, not just add and remove.
-- Run this if you already ran schema.sql before this update. Safe to
-- run more than once.
-- ============================================================

create or replace function update_staff(p_staff_id uuid, p_name text, p_pin text, p_role text)
returns table (id uuid, name text, role text)
language plpgsql security definer as $$
declare
  v_existing int;
  v_restaurant_id uuid;
begin
  if p_pin !~ '^[0-9]{4}$' then
    raise exception 'PIN must be exactly 4 digits';
  end if;
  if p_role not in ('owner', 'manager', 'cashier', 'waiter') then
    raise exception 'Invalid role';
  end if;

  select restaurant_id into v_restaurant_id from staff where staff.id = p_staff_id;

  select count(*) into v_existing
    from staff s
    where s.restaurant_id = v_restaurant_id and s.pin = p_pin and s.id != p_staff_id;
  if v_existing > 0 then
    raise exception 'That PIN is already in use by someone else — pick a different one';
  end if;

  return query
    update staff
    set name = p_name, pin = p_pin, role = p_role
    where staff.id = p_staff_id
    returning staff.id, staff.name, staff.role;
end;
$$;

grant execute on function update_staff to anon;
