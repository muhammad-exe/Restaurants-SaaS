-- ============================================================
-- Migration: real hashed passwords instead of 4-digit PINs (v11)
-- ------------------------------------------------------------
-- Replaces plain-text PIN login with properly hashed passwords
-- (bcrypt-style, via Postgres's pgcrypto extension). Existing staff
-- PINs are automatically migrated into hashed passwords, so nobody's
-- login breaks — they can keep using their old 4-digit PIN as their
-- password going forward, or you can give them a real password via
-- the dashboard's Staff panel (Edit → set a new password).
--
-- Run this if you already ran schema.sql before this update. Safe to
-- run more than once.
-- ============================================================

create extension if not exists "pgcrypto";

alter table staff add column if not exists password_hash text;

do $$
begin
  if exists (select 1 from information_schema.columns where table_name = 'staff' and column_name = 'pin') then
    alter table staff alter column pin drop not null;
  end if;
end $$;

-- Migrate any existing plain-text PINs into hashed passwords, once.
-- (No-op on a fresh install where the old "pin" column never existed.)
do $$
begin
  if exists (select 1 from information_schema.columns where table_name = 'staff' and column_name = 'pin') then
    update staff
    set password_hash = crypt(pin, gen_salt('bf'))
    where password_hash is null and pin is not null;
  end if;
end $$;

drop function if exists check_staff_pin(uuid, text, text[]);
create or replace function check_staff_password(p_restaurant_id uuid, p_password text, p_allowed_roles text[])
returns table (id uuid, name text, role text)
language plpgsql security definer as $$
begin
  return query
    select s.id, s.name, s.role
    from staff s
    where s.restaurant_id = p_restaurant_id
      and s.role = any(p_allowed_roles)
      and crypt(p_password, s.password_hash) = s.password_hash
    limit 1;
end;
$$;

drop function if exists add_staff(uuid, text, text, text);
create or replace function add_staff(p_restaurant_id uuid, p_name text, p_password text, p_role text)
returns table (id uuid, name text, role text)
language plpgsql security definer as $$
declare
  v_existing boolean;
begin
  if length(p_password) < 6 then
    raise exception 'Password must be at least 6 characters';
  end if;
  if p_role not in ('owner', 'manager', 'cashier', 'waiter') then
    raise exception 'Invalid role';
  end if;

  select exists(
    select 1 from staff s
    where s.restaurant_id = p_restaurant_id and crypt(p_password, s.password_hash) = s.password_hash
  ) into v_existing;
  if v_existing then
    raise exception 'That password is already in use — pick a different one';
  end if;

  return query
    insert into staff (restaurant_id, name, password_hash, role)
    values (p_restaurant_id, p_name, crypt(p_password, gen_salt('bf')), p_role)
    returning staff.id, staff.name, staff.role;
end;
$$;

drop function if exists update_staff(uuid, text, text, text);
create or replace function update_staff(p_staff_id uuid, p_name text, p_password text, p_role text)
returns table (id uuid, name text, role text)
language plpgsql security definer as $$
declare
  v_existing boolean;
  v_restaurant_id uuid;
begin
  if length(p_password) < 6 then
    raise exception 'Password must be at least 6 characters';
  end if;
  if p_role not in ('owner', 'manager', 'cashier', 'waiter') then
    raise exception 'Invalid role';
  end if;

  select restaurant_id into v_restaurant_id from staff where staff.id = p_staff_id;

  select exists(
    select 1 from staff s
    where s.restaurant_id = v_restaurant_id and s.id != p_staff_id
      and crypt(p_password, s.password_hash) = s.password_hash
  ) into v_existing;
  if v_existing then
    raise exception 'That password is already in use by someone else — pick a different one';
  end if;

  return query
    update staff
    set name = p_name, password_hash = crypt(p_password, gen_salt('bf')), role = p_role
    where staff.id = p_staff_id
    returning staff.id, staff.name, staff.role;
end;
$$;

grant execute on function check_staff_password to anon;
grant execute on function add_staff to anon;
grant execute on function update_staff to anon;
